import 'dart:async';
import 'dart:math';

import 'dart:ui' show Color, Offset;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../constants.dart';
import '../services/audio_service.dart';
import '../services/haptics_service.dart';
import 'ai_brain.dart';
import 'effects.dart';
import 'missions.dart';
import 'models.dart';

export 'models.dart';

enum GamePhase { idle, playing, paused, dying, over }

/// The whole simulation plus the persisted player profile.
///
/// The simulation runs on a fixed timestep driven by [tick]; rendering
/// interpolates between ticks so the snakes glide rather than jump. Nothing in
/// here touches widgets, which keeps the rules testable in isolation.
class SnakeGame extends ChangeNotifier {
  // ── Persisted profile ────────────────────────────────────────────────
  String playerName = 'Player';
  int currentSkinIndex = 0;
  int currentEyeIndex = 0;
  int coins = 0;
  List<int> unlockedSkins = [0];
  List<int> unlockedEyes = [0];

  bool useCustomColor = false;
  Color customColorPrimary = const Color(0xFF00FF88);
  Color customColorSecondary = const Color(0xFF00CC6A);

  int highScoreEasy = 0;
  int highScoreMedium = 0;
  int highScoreHard = 0;
  String highScoreNameEasy = 'NONE';
  String highScoreNameMedium = 'NONE';
  String highScoreNameHard = 'NONE';

  // Lifetime stats
  int lifetimeGames = 0;
  int lifetimeFood = 0;
  int lifetimeKills = 0;
  int lifetimeCoins = 0;
  int lifetimeBestCombo = 1;
  int lifetimeLongestSnake = 0;
  int lifetimeSecondsPlayed = 0;

  List<Mission> missions = [];
  String _missionDate = '';

  int gamesSinceLastAd = 0;
  int _nextAdThreshold = 4;

  bool _isInitialized = false;
  bool get isInitialized => _isInitialized;

  // ── Live match state ─────────────────────────────────────────────────
  final Random _random = Random();
  late final AiBrain _brain = AiBrain(_random);

  final EffectsSystem effects = EffectsSystem();

  Snake? _player;
  Snake get playerSnake => _player ??= _spawnPlayer();
  bool get hasPlayer => _player != null;

  List<Snake> rivals = [];
  List<Food> food = [];
  List<PowerPickup> powerUps = [];
  Set<Point> obstacles = {};

  GamePhase phase = GamePhase.idle;
  Difficulty difficultyEnum = Difficulty.medium;
  DifficultyConfig difficulty = DifficultyConfig.medium;

  int score = 0;
  final RunStats run = RunStats();

  /// Live combo multiplier and how long it has left before it drops.
  int combo = 1;
  double comboTimer = 0;

  /// Boost bar, in seconds of boost remaining.
  double boostEnergy = GameConstants.boostCapacity;
  bool boostHeld = false;
  bool _boostLockedOut = false;
  bool get isBoosting => boostHeld && !_boostLockedOut && boostEnergy > 0 && phase == GamePhase.playing;

  final Map<PowerType, ActiveEffect> activeEffects = {};
  bool hasShield = false;

  /// Invulnerability window after a revive.
  double graceTimer = 0;

  bool hasUsedRevive = false;
  double elapsedSeconds = 0;
  double _powerSpawnTimer = GameConstants.powerSpawnEverySeconds;
  int _nextRivalId = 100;

  /// Rivals waiting to re-enter the arena, with the delay left before they do.
  final List<double> _respawnQueue = [];

  /// Bumped every tick; painters can use it to key animations off simulation
  /// time rather than wall-clock time.
  int tickCount = 0;

  String? lastDeathCause;

  SnakeGame() {
    unawaited(loadSettings());
  }

  // ───────────────────────────────────────────────────────────────────
  //  Derived getters
  // ───────────────────────────────────────────────────────────────────

  bool get isRunning => phase == GamePhase.playing;
  bool get isPaused => phase == GamePhase.paused;
  bool get isGameOver => phase == GamePhase.over;
  bool get isDying => phase == GamePhase.dying;

  int get currentDifficultyHighScore => switch (difficultyEnum) {
        Difficulty.easy => highScoreEasy,
        Difficulty.medium => highScoreMedium,
        Difficulty.hard => highScoreHard,
      };

  String get currentDifficultyRecordHolder => switch (difficultyEnum) {
        Difficulty.easy => highScoreNameEasy,
        Difficulty.medium => highScoreNameMedium,
        Difficulty.hard => highScoreNameHard,
      };

  int get bestScoreOverall => max(highScoreEasy, max(highScoreMedium, highScoreHard));

  int get aliveRivalCount => rivals.where((r) => r.isAlive).length;

  /// Milliseconds per tick, accounting for boost.
  int get tickIntervalMs =>
      (difficulty.tickMs * (isBoosting ? GameConstants.boostInterval : 1.0)).round();

  double get boostFraction => (boostEnergy / GameConstants.boostCapacity).clamp(0.0, 1.0);

  bool get shouldShowInterstitial => gamesSinceLastAd >= _nextAdThreshold;

