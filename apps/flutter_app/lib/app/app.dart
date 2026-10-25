import 'dart:convert';
import 'dart:io';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:flowshare_core/flowshare_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_code_dart_scan/qr_code_dart_scan.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;
import 'package:qr_flutter/qr_flutter.dart';
import '../core/controller.dart';
import 'theme.dart';

String formatBytes(num n) {
  const units = ['B', 'KiB', 'MiB', 'GiB', 'TiB'];
  var value = n.toDouble(), i = 0;
  while (value >= 1024 && i < 4) {
    value /= 1024;
    i++;
  }
  return '${value.toStringAsFixed(i == 0 ? 0 : 1)} ${units[i]}';
}

String formatTime(Duration value) {
  final m = value.inMinutes;
  final s = value.inSeconds % 60;
  return m > 0 ? '${m}m ${s}s' : '${s}s';
}

bool get desktop => Platform.isWindows || Platform.isMacOS || Platform.isLinux;

class FlowShareApp extends ConsumerStatefulWidget {
  const FlowShareApp({super.key});
  @override
  ConsumerState<FlowShareApp> createState() => _FlowShareAppState();
}

class _FlowShareAppState extends ConsumerState<FlowShareApp> {
  late final GoRouter router = GoRouter(
    routes: [
      ShellRoute(
        builder: (context, state, child) =>
            AppShell(path: state.uri.path, child: child),
        routes: [
          GoRoute(path: '/', builder: (c, s) => const HomePage()),
          GoRoute(path: '/send', builder: (c, s) => const SendPage()),
          GoRoute(path: '/receive', builder: (c, s) => const ReceivePage()),
          GoRoute(path: '/history', builder: (c, s) => const HistoryPage()),
          GoRoute(path: '/settings', builder: (c, s) => const SettingsPage()),
          GoRoute(path: '/help', builder: (c, s) => const HelpPage()),
          GoRoute(path: '/scan', builder: (c, s) => const ScannerPage()),
        ],
      ),
    ],
  );
  @override
  void dispose() {
    router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = ref.watch(controllerProvider);
    return AnimatedBuilder(
      animation: c,
      builder: (context, _) => MaterialApp.router(
        title: 'FlowShare',
        debugShowCheckedModeBanner: false,
        theme: flowTheme(Brightness.light),
        darkTheme: flowTheme(Brightness.dark),
        themeMode: c.themeMode,
        locale: Locale(c.language),
        supportedLocales: const [Locale('en'), Locale('bn')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        routerConfig: router,
        builder: (context, child) => Stack(
          children: [
            if (!c.onboarded) Onboarding(controller: c) else child!,
            if (c.pairing != null) PairingOverlay(controller: c),
          ],
        ),
      ),
    );
  }
}

class BrandMark extends StatelessWidget {
  final double size;
  const BrandMark({super.key, this.size = 40});
  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(size * .25),
    child: Image.asset(
      'assets/brand/icon.png',
      width: size,
      height: size,
      excludeFromSemantics: true,
    ),
  );
}

