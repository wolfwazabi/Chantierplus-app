import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/activite.dart';
import '../../services/activite_source.dart';
import '../../services/app_session.dart';
import '../../services/theme_compagnie.dart';
import '../../widgets/actualiser.dart';
import '../../widgets/pastille.dart';

IconData iconeActivite(TypeActivite type) => switch (type) {
  TypeActivite.heures => Icons.access_time,
  TypeActivite.photo => Icons.photo_camera_outlined,
  TypeActivite.materiel => Icons.inventory_2_outlined,
  TypeActivite.travaux => Icons.handyman_outlined,
  TypeActivite.extra => Icons.add_task,
  TypeActivite.document => Icons.description_outlined,
  TypeActivite.achat => Icons.shopping_cart_checkout,
};

/// Suit en direct le nombre de changements que l'admin connecté n'a pas vus (rien suivi pour
/// les autres rôles).
class NonVusActivite extends StatelessWidget {
  /// Tests : remplace Firestore.
  @visibleForTesting
  final SourceActivite? source;
  final Widget Function(BuildContext context, int nonVus) builder;

  const NonVusActivite({super.key, this.source, required this.builder});

  @override
  Widget build(BuildContext context) => _SuiviNouveautes<int>(
    source: source,
    vide: 0,
    calcul: nombreNouvelles,
    builder: builder,
  );
}

/// Les nouveautés de chaque chantier (identifiant → nombre), pour les pastilles de la liste
/// des chantiers. Même « dernière visite » que le fil Activité.
class NonVusParChantier extends StatelessWidget {
  /// Tests : remplace Firestore.
  @visibleForTesting
  final SourceActivite? source;
  final Widget Function(BuildContext context, Map<String, int> parChantier)
  builder;

  const NonVusParChantier({super.key, this.source, required this.builder});

  @override
  Widget build(BuildContext context) => _SuiviNouveautes<Map<String, int>>(
    source: source,
    vide: const {},
    calcul: nouvellesParChantier,
    builder: builder,
  );
}

/// Lit le fil et la dernière visite de l'admin connecté et en tire [calcul] ; [vide] pour les
/// autres rôles et tant que la lecture n'est pas arrivée.
class _SuiviNouveautes<T> extends StatefulWidget {
  final SourceActivite? source;
  final T vide;
  final T Function(Iterable<Activite>, DateTime?, String moiId) calcul;
  final Widget Function(BuildContext context, T valeur) builder;

  const _SuiviNouveautes({
    required this.source,
    required this.vide,
    required this.calcul,
    required this.builder,
  });

  @override
  State<_SuiviNouveautes<T>> createState() => _SuiviNouveautesState<T>();
}

class _SuiviNouveautesState<T> extends State<_SuiviNouveautes<T>> {
  Stream<List<Activite>>? _evenements;
  Stream<DateTime?>? _vus;
  String _moiId = '';

