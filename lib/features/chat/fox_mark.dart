import 'package:flutter/material.dart';

class FoxMark extends StatelessWidget {
  const FoxMark({super.key, this.size = 72});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'FoxGPT',
      image: true,
      child: SizedBox.square(
        dimension: size,
        child: CustomPaint(
          painter: const _FoxMarkPainter(),
        ),
      ),
    );
  }
}

class _FoxMarkPainter extends CustomPainter {
  const _FoxMarkPainter();

  static const _orange = Color(0xFFFF7A1A);
  static const _cutout = Color(0xFF0B0B0B);

  @override
  void paint(Canvas canvas, Size size) {
    final scaleX = size.width / 100;
    final scaleY = size.height / 100;
    canvas.save();
    canvas.scale(scaleX, scaleY);

    final fox = Path()
      ..moveTo(13, 29)
      ..lineTo(38, 17)
      ..lineTo(48, 29)
      ..quadraticBezierTo(50, 27, 52, 29)
      ..lineTo(62, 17)
      ..lineTo(87, 29)
      ..quadraticBezierTo(84, 57, 72, 72)
      ..quadraticBezierTo(61, 84, 50, 88)
      ..quadraticBezierTo(39, 84, 28, 72)
      ..quadraticBezierTo(16, 57, 13, 29)
      ..close();

    canvas.drawPath(fox, Paint()..color = _orange);

    final leftMask = Path()
      ..moveTo(24, 45)
      ..quadraticBezierTo(35, 43, 46, 54)
      ..quadraticBezierTo(38, 66, 30, 68)
      ..quadraticBezierTo(25, 58, 24, 45)
      ..close();
    final rightMask = Path()
      ..moveTo(76, 45)
      ..quadraticBezierTo(65, 43, 54, 54)
      ..quadraticBezierTo(62, 66, 70, 68)
      ..quadraticBezierTo(75, 58, 76, 45)
      ..close();

    final cutoutPaint = Paint()..color = _cutout;
    canvas.drawPath(leftMask, cutoutPaint);
    canvas.drawPath(rightMask, cutoutPaint);

    final muzzle = Path()
      ..moveTo(40, 70)
      ..quadraticBezierTo(50, 76, 60, 70)
      ..quadraticBezierTo(56, 82, 50, 86)
      ..quadraticBezierTo(44, 82, 40, 70)
      ..close();
    canvas.drawPath(muzzle, cutoutPaint);

    canvas.drawCircle(const Offset(38, 48), 2.2, cutoutPaint);
    canvas.drawCircle(const Offset(62, 48), 2.2, cutoutPaint);

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
