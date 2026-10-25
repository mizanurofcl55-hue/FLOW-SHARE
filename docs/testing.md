# Verification

## Automated checks

`packages/transfer_core/test/transfer_test.dart` uses real localhost TCP/TLS sockets and actual temporary files. It verifies empty, Unicode 1 KiB and 1 MiB files; matching code approvals; rejection; wrong certificate pin; low storage; changed source; cancellation and verified-file retry; mutation after preflight/checksum failure; signature substitution; symlink destination rejection; oversized frames; filename/local-address/manifest bounds; and a 100 MiB streaming transfer.

`apps/flutter_app/test/widget_test.dart` checks mobile light/dark navigation, the desktop sidebar, Bengali at 200% text size, explicit incoming approval, in-place device-name changes and routed error messages, and a real SQLite close/reopen cycle. Golden images are committed and visually reviewed. Widget tests use explicitly isolated test state and are not evidence of native discovery or camera interoperability.

`apps/flutter_app/test/qr_decode_test.dart` renders real pairing QR images, decodes them with the same local Dart decoder used by the camera scanner, checks Unicode identity fields, and rejects an unrelated QR as a pairing invitation. The installed-APK Android emulator workflow checks onboarding, navigation, a native receiver/QR invitation, listener stop, and identity/onboarding persistence after restart. It uploads screenshots, UI hierarchy, logcat and a machine-readable result; this is separate from physical cross-device transfer.

```sh
cd packages/transfer_core
dart test --reporter expanded
FLOWSHARE_LARGE_TESTS=1 dart test --reporter expanded --name 'streaming benchmark (1073741824|5368709120)'
cd ../../apps/flutter_app
flutter analyze --no-pub
flutter test --no-pub --reporter expanded
```

Logs in `docs/evidence` record the reconstructed source in this repository. Historical conversation claims about an earlier, unavailable workspace are not used as verification of this source.

Benchmark timing includes sender revalidation, TLS transfer, receiver SHA-256 and an extra destination hash in the test, but excludes initial source generation and initial manifest hashing. RSS measures the combined sender/receiver process on a Linux host. It is not mobile memory, radio throughput, battery, CPU utilization or a sustained cross-device speed claim.

## Current verified preview

App commit `f7aeb28cde53ed52fd6b20632c2537b9cdd22ddf` passed all four native builds, 14 core tests and 9 Flutter tests in [run 40101280986](https://github.com/MizanurOfcL55/flowShare/actions/runs/40101280986). The installed Android x86_64 APK passed [run 40102025315](https://github.com/MizanurOfcL55/flowShare/actions/runs/40102025315), including the receive/QR/stop/restart flow. The delivered ARM64 APK is from the same source build; it has not been run on a physical ARM64 device. Exact hashes and scope are in [ci-validation.json](evidence/ci-validation.json).

## Required physical validation

For each row in the connectivity matrix, record hardware model, OS, build hash, SDK/hardware availability, route, internet disabled/enabled, permissions, file sizes, exact hashes, measured throughput, failures and recovery. Test 1 KiB, 1 MiB, 100 MiB, 1 GiB and 5 GiB where capacity permits. Repeat with empty/Unicode/duplicate names and mixed formats.

Exercise denied network/camera/hotspot permissions, guest Wi-Fi isolation, firewall denial, lost Wi-Fi, interface changes, screen lock, app background, process termination, low disk, source revocation, receiver rejection and cancellation. Check final files independently. Test installable packaged applications; simulator or compilation success is insufficient.

Nested folders, direct Nearby/Apple/Wi-Fi Aware routes, remote sharing, tray behavior and persistent sender resume are not implemented; do not list those as passed cases. Physical devices were not available in the execution environment.
