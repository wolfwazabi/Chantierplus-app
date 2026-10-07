import 'package:flutter/material.dart';

import '../../models/materiel_general.dart';
import '../../services/app_session.dart';
import '../../services/materiel_general_source.dart';
import '../../services/theme_compagnie.dart';
import '../../widgets/confirmer_action.dart';

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
  Stream<Map<String, DateTime>>? _vus;
  String _moiId = '';

  @override
  void initState() {
    super.initState();
    final moi = AppSession.current;
    if (moi != null && moi.companyId != null && AppSession.estAdmin) {
      final source = widget.source ?? SourceMaterielGeneralFirestore();
      _moiId = moi.id;
      _entrees = source.entrees(moi.companyId!);
      _vus = source.vus(moi.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final entrees = _entrees;
    if (entrees == null) return widget.builder(context, 0);
    return StreamBuilder<List<EntreeMateriel>>(
      stream: entrees,
      builder: (context, demandes) => StreamBuilder<Map<String, DateTime>>(
        stream: _vus,
        builder: (context, vus) {
          final n = demandes.hasData
              ? totalNonVus(
                  grouperParAuteur(
                    demandes.data!,
                    moiId: _moiId,
                    vus: vus.data ?? const {},
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
/// signale ce qui a changé depuis la dernière visite de cette personne.
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
  Stream<Map<String, DateTime>>? _vus;
  String _companyId = '';
  String _moiId = '';

  /// Groupes ouverts, et la dernière visite d'AVANT leur ouverture : les
  /// demandes plus récentes sont marquées « Nouveau » tant que la page reste ouverte.
  final Set<String> _ouverts = {};
  final Map<String, DateTime> _visiteAvant = {};

  @override
  void initState() {
    super.initState();
    _source = widget.source ?? SourceMaterielGeneralFirestore();
    final moi = AppSession.current;
    if (moi != null && moi.companyId != null && AppSession.estAdmin) {
      _companyId = moi.companyId!;
      _moiId = moi.id;
      _entrees = _source.entrees(_companyId);
      _vus = _source.vus(_moiId);
    }
  }

  void _message(String texte, {bool erreur = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(texte), backgroundColor: erreur ? Colors.red : null),
    );
  }

  /// Ouvrir un groupe = l'avoir vu : la pastille disparaît.
  void _basculer(GroupeAuteur g, bool ouvert, Map<String, DateTime> vus) {
    final cle = cleVu(g.auteurId);
    setState(() {
      if (ouvert) {
        _ouverts.add(cle);
        _visiteAvant[cle] = vus[cle] ?? DateTime.fromMillisecondsSinceEpoch(0);
      } else {
        _ouverts.remove(cle);
        _visiteAvant.remove(cle);
      }
    });
    if (ouvert && g.nonVus > 0) {
      _source
          .marquerVu(
            companyId: _companyId,
            employeId: _moiId,
            auteurId: g.auteurId,
          )
          .catchError((_) {
            // Pas grave : la pastille reviendra à la prochaine ouverture.
          });
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
      texte: '« ${e.texte} » sera supprimée pour tous. Cette action est irréversible.',
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
      else
        'Demandé le ${_dateHeure(e.dateAjout)}',
    ].join(' • ');
    return ListTile(
      key: ValueKey('entree_${e.id}'),
      leading: e.photoUrl != null
          ? ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Image.network(
                e.photoUrl!,
                width: 44,
                height: 44,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => const SizedBox(
                  width: 44,
                  height: 44,
                  child: Icon(Icons.broken_image_outlined),
                ),
              ),
            )
          : Icon(
              e.complete ? Icons.check_circle : Icons.shopping_cart_outlined,
              color: e.complete ? Colors.green : Colors.orange.shade800,
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
          if (v == 'supprimer') {
            _supprimer(e);
          } else {
            _definirObtenue(e, v == 'obtenue');
          }
        },
        itemBuilder: (ctx) => [
          PopupMenuItem(
            value: e.complete ? 'manquante' : 'obtenue',
            child: Text(
              e.complete ? 'Remettre comme manquant' : 'Marquer comme obtenu',
            ),
          ),
          const PopupMenuItem(
            value: 'supprimer',
            child: Text('Supprimer', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  Widget _groupe(GroupeAuteur g, Map<String, DateTime> vus) {
    final cle = cleVu(g.auteurId);
    final baseline = _visiteAvant[cle];
    final resume = g.aAcheter == 0
        ? 'Rien à acheter'
        : '${g.aAcheter} à acheter';
    return Card(
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
          g.obtenues > 0 ? '$resume • ${g.obtenues} obtenu${g.obtenues > 1 ? 's' : ''}' : resume,
        ),
        onExpansionChanged: (ouvert) => _basculer(g, ouvert, vus),
        children: [
          for (final e in g.entrees)
            _ligne(
              e,
              nouveau:
                  baseline != null &&
                  estNonVu(e, moiId: _moiId, vuLe: baseline),
            ),
        ],
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
      body: StreamBuilder<List<EntreeMateriel>>(
        stream: _entrees,
        builder: (context, demandes) {
          if (demandes.hasError) {
            return const Center(child: Text('Impossible de charger le matériel.'));
          }
          if (!demandes.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          return StreamBuilder<Map<String, DateTime>>(
            stream: _vus,
            builder: (context, vusSnap) {
              final vus = vusSnap.data ?? const <String, DateTime>{};
              final groupes = grouperParAuteur(
                demandes.data!,
                moiId: _moiId,
                vus: vus,
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
                      'votre dernière visite.',
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
                    for (final g in groupes) _groupe(g, vus),
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
