import 'package:flutter/material.dart';

import 'app_theme.dart';

class WorkflowBrand extends StatelessWidget {
  final bool compact;
  const WorkflowBrand({super.key, this.compact = false});
  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      SizedBox(
        width: compact ? 36 : 42,
        height: 32,
        child: ClipRect(
          child: OverflowBox(
            maxWidth: compact ? 48 : 58,
            maxHeight: compact ? 48 : 58,
            child: Image.asset(
              'assets/images/thh_workflow_logo.png',
              width: compact ? 48 : 58,
              height: compact ? 48 : 58,
              excludeFromSemantics: true,
            ),
          ),
        ),
      ),
      Container(
        height: 20,
        width: 1,
        margin: const EdgeInsets.symmetric(horizontal: 10),
        color: AppTheme.muted.withValues(alpha: .4),
      ),
      Flexible(
        child: Text(
          'THH Workflow',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontFamily: 'Poppins',
            fontSize: compact ? 13 : 16,
            fontWeight: FontWeight.w700,
            color: AppTheme.ink,
            letterSpacing: -.5,
          ),
        ),
      ),
    ],
  );
}

class WaveBackdrop extends StatelessWidget {
  final Widget child;
  final bool strong;
  final BorderRadius? borderRadius;
  const WaveBackdrop({
    super.key,
    required this.child,
    this.strong = false,
    this.borderRadius,
  });
  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: borderRadius ?? BorderRadius.zero,
    child: CustomPaint(painter: _Waves(strong), child: child),
  );
}

class _Waves extends CustomPainter {
  final bool strong;
  const _Waves(this.strong);
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: strong
              ? const [Color(0xFF7449F8), Color(0xFF9876F4)]
              : const [Color(0xFFFCF9FF), Color(0xFFF0E8FF)],
        ).createShader(rect),
    );
    final a = Path()
      ..moveTo(0, size.height * .76)
      ..cubicTo(
        size.width * .23,
        size.height * .52,
        size.width * .53,
        size.height * .96,
        size.width,
        size.height * .33,
      )
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(
      a,
      Paint()
        ..color = (strong ? Colors.white : const Color(0xFFBBA1FF)).withValues(
          alpha: strong ? .08 : .16,
        ),
    );
    final b = Path()
      ..moveTo(size.width * .4, size.height)
      ..cubicTo(
        size.width * .63,
        size.height * .63,
        size.width * .73,
        size.height * .49,
        size.width,
        size.height * .54,
      )
      ..lineTo(size.width, size.height)
      ..close();
    canvas.drawPath(
      b,
      Paint()
        ..color = (strong ? Colors.white : const Color(0xFFD8C6FF)).withValues(
          alpha: strong ? .1 : .38,
        ),
    );
  }

  @override
  bool shouldRepaint(_Waves oldDelegate) => oldDelegate.strong != strong;
}

class GradientButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool busy;
  final bool arrow;
  const GradientButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.busy = false,
    this.arrow = true,
  });
  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(18),
      boxShadow: onPressed == null
          ? []
          : const [
              BoxShadow(
                color: Color(0x267348F6),
                blurRadius: 18,
                offset: Offset(0, 8),
              ),
            ],
    ),
    child: WaveBackdrop(
      strong: true,
      borderRadius: BorderRadius.circular(18),
      child: FilledButton(
        style: FilledButton.styleFrom(
          backgroundColor: Colors.transparent,
          disabledBackgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          minimumSize: const Size(double.infinity, 58),
          padding: const EdgeInsets.symmetric(vertical: 17, horizontal: 18),
        ),
        onPressed: onPressed,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (busy) ...[
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 2,
                ),
              ),
              const SizedBox(width: 12),
            ],
            Flexible(
              child: Text(
                label,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
            ),
            if (arrow && !busy) ...[
              const SizedBox(width: 14),
              const Icon(
                Icons.arrow_forward_rounded,
                color: Colors.white,
                size: 22,
              ),
            ],
          ],
        ),
      ),
    ),
  );
}

class BrandIllustration extends StatelessWidget {
  final String name;
  final double size;
  const BrandIllustration(this.name, {super.key, this.size = 150});
  @override
  Widget build(BuildContext context) => Image.asset(
    'assets/illustrations/$name.png',
    width: size,
    height: size,
    fit: BoxFit.contain,
    excludeFromSemantics: true,
    filterQuality: FilterQuality.medium,
  );
}
