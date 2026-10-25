# Known limitations and incomplete features

- This is a **LAN/hotspot preview**, not completion of the full universal direct-transport master specification.
- No physical Android/iOS/Windows/macOS transfer pair has been verified. Build outcomes are separate from runtime outcomes.
- Nearby Connections, Wi-Fi Aware, Wi-Fi Direct, Apple Network peer-to-peer, Bluetooth discovery and remote WebRTC adapters are not implemented. Guidance and truthful capability declarations replace unavailable routes; they are not stubs advertised as working.
- Native Android hotspot creation is implemented but hardware-dependent and untested on a device. Other OS hotspot creation is user-assisted. Automatic hotspot join is not implemented.
- One active incoming or outgoing transfer. No multi-device queue, scheduling, clipboard sharing or system share-sheet integration.
- Individual files only: no folder trees, directory extraction, compression, native save-location chooser, persistent file-access bookmarks, tray/menu bar, window restoration or desktop notification integration.
- Up to 128 files and 1 TiB per transfer. Source preflight hashes take time. A single file may restart from zero after interruption; only completed verified files resume. Sender retry survives only while the app session retains selected file access.
- Live average throughput includes session preparation/approval elapsed time, not an instantaneous radio measurement. Verified bytes reused from an earlier attempt are excluded from the current throughput numerator. Benchmark logs are the authoritative performance evidence.
- A 60-second frame idle timeout can interrupt exceptionally slow file verification or disks. No claim of indefinite background transfer: keep iOS awake and app visible; Android/desktop can still be stopped by the OS, sleep or network loss.
- Receiver files remain in app-private support storage. Open in an installed compatible application to export/share. Removing app data can remove received files.
- No malware scanner, independent security audit, formal protocol proof, shared-folder race-proof native file API, disk reservation or certificate rotation migration.
- Valid owner signing credentials, Apple provisioning/notarization, Windows signing and physical QA are required before production distribution. Android preview APKs must not be represented as release-signed.
