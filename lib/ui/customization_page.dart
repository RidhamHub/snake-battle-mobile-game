import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../constants.dart';
import '../game/snake_game.dart';
import '../services/ad_service.dart';
import '../services/audio_service.dart';
import '../services/haptics_service.dart';
import 'painters/eye_painter.dart';
import 'painters/snake_preview_painter.dart';
import 'widgets/panels.dart';

/// Skin / eye / colour shop.
///
/// Selections are held locally as a "preview" until the player buys or equips
/// them, so browsing never mutates the saved profile.
class SnakeCustomizationPage extends StatefulWidget {
  const SnakeCustomizationPage({super.key});

  @override
  State<SnakeCustomizationPage> createState() => _SnakeCustomizationPageState();
}

class _SnakeCustomizationPageState extends State<SnakeCustomizationPage>
    with TickerProviderStateMixin {
  late final TabController _tabController;
  late final AnimationController _previewAnim;

  int _skinIndex = 0;
  int _eyeIndex = 0;
  bool _useCustom = false;
  Color _primary = const Color(0xFF00FF88);
  Color _secondary = const Color(0xFF00CC6A);
  bool _seeded = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _previewAnim = AnimationController(vsync: this, duration: const Duration(seconds: 3))..repeat();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_seeded) return;
    final game = context.read<SnakeGame>();
    _skinIndex = game.currentSkinIndex;
    _eyeIndex = game.currentEyeIndex;
    _useCustom = game.useCustomColor;
    _primary = game.customColorPrimary;
    _secondary = game.customColorSecondary;
    _seeded = true;
  }

  @override
  void dispose() {
    _tabController.dispose();
    _previewAnim.dispose();
    super.dispose();
  }

  // ── State helpers ──────────────────────────────────────────────────

  bool _isDirty(SnakeGame game) =>
      _skinIndex != game.currentSkinIndex ||
      _eyeIndex != game.currentEyeIndex ||
      _useCustom != game.useCustomColor ||
      (_useCustom &&
          (_primary != game.customColorPrimary || _secondary != game.customColorSecondary));

  int _outstandingCost(SnakeGame game) {
    var cost = 0;
    if (!game.unlockedSkins.contains(_skinIndex)) {
      cost += GameConstants.availableSkins[_skinIndex].cost;
    }
    if (!game.unlockedEyes.contains(_eyeIndex)) {
      cost += GameConstants.availableEyes[_eyeIndex].cost;
    }
    return cost;
  }

  void _equip(SnakeGame game) {
    game.applyCosmetics(
      skinIndex: _skinIndex,
      eyeIndex: _eyeIndex,
      useCustom: _useCustom,
      primary: _primary,
      secondary: _secondary,
    );

    AudioService().playSfx(GameConstants.sfxPower);
    HapticsService().medium();
    _toast('Equipped', GameConstants.accent, Icons.check_circle_rounded);
    setState(() {});
  }

  void _buy(SnakeGame game) {
    final cost = _outstandingCost(game);
    if (cost == 0) return;

    if (game.coins < cost) {
      _showNotEnoughCoins(game, cost - game.coins);
      return;
    }

    if (!game.unlockedSkins.contains(_skinIndex)) {
      game.unlockSkin(_skinIndex, GameConstants.availableSkins[_skinIndex].cost);
    }
    if (!game.unlockedEyes.contains(_eyeIndex)) {
      game.unlockEye(_eyeIndex, GameConstants.availableEyes[_eyeIndex].cost);
    }

    AudioService().playSfx(GameConstants.sfxGolden);
    HapticsService().heavy();
    _equip(game);
  }

  void _toast(String message, Color color, IconData icon) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: color,
          duration: const Duration(milliseconds: 1400),
          width: 240,
          content: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: Colors.black, size: 18),
              const SizedBox(width: 8),
              Text(message,
                  style: const TextStyle(color: Colors.black, fontWeight: FontWeight.w900)),
            ],
          ),
        ),
      );
  }

  void _showNotEnoughCoins(SnakeGame game, int shortage) {
    final ads = context.read<AdService>();
    showDialog<void>(
      context: context,
      builder: (ctx) {
        final limited = ads.isRewardedLimitReached;
        final canWatch = ads.isAvailable && ads.hasRewarded && !limited;
        return AlertDialog(
          backgroundColor: const Color(0xFF0D1424),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
          title: const Text('Not enough coins',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 17)),
          content: Text(
            canWatch
                ? 'You need $shortage more.\nWatch a short video for '
                    '+${GameConstants.adRewardCoins} coins?'
                : 'You need $shortage more coins.\n'
                    'Complete daily missions or destroy rivals to earn them.',
            style: const TextStyle(color: Colors.white70, height: 1.4),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Close', style: TextStyle(color: Colors.white54)),
            ),
            if (canWatch)
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(backgroundColor: GameConstants.gold),
                onPressed: () {
                  Navigator.pop(ctx);
                  AudioService().pauseMusic();
                  ads.showRewarded(
                    onReward: () {
                      game.addCoins(GameConstants.adRewardCoins);
                      _toast('+${GameConstants.adRewardCoins} coins',
                          GameConstants.gold, Icons.monetization_on_rounded);
                    },
                    onDismissed: AudioService().resumeMusic,
                  );
                },
                icon: const Icon(Icons.play_circle_fill_rounded, color: Colors.black, size: 18),
                label: const Text('Watch',
                    style: TextStyle(color: Colors.black, fontWeight: FontWeight.w900)),
              ),
          ],
        );
      },
    );
  }

  // ── Build ──────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final game = context.watch<SnakeGame>();

    return Scaffold(
      backgroundColor: GameConstants.backgroundColor,
      body: Container(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment.topLeft,
            radius: 1.5,
            colors: [Color(0xFF16203A), Color(0xFF070A11)],
          ),
        ),
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth > 640;
              final preview = _buildPreview(game);
              final controls = _buildControls(game);

              if (wide) {
                return Row(
                  children: [
                    Expanded(flex: 4, child: preview),
                    Expanded(flex: 6, child: controls),
                  ],
                );
              }
              return Column(
                children: [
                  SizedBox(height: 190, child: preview),
                  Expanded(child: controls),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildPreview(SnakeGame game) {
    final skin = GameConstants.availableSkins[_skinIndex];
    final primary = _useCustom ? _primary : skin.primaryColor;
    final secondary = _useCustom ? _secondary : skin.secondaryColor;
    final eye = GameConstants.availableEyes[_eyeIndex].style;
    final dirty = _isDirty(game);

    return Stack(
      children: [
        Positioned.fill(
          child: AnimatedBuilder(
            animation: _previewAnim,
            builder: (context, _) => CustomPaint(
              painter: SnakePreviewPainter(
                t: _previewAnim.value,
                primaryColor: primary,
                secondaryColor: secondary,
                skinType: skin.type,
                eyeStyle: eye,
                segmentSize: 30,
                segments: 10,
              ),
              size: Size.infinite,
            ),
          ),
        ),
        Positioned(
          top: 8,
          left: 8,
          child: GestureDetector(
            onTap: () {
              AudioService().playSfx(GameConstants.sfxClick);
              Navigator.pop(context);
            },
            child: Container(
              padding: const EdgeInsets.all(9),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.45),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
              ),
              child: const Icon(Icons.arrow_back_rounded, color: Colors.white70, size: 20),
            ),
          ),
        ),
        Positioned(
          bottom: 10,
          left: 0,
          right: 0,
          child: Center(
            child: Text(
              _useCustom ? 'CUSTOM COLOURS' : skin.name.toUpperCase(),
              style: TextStyle(
                color: primary.withValues(alpha: 0.85),
                fontSize: 11,
                fontWeight: FontWeight.w900,
                letterSpacing: 2,
              ),
            ),
          ),
        ),
        if (dirty)
          Positioned(
            top: 8,
            right: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: GameConstants.gold,
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Text(
                'PREVIEW',
                style: TextStyle(
                  color: Colors.black,
                  fontWeight: FontWeight.w900,
                  fontSize: 9,
                  letterSpacing: 1.2,
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildControls(SnakeGame game) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
          child: Row(
            children: [
              const Expanded(
                child: Text(
                  'CUSTOMIZE',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 15,
                    letterSpacing: 2,
                  ),
                ),
              ),
              CoinBadge(
                coins: game.coins,
                onTap: () => _showNotEnoughCoins(game, 0),
              ),
            ],
          ),
        ),
        TabBar(
          controller: _tabController,
          indicatorColor: GameConstants.accent,
          indicatorSize: TabBarIndicatorSize.tab,
          labelColor: GameConstants.accent,
          unselectedLabelColor: Colors.white30,
          labelStyle: const TextStyle(fontWeight: FontWeight.w900, fontSize: 11, letterSpacing: 1),
          tabs: const [
            Tab(text: 'SKINS'),
            Tab(text: 'EYES'),
            Tab(text: 'COLOURS'),
          ],
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _skinsTab(game),
              _eyesTab(game),
              _coloursTab(game),
            ],
          ),
        ),
        _bottomBar(game),
      ],
    );
  }

  // ── Tabs ───────────────────────────────────────────────────────────

  Widget _skinsTab(SnakeGame game) {
    final entries = GameConstants.availableSkins.asMap().entries.toList()
      ..sort((a, b) => a.value.cost.compareTo(b.value.cost));

    return GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 116,
        childAspectRatio: 0.82,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
      ),
      itemCount: entries.length,
      itemBuilder: (context, i) {
        final index = entries[i].key;
        final skin = entries[i].value;
        final owned = game.unlockedSkins.contains(index);
        final selected = _skinIndex == index && !_useCustom;

        return _ShopTile(
          selected: selected,
          owned: owned,
          accent: skin.primaryColor,
          cost: skin.cost,
          label: skin.name,
          onTap: () {
            AudioService().playSfx(GameConstants.sfxClick);
            HapticsService().selection();
            setState(() {
              _skinIndex = index;
              _useCustom = false;
            });
          },
          child: CustomPaint(
            painter: SkinSwatchPainter(
              primaryColor: skin.primaryColor,
              secondaryColor: skin.secondaryColor,
              type: skin.type,
            ),
            size: const Size(double.infinity, 34),
          ),
        );
      },
    );
  }

  Widget _eyesTab(SnakeGame game) {
    final entries = GameConstants.availableEyes.asMap().entries.toList()
      ..sort((a, b) => a.value.cost.compareTo(b.value.cost));

    return GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 116,
        childAspectRatio: 0.82,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
      ),
      itemCount: entries.length,
      itemBuilder: (context, i) {
        final index = entries[i].key;
        final eye = entries[i].value;
        final owned = game.unlockedEyes.contains(index);
        final selected = _eyeIndex == index;

        return _ShopTile(
          selected: selected,
          owned: owned,
          accent: GameConstants.accentAlt,
          cost: eye.cost,
          label: eye.name,
          onTap: () {
            AudioService().playSfx(GameConstants.sfxClick);
            HapticsService().selection();
            setState(() => _eyeIndex = index);
          },
          child: CustomPaint(
            painter: EyePreviewPainter(
              style: eye.style,
              headColor: GameConstants.accentAlt,
            ),
            size: const Size(38, 38),
          ),
        );
      },
    );
  }

  Widget _coloursTab(SnakeGame game) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Switch(
                value: _useCustom,
                activeThumbColor: GameConstants.accent,
                onChanged: (v) {
                  AudioService().playSfx(GameConstants.sfxClick);
                  setState(() => _useCustom = v);
                },
              ),
              const Expanded(
                child: Text(
                  'Use custom colours',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 12),
                ),
              ),
            ],
          ),
          Text(
            'Overrides the skin colours while keeping its pattern. '
            'Free — no purchase needed.',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.35), fontSize: 10, height: 1.4),
          ),
          const Divider(color: Colors.white12, height: 24),
          Opacity(
            opacity: _useCustom ? 1 : 0.35,
            child: IgnorePointer(
              ignoring: !_useCustom,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _colourSection('HEAD', _primary, (c) => setState(() => _primary = c)),
                  const SizedBox(height: 18),
                  _colourSection('BODY', _secondary, (c) => setState(() => _secondary = c)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _colourSection(String label, Color current, ValueChanged<Color> onSelect) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.4),
            fontSize: 9,
            letterSpacing: 2,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final c in GameConstants.colorPresets)
              GestureDetector(
                onTap: () {
                  AudioService().playSfx(GameConstants.sfxClick);
                  onSelect(c);
                },
                child: Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: c,
                    shape: BoxShape.circle,
                    border: c.toARGB32() == current.toARGB32()
                        ? Border.all(color: Colors.white, width: 2.5)
                        : Border.all(color: Colors.white.withValues(alpha: 0.1)),
                    boxShadow: c.toARGB32() == current.toARGB32()
                        ? [BoxShadow(color: c.withValues(alpha: 0.5), blurRadius: 10)]
                        : null,
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }

  // ── Bottom bar ─────────────────────────────────────────────────────

  Widget _bottomBar(SnakeGame game) {
    final cost = _outstandingCost(game);
    final dirty = _isDirty(game);

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.35),
        border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.07))),
      ),
      child: cost > 0
          ? ActionButton(
              label: 'UNLOCK  ·  $cost COINS',
              icon: Icons.lock_open_rounded,
              color: game.coins >= cost ? GameConstants.gold : Colors.white38,
              filled: game.coins >= cost,
              onTap: () => _buy(game),
            )
          : ActionButton(
              label: dirty ? 'EQUIP' : 'EQUIPPED',
              icon: dirty ? Icons.check_rounded : Icons.check_circle_rounded,
              color: dirty ? GameConstants.accent : Colors.white24,
              filled: dirty,
              onTap: dirty ? () => _equip(game) : () {},
            ),
    );
  }
}

