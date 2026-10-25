import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
import 'package:basic_utils/basic_utils.dart';
import 'package:crypto/crypto.dart';
import 'models.dart';

class DeviceIdentity {
  final String privateKey, publicKey, certificate;
  const DeviceIdentity(this.privateKey, this.publicKey, this.certificate);
  String get fingerprint => sha256.convert(der(certificate)).toString();
  String get publicFingerprint =>
      sha256.convert(utf8.encode(publicKey)).toString();
  String encode() => jsonEncode({
    'key': privateKey,
    'public': publicKey,
    'certificate': certificate,
  });
  factory DeviceIdentity.decode(String value) {
    final j = jsonDecode(value) as Map;
    return DeviceIdentity(
      j['key'] as String,
      j['public'] as String,
      j['certificate'] as String,
    );
  }
  static Uint8List der(String pem) => base64Decode(
    pem
        .split('\n')
        .where((s) => !s.startsWith('-----'))
        .join()
        .replaceAll(RegExp(r'\s'), ''),
  );
  static Future<DeviceIdentity> generate() => Isolate.run(() {
    final pair = CryptoUtils.generateRSAKeyPair(keySize: 2048);
    final private = pair.privateKey as RSAPrivateKey;
    final public = pair.publicKey as RSAPublicKey;
    final csr = X509Utils.generateRsaCsrPem(
      {'CN': 'FlowShare device'},
      private,
      public,
    );
    final cert = X509Utils.generateSelfSignedCertificate(private, csr, 3650);
    return DeviceIdentity(
      CryptoUtils.encodeRSAPrivateKeyToPem(private),
      CryptoUtils.encodeRSAPublicKeyToPem(public),
      cert,
    );
  });
  SecurityContext get serverContext => SecurityContext(withTrustedRoots: false)
    ..minimumTlsProtocolVersion = TlsProtocolVersion.tls1_2
    ..useCertificateChainBytes(utf8.encode(certificate))
    ..usePrivateKeyBytes(utf8.encode(privateKey));
  String sign(String message) {
    final signer = Signer('SHA-256/RSA')
      ..init(
        true,
        PrivateKeyParameter<RSAPrivateKey>(
          CryptoUtils.rsaPrivateKeyFromPem(privateKey),
        ),
      );
    return base64Encode(
      (signer.generateSignature(Uint8List.fromList(utf8.encode(message)))
              as RSASignature)
          .bytes,
    );
  }

  static bool verify(String publicKey, String message, String signature) {
    try {
      if (publicKey.length > 1024 || signature.length > 1024) return false;
      final key = CryptoUtils.rsaPublicKeyFromPem(publicKey);
      if (key.modulus!.bitLength != 2048 || key.exponent != BigInt.from(65537))
        return false;
      final verifier = Signer('SHA-256/RSA')
        ..init(false, PublicKeyParameter<RSAPublicKey>(key));
      return verifier.verifySignature(
        Uint8List.fromList(utf8.encode(message)),
        RSASignature(base64Decode(signature)),
      );
    } catch (_) {
      return false;
    }
  }
}

String authenticationTranscript(
  String nonce,
  String receiver,
  String sender,
  Manifest manifest,
  String name,
) => jsonEncode([
  'FlowShare/v1/auth',
  nonce,
  receiver,
  sender,
  manifest.digest,
  name,
]);

/// 128 bits avoids reducing human verification to a short brute-forceable code.
String verificationCode(String transcript) {
  final digest = sha256
      .convert(utf8.encode(transcript))
      .toString()
      .substring(0, 32)
      .toUpperCase();
  return List.generate(
    4,
    (i) => digest.substring(i * 8, (i + 1) * 8),
  ).join(' ');
}
