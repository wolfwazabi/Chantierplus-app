import 'package:flutter/material.dart';

import '../models/chantier.dart';

// Lettres accentuées → lettre de base, pour chercher sans se soucier des
// accents : « jerome » trouve « Jérôme ».
const Map<String, String> _sansAccents = {
  'à': 'a',
  'â': 'a',
  'ä': 'a',
  'á': 'a',
  'ã': 'a',
  'å': 'a',
  'ç': 'c',
  'é': 'e',
  'è': 'e',
  'ê': 'e',
  'ë': 'e',
  'î': 'i',
  'ï': 'i',
  'í': 'i',
  'ì': 'i',
  'ô': 'o',
  'ö': 'o',
  'ó': 'o',
  'ò': 'o',
  'õ': 'o',
  'ù': 'u',
  'û': 'u',
  'ü': 'u',
  'ú': 'u',
  'ÿ': 'y',
  'ý': 'y',
  'ñ': 'n',
  'œ': 'oe',
  'æ': 'ae',
};

/// Texte normalisé pour la recherche : minuscules, sans accents, la
/// ponctuation remplacée par des espaces (« St-Denis, » → « st denis »).
String normaliserRecherche(String texte) {
  final buffer = StringBuffer();
  for (final lettre in texte.toLowerCase().split('')) {
    buffer.write(_sansAccents[lettre] ?? lettre);
  }
  return buffer.toString().replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();
}

/// Vrai si chaque mot de [requete] apparaît dans le nom OU l'adresse du
/// chantier, dans n'importe quel ordre. Une requête vide correspond à tout.
bool chantierCorrespond(Chantier chantier, String requete) {
  final mots = normaliserRecherche(requete)
      .split(' ')
      .where((m) => m.isNotEmpty);
  final cible = normaliserRecherche('${chantier.nom} ${chantier.adresse}');
  return mots.every(cible.contains);
}

/// Ouvre la recherche de chantier par nom ou adresse. Retourne le chantier
/// choisi, ou null si l'utilisateur ferme sans choisir.
Future<Chantier?> rechercherChantier(
  BuildContext context,
  List<Chantier> chantiers,
) {
  return showModalBottomSheet<Chantier>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _RechercheChantier(chantiers: chantiers),
  );
}

/// Bouton « … » placé à côté d'une liste de chantiers.
class BoutonRechercheChantier extends StatelessWidget {
  final List<Chantier> chantiers;
  final ValueChanged<Chantier>? onChoisi;

  const BoutonRechercheChantier({
    super.key,
    required this.chantiers,
    required this.onChoisi,
  });

  @override
  Widget build(BuildContext context) {
    final actif = onChoisi != null && chantiers.isNotEmpty;
    return IconButton.outlined(
      key: const ValueKey('bouton_recherche_chantier'),
      tooltip: 'Chercher un chantier par nom ou adresse',
      icon: const Icon(Icons.more_horiz),
      onPressed: !actif
          ? null
          : () async {
              final choisi = await rechercherChantier(context, chantiers);
              if (choisi != null) onChoisi!(choisi);
            },
    );
  }
}

class _RechercheChantier extends StatefulWidget {
  final List<Chantier> chantiers;

  const _RechercheChantier({required this.chantiers});

  @override
  State<_RechercheChantier> createState() => _RechercheChantierState();
}

class _RechercheChantierState extends State<_RechercheChantier> {
  String _requete = '';

  @override
  Widget build(BuildContext context) {
    // « Général » (matériel de la remorque), quand il est proposé, reste premier.
    final resultats =
        widget.chantiers.where((c) => chantierCorrespond(c, _requete)).toList()
          ..sort((a, b) {
            final ga = a.id == idChantierGeneral;
            final gb = b.id == idChantierGeneral;
            if (ga != gb) return ga ? -1 : 1;
            return a.nom.compareTo(b.nom);
          });

    return Padding(
      // Remonte au-dessus du clavier.
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.7,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: TextField(
                key: const ValueKey('champ_recherche_chantier'),
                autofocus: true,
                textInputAction: TextInputAction.search,
                decoration: const InputDecoration(
                  labelText: 'Nom ou adresse du chantier',
                  hintText: 'ex. : Tremblay, 123 rue Principale…',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.search),
                ),
                onChanged: (v) => setState(() => _requete = v),
                // Entrée : choisit le chantier s'il est le seul résultat
                // (recalculé à partir du texte tapé, pas de l'affichage).
                onSubmitted: (texte) {
                  final uniques = widget.chantiers
                      .where((c) => chantierCorrespond(c, texte))
                      .toList();
                  if (uniques.length == 1) {
                    Navigator.pop(context, uniques.first);
                  }
                },
              ),
            ),
            Expanded(
              child: resultats.isEmpty
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Text(
                          'Aucun chantier ne correspond à ce nom ou à cette adresse.',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    )
                  : ListView.separated(
                      itemCount: resultats.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, i) {
                        final c = resultats[i];
                        return ListTile(
                          leading: Icon(
                            c.id == idChantierGeneral
                                ? Icons.local_shipping_outlined
                                : Icons.construction,
                          ),
                          title: Text(
                            c.nom,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          subtitle: c.adresse.isEmpty
                              ? const Text('Adresse non indiquée')
                              : Text(c.adresse),
                          onTap: () => Navigator.pop(context, c),
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