  @override
  void initState() {
    super.initState();
    final moi = AppSession.current;
    if (moi != null && moi.companyId != null && AppSession.estAdmin) {
      final source = widget.source ?? SourceActiviteFirestore();
      _moiId = moi.id;
      _evenements = source.evenements(moi.companyId!);
      _vus = source.vuJusqua(moi.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final evenements = _evenements;
    if (evenements == null) return widget.builder(context, widget.vide);
    return StreamBuilder<List<Activite>>(
      stream: evenements,
      builder: (context, liste) => StreamBuilder<DateTime?>(
        stream: _vus,
        builder: (context, vus) => widget.builder(
          context,
          liste.hasData && vus.hasData
              ? widget.calcul(liste.data!, vus.data, _moiId)
              : widget.vide,
        ),
      ),
    );
  }
}

/// Fil « Activité » : ce qui vient d'être saisi ou modifié (heures, photos, matériel, travaux,
/// extras, documents), du plus récent au plus ancien. Une pastille signale chaque nouveauté ;
/// elles s'éteignent quand on quitte la page (ou avec « Tout marquer comme vu »).
class ActiviteScreen extends StatefulWidget {
  /// Tests : remplace Firestore.
  @visibleForTesting
  final SourceActivite? source;

  const ActiviteScreen({super.key, this.source});

  @override
  State<ActiviteScreen> createState() => _ActiviteScreenState();
}

class _ActiviteScreenState extends State<ActiviteScreen> {
  late final SourceActivite _source =
      widget.source ?? SourceActiviteFirestore();
  final String? _companyId = AppSession.current?.companyId;
  final String _moiId = AppSession.current?.id ?? '';

  StreamSubscription<DateTime?>? _abonnementVu;

  /// Jusqu'où l'admin avait tout vu en ouvrant la page : les pastilles se calculent là-dessus
  /// et restent pendant la visite.
  DateTime? _vuAffiche;
  bool _vuRecu = false;

  /// Dernière date enregistrée comme vue (pour n'écrire que si ça change).
  DateTime? _vuEnregistre;
  DateTime? _plusRecent;
  TypeActivite? _filtre;

  bool get _admin => AppSession.estAdmin && _companyId != null;

  @override
  void initState() {
    super.initState();
    if (!_admin) return;
    _abonnementVu = _source
        .vuJusqua(_moiId)
        .listen(
          (v) {
            // Seule la valeur d'ouverture compte pendant la visite.
            if (_vuRecu) return;
            setState(() {
              _vuRecu = true;
              _vuAffiche = v;
              _vuEnregistre = v;
            });
          },
          onError: (_) {
            if (_vuRecu) return;
            setState(() => _vuRecu = true);
          },
        );
  }

  @override
  void dispose() {
    _abonnementVu?.cancel();
    _enregistrerVu();
    super.dispose();
  }

  /// Marque tout ce qui est affiché comme vu (jusqu'au changement le plus récent).
  void _enregistrerVu() {
    final jusqua = _plusRecent;
    final companyId = _companyId;
    if (!_admin || jusqua == null || companyId == null) return;
    final deja = _vuEnregistre;
    if (deja != null && !jusqua.isAfter(deja)) return;
    _vuEnregistre = jusqua;
    _source
        .marquerVu(employeId: _moiId, companyId: companyId, jusqua: jusqua)
        .catchError((_) {});
  }

  void _toutMarquerVu() {
    _enregistrerVu();
    setState(() => _vuAffiche = _plusRecent ?? _vuAffiche);
  }

  /// Première visite : rien n'est « nouveau » (on ne signale pas tout l'historique).
  void _initialiserSiBesoin(List<Activite> liste) {
    if (liste.isEmpty) return;
    _plusRecent = liste.first.date;
    if (_vuRecu && _vuAffiche == null) {
      _vuAffiche = liste.first.date;
      WidgetsBinding.instance.addPostFrameCallback((_) => _enregistrerVu());
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_admin) {
      return Scaffold(
        appBar: AppBar(title: const Text('Activité')),
        body: const Center(child: Text('Réservé aux administrateurs.')),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('Activité'),
        actions: [
          IconButton(
            key: const ValueKey('activite_tout_vu'),
            tooltip: 'Tout marquer comme vu',
            icon: const Icon(Icons.done_all),
            onPressed: _toutMarquerVu,
          ),
        ],
      ),
      body: FluxActualisable<List<Activite>>(
        creerFlux: () => _source.evenements(_companyId!),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Center(
              child: Text('Impossible de charger l\'activité.'),
            );
          }
          if (!snapshot.hasData || !_vuRecu) {
            return const Center(child: CircularProgressIndicator());
          }
          final tout = snapshot.data!;
          _initialiserSiBesoin(tout);
          final visibles = _filtre == null
              ? tout
              : tout.where((a) => a.type == _filtre).toList();
          return Column(
            children: [
              _filtres(tout),
              const Divider(height: 1),
              Expanded(
                child: visibles.isEmpty
                    ? messageActualisable(
                        const Padding(
                          padding: EdgeInsets.all(24),
                          child: Text(
                            'Aucune activité récente.',
                            key: ValueKey('activite_vide'),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      )
                    : ListView.separated(
                        itemCount: visibles.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (context, i) => _tuile(visibles[i]),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _filtres(List<Activite> tout) {
    final types = [for (final t in TypeActivite.values) t];
    return SizedBox(
      height: 56,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              key: const ValueKey('activite_filtre_tout'),
              label: Text('Tout'),
              selected: _filtre == null,
              onSelected: (_) => setState(() => _filtre = null),
            ),
          ),
          for (final t in types)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                key: ValueKey('activite_filtre_${t.name}'),
                label: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(t.libelle),
                    if (nombreNouvelles(
                          tout.where((a) => a.type == t),
                          _vuAffiche,
                          _moiId,
                        ) >
                        0) ...[
                      const SizedBox(width: 6),
                      PastilleNombre(
                        nombreNouvelles(
                          tout.where((a) => a.type == t),
                          _vuAffiche,
                          _moiId,
                        ),
                        key: ValueKey('activite_pastille_${t.name}'),
                      ),
                    ],
                  ],
                ),
                selected: _filtre == t,
                onSelected: (_) =>
                    setState(() => _filtre = _filtre == t ? null : t),
              ),
            ),
        ],
      ),
    );
  }

  Widget _tuile(Activite a) {
    final nouvelle = estNouvelle(a, _vuAffiche, _moiId);
    return ListTile(
      key: ValueKey('activite_${a.id}'),
      leading: Icon(
        iconeActivite(a.type),
        color: ThemeCompagnie.accentDe(context),
      ),
      title: Text(
        phraseActivite(a),
        style: TextStyle(
          fontWeight: nouvelle ? FontWeight.bold : FontWeight.normal,
        ),
      ),
      subtitle: Text(
        a.detail.isEmpty
            ? dateActivite(a.date)
            : '${dateActivite(a.date)} · ${a.detail}',
        style: const TextStyle(fontSize: 12),
      ),
      trailing: nouvelle
          ? PointNouveau(key: ValueKey('activite_point_${a.id}'))
          : null,
    );
  }
}
