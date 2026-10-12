// Doubles de test du matériel Général et de la Liste d'achats : tout en mémoire, en
// direct, avec les actions notées (aucun accès à Firebase).
import 'dart:async';

import 'package:construction_app/models/employee.dart';
import 'package:construction_app/models/liste_achats.dart';
import 'package:construction_app/models/materiel_general.dart';
import 'package:construction_app/services/liste_achats_source.dart';
import 'package:construction_app/services/materiel_general_source.dart';

DateTime tTest(int jour, [int heure = 8]) => DateTime.utc(2026, 10, jour, heure);

EntreeMateriel entreeTest(
  String id, {
  String auteur = 'plusA',
  String nom = 'Plus A',
  DateTime? ajout,
  DateTime? modif,
  String? modifiePar,
  bool complete = false,
  String texte = 'Sangles',
  String quantite = '',
  List<String> photos = const [],
  bool transfere = false,
  String transfereParNom = '',
}) => EntreeMateriel(
  id: id,
  texte: texte,
  quantite: quantite,
  photos: photos,
  transfere: transfere,
  transfereParNom: transfereParNom,
  auteurId: auteur,
  auteurNom: nom,
  dateAjout: ajout ?? tTest(1),
  dateModif: modif,
  modifiePar: modifiePar,
  complete: complete,
);

/// Trois équipes : plusA (3 demandes dont 1 obtenue), plusB « Bernard » (1), adminA (1).
List<EntreeMateriel> jeuTest() => [
  entreeTest('a1', auteur: 'plusA', nom: 'Plus A', ajout: tTest(1, 9), texte: 'Sangles'),
  entreeTest('a2', auteur: 'plusA', nom: 'Plus A', ajout: tTest(2, 9), texte: 'Cordes', complete: true),
  entreeTest('a3', auteur: 'plusA', nom: 'Plus A', ajout: tTest(3, 9), texte: 'Clous 3 po', quantite: '2 boîtes'),
  entreeTest('b1', auteur: 'plusB', nom: 'Bernard', ajout: tTest(2, 10), texte: 'Bâche'),
  entreeTest('c1', auteur: 'adminA', nom: 'Admin A', ajout: tTest(1, 11), texte: 'Marteau'),
];

/// Double du matériel Général : les demandes et les visites en direct.
class FauxSource implements SourceMaterielGeneral {
  List<EntreeMateriel> donnees;
  VisitesGeneral visitesActuelles;
  DateTime maintenant = tTest(20);
  final _ctrlE = StreamController<List<EntreeMateriel>>.broadcast();
  final _ctrlV = StreamController<VisitesGeneral>.broadcast();

  final List<String> marques = []; // auteurs marqués « vus »
  final List<Set<String>> leves = []; // drapeaux « non lu » levés à chaque visite
  final List<List<String>> nonLusPoses = []; // demandes marquées « non lu »
  final List<String> obtenues = []; // « id:true|false »
  final List<String> supprimees = [];
  final List<String> transferees = []; // ids transférés
  final List<String> signaturesTransfert = []; // admin qui transfère
  int abonnementsEntrees = 0;
  bool echecMarquer = false;
  bool echecNonLu = false;
  bool echecObtenue = false;
  bool echecTransfert = false;
  bool erreurLecture = false;

  FauxSource(this.donnees, [Map<String, DateTime>? vus, Set<String>? nonLus])
    : visitesActuelles = VisitesGeneral(vus: {...?vus}, nonLus: {...?nonLus});

  @override
  Stream<List<EntreeMateriel>> entrees(String companyId) async* {
    abonnementsEntrees++;
    if (erreurLecture) throw StateError('lecture refusée');
    yield donnees;
    yield* _ctrlE.stream;
  }

  @override
  Stream<VisitesGeneral> visites(String employeId) async* {
    yield visitesActuelles;
    yield* _ctrlV.stream;
  }

  void pousser(List<EntreeMateriel> nouvelles) {
    donnees = nouvelles;
    _ctrlE.add(nouvelles);
  }

  void _pousserVisites(VisitesGeneral v) {
    visitesActuelles = v;
    _ctrlV.add(v);
  }

