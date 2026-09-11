import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../constants.dart';
import '../game/missions.dart';
import '../game/snake_game.dart';
import '../services/ad_service.dart';
import '../services/audio_service.dart';
import '../services/haptics_service.dart';
import 'customization_page.dart';
import 'game_screen.dart';
import 'painters/snake_preview_painter.dart';
import 'widgets/panels.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with SingleTickerProviderStateMixin {
  final TextEditingController _nameController = TextEditingController();
  late final AnimationController _previewAnim;
  bool _nameSynced = false;

  @override
  void initState() {
    super.initState();
    _previewAnim = AnimationController(vsync: this, duration: const Duration(seconds: 3))..repeat();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<AdService>().loadRewarded();
      AudioService().startMusic();
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _previewAnim.dispose();
    super.dispose();
  }

  void _syncName(SnakeGame game) {
    // The profile loads asynchronously, so seed the field the first time it
    // is actually available rather than in initState.
    if (_nameSynced || !game.isInitialized) return;
    _nameSynced = true;
    _nameController.text = game.playerName;
  }

  void _play(SnakeGame game) {
    final name = _nameController.text.trim();
    game.playerName = name.isEmpty ? 'Player' : name;
    game.saveSettings();
    game.refreshMissionsIfNeeded();
    AudioService().playSfx(GameConstants.sfxClick);
    HapticsService().medium();
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const GameScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final game = context.watch<SnakeGame>();
    _syncName(game);

    return Scaffold(
      backgroundColor: GameConstants.backgroundColor,
      resizeToAvoidBottomInset: false,
      body: Container(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment.topCenter,
            radius: 1.4,
            colors: [Color(0xFF18243F), Color(0xFF070A11)],
          ),
        ),
        child: Stack(
          children: [
            const _AmbientGlow(),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                child: Column(
                  children: [
                    _Header(game: game),
                    const SizedBox(height: 12),
                    Expanded(
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          // Landscape is the intended orientation, but the
                          // layout still has to survive a portrait phone.
                          final wide = constraints.maxWidth > 700;
                          if (!wide) {
                            return SingleChildScrollView(
                              child: Column(
                                children: [
                                  _identityPanel(game),
                                  const SizedBox(height: 12),
                                  _missionPanel(game),
                                  const SizedBox(height: 12),
                                  _controlPanel(game),
                                ],
                              ),
                            );
                          }
                          return Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Expanded(flex: 4, child: _identityPanel(game)),
                              const SizedBox(width: 12),
                              Expanded(flex: 3, child: _missionPanel(game)),
                              const SizedBox(width: 12),
                              Expanded(flex: 5, child: _controlPanel(game)),
                            ],
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Identity / preview ─────────────────────────────────────────────

  Widget _identityPanel(SnakeGame game) {
    final skin = game.currentSkin;

    return SectionPanel(
      title: 'YOUR SNAKE',
      icon: Icons.person_rounded,
      accent: skin.primaryColor,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _nameController,
            textAlign: TextAlign.center,
            maxLength: 14,
            textCapitalization: TextCapitalization.characters,
            style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w900),
            decoration: InputDecoration(
              counterText: '',
              isDense: true,
              hintText: 'ENTER NAME',
              hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.2)),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(vertical: 4),
            ),
            onSubmitted: (_) {
              game.playerName = _nameController.text.trim().isEmpty
                  ? 'Player'
                  : _nameController.text.trim();
              game.saveSettings();
            },
          ),
          Container(width: 70, height: 1.5, color: skin.primaryColor.withValues(alpha: 0.4)),
          const SizedBox(height: 12),
          Expanded(
            child: GestureDetector(
              onTap: _openCustomization,
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.28),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: skin.primaryColor.withValues(alpha: 0.25)),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: AnimatedBuilder(
                    animation: _previewAnim,
                    builder: (context, _) => CustomPaint(
                      painter: SnakePreviewPainter(
                        t: _previewAnim.value,
                        primaryColor: skin.primaryColor,
                        secondaryColor: skin.secondaryColor,
                        skinType: skin.type,
                        eyeStyle: game.currentEye.style,
                        segmentSize: 24,
                        segments: 8,
                      ),
                      size: Size.infinite,
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          ActionButton(
            label: 'CUSTOMIZE',
            icon: Icons.palette_rounded,
            color: skin.primaryColor,
            onTap: _openCustomization,
          ),
        ],
      ),
    );
  }

  void _openCustomization() {
    AudioService().playSfx(GameConstants.sfxClick);
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const SnakeCustomizationPage()),
    );
  }

  // ── Missions ───────────────────────────────────────────────────────

  Widget _missionPanel(SnakeGame game) {
    return SectionPanel(
      title: 'DAILY MISSIONS',
      icon: Icons.emoji_events_rounded,
      accent: GameConstants.gold,
      child: game.missions.isEmpty
          ? const Center(
              child: Text('No missions today',
                  style: TextStyle(color: Colors.white24, fontSize: 11)),
            )
          : ListView.separated(
              padding: EdgeInsets.zero,
              itemCount: game.missions.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, i) => _MissionRow(
                mission: game.missions[i],
                onClaim: () {
                  if (game.claimMission(game.missions[i])) {
                    AudioService().playSfx(GameConstants.sfxGolden);
                    HapticsService().medium();
                  }
                },
              ),
            ),
    );
  }

  // ── Difficulty + play ──────────────────────────────────────────────

  Widget _controlPanel(SnakeGame game) {
    return SectionPanel(
      title: 'MISSION CONTROL',
      icon: Icons.settings_input_component_rounded,
      accent: GameConstants.accentAlt,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              for (final d in Difficulty.values) ...[
                Expanded(child: _DifficultyCard(difficulty: d, game: game)),
                if (d != Difficulty.values.last) const SizedBox(width: 8),
              ],
            ],
          ),
          const SizedBox(height: 12),
          _StatStrip(game: game),
          const SizedBox(height: 12),
          ActionButton(
            label: 'START BATTLE',
            icon: Icons.play_arrow_rounded,
            color: GameConstants.accent,
            filled: true,
            large: true,
            onTap: () => _play(game),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: ActionButton(
                  label: 'HOW TO PLAY',
                  icon: Icons.help_outline_rounded,
                  color: Colors.white54,
                  onTap: () => showHowToPlay(context),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _AmbientGlow extends StatelessWidget {
  const _AmbientGlow();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Stack(
        children: [
          Positioned(
            top: -120,
            right: -90,
            child: _blob(260, GameConstants.accent.withValues(alpha: 0.07)),
          ),
          Positioned(
            bottom: -110,
            left: -80,
            child: _blob(240, GameConstants.accentAlt.withValues(alpha: 0.05)),
          ),
        ],
      ),
    );
  }

  Widget _blob(double size, Color color) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      );
}