class AppShell extends ConsumerWidget {
  final String path;
  final Widget child;
  const AppShell({super.key, required this.path, required this.child});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = ref.watch(controllerProvider);
    final wide = MediaQuery.sizeOf(context).width >= 960;
    const routes = ['/', '/send', '/receive', '/history', '/settings'];
    const labels = ['home', 'send', 'receive', 'history', 'settings'];
    const icons = [
      Icons.home_outlined,
      Icons.north_east_rounded,
      Icons.south_west_rounded,
      Icons.history_rounded,
      Icons.tune_rounded,
    ];
    final title = switch (path) {
      '/send' => 'send',
      '/receive' => 'receive',
      '/history' => 'history',
      '/settings' => 'settings',
      '/help' => 'help',
      '/scan' => 'scanQr',
      _ => 'home',
    };
    final content = Scaffold(
      appBar: AppBar(
        leading: !wide && !['/', '/history', '/settings'].contains(path)
            ? IconButton(
                onPressed: () => context.go('/'),
                icon: const Icon(Icons.arrow_back),
                tooltip: c.t('home'),
              )
            : null,
        title: Text(path == '/' ? 'FlowShare' : c.t(title)),
        actions: [
          IconButton(
            onPressed: () => context.go('/help'),
            icon: const Icon(Icons.help_outline),
            tooltip: c.t('help'),
          ),
          const SizedBox(width: 12),
        ],
      ),
      bottomNavigationBar: wide
          ? null
          : NavigationBar(
              selectedIndex: path == '/history'
                  ? 1
                  : path == '/settings'
                  ? 2
                  : 0,
              onDestinationSelected: (i) =>
                  context.go(['/', '/history', '/settings'][i]),
              destinations: [
                NavigationDestination(
                  icon: const Icon(Icons.home_outlined),
                  label: c.t('home'),
                ),
                NavigationDestination(
                  icon: const Icon(Icons.history),
                  label: c.t('history'),
                ),
                NavigationDestination(
                  icon: const Icon(Icons.tune),
                  label: c.t('settings'),
                ),
              ],
            ),
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1040),
            child: SingleChildScrollView(
              padding: EdgeInsets.all(wide ? 32 : 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (c.error != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Notice(c.t(c.error!), icon: Icons.info_outline),
                    ),
                  child,
                ],
              ),
            ),
          ),
        ),
      ),
    );
    if (!wide) return content;
    return Scaffold(
      body: Row(
        children: [
          SizedBox(
            width: 240,
            child: Material(
              color: Theme.of(context).colorScheme.surface,
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 24,
                        ),
                        child: Row(
                          children: [
                            BrandMark(),
                            SizedBox(width: 12),
                            Text(
                              'FlowShare',
                              style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                      for (var i = 0; i < routes.length; i++)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: ListTile(
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            selected: path == routes[i],
                            selectedTileColor: Theme.of(
                              context,
                            ).colorScheme.primary.withValues(alpha: .09),
                            leading: Icon(icons[i]),
                            title: Text(c.t(labels[i])),
                            onTap: () => context.go(routes[i]),
                          ),
                        ),
                      const Spacer(),
                      ListTile(
                        leading: const Icon(Icons.help_outline),
                        title: Text(c.t('help')),
                        onTap: () => context.go('/help'),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(
                          c.t('version'),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          VerticalDivider(
            width: 1,
            thickness: 1,
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
          Expanded(child: content),
        ],
      ),
    );
  }
}

class Notice extends StatelessWidget {
  final String text;
  final IconData icon;
  const Notice(this.text, {super.key, this.icon = Icons.lock_outline});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.primary.withValues(alpha: .07),
      borderRadius: BorderRadius.circular(14),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 12),
        Expanded(child: Text(text)),
      ],
    ),
  );
}

class Panel extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  const Panel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(24),
  });
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(padding: padding, child: child),
  );
}

class Section extends StatelessWidget {
  final String title;
  final Widget? action;
  const Section(this.title, {super.key, this.action});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 28, bottom: 16),
    child: Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 16,
      runSpacing: 8,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleLarge),
        ?action,
      ],
    ),
  );
}

class HomePage extends ConsumerWidget {
  const HomePage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = ref.watch(controllerProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(c.t('subtitle'), style: Theme.of(context).textTheme.headlineLarge),
        const SizedBox(height: 12),
        Text(c.t('intro'), style: Theme.of(context).textTheme.bodyLarge),
        const SizedBox(height: 28),
        Panel(
          child: Row(
            children: [
              CircleAvatar(
                radius: 26,
                backgroundColor: Theme.of(
                  context,
                ).colorScheme.primary.withValues(alpha: .08),
                child: Icon(
                  desktop ? Icons.computer : Icons.smartphone,
                  size: 26,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      c.t('myDevice'),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    Text(c.name, style: Theme.of(context).textTheme.titleLarge),
                    Text(c.t(c.receiving ? 'visible' : 'ready')),
                  ],
                ),
              ),
              Icon(
                Icons.check_circle_outline,
                color: Theme.of(context).colorScheme.primary,
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        LayoutBuilder(
          builder: (context, constraints) {
            final buttons = [
              ActionCard(
                title: c.t('send'),
                subtitle: c.t('sendHint'),
                icon: Icons.north_east_rounded,
                primary: true,
                onTap: () => context.go('/send'),
              ),
              ActionCard(
                title: c.t('receive'),
                subtitle: c.t('receiveHint'),
                icon: Icons.south_west_rounded,
                onTap: () => context.go('/receive'),
              ),
            ];
            return constraints.maxWidth > 650
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: buttons[0]),
                      const SizedBox(width: 16),
                      Expanded(child: buttons[1]),
                    ],
                  )
                : Column(
                    children: [
                      buttons[0],
                      const SizedBox(height: 16),
                      buttons[1],
                    ],
                  );
          },
        ),
        if (c.progress != null) ...[
          const SizedBox(height: 24),
          TransferPanel(controller: c),
        ],
        NearbyList(controller: c),
        const SizedBox(height: 24),
        Notice(c.t('privacyBadge')),
      ],
    );
  }
}

