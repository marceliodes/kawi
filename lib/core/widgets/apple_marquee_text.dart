import 'dart:async';
import 'package:flutter/material.dart';

/// An Apple-style running marquee text widget.
///
/// Measures [text] width against parent horizontal constraints:
/// - If text fits: renders a standard [Text] widget without animation or shader overhead.
/// - If text overflows: applies a subtle horizontal alpha gradient fade mask on
///   leading/trailing edges and smoothly scrolls back and forth (ping-pong)
///   with an initial pause, smooth linear scroll (~30px/sec), and an end pause.
class AppleMarqueeText extends StatefulWidget {
  const AppleMarqueeText({
    super.key,
    required this.text,
    this.style,
    this.textAlign,
    this.textDirection,
    this.velocity = 30.0,
    this.pauseDuration = const Duration(milliseconds: 1500),
    this.fadeWidth = 12.0,
  });

  final String text;
  final TextStyle? style;
  final TextAlign? textAlign;
  final TextDirection? textDirection;
  final double velocity;
  final Duration pauseDuration;
  final double fadeWidth;

  @override
  State<AppleMarqueeText> createState() => _AppleMarqueeTextState();
}

class _AppleMarqueeTextState extends State<AppleMarqueeText>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  Timer? _pauseTimer;
  double _lastOverflowWidth = 0.0;
  bool _isCycleRunning = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this);
  }

  @override
  void didUpdateWidget(covariant AppleMarqueeText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.text != oldWidget.text ||
        widget.style != oldWidget.style ||
        widget.velocity != oldWidget.velocity) {
      _stopCycle();
      _controller.reset();
      _lastOverflowWidth = 0.0;
    }
  }

  @override
  void dispose() {
    _stopCycle();
    _controller.dispose();
    super.dispose();
  }

  void _stopCycle() {
    _pauseTimer?.cancel();
    _pauseTimer = null;
    _isCycleRunning = false;
    if (_controller.isAnimating) {
      _controller.stop();
    }
  }

  void _scheduleMarqueeCycle(double overflowWidth) {
    if (_isCycleRunning || !mounted || overflowWidth <= 0) return;
    _isCycleRunning = true;

    _pauseTimer?.cancel();
    // 1. Initial pause at start position
    _pauseTimer = Timer(widget.pauseDuration, () {
      if (!mounted || !_isCycleRunning) return;

      final scrollDuration = Duration(
        milliseconds: ((overflowWidth / widget.velocity) * 1000)
            .clamp(200, 60000)
            .round(),
      );
      _controller.duration = scrollDuration;

      // 2. Linear scroll across hidden text
      _controller.forward().then((_) {
        if (!mounted || !_isCycleRunning) return;

        // 3. Pause at the end
        _pauseTimer = Timer(widget.pauseDuration, () {
          if (!mounted || !_isCycleRunning) return;

          // 4. Smooth linear scroll back to start (ping-pong)
          _controller.reverse().then((_) {
            if (!mounted || !_isCycleRunning) return;
            _isCycleRunning = false;
            // 5. Restart cycle
            _scheduleMarqueeCycle(overflowWidth);
          }).catchError((_) {});
        });
      }).catchError((_) {});
    });
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (!constraints.hasBoundedWidth || widget.text.isEmpty) {
          return Text(
            widget.text,
            style: widget.style,
            textAlign: widget.textAlign,
            maxLines: 1,
            overflow: TextOverflow.clip,
          );
        }

        final defaultStyle = DefaultTextStyle.of(context).style;
        final effectiveStyle = defaultStyle.merge(widget.style);
        final direction = widget.textDirection ??
            Directionality.maybeOf(context) ??
            TextDirection.ltr;

        final textPainter = TextPainter(
          text: TextSpan(text: widget.text, style: effectiveStyle),
          textDirection: direction,
          maxLines: 1,
        )..layout();

        final textWidth = textPainter.width;
        final textHeight = textPainter.height;
        final availableWidth = constraints.maxWidth;

        // If text fits comfortably, render standard Text without animation
        if (textWidth <= availableWidth) {
          if (_isCycleRunning) {
            _stopCycle();
            _controller.reset();
            _lastOverflowWidth = 0.0;
          }
          return Text(
            widget.text,
            style: widget.style,
            textAlign: widget.textAlign,
            maxLines: 1,
            overflow: TextOverflow.clip,
          );
        }

        final overflowWidth = textWidth - availableWidth;

        if (overflowWidth != _lastOverflowWidth) {
          _lastOverflowWidth = overflowWidth;
          _stopCycle();
          _controller.reset();
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              _scheduleMarqueeCycle(overflowWidth);
            }
          });
        } else if (!_isCycleRunning) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              _scheduleMarqueeCycle(overflowWidth);
            }
          });
        }

        final fadeFraction =
            (widget.fadeWidth / availableWidth).clamp(0.01, 0.25);

        return AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            final currentOffset = _controller.value * overflowWidth;
            final isAtStart = _controller.value <= 0.01;
            final isAtEnd = _controller.value >= 0.99;

            final leadingColor =
                isAtStart ? Colors.black : Colors.transparent;
            final trailingColor =
                isAtEnd ? Colors.black : Colors.transparent;

            return ShaderMask(
              shaderCallback: (Rect bounds) {
                return LinearGradient(
                  colors: [
                    leadingColor,
                    Colors.black,
                    Colors.black,
                    trailingColor,
                  ],
                  stops: [
                    0.0,
                    fadeFraction,
                    1.0 - fadeFraction,
                    1.0,
                  ],
                ).createShader(bounds);
              },
              blendMode: BlendMode.dstIn,
              child: ClipRect(
                child: SizedBox(
                  width: availableWidth,
                  height: textHeight,
                  child: Transform.translate(
                    offset: Offset(-currentOffset, 0),
                    child: OverflowBox(
                      alignment: Alignment.centerLeft,
                      minWidth: textWidth,
                      maxWidth: textWidth,
                      minHeight: textHeight,
                      maxHeight: textHeight,
                      child: Text(
                        widget.text,
                        style: widget.style,
                        maxLines: 1,
                        softWrap: false,
                        overflow: TextOverflow.visible,
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}
