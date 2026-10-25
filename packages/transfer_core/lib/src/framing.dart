import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:async/async.dart';
import 'models.dart';

/// A bounded length-prefixed duplex stream. Only one outstanding reader.
class FramedConnection {
  final Socket socket;
  late final StreamQueue<List<int>> _input = StreamQueue(socket);
  List<int> _pending = const [];
  int _offset = 0;
  bool _closed = false;
  FramedConnection(this.socket);
  Future<Uint8List> _read(int length) async {
    final result = Uint8List(length);
    var copied = 0;
    while (copied < length) {
      if (_offset == _pending.length) {
        if (!await _input.hasNext.timeout(const Duration(seconds: 60)))
          throw const FlowException('connectionLost');
        _pending = await _input.next;
        _offset = 0;
      }
      final count = (length - copied).clamp(0, _pending.length - _offset);
      result.setRange(copied, copied + count, _pending, _offset);
      _offset += count;
      copied += count;
    }
    return result;
  }

  Future<Uint8List> readFrame() async {
    final header = await _read(5);
    final len = ByteData.sublistView(header).getUint32(0);
    final kind = header[4];
    if (len < 1 ||
        (kind != 1 && kind != 2) ||
        (kind == 1 && len > 65537) ||
        len > chunkSize + 13)
      throw const FlowException('invalidFrame');
    final result = Uint8List(len);
    result[0] = kind;
    result.setRange(1, len, await _read(len - 1));
    return result;
  }

  Future<Map<String, dynamic>> readJson() async {
    final frame = await readFrame();
    if (frame[0] != 1) throw const FlowException('invalidFrame');
    try {
      final message = jsonDecode(utf8.decode(frame.sublist(1)));
      if (message is! Map<String, dynamic>) throw const FormatException();
      if (message['type'] == 'error')
        throw FlowException(checkedText(message['code'], 64));
      return message;
    } on FlowException {
      rethrow;
    } catch (_) {
      throw const FlowException('invalidFrame');
    }
  }

  Future<void> sendJson(Map<String, Object?> data) =>
      _send(1, utf8.encode(jsonEncode(data)));
  Future<void> sendChunk(int index, int offset, List<int> bytes) async {
    if (bytes.length > chunkSize) throw const FlowException('invalidFrame');
    final payload = Uint8List(12 + bytes.length);
    ByteData.sublistView(payload)
      ..setUint32(0, index)
      ..setUint64(4, offset);
    payload.setRange(12, payload.length, bytes);
    await _send(2, payload);
  }

  Future<void> _send(int kind, List<int> bytes) async {
    if (kind == 1 && bytes.length > 65536)
      throw const FlowException('invalidFrame');
    final header = Uint8List(5);
    ByteData.sublistView(header).setUint32(0, bytes.length + 1);
    header[4] = kind;
    socket.add(header);
    socket.add(bytes);
    await socket.flush();
  }

  void close() {
    if (_closed) return;
    _closed = true;
    socket.destroy();
    _input.cancel(immediate: true);
  }
}
