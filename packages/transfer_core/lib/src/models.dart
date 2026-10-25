import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

const protocolVersion = 1;
const chunkSize = 1024 * 1024;
const maxFiles = 128;
const maxTotalBytes = 1024 * 1024 * 1024 * 1024;

class FlowException implements Exception {
  final String code;
  const FlowException(this.code);
  @override
  String toString() => code;
}

String randomId([int bytes = 24]) => base64UrlEncode(
  List.generate(bytes, (_) => Random.secure().nextInt(256)),
).replaceAll('=', '');

String checkedText(Object? value, int max, {String code = 'invalidMetadata'}) {
  if (value is! String ||
      value.isEmpty ||
      value.length > max ||
      RegExp(r'[\x00-\x1f\x7f\u202a-\u202e\u2066-\u2069]').hasMatch(value)) {
    throw FlowException(code);
  }
  return value;
}

String safeFilename(Object? value) {
  final name = checkedText(value, 180, code: 'unsafeFilename');
  final stem = name.split('.').first.toUpperCase();
  if (name == '.' ||
      name == '..' ||
      RegExp(r'[/\\<>:"|?*]').hasMatch(name) ||
      name.endsWith('.') ||
      name.endsWith(' ') ||
      RegExp(r'^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])$').hasMatch(stem)) {
    throw const FlowException('unsafeFilename');
  }
  return name;
}

String checkedHash(Object? value) {
  if (value is! String || !RegExp(r'^[a-f0-9]{64}$').hasMatch(value)) {
    throw const FlowException('invalidMetadata');
  }
  return value;
}

bool isLocalAddress(InternetAddress address) {
  final b = address.rawAddress;
  if (address.type == InternetAddressType.IPv4) {
    if (address.address == '169.254.169.254') return false;
    return b[0] == 10 ||
        b[0] == 127 ||
        (b[0] == 172 && b[1] >= 16 && b[1] <= 31) ||
        (b[0] == 192 && b[1] == 168) ||
        (b[0] == 169 && b[1] == 254);
  }
  return address.isLoopback ||
      (b[0] & 0xfe) == 0xfc ||
      (b[0] == 0xfe && (b[1] & 0xc0) == 0x80);
}

Future<String> fileHash(File file) async =>
    (await sha256.bind(file.openRead()).first).toString();

class FileMeta {
  final String name;
  final int size;
  final String hash;
  const FileMeta(this.name, this.size, this.hash);
  Map<String, Object> toJson() => {'name': name, 'size': size, 'sha256': hash};
  factory FileMeta.fromJson(Map<String, dynamic> json) {
    final size = json['size'];
    if (size is! int || size < 0 || size > maxTotalBytes)
      throw const FlowException('invalidMetadata');
    return FileMeta(
      safeFilename(json['name']),
      size,
      checkedHash(json['sha256']),
    );
  }
}

