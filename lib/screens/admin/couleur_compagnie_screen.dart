import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../services/app_session.dart';
import '../../services/theme_compagnie.dart';

/// Choix de la couleur de l'application pour toute la compagnie.
/// Réservé aux admins (dont le super-admin) ; appliqué par les règles.
class CouleurCompagnieScreen extends StatefulWidget {
  const CouleurCompagnieScreen({super.key});

  @override
  State<CouleurCompagnieScreen> createState() => _CouleurCompagnieScreenState();
}

class _CouleurCompagnieScreenState extends State<CouleurCompagnieScreen> {
  late Color _choisie = ThemeCompagnie.couleur.value;
  late final TextEditingController _hexCtrl = TextEditingController(
    text: ThemeCompagnie.versHex(_choisie),
  );
  String? _erreurHex;
  bool _enCours = false;

  @override
  void dispose() {
    _hexCtrl.dispose();
    super.dispose();
  }

  void _choisir(Color c) {
    setState(() {
      _choisie = c;
      _hexCtrl.text = ThemeCompagnie.versHex(c);
      _erreurHex = null;
    });
  }

  void _saisieHex(String texte) {
    final c = ThemeCompagnie.depuisHex(texte);
    setState(() {
      if (c == null) {
        _erreurHex = 'Format attendu : #RRGGBB (ex. #C62828)';
      } else {
        _erreurHex = null;
        _choisie = c;
      }
    });
  }

  Future<void> _enregistrer(Color couleur) async {
    final companyId = AppSession.current?.companyId;
    if (companyId == null || !AppSession.estAdmin) return;
    setState(() => _enCours = true);
    try {
      await FirebaseFirestore.instance
          .collection('companies')
          .doc(companyId)
          .update({'couleurTheme': ThemeCompagnie.versHex(couleur)});
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Couleur enregistrée pour toute la compagnie.'),
        ),
      );
      Navigator.of(context).pop();
    } catch (_) {
      if (!mounted) return;
      setState(() => _enCours = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Impossible d\'enregistrer la couleur. Réessayez.'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final actuelle = ThemeCompagnie.couleur.value;
    final modifiee = _choisie != actuelle;

    return Scaffold(
      appBar: AppBar(title: const Text('Couleur de l\'application')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Cette couleur s\'applique à toute la compagnie : barres, boutons, '
            'onglets et calculatrice, sur les appareils de tous les employés.',
          ),
          const SizedBox(height: 16),
          _Apercu(couleur: _choisie),
          const SizedBox(height: 20),
          const Text(
            'Couleurs proposées',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              for (final MapEntry(key: nom, value: c)
                  in ThemeCompagnie.palette.entries)
                _Pastille(
                  nom: nom,
                  couleur: c,
                  choisie: c == _choisie,
                  onTap: () => _choisir(c),
                ),
            ],
          ),
          const SizedBox(height: 20),
          const Text(
            'Ou votre couleur exacte',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          TextField(
            key: const ValueKey('champ_hex'),
            controller: _hexCtrl,
            maxLength: 7,
            decoration: InputDecoration(
              labelText: 'Code couleur',
              hintText: '#RRGGBB',
              helperText:
                  'Le code de votre logo, ex. #C62828. Le texte des boutons '
                  's\'ajuste automatiquement pour rester lisible.',
              helperMaxLines: 2,
              errorText: _erreurHex,
              border: const OutlineInputBorder(),
              prefixIcon: Icon(Icons.circle, color: _choisie),
            ),
            onChanged: _saisieHex,
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            key: const ValueKey('enregistrer_couleur'),
            onPressed: (!modifiee || _erreurHex != null || _enCours)
                ? null
                : () => _enregistrer(_choisie),
            icon: const Icon(Icons.check),
            label: const Text('Enregistrer pour la compagnie'),
          ),
          const SizedBox(height: 8),
          if (actuelle != ThemeCompagnie.couleurParDefaut)
            TextButton(
              onPressed: _enCours
                  ? null
                  : () => _enregistrer(ThemeCompagnie.couleurParDefaut),
              child: const Text('Rétablir le vert d\'origine'),
            ),
        ],
      ),
    );
  }
}

/// Aperçu de l'app avec la couleur choisie (avant d'enregistrer).
class _Apercu extends StatelessWidget {
  final Color couleur;
  const _Apercu({required this.couleur});

  @override
  Widget build(BuildContext context) {
    final theme = ThemeCompagnie.construire(couleur);
    final texte = ThemeCompagnie.texteSur(couleur);
    return Theme(
      data: theme,
      child: Card(
        clipBehavior: Clip.antiAlias,
        color: ThemeCompagnie.fondCreme,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              color: couleur,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Text(
                'Chantier+',
                style: TextStyle(
                  color: texte,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(
                    Icons.construction,
                    color: ThemeCompagnie.accent(couleur),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(child: Text('Chantier Tremblay')),
                  FilledButton(
                    onPressed: () {},
                    child: const Text('Soumettre'),
                  ),
                ],
              ),
            ),
            Container(
              color: ThemeCompagnie.surfaceCreme,
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  Icon(Icons.calculate, color: ThemeCompagnie.accent(couleur)),
                  const Icon(
                    Icons.access_time_outlined,
                    color: Color(0xFF8A8066),
                  ),
                  const Icon(
                    Icons.construction_outlined,
                    color: Color(0xFF8A8066),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Pastille extends StatelessWidget {
  final String nom;
  final Color couleur;
  final bool choisie;
  final VoidCallback onTap;

  const _Pastille({
    required this.nom,
    required this.couleur,
    required this.choisie,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: choisie,
      label: nom,
      child: InkWell(
        key: ValueKey('pastille_$nom'),
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(
          width: 76,
          child: Column(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: couleur,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: choisie ? Colors.black87 : Colors.black12,
                    width: choisie ? 3 : 1,
                  ),
                ),
                child: choisie
                    ? Icon(Icons.check, color: ThemeCompagnie.texteSur(couleur))
                    : null,
              ),
              const SizedBox(height: 4),
              Text(
                nom,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 11),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
