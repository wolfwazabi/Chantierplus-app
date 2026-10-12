// Matériel « Général » (remorque, sans chantier) : auteurs, groupes par personne,
// changements non vus, et les données écrites (les règles Firestore exigent ces champs).
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:construction_app/models/chantier.dart';
import 'package:construction_app/models/employee.dart';
import 'package:construction_app/models/liste_achats.dart';
import 'package:construction_app/models/materiel_general.dart';
import 'package:construction_app/models/photos_entree.dart';
import 'package:flutter_test/flutter_test.dart';

DateTime _t(int jour, [int heure = 8]) => DateTime.utc(2026, 10, jour, heure);

EntreeMateriel _e(
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
  dateAjout: ajout ?? _t(1),
  dateModif: modif,
  modifiePar: modifiePar,
  complete: complete,
);

Employee _emp(String id, String nom, EmployeeRole role) => Employee(
  id: id,
  companyId: 'A',
  companyNom: 'Alpha',
  nom: nom,
  role: role,
);

void main() {
  group('« Général » n\'est pas un chantier', () {
    test('identifiant réservé, jamais un identifiant Firestore', () {
      expect(idChantierGeneral, '_general');
      expect(chantierGeneral.id, idChantierGeneral);
      expect(chantierGeneral.nom, 'Général');
      // Les identifiants Firestore ne commencent pas par « _ ».
      expect(RegExp(r'^[A-Za-z0-9]{20}$').hasMatch(idChantierGeneral), isFalse);
    });

    test('sansGeneral : jamais proposé pour les heures', () {
      const reels = [
        Chantier(id: 'c1', companyId: 'A', nom: 'Chalet', adresse: ''),
        Chantier(id: 'c2', companyId: 'A', nom: 'Garage', adresse: ''),
      ];
      expect(sansGeneral([chantierGeneral, ...reels]).map((c) => c.id), ['c1', 'c2']);
      expect(sansGeneral(reels), reels);
      expect(sansGeneral(const []), isEmpty);
    });
  });

  group('lecture d\'une entrée', () {
    test('champs complets', () {
      final e = EntreeMateriel.fromMap('x', {
        'texte': 'Cordes',
        'quantite': '3',
        'photoUrl': 'https://exemple.test/p.jpg',
        'complete': true,
        'ajoutePar': 'plusA',
        'ajouteParNom': 'Plus A',
        'dateAjout': Timestamp.fromDate(_t(1)),
        'dateModif': Timestamp.fromDate(_t(2)),
        'modifiePar': 'adminA',
        'dateComplete': Timestamp.fromDate(_t(3)),
      });
      expect(e.texte, 'Cordes');
      expect(e.quantite, '3');
      expect(e.photoUrl, 'https://exemple.test/p.jpg');
      expect(e.complete, isTrue);
      expect(e.auteurId, 'plusA');
      expect(e.auteurNom, 'Plus A');
      // Timestamp.toDate() rend l'heure locale : on compare les instants.
      expect(e.dateAjout, _t(1).toLocal());
      expect(e.dateModif, _t(2).toLocal());
      expect(e.dateChangement, _t(2).toLocal());
      expect(e.modifiePar, 'adminA');
      expect(e.changePar, 'adminA');
      expect(e.dateComplete, _t(3).toLocal());
    });

    test('champs absents ou de mauvais type : valeurs par défaut, sans erreur', () {
      final e = EntreeMateriel.fromMap('y', {
        'texte': 5,
        'quantite': 12,
        'photoUrl': '',
        'dateAjout': 'hier',
        'ajoutePar': null,
      });
      expect(e.texte, '');
      expect(e.quantite, '12');
      expect(e.photoUrl, isNull);
      expect(e.complete, isFalse);
      expect(e.auteurId, '');
      expect(e.dateAjout, isNull);
      expect(e.dateChangement, isNull);
      expect(e.changePar, '');
    });

    test('dernier changement = modification, sinon ajout ; auteur tant que personne d\'autre n\'a touché', () {
      final sansModif = _e('a', ajout: _t(1));
      expect(sansModif.dateChangement, _t(1));
      expect(sansModif.changePar, 'plusA');
      final modif = _e('b', ajout: _t(1), modif: _t(4), modifiePar: 'adminA');
      expect(modif.dateChangement, _t(4));
      expect(modif.changePar, 'adminA');
    });
  });

  group('changement non vu (estNonVu)', () {
    test('jamais visité : tout ce que les autres ont fait est nouveau', () {
      expect(estNonVu(_e('a'), moiId: 'adminA'), isTrue);
    });

    test('visité après le changement : plus rien de nouveau', () {
      expect(estNonVu(_e('a', ajout: _t(1)), moiId: 'adminA', vuLe: _t(2)), isFalse);
    });

    test('changé après la visite : nouveau', () {
      expect(
        estNonVu(_e('a', ajout: _t(1), modif: _t(3), modifiePar: 'plusA'), moiId: 'adminA', vuLe: _t(2)),
        isTrue,
      );
    });

    test('mes propres changements ne sont jamais nouveaux pour moi', () {
      // Une demande que j\'ai ajoutée, ou que j\'ai moi-même marquée « obtenue ».
      expect(estNonVu(_e('a', auteur: 'adminA'), moiId: 'adminA'), isFalse);
      expect(
        estNonVu(_e('b', ajout: _t(1), modif: _t(5), modifiePar: 'adminA'), moiId: 'adminA', vuLe: _t(2)),
        isFalse,
      );
    });

    test('mais le changement d\'une autre personne sur ma demande l\'est', () {
      final e = _e('c', auteur: 'adminA', ajout: _t(1), modif: _t(5), modifiePar: 'plusA');
      expect(estNonVu(e, moiId: 'adminA', vuLe: _t(2)), isTrue);
    });

    test('heure du serveur pas encore reçue (écriture en cours) : ignoré', () {
      expect(estNonVu(const EntreeMateriel(id: 'z', texte: 'x', auteurId: 'plusA'), moiId: 'adminA'), isFalse);
    });

    test('à l\'instant exact de la visite : déjà vu', () {
      expect(estNonVu(_e('a', ajout: _t(2)), moiId: 'adminA', vuLe: _t(2)), isFalse);
    });
  });

  group('groupes par contremaître / admin', () {
    final entrees = [
      _e('a1', auteur: 'plusA', nom: 'Plus A', ajout: _t(1, 9)),
      _e('a2', auteur: 'plusA', nom: 'Plus A', ajout: _t(2, 9), complete: true),
      _e('a3', auteur: 'plusA', nom: 'Plus A', ajout: _t(3, 9)),
      _e('b1', auteur: 'plusB', nom: 'Bernard', ajout: _t(2, 10)),
      _e('c1', auteur: 'adminA', nom: 'Admin A', ajout: _t(1, 11)),
    ];

    test('un groupe par personne, dans l\'ordre alphabétique (stable)', () {
      final g = grouperParAuteur(entrees, moiId: 'adminA');
      expect(g.map((x) => x.nom), ['Admin A', 'Bernard', 'Plus A']);
      expect(g.map((x) => x.entrees.length), [1, 1, 3]);
    });

    test('dans un groupe : à acheter d\'abord (récent en premier), obtenues ensuite', () {
      final plus = grouperParAuteur(entrees, moiId: 'adminA').firstWhere((x) => x.auteurId == 'plusA');
      expect(plus.entrees.map((e) => e.id), ['a3', 'a1', 'a2']);
      expect(plus.aAcheter, 2);
      expect(plus.obtenues, 1);
    });

    test('pastille : changements des autres seulement (mon groupe à moi : aucun)', () {
      final g = grouperParAuteur(entrees, moiId: 'adminA');
      final parId = {for (final x in g) x.auteurId: x.nonVus};
      expect(parId, {'adminA': 0, 'plusB': 1, 'plusA': 3});
      expect(totalNonVus(g), 4);
    });

    test('la visite d\'un groupe n\'efface que ce groupe', () {
      final vus = {'plusA': _t(10)};
      final g = grouperParAuteur(entrees, moiId: 'adminA', vus: vus);
      final parId = {for (final x in g) x.auteurId: x.nonVus};
      expect(parId, {'adminA': 0, 'plusB': 1, 'plusA': 0});
      expect(totalNonVus(g), 1);
    });

    test('une nouvelle demande après la visite rallume la pastille de cette personne', () {
      final vus = {'plusA': _t(10), 'plusB': _t(10)};
      final avec = [...entrees, _e('a4', auteur: 'plusA', nom: 'Plus A', ajout: _t(11))];
      final g = grouperParAuteur(avec, moiId: 'adminA', vus: vus);
      expect({for (final x in g) x.auteurId: x.nonVus}, {'adminA': 0, 'plusB': 0, 'plusA': 1});
    });

    test('une modification (ex. quantité changée) compte aussi', () {
      final vus = {'plusA': _t(10)};
      final modifiee = _e('a1', auteur: 'plusA', nom: 'Plus A', ajout: _t(1), modif: _t(12), modifiePar: 'plusA');
      final g = grouperParAuteur([modifiee], moiId: 'adminA', vus: vus);
      expect(g.single.nonVus, 1);
    });

    test('nom : le plus récent non vide ; sans nom : « Auteur inconnu »', () {
      final g = grouperParAuteur([
        _e('1', auteur: 'p', nom: 'Ancien nom', ajout: _t(1)),
        _e('2', auteur: 'p', nom: 'Nouveau nom', ajout: _t(5)),
        _e('3', auteur: '', nom: '', ajout: _t(1)),
      ], moiId: 'adminA');
      expect(g.map((x) => x.nom), containsAll(['Nouveau nom', nomAuteurInconnu]));
    });

    test('aucune demande : aucun groupe', () {
      expect(grouperParAuteur(const [], moiId: 'adminA'), isEmpty);
    });

    test('clé de visite : jamais vide', () {
      expect(cleVu('plusA'), 'plusA');
      expect(cleVu(''), '_inconnu');
      final g = grouperParAuteur([_e('1', auteur: '', nom: '')], moiId: 'adminA', vus: {'_inconnu': _t(9)});
      expect(g.single.nonVus, 0);
    });
  });

  group('document « déjà vu »', () {
    test('lit les dates par personne, ignore le reste', () {
      final m = vusDepuisDonnees({
        'companyId': 'A',
        'vus': {'plusA': Timestamp.fromDate(_t(5)), 'x': 'pas une date', 'plusB': Timestamp.fromDate(_t(6))},
      });
      expect(m, {'plusA': _t(5).toLocal(), 'plusB': _t(6).toLocal()});
    });

    test('absent ou illisible : rien de vu', () {
      expect(vusDepuisDonnees(null), isEmpty);
      expect(vusDepuisDonnees({}), isEmpty);
      expect(vusDepuisDonnees({'vus': 'oui'}), isEmpty);
    });
  });

  group('filtre par personne', () {
    final liste = [_e('a', auteur: 'p1'), _e('b', auteur: 'p2'), _e('c', auteur: 'p1')];
    test('une personne', () => expect(filtrerParAuteur(liste, 'p1').map((e) => e.id), ['a', 'c']));
    test('tout le monde', () => expect(filtrerParAuteur(liste, null).length, 3));
    test('personne inconnue', () => expect(filtrerParAuteur(liste, 'zz'), isEmpty));
  });

  group('données écrites dans Firestore', () {
    final contremaitre = _emp('plusA', 'Plus A', EmployeeRole.plus);

    test('nouvelle entrée Général : porte l\'auteur (id et nom)', () {
      final d = donneesNouvelleEntree(
        companyId: 'A',
        chantierId: idChantierGeneral,
        texte: 'Sangles',
        quantite: '4',
        photos: ['https://exemple.test/p.jpg', 'https://exemple.test/q.jpg'],
        auteur: contremaitre,
      );
      expect(d.keys.toSet(), {
        'companyId', 'chantierId', 'texte', 'complete', 'dateAjout', 'photoUrl', 'photoUrls', 'quantite',
        'ajoutePar', 'ajouteParNom',
      });
      expect(d['photoUrl'], 'https://exemple.test/p.jpg');
      expect(d['photoUrls'], ['https://exemple.test/p.jpg', 'https://exemple.test/q.jpg']);
      expect(d['chantierId'], '_general');
      expect(d['ajoutePar'], 'plusA');
      expect(d['ajouteParNom'], 'Plus A');
      expect(d['complete'], false);
      expect(d['dateAjout'], isA<FieldValue>());
    });

    test('nouvelle entrée Général sans auteur : refusée (les règles l\'exigent)', () {
      expect(
        () => donneesNouvelleEntree(companyId: 'A', chantierId: idChantierGeneral, texte: 'x'),
        throwsArgumentError,
      );
    });

    test('nouvelle entrée d\'un vrai chantier : exactement comme avant, sans auteur', () {
      final d = donneesNouvelleEntree(
        companyId: 'A',
        chantierId: 'chA',
        texte: 'Clous',
        quantite: '',
        auteur: contremaitre, // ignoré : ce n'est pas Général
      );
      expect(d.keys.toSet(), {'companyId', 'chantierId', 'texte', 'complete', 'dateAjout'});
    });

    test('quantité vide ou absente : pas de champ', () {
      expect(
        donneesNouvelleEntree(companyId: 'A', chantierId: 'chA', texte: 'x', quantite: '').containsKey('quantite'),
        isFalse,
      );
      expect(
        donneesNouvelleEntree(companyId: 'A', chantierId: 'chA', texte: 'x').containsKey('quantite'),
        isFalse,
      );
    });

    test('obtenu / manquant : Général signe (dateModif, modifiePar)', () {
      final obtenu = donneesCompletion(complete: true, general: true, modifieParId: 'adminA');
      expect(obtenu.keys.toSet(), {'complete', 'dateComplete', 'dateModif', 'modifiePar'});
      expect(obtenu['complete'], true);
      expect(obtenu['dateComplete'], isA<FieldValue>());
      expect(obtenu['modifiePar'], 'adminA');
      final manquant = donneesCompletion(complete: false, general: true, modifieParId: 'adminA');
      expect(manquant['complete'], false);
      expect(manquant['dateComplete'], isA<FieldValue>()); // FieldValue.delete()
    });

    test('obtenu / manquant d\'un vrai chantier : sans signature (inchangé)', () {
      final d = donneesCompletion(complete: true, general: false, modifieParId: 'adminA');
      expect(d.keys.toSet(), {'complete', 'dateComplete'});
    });

    test('modification Général : texte, quantité, photos + signature', () {
      final d = donneesModification(
        texte: 'Sangles 2 po',
        quantite: '6',
        photos: ['https://exemple.test/n.jpg', 'https://exemple.test/o.jpg'],
        general: true,
        modifieParId: 'plusA',
      );
      expect(d.keys.toSet(), {'texte', 'quantite', 'photoUrl', 'photoUrls', 'dateModif', 'modifiePar'});
      expect(d['photoUrl'], 'https://exemple.test/n.jpg');
      expect(d['modifiePar'], 'plusA');
    });

    test('modification : photos null = inchangées ; liste vide = toutes retirées', () {
      final inchangees = donneesModification(texte: 'x', general: false);
      expect(inchangees.containsKey('photoUrl'), isFalse);
      expect(inchangees.containsKey('photoUrls'), isFalse);
      final retirees = donneesModification(texte: 'x', photos: const [], general: false);
      expect(retirees['photoUrl'], isA<FieldValue>()); // FieldValue.delete()
      expect(retirees['photoUrls'], isA<FieldValue>());
    });

    test('modification d\'un chantier : sans signature ; sans quantité pour les travaux', () {
      final d = donneesModification(texte: 'Coffrage', general: false, modifieParId: 'plusA');
      expect(d.keys.toSet(), {'texte'});
      final avecQuantite = donneesModification(texte: 'Clous', quantite: '', general: false);
      expect(avecQuantite.keys.toSet(), {'texte', 'quantite'});
    });
  });

  group('« non lu » posé à la main', () {
    test('une demande marquée « non lu » compte, même déjà vue ou à moi', () {
      final vue = _e('a', ajout: _t(1));
      expect(estNonVu(vue, moiId: 'adminA', vuLe: _t(9)), isFalse);
      expect(estNonVu(vue, moiId: 'adminA', vuLe: _t(9), marqueNonLu: true), isTrue);
      final miennne = _e('b', auteur: 'adminA');
      expect(estNonVu(miennne, moiId: 'adminA', marqueNonLu: true), isTrue);
    });

    test('même sans date de changement (écriture en cours)', () {
      const sansDate = EntreeMateriel(id: 'z', texte: 'x', auteurId: 'plusA');
      expect(estNonVu(sansDate, moiId: 'adminA', marqueNonLu: true), isTrue);
    });

    test('dans les groupes : la pastille compte les drapeaux en plus des nouveautés', () {
      final entrees = [
        _e('a1', auteur: 'plusA', nom: 'Plus A', ajout: _t(1)),
        _e('a2', auteur: 'plusA', nom: 'Plus A', ajout: _t(2)),
        _e('a3', auteur: 'plusA', nom: 'Plus A', ajout: _t(3)),
        _e('c1', auteur: 'adminA', nom: 'Admin A', ajout: _t(1)),
      ];
      final vus = {'plusA': _t(10)};
      // Tout est vu : rien.
      expect(totalNonVus(grouperParAuteur(entrees, moiId: 'adminA', vus: vus)), 0);
      // Deux demandes de plusA et une des miennes marquées « non lu ».
      final g = grouperParAuteur(entrees, moiId: 'adminA', vus: vus, nonLus: {'a1', 'a3', 'c1', 'fantome'});
      expect({for (final x in g) x.auteurId: x.nonVus}, {'adminA': 1, 'plusA': 2});
      expect(totalNonVus(g), 3);
    });

    test('lecture des drapeaux : seulement « true », le reste est ignoré', () {
      expect(nonLusDepuisDonnees({'nonLus': {'a': true, 'b': false, 'c': 'oui', 'd': true}}), {'a', 'd'});
      expect(nonLusDepuisDonnees({'nonLus': 'oui'}), isEmpty);
      expect(nonLusDepuisDonnees({}), isEmpty);
      expect(nonLusDepuisDonnees(null), isEmpty);
    });

    test('document de visites : dates et drapeaux ensemble', () {
      final v = visitesDepuisDonnees({
        'vus': {'plusA': Timestamp.fromDate(_t(5))},
        'nonLus': {'a1': true},
      });
      expect(v.vus, {'plusA': _t(5).toLocal()});
      expect(v.nonLus, {'a1'});
      final vide = visitesDepuisDonnees(null);
      expect(vide.vus, isEmpty);
      expect(vide.nonLus, isEmpty);
    });
  });

  group('requête de la liste Général', () {
    test('un contremaître impose son identifiant, un admin aucune restriction', () {
      expect(auteurImposeALaRequete(estAdmin: false, moiId: 'plusA'), 'plusA');
      expect(auteurImposeALaRequete(estAdmin: true, moiId: 'adminA'), isNull);
    });
  });

  group('tri des demandes (liste Général d\'un contremaître)', () {
    MapEntry<String, Map<String, dynamic>> m(String id, DateTime? d) =>
        MapEntry(id, {'texte': id, if (d != null) 'dateAjout': Timestamp.fromDate(d)});

    test('récent d\'abord ; écriture en cours (sans heure) tout en haut', () {
      final tri = ordonnerParRecence([m('vieux', _t(1)), m('recent', _t(5)), m('enCours', null), m('milieu', _t(3))]);
      expect(tri.map((e) => e.key), ['enCours', 'recent', 'milieu', 'vieux']);
    });

    test('la liste d\'origine n\'est pas modifiée ; liste vide ou d\'un seul élément', () {
      final origine = [m('a', _t(1)), m('b', _t(2))];
      ordonnerParRecence(origine);
      expect(origine.map((e) => e.key), ['a', 'b']);
      expect(ordonnerParRecence(const []), isEmpty);
      expect(ordonnerParRecence([m('seul', _t(1))]).single.key, 'seul');
    });
  });

  group('Liste d\'achats : transfert depuis Général', () {
    final admin = _emp('adminA', 'Admin A', EmployeeRole.admin);

    test('l\'article garde le texte, la quantité, la photo et les deux personnes', () {
      final d = donneesTransfert(
        _e('x', auteur: 'plusA', nom: 'Plus A', texte: 'Sangles', quantite: '4', photos: ['https://exemple.test/p.jpg', 'https://exemple.test/q.jpg']),
        admin,
      );
      expect(d['photoUrls'], ['https://exemple.test/p.jpg', 'https://exemple.test/q.jpg']);
      expect(d.keys.toSet(), {
        'companyId', 'texte', 'quantite', 'photoUrl', 'photoUrls', 'demandeParId', 'demandeParNom',
        'transfereParId', 'transfereParNom', 'origine', 'origineId', 'complete', 'dateAjout',
      });
      expect(d['origineId'], 'x'); // le lien vers la demande d'origine
      expect(d['companyId'], 'A');
      expect(d['texte'], 'Sangles');
      expect(d['quantite'], '4');
      expect(d['photoUrl'], 'https://exemple.test/p.jpg');
      expect(d['demandeParId'], 'plusA');
      expect(d['demandeParNom'], 'Plus A');
      expect(d['transfereParId'], 'adminA');
      expect(d['transfereParNom'], 'Admin A');
      expect(d['origine'], 'general');
      expect(d['complete'], false);
      expect(d['dateAjout'], isA<FieldValue>());
    });

    test('sans quantité ni photo : ces champs sont absents (les règles les veulent valides)', () {
      final d = donneesTransfert(_e('x'), admin);
      expect(d.containsKey('quantite'), isFalse);
      expect(d.containsKey('photoUrl'), isFalse);
      expect(d.containsKey('photoUrls'), isFalse);
    });

    ArticleAchat a(
      String id, {
      String par = 'plusA',
      String nom = 'Plus A',
      bool complete = false,
      DateTime? ajout,
      DateTime? achete,
    }) => ArticleAchat(
      id: id,
      texte: 'Article $id',
      demandeParId: par,
      demandeParNom: nom,
      complete: complete,
      dateAjout: ajout ?? _t(1),
      dateComplete: achete,
    );

    test('lecture d\'un article', () {
      final x = ArticleAchat.fromMap('id1', {
        'texte': 'Cordes', 'quantite': 3, 'photoUrl': 'https://exemple.test/c.jpg',
        'demandeParId': 'plusB', 'demandeParNom': 'Bernard', 'transfereParNom': 'Admin A',
        'complete': true, 'dateAjout': Timestamp.fromDate(_t(2)), 'dateComplete': Timestamp.fromDate(_t(4)),
      });
      expect(x.texte, 'Cordes');
      expect(x.quantite, '3');
      expect(x.demandeParNom, 'Bernard');
      expect(x.transfereParNom, 'Admin A');
      expect(x.complete, isTrue);
      expect(x.dateComplete, _t(4).toLocal());
      final vide = ArticleAchat.fromMap('id2', {});
      expect(vide.texte, '');
      expect(vide.complete, isFalse);
      expect(nomDemandeur(vide), nomDemandeurInconnu);
    });

    test('à acheter : un groupe par demandeur (alphabétique), récent d\'abord ; achetés à part', () {
      final liste = [
        a('1', par: 'plusB', nom: 'Bernard', ajout: _t(2)),
        a('2', par: 'plusA', nom: 'Plus A', ajout: _t(1)),
        a('3', par: 'plusA', nom: 'Plus A', ajout: _t(5)),
        a('4', par: 'plusA', nom: 'Plus A', complete: true, achete: _t(8)),
        a('5', par: 'plusB', nom: 'Bernard', complete: true, achete: _t(9)),
      ];
      final g = grouperParDemandeur(liste);
      expect(g.map((x) => x.nom), ['Bernard', 'Plus A']);
      expect(g[1].articles.map((x) => x.id), ['3', '2']); // récent d'abord
      expect(g.expand((x) => x.articles).any((x) => x.complete), isFalse);
      expect(articlesAchetes(liste).map((x) => x.id), ['5', '4']); // dernier acheté d'abord
    });

    test('aucun article : aucun groupe', () {
      expect(grouperParDemandeur(const []), isEmpty);
      expect(articlesAchetes(const []), isEmpty);
    });
  });


  group('photos d\'une demande', () {
    test('photosDe : toutes les photos, sinon la seule photoUrl, sinon rien', () {
      expect(photosDe({'photoUrls': ['a', 'b', 'c'], 'photoUrl': 'a'}), ['a', 'b', 'c']);
      expect(photosDe({'photoUrl': 'seule'}), ['seule']);
      expect(photosDe({}), isEmpty);
      expect(photosDe({'photoUrls': [], 'photoUrl': 'seule'}), ['seule']);
      expect(photosDe({'photoUrls': 'pas une liste', 'photoUrl': ''}), isEmpty);
      expect(photosDe({'photoUrls': ['a', 7, '', 'b']}), ['a', 'b']);
    });

    test('lecture d\'une demande : les photos viennent de photoUrls, ou de l\'ancienne photoUrl', () {
      final nouvelle = EntreeMateriel.fromMap('n', {'texte': 'x', 'photoUrl': 'a', 'photoUrls': ['a', 'b']});
      expect(nouvelle.photos, ['a', 'b']);
      expect(nouvelle.photoUrl, 'a');
      final ancienne = EntreeMateriel.fromMap('o', {'texte': 'x', 'photoUrl': 'seule'});
      expect(ancienne.photos, ['seule']);
      final sans = EntreeMateriel.fromMap('s', {'texte': 'x'});
      expect(sans.photos, isEmpty);
      expect(sans.photoUrl, isNull);
    });

    test('champsPhotos : la première + toutes, 6 au plus ; rien si vide', () {
      final d = champsPhotos(['a', 'b']);
      expect(d, {'photoUrl': 'a', 'photoUrls': ['a', 'b']});
      expect(champsPhotos(const []), isEmpty);
      final beaucoup = champsPhotos([for (var i = 0; i < 9; i++) 'p$i']);
      expect((beaucoup['photoUrls'] as List).length, maxPhotosParEntree);
      expect(maxPhotosParEntree, 6);
    });
  });

  group('demande transférée à la Liste d\'achats', () {
    final admin = _emp('adminA', 'Admin A', EmployeeRole.admin);

    test('lecture : marquée transférée, avec le nom de l\'admin', () {
      final e = EntreeMateriel.fromMap('t', {'texte': 'x', 'transfere': true, 'transfereParNom': 'Admin A'});
      expect(e.transfere, isTrue);
      expect(e.transfereParNom, 'Admin A');
      expect(EntreeMateriel.fromMap('u', {'texte': 'x'}).transfere, isFalse);
    });

    test('groupe : à acheter, dans la Liste d\'achats et obtenues se comptent séparément', () {
      final g = grouperParAuteur([
        _e('a', ajout: _t(5)),
        _e('b', ajout: _t(4), transfere: true, transfereParNom: 'Admin A'),
        _e('c', ajout: _t(3), complete: true, transfere: true),
        _e('d', ajout: _t(2), complete: true),
        _e('e', ajout: _t(1)),
      ], moiId: 'adminA').single;
      expect(g.aAcheter, 2); // a, e
      expect(g.enAchat, 1); // b
      expect(g.obtenues, 2); // c, d (même transférée, une demande faite est obtenue)
      // À acheter d'abord, puis celles dans la Liste d'achats, puis les obtenues.
      expect(g.entrees.map((x) => x.id), ['a', 'e', 'b', 'c', 'd']);
    });

    test('marquer le transfert : nom de l\'admin + signature', () {
      final d = donneesMarquerTransfert(admin);
      expect(d.keys.toSet(), {'transfere', 'transfereParNom', 'dateModif', 'modifiePar'});
      expect(d['transfere'], true);
      expect(d['transfereParNom'], 'Admin A');
      expect(d['modifiePar'], 'adminA');
    });

    test('retirer le transfert : les deux champs ensemble, signés', () {
      final d = donneesRetirerTransfert('adminA');
      expect(d.keys.toSet(), {'transfere', 'transfereParNom', 'dateModif', 'modifiePar'});
      expect(d['transfere'], isA<FieldValue>());
      expect(d['transfereParNom'], isA<FieldValue>());
    });

    test('copieAvec : change seulement ce qu\'on demande', () {
      final e = _e('x', texte: 'Sangles', quantite: '4', photos: ['a'], auteur: 'plusA', nom: 'Plus A');
      final c = e.copieAvec(transfere: true, transfereParNom: 'Admin A', complete: true);
      expect(c.transfere, isTrue);
      expect(c.complete, isTrue);
      expect(c.texte, 'Sangles');
      expect(c.quantite, '4');
      expect(c.photos, ['a']);
      expect(c.auteurId, 'plusA');
      expect(e.transfere, isFalse); // l'original n'a pas bougé
    });

    test('article de la Liste d\'achats : photos et lien vers la demande', () {
      final a = ArticleAchat.fromMap('z', {
        'texte': 'Sangles', 'photoUrl': 'a', 'photoUrls': ['a', 'b'], 'origineId': 'dem1',
      });
      expect(a.photos, ['a', 'b']);
      expect(a.photoUrl, 'a');
      expect(a.origineId, 'dem1');
      expect(ArticleAchat.fromMap('y', {'texte': 'x'}).origineId, '');
    });
  });

}
