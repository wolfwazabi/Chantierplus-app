import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/activite.dart';

/// Lecture du fil « Activité » de l'admin et de sa dernière visite. Remplaçable dans les
/// tests.
abstract class SourceActivite {
  /// Les changements récents de la compagnie, du plus récent au plus ancien.
  Stream<List<Activite>> evenements(String companyId);

  /// Jusqu'à quelle date cet admin a tout vu (null : jamais).
  Stream<DateTime?> vuJusqua(String employeId);

  Future<void> marquerVu({
    required String employeId,
    required String companyId,
    required DateTime jusqua,
  });
}

/// Réunit plusieurs lectures en une seule liste, mise à jour dès que l'une change. Une
/// lecture refusée ou en erreur compte pour « rien » : le fil s'affiche quand même avec ce
/// qui marche. Chaque lecture est annulée quand plus personne n'écoute.
Stream<List<Activite>> fusionnerActivites(
  List<Stream<List<Activite>>> sources, {
  Stream<Map<String, String>>? nomsChantiers,
  int max = 150,
}) {
  late StreamController<List<Activite>> controleur;
  final abonnements = <StreamSubscription<Object?>>[];
  final dernieres = List<List<Activite>?>.filled(sources.length, null);
  Map<String, String>? noms;
  var nomsAttendus = nomsChantiers != null;

  void emettre() {
    if (controleur.isClosed) return;
    if (dernieres.any((l) => l == null)) return;
    if (nomsAttendus && noms == null) return;
    final tout = [for (final liste in dernieres) ...liste!];
    final avecNoms = [
      for (final a in tout)
        a.chantierId.isEmpty ? a : a.avecChantierNom(noms?[a.chantierId] ?? ''),
    ];
    controleur.add(ordonnerActivites(avecNoms, max: max));
  }

  controleur = StreamController<List<Activite>>(
    onListen: () {
      for (var i = 0; i < sources.length; i++) {
        abonnements.add(
          sources[i].listen(
            (liste) {
              dernieres[i] = liste;
              emettre();
            },
            onError: (_) {
              dernieres[i] ??= const [];
              emettre();
            },
          ),
        );
      }
      if (nomsChantiers != null) {
        abonnements.add(
          nomsChantiers.listen(
            (m) {
              noms = m;
              emettre();
            },
            onError: (_) {
              noms ??= const {};
              emettre();
            },
          ),
        );
      }
      if (sources.isEmpty && nomsChantiers == null) controleur.add(const []);
    },
    onCancel: () async {
      for (final a in abonnements) {
        await a.cancel();
      }
      abonnements.clear();
    },
  );
  return controleur.stream;
}

class SourceActiviteFirestore implements SourceActivite {
  static const int _parCollection = 40;
  final FirebaseFirestore _db;

  SourceActiviteFirestore({FirebaseFirestore? db})
    : _db = db ?? FirebaseFirestore.instance;

  Stream<List<Activite>> _collection(
    String nom,
    String companyId,
    String champDate,
    Activite? Function(String id, Map<String, dynamic> d) fabrique,
  ) => _db
      .collection(nom)
      .where('companyId', isEqualTo: companyId)
      .orderBy(champDate, descending: true)
      .limit(_parCollection)
      .snapshots()
      .map((s) => [for (final d in s.docs) ?fabrique(d.id, d.data())]);

  @override
  Stream<List<Activite>> evenements(String companyId) => fusionnerActivites(
    [
      _collection(
        'feuilles_temps',
        companyId,
        'dateModification',
        FabriqueActivite.heures,
      ),
      _collection(
        'chantier_photos',
        companyId,
        'dateAjout',
        FabriqueActivite.photo,
      ),
      _collection(
        'chantier_materiel',
        companyId,
        'dateAjout',
        (id, d) => FabriqueActivite.entree(TypeActivite.materiel, id, d),
      ),
      _collection(
        'chantier_travaux',
        companyId,
        'dateAjout',
        (id, d) => FabriqueActivite.entree(TypeActivite.travaux, id, d),
      ),
      _collection(
        'chantier_extras',
        companyId,
        'dateAjout',
        FabriqueActivite.extra,
      ),
      _collection(
        'chantier_documents',
        companyId,
        'dateAjout',
        FabriqueActivite.document,
      ),
      _collection(
        'liste_achats',
        companyId,
        'dateAjout',
        FabriqueActivite.achat,
      ),
    ],
    nomsChantiers: _db
        .collection('chantiers')
        .where('companyId', isEqualTo: companyId)
        .snapshots()
        .map(
          (s) => {
            for (final d in s.docs)
              d.id: (d.data()['nom'] is String
                  ? d.data()['nom'] as String
                  : ''),
          },
        ),
  );

  @override
  Stream<DateTime?> vuJusqua(String employeId) =>
      _db.collection('activite_vus').doc(employeId).snapshots().map((d) {
        final v = d.data()?['vuJusqua'];
        return v is Timestamp ? v.toDate() : null;
      });

  @override
  Future<void> marquerVu({
    required String employeId,
    required String companyId,
    required DateTime jusqua,
  }) => _db.collection('activite_vus').doc(employeId).set({
    'companyId': companyId,
    'vuJusqua': Timestamp.fromDate(jusqua),
  });
}
