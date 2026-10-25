# Connectivity matrix

All physical combinations below are **not physically tested**. Hardware, OS version, radio/SDK capability, permission outcomes and real throughput are **not measured**. Linux host loopback tests do not replace these results.

| Sender | Receiver | Implemented candidate route | Internet for transfer | Physical result |
|---|---|---|---|---|
| Android | Android | LAN / user-assisted hotspot | No | Not tested |
| Android | iPhone | LAN / user-assisted hotspot | No | Not tested |
| iPhone | Android | LAN / user-assisted hotspot | No | Not tested |
| iPhone | iPhone | LAN / system hotspot where available | No | Not tested |
| Android | Windows | LAN / user-assisted hotspot | No | Not tested |
| Windows | Android | LAN / user-assisted hotspot | No | Not tested |
| Android | Mac | LAN / user-assisted hotspot | No | Not tested |
| Mac | Android | LAN / user-assisted hotspot | No | Not tested |
| iPhone | Windows | LAN / system hotspot where available | No | Not tested |
| Windows | iPhone | LAN / system hotspot where available | No | Not tested |
| iPhone | Mac | LAN / system hotspot where available | No | Not tested |
| Mac | iPhone | LAN / system hotspot where available | No | Not tested |
| Windows | Mac | LAN / system hotspot where available | No | Not tested |
| Mac | Windows | LAN / system hotspot where available | No | Not tested |
| Windows | Windows | LAN / system hotspot where available | No | Not tested |
| Mac | Mac | LAN / system hotspot where available | No | Not tested |

Local discovery uses mDNS where the network and OS allow it. Manual and QR pairing can bypass blocked discovery but cannot bypass a firewall or create a network. Local network access must be granted on Apple platforms; Windows may require a private-network firewall allowance. Android local hotspot uses Nearby Wi-Fi Devices on API 33+ and fine location on older Android; Android 8+ is required for the local-only hotspot API. Local-only hotspots have no internet upstream. Other system hotspot products may require a data-enabled device to activate; FlowShare does not use that internet path for files.

## Native direct route feasibility

| Route | Official API basis | Status in this build |
|---|---|---|
| Android ↔ Android / iOS via Nearby | Google Nearby Connections supports both mobile platforms; permissions/services and iOS capabilities apply | Not implemented; no GMS dependency |
| Android Wi-Fi Aware | Hardware/runtime support and availability must be checked | Not implemented |
| Apple Wi-Fi Aware | Supported OS/hardware, entitlement and declared service required | Not implemented |
| iOS ↔ iOS / macOS peer-to-peer | Apple Network framework Bonjour with peer-to-peer parameters | Not implemented |
| Android Wi-Fi Direct | Public Android P2P APIs; not universal iPhone interoperability | Not implemented |
| Android local-only hotspot | Public `WifiManager.startLocalOnlyHotspot` | Implemented native bridge; physical behavior untested |
| Remote WebRTC | Needs explicit consent, signaling/ICE and potentially relay infrastructure | Not implemented, never automatically selected |

## Official references consulted

- [Google Nearby overview](https://developers.google.com/nearby/connections/overview)
- [Nearby Swift setup](https://developers.google.com/nearby/connections/swift/get-started) — documentation updated 2026-10-01; lists hotspot/Wi-Fi capabilities and contextual protected resources.
- [Android local-only hotspot](https://developer.android.com/develop/connectivity/wifi/localonlyhotspot)
- [Android Wi-Fi Aware](https://developer.android.com/develop/connectivity/wifi/wifi-aware)
- [Apple Network peer-to-peer](https://developer.apple.com/documentation/network/nwparameters/includepeertopeer)
- [Apple migration from Multipeer Connectivity](https://developer.apple.com/documentation/technotes/tn3213-moving-from-multipeer-connectivity-to-network-framework)

These documents establish possible API paths, not physical interoperability evidence for this app. No untested route is labelled “Direct Offline” in the interface.
