import 'dart:math' as math;

/// Keeps the full-screen chat composer lifted through transient focus loss
/// while the IME is still opening or visibly present.
///
/// The latch only activates after a real input intent (focus/editing) has
/// happened. Once focus is gone, it stays active until either:
/// - the keyboard clearly starts closing, or
/// - the keyboard has fully settled closed.
class ComposerLiftIntentTracker {
  ComposerLiftIntentTracker({
    this.visibleInsetThreshold = 0.5,
    this.motionEpsilon = 1.0,
  });

  final double visibleInsetThreshold;
  final double motionEpsilon;

  bool _latched = false;
  double? _lastInset;

  bool update({required bool hasInputIntent, required double bottomInset}) {
    final inset = bottomInset.isFinite ? math.max(0.0, bottomInset) : 0.0;

    if (hasInputIntent) {
      _latched = true;
      _lastInset = inset;
      return true;
    }

    final lastInset = _lastInset;
    if (_latched) {
      if (inset <= visibleInsetThreshold ||
          (lastInset != null && inset < lastInset - motionEpsilon)) {
        _latched = false;
      }
    }

    _lastInset = inset;
    return _latched && inset > visibleInsetThreshold;
  }
}
