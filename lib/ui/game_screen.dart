import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'package:provider/provider.dart';

import '../constants.dart';
import '../game/snake_game.dart';
import '../services/ad_service.dart';
import '../services/audio_service.dart';
import '../services/haptics_service.dart';
import 'painters/game_painter.dart';
import 'widgets/ad_banner.dart';
import 'widgets/game_over_sheet.dart';
import 'widgets/hud.dart';

class GameScreen extends StatefulWidget {
  const GameScreen({super.key});

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final Ticker _ticker;

  /// Resolved once: the ticker runs 60x a second and should not re-walk the
  /// widget tree for the provider every frame.
  late final SnakeGame _game;

  /// Repaint driver. Everything visual listens to this rather than to
  /// `setState`, so a frame costs one painter run instead of a widget rebuild.
  final ValueNotifier<double> _frame = ValueNotifier<double>(0);

  Duration _lastElapsed = Duration.zero;

  /// Leftover time not yet consumed by a simulation tick. Also drives
  /// interpolation, which is what makes the snakes glide between cells.
  double _accumulator = 0;
  double _clock = 0;

  // Swipe tracking for the floating D-pad.
  Offset? _touchStart;
  Offset? _touchCurrent;
  bool _dpadVisible = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _game = context.read<SnakeGame>();
    _game.startGame();

