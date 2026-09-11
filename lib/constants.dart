import 'package:flutter/foundation.dart' show kReleaseMode;
import 'package:flutter/material.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  Difficulty
// ─────────────────────────────────────────────────────────────────────────────

enum Difficulty { easy, medium, hard }

extension DifficultyX on Difficulty {
  String get label => switch (this) {
        Difficulty.easy => 'ROOKIE',
        Difficulty.medium => 'VETERAN',
        Difficulty.hard => 'LEGEND',
      };

  String get aiLabel => switch (this) {
        Difficulty.easy => 'BASIC AI',
        Difficulty.medium => 'ALPHA AI',
        Difficulty.hard => 'OMEGA AI',
      };

  Color get color => switch (this) {
        Difficulty.easy => const Color(0xFF5BE49B),
        Difficulty.medium => const Color(0xFFFFB13B),
        Difficulty.hard => const Color(0xFFFF5C6C),
      };
}

class DifficultyConfig {
  /// How many rival snakes are in the arena at once.
  final int aiCount;

  /// Milliseconds between game ticks. Lower = faster.
  final int tickMs;

  /// How many food pellets the arena tries to keep available.
  final int foodTarget;

  /// Base score for a normal pellet (before combo multiplier).
  final int foodPoints;

  /// Coins granted per pellet.
  final int coinPerFood;

  /// Coins granted per rival destroyed.
  final int coinPerKill;

  /// 0..1 — how often the AI plays its best move instead of a random safe one.
  final double aiSkill;

  /// 0..1 — chance a newly spawned rival hunts the player instead of food.
  final double aiAggression;

  /// Number of static wall blocks scattered in the arena.
  final int obstacleCount;

  const DifficultyConfig({
    required this.aiCount,
    required this.tickMs,
    required this.foodTarget,
    required this.foodPoints,
    required this.coinPerFood,
    required this.coinPerKill,
    required this.aiSkill,
    required this.aiAggression,
    required this.obstacleCount,
  });

  static const easy = DifficultyConfig(
    aiCount: 3,
    tickMs: 175,
    foodTarget: 10,
    foodPoints: 10,
    coinPerFood: 4,
    coinPerKill: 40,
    aiSkill: 0.45,
    aiAggression: 0.15,
    obstacleCount: 0,
  );

  static const medium = DifficultyConfig(
    aiCount: 5,
    tickMs: 145,
    foodTarget: 8,
    foodPoints: 15,
    coinPerFood: 7,
    coinPerKill: 60,
    aiSkill: 0.78,
    aiAggression: 0.40,
    obstacleCount: 6,
  );

  static const hard = DifficultyConfig(
    aiCount: 7,
    tickMs: 118,
    foodTarget: 6,
    foodPoints: 25,
    coinPerFood: 12,
    coinPerKill: 95,
    aiSkill: 0.95,
    aiAggression: 0.70,
    obstacleCount: 12,
  );

  static DifficultyConfig of(Difficulty d) => switch (d) {
        Difficulty.easy => easy,
        Difficulty.medium => medium,
        Difficulty.hard => hard,
      };
}

// ─────────────────────────────────────────────────────────────────────────────
//  Power-ups
// ─────────────────────────────────────────────────────────────────────────────

enum PowerType { frenzy, shield, magnet, phase, freeze }

class PowerConfig {
  final String name;
  final String blurb;
  final IconData icon;
  final Color color;

  /// How long the effect lasts once collected. 0 means it is a held charge.
  final double seconds;

  const PowerConfig({
    required this.name,
    required this.blurb,
    required this.icon,
    required this.color,
    required this.seconds,
  });

  static const map = <PowerType, PowerConfig>{
    PowerType.frenzy: PowerConfig(
      name: 'FRENZY',
      blurb: 'Double score',
      icon: Icons.local_fire_department_rounded,
      color: Color(0xFFFF7043),
      seconds: 9,
    ),
    PowerType.shield: PowerConfig(
      name: 'SHIELD',
      blurb: 'Survive one hit',
      icon: Icons.shield_rounded,
      color: Color(0xFF64B5F6),
      seconds: 0,
    ),
    PowerType.magnet: PowerConfig(
      name: 'MAGNET',
      blurb: 'Pulls nearby food',
      icon: Icons.filter_tilt_shift_rounded,
      color: Color(0xFFBA68C8),
      seconds: 9,
    ),
    PowerType.phase: PowerConfig(
      name: 'PHASE',
      blurb: 'Pass through snakes',
      icon: Icons.blur_on_rounded,
      color: Color(0xFF4DD0E1),
      seconds: 6,
    ),
    PowerType.freeze: PowerConfig(
      name: 'FREEZE',
      blurb: 'Rivals stop moving',
      icon: Icons.ac_unit_rounded,
      color: Color(0xFF90CAF9),
      seconds: 5,
    ),
  };

  static PowerConfig of(PowerType t) => map[t]!;
}

// ─────────────────────────────────────────────────────────────────────────────
//  Cosmetics
// ─────────────────────────────────────────────────────────────────────────────

