import 'package:flutter/material.dart';

import '../chat/fox_mark.dart';
import 'legal_documents.dart';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    const background = Color(0xFF0B0B0B);
    const muted = Color(0xFF969696);

    return Scaffold(
      backgroundColor: background,
      appBar: AppBar(
        backgroundColor: background,
        surfaceTintColor: Colors.transparent,
        title: const Text(
          'À propos',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 36),
        children: <Widget>[
          const SizedBox(height: 12),
          const Center(child: FoxMark(size: 84)),
          const SizedBox(height: 18),
          const Center(
            child: Text(
              'FoxGPT',
              style: TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(height: 6),
          const Center(
            child: Text(
              'Version $foxGptVersion',
              style: TextStyle(color: muted, fontSize: 14),
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'Client de discussion qui exécute des modèles GGUF directement sur '
            'ton téléphone, ou contacte le fournisseur d’API de ton choix avec '
            'ta propre clé.',
            textAlign: TextAlign.center,
            style: TextStyle(color: muted, fontSize: 14, height: 1.5),
          ),
          const SizedBox(height: 28),
          _AboutCard(
            children: <Widget>[
              _AboutTile(
                icon: Icons.description_outlined,
                title: termsOfUseDocument.title,
                subtitle: 'Ce que tu acceptes en utilisant FoxGPT',
                document: termsOfUseDocument,
              ),
              const Divider(height: 1, color: Color(0xFF292929)),
              _AboutTile(
                icon: Icons.privacy_tip_outlined,
                title: privacyPolicyDocument.title,
                subtitle: 'Ce que deviennent tes données',
                document: privacyPolicyDocument,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AboutCard extends StatelessWidget {
  const _AboutCard({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF181818),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: Color(0xFF242424)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(children: children),
    );
  }
}

class _AboutTile extends StatelessWidget {
  const _AboutTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.document,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final LegalDocument document;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      minLeadingWidth: 28,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      leading: Icon(icon, color: Colors.white),
      title: Text(
        title,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: const TextStyle(color: Color(0xFF909090), fontSize: 13),
      ),
      trailing: const Icon(
        Icons.chevron_right_rounded,
        color: Color(0xFF8D8D8D),
      ),
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (context) => LegalDocumentScreen(document: document),
          ),
        );
      },
    );
  }
}
