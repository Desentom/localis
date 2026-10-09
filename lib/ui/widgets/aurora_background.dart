import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme.dart';

/// Фон приложения.
///
/// Здесь больше нет ничего, кроме чёрной заливки. И это не simplification,
/// а результат диагностики: полноэкранный `CustomPaint` с радиальными
/// градиентами и `BlendMode.plus`, перерисовывающийся каждый кадр, на
/// слабом GPU не успевает растеризоваться — Android показывает серые
/// заглушки неотрисованных тайлов. Именно это выглядело как «серый
/// прямоугольник во весь экран» при генерации ответа.
///
/// Фон не должен стоить ни одного кадра. Всё оформление строится на
/// тонких линиях и белом тексте поверх чистого чёрного, поэтому фон можно
/// просто убрать.
class AuroraBackground extends StatelessWidget {
  const AuroraBackground({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(color: AppColors.bg, child: child);
  }
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
              color: const Color(0xFF141414),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.focus, width: 1.5),
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