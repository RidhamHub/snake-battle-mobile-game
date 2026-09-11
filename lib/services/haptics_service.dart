import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../constants.dart';

/// Thin wrapper over [HapticFeedback] that respects the user's toggle and
/// silently no-ops on platforms without a vibrator.
class HapticsService extends ChangeNotifier {
  static final HapticsService _instance = HapticsService._internal();
  factory HapticsService() => _instance;
  HapticsService._internal();

  bool _enabled = true;
  bool get isEnabled => _enabled;

  /// Haptics only make sense on phones; calling them elsewhere just throws.
  bool get _supported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _enabled = prefs.getBool(GameConstants.hapticsEnabledKey) ?? true;
  }

  Future<void> toggle() async {
    _enabled = !_enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(GameConstants.hapticsEnabledKey, _enabled);
    if (_enabled) light();
    notifyListeners();
  }

  void selection() {
    if (!_enabled || !_supported) return;
    HapticFeedback.selectionClick();
  }

  void light() {
    if (!_enabled || !_supported) return;
    HapticFeedback.lightImpact();
  }

  void medium() {
    if (!_enabled || !_supported) return;
    HapticFeedback.mediumImpact();
  }

  void heavy() {
    if (!_enabled || !_supported) return;
    HapticFeedback.heavyImpact();
  }
}
