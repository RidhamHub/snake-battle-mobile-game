import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'constants.dart';
import 'game/snake_game.dart';
import 'services/ad_service.dart';
import 'services/audio_service.dart';
import 'services/haptics_service.dart';
import 'ui/home_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final audio = AudioService();
  final haptics = HapticsService();
  final ads = AdService();

  // Audio and haptics gate real gameplay feedback, so wait for them. The ad
  // SDK is slow and entirely optional, so let it warm up in the background.
  await Future.wait([audio.init(), haptics.init()]);
  unawaited(ads.init());

  await _applyDisplayPreferences();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: ads),
        ChangeNotifierProvider.value(value: audio),
        ChangeNotifierProvider.value(value: haptics),
        ChangeNotifierProvider(create: (_) => SnakeGame()),
      ],
      child: const SnakeBattleApp(),
    ),
  );
}

/// Landscape, edge-to-edge, no status bar. Applied once at startup instead of
/// from inside a `build`, which used to re-issue platform calls every frame.
Future<void> _applyDisplayPreferences() async {
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

  final isMobile = !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);
  if (isMobile) {
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  }
}

class SnakeBattleApp extends StatelessWidget {
  const SnakeBattleApp({super.key});

  @override
  Widget build(BuildContext context) {
    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: GameConstants.backgroundColor,
      colorScheme: ColorScheme.fromSeed(
        seedColor: GameConstants.accent,
        brightness: Brightness.dark,
      ),
    );

    return MaterialApp(
      title: 'Snake Battle',
      debugShowCheckedModeBanner: false,
      theme: base.copyWith(
        textSelectionTheme: const TextSelectionThemeData(
          cursorColor: GameConstants.accent,
          selectionHandleColor: GameConstants.accent,
        ),
        snackBarTheme: const SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
        ),
      ),
      home: const _Bootstrap(),
    );
  }
}

/// Holds a branded splash until the saved profile has loaded, so the home
/// screen never flashes default values before the real ones arrive.
class _Bootstrap extends StatelessWidget {
  const _Bootstrap();

  @override
  Widget build(BuildContext context) {
    final ready = context.select<SnakeGame, bool>((g) => g.isInitialized);
    if (ready) return const HomeScreen();

    return const Scaffold(
      backgroundColor: GameConstants.backgroundColor,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'SNAKE BATTLE',
              style: TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.w900,
                letterSpacing: 4,
                shadows: [Shadow(color: Color(0x8000FF88), blurRadius: 20)],
              ),
            ),
            SizedBox(height: 20),
            SizedBox(
              width: 26,
              height: 26,
              child: CircularProgressIndicator(
                strokeWidth: 2.4,
                valueColor: AlwaysStoppedAnimation(GameConstants.accent),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
