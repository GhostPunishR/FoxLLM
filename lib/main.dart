import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:foxgpt_native/foxgpt_native.dart';

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
  String _nativeStatus = 'Non vérifié';

  void _checkNativeBridge() {
    FoxGptNativeEngine? engine;
    try {
      engine = FoxGptNativeEngine();
      setState(() {
        _nativeStatus = 'OK · ${engine!.version}';
      });
    } catch (error) {
      setState(() {
        _nativeStatus = 'Erreur · $error';
      });
    } finally {
      engine?.dispose();
    }
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
                    'Pont natif C++',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(_nativeStatus),
                  const SizedBox(height: 12),
                  FilledButton.tonalIcon(
                    onPressed: _checkNativeBridge,
                    icon: const Icon(Icons.memory),
                    label: const Text('Vérifier le moteur natif'),
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
