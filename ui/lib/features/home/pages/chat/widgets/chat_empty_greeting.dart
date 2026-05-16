import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:ui/theme/theme_context.dart';

const List<String> _kChatGreetingWordsZh = <String>[
  '聊天',
  '执行',
  '构建',
  '探索',
  '规划',
  '总结',
  '检索',
  '记忆',
];

const List<String> _kChatGreetingWordsEn = <String>[
  'chat',
  'execute',
  'build',
  'explore',
  'plan',
  'summarize',
  'search',
  'remember',
];

class ChatEmptyGreeting extends StatelessWidget {
  final Color? primaryTextColor;
  final Color? secondaryTextColor;
  final Color? accentColor;
  final bool compact;

  const ChatEmptyGreeting({
    super.key,
    this.primaryTextColor,
    this.secondaryTextColor,
    this.accentColor,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final isEnglish = Localizations.localeOf(context).languageCode == 'en';
    final palette = context.omniPalette;
    final primaryColor = primaryTextColor ?? palette.textPrimary;
    final secondaryColor = secondaryTextColor ?? palette.textSecondary;
    final keywordColor = accentColor ?? palette.accentPrimary;
    final disableAnimations =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final headline = isEnglish ? "Hi 👋, I'm Omnibot" : '你好👋，我是小万';
    final prefix = isEnglish ? 'I can help you' : '我可以帮助你';
    final words = isEnglish ? _kChatGreetingWordsEn : _kChatGreetingWordsZh;
    final fontSize = compact ? 17.0 : 19.0;
    final headlineStyle = TextStyle(
      color: primaryColor,
      fontSize: fontSize,
      fontWeight: FontWeight.w400,
      height: 1.3,
      letterSpacing: 0,
    );
    final helperStyle = TextStyle(
      color: secondaryColor,
      fontSize: fontSize,
      fontWeight: FontWeight.w400,
      height: 1.3,
      letterSpacing: 0,
    );
    final keywordStyle = TextStyle(
      color: keywordColor,
      fontSize: fontSize,
      fontWeight: FontWeight.w400,
      height: 1.3,
      letterSpacing: 0,
      fontFamily: isEnglish ? 'Georgia' : 'Noto Serif CJK SC',
      fontFamilyFallback: const <String>[
        'Noto Serif CJK SC',
        'Source Han Serif SC',
        'Songti SC',
        'STSong',
        'Georgia',
        'Times New Roman',
        'serif',
      ],
    );

    return Semantics(
      label: isEnglish
          ? "$headline\nI can help you chat, execute, build, and explore."
          : '$headline\n我可以帮助你聊天、执行、构建和探索。',
      child: ExcludeSemantics(
        child: TweenAnimationBuilder<double>(
          tween: Tween<double>(begin: 0, end: 1),
          duration: disableAnimations
              ? Duration.zero
              : const Duration(milliseconds: 420),
          curve: Curves.easeOutCubic,
          builder: (context, value, child) {
            if (disableAnimations) {
              return child ?? const SizedBox.shrink();
            }
            final eased = Curves.easeOutCubic.transform(value);
            return Opacity(
              opacity: eased,
              child: Transform.translate(
                offset: Offset(0, 10 * (1 - eased)),
                child: child,
              ),
            );
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(headline, textAlign: TextAlign.left, style: headlineStyle),
                const SizedBox(height: 6),
                Wrap(
                  alignment: WrapAlignment.start,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 5,
                  runSpacing: 2,
                  children: [
                    Text(prefix, style: helperStyle),
                    _SlotWordRotator(words: words, style: keywordStyle),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SlotWordRotator extends StatefulWidget {
  final List<String> words;
  final TextStyle style;

  const _SlotWordRotator({required this.words, required this.style});

  @override
  State<_SlotWordRotator> createState() => _SlotWordRotatorState();
}

class _SlotWordRotatorState extends State<_SlotWordRotator>
    with SingleTickerProviderStateMixin {
  static const Duration _rotationInterval = Duration(milliseconds: 1800);
  static const Duration _spinDuration = Duration(milliseconds: 460);

  late final AnimationController _controller;
  final math.Random _random = math.Random();
  Timer? _timer;
  int _currentIndex = 0;
  int? _previousIndex;

  @override
  void initState() {
    super.initState();
    _currentIndex = _randomInitialIndex();
    _controller = AnimationController(vsync: this, duration: _spinDuration);
    _startTimer();
  }

  @override
  void didUpdateWidget(covariant _SlotWordRotator oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!listEquals(oldWidget.words, widget.words)) {
      _controller.stop();
      _currentIndex = _randomInitialIndex();
      _previousIndex = null;
      _controller.value = 0;
      _startTimer();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  int _randomInitialIndex() {
    if (widget.words.isEmpty) {
      return 0;
    }
    return _random.nextInt(widget.words.length);
  }

  void _startTimer() {
    _timer?.cancel();
    if (widget.words.length <= 1) {
      return;
    }
    _timer = Timer.periodic(_rotationInterval, (_) => _advance());
  }

  void _advance() {
    if (!mounted || widget.words.length <= 1 || _controller.isAnimating) {
      return;
    }
    var nextIndex = _random.nextInt(widget.words.length);
    if (nextIndex == _currentIndex) {
      nextIndex = (nextIndex + 1) % widget.words.length;
    }
    setState(() {
      _previousIndex = _currentIndex;
      _currentIndex = nextIndex;
    });
    _controller.forward(from: 0).whenCompleteOrCancel(() {
      if (!mounted) {
        return;
      }
      setState(() {
        _previousIndex = null;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    if (widget.words.isEmpty) {
      return const SizedBox.shrink();
    }
    final disableAnimations =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final textScaler = MediaQuery.textScalerOf(context);
    final fontSize = widget.style.fontSize ?? 20;
    final lineHeight = widget.style.height ?? 1.2;
    final slotHeight = math.max(24.0, textScaler.scale(fontSize) * lineHeight);
    final maxWordWidth = _measureMaxWordWidth(context);

    if (disableAnimations || _previousIndex == null) {
      return SizedBox(
        width: maxWordWidth,
        height: slotHeight,
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(
            widget.words[_currentIndex],
            maxLines: 1,
            overflow: TextOverflow.visible,
            style: widget.style,
          ),
        ),
      );
    }

    return SizedBox(
      width: maxWordWidth,
      height: slotHeight,
      child: ClipRect(
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            final slideValue = Curves.easeOutCubic.transform(_controller.value);
            final fadeIn = Curves.easeOut.transform(_controller.value);
            final fadeOut = Curves.easeIn.transform(1 - _controller.value);
            return Stack(
              clipBehavior: Clip.hardEdge,
              children: [
                _buildWord(
                  widget.words[_previousIndex!],
                  dy: -slotHeight * slideValue,
                  opacity: fadeOut,
                ),
                _buildWord(
                  widget.words[_currentIndex],
                  dy: slotHeight * (1 - slideValue),
                  opacity: fadeIn,
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildWord(
    String text, {
    required double dy,
    required double opacity,
  }) {
    return Positioned.fill(
      child: Opacity(
        opacity: opacity.clamp(0.0, 1.0).toDouble(),
        child: Transform.translate(
          offset: Offset(0, dy),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.visible,
              style: widget.style,
            ),
          ),
        ),
      ),
    );
  }

  double _measureMaxWordWidth(BuildContext context) {
    final textDirection = Directionality.of(context);
    final textScaler = MediaQuery.textScalerOf(context);
    var maxWidth = 0.0;
    for (final word in widget.words) {
      final painter = TextPainter(
        text: TextSpan(text: word, style: widget.style),
        maxLines: 1,
        textDirection: textDirection,
        textScaler: textScaler,
      )..layout();
      maxWidth = math.max(maxWidth, painter.width);
    }
    return maxWidth + 2;
  }
}
