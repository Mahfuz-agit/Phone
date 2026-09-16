import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'theme/app_theme.dart';

/// Recreates the app icon glyph in pure Flutter widgets (no bundled
/// image asset needed) with a short fade + scale-in, then a subtle
/// "breathing" loop while init work finishes. Kept under ~250ms for
/// the entry animation itself, per HIG's "motion should be quick and
/// purposeful" — the loop exists only so a slower device doesn't
/// show a static, seemingly-frozen screen for a couple of seconds.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _entryOpacity;
  late final Animation<double> _entryScale;
  late final Animation<double> _pulse;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))..repeat();

    // First 200ms of the 1400ms loop = the one-time entry animation;
    // everything after is a gentle, low-amplitude pulse so a slow
    // device doesn't look stuck.
    _entryOpacity = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.0, 0.16, curve: Curves.easeOut),
    );
    _entryScale = Tween<double>(begin: 0.85, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: const Interval(0.0, 0.16, curve: Curves.easeOutBack)),
    );
    _pulse = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.04).chain(CurveTween(curve: Curves.easeInOut)), weight: 50),
      TweenSequenceItem(tween: Tween(begin: 1.04, end: 1.0).chain(CurveTween(curve: Curves.easeInOut)), weight: 50),
    ]).animate(CurvedAnimation(parent: _controller, curve: const Interval(0.16, 1.0)));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      backgroundColor: AppColors.systemBlue,
      child: Center(
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            final scale = _controller.value < 0.16 ? _entryScale.value : _pulse.value;
            return Opacity(
              opacity: _entryOpacity.value,
              child: Transform.scale(scale: scale, child: child),
            );
          },
          child: const _AppGlyph(),
        ),
      ),
    );
  }
}

/// Same smartphone glyph as the launcher icon, drawn with plain
/// widgets so no image asset needs to be bundled/kept in sync.
class _AppGlyph extends StatelessWidget {
  const _AppGlyph();

  @override
  Widget build(BuildContext context) {
    const bodyWidth = 96.0;
    const bodyHeight = 148.0;

    return Container(
      width: bodyWidth,
      height: bodyHeight,
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(bodyWidth * 0.22)),
      padding: EdgeInsets.symmetric(horizontal: bodyWidth * 0.10, vertical: bodyHeight * 0.10),
      child: Column(
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(color: AppColors.systemBlue, borderRadius: BorderRadius.circular(bodyWidth * 0.10)),
            ),
          ),
          SizedBox(height: bodyHeight * 0.05),
          Container(
            width: bodyWidth * 0.12,
            height: bodyWidth * 0.12,
            decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
          ),
        ],
      ),
    );
  }
}
