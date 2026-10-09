import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme.dart';

/// Фон приложения.
///
/// Раньше здесь был градиент из трёх цветных пятен. Сейчас — тот же приём,
/// но в оттенках серого и всего два пятна вместо трёх. Причина не только в
/// требовании монохрома: лишние радиальные градиенты — это лишняя работа
/// GPU каждый кадр, а на телефоне с 3–4 ГБ оперативной памяти плавность
/// интерфейса обменивается прямо на отзывы.
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
                painter: _GreyGlowPainter(_c.value),
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

/// Плавное серое свечение. Контраст намеренно низкий: фон должен читаться
/// как глубина, а не как украшение, и не спорить с текстом.
class _GreyGlowPainter extends CustomPainter {
  _GreyGlowPainter(this.t);

  /// 0..1, полный цикл анимации.
  final double t;

  static const _blobs = <_Blob>[
    _Blob(alpha: 0.055, radiusFactor: 0.95, phase: 0.00, speed: 1.00),
    _Blob(alpha: 0.032, radiusFactor: 0.72, phase: 0.42, speed: 0.62),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..blendMode = BlendMode.plus;

    for (final b in _blobs) {
      final angle = (t * 2 * math.pi * b.speed) + b.phase * 2 * math.pi;
      // Блубы ходят по эллипсу, а не по кругу — движение выглядит
      // естественнее и не выдаёт себя идеальной симметрией.
      final center = Offset(
        size.width * (0.5 + 0.38 * math.cos(angle)),
        size.height * (0.28 + 0.26 * math.sin(angle * 0.8 + b.phase)),
      );
      final radius = size.shortestSide * b.radiusFactor;

      paint.shader = RadialGradient(
        colors: [
          Colors.white.withValues(alpha: b.alpha),
          Colors.white.withValues(alpha: b.alpha * 0.35),
          Colors.white.withValues(alpha: 0.0),
        ],
        stops: const [0.0, 0.45, 1.0],
      ).createShader(Rect.fromCircle(center: center, radius: radius));

      canvas.drawCircle(center, radius, paint);
    }
  }

  @override
  bool shouldRepaint(_GreyGlowPainter old) => old.t != t;
}

class _Blob {
  const _Blob({
    required this.alpha,
    required this.radiusFactor,
    required this.phase,
    required this.speed,
  });

  final double alpha;
  final double radiusFactor;
  final double phase;
  final double speed;
}

/// Карточка. Раньше здесь было [BackdropFilter] с размытием на 14 пикселей —
/// оно брало с телефона заметную часть кадрового бюджета. Заменено на
/// сплошную заливку: на чёрном фоне размытие не даёт видимого эффекта,
/// а стоит реальных кадров.
class GlassCard extends StatelessWidget {
  const GlassCard({
    required this.child,
    super.key,
    this.padding = const EdgeInsets.all(16),
    this.borderRadius = AppRadius.card,
    this.onTap,
    this.borderColor = AppSurfaces.border,
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
        color: AppColors.surface,
        borderRadius: borderRadius,
        border: Border.all(color: borderColor),
      ),
      child: child,
    );

    if (onTap == null) return content;

    return ClipRRect(
      borderRadius: borderRadius,
      child: Material(
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
              // Тень без цвета: на чёрном фоне она читается как глубина
              // кнопки, а не как свечение.
              boxShadow: enabled
                  ? [
                      BoxShadow(
                        color: Colors.white.withValues(alpha: 0.14),
                        blurRadius: 22,
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
                        valueColor: AlwaysStoppedAnimation(Colors.black),
                      ),
                    )
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (widget.icon != null) ...[
                          Icon(widget.icon, color: Colors.black, size: 19),
                          const SizedBox(width: 9),
                        ],
                        Text(
                          widget.label,
                          style: const TextStyle(
                            color: Colors.black,
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
