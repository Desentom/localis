import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme.dart';

/// Живой градиентный фон.
///
/// Важное решение: размытие сделано НЕ через [ImageFilter.blur] на весь
/// экран, а через мягкие радиальные градиенты. На среднем телефоне реальный
/// blur съедает 15–25 кадров в секунду — а плавность интерфейса здесь
/// продающая фича.
class AuroraBackground extends StatefulWidget {
  const AuroraBackground({required this.child, super.key});

  final Widget child;

  @override
  State<AuroraBackground> createState() => _AuroraBackgroundState();
}

class _AuroraBackgroundState extends State<AuroraBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 24),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        const Positioned.fill(child: ColoredBox(color: AppColors.bg)),
        Positioned.fill(
          child: RepaintBoundary(
            child: AnimatedBuilder(
              animation: _c,
              builder: (context, _) => CustomPaint(
                painter: _AuroraPainter(_c.value),
                willChange: true,
              ),
            ),
          ),
        ),
        Positioned.fill(child: widget.child),
      ],
    );
  }
}

class _AuroraPainter extends CustomPainter {
  _AuroraPainter(this.t);

  /// 0..1, полный цикл анимации.
  final double t;

  static const _blobs = <_Blob>[
    _Blob(color: AppColors.violet, radiusFactor: 0.95, phase: 0.00, speed: 1.00),
    _Blob(color: AppColors.cyan, radiusFactor: 0.78, phase: 0.35, speed: 0.70),
    _Blob(color: Color(0xFF4C3BCF), radiusFactor: 0.62, phase: 0.68, speed: 0.45),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..blendMode = BlendMode.plus;

    for (final b in _blobs) {
      final angle = (t * 2 * math.pi * b.speed) + b.phase * 2 * math.pi;
      // Блубы ходят по эллипсу, а не по кругу — движение выглядит
      // естественнее и не выдаёт себя идеальной симметрией.
      final center = Offset(
        size.width * (0.5 + 0.40 * math.cos(angle)),
        size.height * (0.30 + 0.28 * math.sin(angle * 0.8 + b.phase)),
      );
      final radius = size.shortestSide * b.radiusFactor;

      paint.shader = RadialGradient(
        colors: [
          b.color.withValues(alpha: 0.28),
          b.color.withValues(alpha: 0.09),
          b.color.withValues(alpha: 0.0),
        ],
        stops: const [0.0, 0.45, 1.0],
      ).createShader(Rect.fromCircle(center: center, radius: radius));

      canvas.drawCircle(center, radius, paint);
    }
  }

  @override
  bool shouldRepaint(_AuroraPainter old) => old.t != t;
}

class _Blob {
  const _Blob({
    required this.color,
    required this.radiusFactor,
    required this.phase,
    required this.speed,
  });

  final Color color;
  final double radiusFactor;
  final double phase;
  final double speed;
}

/// Матовое стекло. Размытие включается точечно и только на карточках,
/// где это читается, а не на всём экране.
class GlassCard extends StatelessWidget {
  const GlassCard({
    required this.child,
    super.key,
    this.padding = const EdgeInsets.all(16),
    this.borderRadius = AppRadius.card,
    this.onTap,
    this.borderColor = const Color(0x1FFFFFFF),
  });

  final Widget child;
  final EdgeInsets padding;
  final BorderRadius borderRadius;
  final VoidCallback? onTap;
  final Color borderColor;

  @override
  Widget build(BuildContext context) {
    final content = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: const Color(0x14FFFFFF),
        borderRadius: borderRadius,
        border: Border.all(color: borderColor),
      ),
      child: child,
    );

    return ClipRRect(
      borderRadius: borderRadius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: onTap == null
            ? content
            : Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    onTap!();
                  },
                  borderRadius: borderRadius,
                  child: content,
                ),
              ),
      ),
    );
  }
}

/// Градиентная кнопка-CTA. Главный визуальный акцент приложения.
class GradientButton extends StatefulWidget {
  const GradientButton({
    required this.label,
    required this.onPressed,
    super.key,
    this.icon,
    this.busy = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool busy;

  @override
  State<GradientButton> createState() => _GradientButtonState();
}

class _GradientButtonState extends State<GradientButton> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null && !widget.busy;
    return AnimatedScale(
      scale: _down ? 0.97 : 1.0,
      duration: const Duration(milliseconds: 110),
      child: GestureDetector(
        onTapDown: enabled ? (_) => setState(() => _down = true) : null,
        onTapUp: enabled ? (_) => setState(() => _down = false) : null,
        onTapCancel: enabled ? () => setState(() => _down = false) : null,
        onTap: enabled
            ? () {
                HapticFeedback.lightImpact();
                widget.onPressed!();
              }
            : null,
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 150),
          opacity: enabled ? 1.0 : 0.45,
          child: Container(
            height: 54,
            width: double.infinity,
            decoration: BoxDecoration(
              gradient: AppColors.accent,
              borderRadius: BorderRadius.circular(16),
              boxShadow: enabled
                  ? [
                      BoxShadow(
                        color: AppColors.violet.withValues(alpha: 0.30),
                        blurRadius: 24,
                        offset: const Offset(0, 8),
                      ),
                    ]
                  : null,
            ),
            child: Center(
              child: widget.busy
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.2,
                        valueColor: AlwaysStoppedAnimation(Colors.white),
                      ),
                    )
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (widget.icon != null) ...[
                          Icon(widget.icon, color: Colors.white, size: 19),
                          const SizedBox(width: 9),
                        ],
                        Text(
                          widget.label,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15.5,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.1,
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Небольшая метка-пилюля: «локально», «18 ток/с», «без сети».
class Pill extends StatelessWidget {
  const Pill({
    required this.label,
    super.key,
    this.icon,
    this.color = AppColors.textSecondary,
    this.background = const Color(0x14FFFFFF),
    this.dense = false,
  });

  final String label;
  final IconData? icon;
  final Color color;
  final Color background;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: dense ? 8 : 10,
        vertical: dense ? 3 : 5,
      ),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: dense ? 11 : 13, color: color),
            SizedBox(width: dense ? 4 : 5),
          ],
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: dense ? 10.5 : 11.5,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }
}