class ActionCard extends StatelessWidget {
  final String title, subtitle;
  final IconData icon;
  final bool primary;
  final VoidCallback onTap;
  const ActionCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
    this.primary = false,
  });
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      child: Material(
        color: primary ? scheme.primary : scheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(
            color: primary ? scheme.primary : scheme.outlineVariant,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  icon,
                  size: 32,
                  color: primary ? scheme.onPrimary : scheme.primary,
                ),
                const SizedBox(height: 20),
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: primary ? scheme.onPrimary : scheme.onSurface,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: primary ? scheme.onPrimary : scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class NearbyList extends StatelessWidget {
  final AppController controller;
  final bool sending;
  const NearbyList({super.key, required this.controller, this.sending = false});
  @override
  Widget build(BuildContext context) {
    final c = controller;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Section(
          c.t('nearby'),
          action: TextButton.icon(
            onPressed: c.scanning ? null : () => c.guarded(c.scan),
            icon: c.scanning
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh),
            label: Text(c.t(c.scanning ? 'scanning' : 'scanAgain')),
          ),
        ),
        if (c.discovery?.error != null)
          Notice(c.t(c.discovery!.error!), icon: Icons.wifi_off),
        if (c.peers.isEmpty)
          Panel(
            child: Column(
              children: [
                Icon(
                  Icons.radar,
                  size: 44,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                const SizedBox(height: 16),
                Text(
                  c.t('emptyPeers'),
                  style: Theme.of(context).textTheme.titleMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(c.t('emptyPeersHelp'), textAlign: TextAlign.center),
                const SizedBox(height: 16),
                TextButton.icon(
                  onPressed: () => context.go('/help'),
                  icon: const Icon(Icons.link),
                  label: Text(c.t('help')),
                ),
              ],
            ),
          )
        else
          ...c.peers.map(
            (peer) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Card(
                child: ListTile(
                  contentPadding: const EdgeInsets.all(16),
                  leading: Icon(
                    ['macos', 'windows'].contains(peer.platform)
                        ? Icons.computer
                        : Icons.smartphone,
                  ),
                  title: Text(peer.name),
                  subtitle: Text('${peer.platform} • ${c.t('localNetwork')}'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: c.busy
                      ? null
                      : () => sending
                            ? c.guarded(() => c.sendTo(peer))
                            : context.go('/send'),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class SendPage extends ConsumerStatefulWidget {
  const SendPage({super.key});
  @override
  ConsumerState<SendPage> createState() => _SendPageState();
}

class _SendPageState extends ConsumerState<SendPage> {
  final link = TextEditingController();
  String category = 'allFiles';
  bool hovered = false;
  @override
  void dispose() {
    link.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = ref.watch(controllerProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(c.t('sendHint'), style: Theme.of(context).textTheme.bodyLarge),
        const SizedBox(height: 24),
        DropTarget(
          onDragEntered: (_) => setState(() => hovered = true),
          onDragExited: (_) => setState(() => hovered = false),
          onDragDone: (d) {
            setState(() => hovered = false);
            c.guarded(() => c.addFiles(d.files));
          },
          child: Panel(
            child: Column(
              children: [
                Icon(
                  Icons.upload_file_rounded,
                  size: 48,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(height: 16),
                Text(
                  c.t(desktop ? 'dropFiles' : 'chooseFiles'),
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                Text(c.t('dropHint'), textAlign: TextAlign.center),
                const SizedBox(height: 20),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: WrapAlignment.center,
                  children: [
                    DropdownButton<String>(
                      value: category,
                      items: [
                        for (final key in [
                          'allFiles',
                          'photos',
                          'videos',
                          'documents',
                          'audio',
                          'archives',
                        ])
                          DropdownMenuItem(value: key, child: Text(c.t(key))),
                      ],
                      onChanged: c.busy
                          ? null
                          : (v) => setState(() => category = v!),
                    ),
                    FilledButton.icon(
                      onPressed: c.busy
                          ? null
                          : () => c.guarded(() => c.chooseFiles(category)),
                      icon: const Icon(Icons.add),
                      label: Text(
                        c.t(c.selected.isEmpty ? 'chooseFiles' : 'addFiles'),
                      ),
                    ),
                  ],
                ),
                if (hovered) const LinearProgressIndicator(),
              ],
            ),
          ),
        ),
        if (c.selected.isNotEmpty) ...[
          Section('${c.t('selectedFiles')} (${c.selected.length})'),
          Text(formatBytes(c.selectedBytes)),
          const SizedBox(height: 12),
          for (final file in c.selected)
            Card(
              child: ListTile(
                leading: const Icon(Icons.insert_drive_file_outlined),
                title: Text(file.name),
                trailing: IconButton(
                  onPressed: c.busy
                      ? null
                      : () => c.guarded(() => c.removeFile(file)),
                  icon: const Icon(Icons.close),
                  tooltip: c.t('remove'),
                ),
              ),
            ),
          NearbyList(controller: c, sending: true),
          Section(c.t('manual')),
          TextField(
            controller: link,
            maxLines: 3,
            minLines: 1,
            autocorrect: false,
            decoration: InputDecoration(labelText: c.t('pairingLink')),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              FilledButton.icon(
                onPressed: c.busy
                    ? null
                    : () => c.guarded(
                        () => c.sendTo(Invitation.parse(link.text)),
                      ),
                icon: const Icon(Icons.link),
                label: Text(c.t('connect')),
              ),
              if (Platform.isAndroid || Platform.isIOS)
                OutlinedButton.icon(
                  onPressed: c.busy ? null : () => context.go('/scan'),
                  icon: const Icon(Icons.qr_code_scanner),
                  label: Text(c.t('scanQr')),
                ),
            ],
          ),
        ],
        if (c.preparing) ...[
          const SizedBox(height: 24),
          const LinearProgressIndicator(),
          Text(c.t('checking')),
        ],
        if (c.progress != null) ...[
          const SizedBox(height: 24),
          TransferPanel(controller: c),
        ],
      ],
    );
  }
}

class ReceivePage extends ConsumerWidget {
  const ReceivePage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = ref.watch(controllerProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(c.t('receiveHint'), style: Theme.of(context).textTheme.bodyLarge),
        const SizedBox(height: 24),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            FilledButton.icon(
              onPressed: c.busy
                  ? null
                  : () => c.guarded(
                      c.receiving ? c.stopReceiving : c.startReceiving,
                    ),
              icon: Icon(
                c.receiving ? Icons.stop_circle_outlined : Icons.south_west,
              ),
              label: Text(
                c.t(c.receiving ? 'stopReceiving' : 'startReceiving'),
              ),
            ),
            if (c.receiving)
              OutlinedButton.icon(
                onPressed: () => c.guarded(c.refreshAddresses),
                icon: const Icon(Icons.refresh),
                label: Text(c.t('refreshAddresses')),
              ),
          ],
        ),
        const SizedBox(height: 24),
        if (c.receiving && c.invitations.isEmpty)
          Notice(c.t('noAddress'), icon: Icons.wifi_off),
        for (final invite in c.invitations)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Panel(
              child: Column(
                children: [
                  Text(c.name, style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 8),
                  Text(
                    '${invite.host}:${invite.port} • ${c.t(c.hotspot == null ? 'localNetwork' : 'temporaryHotspot')}',
                  ),
                  const SizedBox(height: 24),
                  Semantics(
                    label: c.t('pairingLink'),
                    child: Container(
                      color: Colors.white,
                      padding: const EdgeInsets.all(12),
                      child: QrImageView(
                        data: invite.encode(),
                        size: 220,
                        backgroundColor: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  OutlinedButton.icon(
                    onPressed: () async {
                      await Clipboard.setData(
                        ClipboardData(text: invite.encode()),
                      );
                      if (context.mounted) {
                        ScaffoldMessenger.of(
                          context,
                        ).showSnackBar(SnackBar(content: Text(c.t('copied'))));
                      }
                    },
                    icon: const Icon(Icons.copy),
                    label: Text(c.t('copyLink')),
                  ),
                ],
              ),
            ),
          ),
        if (c.progress != null) ...[
          TransferPanel(controller: c),
          const SizedBox(height: 24),
        ],
        Notice(c.t('backgroundHelp'), icon: Icons.phone_iphone),
        const SizedBox(height: 16),
        TextButton.icon(
          onPressed: () => context.go('/help'),
          icon: const Icon(Icons.wifi_tethering),
          label: Text(c.t('help')),
        ),
      ],
    );
  }
}

class TransferPanel extends StatelessWidget {
  final AppController controller;
  const TransferPanel({super.key, required this.controller});
  @override
  Widget build(BuildContext context) {
    final c = controller, r = c.progress!;
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                r.status == TransferStatus.complete
                    ? Icons.check_circle_outline
                    : Icons.swap_horiz,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  c.t(r.status.name),
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text('${c.t(r.direction)} • ${r.peer}'),
          const SizedBox(height: 20),
          LinearProgressIndicator(
            value:
                r.status == TransferStatus.connecting ||
                    r.status == TransferStatus.pairing
                ? null
                : r.fraction,
            minHeight: 8,
            borderRadius: BorderRadius.circular(8),
          ),
          const SizedBox(height: 12),
          Text(
            '${formatBytes(r.bytes)} / ${formatBytes(r.manifest.total)} • ${(r.fraction * 100).toStringAsFixed(0)}%',
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 24,
            runSpacing: 8,
            children: [
              Text('${c.t('speed')}: ${formatBytes(r.speed)}/s'),
              Text(
                '${c.t('remaining')}: ${r.remaining == null ? c.t('calculating') : formatTime(r.remaining!)}',
              ),
              Text('${c.t('elapsed')}: ${formatTime(r.elapsed)}'),
            ],
          ),
          const SizedBox(height: 8),
          Text(c.t('localNetwork')),
          if (r.fileIndex < r.manifest.files.length && !r.finished)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Text(r.manifest.files[r.fileIndex].name),
            ),
          if (r.error != null) ...[
            const SizedBox(height: 16),
            Notice(c.t(r.error!), icon: Icons.info_outline),
          ],
          if (r.destination != null && r.status == TransferStatus.complete) ...[
            const Divider(),
            Text(c.t('destination')),
            SelectableText(r.destination!),
            const SizedBox(height: 12),
            for (var i = 0; i < r.manifest.files.length; i++)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(r.manifest.files[i].name),
                subtitle: Text(formatBytes(r.manifest.files[i].size)),
                trailing: IconButton(
                  tooltip: c.t('openFile'),
                  icon: const Icon(Icons.open_in_new),
                  onPressed: () => openPath(
                    c,
                    p.join(r.destination!, '$i-${r.manifest.files[i].name}'),
                  ),
                ),
              ),
            if (desktop)
              OutlinedButton.icon(
                onPressed: () => openPath(c, r.destination!),
                icon: const Icon(Icons.folder_open),
                label: Text(c.t('openFolder')),
              ),
          ],
          const SizedBox(height: 20),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              if (!r.finished)
                OutlinedButton.icon(
                  onPressed: c.cancel,
                  icon: const Icon(Icons.close),
                  label: Text(c.t('cancel')),
                ),
              if (c.canRetry)
                FilledButton.icon(
                  onPressed: () => c.guarded(c.retry),
                  icon: const Icon(Icons.refresh),
                  label: Text(c.t('retry')),
                ),
              if (r.finished)
                OutlinedButton(
                  onPressed: c.dismissProgress,
                  child: Text(c.t('done')),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

Future<void> openPath(AppController c, String path) async {
  await c.guarded(() async {
    final result = await OpenFilex.open(path);
    if (result.type != ResultType.done) {
      throw const FlowException('fileUnavailable');
    }
  });
}

class PairingOverlay extends StatelessWidget {
  final AppController controller;
  const PairingOverlay({super.key, required this.controller});
  @override
  Widget build(BuildContext context) {
    final c = controller, r = c.pairing!;
    return Stack(
      children: [
        const ModalBarrier(dismissible: false, color: Colors.black54),
        Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 580,
              maxHeight: MediaQuery.sizeOf(context).height * .92,
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Material(
                borderRadius: BorderRadius.circular(24),
                color: Theme.of(context).colorScheme.surface,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Icon(
                        Icons.verified_user_outlined,
                        size: 40,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        c.t(
                          r.direction == 'received'
                              ? 'incoming'
                              : 'verifyConnection',
                        ),
                        style: Theme.of(context).textTheme.headlineMedium,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 12),
                      Text(r.peer, textAlign: TextAlign.center),
                      Text(
                        '${r.manifest.files.length} ${c.t('allFiles')} • ${formatBytes(r.manifest.total)}',
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 24),
                      Text(c.t('compareCode')),
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Theme.of(
                            context,
                          ).colorScheme.primary.withValues(alpha: .08),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Wrap(
                          alignment: WrapAlignment.center,
                          spacing: 16,
                          runSpacing: 8,
                          children: r.code
                              .split(' ')
                              .map(
                                (part) => Text(
                                  part,
                                  style: const TextStyle(
                                    fontSize: 21,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 1,
                                  ),
                                ),
                              )
                              .toList(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      for (final f in r.manifest.files.take(4)) Text(f.name),
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        value: c.rememberPeer,
                        onChanged: (value) {
                          c.setRememberPeer(value!);
                        },
                        title: Text(c.t('remember')),
                        controlAffinity: ListTileControlAffinity.leading,
                      ),
                      Text(
                        c.t('trustedNotice'),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: 20),
                      FilledButton(
                        onPressed: () => c.guarded(() => c.decide(true)),
                        child: Text(c.t('accept')),
                      ),
                      const SizedBox(height: 8),
                      OutlinedButton(
                        onPressed: () => c.guarded(() => c.decide(false)),
                        child: Text(c.t('decline')),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class HistoryPage extends ConsumerStatefulWidget {
  const HistoryPage({super.key});
  @override
  ConsumerState<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends ConsumerState<HistoryPage> {
  String filter = 'all';
  @override
  Widget build(BuildContext context) {
    final c = ref.watch(controllerProvider);
    final records = c.history
        .where(
          (r) =>
              filter == 'all' ||
              r['direction'] == filter ||
              (filter == 'failed' &&
                  ['failed', 'cancelled'].contains(r['status'])),
        )
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(c.t('historyHint')),
        const SizedBox(height: 20),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final key in ['all', 'sent', 'received', 'failed'])
              ChoiceChip(
                label: Text(c.t(key)),
                selected: filter == key,
                onSelected: (_) => setState(() => filter = key),
              ),
          ],
        ),
        const SizedBox(height: 24),
        if (records.isEmpty)
          Panel(
            child: Column(
              children: [
                const Icon(Icons.history, size: 48),
                const SizedBox(height: 16),
                Text(c.t('emptyHistory'), textAlign: TextAlign.center),
              ],
            ),
          ),
        for (final row in records)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Panel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${c.t(row['direction'] as String)} • ${row['peer']}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  Text(
                    '${c.t(row['status'] as String)} • ${formatBytes(row['total'] as int)}',
                  ),
                  Text(
                    DateTime.parse(
                      row['created'] as String,
                    ).toLocal().toString().split('.').first,
                  ),
                  const SizedBox(height: 8),
                  for (final f
                      in (jsonDecode(row['files'] as String) as List).take(6))
                    Text(f['name'] as String),
                  if (row['destination'] != null && row['status'] == 'complete')
                    TextButton.icon(
                      onPressed: () => openPath(
                        c,
                        p.join(
                          row['destination'] as String,
                          '0-${(jsonDecode(row['files'] as String) as List).first['name']}',
                        ),
                      ),
                      icon: const Icon(Icons.open_in_new),
                      label: Text(c.t('openFile')),
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});
  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  late final TextEditingController name = TextEditingController(
    text: ref.read(controllerProvider).name,
  );
  @override
  void dispose() {
    name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = ref.watch(controllerProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Section(c.t('myDevice')),
        Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: name,
                maxLength: 64,
                enabled: !c.busy,
                decoration: InputDecoration(labelText: c.t('deviceName')),
              ),
              const SizedBox(height: 8),
              FilledButton(
                onPressed: c.busy
                    ? null
                    : () => c.guarded(
                        () => c.preference('name', name.text.trim()),
                      ),
                child: Text(c.t('save')),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: c.receiving,
                onChanged: c.busy
                    ? null
                    : (v) => c.guarded(v ? c.startReceiving : c.stopReceiving),
                title: Text(c.t('visible')),
              ),
            ],
          ),
        ),
        Section(c.t('appearance')),
        Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(c.t('theme')),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final key in ['light', 'dark', 'system'])
                    ChoiceChip(
                      label: Text(c.t(key)),
                      selected: c.theme == key,
                      onSelected: (_) =>
                          c.guarded(() => c.preference('theme', key)),
                    ),
                ],
              ),
              const SizedBox(height: 20),
              DropdownButtonFormField<String>(
                initialValue: c.language,
                decoration: InputDecoration(labelText: c.t('language')),
                items: const [
                  DropdownMenuItem(value: 'en', child: Text('English')),
                  DropdownMenuItem(value: 'bn', child: Text('বাংলা')),
                ],
                onChanged: (value) =>
                    c.guarded(() => c.preference('language', value!)),
              ),
            ],
          ),
        ),
        Section(c.t('storage')),
        Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(c.t('storageHint')),
              const SizedBox(height: 12),
              SelectableText(c.receivePath),
              const Divider(),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.verified_user_outlined),
                title: Text(c.t('askAlways')),
              ),
              Text(c.t('resumeHint')),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: c.busy ? null : () => c.guarded(c.clearFragments),
                child: Text(c.t('clearTemporary')),
              ),
            ],
          ),
        ),
        Section(c.t('trusted')),
        Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (c.trusted.isEmpty) Text(c.t('noTrusted')),
              for (final device in c.trusted)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(device['name'] as String),
                  subtitle: Text(
                    (device['fingerprint'] as String).substring(0, 16),
                  ),
                  trailing: IconButton(
                    tooltip: c.t('forget'),
                    onPressed: () => c.guarded(
                      () => c.forget(device['fingerprint'] as String),
                    ),
                    icon: const Icon(Icons.delete_outline),
                  ),
                ),
              const SizedBox(height: 8),
              Text(c.t('trustedNotice')),
            ],
          ),
        ),
        Section(c.t('privacy')),
        Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(c.t('privacyText')),
              const SizedBox(height: 20),
              OutlinedButton(
                onPressed: () => c.guarded(c.clearHistory),
                child: Text(c.t('clearHistory')),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () => showLicensePage(
                  context: context,
                  applicationName: 'FlowShare',
                  applicationVersion: '0.1.0',
                ),
                child: Text(c.t('licenses')),
              ),
              Text(c.t('version'), textAlign: TextAlign.center),
            ],
          ),
        ),
      ],
    );
  }
}