class _Header extends StatelessWidget {
  final SnakeGame game;
  const _Header({required this.game});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          height: 46,
          width: 46,
          clipBehavior: Clip.hardEdge,
          decoration: BoxDecoration(
            color: GameConstants.accent.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: GameConstants.accent.withValues(alpha: 0.25)),
          ),
          child: Transform.scale(
            scale: 1.35,
            child: Image.asset(
              'assets/images/icon.png',
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) =>
                  const Icon(Icons.videogame_asset_rounded, color: GameConstants.accent),
            ),
          ),
        ),
        const SizedBox(width: 12),
        const Expanded(
          child: Text(
            'SNAKE BATTLE',
            style: TextStyle(
              color: Colors.white,
              fontSize: 21,
              fontWeight: FontWeight.w900,
              letterSpacing: 2.5,
              shadows: [Shadow(color: Color(0x8000FF88), blurRadius: 18)],
            ),
          ),
        ),
        const _SettingsCluster(),
        const SizedBox(width: 10),
        const _RewardButton(),
        const SizedBox(width: 10),
        CoinBadge(coins: game.coins),
      ],
    );
  }
}

class _SettingsCluster extends StatelessWidget {
  const _SettingsCluster();

  @override
  Widget build(BuildContext context) {
    final audio = context.watch<AudioService>();
    final haptics = context.watch<HapticsService>();

    return Row(
      children: [
        SmallToggle(
          icon: audio.isEnabled ? Icons.volume_up_rounded : Icons.volume_off_rounded,
          active: audio.isEnabled,
          onTap: audio.toggleSfx,
        ),
        const SizedBox(width: 6),
        SmallToggle(
          icon: audio.isMusicEnabled ? Icons.music_note_rounded : Icons.music_off_rounded,
          active: audio.isMusicEnabled,
          onTap: audio.toggleMusic,
        ),
        const SizedBox(width: 6),
        SmallToggle(
          icon: haptics.isEnabled ? Icons.vibration_rounded : Icons.smartphone_rounded,
          active: haptics.isEnabled,
          onTap: haptics.toggle,
        ),
      ],
    );
  }
}

