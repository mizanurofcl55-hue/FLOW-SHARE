# Building and distribution

Public preview downloads are published to [GitHub Releases](https://github.com/mizanurofcl55-hue/FLOW-SHARE/releases/tag/v0.1.0-preview.1). See [downloads](downloads.md) for installation. Release assets do not have the CI artifact retention limit described below.

The installed-app workflow validates that its source is a successful `main` build from this repository, tests the exact build's Android x86_64 APK, then verifies every platform checksum before publishing a prerelease. Upload sizes and GitHub asset SHA-256 digests are checked while the release is still a draft. It is made public only after those checks pass. Once published, the version is not overwritten by later CI runs. `build-provenance.json` records the source commit, build and emulator run URLs. The release job alone has `contents: write`; build/test jobs retain read access.

The main CI workflow runs static analysis, protocol/integration tests, widget/SQLite tests, and separate Android, Windows, macOS and iOS builds. It uploads previews with `SHA256SUMS.txt`; downloads are retained for 30 days. Artifacts are associated with an exact commit and workflow run.

## Android

`flutter build apk --debug --split-per-abi` produces debug-signed installable previews for supported ABIs. These are for testing and not Play Store releases. The default Flutter template's release-to-debug-key signing fallback has been removed. For production the owner must provide an existing/new keystore, alias and passwords privately, configure a release signing config, choose the application ID/version policy and run `flutter build appbundle --release` or `flutter build apk --release`. Never commit the keystore or `key.properties`.

## iOS

The CI command is `flutter build ios --debug --no-codesign`. Its `.app` bundle is compilation evidence, not an installable signed IPA. A physical device build requires an Apple developer team, registered bundle ID, valid certificate/provisioning profile and matching Keychain entitlements. Set the signing team in Xcode, build/archive and export using the owner’s distribution method. Direct Nearby/Wi-Fi Aware entitlements are not requested because those routes are not implemented.

## macOS

CI builds a debug app and packages it as a tarball to retain bundle permissions/symlinks. OS-local network prompts and the Keychain must be tested with the intended signing identity. Distribution requires a Developer ID Application certificate, hardened runtime/appropriate sandbox entitlements and notarization credentials. Do not bypass Gatekeeper to treat an unsigned preview as trusted production software.

## Windows

CI builds release mode and packages the entire runner Release folder as a portable ZIP, including DLLs and Flutter assets. Do not distribute the EXE alone. Test on a clean Windows machine, including private-network firewall permission and secure-storage persistence. A production installer/MSIX and trusted Authenticode signing are not yet prepared.

## Release gates

Complete the physical compatibility/failure matrix, verify the exact packaged bytes, review dependencies and third-party notices, audit authentication/filesystem behavior, decide support/minimum OS policy, configure private signing, document privacy/support, and generate final signed-artifact checksums. No signing secret or approval is needed for source push or unsigned/debug CI; production signing is blocked by absent owner credentials.

