import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'framing.dart';
import 'identity.dart';
import 'models.dart';

typedef Approval = Future<bool> Function(PairingRequest request);
typedef ProgressCallback = void Function(TransferProgress progress);

class TransferEngine {
  final DeviceIdentity identity;
  final String name;
  final Directory receiveRoot;
  final Approval approve;
  final ProgressCallback onProgress;
  final Future<int> Function() freeBytes;
  ServerSocket? _server;
  TransferControl? _incoming;
  final List<DateTime> _attempts = [];
  TransferEngine({
    required this.identity,
    required this.name,
    required this.receiveRoot,
    required this.approve,
    required this.onProgress,
    required this.freeBytes,
  });
  int? get port => _server?.port;
  bool get receiving => _server != null;

  Future<int> start({InternetAddress? bindAddress}) async {
    if (_server != null) return _server!.port;
    _server = await ServerSocket.bind(
      bindAddress ?? InternetAddress.anyIPv4,
      0,
      backlog: 4,
    );
    _server!.listen((raw) async {
      final now = DateTime.now();
      _attempts.removeWhere(
        (t) => now.difference(t) > const Duration(minutes: 1),
      );
      if (_incoming != null ||
          _attempts.length >= 5 ||
          !isLocalAddress(raw.remoteAddress)) {
        raw.destroy();
        return;
      }
      _attempts.add(now);
      final control = TransferControl();
      _incoming = control;
      control.onCancel = raw.destroy;
      try {
        final secure = await SecureSocket.secureServer(
          raw,
          identity.serverContext,
        ).timeout(const Duration(seconds: 15));
        control.check();
        await _receive(secure, control);
      } catch (_) {
        raw.destroy();
      } finally {
        _incoming = null;
      }
    }, onError: (Object error) {});
    return _server!.port;
  }

  void cancelIncoming() => _incoming?.cancel();
  Future<void> stop() async {
    _incoming?.cancel();
    await _server?.close();
    _server = null;
  }

  Future<void> send(
    Invitation invitation,
    Manifest manifest,
    List<String> paths, {
    TransferControl? control,
  }) async {
    final c = control ?? TransferControl();
    final timer = Stopwatch()..start();
    FramedConnection? connection;
    var bytes = 0, index = 0, resumedBytes = 0;
    void progress(TransferStatus status, {String? error}) => onProgress(
      TransferProgress(
        manifest: manifest,
        peer: invitation.name,
        direction: 'sent',
        status: status,
        bytes: bytes,
        resumedBytes: resumedBytes,
        elapsed: timer.elapsed,
        fileIndex: index,
        error: error,
      ),
    );
    try {
      // Apply the same validation to programmatically constructed invitations.
      Invitation.parse(invitation.encode());
      Manifest.fromJson(manifest.toJson());
      if (paths.length != manifest.files.length)
        throw const FlowException('invalidMetadata');
      progress(TransferStatus.connecting);
      for (var i = 0; i < paths.length; i++) {
        c.check();
        if (await File(paths[i]).length() != manifest.files[i].size ||
            await fileHash(File(paths[i])) != manifest.files[i].hash)
          throw const FlowException('fileChanged');
      }
      final socket = await SecureSocket.connect(
        InternetAddress(invitation.host),
        invitation.port,
        context: SecurityContext(withTrustedRoots: false)
          ..minimumTlsProtocolVersion = TlsProtocolVersion.tls1_2,
        timeout: const Duration(seconds: 15),
        onBadCertificate: (cert) =>
            sha256.convert(cert.der).toString() == invitation.fingerprint,
      );
      final cert = socket.peerCertificate;
      if (cert == null ||
          sha256.convert(cert.der).toString() != invitation.fingerprint ||
          DateTime.now().isAfter(cert.endValidity) ||
          DateTime.now().isBefore(cert.startValidity)) {
        socket.destroy();
        throw const FlowException('authenticationFailed');
      }
      connection = FramedConnection(socket);
      c.onCancel = connection.close;
      c.check();
      final challenge = await connection.readJson();
      if (challenge['type'] != 'challenge' || challenge['v'] != protocolVersion)
        throw const FlowException('protocolVersion');
      final nonce = checkedText(challenge['nonce'], 64);
      if (!RegExp(r'^[A-Za-z0-9_-]{32}$').hasMatch(nonce))
        throw const FlowException('authenticationFailed');
      final transcript = authenticationTranscript(
        nonce,
        invitation.fingerprint,
        identity.publicFingerprint,
        manifest,
        name,
      );
      await connection.sendJson({
        'type': 'offer',
        'v': protocolVersion,
        'name': name,
        'publicKey': identity.publicKey,
        'manifest': manifest.toJson(),
        'signature': identity.sign(transcript),
      });
      progress(TransferStatus.pairing);
      if (!await approve(
        PairingRequest(
          invitation.name,
          invitation.fingerprint,
          verificationCode(transcript),
          'sent',
          manifest,
        ),
      ).timeout(const Duration(seconds: 55)))
        throw const FlowException('rejected');
      c.check();
      await connection.sendJson({'type': 'confirmed'});
      final ready = await connection.readJson();
      if (ready['type'] != 'ready' || ready['completed'] is! List)
        throw const FlowException('invalidFrame');
      final completed = (ready['completed'] as List).toSet();
      if (completed.any(
        (i) => i is! int || i < 0 || i >= manifest.files.length,
      ))
        throw const FlowException('invalidFrame');
      for (final i in completed) {
        bytes += manifest.files[i as int].size;
      }
      resumedBytes = bytes;
      for (index = 0; index < paths.length; index++) {
        if (completed.contains(index)) continue;
        c.check();
        progress(TransferStatus.transferring);
        final input = await File(paths[index]).open();
        try {
          var offset = 0;
          while (offset < manifest.files[index].size) {
            c.check();
            final data = await input.read(
              (manifest.files[index].size - offset).clamp(0, chunkSize),
            );
            if (data.isEmpty) throw const FlowException('fileChanged');
            await connection.sendChunk(index, offset, data);
            final ack = await connection.readJson();
            if (ack['type'] != 'ack' ||
                ack['file'] != index ||
                ack['offset'] != offset + data.length)
              throw const FlowException('invalidFrame');
            offset += data.length;
            bytes += data.length;
            progress(TransferStatus.transferring);
          }
        } finally {
          await input.close();
        }
        await connection.sendJson({'type': 'fileEnd', 'file': index});
        final committed = await connection.readJson();
        if (committed['type'] != 'committed' || committed['file'] != index)
          throw const FlowException('invalidFrame');
      }
      await connection.sendJson({'type': 'finish'});
      final done = await connection.readJson();
      if (done['type'] != 'complete') throw const FlowException('invalidFrame');
      progress(TransferStatus.complete);
    } catch (error) {
      final code = c.cancelled ? 'cancelled' : errorCode(error);
      try {
        await connection?.sendJson({'type': 'error', 'code': code});
      } catch (_) {}
      progress(
        code == 'cancelled' ? TransferStatus.cancelled : TransferStatus.failed,
        error: code,
      );
      throw FlowException(code);
    } finally {
      connection?.close();
      c.onCancel = null;
    }
  }

