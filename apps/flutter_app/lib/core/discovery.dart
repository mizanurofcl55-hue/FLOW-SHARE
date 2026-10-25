import 'dart:async';
import 'dart:io';
import 'package:bonsoir/bonsoir.dart';
import 'package:flowshare_core/flowshare_core.dart';
import 'package:flutter/foundation.dart';

class PeerDiscovery extends ChangeNotifier {
  final String ownFingerprint;
  final Map<String, Invitation> peers = {};
  BonsoirDiscovery? _discovery;
  BonsoirBroadcast? _broadcast;
  StreamSubscription<BonsoirDiscoveryEvent>? _events;
  Timer? _timeout;
  bool scanning = false;
  String? error;
  PeerDiscovery(this.ownFingerprint);
  Future<void> scan() async {
    await stopScan();
    peers.clear();
    error = null;
    scanning = true;
    notifyListeners();
    try {
      final d = BonsoirDiscovery(type: '_flowshare._tcp', printLogs: false);
      _discovery = d;
      await d.initialize();
      _events = d.eventStream?.listen(
        (event) {
          try {
            if (event is BonsoirDiscoveryServiceFoundEvent) {
              event.service.resolve(d.serviceResolver);
            }
            if (event is BonsoirDiscoveryServiceResolvedEvent ||
                event is BonsoirDiscoveryServiceUpdatedEvent) {
              final service = event.service;
              if (service == null || peers.length >= 128) return;
              final fp = checkedHash(service.attributes['fp']);
              if (fp == ownFingerprint) return;
              for (final host in service.hostAddresses) {
                final address = InternetAddress.tryParse(host);
                if (address == null ||
                    address.type != InternetAddressType.IPv4 ||
                    !isLocalAddress(address)) {
                  continue;
                }
                final invitation = Invitation(
                  host: address.address,
                  port: service.port,
                  fingerprint: fp,
                  name: checkedText(service.attributes['name'], 64),
                  platform: checkedText(service.attributes['platform'], 32),
                );
                Invitation.parse(invitation.encode());
                peers[service.name] = invitation;
                notifyListeners();
                break;
              }
            }
            if (event is BonsoirDiscoveryServiceLostEvent) {
              peers.remove(event.service.name);
              notifyListeners();
            }
          } catch (_) {
            /* Untrusted mDNS records are ignored. */
          }
        },
        onError: (Object e) {
          error = 'permissionDenied';
          notifyListeners();
        },
      );
      await d.start();
      _timeout = Timer(const Duration(seconds: 20), stopScan);
    } catch (_) {
      error = 'permissionDenied';
      await stopScan();
      notifyListeners();
    }
  }

  Future<void> advertise(String name, int port) async {
    await stopAdvertising();
    final b = BonsoirBroadcast(
      service: BonsoirService(
        name: 'FlowShare-${ownFingerprint.substring(0, 12)}',
        type: '_flowshare._tcp',
        port: port,
        attributes: {
          'fp': ownFingerprint,
          'name': name,
          'platform': Platform.operatingSystem,
          'v': '1',
        },
      ),
      printLogs: false,
    );
    _broadcast = b;
    await b.initialize();
    await b.start();
  }

  Future<void> stopScan() async {
    _timeout?.cancel();
    await _events?.cancel();
    _events = null;
    try {
      await _discovery?.stop();
    } catch (_) {}
    _discovery = null;
    scanning = false;
    notifyListeners();
  }

  Future<void> stopAdvertising() async {
    try {
      await _broadcast?.stop();
    } catch (_) {}
    _broadcast = null;
  }

  Future<void> shutdown() async {
    await stopScan();
    await stopAdvertising();
  }
}
