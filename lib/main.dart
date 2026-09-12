import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/llm/local_llm_backend.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ProviderScope(child: FoxGptApp()));
}

class FoxGptApp extends StatelessWidget {
  const FoxGptApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'FoxGPT',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFFFF7A1A),
        brightness: Brightness.dark,
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  LocalLlmBackend? _localBackend;
  String _nativeStatus = 'Non vérifié';
  bool _checkingNative = false;

  Future<void> _checkNativeBridge() async {
    if (_checkingNative) {
      return;
    }

    setState(() {
      _checkingNative = true;
      _nativeStatus = 'Vérification du worker…';
    });

    final backend = _localBackend ??= LocalLlmBackend();

    try {
      final version = await backend.nativeVersion;
      if (!mounted) {
        return;
      }
      setState(() {
        _nativeStatus = 'OK · $version';
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _nativeStatus = 'Erreur · $error';
      });
    } finally {
      if (mounted) {
        setState(() {
          _checkingNative = false;
        });
      }
    }
  }

  @override
  void dispose() {
    final backend = _localBackend;
    if (backend != null) {
      unawaited(backend.dispose());
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('FoxGPT')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: <Widget>[
          Text(
            'Choisis où ton modèle s’exécute.',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          Text(
            'FoxGPT utilisera soit un modèle local sur le téléphone, soit la clé API personnelle de l’utilisateur.',
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          const SizedBox(height: 24),
          const _ModeCard(
            icon: Icons.smartphone,
            title: 'Local',
            subtitle: 'GGUF · C++ · llama.cpp · hors connexion',
          ),
          const SizedBox(height: 12),
          const _ModeCard(
            icon: Icons.cloud_outlined,
            title: 'API personnelle',
            subtitle:
                'BYOK · clé stockée localement · connexion directe au fournisseur',
          ),
          const SizedBox(height: 24),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    'Worker natif C++',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(_nativeStatus),
                  const SizedBox(height: 12),
                  FilledButton.tonalIcon(
                    onPressed: _checkingNative ? null : _checkNativeBridge,
                    icon: _checkingNative
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.memory),
                    label: Text(
                      _checkingNative
                          ? 'Vérification…'
                          : 'Vérifier le moteur natif',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ModeCard extends StatelessWidget {
  const _ModeCard({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 20,
          vertical: 12,
        ),
        leading: Icon(icon, size: 32),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
      ),
    );
  }
}
