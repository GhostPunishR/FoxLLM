import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/theme/theme_provider.dart';
import 'features/chat/chat_backend_host.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky));
  runApp(const ProviderScope(child: FoxGptApp()));
}

class FoxGptApp extends ConsumerWidget {
  const FoxGptApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(foxThemeProvider);
    final palette = theme.palette;
    final isDark = theme.brightness == Brightness.dark;

    // Les barres système suivent le thème, sinon leurs icônes deviennent
    // illisibles sur la déclinaison claire.
    SystemChrome.setSystemUIOverlayStyle(
      SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
        statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
        systemNavigationBarColor: palette.background,
        systemNavigationBarIconBrightness: isDark
            ? Brightness.light
            : Brightness.dark,
        systemNavigationBarDividerColor: palette.background,
      ),
    );

    return MaterialApp(
      title: 'FoxGPT',
      debugShowCheckedModeBanner: false,
      theme: theme.themeData,
      home: const ChatBackendHost(),
    );
  }
}
