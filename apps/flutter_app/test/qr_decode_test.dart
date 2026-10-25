import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:flowshare_core/flowshare_core.dart';
import 'package:qr_code_dart_scan/qr_code_dart_scan.dart';
import 'package:qr_flutter/qr_flutter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<String?> decodeRenderedQr(String text) async {
    final folder = await Directory.systemTemp.createTemp('flowshare-qr-');
    final decoder = QRCodeDartScanDecoder(
      formats: const [BarcodeFormat.qrCode],
    );
    try {
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      canvas.drawRect(
        const ui.Rect.fromLTWH(0, 0, 732, 732),
        ui.Paint()..color = const ui.Color(0xffffffff),
      );
      canvas.translate(36, 36);
      QrPainter(
        data: text,
        version: QrVersions.auto,
        gapless: false,
      ).paint(canvas, const ui.Size(660, 660));
      final picture = recorder.endRecording();
      final image = await picture.toImage(732, 732);
      picture.dispose();
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      final file = await File(
        '${folder.path}/pairing.png',
      ).writeAsBytes(bytes!.buffer.asUint8List());
      return (await decoder.decodeFile(XFile(file.path)))?.text;
    } finally {
      decoder.dispose();
      await folder.delete(recursive: true);
    }
  }

  test(
    'local Dart decoder reads a rendered Unicode pairing invitation',
    () async {
      final invitation = Invitation(
        host: '192.168.12.34',
        port: 49321,
        fingerprint: 'a7' * 32,
        name: 'আমার ফোন — FlowShare',
        platform: 'android',
      );
      final decoded = await decodeRenderedQr(invitation.encode());
      expect(decoded, invitation.encode());
      final parsed = Invitation.parse(decoded!);
      expect(parsed.host, invitation.host);
      expect(parsed.port, invitation.port);
      expect(parsed.fingerprint, invitation.fingerprint);
      expect(parsed.name, invitation.name);
    },
  );

  test('a decoded external QR is rejected as a pairing invitation', () async {
    final decoded = await decodeRenderedQr('https://example.invalid/untrusted');
    expect(decoded, 'https://example.invalid/untrusted');
    expect(() => Invitation.parse(decoded!), throwsA(isA<FlowException>()));
  });
}
