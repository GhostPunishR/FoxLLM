import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/llm/personal_api_provider.dart';
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

  final _baseUrlController = TextEditingController();
  final _modelController = TextEditingController();
  final _apiKeyController = TextEditingController();

  String _providerId = openAiPersonalApiProvider.id;
  String _selectedModel = '';
  List<String> _models = const <String>[];
  ApiKeyPersistence _persistence = ApiKeyPersistence.device;
  bool _useInChat = false;
  bool _obscureApiKey = true;
  bool _manualModel = false;
  bool _initialized = false;
  bool _saving = false;
  bool _testing = false;
  bool _loadingModels = false;

  PersonalApiProvider get _provider => personalApiProviderById(_providerId);

  bool get _busy => _saving || _testing || _loadingModels;

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
        _providerId = settings.providerId;
        _baseUrlController.text = settings.baseUrl;
        _modelController.text = settings.model;
        _selectedModel = settings.model;
        _models = settings.model.isEmpty
            ? const <String>[]
            : <String>[settings.model];
        _manualModel = settings.provider.custom;
        _persistence = settings.apiKeyPersistence;
        _useInChat = settings.useInChat;
        _initialized = true;
      });
    } catch (error) {
      if (mounted) {
        setState(() => _initialized = true);
        _showSnack(
          'Impossible de charger les réglages API : '
          '${describePersonalApiError(error)}',
        );
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

  bool _hasStoredKeyForSelectedProvider() {
    final current = ref.read(personalApiSettingsProvider).value;
    return current?.providerId == _providerId && (current?.hasApiKey ?? false);
  }

  String _currentModel() {
    if (_provider.custom || _manualModel) {
      return _modelController.text.trim();
    }
    return _selectedModel.trim();
  }

  String? _validateCustomBaseUrl() {
    if (!_provider.custom) {
      return null;
    }
    final value = _baseUrlController.text.trim();
    if (value.isEmpty) {
      return 'Indique une Base URL.';
    }
    if (!isAllowedPersonalApiBaseUrl(value)) {
      return 'Utilise HTTPS, ou HTTP uniquement sur localhost/réseau privé.';
    }
    return null;
  }

  Future<void> _loadModels() async {
    final baseUrlError = _validateCustomBaseUrl();
    if (baseUrlError != null) {
      _showSnack(baseUrlError);
      return;
    }
    if (_apiKeyController.text.trim().isEmpty &&
        !_hasStoredKeyForSelectedProvider()) {
      _showSnack('Entre la clé API du fournisseur.');
      return;
    }

    setState(() => _loadingModels = true);
    try {
      final models = await ref
          .read(personalApiSettingsProvider.notifier)
          .fetchModels(
            providerId: _providerId,
            baseUrl: _baseUrlController.text,
            apiKey: _apiKeyController.text,
          );
      if (!mounted) {
        return;
      }
      setState(() {
        _models = models;
        if (!models.contains(_selectedModel)) {
          _selectedModel = '';
        }
        _manualModel = false;
      });
      _showSnack('${models.length} modèle(s) disponible(s).');
    } catch (error) {
      if (mounted) {
        _showSnack(
          'Impossible de récupérer les modèles : '
          '${describePersonalApiError(error)}',
        );
      }
    } finally {
      if (mounted) {
        setState(() => _loadingModels = false);
      }
    }
  }

  Future<PersonalApiSettings?> _save({bool showSuccess = true}) async {
    final baseUrlError = _validateCustomBaseUrl();
    if (baseUrlError != null) {
      _showSnack(baseUrlError);
      return null;
    }

    final model = _currentModel();
    if (model.isEmpty) {
      _showSnack('Choisis un modèle, ou saisis son identifiant manuellement.');
      return null;
    }
    if (_apiKeyController.text.trim().isEmpty &&
        !_hasStoredKeyForSelectedProvider()) {
      _showSnack('Entre la clé API du fournisseur.');
      return null;
    }

    setState(() => _saving = true);
    try {
      final settings = await ref
          .read(personalApiSettingsProvider.notifier)
          .save(
            providerId: _providerId,
            baseUrl: _baseUrlController.text,
            model: model,
            persistence: _persistence,
            useInChat: _useInChat,
            apiKey: _apiKeyController.text,
          );
      // Les contrôleurs sont libérés avec l'écran : y toucher après l'await
      // lançait une exception que le `catch` ci-dessous avalait, masquant le
      // fait que l'enregistrement avait bien abouti.
      if (!mounted) {
        return settings;
      }
      _apiKeyController.clear();
      setState(() {
        _providerId = settings.providerId;
        _selectedModel = settings.model;
        _modelController.text = settings.model;
        _useInChat = settings.useInChat;
      });
      if (showSuccess) {
        _showSnack(
          '${settings.provider.displayName} · ${settings.model} enregistré.',
        );
      }
      return settings;
    } catch (error) {
      if (mounted) {
        _showSnack(
          'Enregistrement impossible : ${describePersonalApiError(error)}',
        );
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
    // `_save` rend les réglages même si l'écran a été quitté entre-temps :
    // sans ce garde, le `setState` suivant s'exécute après `dispose()`.
    if (saved == null || !mounted) {
      return;
    }

    setState(() => _testing = true);
    try {
      await ref.read(personalApiSettingsProvider.notifier).testConnection();
      if (mounted) {
        _showSnack(
          'Connexion réussie à ${saved.provider.displayName} avec ${saved.model}.',
        );
      }
    } catch (error) {
      if (mounted) {
        _showSnack('Échec de connexion : ${describePersonalApiError(error)}');
      }
    } finally {
      if (mounted) {
        setState(() => _testing = false);
      }
    }
  }

  Future<void> _deleteApiKey() async {
    try {
      final settings = await ref
          .read(personalApiSettingsProvider.notifier)
          .deleteApiKey();
      if (!mounted) {
        return;
      }
      _apiKeyController.clear();
      setState(() => _useInChat = settings.useInChat);
      _showSnack('Clé API supprimée.');
    } catch (error) {
      if (mounted) {
        _showSnack(
          'Suppression impossible : ${describePersonalApiError(error)}',
        );
      }
    }
  }

  void _selectProvider(String? providerId) {
    if (providerId == null || providerId == _providerId) {
      return;
    }
    final provider = personalApiProviderById(providerId);
    setState(() {
      _providerId = provider.id;
      _models = const <String>[];
      _selectedModel = '';
      _modelController.clear();
      _apiKeyController.clear();
      _manualModel = provider.custom;
      _useInChat = false;
    });
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(personalApiSettingsProvider);
    final hasStoredKey =
        state.value?.providerId == _providerId &&
        (state.value?.hasApiKey ?? false);

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
          : ListView(
              padding: const EdgeInsets.fromLTRB(18, 10, 18, 36),
              children: <Widget>[
                const Text(
                  'Ton fournisseur, ta clé, ton modèle',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'FoxGPT contacte directement le fournisseur depuis ton téléphone. '
                  'Pour les fournisseurs connus, la Base URL est configurée automatiquement '
                  'et les modèles accessibles sont récupérés avec ta clé.',
                  style: TextStyle(color: muted, fontSize: 14, height: 1.45),
                ),
                const SizedBox(height: 22),
                _FieldCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      const _FieldLabel('Fournisseur'),
                      DropdownButtonFormField<String>(
                        key: ValueKey<String>('provider-$_providerId'),
                        initialValue: _providerId,
                        dropdownColor: const Color(0xFF222222),
                        style: const TextStyle(color: Colors.white),
                        decoration: _inputDecoration('Fournisseur'),
                        items: personalApiProviders
                            .map(
                              (provider) => DropdownMenuItem<String>(
                                value: provider.id,
                                child: Text(provider.displayName),
                              ),
                            )
                            .toList(growable: false),
                        onChanged: _busy ? null : _selectProvider,
                      ),
                      if (_provider.custom) ...<Widget>[
                        const SizedBox(height: 18),
                        const _FieldLabel('Base URL'),
                        TextFormField(
                          controller: _baseUrlController,
                          keyboardType: TextInputType.url,
                          keyboardAppearance: Brightness.dark,
                          autocorrect: false,
                          enableSuggestions: false,
                          style: const TextStyle(color: Colors.white),
                          decoration: _inputDecoration(
                            'https://fournisseur.example/v1',
                          ),
                        ),
                      ],
                      const SizedBox(height: 18),
                      const _FieldLabel('Clé API'),
                      TextFormField(
                        controller: _apiKeyController,
                        keyboardAppearance: Brightness.dark,
                        autocorrect: false,
                        enableSuggestions: false,
                        obscureText: _obscureApiKey,
                        style: const TextStyle(color: Colors.white),
                        decoration:
                            _inputDecoration(
                              hasStoredKey
                                  ? 'Clé déjà enregistrée · laisse vide pour la conserver'
                                  : 'Clé API ${_provider.displayName}',
                            ).copyWith(
                              suffixIcon: IconButton(
                                tooltip: _obscureApiKey
                                    ? 'Afficher'
                                    : 'Masquer',
                                onPressed: () {
                                  setState(
                                    () => _obscureApiKey = !_obscureApiKey,
                                  );
                                },
                                icon: Icon(
                                  _obscureApiKey
                                      ? Icons.visibility_outlined
                                      : Icons.visibility_off_outlined,
                                ),
                              ),
                            ),
                      ),
                      const SizedBox(height: 14),
                      if (!_provider.custom)
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: _busy ? null : _loadModels,
                            icon: _loadingModels
                                ? const SizedBox.square(
                                    dimension: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.cloud_download_outlined),
                            label: const Text(
                              'Récupérer les modèles disponibles',
                            ),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.white,
                              minimumSize: const Size.fromHeight(48),
                            ),
                          ),
                        ),
                      const SizedBox(height: 18),
                      const _FieldLabel('Modèle'),
                      if (_provider.custom || _manualModel)
                        TextFormField(
                          controller: _modelController,
                          keyboardAppearance: Brightness.dark,
                          autocorrect: false,
                          enableSuggestions: false,
                          style: const TextStyle(color: Colors.white),
                          decoration: _inputDecoration('identifiant-du-modèle'),
                        )
                      else
                        DropdownButtonFormField<String>(
                          key: ValueKey<String>(
                            'model-$_providerId-${_models.length}-$_selectedModel',
                          ),
                          initialValue:
                              _models.contains(_selectedModel) &&
                                  _selectedModel.isNotEmpty
                              ? _selectedModel
                              : null,
                          isExpanded: true,
                          dropdownColor: const Color(0xFF222222),
                          style: const TextStyle(color: Colors.white),
                          decoration: _inputDecoration(
                            _models.isEmpty
                                ? 'Récupère d’abord les modèles'
                                : 'Choisis un modèle',
                          ),
                          items: _models
                              .map(
                                (model) => DropdownMenuItem<String>(
                                  value: model,
                                  child: Text(
                                    model,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              )
                              .toList(growable: false),
                          onChanged: _busy || _models.isEmpty
                              ? null
                              : (value) {
                                  setState(() {
                                    _selectedModel = value ?? '';
                                    _modelController.text = _selectedModel;
                                  });
                                },
                        ),
                      if (!_provider.custom) ...<Widget>[
                        const SizedBox(height: 6),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton(
                            onPressed: _busy
                                ? null
                                : () {
                                    setState(() {
                                      _manualModel = !_manualModel;
                                      if (_manualModel &&
                                          _modelController.text.isEmpty) {
                                        _modelController.text = _selectedModel;
                                      }
                                    });
                                  },
                            child: Text(
                              _manualModel
                                  ? 'Revenir à la liste des modèles'
                                  : 'Saisir un identifiant manuellement',
                            ),
                          ),
                        ),
                      ],
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
                        onChanged: _busy
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
                        subtitle: Text(
                          'Quand activé, le chat utilise ${_provider.displayName} '
                          'au lieu du modèle GGUF local.',
                          style: const TextStyle(color: muted, fontSize: 13),
                        ),
                        onChanged: _busy
                            ? null
                            : (value) => setState(() => _useInChat = value),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: _busy ? null : () => _save(),
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
                  onPressed: _busy ? null : _testConnection,
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
                  'Le test envoie une très courte requête au modèle sélectionné '
                  'et peut consommer quelques tokens.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: muted, fontSize: 12, height: 1.4),
                ),
                if (hasStoredKey) ...<Widget>[
                  const SizedBox(height: 18),
                  TextButton.icon(
                    onPressed: _busy ? null : _deleteApiKey,
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Supprimer la clé API'),
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.redAccent,
                    ),
                  ),
                ],
              ],
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
      child: Padding(padding: const EdgeInsets.all(16), child: child),
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
