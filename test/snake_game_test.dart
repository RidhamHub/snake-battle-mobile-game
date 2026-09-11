import 'dart:ui' show Color;

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:snake_battle/constants.dart';
import 'package:snake_battle/game/missions.dart';
import 'package:snake_battle/game/snake_game.dart';

/// Builds a game with a loaded (empty) profile and a started match.
Future<SnakeGame> newGame({Difficulty difficulty = Difficulty.medium}) async {
  SharedPreferences.setMockInitialValues({
    GameConstants.hapticsEnabledKey: false,
    GameConstants.audioEnabledKey: false,
    GameConstants.musicEnabledKey: false,
  });
  final game = SnakeGame();
  await game.loadSettings();
  game.setDifficulty(difficulty, notify: false);
  game.startGame();
  return game;
}

/// Clears the arena so a test can set up an exact scenario.
void isolateArena(SnakeGame game) {
  game.rivals.clear();
  game.food.clear();
  game.powerUps.clear();
  game.obstacles.clear();
}

/// Coils the player so its very next step lands on a mid-body segment.
///
/// Note the shape has to be long enough that the cell being entered is NOT the
/// tail: a snake is allowed to move into the square its tail is vacating, so a
/// short hook is a legal move rather than a crash.
void coilPlayerIntoSelfCrash(SnakeGame game) {
  game.playerSnake.body = [
    const Point(6, 5),
    const Point(6, 6),
    const Point(7, 6),
    const Point(7, 5), // <- the head steps here next tick
    const Point(8, 5),
    const Point(9, 5),
  ];
  game.playerSnake.direction = Direction.right;
  game.playerSnake.pendingGrowth = 0;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Point', () {
    test('wraps around the arena edges', () {
      const topLeft = Point(0, 0);
      expect(topLeft.moveWrapped(Direction.left),
          const Point(GameConstants.gridSize - 1, 0));
      expect(topLeft.moveWrapped(Direction.up),
          const Point(0, GameConstants.gridSize - 1));

      const bottomRight =
          Point(GameConstants.gridSize - 1, GameConstants.gridSize - 1);
      expect(bottomRight.moveWrapped(Direction.right), const Point(0, GameConstants.gridSize - 1));
      expect(bottomRight.moveWrapped(Direction.down), const Point(GameConstants.gridSize - 1, 0));
    });

    test('distance takes the short way around the wrap', () {
      // 1 step apart through the left/right edge, not 29 across the board.
      expect(const Point(0, 5).wrappedDistanceTo(const Point(29, 5)), 1);
      expect(const Point(0, 0).wrappedDistanceTo(const Point(29, 29)), 2);
      expect(const Point(3, 3).wrappedDistanceTo(const Point(6, 7)), 7);
    });

    test('equal points share a hash bucket', () {
      expect(const Point(4, 7), const Point(4, 7));
      expect(const Point(4, 7).hashCode, const Point(4, 7).hashCode);
      expect(const Point(4, 7) == const Point(7, 4), isFalse);
    });
  });

  group('Snake movement', () {
    test('advance/settle keeps length constant when not growing', () {
      final snake = Snake(
        body: [const Point(5, 5), const Point(4, 5), const Point(3, 5)],
        direction: Direction.right,
        id: 1,
      );

      snake.advance();
      expect(snake.body.length, 4, reason: 'head is pushed before the tail is trimmed');
      snake.settle();

      expect(snake.body.length, 3);
      expect(snake.head, const Point(6, 5));
      expect(snake.body.last, const Point(4, 5));
      expect(snake.prevTail, const Point(3, 5));
    });

    test('pending growth holds the tail in place for one step', () {
      final snake = Snake(
        body: [const Point(5, 5), const Point(4, 5)],
        direction: Direction.right,
        id: 1,
        pendingGrowth: 2,
      );

      snake.advance();
      snake.settle();
      expect(snake.body.length, 3);
      expect(snake.pendingGrowth, 1);

      snake.advance();
      snake.settle();
      expect(snake.body.length, 4);
      expect(snake.pendingGrowth, 0);

      snake.advance();
      snake.settle();
      expect(snake.body.length, 4, reason: 'growth is spent, back to trimming');
    });

    test('detects running into its own body', () {
      final snake = Snake(
        body: [const Point(5, 5), const Point(5, 5)],
        direction: Direction.right,
        id: 1,
      );
      expect(snake.hitsSelf, isTrue);

      final clear = Snake(
        body: [const Point(5, 5), const Point(4, 5)],
        direction: Direction.right,
        id: 1,
      );
      expect(clear.hitsSelf, isFalse);
    });
  });

  group('Input', () {
    test('ignores a straight reversal', () async {
      final game = await newGame();
      game.playerSnake.direction = Direction.right;

      game.changeDirection(Direction.left);
      game.tick();

      expect(game.playerSnake.direction, Direction.right);
    });

    test('queues two turns so a fast corner is not swallowed', () async {
      final game = await newGame();
      isolateArena(game);
      game.playerSnake.direction = Direction.right;

      // Both swipes land inside a single tick.
      game.changeDirection(Direction.up);
      game.changeDirection(Direction.left);

      game.tick();
      expect(game.playerSnake.direction, Direction.up);

      game.tick();
      expect(game.playerSnake.direction, Direction.left,
          reason: 'the buffered second turn applies on the next tick');
    });

    test('drops a queued turn that would become a reversal', () async {
      final game = await newGame();
      game.playerSnake.direction = Direction.right;

      game.changeDirection(Direction.up);
      game.changeDirection(Direction.down); // reverses the queued up
      game.tick();
      game.tick();

      expect(game.playerSnake.direction, Direction.up);
    });
  });

  group('Food and scoring', () {
    test('eating grows the snake and pays score plus coins', () async {
      final game = await newGame();
      isolateArena(game);

      final startCoins = game.coins;
      final startLength = game.playerSnake.body.length;

      final ahead = game.playerSnake.head.moveWrapped(game.playerSnake.direction);
      game.food.add(Food(ahead, FoodKind.normal));

      game.tick();

      expect(game.run.foodEaten, 1);
      expect(game.score, DifficultyConfig.medium.foodPoints);
      expect(game.coins, startCoins + DifficultyConfig.medium.coinPerFood);

      game.tick();
      expect(game.playerSnake.body.length, startLength + 1);
    });

    test('golden food is worth the configured multiple', () async {
      final game = await newGame();
      isolateArena(game);

      final ahead = game.playerSnake.head.moveWrapped(game.playerSnake.direction);
      game.food.add(Food(ahead, FoodKind.golden, ttl: 5));

      game.tick();

      expect(game.run.goldenEaten, 1);
      expect(
        game.score,
        DifficultyConfig.medium.foodPoints * GameConstants.goldenFoodMultiplier,
      );
    });

    test('combo multiplies consecutive pellets and then expires', () async {
      final game = await newGame();
      isolateArena(game);

      // Lay a straight line of pellets in front of the snake.
      var p = game.playerSnake.head;
      for (var i = 0; i < 3; i++) {
        p = p.moveWrapped(Direction.right);
        game.food.add(Food(p, FoodKind.normal));
      }

      const base = 15; // medium foodPoints
      game.tick();
      expect(game.combo, 1);
      game.tick();
      expect(game.combo, 2);
      game.tick();
      expect(game.combo, 3);

      expect(game.score, base * 1 + base * 2 + base * 3);
      expect(game.run.bestCombo, 3);

      // Let the window lapse.
      game.updateContinuous(GameConstants.comboWindow + 0.1);
      expect(game.combo, 1);
    });

    test('combo is capped', () async {
      final game = await newGame();
      isolateArena(game);

      var p = game.playerSnake.head;
      for (var i = 0; i < GameConstants.maxCombo + 4; i++) {
        p = p.moveWrapped(Direction.right);
        game.food.add(Food(p, FoodKind.normal));
      }
      for (var i = 0; i < GameConstants.maxCombo + 4; i++) {
        game.tick();
      }

      expect(game.combo, GameConstants.maxCombo);
    });
  });

  group('Power-ups', () {
    test('frenzy doubles the score of a pellet', () async {
      final game = await newGame();
      isolateArena(game);

      final head = game.playerSnake.head;
      game.powerUps.add(PowerPickup(head.moveWrapped(Direction.right), PowerType.frenzy, 9));
      game.tick();
      expect(game.activeEffects.containsKey(PowerType.frenzy), isTrue);

      game.food.add(Food(game.playerSnake.head.moveWrapped(Direction.right), FoodKind.normal));
      game.tick();

      expect(game.score, DifficultyConfig.medium.foodPoints * 2);
    });

    test('shield absorbs one otherwise fatal hit', () async {
      final game = await newGame();
      isolateArena(game);

      game.hasShield = true;
      coilPlayerIntoSelfCrash(game);

      game.tick();

      expect(game.hasShield, isFalse, reason: 'the shield was consumed');
      expect(game.isGameOver, isFalse);
      expect(game.isDying, isFalse);
      expect(game.graceTimer, greaterThan(0));
    });

    test('freeze stops rivals from moving', () async {
      final game = await newGame();
      isolateArena(game);

      game.rivals.add(Snake(
        body: [const Point(2, 2), const Point(1, 2)],
        direction: Direction.right,
        id: 500,
      ));

      final head = game.playerSnake.head;
      game.powerUps.add(PowerPickup(head.moveWrapped(Direction.right), PowerType.freeze, 9));
      game.tick();

      final frozenAt = game.rivals.first.head;
      game.tick();

      expect(game.rivals.first.head, frozenAt);
    });
  });

  group('Collisions', () {
    test('self-collision ends the run', () async {
      final game = await newGame();
      isolateArena(game);

      coilPlayerIntoSelfCrash(game);

      game.tick();

      expect(game.isDying || game.isGameOver, isTrue);
      expect(game.lastDeathCause, 'Bit your own tail');
    });

    test('moving into the cell the tail is vacating is legal', () async {
      final game = await newGame();
      isolateArena(game);

      // A tight hook: the head enters the square the tail leaves this tick.
      game.playerSnake.body = [
        const Point(6, 5),
        const Point(6, 6),
        const Point(7, 6),
        const Point(7, 5),
      ];
      game.playerSnake.direction = Direction.right;

      game.tick();

      expect(game.isDying, isFalse);
      expect(game.isGameOver, isFalse);
      expect(game.playerSnake.head, const Point(7, 5));
    });

    test('a rival that runs into the player body is destroyed', () async {
      final game = await newGame();
      isolateArena(game);

      // Long horizontal player body acting as a wall.
      game.playerSnake.body = [
        for (var x = 14; x >= 8; x--) Point(x, 15),
      ];
      game.playerSnake.direction = Direction.right;

      // Box the rival in so its only remaining move is into the player.
      // Without this the new AI simply steers around the obstacle, which is
      // exactly the behaviour the old greedy brain lacked.
      game.obstacles.addAll(const [Point(10, 14), Point(12, 14)]);
      game.rivals.add(Snake(
        body: [const Point(11, 14), const Point(11, 13)],
        direction: Direction.down,
        id: 501,
      ));

      final startScore = game.score;
      game.tick();

      expect(game.run.kills, 1);
      expect(game.score, greaterThan(startScore));
      expect(game.isGameOver, isFalse);
    });

    test('head-on trade is won by the longer snake', () async {
      final game = await newGame();
      isolateArena(game);

      game.playerSnake.body = [
        for (var x = 14; x >= 9; x--) Point(x, 15),
      ];
      game.playerSnake.direction = Direction.right;

      // Shorter rival walking straight into the player's next cell. It is
      // boxed in so the brain cannot simply steer around the trade, which is
      // what makes this assert the collision rule rather than the AI's mood.
      game.obstacles.addAll(const [Point(16, 14), Point(16, 16)]);
      game.rivals.add(Snake(
        body: [const Point(16, 15), const Point(17, 15)],
        direction: Direction.left,
        id: 502,
      ));

      game.tick();

      expect(game.run.kills, 1, reason: 'the longer player wins the trade');
      expect(game.isDying, isFalse);
      expect(game.isGameOver, isFalse);
    });

    test('head-on trade is lost by the shorter snake', () async {
      final game = await newGame();
      isolateArena(game);

      game.playerSnake.body = [const Point(14, 15), const Point(13, 15)];
      game.playerSnake.direction = Direction.right;

      game.obstacles.addAll(const [Point(16, 14), Point(16, 16)]);
      game.rivals.add(Snake(
        body: [
          for (var x = 16; x <= 22; x++) Point(x, 15),
        ],
        direction: Direction.left,
        id: 503,
      ));

      game.tick();

      expect(game.isDying || game.isGameOver, isTrue);
      expect(game.lastDeathCause, 'Crashed into a rival');
    });

    test('obstacles are lethal', () async {
      final game = await newGame(difficulty: Difficulty.hard);
      isolateArena(game);

      game.playerSnake.direction = Direction.right;
      game.obstacles.add(game.playerSnake.head.moveWrapped(Direction.right));

      game.tick();

      expect(game.isDying || game.isGameOver, isTrue);
      expect(game.lastDeathCause, 'Hit a wall block');
    });

    test('phase lets the player pass through everything', () async {
      final game = await newGame();
      isolateArena(game);

      game.activeEffects[PowerType.phase] = ActiveEffect(PowerType.phase, 6);
      game.playerSnake.direction = Direction.right;
      game.obstacles.add(game.playerSnake.head.moveWrapped(Direction.right));

      game.tick();

      expect(game.isDying, isFalse);
      expect(game.isGameOver, isFalse);
    });
  });

  group('Boost', () {
    test('drains while held and shortens the tick interval', () async {
      final game = await newGame();
      final normalInterval = game.tickIntervalMs;

      game.setBoost(true);
      expect(game.isBoosting, isTrue);
      expect(game.tickIntervalMs, lessThan(normalInterval));

      game.updateContinuous(1.0);
      expect(game.boostEnergy, closeTo(GameConstants.boostCapacity - 1.0, 0.001));
    });

    test('locks out when empty and stays locked until it recovers', () async {
      final game = await newGame();
      game.setBoost(true);
      game.updateContinuous(GameConstants.boostCapacity + 0.5);

      expect(game.boostEnergy, 0);
      expect(game.isBoosting, isFalse, reason: 'empty bar disengages boost');

      // Still held, but locked out: energy must recharge rather than stay at 0.
      game.updateContinuous(0.5);
      expect(game.boostEnergy, greaterThan(0));
      expect(game.isBoosting, isFalse);

      // Recharge past the re-engage threshold.
      game.updateContinuous(5.0);
      expect(game.isBoosting, isTrue);
    });

    test('recharges up to the cap and no further', () async {
      final game = await newGame();
      game.updateContinuous(60);
      expect(game.boostEnergy, GameConstants.boostCapacity);
    });
  });

  group('AI', () {
    test('rivals mostly survive a long match instead of suiciding', () async {
      final game = await newGame(difficulty: Difficulty.hard);

      // The dumb greedy AI this replaced wiped itself out almost immediately.
      // Drive a few hundred ticks and check the arena stays populated.
      var emptyTicks = 0;
      for (var i = 0; i < 400; i++) {
        if (!game.isRunning) break;
        game.tick();
        game.updateContinuous(game.difficulty.tickMs / 1000);
        if (game.aliveRivalCount == 0) emptyTicks++;
      }

      expect(emptyTicks, lessThan(20),
          reason: 'the arena should rarely be empty of rivals');
    });

    test('a rival in an open arena keeps itself alive', () async {
      final game = await newGame(difficulty: Difficulty.hard);
      isolateArena(game);

      // Park the player far away so it cannot interfere.
      game.playerSnake.body = [const Point(0, 0), const Point(0, 1)];
      game.playerSnake.direction = Direction.down;

      final rival = Snake(
        body: [const Point(15, 15), const Point(14, 15), const Point(13, 15)],
        direction: Direction.right,
        id: 600,
        pendingGrowth: 40, // force it to grow long and risk trapping itself
      );
      game.rivals.add(rival);
      game.food.add(Food(const Point(20, 20), FoodKind.normal));

      for (var i = 0; i < 120 && game.isRunning; i++) {
        game.tick();
      }

      expect(game.rivals.any((r) => r.id == 600 && r.isAlive), isTrue,
          reason: 'flood-fill safety should stop it coiling into a dead end');
    });

    test('rivals get replaced after they die', () async {
      final game = await newGame();
      final target = game.rivals.length;

      game.rivals.clear();
      // Respawn timers run on the continuous clock.
      for (var i = 0; i < target; i++) {
        game.tick();
      }
      for (var i = 0; i < 200; i++) {
        game.updateContinuous(0.05);
      }

      expect(game.rivals.length, lessThanOrEqualTo(target));
    });
  });

  group('Missions', () {
    test('encode/decode round-trips', () {
      final m = Mission(
        id: 'kills',
        metric: MissionMetric.kills,
        goal: 7,
        reward: 350,
        singleRun: true,
        progress: 3,
      );
      final back = Mission.decode(m.encode())!;

      expect(back.id, m.id);
      expect(back.metric, m.metric);
      expect(back.goal, m.goal);
      expect(back.reward, m.reward);
      expect(back.singleRun, m.singleRun);
      expect(back.progress, m.progress);
      expect(back.claimed, m.claimed);
    });

    test('decode rejects malformed input', () {
      expect(Mission.decode('garbage'), isNull);
      expect(Mission.decode('a|999|1|1|0|0|0'), isNull);
    });

    test('the same day always produces the same missions', () {
      final a = MissionFactory.forDate(DateTime(2026, 9, 4));
      final b = MissionFactory.forDate(DateTime(2026, 9, 4));
      final c = MissionFactory.forDate(DateTime(2026, 9, 5));

      expect(a.map((m) => m.id).toList(), b.map((m) => m.id).toList());
      expect(a.length, 3);
      expect(a.map((m) => m.id).toSet().length, 3, reason: 'no duplicate objectives');
      expect(
        a.map((m) => '${m.id}${m.goal}').join() == c.map((m) => '${m.id}${m.goal}').join(),
        isFalse,
        reason: 'a different day should roll a different set',
      );
    });

    test('claiming pays out exactly once', () async {
      final game = await newGame();
      final mission = Mission(
        id: 'x',
        metric: MissionMetric.kills,
        goal: 1,
        reward: 500,
        progress: 1,
      );
      game.missions
        ..clear()
        ..add(mission);

      final before = game.coins;
      expect(game.claimMission(mission), isTrue);
      expect(game.coins, before + 500);

      expect(game.claimMission(mission), isFalse);
      expect(game.coins, before + 500);
    });

    test('incomplete missions cannot be claimed', () async {
      final game = await newGame();
      final mission = Mission(id: 'x', metric: MissionMetric.kills, goal: 5, reward: 500);
      final before = game.coins;

      expect(game.claimMission(mission), isFalse);
      expect(game.coins, before);
    });
  });

  group('Economy', () {
    test('a skin unlock deducts its cost once', () async {
      final game = await newGame();
      game.coins = 5000;

      expect(game.unlockSkin(3, 3000), isTrue);
      expect(game.coins, 2000);
      expect(game.unlockedSkins, contains(3));

      expect(game.unlockSkin(3, 3000), isFalse, reason: 'already owned');
      expect(game.coins, 2000);
    });

    test('an unaffordable unlock changes nothing', () async {
      final game = await newGame();
      game.coins = 100;

      expect(game.unlockSkin(5, 4000), isFalse);
      expect(game.coins, 100);
      expect(game.unlockedSkins, isNot(contains(5)));
    });

    test('custom colours override the skin palette but keep its pattern', () async {
      final game = await newGame();
      game.applyCosmetics(
        skinIndex: 2, // Zebra, striped
        eyeIndex: 0,
        useCustom: true,
        primary: const Color(0xFF123456),
        secondary: const Color(0xFF654321),
      );

      expect(game.currentSkin.primaryColor, const Color(0xFF123456));
      expect(game.currentSkin.secondaryColor, const Color(0xFF654321));
      expect(game.currentSkin.type, GameConstants.availableSkins[2].type);
    });

    test('an out-of-range skin index falls back to the default', () async {
      final game = await newGame();
      game.currentSkinIndex = 999;
      game.currentEyeIndex = -4;

      expect(game.currentSkin.name, GameConstants.availableSkins[0].name);
      expect(game.currentEye.style, EyeStyle.classic);
    });
  });

  group('Match lifecycle', () {
    test('starting a match resets per-run state', () async {
      final game = await newGame();
      game.score = 999;
      game.combo = 5;
      game.hasShield = true;
      game.activeEffects[PowerType.frenzy] = ActiveEffect(PowerType.frenzy, 5);

      game.startGame();

      expect(game.score, 0);
      expect(game.combo, 1);
      expect(game.hasShield, isFalse);
      expect(game.activeEffects, isEmpty);
      expect(game.run.foodEaten, 0);
      expect(game.playerSnake.body.length, GameConstants.initialSnakeLength);
      expect(game.rivals.length, DifficultyConfig.medium.aiCount);
    });

    test('food spawns clear of snakes and obstacles', () async {
      final game = await newGame(difficulty: Difficulty.hard);

      for (final f in game.food) {
        expect(game.obstacles.contains(f.pos), isFalse);
        expect(game.playerSnake.occupies(f.pos), isFalse);
        for (final r in game.rivals) {
          expect(r.occupies(f.pos), isFalse);
        }
      }
      // Every pellet sits on its own cell.
      expect(game.food.map((f) => f.pos).toSet().length, game.food.length);
    });

    test('pausing halts the simulation', () async {
      final game = await newGame();
      isolateArena(game);

      game.togglePause();
      final head = game.playerSnake.head;
      game.tick();

      expect(game.playerSnake.head, head);

      game.togglePause();
      game.tick();
      expect(game.playerSnake.head, isNot(head));
    });

    test('revive restores play, clears the area and only works once', () async {
      final game = await newGame();
      isolateArena(game);

      // Force the run to end.
      coilPlayerIntoSelfCrash(game);
      game.tick();

      // Skip the death animation delay.
      await Future<void>.delayed(const Duration(milliseconds: 900));
      expect(game.isGameOver, isTrue);

      game.revive();
      expect(game.isRunning, isTrue);
      expect(game.hasUsedRevive, isTrue);
      expect(game.graceTimer, GameConstants.reviveGraceSeconds);

      // A second revive is refused.
      game.phase = GamePhase.over;
      game.revive();
      expect(game.isGameOver, isTrue);
    });

    test('difficulty selection swaps in the matching config', () async {
      final game = await newGame();

      game.setDifficulty(Difficulty.hard, notify: false);
      expect(game.difficulty.aiCount, DifficultyConfig.hard.aiCount);
      expect(game.difficulty.tickMs, DifficultyConfig.hard.tickMs);

      game.startGame();
      expect(game.rivals.length, DifficultyConfig.hard.aiCount);
      expect(game.obstacles, isNotEmpty);
    });

    test('easy has no obstacles', () async {
      final game = await newGame(difficulty: Difficulty.easy);
      expect(game.obstacles, isEmpty);
    });
  });

  group('Long-run stability', () {
    test('a full match never throws and keeps its invariants', () async {
      final game = await newGame(difficulty: Difficulty.hard);
      final rng = [Direction.up, Direction.right, Direction.down, Direction.left];

      for (var i = 0; i < 1500; i++) {
        if (!game.isRunning) {
          game.startGame();
        }
        if (i % 7 == 0) game.changeDirection(rng[i % 4]);
        game.tick();
        game.updateContinuous(game.difficulty.tickMs / 1000);

        // Bodies must never contain duplicate cells for a living snake.
        for (final r in game.rivals.where((r) => r.isAlive)) {
          expect(r.body.length, greaterThan(0));
        }
        expect(game.food.length, lessThan(120), reason: 'corpse food must stay bounded');
        expect(game.powerUps.length, lessThanOrEqualTo(GameConstants.maxPowerUpsOnField));
      }
    });
  });
}
