import 'dart:math';

/// What a mission counts.
enum MissionMetric {
  foodEaten,
  kills,
  score,
  survivalSeconds,
  bestCombo,
  powerUps,
  goldenFood,
}

/// A single rotating objective. Missions give the coin economy a floor that
/// does not depend on watching ads, and they give a run a goal beyond "score".
class Mission {
  final String id;
  final MissionMetric metric;
  final int goal;
  final int reward;

  /// Whether progress accumulates across runs or must happen in a single run.
  final bool singleRun;

  int progress;
  bool claimed;

  Mission({
    required this.id,
    required this.metric,
    required this.goal,
    required this.reward,
    this.singleRun = false,
    this.progress = 0,
    this.claimed = false,
  });

  bool get isComplete => progress >= goal;
  double get fraction => (progress / goal).clamp(0.0, 1.0);

  String get title => switch (metric) {
        MissionMetric.foodEaten =>
          singleRun ? 'Eat $goal pellets in one run' : 'Eat $goal pellets',
        MissionMetric.kills =>
          singleRun ? 'Destroy $goal rivals in one run' : 'Destroy $goal rivals',
        MissionMetric.score => 'Score $goal in one run',
        MissionMetric.survivalSeconds => 'Survive ${goal}s in one run',
        MissionMetric.bestCombo => 'Reach a x$goal combo',
        MissionMetric.powerUps => 'Collect $goal power-ups',
        MissionMetric.goldenFood => 'Eat $goal golden pellets',
      };

  String encode() => '$id|${metric.index}|$goal|$reward|${singleRun ? 1 : 0}|$progress|${claimed ? 1 : 0}';

  static Mission? decode(String raw) {
    final parts = raw.split('|');
    if (parts.length != 7) return null;
    final metricIndex = int.tryParse(parts[1]);
    if (metricIndex == null || metricIndex >= MissionMetric.values.length) return null;
    return Mission(
      id: parts[0],
      metric: MissionMetric.values[metricIndex],
      goal: int.tryParse(parts[2]) ?? 1,
      reward: int.tryParse(parts[3]) ?? 0,
      singleRun: parts[4] == '1',
      progress: int.tryParse(parts[5]) ?? 0,
      claimed: parts[6] == '1',
    );
  }
}

/// Builds the daily mission set. Deterministic per day so the objectives stay
/// stable if the player closes and reopens the app.
class MissionFactory {
  static List<Mission> forDate(DateTime date) {
    final seed = date.year * 10000 + date.month * 100 + date.day;
    final rnd = Random(seed);

    final pool = <Mission Function()>[
      () => Mission(id: 'food', metric: MissionMetric.foodEaten, goal: 60 + rnd.nextInt(4) * 20, reward: 300),
      () => Mission(id: 'food_run', metric: MissionMetric.foodEaten, goal: 20 + rnd.nextInt(3) * 5, reward: 250, singleRun: true),
      () => Mission(id: 'kills', metric: MissionMetric.kills, goal: 5 + rnd.nextInt(4) * 2, reward: 350),
      () => Mission(id: 'kills_run', metric: MissionMetric.kills, goal: 3 + rnd.nextInt(2), reward: 400, singleRun: true),
      () => Mission(id: 'score', metric: MissionMetric.score, goal: 1500 + rnd.nextInt(5) * 500, reward: 400),
      () => Mission(id: 'survive', metric: MissionMetric.survivalSeconds, goal: 60 + rnd.nextInt(3) * 30, reward: 300),
      () => Mission(id: 'combo', metric: MissionMetric.bestCombo, goal: 4 + rnd.nextInt(3), reward: 350),
      () => Mission(id: 'power', metric: MissionMetric.powerUps, goal: 6 + rnd.nextInt(3) * 2, reward: 250),
      () => Mission(id: 'golden', metric: MissionMetric.goldenFood, goal: 3 + rnd.nextInt(3), reward: 300),
    ];

    pool.shuffle(rnd);
    return pool.take(3).map((f) => f()).toList();
  }
}

/// Everything a single run produced. Feeds both the game-over screen and
/// mission progress.
class RunStats {
  int score = 0;
  int foodEaten = 0;
  int goldenEaten = 0;
  int kills = 0;
  int powerUpsCollected = 0;
  int bestCombo = 1;
  int coins = 0;
  double survivedSeconds = 0;
  int maxLength = 0;

  void reset() {
    score = 0;
    foodEaten = 0;
    goldenEaten = 0;
    kills = 0;
    powerUpsCollected = 0;
    bestCombo = 1;
    coins = 0;
    survivedSeconds = 0;
    maxLength = 0;
  }
}
