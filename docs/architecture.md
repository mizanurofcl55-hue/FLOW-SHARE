# Architecture

FlowShare 0.1.0 is an offline LAN/hotspot preview. Its application protocol is implemented in Dart so the same tested streaming implementation runs inside all four Flutter targets. Rust/FFI was not introduced: it would add a second crypto/runtime bridge without improving the current single-session, socket-bound design. The core has no Flutter dependency and can be replaced behind `TransferEngine` without moving UI logic into native code.

## Boundaries

- `packages/transfer_core`: validated models, device identity, framed streams, authenticated session, file I/O, integrity verification and recovery journal.
- `lib/core/controller.dart`: lifecycle, user approval, file selection, secure identity initialization, progress, history and retry.
- `lib/core/discovery.dart`: native Bonsoir mDNS advertisements and 20-second scans. Discovered entries are untrusted until pairing.
- `lib/core/storage.dart`: SQLite v1 schema with settings, remembered identities and per-transfer file metadata. Private keys are excluded.
- `lib/app`: responsive Flutter screens, Riverpod ChangeNotifier subscriptions and go_router navigation. Every routed consumer listens to controller updates, so receive state, file selection, discovery, progress and errors update without leaving the page. Structured English/Bengali resources and locally bundled fonts.
- Native method channel: disk capacity on all platforms; Android local-only hotspot, contextual permissions and active-transfer foreground service.

The connection planner declares only adapters linked into this build. Nearby Connections, Wi-Fi Aware, Wi-Fi Direct, Apple peer-to-peer and remote transfer are explicitly unavailable; they are not mock implementations. A hotspot is a network setup mechanism; established file sessions still use the common pinned TLS protocol.

## Lifecycle and persistence

Receiving is opt-in. Starting it binds an IPv4 TLS listener and publishes a Bonjour record. Stopping it cancels the active incoming session and removes the advertisement. Sending stops receiving to keep a single active transfer. Discovery stops after 20 seconds and can be refreshed manually.

The core reads and writes chunks asynchronously with ACK backpressure. Manifest preflight and RSA identity generation run in isolates. The app never reads an entire large file into memory. UI receives real progress, elapsed time and throughput; no simulated peers or transfers are present.

Received data is stored in the app support folder, under a separate random transfer ID. Files are indexed to avoid duplicate-name collisions. A private recovery journal binds the transfer to sender identity and manifest hash. On retry every existing final file is rehashed; incomplete files restart from zero. Sender retry is available in the current running session. Persistent sender queues and Apple security-scoped bookmarks are not implemented.

Settings and history survive app restart. History clearing preserves received files. Temporary-file cleanup removes `.part` fragments only, and is disabled during an active transfer. Forgetting a device removes the local remembered identity record, not file data.

## Dependencies

| Dependency | Reason |
|---|---|
| Flutter / Riverpod / go_router | Native UI, injection and navigation |
| Dart `dart:io` | Native TLS, sockets and streaming file I/O |
| basic_utils / PointyCastle / crypto | Self-signed certificates, RSA signatures and SHA-256 |
| async | Bounded stream framing without reading the whole socket stream |
| Bonsoir | Real native mDNS discovery and advertisement |
| file_selector / desktop_drop / open_filex | OS-mediated selection, desktop drop and opening |
| flutter_secure_storage | OS-backed protected device identity |
| sqflite / sqflite_common_ffi | Local structured records, including Windows support |
| path_provider / path | App-private destinations and portable path handling |
| qr_flutter / qr_code_dart_scan | Pairing QR display; Android/iOS camera frames decoded locally in Dart |

Direct dependency versions and lockfiles are committed. GitHub Actions and the Gradle distribution checksum are pinned. OS/Xcode/Android toolchain updates still require compatibility review; a lockfile alone does not make builds bit-for-bit reproducible.


QR scanning uses the Dart ZXing decoder through `qr_code_dart_scan` with camera audio disabled. This build does not include ML Kit. Live camera scanning is available on Android/iOS; Windows/macOS use discovery or manual pairing links. QR display works on all targets.