class _RewardButton extends StatelessWidget {
  const _RewardButton();

  @override
  Widget build(BuildContext context) {
    final ads = context.watch<AdService>();
    if (!ads.isAvailable) return const SizedBox.shrink();

    final limited = ads.isRewardedLimitReached;
    final ready = ads.hasRewarded;
    final label = limited
        ? 'MAX ${ads.rewardedAdsCount}/${AdService.maxRewardedAdsPerDay}'
        : (ready ? '+${GameConstants.adRewardCoins}' : 'LOADING');
    final enabled = ready && !limited;

    return GestureDetector(
      onTap: enabled
          ? () {
              final game = context.read<SnakeGame>();
              final messenger = ScaffoldMessenger.of(context);
              AudioService().pauseMusic();
              ads.showRewarded(
                onReward: () {
                  game.addCoins(GameConstants.adRewardCoins);
                  messenger.showSnackBar(
                    SnackBar(
                      behavior: SnackBarBehavior.floating,
                      backgroundColor: GameConstants.gold,
                      content: Text('+${GameConstants.adRewardCoins} coins!',
                          style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                    ),
                  );
                },
                onDismissed: AudioService().resumeMusic,
              );
            }
          : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
        decoration: BoxDecoration(
          gradient: enabled
              ? const LinearGradient(colors: [Color(0xFFFFA502), Color(0xFFFFC53D)])
              : null,
          color: enabled ? null : Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: enabled ? Colors.transparent : Colors.white.withValues(alpha: 0.08),
          ),
        ),
        child: Row(
          children: [
            Icon(
              limited ? Icons.block_rounded : Icons.slideshow_rounded,
              size: 15,
              color: enabled ? Colors.black : Colors.white24,
            ),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                color: enabled ? Colors.black : Colors.white24,
                fontWeight: FontWeight.w900,
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DifficultyCard extends StatelessWidget {
  final Difficulty difficulty;
  final SnakeGame game;

  const _DifficultyCard({required this.difficulty, required this.game});

  @override
  Widget build(BuildContext context) {
    final selected = game.difficultyEnum == difficulty;
    final color = difficulty.color;
    final cfg = DifficultyConfig.of(difficulty);

    final (best, holder) = switch (difficulty) {
      Difficulty.easy => (game.highScoreEasy, game.highScoreNameEasy),
      Difficulty.medium => (game.highScoreMedium, game.highScoreNameMedium),
      Difficulty.hard => (game.highScoreHard, game.highScoreNameHard),
    };

    return InkWell(
      onTap: () {
        AudioService().playSfx(GameConstants.sfxClick);
        HapticsService().selection();
        game.setDifficulty(difficulty);
      },
      borderRadius: BorderRadius.circular(18),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
        decoration: BoxDecoration(
          gradient: selected
              ? LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [color.withValues(alpha: 0.22), color.withValues(alpha: 0.05)],
                )
              : null,
          color: selected ? null : Colors.black.withValues(alpha: 0.25),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: selected ? color : Colors.white.withValues(alpha: 0.07),
            width: selected ? 1.6 : 1,
          ),
        ),
        child: Column(
          children: [
            Text(
              difficulty.label,
              style: TextStyle(
                color: selected ? color : Colors.white38,
                fontWeight: FontWeight.w900,
                fontSize: 10,
                letterSpacing: 1,
              ),
            ),
            const SizedBox(height: 1),
            Text(
              '${cfg.aiCount} RIVALS',
              style: TextStyle(
                color: selected ? Colors.white38 : Colors.white12,
                fontSize: 7,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '$best',
              style: TextStyle(
                color: selected ? Colors.white : Colors.white24,
                fontWeight: FontWeight.w900,
                fontSize: 17,
              ),
            ),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                holder == 'NONE' ? 'NO RECORD' : 'BY ${holder.toUpperCase()}',
                style: TextStyle(
                  color: selected ? color.withValues(alpha: 0.8) : Colors.white10,
                  fontWeight: FontWeight.w800,
                  fontSize: 7,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatStrip extends StatelessWidget {
  final SnakeGame game;
  const _StatStrip({required this.game});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _stat('${game.lifetimeGames}', 'RUNS'),
          _divider(),
          _stat('${game.lifetimeKills}', 'KILLS'),
          _divider(),
          _stat('${game.lifetimeFood}', 'FOOD'),
          _divider(),
          _stat('x${game.lifetimeBestCombo}', 'COMBO'),
        ],
      ),
    );
  }

  Widget _divider() => Container(width: 1, height: 20, color: Colors.white.withValues(alpha: 0.06));

  Widget _stat(String value, String label) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(value,
            style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w900)),
        Text(label,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.3),
              fontSize: 7.5,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.2,
            )),
      ],
    );
  }
}

