# FLOWSHARE DEVELOPMENT REPORT

> This is the preserved development report from the original repository. Historical run URLs and APK hashes below refer to those original builds. For this public repository's downloads, use the [public release](https://github.com/mizanurofcl55-hue/FLOW-SHARE/releases/tag/v0.1.0-preview.1) and its `build-provenance.json` / `SHA256SUMS.txt`. Source import details are in [public-transfer.md](public-transfer.md).

Status: **0.1.0 LAN/hotspot preview. The full production definition of done is not met.** This report separates implemented behavior, automated/native build evidence, and remaining physical-device and release work.

## 1. Project Overview

FlowShare is a Flutter Android/iOS/Windows/macOS application for private offline local file sharing. No backend or account is required. This delivery prioritizes a working, testable authenticated LAN/hotspot path with honest capability labels.

## 2. Implemented Features

| Feature | Status |
|---|---|
| TLS sockets, pinned server certificate, signed sender identity and both-user approval | Implemented and verified in host integration tests |
| Streaming, ACKs, checksum, cancellation, safe destinations and completed-file retry | Implemented and verified in host integration tests |
| File chooser, desktop drag/drop, mDNS discovery, QR display, Android/iOS local camera decoding, file opening | Implemented; native runtime behavior not physically tested |
| Onboarding, mobile/desktop navigation, light/dark, English/Bengali | Implemented; widget/golden checks passed |
| Local settings, history with file names, remembered identities | Implemented; SQLite persistence verified |
| Secure identity persistence | Android emulator secure-store/database initialization and restart passed; physical OS validation remains |
| Android local-only hotspot and foreground transfer notification | Implemented; physical verification pending |
| Nearby/Wi-Fi Aware/Wi-Fi Direct/Apple peer-to-peer/remote WebRTC | Not implemented; UI provides explicit alternatives |

## 3. Architecture Summary

UI and native integration reside in `apps/flutter_app`; the reusable Dart transfer engine is in `packages/transfer_core`. Native Kotlin/Swift/C++ bridges provide capacity and Android hotspot/lifecycle operations. Flutter/Riverpod/go_router, SQLite, native secure storage and Bonsoir are used. Android/iOS QR scanning uses a local Dart decoder with audio disabled; macOS/Windows use discovery/manual pairing. ML Kit and its telemetry dependency were removed, and Android CI checks the runtime graph and merged permissions. Rust is intentionally omitted to avoid an unnecessary additional runtime/FFI boundary in the current streaming engine. See [architecture](architecture.md) and [protocol](protocol.md).

## 4. Android Build Status