  @override
  Future<void> marquerVu({
    required String companyId,
    required String employeId,
    required String auteurId,
    Iterable<String> idsALever = const [],
  }) async {
    marques.add(auteurId);
    leves.add({...idsALever});
    if (echecMarquer) throw StateError('refusé');
    _pousserVisites(
      VisitesGeneral(
        vus: {...visitesActuelles.vus, cleVu(auteurId): maintenant},
        nonLus: visitesActuelles.nonLus.difference(idsALever.toSet()),
      ),
    );
  }

  @override
  Future<void> marquerNonLu({
    required String companyId,
    required String employeId,
    required Iterable<String> entreeIds,
  }) async {
    nonLusPoses.add([...entreeIds]);
    if (echecNonLu) throw StateError('refusé');
    _pousserVisites(
      VisitesGeneral(
        vus: visitesActuelles.vus,
        nonLus: {...visitesActuelles.nonLus, ...entreeIds},
      ),
    );
  }

  @override
  Future<void> definirObtenue(
    EntreeMateriel entree,
    bool obtenue, {
    required String employeId,
  }) async {
    obtenues.add('${entree.id}:$obtenue');
    if (echecObtenue) throw StateError('refusé');
    pousser([
      for (final e in donnees)
        if (e.id == entree.id)
          e.copieAvec(
            complete: obtenue,
            dateModif: maintenant,
            modifiePar: employeId,
          )
        else
          e,
    ]);
  }

  @override
  Future<void> supprimer(EntreeMateriel entree) async {
    supprimees.add(entree.id);
    pousser([
      for (final e in donnees)
        if (e.id != entree.id) e,
    ]);
  }

  @override
  Future<void> transfererAuxAchats(EntreeMateriel entree, Employee admin) async {
    transferees.add(entree.id);
    signaturesTransfert.add(admin.id);
    if (echecTransfert) throw StateError('refusé');
    // La demande reste dans Général, marquée « transférée ».
    pousser([
      for (final e in donnees)
        if (e.id == entree.id)
          e.copieAvec(
            transfere: true,
            transfereParNom: admin.nom,
            dateModif: maintenant,
            modifiePar: admin.id,
          )
        else
          e,
    ]);
  }
}

/// Matériel Général sans aucune demande ni visite : pour les tests d'écrans Admin
/// qui ne s'intéressent pas à Général.
class SourceMaterielGeneralVide extends FauxSource {
  SourceMaterielGeneralVide() : super(const []);
}

/// Double de la Liste d'achats.
class FauxAchats implements SourceListeAchats {
  List<ArticleAchat> donnees;
  final _ctrl = StreamController<List<ArticleAchat>>.broadcast();
  final List<String> achetes = []; // « id:true|false »
  final List<String> retires = [];
  final List<String> employes = []; // admin de chaque action
  int abonnements = 0;
  bool echecAchete = false;
  bool erreurLecture = false;

  FauxAchats(this.donnees);

  void pousser(List<ArticleAchat> nouveaux) {
    donnees = nouveaux;
    _ctrl.add(nouveaux);
  }

  @override
  Stream<List<ArticleAchat>> articles(String companyId) async* {
    abonnements++;
    if (erreurLecture) throw StateError('lecture refusée');
    yield donnees;
    yield* _ctrl.stream;
  }

  @override
  Future<void> definirAchete(
    ArticleAchat article,
    bool achete, {
    required String employeId,
  }) async {
    employes.add(employeId);
    achetes.add('${article.id}:$achete');
    if (echecAchete) throw StateError('refusé');
    pousser([
      for (final a in donnees)
        if (a.id == article.id)
          ArticleAchat(
            id: a.id,
            texte: a.texte,
            quantite: a.quantite,
            photos: a.photos,
            origineId: a.origineId,
            demandeParId: a.demandeParId,
            demandeParNom: a.demandeParNom,
            transfereParNom: a.transfereParNom,
            complete: achete,
            dateAjout: a.dateAjout,
            dateComplete: achete ? tTest(21) : null,
          )
        else
          a,
    ]);
  }

  @override
  Future<void> supprimer(ArticleAchat article, {required String employeId}) async {
    employes.add(employeId);
    retires.add(article.id);
    pousser([
      for (final a in donnees)
        if (a.id != article.id) a,
    ]);
  }
}