  Future<void> _receive(SecureSocket socket, TransferControl control) async {
    final connection = FramedConnection(socket);
    control.onCancel = connection.close;
    final timer = Stopwatch()..start();
    Manifest? manifest;
    String peer = '';
    String? destination;
    File? partial;
    var bytes = 0, index = 0, resumedBytes = 0;
    void progress(TransferStatus status, {String? error}) {
      if (manifest != null)
        onProgress(
          TransferProgress(
            manifest: manifest,
            peer: peer,
            direction: 'received',
            status: status,
            bytes: bytes,
            resumedBytes: resumedBytes,
            elapsed: timer.elapsed,
            fileIndex: index,
            error: error,
            destination: destination,
          ),
        );
    }

    try {
      final nonce = randomId();
      await connection.sendJson({
        'type': 'challenge',
        'v': protocolVersion,
        'nonce': nonce,
      });
      final offer = await connection.readJson();
      if (offer['type'] != 'offer' || offer['v'] != protocolVersion)
        throw const FlowException('protocolVersion');
      peer = checkedText(offer['name'], 64);
      final public = offer['publicKey'];
      if (public is! String || public.length > 1024)
        throw const FlowException('authenticationFailed');
      final fingerprint = sha256.convert(utf8.encode(public)).toString();
      manifest = Manifest.fromJson(
        Map<String, dynamic>.from(offer['manifest'] as Map),
      );
      final transcript = authenticationTranscript(
        nonce,
        identity.fingerprint,
        fingerprint,
        manifest,
        peer,
      );
      if (offer['signature'] is! String ||
          !DeviceIdentity.verify(
            public,
            transcript,
            offer['signature'] as String,
          ))
        throw const FlowException('authenticationFailed');
      progress(TransferStatus.pairing);
      if (!await approve(
        PairingRequest(
          peer,
          fingerprint,
          verificationCode(transcript),
          'received',
          manifest,
        ),
      ).timeout(const Duration(seconds: 55)))
        throw const FlowException('rejected');
      control.check();
      if ((await connection.readJson())['type'] != 'confirmed')
        throw const FlowException('rejected');
      final folder = await _safeFolder(manifest.id);
      destination = folder.path;
      final journal = File(p.join(folder.path, '.flowshare.json'));
      final completed = <int>{};
      if (await journal.exists()) {
        if (await FileSystemEntity.type(journal.path, followLinks: false) !=
                FileSystemEntityType.file ||
            await journal.length() > 65536)
          throw const FlowException('unsafeDestination');
        final saved = jsonDecode(await journal.readAsString()) as Map;
        if (saved['sender'] != fingerprint ||
            saved['manifest'] != manifest.digest)
          throw const FlowException('resumeMismatch');
        for (var i = 0; i < manifest.files.length; i++) {
          final file = File(
            p.join(folder.path, '$i-${manifest.files[i].name}'),
          );
          final type = await FileSystemEntity.type(
            file.path,
            followLinks: false,
          );
          if (type == FileSystemEntityType.notFound) continue;
          if (type != FileSystemEntityType.file ||
              await file.length() != manifest.files[i].size ||
              await fileHash(file) != manifest.files[i].hash)
            throw const FlowException('resumeMismatch');
          completed.add(i);
          bytes += manifest.files[i].size;
        }
      } else {
        // A transfer ID cannot overwrite an existing unjournaled destination.
        if (!await folder.list().isEmpty)
          throw const FlowException('unsafeDestination');
      }
      if (await freeBytes() < manifest.total - bytes + 16 * 1024 * 1024)
        throw const FlowException('insufficientStorage');
      await journal.writeAsString(
        jsonEncode({
          'v': 1,
          'sender': fingerprint,
          'manifest': manifest.digest,
        }),
        flush: true,
      );
      resumedBytes = bytes;
      await connection.sendJson({
        'type': 'ready',
        'completed': completed.toList(),
      });
      for (index = 0; index < manifest.files.length; index++) {
        if (completed.contains(index)) continue;
        control.check();
        final meta = manifest.files[index];
        partial = File(p.join(folder.path, '.${randomId()}.part'));
        final output = await partial.open(mode: FileMode.writeOnly);
        var offset = 0;
        try {
          while (offset < meta.size) {
            control.check();
            final frame = await connection.readFrame();
            if (frame[0] != 2 || frame.length <= 13)
              throw const FlowException('invalidFrame');
            final header = ByteData.sublistView(frame);
            final count = frame.length - 13;
            if (header.getUint32(1) != index ||
                header.getUint64(5) != offset ||
                offset + count > meta.size)
              throw const FlowException('invalidFrame');
            await output.writeFrom(frame, 13);
            offset += count;
            bytes += count;
            await connection.sendJson({
              'type': 'ack',
              'file': index,
              'offset': offset,
            });
            progress(TransferStatus.transferring);
          }
          await output.flush();
        } finally {
          await output.close();
        }
        final end = await connection.readJson();
        if (end['type'] != 'fileEnd' || end['file'] != index)
          throw const FlowException('invalidFrame');
        progress(TransferStatus.verifying);
        if (await fileHash(partial) != meta.hash)
          throw const FlowException('checksumMismatch');
        final target = p.join(folder.path, '$index-${meta.name}');
        if (await FileSystemEntity.type(target, followLinks: false) !=
            FileSystemEntityType.notFound)
          throw const FlowException('unsafeDestination');
        control.check();
        await partial.rename(target);
        partial = null;
        await connection.sendJson({'type': 'committed', 'file': index});
      }
      if ((await connection.readJson())['type'] != 'finish')
        throw const FlowException('invalidFrame');
      await connection.sendJson({'type': 'complete'});
      progress(TransferStatus.complete);
    } catch (error) {
      final code = control.cancelled ? 'cancelled' : errorCode(error);
      try {
        await connection.sendJson({'type': 'error', 'code': code});
      } catch (_) {}
      progress(
        code == 'cancelled' ? TransferStatus.cancelled : TransferStatus.failed,
        error: code,
      );
    } finally {
      if (partial != null && await partial.exists()) {
        try {
          await partial.delete();
        } catch (_) {}
      }
      connection.close();
    }
  }