enum SkinType { standard, pixel, rounded, striped, spotted, patterned, neon }

/// Defines how the snake's eyes are rendered.
enum EyeStyle { classic, cute, angry, sleepy, wink, star, heart, neon, dizzy, cool }

class EyeConfig {
  final String name;
  final EyeStyle style;
  final int cost;
  final String emoji;

  const EyeConfig({
    required this.name,
    required this.style,
    required this.cost,
    required this.emoji,
  });
}

class SkinConfig {
  final String name;
  final Color primaryColor;
  final Color secondaryColor;
  final SkinType type;
  final int cost;

  const SkinConfig({
    required this.name,
    required this.primaryColor,
    required this.secondaryColor,
    required this.type,
    required this.cost,
  });
}

// ─────────────────────────────────────────────────────────────────────────────
//  Global tuning
// ─────────────────────────────────────────────────────────────────────────────

class GameConstants {
  // Grid & movement
  static const int gridSize = 30;
  static const int initialSnakeLength = 4;
  static const int aiInitialLength = 4;

  /// Tick-interval multiplier while boosting (lower = faster).
  static const double boostInterval = 0.52;

  /// Seconds of boost available on a full bar.
  static const double boostCapacity = 3.0;

  /// Bar refill rate, in seconds-of-boost per real second.
  static const double boostRecharge = 0.55;

  /// Once drained, boost stays locked until the bar reaches this fraction.
  static const double boostMinToEngage = 0.18;

  // Combo
  /// A pellet keeps the combo alive if eaten within this many seconds.
  static const double comboWindow = 2.6;
  static const int maxCombo = 8;

  // Scoring
  static const int killScoreBonus = 400;
  static const int killScorePerSegment = 25;
  static const int goldenFoodMultiplier = 5;

  // Power-ups
  static const double powerSpawnEverySeconds = 11.0;
  static const double powerLifetimeSeconds = 9.0;
  static const int maxPowerUpsOnField = 2;
  static const double magnetRadius = 5.5;

  // Golden food
  static const double goldenChance = 0.11;
  static const double goldenLifetimeSeconds = 7.0;

  /// Invulnerability granted after a revive.
  static const double reviveGraceSeconds = 3.0;

  // Colors
  static const Color backgroundColor = Color(0xFF0B0F1A);
  static const Color accent = Color(0xFF00FF88);
  static const Color accentAlt = Color(0xFF19E3FF);
  static const Color danger = Color(0xFFFF4757);
  static const Color gold = Color(0xFFFFC53D);
  static const Color obstacleColor = Color(0xFF33405C);

  // Prefs keys
  static const String audioEnabledKey = 'AudioEnabled';
  static const String musicEnabledKey = 'MusicEnabled';
  static const String hapticsEnabledKey = 'HapticsEnabled';
  static const String coinsKey = 'Coins';
  static const String unlockedSkinsKey = 'UnlockedSkins';
  static const String currentSkinIndexKey = 'CurrentSkinIndex';
  static const String currentEyeIndexKey = 'CurrentEyeIndex';
  static const String unlockedEyesKey = 'UnlockedEyes';
  static const String customColorPrimaryKey = 'CustomColorPrimary';
  static const String customColorSecondaryKey = 'CustomColorSecondary';
  static const String useCustomColorKey = 'UseCustomColor';

  // AdMob ad units. Release builds serve live ads; debug/profile builds use
  // Google's test units so development never generates invalid traffic.
  static const String bannerAdUnitId = kReleaseMode
      ? 'ca-app-pub-9874947669431292/6958607892'
      : 'ca-app-pub-3940256099942544/6300978111';
  static const String interstitialAdUnitId = kReleaseMode
      ? 'ca-app-pub-9874947669431292/4188974326'
      : 'ca-app-pub-3940256099942544/1033173712';
  static const String rewardedAdUnitId = kReleaseMode
      ? 'ca-app-pub-9874947669431292/6815137666'
      : 'ca-app-pub-3940256099942544/5224354917';

  static const int adRewardCoins = 250;

  // Audio assets
  static const String sfxEat = 'audio/eat.wav';
  static const String sfxGolden = 'audio/golden.wav';
  static const String sfxPower = 'audio/power.wav';
  static const String sfxKill = 'audio/kill.wav';
  static const String sfxDeath = 'audio/death.wav';
  static const String sfxCombo = 'audio/combo.wav';
  static const String sfxClick = 'audio/click.wav';
  static const String bgmLoop = 'audio/bgm_loop.wav';

