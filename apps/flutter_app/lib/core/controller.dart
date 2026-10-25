import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'package:file_selector/file_selector.dart';
import 'package:flowshare_core/flowshare_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'discovery.dart';
import 'storage.dart';
import 'strings.dart';

final controllerProvider = ChangeNotifierProvider<AppController>(
  (ref) => throw StateError('Controller must be initialized'),
);

class AppController extends ChangeNotifier {
  static const native = MethodChannel('app.flowshare/platform');
  LocalStore? store;
  DeviceIdentity? identity;
  TransferEngine? engine;
  PeerDiscovery? discovery;
  String name = 'My device',
      language = 'en',
      theme = 'system',
      receivePath = '';
  bool onboarded = false, preparing = false, rememberPeer = false;
  bool _foregroundActive = false;
  String? error;
  Map<String, dynamic>? hotspot;
  List<XFile> selected = [];
  List<Invitation> invitations = [];
  List<Map<String, Object?>> history = [], trusted = [];
  TransferProgress? progress;
  PairingRequest? pairing;
  Completer<bool>? _approval;
  TransferControl? _outgoing;
  Manifest? _retryManifest;
  Invitation? _retryPeer;
  List<String>? _retryPaths;
  int selectedBytes = 0;
  bool get busy => preparing || (progress != null && !progress!.finished);
  bool get receiving => engine?.receiving ?? false;
  bool get scanning => discovery?.scanning ?? false;
  List<Invitation> get peers => discovery?.peers.values.toList() ?? [];
  String t(String key) => AppStrings.text(language, key);
  ThemeMode get themeMode => switch (theme) {
    'light' => ThemeMode.light,
    'dark' => ThemeMode.dark,
    _ => ThemeMode.system,
  };
  Future<void> initialize() async {
    final support = await getApplicationSupportDirectory();
    await support.create(recursive: true);
    receivePath = p.join(support.path, 'Received');
    store = await LocalStore.open(p.join(support.path, 'flowshare.sqlite'));
    final values = await store!.settings();
    name = values['name'] ?? 'FlowShare ${Platform.operatingSystem}';
    language = values['language'] ?? 'en';
    theme = values['theme'] ?? 'system';
    onboarded = values['onboarded'] == 'true';
    const secure = FlutterSecureStorage();
    final saved = await secure.read(key: 'flowshare.identity.v1');
    identity = saved == null
        ? await DeviceIdentity.generate()
        : DeviceIdentity.decode(saved);
    if (saved == null) {
      await secure.write(
        key: 'flowshare.identity.v1',
        value: identity!.encode(),
      );
    }
    discovery = PeerDiscovery(identity!.fingerprint)
      ..addListener(notifyListeners);
    _newEngine();
    await refreshRecords();
    native.setMethodCallHandler((call) async {
      if (call.method == 'hotspotStopped') {
        hotspot = null;
        notifyListeners();
      }
    });
  }

  void _newEngine() {
    engine = TransferEngine(
      identity: identity!,
      name: name,
      receiveRoot: Directory(receivePath),
      approve: _approve,
      onProgress: _progress,
      freeBytes: () async {
        final bytes = await native.invokeMethod<int>('freeBytes', {
          'path': receivePath,
        });
        if (bytes == null) throw const FlowException('fileUnavailable');
        return bytes;
      },
    );
  }

  Future<void> refreshRecords() async {
    history = await store?.history() ?? [];
    trusted = await store?.trusted() ?? [];
    notifyListeners();
  }

  Future<void> preference(String key, String value) async {
    if (key == 'name') {
      checkedText(value, 64);
      if (busy) return;
      await stopReceiving();
      name = value;
      if (identity != null) _newEngine();
    }
    if (key == 'language') language = value;
    if (key == 'theme') theme = value;
    if (key == 'onboarded') onboarded = true;
    await store?.set(key, value);
    notifyListeners();
  }

  Future<void> guarded(Future<void> Function() operation) async {
    error = null;
    try {
      await operation();
    } catch (e) {
      error = e is FlowException
          ? e.code
          : e is PlatformException
          ? (e.code == 'permissionDenied'
                ? 'permissionDenied'
                : 'operationFailed')
          : 'operationFailed';
    }
    notifyListeners();
  }

  Future<void> chooseFiles([String category = 'allFiles']) async {
    final extensions = switch (category) {
      'photos' => ['jpg', 'jpeg', 'png', 'heic', 'webp'],
      'videos' => ['mp4', 'mov', 'mkv', 'webm'],
      'documents' => ['pdf', 'doc', 'docx', 'txt', 'xlsx'],
      'audio' => ['mp3', 'm4a', 'wav', 'flac'],
      'archives' => ['zip', '7z', 'tar', 'gz'],
      _ => null,
    };
    final picks = await openFiles(
      acceptedTypeGroups: extensions == null
          ? []
          : [XTypeGroup(label: t(category), extensions: extensions)],
    );
    await addFiles(picks);
  }

  Future<void> addFiles(List<XFile> files) async {
    if (busy) return;
    final all = [...selected, ...files];
    final unique = {for (final f in all) f.path: f}.values.toList();
    if (unique.length > maxFiles) throw const FlowException('tooManyFiles');
    for (final f in unique) {
      safeFilename(f.name);
      if (await FileSystemEntity.type(f.path) != FileSystemEntityType.file) {
        throw const FlowException('fileUnavailable');
      }
    }
    selected = unique;
    selectedBytes = 0;
    for (final f in selected) {
      selectedBytes += await f.length();
    }
    notifyListeners();
  }