class HelpPage extends ConsumerWidget {
  const HelpPage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = ref.watch(controllerProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Section(c.t('localNetwork')),
        Panel(child: Text(c.t('lanHelp'))),
        Section(c.t('temporaryHotspot')),
        Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                c.t(Platform.isAndroid ? 'androidHotspotHelp' : 'hotspotHelp'),
              ),
              if (Platform.isAndroid) ...[
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: c.busy
                      ? null
                      : () => c.guarded(
                          c.hotspot == null ? c.createHotspot : c.stopHotspot,
                        ),
                  icon: const Icon(Icons.wifi_tethering),
                  label: Text(
                    c.t(c.hotspot == null ? 'createHotspot' : 'stopHotspot'),
                  ),
                ),
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: () => c.guarded(
                    () =>
                        AppController.native.invokeMethod<void>('wifiSettings'),
                  ),
                  child: Text(c.t('wifiSettings')),
                ),
              ],
              if (c.hotspot != null) ...[
                const SizedBox(height: 16),
                SelectableText(
                  '${c.t('networkName')}: ${c.hotspot!['ssid']}\n${c.t('password')}: ${c.hotspot!['password']}',
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 20),
        Notice(c.t('permissionsHelp'), icon: Icons.security),
        const SizedBox(height: 16),
        Notice(c.t('firewallHelp'), icon: Icons.wifi_off),
        const SizedBox(height: 16),
        Notice(c.t('backgroundHelp'), icon: Icons.phone_iphone),
        const SizedBox(height: 16),
        Notice(c.t('directUnavailable'), icon: Icons.info_outline),
        const SizedBox(height: 16),
        Notice(c.t('remoteUnavailable'), icon: Icons.cloud_off),
      ],
    );
  }
}