Native build **passed** in [CI run 40101280986](https://github.com/MizanurOfcL55/flowShare/actions/runs/40101280986); ARM64, ARMv7 and x86_64 debug APKs were produced. The resolved Android dependency graph contains no ML Kit or Google DataTransport; the merged manifest has no microphone or broad write/manage storage permissions. Debug APKs only until valid owner release signing credentials are supplied. [Installed-APK emulator run 40102025315](https://github.com/MizanurOfcL55/flowShare/actions/runs/40102025315) passed onboarding, Home/History/Settings navigation, native receive listener with QR invitation, listener stop, and restart with saved onboarding. Native hotspot and foreground service have not been exercised on a physical device.

## 5. iOS Build Status

Unsigned native debug compilation **passed** in [CI run 40101280986](https://github.com/MizanurOfcL55/flowShare/actions/runs/40101280986) on macOS 15. Apple team, signing certificate and provisioning are required for an installable IPA/device validation. iOS local socket transfers must keep the app active.

## 6. Windows Build Status

Native release-mode portable bundle **built successfully** in [CI run 40101280986](https://github.com/MizanurOfcL55/flowShare/actions/runs/40101280986) on Windows Server 2022. No physical Windows execution or firewall/credential-storage verification has been performed. Installer/MSIX and Authenticode signing remain incomplete.

## 7. macOS Build Status

Native debug build **passed** in [CI run 40101280986](https://github.com/MizanurOfcL55/flowShare/actions/runs/40101280986) on macOS 15. Packaged-app local-network and Keychain behavior need physical testing with the intended signing identity. Developer ID signing and notarization are incomplete.

## 8. Connectivity Matrix

All 16 requested sender/receiver combinations are listed in [connectivity-matrix.md](connectivity-matrix.md). Each currently has an implemented LAN/hotspot candidate and **not physically tested** status. No native direct route is claimed to work from documentation alone.

## 9. Tested Devices

Core and widget/database tests ran on Linux with Flutter 3.47.7 / Dart 3.13.5. Native builds ran on Ubuntu, Windows Server 2022 and macOS 15. The installed Android x86_64 debug APK passed the installed-app checks on an Android 15 / API 35 Pixel 7 Pro emulator. There were no accessible physical Android, iPhone, Windows or Mac devices. Hardware radio capabilities, battery behavior and native permission flows are unmeasured.

## 10. Offline Transfer Results

Actual bytes moved through localhost TCP/TLS without a relay. Empty files, Unicode filenames, 1 KiB, 1 MiB, 100 MiB, 1 GiB and 5 GiB were verified by SHA-256. The tests do not contact a cloud transfer service. They do not prove radio-level router-free interoperability.

## 11. Cross-Platform Test Results

The shared engine is platform-independent Dart source. Android, iOS, Windows and macOS native builds all passed in CI for source commit `f7aeb28cde53ed52fd6b20632c2537b9cdd22ddf`. Cross-device runtime results are all untested; compilation is not substituted for physical verification.

## 12. Security Verification

Tests cover wrong certificate pin, rejected approval, transcript/identity substitution, malicious filenames, manifest bounds, oversized frame, symlink destination, low storage, changed source and checksum mismatch after preflight. See [security.md](security.md) for threat assumptions and audit limitations. Keys are not stored in SQLite or source. Two rendered-QR decoding tests verify a Unicode invitation and reject an unrelated decoded QR. The Android dependency check rejects ML Kit/Google DataTransport and microphone/broad storage permissions. No independent audit has been completed.

## 13. Performance Measurements

| Payload | Elapsed measured interval | Baseline RSS | Peak RSS | Scope |
|---|---:|---:|---:|---|
| 1 GiB | 85,374 ms | 196,468,736 B | 231,256,064 B | One-process host loopback |
| 5 GiB | 434,039 ms | 218,824,704 B | 242,503,680 B | One-process host loopback |

The 5 GiB run added about **22.6 MiB** of measured process memory, rather than buffering the file. Timing includes sender rehash, transfer, receiver verification and an additional test hash; initial fixture generation/manifest are excluded. No mobile throughput, CPU, battery or fixed-speed claim is made. Exact 100 MiB measurements are in the latest [core test log](evidence/core-tests.log).

## 14. Automated Test Results

- **14 core tests passed**, including real 100 MiB streaming and negative security/recovery cases.
- **2 additional large-file tests passed** for 1 GiB and 5 GiB.
- **9 Flutter tests passed in CI**: seven UI/SQLite cases plus two real rendered-QR decoding cases. Coverage includes light/dark mobile navigation, desktop sidebar, Bengali 200% text scaling, explicit pairing controls, SQLite reopen, Unicode pairing QR and rejection of an unrelated QR, and routed-screen updates after controller changes.
- **Android installed-APK smoke test passed** on API 35 x86_64: startup/storage initialization, onboarding/navigation, receive listener/QR invitation, stop, and restart. See [the exact result](evidence/android-smoke-result.json) and [workflow/screenshots](https://github.com/MizanurOfcL55/flowShare/actions/runs/40102025315).
- Core analysis and Flutter analysis reported **no issues**.
- Golden screenshots were rendered and visually inspected. Native emulator Home, History, Settings and receiving QR screenshots were also inspected. These checks do not prove physical discovery or transfer interoperability.

Logs are under [evidence](evidence/), including [selected current CI verification output](evidence/ci-verification-summary.txt). The full current verification log is in [CI run 40101280986](https://github.com/MizanurOfcL55/flowShare/actions/runs/40101280986). The 1/5 GiB benchmark logs remain applicable to the unchanged transfer engine; these benchmarks were not repeated for the QR and UI-state changes.

## 15. Release Artifacts

Complete source, lockfiles, original icon/fonts/licenses, tests, screenshots, documentation and workflows are included. GitHub CI produced ABI-specific Android debug APKs, a Windows portable ZIP, and unsigned Apple preview bundles with SHA-256 checksums. All four artifacts are available in [CI run 40101280986](https://github.com/MizanurOfcL55/flowShare/actions/runs/40101280986). Artifact IDs, archive digests, APK hashes and test scope are recorded in [CI validation evidence](evidence/ci-validation.json). The delivered ARM64 APK SHA-256 is `77d776988689eede6b6e408807992b223fd89fbf8e4d5c747202ec1967d52b87`. It is a debug-signed preview; no store-ready signed release is claimed.

The delivered app includes the routed-screen state fix: receive state, selected files, discovery, progress and errors update in place through a listening ChangeNotifier provider. A regression test checks device-name updates and errors on the Receive route. Use the exact current build linked above; older previews do not contain this correction.

## 16. Known Limitations

Camera scanning is Android/iOS only; desktop pairing uses discovery/manual links. Single active session, 128-file limit, app-private receive destination, manual hotspot joining, IPv4 discovery/listener, 60-second idle timeout, no indefinite iOS background transfer, interrupted-file restart from zero, and in-session sender retry. See [limitations.md](limitations.md).

## 17. Incomplete Features

Native direct adapters and their physical proof-of-concept tests; persistent sender resume/bookmarks; folder trees; custom save location; share sheet; system tray/menu bar; window restoration; desktop notifications; production installers; remote transfer; security audit; full physical failure matrix; final signing and notarization.

## 18. Required Credentials or Approvals

Repository source push and preview builds are authorized by the user. Production Android signing needs the owner’s keystore/alias/passwords; Apple distribution needs the developer team, certificates/profiles and notarization access; Windows signing requires a trusted signing identity. These must be configured privately, never in source. Physical devices and tester execution are required for interoperability validation.

## 19. Next Recommended Improvements

First run the documented physical LAN/hotspot matrix using exact CI artifacts, then fix measured lifecycle and permission failures. Next implement one native direct adapter at a time with real-device byte/hash tests. Add persistent file access/recovery and desktop packaging after the common protocol is proven on each platform. Complete audit and signing before a production release.