  Future<void> removeFile(XFile file) async {
    selected.remove(file);
    selectedBytes = 0;
    for (final f in selected) {
      selectedBytes += await f.length();
    }
    notifyListeners();
  }

  Future<void> scan() async {
    if (discovery != null) await discovery!.scan();
  }

  Future<void> startReceiving() async {
    if (busy) return;
    error = null;
    await Directory(receivePath).create(recursive: true);
    final port = await engine!.start();
    await refreshAddresses();
    try {
      await discovery?.advertise(name, port);
    } catch (_) {
      error = 'permissionDenied';
    }
    notifyListeners();
  }

  Future<void> refreshAddresses() async {
    invitations = [];
    final port = engine?.port;
    if (port == null) return;
    for (final net in await NetworkInterface.list(
      type: InternetAddressType.IPv4,
      includeLoopback: false,
    )) {
      for (final address in net.addresses) {
        if (isLocalAddress(address)) {
          invitations.add(
            Invitation(
              host: address.address,
              port: port,
              fingerprint: identity!.fingerprint,
              name: name,
              platform: Platform.operatingSystem,
            ),
          );
        }
      }
    }
    notifyListeners();
  }

  Future<void> stopReceiving() async {
    await engine?.stop();
    await discovery?.stopAdvertising();
    invitations = [];
    notifyListeners();
  }

  Future<bool> _approve(PairingRequest request) async {
    if (_approval != null) return false;
    pairing = request;
    rememberPeer = false;
    _approval = Completer<bool>();
    notifyListeners();
    try {
      return await _approval!.future.timeout(
        const Duration(seconds: 50),
        onTimeout: () => false,
      );
    } finally {
      _approval = null;
      pairing = null;
      notifyListeners();
    }
  }

  void setRememberPeer(bool value) {
    rememberPeer = value;
    notifyListeners();
  }

  Future<void> decide(bool accepted) async {
    if (accepted && rememberPeer && pairing != null) {
      await store?.remember(pairing!.fingerprint, pairing!.peer);
      await refreshRecords();
    }
    final approval = _approval;
    if (approval != null && !approval.isCompleted) approval.complete(accepted);
  }

  void _progress(TransferProgress update) {
    progress = update;
    final active = !update.finished;
    if (active != _foregroundActive && Platform.isAndroid) {
      _foregroundActive = active;
      unawaited(
        native
            .invokeMethod<void>('transferActive', {
              'active': active,
              'language': language,
            })
            .catchError((Object e) {
              error = 'foregroundUnavailable';
              notifyListeners();
            }),
      );
    }
    if (update.finished) {
      unawaited(_saveProgress(update));
      if (_approval != null && !_approval!.isCompleted) {
        _approval!.complete(false);
      }
    }
    notifyListeners();
  }

  Future<void> _saveProgress(TransferProgress update) async {
    try {
      await store?.record(update);
      await refreshRecords();
    } catch (_) {
      error = 'operationFailed';
      notifyListeners();
    }
  }

  Future<void> sendTo(Invitation target, {bool retry = false}) async {
    if (busy) return;
    await stopReceiving();
    await discovery?.stopScan();
    preparing = true;
    error = null;
    notifyListeners();
    try {
      final paths = retry ? _retryPaths! : selected.map((e) => e.path).toList();
      final manifest = retry
          ? _retryManifest!
          : await Isolate.run(() => Manifest.fromPaths(paths));
      _retryManifest = manifest;
      _retryPaths = paths;
      _retryPeer = target;
      _outgoing = TransferControl();
      preparing = false;
      await engine!.send(target, manifest, paths, control: _outgoing);
    } catch (e) {
      error = errorCode(e);
    } finally {
      preparing = false;
      notifyListeners();
    }
  }

  Future<void> retry() async {
    if (_retryPeer != null) await sendTo(_retryPeer!, retry: true);
  }

  bool get canRetry =>
      progress?.direction == 'sent' &&
      progress?.finished == true &&
      progress?.status != TransferStatus.complete &&
      _retryPeer != null;
  void cancel() {
    _outgoing?.cancel();
    engine?.cancelIncoming();
    unawaited(decide(false));
  }

  void dismissProgress() {
    if (progress?.finished == true) {
      progress = null;
      error = null;
      notifyListeners();
    }
  }

  Future<void> clearHistory() async {
    await store?.clearHistory();
    await refreshRecords();
  }

  Future<void> forget(String fp) async {
    await store?.forget(fp);
    await refreshRecords();
  }

  Future<void> clearFragments() async {
    if (busy) return;
    final root = Directory(receivePath);
    if (!await root.exists()) return;
    await for (final item in root.list(recursive: true, followLinks: false)) {
      if (item is File && item.path.endsWith('.part')) await item.delete();
    }
  }

  Future<void> createHotspot() async {
    hotspot = await native.invokeMapMethod<String, dynamic>('createHotspot');
    notifyListeners();
  }

  Future<void> stopHotspot() async {
    await native.invokeMethod<void>('stopHotspot');
    hotspot = null;
    notifyListeners();
  }
}
