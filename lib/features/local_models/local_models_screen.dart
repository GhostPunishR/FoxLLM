// Copyright © 2026 GhostPunishR
// SPDX-License-Identifier: AGPL-3.0-only

import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:foxllm_native/foxllm_native.dart';

import '../../core/llm/last_model_store.dart';
import '../../core/llm/local_backend_provider.dart';
import 'local_model_file.dart';
import 'local_model_library.dart';

class LocalModelsScreen extends ConsumerStatefulWidget {
  const LocalModelsScreen({super.key});

  @override
  ConsumerState<LocalModelsScreen> createState() => _LocalModelsScreenState();
}

class _LocalModelsScreenState extends ConsumerState<LocalModelsScreen> {
  final LocalModelLibrary _library = LocalModelLibrary();

  List<LocalModelFile> _models = const <LocalModelFile>[];
  bool _loading = true;
  bool _importing = false;
  double? _importProgress;
  String? _busyModelPath;
  String? _runtimeDetails;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_refresh());
    unawaited(_refreshRuntimeDetails());
  }

  Future<void> _refresh() async {
    try {
      final models = await _library.listModels();
      if (!mounted) {
        return;
      }
      setState(() {
        _models = models;
        _loading = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loading = false;
        _error = 'Impossible de lire la bibliothèque de modèles : $error';
      });
    }
  }

  Future<void> _refreshRuntimeDetails() async {
    final backend = ref.read(localLlmBackendProvider);
    if (backend.loadedModelPath == null) {
      return;
    }

    try {
      final info = await backend.modelInfo;
      if (!mounted || info == null) {
        return;
      }
      setState(() {
        _runtimeDetails = _formatRuntimeDetails(info);
      });
    } catch (_) {
      // The model list remains usable even if runtime metadata is unavailable.
    }
  }

  Future<void> _importModel() async {
    if (_importing) {
      return;
    }

    final picked = await FilePicker.pickFile(
      dialogTitle: 'Choisir un modèle GGUF',
      type: FileType.custom,
      allowedExtensions: const <String>['gguf'],
    );
    if (picked == null) {
      return;
    }

    setState(() {
      _importing = true;
      _importProgress = 0;
      _error = null;
    });

    try {
      final totalBytes = await picked.length();
      await _library.importModel(
        fileName: picked.name,
        bytes: picked.readAsByteStream(),
        expectedSizeBytes: totalBytes,
        onProgress: (copiedBytes, expectedBytes) {
          if (!mounted || expectedBytes == null || expectedBytes <= 0) {
            return;
          }
          setState(() {
            _importProgress = (copiedBytes / expectedBytes)
                .clamp(0.0, 1.0)
                .toDouble();
          });
        },
      );
      await _refresh();
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = 'Import impossible : $error';
      });
    } finally {
      if (mounted) {
        setState(() {
          _importing = false;
          _importProgress = null;
        });
      }
    }
  }

  Future<void> _loadModel(LocalModelFile model) async {
    if (_busyModelPath != null) {
      return;
    }

    setState(() {
      _busyModelPath = model.path;
      _error = null;
    });

    try {
      final backend = ref.read(localLlmBackendProvider);
      await backend.loadModel(model.path);
      await ref.read(lastModelStoreProvider).save(model.path);
      final info = await backend.modelInfo;
      if (!mounted) {
        return;
      }
      setState(() {
        _runtimeDetails = info == null ? null : _formatRuntimeDetails(info);
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = 'Chargement impossible : $error';
      });
    } finally {
      if (mounted) {
        setState(() {
          _busyModelPath = null;
        });
      }
    }
  }

  Future<void> _unloadModel(LocalModelFile model) async {
    if (_busyModelPath != null) {
      return;
    }

    setState(() {
      _busyModelPath = model.path;
      _error = null;
    });

    try {
      await ref.read(localLlmBackendProvider).unloadModel();
      await ref.read(lastModelStoreProvider).clear();
      if (!mounted) {
        return;
      }
      setState(() {
        _runtimeDetails = null;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = 'Déchargement impossible : $error';
      });
    } finally {
      if (mounted) {
        setState(() {
          _busyModelPath = null;
        });
      }
    }
  }

  Future<void> _deleteModel(LocalModelFile model) async {
    final backend = ref.read(localLlmBackendProvider);
    if (backend.loadedModelPath == model.path) {
      setState(() {
        _error = 'Décharge le modèle avant de le supprimer.';
      });
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Supprimer le modèle ?'),
        content: Text(
          '${model.fileName}\n\nLe fichier GGUF importé dans FoxLLM sera supprimé du téléphone.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }

    setState(() {
      _busyModelPath = model.path;
      _error = null;
    });
    try {
      await _library.deleteModel(model);
      await _refresh();
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = 'Suppression impossible : $error';
      });
    } finally {
      if (mounted) {
        setState(() {
          _busyModelPath = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final backend = ref.read(localLlmBackendProvider);
    final loadedPath = backend.loadedModelPath;

    return Scaffold(
      appBar: AppBar(title: const Text('Modèles locaux')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _importing ? null : _importModel,
        icon: const Icon(Icons.add),
        label: const Text('Importer un GGUF'),
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
          children: <Widget>[
            Text(
              'Bibliothèque locale',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            const Text(
              'Les fichiers sélectionnés sont copiés dans le stockage privé de FoxLLM. Le modèle chargé reste disponible hors connexion.',
            ),
            if (_importing) ...<Widget>[
              const SizedBox(height: 16),
              LinearProgressIndicator(value: _importProgress),
              const SizedBox(height: 8),
              Text(
                _importProgress == null
                    ? 'Import du modèle…'
                    : 'Import ${(_importProgress! * 100).round()} %',
              ),
            ],
            if (_error != null) ...<Widget>[
              const SizedBox(height: 16),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.error_outline),
                  title: Text(_error!),
                ),
              ),
            ],
            const SizedBox(height: 16),
            if (_loading)
              const Center(child: CircularProgressIndicator())
            else if (_models.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(20),
                  child: Text(
                    'Aucun modèle GGUF importé. Utilise « Importer un GGUF » pour ajouter ton premier modèle.',
                  ),
                ),
              )
            else
              for (final model in _models)
                _ModelCard(
                  model: model,
                  isLoaded: loadedPath == model.path,
                  isBusy: _busyModelPath == model.path,
                  runtimeDetails: loadedPath == model.path
                      ? _runtimeDetails
                      : null,
                  onLoad: () => _loadModel(model),
                  onUnload: () => _unloadModel(model),
                  onDelete: () => _deleteModel(model),
                ),
          ],
        ),
      ),
    );
  }
}