  SkinConfig get currentSkin {
    final safeIndex =
        (currentSkinIndex >= 0 && currentSkinIndex < GameConstants.availableSkins.length)
            ? currentSkinIndex
            : 0;
    final base = GameConstants.availableSkins[safeIndex];
    if (!useCustomColor) return base;
    return SkinConfig(
      name: base.name,
      primaryColor: customColorPrimary,
      secondaryColor: customColorSecondary,
      type: base.type,
      cost: base.cost,
    );
  }

  EyeConfig get currentEye {
    final safeIndex =
        (currentEyeIndex >= 0 && currentEyeIndex < GameConstants.availableEyes.length)
            ? currentEyeIndex
            : 0;
    return GameConstants.availableEyes[safeIndex];
  }

  Color rivalColor(Snake s) => GameConstants.rivalColors[s.colorSlot % GameConstants.rivalColors.length];

  // ───────────────────────────────────────────────────────────────────
  //  Persistence
  // ───────────────────────────────────────────────────────────────────

  Future<void> loadSettings() async {
    final prefs = await SharedPreferences.getInstance();

    playerName = prefs.getString('player_name') ?? 'Player';
    currentSkinIndex = prefs.getInt(GameConstants.currentSkinIndexKey) ?? 0;
    currentEyeIndex = prefs.getInt(GameConstants.currentEyeIndexKey) ?? 0;
    coins = prefs.getInt(GameConstants.coinsKey) ?? 0;

    useCustomColor = prefs.getBool(GameConstants.useCustomColorKey) ?? false;
    final primary = prefs.getInt(GameConstants.customColorPrimaryKey);
    if (primary != null) customColorPrimary = Color(primary);
    final secondary = prefs.getInt(GameConstants.customColorSecondaryKey);
    if (secondary != null) customColorSecondary = Color(secondary);

    unlockedSkins = _readIntList(prefs, GameConstants.unlockedSkinsKey) ?? [0];
    unlockedEyes = _readIntList(prefs, GameConstants.unlockedEyesKey) ?? [0];
    if (!unlockedSkins.contains(0)) unlockedSkins.add(0);
    if (!unlockedEyes.contains(0)) unlockedEyes.add(0);

    highScoreEasy = prefs.getInt('high_score_easy') ?? 0;
    highScoreMedium = prefs.getInt('high_score_medium') ?? 0;
    highScoreHard = prefs.getInt('high_score_hard') ?? 0;
    highScoreNameEasy = prefs.getString('high_score_name_easy') ?? 'NONE';
    highScoreNameMedium = prefs.getString('high_score_name_medium') ?? 'NONE';
    highScoreNameHard = prefs.getString('high_score_name_hard') ?? 'NONE';

    lifetimeGames = prefs.getInt('games_played') ?? 0;
    lifetimeFood = prefs.getInt('lifetime_food') ?? 0;
    lifetimeKills = prefs.getInt('lifetime_kills') ?? 0;
    lifetimeCoins = prefs.getInt('lifetime_coins') ?? 0;
    lifetimeBestCombo = prefs.getInt('lifetime_best_combo') ?? 1;
    lifetimeLongestSnake = prefs.getInt('lifetime_longest') ?? 0;
    lifetimeSecondsPlayed = prefs.getInt('lifetime_seconds') ?? 0;

    gamesSinceLastAd = prefs.getInt('games_since_last_ad') ?? 0;
    _nextAdThreshold = prefs.getInt('next_ad_threshold') ?? (4 + _random.nextInt(2));

    final savedDifficulty = prefs.getInt('difficulty');
    if (savedDifficulty != null && savedDifficulty < Difficulty.values.length) {
      setDifficulty(Difficulty.values[savedDifficulty], notify: false);
    }

    _loadMissions(prefs);

    _isInitialized = true;
    notifyListeners();
  }

  static List<int>? _readIntList(SharedPreferences prefs, String key) {
    final raw = prefs.getStringList(key);
    if (raw == null) return null;
    final out = <int>[];
    for (final s in raw) {
      final v = int.tryParse(s);
      if (v != null) out.add(v);
    }
    return out;
  }

  void _loadMissions(SharedPreferences prefs) {
    final today = _todayKey();
    final storedDate = prefs.getString('mission_date') ?? '';
    final stored = prefs.getStringList('missions');

    if (storedDate == today && stored != null && stored.isNotEmpty) {
      missions = stored.map(Mission.decode).whereType<Mission>().toList();
      _missionDate = storedDate;
      if (missions.isNotEmpty) return;
    }

    missions = MissionFactory.forDate(DateTime.now());
    _missionDate = today;
    unawaited(_saveMissions());
  }

  static String _todayKey() {
    final now = DateTime.now();
    return '${now.year}-${now.month}-${now.day}';
  }

  /// Rolls a fresh mission set if the day changed while the app was open.
  void refreshMissionsIfNeeded() {
    final today = _todayKey();
    if (today == _missionDate) return;
    missions = MissionFactory.forDate(DateTime.now());
    _missionDate = today;
    unawaited(_saveMissions());
    notifyListeners();
  }