class ScannerPage extends ConsumerStatefulWidget {
  const ScannerPage({super.key});
  @override
  ConsumerState<ScannerPage> createState() => _ScannerPageState();
}

class _ScannerPageState extends ConsumerState<ScannerPage> {
  bool handled = false;
  bool cameraFailed = false;
  @override
  Widget build(BuildContext context) {
    final c = ref.watch(controllerProvider);
    if (!Platform.isAndroid && !Platform.isIOS) return Notice(c.t('manual'));
    return Column(
      children: [
        Text(c.t('pairingLink')),
        const SizedBox(height: 20),
        SizedBox(
          height: 360,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: cameraFailed
                ? Center(
                    child: Notice(
                      c.t('permissionDenied'),
                      icon: Icons.camera_alt_outlined,
                    ),
                  )
                : QRCodeDartScanView(
                    formats: const [BarcodeFormat.qrCode],
                    onCameraError: (_) {
                      if (mounted) setState(() => cameraFailed = true);
                    },
                    onCapture: (result) {
                      if (handled || !mounted) return;
                      try {
                        final peer = Invitation.parse(result.text);
                        handled = true;
                        context.go('/send');
                        c.guarded(() => c.sendTo(peer));
                      } catch (_) {}
                    },
                  ),
          ),
        ),
      ],
    );
  }
}

