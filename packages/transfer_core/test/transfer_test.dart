import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flowshare_core/flowshare_core.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late DeviceIdentity senderIdentity, receiverIdentity;
  late Directory temp;
  late TransferEngine sender, receiver;
  late Invitation invitation;
  late List<TransferProgress> received, sent;
  late List<PairingRequest> approvals;
  var allow = true;
  var capacity = 1 << 50;
  setUpAll(() async {
    senderIdentity = await DeviceIdentity.generate();
    receiverIdentity = await DeviceIdentity.generate();
  });
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('flowshare-test-');
    received = [];
    sent = [];
    approvals = [];
    allow = true;
    capacity = 1 << 50;
    Future<bool> approve(PairingRequest r) async {
      approvals.add(r);
      return allow;
    }

    sender = TransferEngine(
      identity: senderIdentity,
      name: 'Sender',
      receiveRoot: Directory(p.join(temp.path, 'sender')),
      approve: approve,
      onProgress: sent.add,
      freeBytes: () async => capacity,
    );
    receiver = TransferEngine(
      identity: receiverIdentity,
      name: 'Receiver',
      receiveRoot: Directory(p.join(temp.path, 'received')),
      approve: approve,
      onProgress: received.add,
      freeBytes: () async => capacity,
    );
    final port = await receiver.start(
      bindAddress: InternetAddress.loopbackIPv4,
    );
    invitation = Invitation(
      host: '127.0.0.1',
      port: port,
      fingerprint: receiverIdentity.fingerprint,
      name: 'Receiver',
      platform: 'test',
    );
  });
  tearDown(() async {
    await sender.stop();
    await receiver.stop();
    await Future<void>.delayed(const Duration(milliseconds: 80));
    await temp.delete(recursive: true);
  });

  Future<List<String>> files(List<int> sizes) async {
    final source = await Directory(p.join(temp.path, 'source')).create();
    final paths = <String>[];
    for (var i = 0; i < sizes.length; i++) {
      final f = File(p.join(source.path, 'বাংলা-$i.bin'));
      final output = await f.open(mode: FileMode.write);
      final block = Uint8List.fromList(
        List.generate(chunkSize, (j) => (j + i) % 251),
      );
      var size = sizes[i];
      while (size > 0) {
        final count = size.clamp(0, block.length);
        await output.writeFrom(block, 0, count);
        size -= count;
      }
      await output.close();
      paths.add(f.path);
    }
    return paths;
  }

  test(
    'real TLS: empty, Unicode 1 KiB, 1 MiB files; both approvals and matching bytes',
    () async {
      final paths = await files([0, 1024, 1024 * 1024]);
      final m = await Manifest.fromPaths(paths);
      await sender.send(invitation, m, paths);
      expect(sent.last.status, TransferStatus.complete);
      expect(received.last.status, TransferStatus.complete);
      expect(approvals.length, 2);
      expect(approvals[0].code, approvals[1].code);
      expect(approvals[0].code.replaceAll(' ', '').length, 32);
      for (var i = 0; i < paths.length; i++) {
        final dest = File(
          p.join(received.last.destination!, '$i-${m.files[i].name}'),
        );
        expect(await fileHash(dest), await fileHash(File(paths[i])));
        expect(await dest.readAsBytes(), await File(paths[i]).readAsBytes());
      }
    },
  );
  test('receiver rejection writes no payload', () async {
    final paths = await files([1024]);
    final m = await Manifest.fromPaths(paths);
    allow = false;
    await expectLater(
      sender.send(invitation, m, paths),
      throwsA(isA<FlowException>()),
    );
    expect(await Directory(p.join(temp.path, 'received')).exists(), false);
  });
  test('wrong certificate pin fails before an offer', () async {
    final paths = await files([1024]);
    final m = await Manifest.fromPaths(paths);
    final bad = Invitation(
      host: invitation.host,
      port: invitation.port,
      fingerprint: '0' * 64,
      name: 'Bad',
      platform: 'test',
    );
    await expectLater(
      sender.send(bad, m, paths),
      throwsA(isA<FlowException>()),
    );
    expect(approvals, isEmpty);
  });
  test('insufficient disk space prevents payload', () async {
    final paths = await files([1024]);
    final m = await Manifest.fromPaths(paths);
    capacity = 0;
    await expectLater(
      sender.send(invitation, m, paths),
      throwsA(
        predicate((e) => e is FlowException && e.code == 'insufficientStorage'),
      ),
    );
    expect(received.last.bytes, 0);
  });
  test('changed source rejected before reconnect', () async {
    final paths = await files([1024]);
    final m = await Manifest.fromPaths(paths);
    await File(paths.single).writeAsString('changed');
    await expectLater(
      sender.send(invitation, m, paths),
      throwsA(predicate((e) => e is FlowException && e.code == 'fileChanged')),
    );
    expect(approvals, isEmpty);
  });
  test('cancel then retry reuses only fully verified files', () async {
    final paths = await files([1024, 3 * chunkSize]);
    final m = await Manifest.fromPaths(paths);
    final control = TransferControl();
    final interrupted = TransferEngine(
      identity: senderIdentity,
      name: 'Sender',
      receiveRoot: temp,
      approve: (r) async => true,
      onProgress: (r) {
        if (r.bytes >= 1024 + chunkSize && !control.cancelled) control.cancel();
      },
      freeBytes: () async => capacity,
    );
    await expectLater(
      interrupted.send(invitation, m, paths, control: control),
      throwsA(isA<FlowException>()),
    );
    await Future<void>.delayed(const Duration(milliseconds: 200));
    await sender.send(invitation, m, paths);
    expect(sent.last.status, TransferStatus.complete);
    expect(
      await fileHash(
        File(p.join(received.last.destination!, '1-${m.files[1].name}')),
      ),
      m.files[1].hash,
    );
    expect(
      await Directory(
        received.last.destination!,
      ).list().where((f) => f.path.endsWith('.part')).isEmpty,
      true,
    );
  });
  test(
    'file mutation after preflight fails checksum without a committed file',
    () async {
      final paths = await files([1024]);
      final m = await Manifest.fromPaths(paths);
      final mutator = TransferEngine(
        identity: senderIdentity,
        name: 'Sender',
        receiveRoot: temp,
        approve: (r) async {
          await File(paths.single).writeAsBytes(List.filled(1024, 42));
          return true;
        },
        onProgress: sent.add,
        freeBytes: () async => capacity,
      );
      await expectLater(
        mutator.send(invitation, m, paths),
        throwsA(
          predicate((e) => e is FlowException && e.code == 'checksumMismatch'),
        ),
      );
      expect(
        await File(
          p.join(temp.path, 'received', m.id, '0-${m.files.single.name}'),
        ).exists(),
        false,
      );
    },
  );
  test(
    'signature does not authorize changed transcript or another identity',
    () {
      final signature = senderIdentity.sign('bound transcript');
      expect(
        DeviceIdentity.verify(
          senderIdentity.publicKey,
          'bound transcript',
          signature,
        ),
        true,
      );
      expect(
        DeviceIdentity.verify(
          senderIdentity.publicKey,
          'changed transcript',
          signature,
        ),
        false,
      );
      expect(
        DeviceIdentity.verify(
          receiverIdentity.publicKey,
          'bound transcript',
          signature,
        ),
        false,
      );
    },
  );
  test(
    'symlink destination is rejected',
    () async {
      final paths = await files([1024]);
      final m = await Manifest.fromPaths(paths);
      final root = await Directory(p.join(temp.path, 'received')).create();
      final outside = await Directory(p.join(temp.path, 'outside')).create();
      await Link(p.join(root.path, m.id)).create(outside.path);
      await expectLater(
        sender.send(invitation, m, paths),
        throwsA(
          predicate((e) => e is FlowException && e.code == 'unsafeDestination'),
        ),
      );
      expect(await outside.list().isEmpty, true);
    },
    skip: Platform.isWindows ? 'Host test requires symlink privileges' : false,
  );
  test(
    'oversized untrusted frame is rejected before body allocation',
    () async {
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final remote = Socket.connect('127.0.0.1', server.port);
      final local = await server.first;
      final peer = await remote;
      final header = Uint8List(5);
      ByteData.sublistView(header).setUint32(0, 0x7fffffff);
      header[4] = 1;
      peer.add(header);
      await peer.flush();
      final stream = FramedConnection(local);
      await expectLater(stream.readJson(), throwsA(isA<FlowException>()));
      stream.close();
      peer.destroy();
      await server.close();
    },
  );
  test(
    'portable safe names reject traversal, reserved devices, controls and bidi',
    () {
      for (final name in [
        '../oops',
        'a/b',
        'a\\b',
        'NUL.txt',
        'COM1',
        'x.',
        'x ',
        '\u202Etxt.exe',
        'a\u0000b',
      ]) {
        expect(
          () => safeFilename(name),
          throwsA(isA<FlowException>()),
          reason: name,
        );
      }
      expect(safeFilename('ছবি ১.jpg'), 'ছবি ১.jpg');
    },
  );
  test('local address and invitation validation', () {
    expect(
      Invitation.parse(invitation.encode()).fingerprint,
      receiverIdentity.fingerprint,
    );
    for (final ip in [
      '8.8.8.8',
      '169.254.169.254',
      '224.0.0.1',
      '0.0.0.0',
      '::ffff:8.8.8.8',
    ]) {
      expect(isLocalAddress(InternetAddress(ip)), false);
    }
    for (final text in [
      'https://example.com',
      'flowshare://pair/!!',
      'x' * 2049,
    ]) {
      expect(() => Invitation.parse(text), throwsA(isA<FlowException>()));
    }
  });
  test(
    'manifest bounds reject count, negative sizes and invalid checksums',
    () {
      expect(
        () => Manifest.fromJson({'id': randomId(), 'files': []}),
        throwsA(isA<FlowException>()),
      );
      expect(
        () => FileMeta.fromJson({'name': 'ok', 'size': -1, 'sha256': '0' * 64}),
        throwsA(isA<FlowException>()),
      );
      expect(
        () => FileMeta.fromJson({'name': 'ok', 'size': 1, 'sha256': 'bad'}),
        throwsA(isA<FlowException>()),
      );
      expect(
        () => Manifest.fromJson({
          'id': randomId(),
          'files': List.generate(
            129,
            (_) => {'name': 'ok', 'size': 0, 'sha256': '0' * 64},
          ),
        }),
        throwsA(isA<FlowException>()),
      );
    },
  );
  for (final size in [
    100 * 1024 * 1024,
    if (Platform.environment['FLOWSHARE_LARGE_TESTS'] == '1') ...[
      1024 * 1024 * 1024,
      5 * 1024 * 1024 * 1024,
    ],
  ]) {
    test('streaming benchmark $size bytes', () async {
      final paths = await files([size]);
      final m = await Manifest.fromPaths(paths);
      final before = ProcessInfo.currentRss;
      var peak = before;
      final monitor = Timer.periodic(const Duration(milliseconds: 50), (_) {
        if (ProcessInfo.currentRss > peak) peak = ProcessInfo.currentRss;
      });
      final watch = Stopwatch()..start();
      try {
        await sender.send(invitation, m, paths);
        expect(sent.last.status, TransferStatus.complete);
        expect(
          await fileHash(
            File(
              p.join(received.last.destination!, '0-${m.files.single.name}'),
            ),
          ),
          m.files.single.hash,
        );
      } finally {
        monitor.cancel();
      }
      print(
        jsonEncode({
          'bytes': size,
          'elapsedMs': watch.elapsedMilliseconds,
          'baselineRss': before,
          'peakRss': peak,
          'scope': 'Linux loopback, not physical P2P',
        }),
      );
    }, timeout: const Timeout(Duration(minutes: 20)));
  }
}