  Future<Directory> _safeFolder(String id) async {
    final rootType = await FileSystemEntity.type(
      receiveRoot.path,
      followLinks: false,
    );
    if (rootType == FileSystemEntityType.notFound)
      await receiveRoot.create(recursive: true);
    if (await FileSystemEntity.type(receiveRoot.path, followLinks: false) !=
        FileSystemEntityType.directory)
      throw const FlowException('unsafeDestination');
    final canonical = await receiveRoot.resolveSymbolicLinks();
    final folder = Directory(p.join(canonical, id));
    final type = await FileSystemEntity.type(folder.path, followLinks: false);
    if (type == FileSystemEntityType.notFound) await folder.create();
    if (await FileSystemEntity.type(folder.path, followLinks: false) !=
            FileSystemEntityType.directory ||
        await folder.resolveSymbolicLinks() != folder.path)
      throw const FlowException('unsafeDestination');
    return folder;
  }
}

String errorCode(Object error) {
  if (error is FlowException) return error.code;
  if (error is TimeoutException) return 'connectionTimeout';
  if (error is HandshakeException) return 'authenticationFailed';
  if (error is SocketException) return 'connectionLost';
  if (error is FileSystemException)
    return error.osError?.errorCode == 28
        ? 'insufficientStorage'
        : 'fileUnavailable';
  return 'invalidFrame';
}
