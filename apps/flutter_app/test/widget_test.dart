import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flowshare/app/app.dart';
import 'package:flowshare/core/controller.dart';
import 'package:flowshare/core/storage.dart';
import 'package:flowshare/core/strings.dart';
import 'package:flowshare_core/flowshare_core.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await AppStrings.load();
    for (final font in ['Inter', 'NotoSansBengali']) {
      await (FontLoader(
        font,
      )..addFont(rootBundle.load('assets/fonts/$font.ttf'))).load();
    }
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });
  Future<AppController> render(
    WidgetTester tester, {
    Size size = const Size(390, 844),
    String theme = 'light',
    String language = 'en',
    double scale = 1,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = scale;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final c = AppController()
      ..onboarded = true
      ..name = 'My device'
      ..theme = theme
      ..language = language
      ..receivePath = '/private/FlowShare/Received';
    await tester.pumpWidget(
      ProviderScope(
        overrides: [controllerProvider.overrideWith((ref) => c)],
        child: const FlowShareApp(),
      ),
    );
    await tester.runAsync(
      () => precacheImage(
        const AssetImage('assets/brand/icon.png'),
        tester.element(find.byType(MaterialApp)),
      ),
    );
    await tester.pumpAndSettle();
    return c;
  }

  for (final theme in ['light', 'dark']) {
    testWidgets('mobile $theme navigation and honest empty discovery', (
      tester,
    ) async {
      await render(tester, theme: theme);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/home-$theme.png'),
      );
      await tester.tap(find.byType(ActionCard).first);
      await tester.pumpAndSettle();
      expect(find.text('Choose files'), findsWidgets);
      await tester.tap(find.text('History'));
      await tester.pumpAndSettle();
      expect(find.text('Your transfers will appear here'), findsOneWidget);
      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();
      expect(find.text('Device name'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('routed pages react to controller changes', (tester) async {
    final c = await render(tester);
    await c.preference('name', 'Renamed device');
    await tester.pumpAndSettle();
    expect(find.text('Renamed device'), findsOneWidget);
    await tester.tap(find.byType(ActionCard).last);
    await tester.pumpAndSettle();
    await c.guarded(() async {
      throw const FlowException('fileUnavailable');
    });
    await tester.pumpAndSettle();
    expect(find.text(c.t('fileUnavailable')), findsOneWidget);
    expect(find.text('Start receiving'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('desktop adapts to sidebar', (tester) async {
    await render(tester, size: const Size(1440, 1000));
    expect(find.byType(NavigationBar), findsNothing);
    expect(find.text('No nearby devices found'), findsOneWidget);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/home-desktop.png'),
    );
    expect(tester.takeException(), isNull);
  });
  testWidgets('Bengali at 200 percent text size', (tester) async {
    await render(tester, language: 'bn', scale: 2);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/bengali-large-text.png'),
    );
    expect(tester.takeException(), isNull);
  });
  testWidgets('incoming transfer requires explicit code approval', (
    tester,
  ) async {
    final c = await render(tester);
    c.pairing = PairingRequest(
      'Test peer',
      'a' * 64,
      '01234567 89ABCDEF 01234567 89ABCDEF',
      'received',
      Manifest(randomId(), [FileMeta('photo.jpg', 1024, 'a' * 64)]),
    );
    c.setRememberPeer(false);
    await tester.pumpAndSettle();
    expect(find.text('Codes match — accept'), findsOneWidget);
    expect(find.text('Decline'), findsOneWidget);
    expect(find.text('01234567'), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });
  test(
    'SQLite survives close and reopen; history clearing does not delete payload',
    () async {
      final temp = await Directory.systemTemp.createTemp('flowshare-db-');
      addTearDown(() => temp.delete(recursive: true));
      final path = '${temp.path}/app.sqlite';
      var db = await LocalStore.open(path);
      await db.set('language', 'bn');
      await db.remember('a' * 64, 'Verified peer');
      final payload = await File('${temp.path}/kept.txt').writeAsString('keep');
      await db.record(
        TransferProgress(
          manifest: Manifest(randomId(), [FileMeta('kept.txt', 4, 'a' * 64)]),
          peer: 'Verified peer',
          direction: 'received',
          status: TransferStatus.complete,
          bytes: 4,
          elapsed: const Duration(seconds: 1),
          destination: temp.path,
        ),
      );
      await db.close();
      db = await LocalStore.open(path);
      expect((await db.settings())['language'], 'bn');
      expect((await db.trusted()).single['name'], 'Verified peer');
      expect((await db.history()).single['files'], contains('kept.txt'));
      await db.clearHistory();
      expect(await db.history(), isEmpty);
      expect(await payload.readAsString(), 'keep');
      await db.close();
    },
  );
}