  Future<void> _saveMissions() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('mission_date', _missionDate);
    await prefs.setStringList('missions', missions.map((m) => m.encode()).toList());
  }

  Future<void> saveSettings() async {
    if (!_isInitialized) return;
    final prefs = await SharedPreferences.getInstance();

    await prefs.setString('player_name', playerName);
    await prefs.setInt(GameConstants.currentSkinIndexKey, currentSkinIndex);
    await prefs.setInt(GameConstants.currentEyeIndexKey, currentEyeIndex);
    await prefs.setInt(GameConstants.coinsKey, coins);
    await prefs.setBool(GameConstants.useCustomColorKey, useCustomColor);
    await prefs.setInt(GameConstants.customColorPrimaryKey, customColorPrimary.toARGB32());
    await prefs.setInt(GameConstants.customColorSecondaryKey, customColorSecondary.toARGB32());
    await prefs.setStringList(
        GameConstants.unlockedSkinsKey, unlockedSkins.map((e) => e.toString()).toList());
    await prefs.setStringList(
        GameConstants.unlockedEyesKey, unlockedEyes.map((e) => e.toString()).toList());
    await prefs.setInt('difficulty', difficultyEnum.index);

    await prefs.setInt('games_played', lifetimeGames);
    await prefs.setInt('lifetime_food', lifetimeFood);
    await prefs.setInt('lifetime_kills', lifetimeKills);
    await prefs.setInt('lifetime_coins', lifetimeCoins);
    await prefs.setInt('lifetime_best_combo', lifetimeBestCombo);
    await prefs.setInt('lifetime_longest', lifetimeLongestSnake);
    await prefs.setInt('lifetime_seconds', lifetimeSecondsPlayed);
    await prefs.setInt('games_since_last_ad', gamesSinceLastAd);
    await prefs.setInt('next_ad_threshold', _nextAdThreshold);
  }

  Future<void> _persistHighScore() async {
    final prefs = await SharedPreferences.getInstance();
    switch (difficultyEnum) {
      case Difficulty.easy:
        if (score > highScoreEasy) {
          highScoreEasy = score;
          highScoreNameEasy = playerName;
          await prefs.setInt('high_score_easy', highScoreEasy);
          await prefs.setString('high_score_name_easy', highScoreNameEasy);
        }
      case Difficulty.medium:
        if (score > highScoreMedium) {
          highScoreMedium = score;
          highScoreNameMedium = playerName;
          await prefs.setInt('high_score_medium', highScoreMedium);
          await prefs.setString('high_score_name_medium', highScoreNameMedium);
        }
      case Difficulty.hard:
        if (score > highScoreHard) {
          highScoreHard = score;
          highScoreNameHard = playerName;
          await prefs.setInt('high_score_hard', highScoreHard);
          await prefs.setString('high_score_name_hard', highScoreNameHard);
        }
    }
  }

  // ───────────────────────────────────────────────────────────────────
  //  Economy & cosmetics
  // ───────────────────────────────────────────────────────────────────

  void addCoins(int amount) {
    coins += amount;
    lifetimeCoins += amount;
    unawaited(saveSettings());
    notifyListeners();
  }

  /// Commits a cosmetic selection made in the customisation screen.
  void applyCosmetics({
    required int skinIndex,
    required int eyeIndex,
    required bool useCustom,
    required Color primary,
    required Color secondary,
  }) {
    currentSkinIndex = skinIndex;
    currentEyeIndex = eyeIndex;
    useCustomColor = useCustom;
    customColorPrimary = primary;
    customColorSecondary = secondary;
    unawaited(saveSettings());
    notifyListeners();
  }

  bool unlockSkin(int index, int cost) {
    if (coins < cost || unlockedSkins.contains(index)) return false;
    coins -= cost;
    unlockedSkins.add(index);
    unawaited(saveSettings());
    notifyListeners();
    return true;
  }

  bool unlockEye(int index, int cost) {
    if (coins < cost || unlockedEyes.contains(index)) return false;
    coins -= cost;
    unlockedEyes.add(index);
    unawaited(saveSettings());
    notifyListeners();
    return true;
  }

  /// Grants a completed mission's reward. Returns false if it was not claimable.
  bool claimMission(Mission mission) {
    if (!mission.isComplete || mission.claimed) return false;
    mission.claimed = true;
    coins += mission.reward;
    lifetimeCoins += mission.reward;
    unawaited(_saveMissions());
    unawaited(saveSettings());
    notifyListeners();
    return true;
  }

  void setDifficulty(Difficulty d, {bool notify = true}) {
    difficultyEnum = d;
    difficulty = DifficultyConfig.of(d);
    if (notify) {
      unawaited(saveSettings());
      notifyListeners();
    }
  }

  void markInterstitialShown() {
    gamesSinceLastAd = 0;
    _nextAdThreshold = 4 + _random.nextInt(2);
    unawaited(saveSettings());
  }

  // ───────────────────────────────────────────────────────────────────
  //  Match lifecycle
  // ───────────────────────────────────────────────────────────────────

  void startGame() {
    lifetimeGames++;
    gamesSinceLastAd++;

    score = 0;
    run.reset();
    combo = 1;
    comboTimer = 0;
    elapsedSeconds = 0;
    tickCount = 0;
    boostEnergy = GameConstants.boostCapacity;
    boostHeld = false;
    _boostLockedOut = false;
    hasUsedRevive = false;
    hasShield = false;
    graceTimer = 0;
    lastDeathCause = null;
    activeEffects.clear();
    effects.clear();
    _respawnQueue.clear();
    _powerSpawnTimer = GameConstants.powerSpawnEverySeconds;
    powerUps.clear();
    food.clear();
    _inputQueue.clear(); // a turn queued in the last match must not carry over

    _generateObstacles();
    _player = _spawnPlayer();

    rivals = [];
    for (var i = 0; i < difficulty.aiCount; i++) {
      rivals.add(_spawnRival(colorSlot: i));
    }

    _refillFood(initial: true);

    phase = GamePhase.playing;
    unawaited(saveSettings());
    notifyListeners();
  }

  void reset() => startGame();

  void togglePause() {
    if (phase == GamePhase.playing) {
      phase = GamePhase.paused;
      boostHeld = false;
    } else if (phase == GamePhase.paused) {
      phase = GamePhase.playing;
    } else {
      return;
    }
    notifyListeners();
  }

  void pauseIfPlaying() {
    if (phase == GamePhase.playing) {
      phase = GamePhase.paused;
      boostHeld = false;
      notifyListeners();
    }
  }

  /// Brings the player back once per match, with a grace window and the
  /// immediate area cleared so they are not killed again on the next tick.
  void revive() {
    if (phase != GamePhase.over || hasUsedRevive) return;

    hasUsedRevive = true;
    phase = GamePhase.playing;
    graceTimer = GameConstants.reviveGraceSeconds;
    combo = 1;
    comboTimer = 0;
    boostEnergy = GameConstants.boostCapacity;
    _boostLockedOut = false;

    final p = playerSnake;
    p.isAlive = true;

    // Trim back to a manageable length so the body itself is not a death trap.
    if (p.body.length > 6) {
      p.body = p.body.sublist(0, 6);
    }
    p.pendingGrowth = 0;

    // Clear rivals and obstacles crowding the respawn point.
    final head = p.head;
    for (final r in rivals) {
      if (r.isAlive && r.head.wrappedDistanceTo(head) < 7) {
        r.isAlive = false;
        _queueRespawn(1.5);
      }
    }
    rivals.removeWhere((r) => !r.isAlive);
    obstacles.removeWhere((o) => o.wrappedDistanceTo(head) < 4);

    effects.ring(head.x + 0.5, head.y + 0.5, GameConstants.accentAlt, radius: 9, duration: 0.7);
    effects.flash(GameConstants.accentAlt.withValues(alpha: 0.35), duration: 0.4);

    notifyListeners();
  }

  Snake _spawnPlayer() {
    const mid = GameConstants.gridSize ~/ 2;
    const dir = Direction.right;
    final body = List<Point>.generate(
      GameConstants.initialSnakeLength,
      (i) => Point(mid - i, mid),
    );
    return Snake(body: body, direction: dir, id: 0, isPlayer: true);
  }

  Snake _spawnRival({int? colorSlot}) {
    const n = GameConstants.gridSize;
    final id = _nextRivalId++;

    // Try a few spots so rivals do not materialise on top of anything.
    Point start = const Point(0, 0);
    Direction dir = Direction.right;
    for (var attempt = 0; attempt < 40; attempt++) {
      final side = _random.nextInt(4);
      switch (side) {
        case 0:
          start = Point(_random.nextInt(n), 1);
          dir = Direction.down;
        case 1:
          start = Point(_random.nextInt(n), n - 2);
          dir = Direction.up;
        case 2:
          start = Point(1, _random.nextInt(n));
          dir = Direction.right;
        default:
          start = Point(n - 2, _random.nextInt(n));
          dir = Direction.left;
      }
      if (_player != null && start.wrappedDistanceTo(_player!.head) < 8) continue;
      if (_isOccupied(start)) continue;
      break;
    }

    final body = <Point>[];
    for (var i = 0; i < GameConstants.aiInitialLength; i++) {
      body.add(Point(
        (start.x - dir.dx * i + n) % n,
        (start.y - dir.dy * i + n) % n,
      ));
    }

    final roll = _random.nextDouble();
    final AiPersonality personality;
    if (roll < difficulty.aiAggression * 0.6) {
      personality = AiPersonality.hunter;
    } else if (roll < difficulty.aiAggression) {
      personality = AiPersonality.bully;
    } else if (roll > 0.88) {
      personality = AiPersonality.coward;
    } else {
      personality = AiPersonality.forager;
    }

    return Snake(
      body: body,
      direction: dir,
      id: id,
      personality: personality,
      colorSlot: colorSlot ?? _random.nextInt(GameConstants.rivalColors.length),
    );
  }

  void _generateObstacles() {
    obstacles = {};
    final count = difficulty.obstacleCount;
    if (count == 0) return;

    const n = GameConstants.gridSize;
    const mid = n ~/ 2;
    var placed = 0;
    var guard = 0;

    while (placed < count && guard++ < 400) {
      final x = 3 + _random.nextInt(n - 6);
      final y = 3 + _random.nextInt(n - 6);
      final p = Point(x, y);
      // Keep the player's spawn lane and the arena centre clear.
      if ((x - mid).abs() < 5 && (y - mid).abs() < 3) continue;
      if (obstacles.contains(p)) continue;

      // Short bars read better than lone dots.
      final horizontal = _random.nextBool();
      final len = 2 + _random.nextInt(2);
      final cells = <Point>[];
      var ok = true;
      for (var i = 0; i < len; i++) {
        final c = Point(horizontal ? x + i : x, horizontal ? y : y + i);
        if (c.x >= n - 2 || c.y >= n - 2) {
          ok = false;
          break;
        }
        if ((c.x - mid).abs() < 5 && (c.y - mid).abs() < 3) {
          ok = false;
          break;
        }
        cells.add(c);
      }
      if (!ok) continue;
      obstacles.addAll(cells);
      placed++;
    }
  }

  // ───────────────────────────────────────────────────────────────────
  //  Input
  // ───────────────────────────────────────────────────────────────────

  /// Buffered turn inputs. Without a queue, two quick swipes inside one tick
  /// would overwrite each other and the second turn would be swallowed.
  final List<Direction> _inputQueue = [];

  void changeDirection(Direction newDirection) {
    if (phase != GamePhase.playing) return;

    final reference = _inputQueue.isNotEmpty ? _inputQueue.last : playerSnake.direction;
    if (newDirection == reference || newDirection == reference.opposite) return;

    if (_inputQueue.length >= 2) _inputQueue.removeAt(0);
    _inputQueue.add(newDirection);
  }

  void setBoost(bool held) {
    if (boostHeld == held) return;
    boostHeld = held;
    notifyListeners();
  }

  // ───────────────────────────────────────────────────────────────────
  //  Simulation
  // ───────────────────────────────────────────────────────────────────

  /// Advances continuous state (timers, boost, effects). Called every frame.
  void updateContinuous(double dt) {
    if (phase == GamePhase.playing) {
      elapsedSeconds += dt;
      run.survivedSeconds = elapsedSeconds;

      if (graceTimer > 0) graceTimer = max(0, graceTimer - dt);

      // Boost drain / recharge.
      if (isBoosting) {
        boostEnergy = max(0, boostEnergy - dt);
        if (boostEnergy <= 0) _boostLockedOut = true;
      } else {
        boostEnergy = min(GameConstants.boostCapacity, boostEnergy + dt * GameConstants.boostRecharge);
        if (_boostLockedOut && boostFraction >= GameConstants.boostMinToEngage) {
          _boostLockedOut = false;
        }
      }

      // Combo decay.
      if (comboTimer > 0) {
        comboTimer = max(0, comboTimer - dt);
        if (comboTimer == 0 && combo > 1) {
          combo = 1;
          notifyListeners();
        }
      }

      // Power-up effect timers.
      if (activeEffects.isNotEmpty) {
        final expired = <PowerType>[];
        for (final e in activeEffects.values) {
          e.remaining -= dt;
          if (e.remaining <= 0) expired.add(e.type);
        }
        for (final t in expired) {
          activeEffects.remove(t);
        }
        if (expired.isNotEmpty) notifyListeners();
      }

      // Field pickups age out.
      for (var i = powerUps.length - 1; i >= 0; i--) {
        powerUps[i].ttl -= dt;
        if (powerUps[i].ttl <= 0) powerUps.removeAt(i);
      }
      for (var i = food.length - 1; i >= 0; i--) {
        final ttl = food[i].ttl;
        if (ttl == null) continue;
        food[i].ttl = ttl - dt;
        if (food[i].ttl! <= 0) food.removeAt(i);
      }

      // Periodic power-up spawn.
      _powerSpawnTimer -= dt;
      if (_powerSpawnTimer <= 0) {
        _powerSpawnTimer = GameConstants.powerSpawnEverySeconds;
        if (powerUps.length < GameConstants.maxPowerUpsOnField) _spawnPowerUp();
      }

      // Rival respawn timers.
      for (var i = _respawnQueue.length - 1; i >= 0; i--) {
        _respawnQueue[i] -= dt;
        if (_respawnQueue[i] <= 0) {
          _respawnQueue.removeAt(i);
          if (rivals.length < difficulty.aiCount) {
            rivals.add(_spawnRival());
          }
        }
      }
    }

    effects.update(dt);
  }

  /// One fixed simulation step.
  void tick() {
    if (phase != GamePhase.playing) return;
    tickCount++;

    final player = playerSnake;

    // Apply one buffered turn per tick so inputs cannot stack into a 180.
    if (_inputQueue.isNotEmpty) {
      final next = _inputQueue.removeAt(0);
      if (next != player.direction.opposite) player.direction = next;
    }

    // Rivals decide.
    _brain.beginTick(player: player, rivals: rivals, obstacles: obstacles);
    for (final r in rivals) {
      if (!r.isAlive) continue;
      if (r.frozenTicks > 0) {
        r.frozenTicks--;
        continue;
      }
      r.direction = _brain.chooseDirection(
        ai: r,
        player: player,
        rivals: rivals,
        food: food,
        powerUps: powerUps,
        skill: difficulty.aiSkill,
      );
    }

    // Move heads.
    player.advance();
    for (final r in rivals) {
      if (r.isAlive && r.frozenTicks == 0) r.advance();
    }

    if (isBoosting) {
      effects.boostTrail(player.head.x + 0.5, player.head.y + 0.5, currentSkin.primaryColor);
    }

    _applyMagnet();
    _resolvePickups();

    // Trim tails.
    player.settle();
    for (final r in rivals) {
      if (r.isAlive && r.frozenTicks == 0) r.settle();
    }

    _resolveCollisions();
    _refillFood();

    run.maxLength = max(run.maxLength, player.body.length);
    notifyListeners();
  }

  /// Nudges nearby pellets one cell toward the player while MAGNET is up.
  void _applyMagnet() {
    if (!activeEffects.containsKey(PowerType.magnet)) return;
    final head = playerSnake.head;

    for (final f in food) {
      final d = f.pos.wrappedDistanceTo(head);
      if (d == 0 || d > GameConstants.magnetRadius) continue;

      const n = GameConstants.gridSize;
      // Move along the shorter wrapped axis.
      var dx = head.x - f.pos.x;
      var dy = head.y - f.pos.y;
      if (dx.abs() > n ~/ 2) dx = dx > 0 ? dx - n : dx + n;
      if (dy.abs() > n ~/ 2) dy = dy > 0 ? dy - n : dy + n;

      final stepX = dx.abs() >= dy.abs() ? dx.sign : 0;
      final stepY = dx.abs() >= dy.abs() ? 0 : dy.sign;
      final next = Point((f.pos.x + stepX + n) % n, (f.pos.y + stepY + n) % n);
      if (obstacles.contains(next)) continue;
      f.pos = next;
    }
  }

  void _resolvePickups() {
    final player = playerSnake;

    // ── Player food ──
    for (var i = food.length - 1; i >= 0; i--) {
      if (food[i].pos != player.head) continue;
      final f = food.removeAt(i);
      _consumeFood(f, player);
      break;
    }

    // ── Player power-ups ──
    for (var i = powerUps.length - 1; i >= 0; i--) {
      if (powerUps[i].pos != player.head) continue;
      final p = powerUps.removeAt(i);
      _collectPower(p.type);
      break;
    }

    // ── Rival food (rivals ignore power-ups' effects, they just clear them) ──
    for (final r in rivals) {
      if (!r.isAlive) continue;
      for (var i = food.length - 1; i >= 0; i--) {
        if (food[i].pos != r.head) continue;
        food.removeAt(i);
        r.pendingGrowth += 1;
        break;
      }
      for (var i = powerUps.length - 1; i >= 0; i--) {
        if (powerUps[i].pos != r.head) continue;
        powerUps.removeAt(i);
        r.pendingGrowth += 1;
        break;
      }
    }
  }

  void _consumeFood(Food f, Snake player) {
    // Combo: chain pellets inside the window to multiply the payout.
    if (comboTimer > 0) {
      combo = min(GameConstants.maxCombo, combo + 1);
    } else {
      combo = 1;
    }
    comboTimer = GameConstants.comboWindow;

    final frenzy = activeEffects.containsKey(PowerType.frenzy) ? 2 : 1;
    final gained = (difficulty.foodPoints * f.valueMultiplier * combo * frenzy).round();

    score += gained;
    final coinsGained = (difficulty.coinPerFood * f.valueMultiplier).round();
    coins += coinsGained;
    lifetimeCoins += coinsGained;

    run.score = score;
    run.coins += coinsGained;
    run.foodEaten++;
    if (f.isGolden) run.goldenEaten++;
    run.bestCombo = max(run.bestCombo, combo);

    player.pendingGrowth += f.isGolden ? 3 : 1;

    // ── Feedback ──
    final cx = f.pos.x + 0.5;
    final cy = f.pos.y + 0.5;
    final color = f.isGolden ? GameConstants.gold : const Color(0xFFFFB733);

    effects.burst(cx, cy, color, count: f.isGolden ? 20 : 9, glow: f.isGolden);
    effects.popup(cx, cy, '+$gained', color, fontSize: f.isGolden ? 17 : 13);

    if (combo >= 3) {
      effects.popup(cx, cy - 0.9, 'x$combo', GameConstants.accentAlt, fontSize: 12);
    }

    if (f.isGolden) {
      effects.ring(cx, cy, GameConstants.gold, radius: 5, duration: 0.45);
      effects.shake(0.22);
      AudioService().playSfx(GameConstants.sfxGolden);
      HapticsService().medium();
    } else if (combo >= 4) {
      AudioService().playSfx(GameConstants.sfxCombo);
      HapticsService().light();
    } else {
      AudioService().playSfx(GameConstants.sfxEat);
      HapticsService().selection();
    }
  }

  void _collectPower(PowerType type) {
    run.powerUpsCollected++;
    final cfg = PowerConfig.of(type);

    if (type == PowerType.shield) {
      hasShield = true;
    } else if (type == PowerType.freeze) {
      final ticks = (cfg.seconds * 1000 / difficulty.tickMs).round();
      for (final r in rivals) {
        r.frozenTicks = ticks;
      }
      activeEffects[type] = ActiveEffect(type, cfg.seconds);
    } else {
      activeEffects[type] = ActiveEffect(type, cfg.seconds);
    }

    final head = playerSnake.head;
    effects.burst(head.x + 0.5, head.y + 0.5, cfg.color, count: 22, speed: 6, glow: true);
    effects.ring(head.x + 0.5, head.y + 0.5, cfg.color, radius: 7, duration: 0.55);
    effects.popup(head.x + 0.5, head.y - 0.6, cfg.name, cfg.color, fontSize: 15);
    effects.flash(cfg.color.withValues(alpha: 0.22), duration: 0.3);
    effects.shake(0.25);

    AudioService().playSfx(GameConstants.sfxPower);
    HapticsService().medium();
    notifyListeners();
  }

  /// Decides who dies this tick. Deaths are computed against a single snapshot
  /// and applied together, so two snakes meeting head-on resolve symmetrically.
  void _resolveCollisions() {
    final player = playerSnake;
    final phasing = activeEffects.containsKey(PowerType.phase);
    final invulnerable = phasing || graceTimer > 0;

    final all = <Snake>[player, ...rivals.where((r) => r.isAlive)];

    // Map every occupied cell to the snakes standing on it.
    final bodyOwners = <Point, List<Snake>>{};
    for (final s in all) {
      for (var i = 0; i < s.body.length; i++) {
        bodyOwners.putIfAbsent(s.body[i], () => []).add(s);
      }
    }

    final doomed = <Snake, Snake?>{}; // victim -> killer (null = self/obstacle)

    for (final s in all) {
      // PHASE and the post-revive grace window make the player immune to every
      // death cause, including walls, so they always get a way out.
      if (s.isPlayer && invulnerable) continue;

      final head = s.head;

      if (obstacles.contains(head)) {
        doomed[s] = null;
        continue;
      }

      if (s.hitsSelf) {
        doomed[s] = null;
        continue;
      }

      final owners = bodyOwners[head];
      for (final other in all) {
        if (identical(other, s)) continue;

        // A player who is phasing is not a wall for anyone else either.
        if (other.isPlayer && phasing) continue;

        if (other.head == head) {
          // Head-on: the longer snake wins, equal lengths take each other out.
          if (s.length <= other.length) doomed[s] = other;
          continue;
        }

        // Running into a body kills the runner and credits the body's owner.
        if (owners != null && owners.contains(other)) {
          doomed[s] = other;
          break;
        }
      }
    }

    if (doomed.isEmpty) return;

    var playerDied = false;
    for (final entry in doomed.entries) {
      final victim = entry.key;
      final killer = entry.value;

      if (victim.isPlayer) {
        if (hasShield) {
          // Burn the shield and hand out a short grace window instead of the
          // death, which is what lets the player steer back out of the pile-up.
          hasShield = false;
          graceTimer = max(graceTimer, 1.4);
          final shieldColor = PowerConfig.of(PowerType.shield).color;
          effects.ring(victim.head.x + 0.5, victim.head.y + 0.5, shieldColor,
              radius: 8, duration: 0.6);
          effects.flash(shieldColor.withValues(alpha: 0.3));
          effects.shake(0.4);
          effects.popup(victim.head.x + 0.5, victim.head.y - 0.8, 'SHIELD USED', shieldColor);
          AudioService().playSfx(GameConstants.sfxPower);
          HapticsService().heavy();
          continue;
        }
        playerDied = true;
        lastDeathCause = killer == null
            ? (obstacles.contains(victim.head) ? 'Hit a wall block' : 'Bit your own tail')
            : 'Crashed into a rival';
      } else {
        _destroyRival(victim, killedByPlayer: killer != null && killer.isPlayer);
      }
    }

    rivals.removeWhere((r) => !r.isAlive);

    if (playerDied) _gameOver();
  }

  void _destroyRival(Snake rival, {required bool killedByPlayer}) {
    if (!rival.isAlive) return;
    rival.isAlive = false;

    final color = rivalColor(rival);

    if (killedByPlayer) {
      final bonus = GameConstants.killScoreBonus + rival.length * GameConstants.killScorePerSegment;
      score += bonus;
      coins += difficulty.coinPerKill;
      lifetimeCoins += difficulty.coinPerKill;
      run.score = score;
      run.kills++;
      run.coins += difficulty.coinPerKill;

      effects.popup(rival.head.x + 0.5, rival.head.y - 0.5, 'KILL +$bonus', GameConstants.danger,
          fontSize: 16);
      effects.ring(rival.head.x + 0.5, rival.head.y + 0.5, color, radius: 9, duration: 0.55);
      effects.shake(0.55);
      effects.flash(color.withValues(alpha: 0.18), duration: 0.25);

      AudioService().playSfx(GameConstants.sfxKill);
      HapticsService().heavy();
    }

    effects.explodeAlong(
      rival.body.map((p) => Offset(p.x + 0.5, p.y + 0.5)).toList(),
      color,
    );

    // A destroyed snake leaves its body behind as scavengeable food.
    for (final segment in rival.body) {
      if (_isOccupied(segment) || obstacles.contains(segment)) continue;
      if (food.length > 70) break;
      food.add(Food(segment, FoodKind.corpse, phase: _random.nextDouble()));
    }

    _queueRespawn(2.0 + _random.nextDouble() * 1.5);
  }

  void _queueRespawn(double delay) => _respawnQueue.add(delay);

  void _gameOver() {
    if (phase == GamePhase.dying || phase == GamePhase.over) return;

    phase = GamePhase.dying;
    boostHeld = false;

    final p = playerSnake;
    effects.explodeAlong(
      p.body.map((q) => Offset(q.x + 0.5, q.y + 0.5)).toList(),
      currentSkin.primaryColor,
    );
    effects.ring(p.head.x + 0.5, p.head.y + 0.5, GameConstants.danger, radius: 12, duration: 0.8);
    effects.shake(1.0);
    effects.flash(GameConstants.danger.withValues(alpha: 0.4), duration: 0.5);

    AudioService().playSfx(GameConstants.sfxDeath);
    HapticsService().heavy();

    notifyListeners();

    Future.delayed(const Duration(milliseconds: 700), () {
      if (phase != GamePhase.dying) return;
      phase = GamePhase.over;
      _finalizeRun();
      notifyListeners();
    });
  }

  void _finalizeRun() {
    run.score = score;
    run.survivedSeconds = elapsedSeconds;

    lifetimeFood += run.foodEaten;
    lifetimeKills += run.kills;
    lifetimeBestCombo = max(lifetimeBestCombo, run.bestCombo);
    lifetimeLongestSnake = max(lifetimeLongestSnake, run.maxLength);
    lifetimeSecondsPlayed += elapsedSeconds.round();

    _applyMissionProgress();
    unawaited(_persistHighScore());
    unawaited(saveSettings());
  }

  void _applyMissionProgress() {
    var changed = false;
    for (final m in missions) {
      if (m.claimed) continue;
      final value = switch (m.metric) {
        MissionMetric.foodEaten => run.foodEaten,
        MissionMetric.kills => run.kills,
        MissionMetric.score => run.score,
        MissionMetric.survivalSeconds => run.survivedSeconds.round(),
        MissionMetric.bestCombo => run.bestCombo,
        MissionMetric.powerUps => run.powerUpsCollected,
        MissionMetric.goldenFood => run.goldenEaten,
      };
      if (value <= 0) continue;

      // Single-run missions track the best run; the rest accumulate.
      final next = m.singleRun ? max(m.progress, value) : m.progress + value;
      if (next != m.progress) {
        m.progress = next;
        changed = true;
      }
    }
    if (changed) unawaited(_saveMissions());
  }

  /// Missions completed but not yet claimed — surfaced on the game-over screen.
  List<Mission> get claimableMissions =>
      missions.where((m) => m.isComplete && !m.claimed).toList();

  // ───────────────────────────────────────────────────────────────────
  //  Spawning helpers
  // ───────────────────────────────────────────────────────────────────

  bool _isOccupied(Point p) {
    if (_player != null && _player!.occupies(p)) return true;
    for (final r in rivals) {
      if (r.isAlive && r.occupies(p)) return true;
    }
    if (obstacles.contains(p)) return true;
    for (final f in food) {
      if (f.pos == p) return true;
    }
    for (final u in powerUps) {
      if (u.pos == p) return true;
    }
    return false;
  }

  Point? _findFreeCell() {
    for (var attempt = 0; attempt < 120; attempt++) {
      final p = Point(
        _random.nextInt(GameConstants.gridSize),
        _random.nextInt(GameConstants.gridSize),
      );
      if (!_isOccupied(p)) return p;
    }
    return null;
  }

  void _refillFood({bool initial = false}) {
    // Corpse pellets already litter the arena, so only top up real food.
    final proper = food.where((f) => f.kind != FoodKind.corpse).length;
    var needed = difficulty.foodTarget - proper;
    if (needed <= 0) return;
    if (!initial) needed = min(needed, 2); // drip-feed during play

    for (var i = 0; i < needed; i++) {
      final pos = _findFreeCell();
      if (pos == null) return;

      final golden = !initial && _random.nextDouble() < GameConstants.goldenChance;
      food.add(Food(
        pos,
        golden ? FoodKind.golden : FoodKind.normal,
        ttl: golden ? GameConstants.goldenLifetimeSeconds : null,
        phase: _random.nextDouble(),
      ));

      if (golden) {
        effects.ring(pos.x + 0.5, pos.y + 0.5, GameConstants.gold, radius: 3.5, duration: 0.6);
      }
    }
  }

  void _spawnPowerUp() {
    final pos = _findFreeCell();
    if (pos == null) return;

    // Do not offer a second shield while one is already banked.
    final options = PowerType.values.where((t) => !(t == PowerType.shield && hasShield)).toList();
    final type = options[_random.nextInt(options.length)];

    powerUps.add(PowerPickup(
      pos,
      type,
      GameConstants.powerLifetimeSeconds,
      phase: _random.nextDouble(),
    ));
    effects.ring(pos.x + 0.5, pos.y + 0.5, PowerConfig.of(type).color, radius: 4, duration: 0.6);
  }

  @override
  void dispose() {
    effects.clear();
    super.dispose();
  }
}