/// One purchasable item in the skins/eyes grid.
class _ShopTile extends StatelessWidget {
  final bool selected;
  final bool owned;
  final Color accent;
  final int cost;
  final String label;
  final Widget child;
  final VoidCallback onTap;

  const _ShopTile({
    required this.selected,
    required this.owned,
    required this.accent,
    required this.cost,
    required this.label,
    required this.child,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
        decoration: BoxDecoration(
          color: selected
              ? accent.withValues(alpha: 0.14)
              : Colors.white.withValues(alpha: 0.035),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? accent : Colors.white.withValues(alpha: 0.07),
            width: selected ? 2 : 1,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Expanded(
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Locked items stay fully legible: you cannot want a skin you
                  // are not allowed to look at.
                  Opacity(opacity: owned ? 1 : 0.9, child: Center(child: child)),
                  if (!owned)
                    Positioned(
                      top: -2,
                      left: -2,
                      child: Container(
                        padding: const EdgeInsets.all(3),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.7),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(Icons.lock_rounded,
                            color: GameConstants.gold.withValues(alpha: 0.9), size: 11),
                      ),
                    ),
                  if (selected)
                    Positioned(
                      top: -2,
                      right: -2,
                      child: Icon(Icons.check_circle_rounded, color: accent, size: 15),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 5),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: selected ? accent : Colors.white54,
                fontSize: 9.5,
                fontWeight: FontWeight.w800,
              ),
            ),
            if (!owned)
              Text(
                '$cost',
                style: const TextStyle(
                  color: GameConstants.gold,
                  fontSize: 9,
                  fontWeight: FontWeight.w900,
                ),
              )
            else
              Text(
                'OWNED',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.22),
                  fontSize: 7.5,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