class Onboarding extends StatefulWidget {
  final AppController controller;
  const Onboarding({super.key, required this.controller});
  @override
  State<Onboarding> createState() => _OnboardingState();
}

class _OnboardingState extends State<Onboarding> {
  int page = 0;
  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(32),
              child: Column(
                children: [
                  const BrandMark(size: 72),
                  const SizedBox(height: 40),
                  Icon(
                    [
                      Icons.devices,
                      Icons.wifi_tethering,
                      Icons.verified_user_outlined,
                    ][page],
                    size: 88,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(height: 32),
                  Text(
                    c.t('onboard${page + 1}'),
                    style: Theme.of(context).textTheme.headlineLarge,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    c.t('onboard${page + 1}Text'),
                    style: Theme.of(context).textTheme.bodyLarge,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 32),
                  Wrap(
                    spacing: 8,
                    children: [
                      for (var i = 0; i < 3; i++)
                        Container(
                          width: i == page ? 24 : 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: i == page
                                ? Theme.of(context).colorScheme.primary
                                : Theme.of(context).colorScheme.outlineVariant,
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 32),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: () => page < 2
                          ? setState(() => page++)
                          : c.guarded(() => c.preference('onboarded', 'true')),
                      child: Text(c.t(page < 2 ? 'next' : 'getStarted')),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextButton(
                    onPressed: () => c.preference(
                      'language',
                      c.language == 'en' ? 'bn' : 'en',
                    ),
                    child: Text(c.language == 'en' ? 'বাংলা' : 'English'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