    _ticker = createTicker(_onFrame)..start();
    AudioService().startMusic();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ticker.dispose();
    _frame.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      _game.pauseIfPlaying();
      AudioService().pauseMusic();
    } else {
      AudioService().resumeMusic();
    }
  }

  void _onFrame(Duration elapsed) {
    if (!mounted) return;

    var dt = (elapsed - _lastElapsed).inMicroseconds / 1e6;
    _lastElapsed = elapsed;

    // A long stall (app resumed, GC pause) must not fast-forward the match.
    if (dt <= 0) return;
    if (dt > 0.25) dt = 0.25;

    final game = _game;
    final wasIdle = !game.isRunning && !game.isDying && game.effects.isEmpty;

    _clock += dt;
    game.updateContinuous(dt);

    if (game.isRunning) {
      _accumulator += dt;
      final interval = game.tickIntervalMs / 1000.0;

      // Fixed timestep: the simulation always advances in whole ticks, so game
      // speed never depends on the device's frame rate.
      var guard = 0;
      while (_accumulator >= interval && guard++ < 5) {
        game.tick();
        _accumulator -= interval;
        if (!game.isRunning) break;
      }
      if (guard >= 5) _accumulator = 0;
    } else {
      _accumulator = 0;
    }

    // Nothing is moving on the pause / game-over screens once the last effect
    // has faded, so stop republishing frames and let the painters idle.
    if (!wasIdle || !game.effects.isEmpty) {
      _frame.value = _clock;
    }
  }

  double _renderT(SnakeGame game) {
    if (!game.isRunning) return 1.0;
    final interval = game.tickIntervalMs / 1000.0;
    return (_accumulator / interval).clamp(0.0, 1.0);
  }

  // ── Input ──────────────────────────────────────────────────────────

  void _handleDrag(SnakeGame game, Offset current) {
    _touchCurrent = current;
    final start = _touchStart;
    if (start == null) return;

    final diff = current - start;
    if (diff.distance < 18) return;

    if (diff.dx.abs() > diff.dy.abs()) {
      game.changeDirection(diff.dx > 0 ? Direction.right : Direction.left);
    } else {
      game.changeDirection(diff.dy > 0 ? Direction.down : Direction.up);
    }

    // Re-anchor so the player can chain turns without lifting their finger.
    if (diff.distance > 46) {
      _touchStart = current - Offset(diff.dx * 0.35, diff.dy * 0.35);
    }
  }

  void _endTouch(SnakeGame game) {
    _touchStart = null;
    _touchCurrent = null;
    if (_dpadVisible) setState(() => _dpadVisible = false);
    game.setBoost(false);
  }

  @override
  Widget build(BuildContext context) {
    final game = context.watch<SnakeGame>();

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (game.isGameOver) {
          Navigator.of(context).pop();
        } else if (game.isPaused) {
          game.togglePause();
        } else {
          game.pauseIfPlaying();
        }
      },
      child: Scaffold(
        backgroundColor: GameConstants.backgroundColor,
        body: Container(
          decoration: const BoxDecoration(
            gradient: RadialGradient(
              center: Alignment.center,
              radius: 1.15,
              colors: [Color(0xFF16203A), Color(0xFF07090F)],
            ),
          ),
          child: SafeArea(
            child: Stack(
              children: [
                _buildArena(game),
                _buildTopHud(game),
                _buildBottomHud(game),
                if (_dpadVisible && game.isRunning) _buildDPad(game),
                if (game.isPaused) _PauseOverlay(onResume: game.togglePause),
                if (game.isGameOver)
                  GameOverSheet(
                    onRetry: _restart,
                    onExit: () => Navigator.of(context).pop(),
                    onRevive: _revive,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _restart() {
    final game = _game;
    if (game.shouldShowInterstitial) {
      context.read<AdService>().showInterstitial(
            onDismissed: () => AudioService().resumeMusic(),
          );
      AudioService().pauseMusic();
      game.markInterstitialShown();
    }
    game.reset();
    _accumulator = 0;
  }

  void _revive() {
    final game = _game;
    AudioService().pauseMusic();
    context.read<AdService>().showRewarded(
      onReward: () {
        game.revive();
        _accumulator = 0;
      },
      onDismissed: () => AudioService().resumeMusic(),
    );
  }

  // ── Arena ──────────────────────────────────────────────────────────

  Widget _buildArena(SnakeGame game) {
    return Positioned.fill(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanStart: (d) {
          _touchStart = d.localPosition;
          _touchCurrent = d.localPosition;
          if (!_dpadVisible) setState(() => _dpadVisible = true);
        },
        onPanUpdate: (d) => _handleDrag(game, d.localPosition),
        onPanEnd: (_) => _endTouch(game),
        onPanCancel: () => _endTouch(game),
        onLongPressStart: (_) {
          game.setBoost(true);
          HapticsService().light();
        },
        onLongPressEnd: (_) => game.setBoost(false),
        onLongPressCancel: () => game.setBoost(false),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 56, 8, 48),
            child: AspectRatio(
              aspectRatio: 1,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: GameConstants.accent.withValues(alpha: 0.32),
                        width: 1.5,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: GameConstants.accent.withValues(alpha: 0.14),
                          blurRadius: 22,
                          spreadRadius: 1,
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(5),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          const RepaintBoundary(
                            child: CustomPaint(
                              painter: ArenaBackgroundPainter(),
                              isComplex: true,
                              willChange: false,
                            ),
                          ),
                          RepaintBoundary(
                            child: ValueListenableBuilder<double>(
                              valueListenable: _frame,
                              builder: (context, clock, _) {
                                return CustomPaint(
                                  painter: GamePainter(
                                    game: game,
                                    renderT: _renderT(game),
                                    clock: clock,
                                  ),
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── HUD ────────────────────────────────────────────────────────────

  Widget _buildTopHud(SnakeGame game) {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ScorePanel(game: game),
            const SizedBox(width: 10),
            Expanded(
              child: ValueListenableBuilder<double>(
                valueListenable: _frame,
                builder: (_, _, _) => ComboBanner(game: game),
              ),
            ),
            const SizedBox(width: 10),
            RivalCounter(game: game),
            const SizedBox(width: 10),
            HudIconButton(
              icon: game.isPaused ? Icons.play_arrow_rounded : Icons.pause_rounded,
              onTap: () {
                HapticsService().selection();
                AudioService().playSfx(GameConstants.sfxClick);
                game.togglePause();
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomHud(SnakeGame game) {
    return Positioned(
      left: 14,
      right: 14,
      bottom: 8,
      child: ValueListenableBuilder<double>(
        valueListenable: _frame,
        builder: (_, _, _) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(child: BoostBar(game: game)),
              const SizedBox(width: 12),
              ActiveEffectsStrip(game: game),
            ],
          );
        },
      ),
    );
  }

  Widget _buildDPad(SnakeGame game) {
    final start = _touchStart;
    if (start == null) return const SizedBox.shrink();

    return Positioned(
      left: start.dx - 78,
      top: start.dy - 78,
      child: IgnorePointer(
        child: ValueListenableBuilder<double>(
          valueListenable: _frame,
          builder: (_, _, _) => _DPad(
            active: _activeSwipeDirection(),
            color: game.currentSkin.primaryColor,
            boosting: game.isBoosting,
          ),
        ),
      ),
    );
  }

  Direction? _activeSwipeDirection() {
    final s = _touchStart;
    final c = _touchCurrent;
    if (s == null || c == null) return null;
    final diff = c - s;
    if (diff.distance < 12) return null;
    if (diff.dx.abs() > diff.dy.abs()) {
      return diff.dx > 0 ? Direction.right : Direction.left;
    }
    return diff.dy > 0 ? Direction.down : Direction.up;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Floating D-pad
// ─────────────────────────────────────────────────────────────────────────────

class _DPad extends StatelessWidget {
  final Direction? active;
  final Color color;
  final bool boosting;

  const _DPad({required this.active, required this.color, required this.boosting});

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: 0.75,
      child: Container(
        width: 156,
        height: 156,
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.22),
          shape: BoxShape.circle,
          border: Border.all(
            color: boosting ? color.withValues(alpha: 0.65) : Colors.white.withValues(alpha: 0.12),
            width: boosting ? 2.5 : 2,
          ),
        ),
        child: Stack(
          children: [
            _arrow(Alignment.topCenter, Icons.keyboard_arrow_up_rounded, Direction.up),
            _arrow(Alignment.bottomCenter, Icons.keyboard_arrow_down_rounded, Direction.down),
            _arrow(Alignment.centerLeft, Icons.keyboard_arrow_left_rounded, Direction.left),
            _arrow(Alignment.centerRight, Icons.keyboard_arrow_right_rounded, Direction.right),
            if (boosting)
              Center(
                child: Icon(Icons.bolt_rounded, color: color, size: 30),
              ),
          ],
        ),
      ),
    );
  }

  Widget _arrow(Alignment alignment, IconData icon, Direction dir) {
    final isActive = active == dir;
    return Align(
      alignment: alignment,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        width: 60,
        height: 60,
        decoration: BoxDecoration(
          color: isActive ? color.withValues(alpha: 0.3) : Colors.transparent,
          shape: BoxShape.circle,
        ),
        child: Icon(
          icon,
          size: 36,
          color: isActive ? Colors.white : Colors.white.withValues(alpha: 0.22),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Pause overlay
// ─────────────────────────────────────────────────────────────────────────────

class _PauseOverlay extends StatelessWidget {
  final VoidCallback onResume;
  const _PauseOverlay({required this.onResume});

  @override
  Widget build(BuildContext context) {
    final game = context.watch<SnakeGame>();

    return Positioned.fill(
      child: ColoredBox(
        color: Colors.black.withValues(alpha: 0.82),
        child: Center(
          child: SingleChildScrollView(
            child: Container(
              width: 360,
              margin: const EdgeInsets.symmetric(vertical: 12),
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                color: const Color(0xFF0D1424),
                borderRadius: BorderRadius.circular(26),
                border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.pause_circle_filled_rounded,
                      color: GameConstants.accentAlt, size: 40),
                  const SizedBox(height: 10),
                  const Text(
                    'PAUSED',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 3,
                    ),
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Expanded(child: _stat('SCORE', '${game.score}', Colors.white)),
                      const SizedBox(width: 8),
                      Expanded(child: _stat('COINS', '+${game.run.coins}', GameConstants.gold)),
                      const SizedBox(width: 8),
                      Expanded(child: _stat('KILLS', '${game.run.kills}', GameConstants.danger)),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Expanded(
                        child: _PauseButton(
                          icon: Icons.play_arrow_rounded,
                          label: 'RESUME',
                          color: GameConstants.accent,
                          filled: true,
                          onTap: onResume,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _PauseButton(
                          icon: Icons.home_rounded,
                          label: 'QUIT',
                          color: Colors.white70,
                          onTap: () {
                            game.togglePause();
                            Navigator.of(context).pop();
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  const AdBannerWidget(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _stat(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          Text(label,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.4),
                fontSize: 9,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.5,
              )),
          const SizedBox(height: 2),
          Text(value,
              style: TextStyle(
                color: color,
                fontSize: 18,
                fontWeight: FontWeight.w900,
                fontFeatures: const [FontFeature.tabularFigures()],
              )),
        ],
      ),
    );
  }
}

class _PauseButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final bool filled;
  final VoidCallback onTap;

  const _PauseButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
    this.filled = false,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          AudioService().playSfx(GameConstants.sfxClick);
          onTap();
        },
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 13),
          decoration: BoxDecoration(
            color: filled ? color : color.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: color.withValues(alpha: filled ? 1 : 0.35)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 18, color: filled ? Colors.black : color),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  color: filled ? Colors.black : color,
                  fontWeight: FontWeight.w900,
                  fontSize: 12,
                  letterSpacing: 1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Rounds a double for display without pulling in intl.
String formatSeconds(double seconds) {
  final total = seconds.round();
  final m = total ~/ 60;
  final s = total % 60;
  return m > 0 ? '${m}m ${s.toString().padLeft(2, '0')}s' : '${s}s';
}

/// Kept next to [formatSeconds] so score formatting is consistent everywhere.
String formatCompact(int value) {
  if (value < 1000) return '$value';
  if (value < 100000) {
    final k = value / 1000;
    return '${k.toStringAsFixed(k < 10 ? 1 : 0)}K';
  }
  return '${(value / 1000).round()}K';
}

/// Used by the HUD to keep the arena square regardless of notch geometry.
double arenaSideFor(BoxConstraints constraints) =>
    math.min(constraints.maxWidth, constraints.maxHeight);
