# Download FlowShare

Open **[FlowShare 0.1.0 preview](https://github.com/mizanurofcl55-hue/FLOW-SHARE/releases/tag/v0.1.0-preview.1)** and expand **Assets**. Downloads are public; no GitHub account is required.

- **Most Android phones:** [ARM64 APK](https://github.com/mizanurofcl55-hue/FLOW-SHARE/releases/download/v0.1.0-preview.1/FlowShare-0.1.0-Android-arm64-Preview.apk).
- **Older Android phones:** [ARMv7 APK](https://github.com/mizanurofcl55-hue/FLOW-SHARE/releases/download/v0.1.0-preview.1/FlowShare-0.1.0-Android-armv7-Preview.apk).
- **Windows 64-bit:** [Portable ZIP](https://github.com/mizanurofcl55-hue/FLOW-SHARE/releases/download/v0.1.0-preview.1/FlowShare-0.1.0-Windows-x64-Preview.zip). Extract all files and run `flowshare.exe`.
- **macOS/iOS developers:** unsigned bundles are listed on the release page. The iOS archive is not an installable IPA. Apple signing/provisioning is required.
- **Source code:** use **Code → Download ZIP** on the repository, or the source archives on the release page.

These are testing builds. Android APKs use a CI debug signing key. A previous preview may use a different key and reject an in-place update. Preserve received files before uninstalling any old app: its local data can be removed. Do not disable device security protections to install a blocked APK.

Compare a download's SHA-256 with the release's `SHA256SUMS.txt`. Windows: `Get-FileHash <file> -Algorithm SHA256`; macOS: `shasum -a 256 <file>`; Linux: `sha256sum <file>`.

## বাংলা

সাধারণ Android ফোনে উপরের **ARM64 APK** ডাউনলোড করে খুলুন। এই preview বিশ্বাস করলে শুধু যেখান থেকে APK খুলছেন সেই app-এর installation permission দিন। পুরোনো preview update না হলে আগের app-এর received files আগে সংরক্ষণ করুন—uninstall করলে app-এর data মুছে যেতে পারে।

Windows-এ পুরো ZIP extract করে `flowshare.exe` চালান। শুধু EXE আলাদা করে নেবেন না। iPhone-এর জন্য এখন সাধারণভাবে install করার IPA নেই।

## First transfer

Connect both devices to the same reachable Wi-Fi/Ethernet LAN or one device's hotspot. Open **Receive files → Start receiving** on the recipient, choose files on the sender, then find the device or use its pairing link/QR. Compare all four verification-code groups on both devices and approve. Keep both apps open until completion. A QR invitation does not create or join a network.

[Full release notes](releases/v0.1.0-preview.1.md) · [Known limitations](limitations.md) · [Troubleshooting / report an issue](https://github.com/mizanurofcl55-hue/FLOW-SHARE/issues)