class _ModelCard extends StatelessWidget {
  const _ModelCard({
    required this.model,
    required this.isLoaded,
    required this.isBusy,
    required this.runtimeDetails,
    required this.onLoad,
    required this.onUnload,
    required this.onDelete,
  });

  final LocalModelFile model;
  final bool isLoaded;
  final bool isBusy;
  final String? runtimeDetails;
  final VoidCallback onLoad;
  final VoidCallback onUnload;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    model.displayName,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                if (isLoaded)
                  const Chip(
                    avatar: Icon(Icons.memory, size: 18),
                    label: Text('Chargé'),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              runtimeDetails ?? _formatBytes(model.sizeBytes),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                FilledButton.tonalIcon(
                  onPressed: isBusy
                      ? null
                      : isLoaded
                      ? onUnload
                      : onLoad,
                  icon: isBusy
                      ? const SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(isLoaded ? Icons.eject : Icons.play_arrow),
                  label: Text(isLoaded ? 'Décharger' : 'Charger'),
                ),
                TextButton.icon(
                  onPressed: isBusy || isLoaded ? null : onDelete,
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Supprimer'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

String _formatRuntimeDetails(FoxLlmModelInfo info) =>
    '${_formatBytes(info.sizeBytes)} · contexte ${info.contextSize} tokens';

String _formatBytes(int bytes) {
  const units = <String>['o', 'Ko', 'Mo', 'Go', 'To'];
  var value = bytes.toDouble();
  var unitIndex = 0;
  while (value >= 1024 && unitIndex < units.length - 1) {
    value /= 1024;
    unitIndex += 1;
  }

  final decimals = unitIndex == 0 || value >= 100 ? 0 : 1;
  return '${value.toStringAsFixed(decimals)} ${units[unitIndex]}';
}
