import 'dart:async';

import 'package:flutter/material.dart';

import '../chat/chat_backend_host.dart';
import '../chat/fox_mark.dart';

class FoxGptSplashScreen extends StatefulWidget {
  const FoxGptSplashScreen({
    super.key,
    this.duration = const Duration(milliseconds: 700),
  });

  final Duration duration;

  @override
  State<FoxGptSplashScreen> createState() => _FoxGptSplashScreenState();
}

class _FoxGptSplashScreenState extends State<FoxGptSplashScreen>
    with SingleTickerProviderStateMixin {
  static const _orange = Color(0xFFFC6117);

  late final AnimationController _progressController;

  @override
  void initState() {
    super.initState();
    _progressController = AnimationController(
      vsync: this,
      duration: widget.duration,
    );
    unawaited(_runSplash());
  }

  Future<void> _runSplash() async {
    await _progressController.forward();
    if (!mounted) {
      return;
    }

    unawaited(
      Navigator.of(context).pushReplacement<void, void>(
        PageRouteBuilder<void>(
          transitionDuration: const Duration(milliseconds: 140),
          pageBuilder: (context, animation, secondaryAnimation) =>
              const ChatBackendHost(),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return FadeTransition(opacity: animation, child: child);
          },
        ),
      ),
    );
  }

  @override
  void dispose() {
    _progressController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const FoxMark(size: 176),
            const SizedBox(height: 34),
            SizedBox(
              width: 218,
              child: AnimatedBuilder(
                animation: _progressController,
                builder: (context, child) {
                  return ClipRRect(
                    borderRadius: BorderRadius.circular(99),
                    child: LinearProgressIndicator(
                      value: _progressController.value,
                      minHeight: 5,
                      backgroundColor: const Color(0xFFE7E7E7),
                      valueColor: const AlwaysStoppedAnimation<Color>(_orange),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
