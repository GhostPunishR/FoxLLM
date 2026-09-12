import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/llm/personal_api_settings.dart';
import '../../core/llm/personal_api_settings_provider.dart';
import '../../core/llm/provider_config.dart';

class PersonalApiScreen extends ConsumerStatefulWidget {
  const PersonalApiScreen({super.key});

  @override
  ConsumerState<PersonalApiScreen> createState() => _PersonalApiScreenState();
}

class _PersonalApiScreenState extends ConsumerState<PersonalApiScreen> {
  static const background = Color(0xFF0B0B0B);
  static const surface = Color(0xFF181818);
  static const border = Color(0xFF2A2A2A);
  static const muted = Color(0xFF969696);
  static const orange = Color(0xFFFC6117);

  final _formKey = GlobalKey<FormState>();
  final _baseUrlController = TextEditingController();
  final _modelController = TextEditingController();
  final _apiKeyController = TextEditingController();

  ApiKeyPersistence _persistence = ApiKeyPersistence.device;
  bool _useInChat = false;
  bool _obscureApiKey = true;
  bool _initialized = false;
  bool _saving = false;
  bool _testing = false;

  @override
  void initState() {
    super.initState();
    Future<void>.microtask(_loadInitialState);
  }

  Future<void> _loadInitialState() async {
    try {
      final settings = await ref.read(personalApiSettingsProvider.future);
      if (!mounted) {
        return;
      }
      setState(() {
        _baseUrlController.text = settings.baseUrl;
        _modelController.text = settings.model;
        _persistence = settings.apiKeyPersistence;
        _useInChat = settings.useInChat;
        _initialized = true;
      });
    } catch (error) {
      if (mounted) {
        setState(() => _initialized = true);
        _showSnack('Impossible de charger les réglages API : $error');
      }
    }
  }

  @override
  void dispose() {
    _baseUrlController.dispose();
    _modelController.dispose();
    _apiKeyController.dispose();
    super.dispose();
  }

