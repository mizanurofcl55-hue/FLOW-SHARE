# Security and privacy

## Implemented controls

- Exact certificate pinning on the sender, plus explicit post-handshake pin/validity checks. The certificate callback never returns an unconditional `true`.
- Fresh receiver challenge and RSA/SHA-256 proof of the sender identity, bound to receiver pin, sender name and manifest digest.
- 128-bit comparison code on both devices and explicit approvals. A remembered device still requires approval.
- TLS >= 1.2 with no plaintext fallback. The negotiated version depends on platform runtime.
- Bounded manifest, frame, file-count and file-size values; sequential ACK backpressure.
- Filename validation rejects traversal, separators, control/bidi characters, Windows device names, trailing dots/spaces and reserved characters.
- Private transfer-ID directories, indexed destination filenames, checks against symlink destinations and existing targets, temporary files, flush, checksum and rename before success.
- Free-space check before payload, cancellation cleanup, sender-change detection, and rehash of resumed completed files.
- Rate-limited incoming admissions and explicit operation timeouts.
- Private keys kept in the native secure store, never SQLite, diagnostics or committed source. Android app backup is disabled.
- No cloud/backend/analytics, no contacts access, no unrestricted Android storage permission and no always-on location collection. Camera and hotspot permissions are contextual.

## QR dependency privacy

Android/iOS scanning uses `qr_code_dart_scan` 0.14.0 and its local Dart decoder. The camera controller sets `enableAudio: false`; FlowShare does not record audio or upload camera images. `mobile_scanner` was removed because its Android ML Kit dependency collects SDK diagnostics and analytics ([Google disclosure](https://developers.google.com/ml-kit/android-data-disclosure)). The Android build checks its resolved runtime dependencies for ML Kit and Google DataTransport. Desktop pairing uses discovery/manual links. Camera permission and physical scanning still require device validation.

## Threat model and remaining review

Peers, QR/manual links and network advertisements are untrusted. A malicious nearby peer can lie about its name, send malformed frames, send hostile filenames, fill storage up to approved limits, or interrupt sessions. The app does not execute received content and does not scan it for malware. Users choose whether to open it in another application.

The comparison step is essential for first-contact authentication. Code comparison cannot protect users who approve a mismatching code. Private-directory protection assumes the OS account/sandbox is trusted; the Dart check-then-rename sequence is not claimed to resist a malicious process with concurrent write access to that same private directory. Full disk reservations and a shared-folder race-proof native file API are not implemented.

Signed metadata is still validated before disk access. Local history contains filenames and peer/transfer metadata; it can be cleared in Settings. mDNS exposes device name, platform and public certificate fingerprint only while receiving. System backups on Apple/desktop platforms are controlled by the OS/user and are outside FlowShare's own network transfer path.

No independent audit, fuzzing campaign, certificate-rotation migration, malicious TLS handshake stress test, native permission regression suite, or production threat assessment has been completed. Physical-device testing is required before claiming security and reliability of packaged applications.

See `docs/evidence/core-tests.log` for the automated negative cases. Tests are evidence of specific behavior, not proof of absence of vulnerabilities.

