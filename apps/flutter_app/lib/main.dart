import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app/app.dart';
import 'app/theme.dart';
import 'core/controller.dart';
import 'core/strings.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  LicenseRegistry.addLicense(() async* {
    for (final font in ['Inter', 'NotoSansBengali']) {
      yield LicenseEntryWithLineBreaks([
        font,
      ], await rootBundle.loadString('assets/fonts/$font-OFL.txt'));
    }
  });
  runApp(const Bootstrap());
}

class Bootstrap extends StatefulWidget {
  const Bootstrap({super.key});
  @override
  State<Bootstrap> createState() => _BootstrapState();
}

class _BootstrapState extends State<Bootstrap> {
  AppController? controller;
  bool failed = false;
  @override
  void initState() {
    super.initState();
    initialize();
  }

  Future<void> initialize() async {
    try {
      await AppStrings.load();
      final c = AppController();
      await c.initialize();
      if (mounted) setState(() => controller = c);
    } catch (_) {
      if (mounted) setState(() => failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (controller != null) {
      return ProviderScope(
        overrides: [controllerProvider.overrideWith((ref) => controller!)],
        child: const FlowShareApp(),
      );
    }
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: flowTheme(Brightness.light),
      home: Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.swap_calls_rounded,
                  size: 64,
                  color: Color(0xFF2563EB),
                ),
                const SizedBox(height: 24),
                const Text(
                  'FlowShare',
                  style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 24),
                if (failed)
                  Text(AppStrings.text('en', 'initializationFailed'))
                else
                  const CircularProgressIndicator(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
