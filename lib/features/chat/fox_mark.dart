import 'package:flutter/material.dart';

/// Renard FoxGPT, identique à celui de l'écran de lancement et de l'icône.
///
/// Le logo est fourni en 1x, 2x et 3x : Flutter choisit la variante adaptée à
/// la densité de l'écran, ce qui garde le tracé net même aux petites tailles.
/// Le fichier est transparent autour du tracé, donc les séparations internes
/// (museau, rayures de la queue, œil) prennent la couleur du fond.
class FoxMark extends StatelessWidget {
  const FoxMark({super.key, this.size = 48});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'FoxGPT',
      image: true,
      child: Image.asset(
        'assets/images/fox_logo.png',
        width: size,
        height: size,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.medium,
      ),
    );
  }
}