class _MissionRow extends StatelessWidget {
  final Mission mission;
  final VoidCallback onClaim;

  const _MissionRow({required this.mission, required this.onClaim});

  @override
  Widget build(BuildContext context) {
    final done = mission.isComplete;
    final claimed = mission.claimed;

    return Container(
      padding: const EdgeInsets.all(9),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: claimed ? 0.015 : 0.035),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: done && !claimed
              ? GameConstants.gold.withValues(alpha: 0.45)
              : Colors.white.withValues(alpha: 0.05),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  mission.title,
                  style: TextStyle(
                    color: claimed ? Colors.white24 : Colors.white70,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                    decoration: claimed ? TextDecoration.lineThrough : null,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              if (claimed)
                const Icon(Icons.check_circle_rounded, size: 15, color: Colors.white24)
              else if (done)
                GestureDetector(
                  onTap: onClaim,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: GameConstants.gold,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text('+${mission.reward}',
                        style: const TextStyle(
                            color: Colors.black, fontSize: 10, fontWeight: FontWeight.w900)),
                  ),
                )
              else
                Text('+${mission.reward}',
                    style: TextStyle(
                      color: GameConstants.gold.withValues(alpha: 0.55),
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                    )),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: mission.fraction,
              minHeight: 4,
              backgroundColor: Colors.white.withValues(alpha: 0.06),
              valueColor: AlwaysStoppedAnimation(
                claimed
                    ? Colors.white12
                    : (done ? GameConstants.gold : GameConstants.accent.withValues(alpha: 0.7)),
              ),
            ),
          ),
          const SizedBox(height: 3),
          Text(
            '${mission.progress.clamp(0, mission.goal)} / ${mission.goal}',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.28),
              fontSize: 8,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}