  Future<PersonalApiSettings?> _save({bool showSuccess = true}) async {
    if (!_formKey.currentState!.validate()) {
      return null;
    }

    setState(() => _saving = true);
    try {
      final settings = await ref.read(personalApiSettingsProvider.notifier).save(
            baseUrl: _baseUrlController.text,
            model: _modelController.text,
            persistence: _persistence,
            useInChat: _useInChat,
            apiKey: _apiKeyController.text,
          );
      _apiKeyController.clear();
      if (!mounted) {
        return settings;
      }
      setState(() {
        _useInChat = settings.useInChat;
      });
      if (showSuccess) {
        _showSnack('Configuration API enregistrée.');
      }
      return settings;
    } catch (error) {
      if (mounted) {
        _showSnack('Enregistrement impossible : $error');
      }
      return null;
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  Future<void> _testConnection() async {
    final saved = await _save(showSuccess: false);
    if (saved == null) {
      return;
    }

    setState(() => _testing = true);
    try {
      await ref.read(personalApiSettingsProvider.notifier).testConnection();
      if (mounted) {
        _showSnack('Connexion réussie. Le fournisseur a répondu.');
      }
    } catch (error) {
      if (mounted) {
        _showSnack('Échec de connexion : $error');
      }
    } finally {
      if (mounted) {
        setState(() => _testing = false);
      }
    }
  }

  Future<void> _deleteApiKey() async {
    try {
      final settings =
          await ref.read(personalApiSettingsProvider.notifier).deleteApiKey();
      if (!mounted) {
        return;
      }
      _apiKeyController.clear();
      setState(() => _useInChat = settings.useInChat);
      _showSnack('Clé API supprimée.');
    } catch (error) {
      if (mounted) {
        _showSnack('Suppression impossible : $error');
      }
    }
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  String? _validateBaseUrl(String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) {
      return 'Indique une base URL.';
    }
    if (!isAllowedPersonalApiBaseUrl(text)) {
      return 'Utilise HTTPS, ou HTTP uniquement sur le réseau local.';
    }
    return null;
  }

  String? _validateModel(String? value) {
    if ((value?.trim() ?? '').isEmpty) {
      return 'Indique le nom du modèle.';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(personalApiSettingsProvider);
    final hasStoredKey = state.value?.hasApiKey ?? false;
    final busy = _saving || _testing;

    return Scaffold(
      backgroundColor: background,
      appBar: AppBar(
        backgroundColor: background,
        surfaceTintColor: Colors.transparent,
        title: const Text(
          'API personnelle',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
        ),
      ),
      body: !_initialized
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(18, 10, 18, 36),
                children: <Widget>[
                  const Text(
                    'Compatible OpenAI',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'FoxGPT envoie directement les requêtes depuis ton téléphone. '
                    'La clé n’est jamais envoyée à un serveur FoxGPT.',
                    style: TextStyle(color: muted, fontSize: 14, height: 1.45),
                  ),
                  const SizedBox(height: 22),
                  _FieldCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        const _FieldLabel('Base URL'),
                        TextFormField(
                          controller: _baseUrlController,
                          keyboardType: TextInputType.url,
                          keyboardAppearance: Brightness.dark,
                          autocorrect: false,
                          enableSuggestions: false,
                          validator: _validateBaseUrl,
                          style: const TextStyle(color: Colors.white),
                          decoration: _inputDecoration(
                            'https://fournisseur.example/v1',
                          ),
                        ),
                        const SizedBox(height: 18),
                        const _FieldLabel('Modèle'),
                        TextFormField(
                          controller: _modelController,
                          keyboardAppearance: Brightness.dark,
                          autocorrect: false,
                          enableSuggestions: false,
                          validator: _validateModel,
                          style: const TextStyle(color: Colors.white),
                          decoration: _inputDecoration('nom-du-modèle'),
                        ),
                        const SizedBox(height: 18),
                        const _FieldLabel('Clé API'),
                        TextFormField(
                          controller: _apiKeyController,
                          keyboardAppearance: Brightness.dark,
                          autocorrect: false,
                          enableSuggestions: false,
                          obscureText: _obscureApiKey,
                          style: const TextStyle(color: Colors.white),
                          decoration: _inputDecoration(
                            hasStoredKey
                                ? 'Clé déjà enregistrée · laisse vide pour la conserver'
                                : 'Clé API',
                          ).copyWith(
                            suffixIcon: IconButton(
                              tooltip: _obscureApiKey ? 'Afficher' : 'Masquer',
                              onPressed: () {
                                setState(() {
                                  _obscureApiKey = !_obscureApiKey;
                                });
                              },
                              icon: Icon(
                                _obscureApiKey
                                    ? Icons.visibility_outlined
                                    : Icons.visibility_off_outlined,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  _FieldCard(
                    child: Column(
                      children: <Widget>[
                        SwitchListTile.adaptive(
                          contentPadding: EdgeInsets.zero,
                          value: _persistence == ApiKeyPersistence.device,
                          activeThumbColor: orange,
                          title: const Text(
                            'Mémoriser sur cet appareil',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          subtitle: const Text(
                            'Désactivé = clé gardée seulement pendant cette session.',
                            style: TextStyle(color: muted, fontSize: 13),
                          ),
                          onChanged: busy
                              ? null
                              : (value) {
                                  setState(() {
                                    _persistence = value
                                        ? ApiKeyPersistence.device
                                        : ApiKeyPersistence.session;
                                  });
                                },
                        ),
                        const Divider(color: border, height: 1),
                        SwitchListTile.adaptive(
                          contentPadding: EdgeInsets.zero,
                          value: _useInChat,
                          activeThumbColor: orange,
                          title: const Text(
                            'Utiliser dans le chat',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          subtitle: const Text(
                            'Quand activé, les messages utilisent cette API au lieu du modèle local.',
                            style: TextStyle(color: muted, fontSize: 13),
                          ),
                          onChanged: busy
                              ? null
                              : (value) => setState(() => _useInChat = value),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    onPressed: busy ? null : () => _save(),
                    icon: _saving
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.save_outlined),
                    label: const Text('Enregistrer'),
                    style: FilledButton.styleFrom(
                      backgroundColor: orange,
                      foregroundColor: Colors.white,
                      minimumSize: const Size.fromHeight(50),
                    ),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: busy ? null : _testConnection,
                    icon: _testing
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.wifi_tethering_outlined),
                    label: const Text('Tester la connexion'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      minimumSize: const Size.fromHeight(50),
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Le test envoie une très courte requête au modèle configuré et peut consommer quelques tokens.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: muted, fontSize: 12, height: 1.4),
                  ),
                  if (hasStoredKey) ...<Widget>[
                    const SizedBox(height: 18),
                    TextButton.icon(
                      onPressed: busy ? null : _deleteApiKey,
                      icon: const Icon(Icons.delete_outline),
                      label: const Text('Supprimer la clé API'),
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.redAccent,
                      ),
                    ),
                  ],
                ],
              ),
            ),
    );
  }

  InputDecoration _inputDecoration(String hintText) {
    return InputDecoration(
      hintText: hintText,
      hintStyle: const TextStyle(color: muted),
      filled: true,
      fillColor: const Color(0xFF222222),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: orange),
      ),
    );
  }
}

class _FieldCard extends StatelessWidget {
  const _FieldCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: _PersonalApiScreenState.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: _PersonalApiScreenState.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: child,
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