  static const List<SkinConfig> availableSkins = [
    SkinConfig(name: "Classic Green", primaryColor: Color(0xFF00FF88), secondaryColor: Color(0xFF00CC6A), type: SkinType.standard, cost: 0),
    SkinConfig(name: "Shadow", primaryColor: Color(0xFF7A8CA8), secondaryColor: Color(0xFF2F3B52), type: SkinType.standard, cost: 2500),
    SkinConfig(name: "Zebra", primaryColor: Color(0xFFF5F5F5), secondaryColor: Color(0xFF1A1A1A), type: SkinType.striped, cost: 3000),
    SkinConfig(name: "Blue Pixel", primaryColor: Color(0xFF448AFF), secondaryColor: Color(0xFF2962FF), type: SkinType.pixel, cost: 3000),
    SkinConfig(name: "Jungle", primaryColor: Color(0xFF9CFF57), secondaryColor: Color(0xFF1B5E20), type: SkinType.spotted, cost: 3500),
    SkinConfig(name: "Red Round", primaryColor: Color(0xFFFF5252), secondaryColor: Color(0xFFB71C1C), type: SkinType.rounded, cost: 4000),
    SkinConfig(name: "Ocean", primaryColor: Color(0xFF64FFDA), secondaryColor: Color(0xFF0D3B66), type: SkinType.patterned, cost: 4000),
    SkinConfig(name: "Inferno", primaryColor: Color(0xFFFF6D00), secondaryColor: Color(0xFF1A1A1A), type: SkinType.striped, cost: 4500),
    SkinConfig(name: "Honeycomb", primaryColor: Color(0xFFFFD700), secondaryColor: Color(0xFFC77800), type: SkinType.patterned, cost: 5000),
    SkinConfig(name: "Electric", primaryColor: Color(0xFF18FFFF), secondaryColor: Color(0xFF1A237E), type: SkinType.neon, cost: 5500),
    SkinConfig(name: "Yellow Stripe", primaryColor: Color(0xFFFFEA00), secondaryColor: Color(0xFFFF9100), type: SkinType.striped, cost: 6000),
    SkinConfig(name: "Galaxy", primaryColor: Color(0xFFFF80AB), secondaryColor: Color(0xFF4A148C), type: SkinType.neon, cost: 7000),
    SkinConfig(name: "Purple Spot", primaryColor: Color(0xFFE040FB), secondaryColor: Color(0xFF4A148C), type: SkinType.spotted, cost: 8000),
    SkinConfig(name: "Lava", primaryColor: Color(0xFFFFD54F), secondaryColor: Color(0xFF8B0000), type: SkinType.neon, cost: 8000),
    SkinConfig(name: "Diamond", primaryColor: Color(0xFFE0F7FA), secondaryColor: Color(0xFF80DEEA), type: SkinType.pixel, cost: 10000),
    SkinConfig(name: "Cool Pattern", primaryColor: Color(0xFFFFAB40), secondaryColor: Color(0xFF5D4037), type: SkinType.patterned, cost: 12000),
    SkinConfig(name: "Neon Cyber", primaryColor: Color(0xFF18FFFF), secondaryColor: Color(0xFFFF4081), type: SkinType.neon, cost: 20000),
  ];

  static const List<EyeConfig> availableEyes = [
    EyeConfig(name: "Classic", style: EyeStyle.classic, cost: 0, emoji: "👁️"),
    EyeConfig(name: "Cute", style: EyeStyle.cute, cost: 3000, emoji: "🥺"),
    EyeConfig(name: "Wink", style: EyeStyle.wink, cost: 3500, emoji: "😉"),
    EyeConfig(name: "Sleepy", style: EyeStyle.sleepy, cost: 4000, emoji: "😴"),
    EyeConfig(name: "Angry", style: EyeStyle.angry, cost: 5000, emoji: "😠"),
    EyeConfig(name: "Dizzy", style: EyeStyle.dizzy, cost: 6000, emoji: "😵"),
    EyeConfig(name: "Hearts", style: EyeStyle.heart, cost: 7500, emoji: "🥰"),
    EyeConfig(name: "Star Eyes", style: EyeStyle.star, cost: 8000, emoji: "🤩"),
    EyeConfig(name: "Cool", style: EyeStyle.cool, cost: 10000, emoji: "😎"),
    EyeConfig(name: "Neon Glow", style: EyeStyle.neon, cost: 12000, emoji: "🤖"),
  ];

  static String getEmojiForStyle(EyeStyle style) =>
      availableEyes.firstWhere((e) => e.style == style, orElse: () => availableEyes[0]).emoji;

  /// Preset colors for the custom color picker panel.
  static const List<Color> colorPresets = [
    Color(0xFF00FF88), Color(0xFF00CCFF), Color(0xFFFF4757),
    Color(0xFFFFA502), Color(0xFF7BED9F), Color(0xFFFF6B81),
    Color(0xFFA29BFE), Color(0xFFFD79A8), Color(0xFF00CEC9),
    Color(0xFFFDCB6E), Color(0xFFE17055), Color(0xFF6C5CE7),
    Color(0xFF55EFC4), Color(0xFFDFE6E9), Color(0xFF2D3436),
    Color(0xFFFFEAA7), Color(0xFFB2BEC3), Color(0xFFFF7675),
  ];

  /// Palette used to tint rivals so each one reads as a distinct threat.
  static const List<Color> rivalColors = [
    Color(0xFFFF4757), Color(0xFFFF7F50), Color(0xFFFFA502),
    Color(0xFFE1B12C), Color(0xFF9C88FF), Color(0xFF74B9FF),
    Color(0xFFFD79A8), Color(0xFF00B894),
  ];
}
