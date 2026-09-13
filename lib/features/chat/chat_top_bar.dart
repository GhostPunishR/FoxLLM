// Copyright © 2026 GhostPunishR
// SPDX-License-Identifier: AGPL-3.0-only

// Barre du haut : titre, ouverture du menu et nouvelle conversation.
// Partie de la bibliothèque `chat_screen.dart` : ces widgets ne servent
// qu'à cet écran et restent donc privés, sans changer de nom ni d'accès.

part of 'chat_screen.dart';

/// En-tête du chat : menu latéral et nouveau chat, sur le fond du thème.
class _ChatTopBar extends StatelessWidget {
  const _ChatTopBar({required this.onMenu, required this.onNewChat});

  final VoidCallback onMenu;
  final VoidCallback onNewChat;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: context.fox.background,
      child: SafeArea(
        bottom: false,
        child: SizedBox(
          height: 52,
          child: Row(
            children: <Widget>[
              const SizedBox(width: 12),
              _TopButton(
                tooltip: 'Menu',
                onPressed: onMenu,
                child: const _MenuGlyph(),
              ),
              const Spacer(),
              _TopButton(
                tooltip: 'Nouveau chat',
                onPressed: onNewChat,
                child: const _NewChatGlyph(),
              ),
              const SizedBox(width: 12),
            ],
          ),
        ),
      ),
    );
  }
}

class _TopButton extends StatelessWidget {
  const _TopButton({
    required this.tooltip,
    required this.onPressed,
    required this.child,
  });

  final String tooltip;
  final VoidCallback onPressed;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: SizedBox.square(
        dimension: 42,
        child: InkResponse(
          radius: 22,
          onTap: onPressed,
          child: Center(child: child),
        ),
      ),
    );
  }
}

class _MenuGlyph extends StatelessWidget {
  const _MenuGlyph();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 24,
      height: 20,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Container(width: 24, height: 2, color: context.fox.textPrimary),
          const SizedBox(height: 7),
          Container(width: 16, height: 2, color: context.fox.textPrimary),
        ],
      ),
    );
  }
}

class _NewChatGlyph extends StatelessWidget {
  const _NewChatGlyph();

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: 29,
      child: CustomPaint(painter: _NewChatPainter(context.fox.textPrimary)),
    );
  }
}

class _NewChatPainter extends CustomPainter {
  const _NewChatPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final bubble = Path()
      ..moveTo(5, 4)
      ..quadraticBezierTo(3, 4, 3, 7)
      ..lineTo(3, 21)
      ..quadraticBezierTo(3, 24, 6, 24)
      ..lineTo(18, 24)
      ..lineTo(24, 28)
      ..lineTo(23, 23)
      ..quadraticBezierTo(26, 22, 26, 19)
      ..lineTo(26, 7)
      ..quadraticBezierTo(26, 4, 23, 4)
      ..close();
    canvas.drawPath(bubble, paint);

    canvas
      ..drawLine(const Offset(14.5, 8), const Offset(14.5, 20), paint)
      ..drawLine(const Offset(8.5, 14), const Offset(20.5, 14), paint);
  }

  @override
  bool shouldRepaint(covariant _NewChatPainter oldDelegate) =>
      oldDelegate.color != color;
}
