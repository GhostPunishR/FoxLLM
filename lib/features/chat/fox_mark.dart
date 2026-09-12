import 'package:flutter/material.dart';

class FoxMark extends StatelessWidget {
  const FoxMark({super.key, this.size = 48});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'FoxGPT',
      image: true,
      child: SizedBox.square(
        dimension: size,
        child: CustomPaint(painter: const _FoxMarkPainter()),
      ),
    );
  }
}

class _FoxMarkPainter extends CustomPainter {
  const _FoxMarkPainter();

  static const _orange = Color(0xFFFF7A1A);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.saveLayer(Offset.zero & size, Paint());
    canvas.scale(size.width / 100, size.height / 100);

    final orangePaint = Paint()
      ..color = _orange
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    final fox = Path()
      ..moveTo(8, 39)
      ..lineTo(23, 31)
      ..lineTo(30, 17)
      ..lineTo(37, 29)
      ..cubicTo(45, 28, 51, 34, 51, 40)
      ..cubicTo(50, 46, 44, 49, 38, 51)
      ..cubicTo(50, 47, 65, 49, 72, 60)
      ..cubicTo(79, 70, 77, 81, 69, 89)
      ..cubicTo(63, 95, 55, 95, 47, 91)
      ..cubicTo(38, 87, 33, 79, 33, 70)
      ..cubicTo(33, 62, 35, 56, 38, 51)
      ..cubicTo(32, 54, 29, 61, 29, 70)
      ..cubicTo(29, 79, 33, 86, 39, 91)
      ..cubicTo(31, 91, 25, 86, 22, 79)
      ..cubicTo(18, 70, 19, 60, 23, 52)
      ..cubicTo(21, 47, 17, 43, 8, 39)
      ..close();

    final tail = Path()
      ..moveTo(69, 61)
      ..cubicTo(82, 60, 93, 66, 98, 73)
      ..cubicTo(91, 83, 81, 90, 69, 94)
      ..cubicTo(56, 98, 43, 95, 34, 88)
      ..cubicTo(49, 89, 61, 84, 69, 77)
      ..cubicTo(75, 72, 76, 65, 69, 61)
      ..close();

    canvas
      ..drawPath(fox, orangePaint)
      ..drawPath(tail, orangePaint);

    final clearPaint = Paint()
      ..blendMode = BlendMode.clear
      ..isAntiAlias = true;
    canvas.drawOval(
      Rect.fromCenter(
        center: const Offset(36, 36),
        width: 4,
        height: 2.4,
      ),
      clearPaint,
    );

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