class Manifest {
  final String id;
  final List<FileMeta> files;
  Manifest(this.id, List<FileMeta> files) : files = List.unmodifiable(files);
  int get total => files.fold(0, (n, f) => n + f.size);
  Map<String, Object> toJson() => {
    'id': id,
    'files': files.map((e) => e.toJson()).toList(),
  };
  String get digest =>
      sha256.convert(utf8.encode(jsonEncode(toJson()))).toString();
  factory Manifest.fromJson(Map<String, dynamic> json) {
    final id = checkedText(json['id'], 32);
    if (!RegExp(r'^[A-Za-z0-9_-]{32}$').hasMatch(id))
      throw const FlowException('invalidMetadata');
    final entries = json['files'];
    if (entries is! List || entries.isEmpty || entries.length > maxFiles)
      throw const FlowException('invalidMetadata');
    final m = Manifest(
      id,
      entries
          .map((e) => FileMeta.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList(),
    );
    if (m.total > maxTotalBytes) throw const FlowException('invalidMetadata');
    return m;
  }
  static Future<Manifest> fromPaths(List<String> paths) async {
    if (paths.isEmpty || paths.length > maxFiles)
      throw const FlowException('tooManyFiles');
    final files = <FileMeta>[];
    for (final path in paths) {
      final file = File(path);
      final before = await file.stat();
      if (before.type != FileSystemEntityType.file)
        throw const FlowException('fileUnavailable');
      final hash = await fileHash(file);
      final after = await file.stat();
      if (before.size != after.size || before.modified != after.modified)
        throw const FlowException('fileChanged');
      files.add(FileMeta(safeFilename(p.basename(path)), before.size, hash));
    }
    final result = Manifest(randomId(), files);
    if (result.total > maxTotalBytes)
      throw const FlowException('invalidMetadata');
    return result;
  }
}

class Invitation {
  final String host, fingerprint, name, platform;
  final int port;
  const Invitation({
    required this.host,
    required this.port,
    required this.fingerprint,
    required this.name,
    required this.platform,
  });
  String encode() =>
      'flowshare://pair/${base64UrlEncode(utf8.encode(jsonEncode({'v': protocolVersion, 'host': host, 'port': port, 'fp': fingerprint, 'name': name, 'platform': platform})))}';
  factory Invitation.parse(String text) {
    if (text.length > 2048) throw const FlowException('invalidInvitation');
    try {
      final uri = Uri.parse(text.trim());
      if (uri.scheme != 'flowshare' ||
          uri.host != 'pair' ||
          uri.pathSegments.length != 1 ||
          uri.hasQuery ||
          uri.hasFragment)
        throw const FormatException();
      final json =
          jsonDecode(
                utf8.decode(
                  base64Url.decode(
                    base64Url.normalize(uri.pathSegments.single),
                  ),
                ),
              )
              as Map;
      if (json['v'] != protocolVersion)
        throw const FlowException('protocolVersion');
      final address = InternetAddress.tryParse(json['host'] as String);
      if (address == null || !isLocalAddress(address))
        throw const FormatException();
      final port = json['port'];
      if (port is! int || port < 1 || port > 65535)
        throw const FormatException();
      return Invitation(
        host: address.address,
        port: port,
        fingerprint: checkedHash(json['fp']),
        name: checkedText(json['name'], 64),
        platform: checkedText(json['platform'], 32),
      );
    } on FlowException {
      rethrow;
    } catch (_) {
      throw const FlowException('invalidInvitation');
    }
  }
}

enum TransferStatus {
  connecting,
  pairing,
  transferring,
  verifying,
  complete,
  cancelled,
  failed,
}

class TransferProgress {
  final Manifest manifest;
  final String peer, direction;
  final TransferStatus status;
  final int bytes, fileIndex, resumedBytes;
  final Duration elapsed;
  final String? error, destination;
  const TransferProgress({
    required this.manifest,
    required this.peer,
    required this.direction,
    required this.status,
    required this.bytes,
    required this.elapsed,
    this.fileIndex = 0,
    this.resumedBytes = 0,
    this.error,
    this.destination,
  });
  double get fraction => manifest.total == 0
      ? (status == TransferStatus.complete ? 1 : 0)
      : (bytes / manifest.total).clamp(0, 1);
  double get speed => elapsed.inMilliseconds == 0
      ? 0
      : (bytes - resumedBytes).clamp(0, bytes) * 1000 / elapsed.inMilliseconds;
  Duration? get remaining => speed <= 0
      ? null
      : Duration(seconds: ((manifest.total - bytes) / speed).ceil());
  bool get finished => [
    TransferStatus.complete,
    TransferStatus.cancelled,
    TransferStatus.failed,
  ].contains(status);
}

class TransferControl {
  bool cancelled = false;
  void Function()? onCancel;
  void cancel() {
    cancelled = true;
    onCancel?.call();
  }

  void check() {
    if (cancelled) throw const FlowException('cancelled');
  }
}

class PairingRequest {
  final String peer, fingerprint, code, direction;
  final Manifest manifest;
  const PairingRequest(
    this.peer,
    this.fingerprint,
    this.code,
    this.direction,
    this.manifest,
  );
}
