import 'package:flutter/material.dart';

import '../../models/materiel_general.dart';
import '../../services/app_session.dart';
import '../../services/materiel_general_source.dart';
import '../../services/theme_compagnie.dart';
import '../../widgets/confirmer_action.dart';
import '../../widgets/photos_multiples.dart';
import '../../widgets/actualiser.dart';

/// Pastille de couleur : nombre de changements pas encore vus. Rien à l'écran
/// s'il n'y en a pas.
class PastilleNonVus extends StatelessWidget {
  final int nombre;
  const PastilleNonVus(this.nombre, {super.key});

  @override
  Widget build(BuildContext context) {
    if (nombre <= 0) return const SizedBox.shrink();
    return Semantics(
      label: nombre == 1
          ? '1 changement non vu'
          : '$nombre changements non vus',
      child: Container(
        constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
        padding: const EdgeInsets.symmetric(horizontal: 6),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Colors.red.shade600,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          nombre > 99 ? '99+' : '$nombre',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}

/// Suit en direct le nombre de changements du matériel Général que l'admin
/// connecté n'a pas vus (rien suivi pour les autres rôles).
class NonVusGeneral extends StatefulWidget {
  /// Tests : remplace Firestore.
  @visibleForTesting
  final SourceMaterielGeneral? source;
  final Widget Function(BuildContext context, int nonVus) builder;

  const NonVusGeneral({super.key, this.source, required this.builder});

  @override
  State<NonVusGeneral> createState() => _NonVusGeneralState();
}

class _NonVusGeneralState extends State<NonVusGeneral> {
  Stream<List<EntreeMateriel>>? _entrees;
  Stream<VisitesGeneral>? _visites;
  String _moiId = '';

  @override
  void initState() {
    super.initState();
    final moi = AppSession.current;
    if (moi != null && moi.companyId != null && AppSession.estAdmin) {
      final source = widget.source ?? SourceMaterielGeneralFirestore();
      _moiId = moi.id;
      _entrees = source.entrees(moi.companyId!);
      _visites = source.visites(moi.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final entrees = _entrees;
    if (entrees == null) return widget.builder(context, 0);
    return StreamBuilder<List<EntreeMateriel>>(
      stream: entrees,
      builder: (context, demandes) => StreamBuilder<VisitesGeneral>(
        stream: _visites,
        builder: (context, visites) {
          final v = visites.data ?? const VisitesGeneral();
          final n = demandes.hasData
              ? totalNonVus(
                  grouperParAuteur(
                    demandes.data!,
                    moiId: _moiId,
                    vus: v.vus,
                    nonLus: v.nonLus,
                  ),
                )
              : 0;
          return widget.builder(context, n);
        },
      ),
    );
  }
}

/// Admin → Chantiers → Général : le matériel de la remorque, séparé par
/// contremaître et admin, pour acheter équipe par équipe. Une pastille de couleur
/// signale ce qui a changé depuis la dernière visite de cette personne ; un appui
/// long permet de marquer « non lu » ou de transférer à la Liste d'achats.
class MaterielGeneralScreen extends StatefulWidget {
  /// Tests : remplace Firestore.
  @visibleForTesting
  final SourceMaterielGeneral? source;

  const MaterielGeneralScreen({super.key, this.source});

  @override
  State<MaterielGeneralScreen> createState() => _MaterielGeneralScreenState();
}

class _MaterielGeneralScreenState extends State<MaterielGeneralScreen> {
  late final SourceMaterielGeneral _source;
  Stream<List<EntreeMateriel>>? _entrees;
  Stream<VisitesGeneral>? _visites;
  String _companyId = '';
  String _moiId = '';

  /// Groupes ouverts, et ce qui était « non vu » AVANT leur ouverture (dernière
  /// visite et demandes marquées « non lu ») : ces demandes restent marquées
  /// « Nouveau » tant que la page reste ouverte.
  final Set<String> _ouverts = {};
  final Map<String, DateTime> _visiteAvant = {};
  final Map<String, Set<String>> _nonLusAvant = {};

  @override
  void initState() {
    super.initState();
    _source = widget.source ?? SourceMaterielGeneralFirestore();
    final moi = AppSession.current;
    if (moi != null && moi.companyId != null && AppSession.estAdmin) {
      _companyId = moi.companyId!;
      _moiId = moi.id;
      _entrees = _source.entrees(_companyId);
      _visites = _source.visites(_moiId);
    }
  }

  void _message(String texte, {bool erreur = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(texte),
        backgroundColor: erreur ? Colors.red : null,
      ),
    );
  }

  /// Ouvrir un groupe = l'avoir vu : la pastille disparaît, les drapeaux « non
  /// lu » de ce groupe tombent (et ceux de demandes qui n'existent plus).
  void _basculer(
    GroupeAuteur g,
    bool ouvert,
    VisitesGeneral visites,
    Set<String> idsExistants,
  ) {
    final cle = cleVu(g.auteurId);
    final drapeaux = {
      for (final e in g.entrees)
        if (visites.nonLus.contains(e.id)) e.id,
    };
    setState(() {
      if (ouvert) {
        _ouverts.add(cle);
        _visiteAvant[cle] =
            visites.vus[cle] ?? DateTime.fromMillisecondsSinceEpoch(0);
        _nonLusAvant[cle] = drapeaux;
      } else {
        _ouverts.remove(cle);
        _visiteAvant.remove(cle);
        _nonLusAvant.remove(cle);
      }
    });
    if (ouvert && (g.nonVus > 0 || drapeaux.isNotEmpty)) {
      final perimes = visites.nonLus.difference(idsExistants);
      _source
          .marquerVu(
            companyId: _companyId,
            employeId: _moiId,
            auteurId: g.auteurId,
            idsALever: {...drapeaux, ...perimes},
          )
          .catchError((_) {
            // Pas grave : la pastille reviendra à la prochaine ouverture.
          });
    }
  }

  Future<void> _marquerNonLu(List<EntreeMateriel> entrees) async {
    if (entrees.isEmpty) {
      _message('Rien à marquer : aucune demande à acheter.');
      return;
    }
    try {
      await _source.marquerNonLu(
        companyId: _companyId,
        employeId: _moiId,
        entreeIds: [for (final e in entrees) e.id],
      );
      _message(
        entrees.length == 1
            ? 'Marqué comme non lu.'
            : '${entrees.length} demandes marquées comme non lues.',
      );
    } catch (_) {
      _message('Impossible de marquer comme non lu. Réessayez.', erreur: true);
    }
  }

  Future<void> _transferer(EntreeMateriel e) async {
    final moi = AppSession.current;
    if (moi == null) return;
    try {
      await _source.transfererAuxAchats(e, moi);
      _message('« ${e.texte} » transféré à la Liste d\'achats.');
    } catch (_) {
      _message('Transfert impossible. Réessayez.', erreur: true);
    }
  }

  Future<void> _definirObtenue(EntreeMateriel e, bool obtenue) async {
    try {
      await _source.definirObtenue(e, obtenue, employeId: _moiId);
    } catch (_) {
      _message('Modification impossible. Réessayez.', erreur: true);
    }
  }

  Future<void> _supprimer(EntreeMateriel e) async {
    final ok = await confirmerAction(
      context,
      titre: 'Supprimer cette demande ?',
      texte:
          '« ${e.texte} » sera supprimée pour tous. Cette action est irréversible.',
      action: 'Supprimer',
    );
    if (!ok) return;
    try {
      await _source.supprimer(e);
      _message('Demande supprimée.');
    } catch (_) {
      _message('Suppression impossible.', erreur: true);
    }
  }

  /// Appui long sur une demande : marquer « non lu » ou transférer aux achats.
  Future<void> _menuDemande(EntreeMateriel e) async {
    final choix = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(
                e.texte,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            ListTile(
              key: const ValueKey('action_non_lu'),
              leading: const Icon(Icons.mark_email_unread_outlined),
              title: const Text('Marquer comme non lu'),
              onTap: () => Navigator.pop(ctx, 'non_lu'),
            ),
            if (!e.complete && !e.transfere)
              ListTile(
                key: const ValueKey('action_transferer'),
                leading: const Icon(Icons.shopping_cart_checkout),
                title: const Text('Transférer à la Liste d\'achats'),
                onTap: () => Navigator.pop(ctx, 'transferer'),
              ),
          ],
        ),
      ),
    );
    if (choix == 'non_lu') await _marquerNonLu([e]);
    if (choix == 'transferer') await _transferer(e);
  }

  /// Appui long sur une personne : marquer sa liste « non lu » (ses demandes à
  /// acheter).
  Future<void> _menuGroupe(GroupeAuteur g) async {
    final choix = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(
                g.nom,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            ListTile(
              key: const ValueKey('action_groupe_non_lu'),
              leading: const Icon(Icons.mark_email_unread_outlined),
              title: const Text('Marquer comme non lu'),
              subtitle: const Text('Ses demandes à acheter'),
              onTap: () => Navigator.pop(ctx, 'non_lu'),
            ),
          ],
        ),
      ),
    );
    if (choix == 'non_lu') {
      await _marquerNonLu([
        for (final e in g.entrees)
          if (!e.complete && !e.transfere) e,
      ]);
    }
  }

  static String _dateHeure(DateTime? d) {
    if (d == null) return '';
    final l = d.toLocal();
    String deux(int n) => n.toString().padLeft(2, '0');
    return '${deux(l.day)}/${deux(l.month)} ${deux(l.hour)}:${deux(l.minute)}';
  }

  Widget _ligne(EntreeMateriel e, {required bool nouveau}) {
    final detail = [
      if (e.quantite.isNotEmpty) 'Quantité : ${e.quantite}',
      if (e.complete)
        'Obtenu${e.dateComplete == null ? '' : ' le ${_dateHeure(e.dateComplete)}'}'
      else if (e.transfere)
        'Dans la Liste d\'achats${e.transfereParNom.isEmpty ? '' : ' (transféré par ${e.transfereParNom})'}'
      else
        'Demandé le ${_dateHeure(e.dateAjout)}',
    ].join(' • ');
    return ListTile(
      key: ValueKey('entree_${e.id}'),
      onLongPress: () => _menuDemande(e),
      leading: e.photos.isNotEmpty
          ? VignettePhotos(urls: e.photos)
          : Icon(
              e.complete
                  ? Icons.check_circle
                  : (e.transfere
                        ? Icons.shopping_cart_checkout
                        : Icons.shopping_cart_outlined),
              color: e.complete
                  ? Colors.green
                  : (e.transfere
                        ? ThemeCompagnie.accentDe(context)
                        : Colors.orange.shade800),
            ),
      title: Row(
        children: [
          if (nouveau) ...[
            Container(
              key: ValueKey('nouveau_${e.id}'),
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: Colors.red.shade600,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 6),
          ],
          Expanded(
            child: Text(
              e.texte,
              style: TextStyle(
                decoration: e.complete ? TextDecoration.lineThrough : null,
                color: e.complete ? Colors.grey : null,
              ),
            ),
          ),
        ],
      ),
      subtitle: Text(detail, style: const TextStyle(fontSize: 12)),
      trailing: PopupMenuButton<String>(
        key: ValueKey('menu_entree_${e.id}'),
        onSelected: (v) {
          switch (v) {
            case 'supprimer':
              _supprimer(e);
            case 'non_lu':
              _marquerNonLu([e]);
            case 'transferer':
              _transferer(e);
            default:
              _definirObtenue(e, v == 'obtenue');
          }
        },
        itemBuilder: (ctx) => [
          // Une demande dans la Liste d'achats se marque achetée là-bas.
          if (e.complete || !e.transfere)
            PopupMenuItem(
              value: e.complete ? 'manquante' : 'obtenue',
              child: Text(
                e.complete ? 'Remettre comme manquant' : 'Marquer comme obtenu',
              ),
            ),
          const PopupMenuItem(
            value: 'non_lu',
            child: Text('Marquer comme non lu'),
          ),
          if (!e.complete && !e.transfere)
            const PopupMenuItem(
              value: 'transferer',
              child: Text('Transférer à la Liste d\'achats'),
            ),
          const PopupMenuItem(
            value: 'supprimer',
            child: Text('Supprimer', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  Widget _groupe(
    GroupeAuteur g,
    VisitesGeneral visites,
    Set<String> idsExistants,
  ) {
    final cle = cleVu(g.auteurId);
    final baseline = _visiteAvant[cle];
    final drapeauxAvant = _nonLusAvant[cle] ?? const <String>{};
    final parties = [
      if (g.aAcheter > 0) '${g.aAcheter} à acheter',
      if (g.enAchat > 0) '${g.enAchat} dans la Liste d\'achats',
    ];
    final resume = parties.isEmpty ? 'Rien à acheter' : parties.join(' • ');
    return GestureDetector(
      // Appui long sur la personne : marquer sa liste « non lu ».
      onLongPress: () => _menuGroupe(g),
      child: Card(
        child: ExpansionTile(
          key: ValueKey('groupe_${g.auteurId}'),
          initiallyExpanded: _ouverts.contains(cle),
          shape: const Border(),
          collapsedShape: const Border(),
          leading: Icon(
            Icons.person_outline,
            color: ThemeCompagnie.accentDe(context),
          ),
          title: Row(
            children: [
              Flexible(
                child: Text(
                  g.nom,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(width: 8),
              PastilleNonVus(
                g.nonVus,
                key: ValueKey('pastille_groupe_${g.auteurId}'),
              ),
            ],
          ),
          subtitle: Text(
            g.obtenues > 0
                ? '$resume • ${g.obtenues} obtenu${g.obtenues > 1 ? 's' : ''}'
                : resume,
          ),
          onExpansionChanged: (ouvert) =>
              _basculer(g, ouvert, visites, idsExistants),
          children: [
            for (final e in g.entrees)
              _ligne(
                e,
                // Demandes nouvelles depuis la dernière visite, marquées « non lu »
                // avant l'ouverture, ou marquées « non lu » maintenant.
                nouveau:
                    visites.nonLus.contains(e.id) ||
                    (baseline != null &&
                        estNonVu(
                          e,
                          moiId: _moiId,
                          vuLe: baseline,
                          marqueNonLu: drapeauxAvant.contains(e.id),
                        )),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_entrees == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Général')),
        body: const Center(child: Text('Réservé aux administrateurs.')),
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Général')),
      body: FluxActualisable<List<EntreeMateriel>>(
        creerFlux: () => _entrees!,
        builder: (context, demandes) {
          if (demandes.hasError) {
            return const Center(
              child: Text('Impossible de charger le matériel.'),
            );
          }
          if (!demandes.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          return StreamBuilder<VisitesGeneral>(
            stream: _visites,
            builder: (context, visitesSnap) {
              final visites = visitesSnap.data ?? const VisitesGeneral();
              final idsExistants = {for (final e in demandes.data!) e.id};
              final groupes = grouperParAuteur(
                demandes.data!,
                moiId: _moiId,
                vus: visites.vus,
                nonLus: visites.nonLus,
              );
              final total = groupes.fold<int>(0, (s, g) => s + g.aAcheter);
              return ListView(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
                children: [
                  const Padding(
                    padding: EdgeInsets.fromLTRB(4, 0, 4, 8),
                    child: Text(
                      'Matériel de la remorque et sans chantier, séparé par '
                      'contremaître et admin. Ouvrez une personne pour voir sa '
                      'liste ; la pastille rouge signale ce qui a changé depuis '
                      'votre dernière visite. Appui long sur une personne ou une '
                      'demande : marquer « non lu » ou transférer à la Liste '
                      'd\'achats.',
                      key: ValueKey('aide_general_admin'),
                      style: TextStyle(fontSize: 12, color: Colors.black54),
                    ),
                  ),
                  if (groupes.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'Aucun matériel dans Général. Les contremaîtres et les '
                        'admins en ajoutent dans Chantiers → Général.',
                        key: ValueKey('general_vide'),
                        textAlign: TextAlign.center,
                      ),
                    )
                  else ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
                      child: Text(
                        '$total à acheter • ${groupes.length} '
                        '${groupes.length > 1 ? 'personnes' : 'personne'}',
                        key: const ValueKey('general_total'),
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                    for (final g in groupes) _groupe(g, visites, idsExistants),
                  ],
                ],
              );
            },
          );
        },
      ),
    );
  }
}
