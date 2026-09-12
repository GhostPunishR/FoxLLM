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
    final bounds = Offset.zero & size;
    canvas.saveLayer(bounds, Paint());
    canvas.scale(size.width / 100, size.height / 100);

    final orangePaint = Paint()
      ..color = _orange
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    // Profil d'un renard assis : museau pointu, oreille haute et poitrine.
    final headAndChest = Path()
      ..moveTo(7, 43)
      ..quadraticBezierTo(15, 37, 27, 33)
      ..lineTo(35, 16)
      ..lineTo(44, 29)
      ..quadraticBezierTo(50, 29, 56, 34)
      ..quadraticBezierTo(61, 38, 60, 42)
      ..quadraticBezierTo(56, 49, 45, 52)
      ..quadraticBezierTo(36, 55, 31, 64)
      ..quadraticBezierTo(27, 58, 23, 52)
      ..quadraticBezierTo(18, 47, 7, 43)
      ..close();

    // Corps compact du renard.
    final body = Path()
      ..moveTo(39, 49)
      ..quadraticBezierTo(56, 44, 70, 50)
      ..quadraticBezierTo(81, 55, 83, 67)
      ..quadraticBezierTo(85, 79, 76, 88)
      ..quadraticBezierTo(66, 97, 51, 92)
      ..quadraticBezierTo(37, 88, 31, 76)
      ..quadraticBezierTo(27, 65, 32, 56)
      ..quadraticBezierTo(35, 52, 39, 49)
      ..close();

    // Grande queue touffue enroulée autour du corps.
    final tail = Path()
      ..moveTo(69, 56)
      ..quadraticBezierTo(88, 54, 96, 65)
      ..quadraticBezierTo(102, 75, 94, 85)
      ..quadraticBezierTo(84, 98, 64, 98)
      ..quadraticBezierTo(46, 98, 34, 87)
      ..quadraticBezierTo(49, 91, 62, 85)
      ..quadraticBezierTo(73, 80, 77, 70)
      ..quadraticBezierTo(80, 61, 69, 56)
      ..close();

    canvas
      ..drawPath(body, orangePaint)
      ..drawPath(tail, orangePaint)
      ..drawPath(headAndChest, orangePaint);

    final clearPaint = Paint()
      ..blendMode = BlendMode.clear
      ..isAntiAlias = true;

    // Œil discret comme sur un pictogramme monocolore.
    canvas.drawOval(
      Rect.fromCenter(
        center: const Offset(36.5, 35.5),
        width: 4.2,
        height: 3.2,
      ),
      clearPaint,
    );

    // Pointe claire de la queue : détail immédiatement associé au renard.
    final tailTip = Path()
      ..moveTo(88, 61)
      ..quadraticBezierTo(98, 67, 96, 76)
      ..quadraticBezierTo(94, 81, 89, 84)
      ..quadraticBezierTo(86, 76, 80, 70)
      ..quadraticBezierTo(84, 65, 88, 61)
      ..close();
    canvas.drawPath(tailTip, clearPaint);

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
