// Matériel « Général » (remorque, sans chantier) : auteurs, groupes par personne,
// changements non vus, et les données écrites (les règles Firestore exigent ces champs).
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:construction_app/models/chantier.dart';
import 'package:construction_app/models/employee.dart';
import 'package:construction_app/models/materiel_general.dart';
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
}) => EntreeMateriel(
  id: id,
  texte: texte,
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
        photoUrl: 'https://exemple.test/p.jpg',
        auteur: contremaitre,
      );
      expect(d.keys.toSet(), {
        'companyId', 'chantierId', 'texte', 'complete', 'dateAjout', 'photoUrl', 'quantite',
        'ajoutePar', 'ajouteParNom',
      });
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

    test('modification Général : texte, quantité, photo + signature', () {
      final d = donneesModification(
        texte: 'Sangles 2 po',
        quantite: '6',
        photoUrl: 'https://exemple.test/n.jpg',
        general: true,
        modifieParId: 'plusA',
      );
      expect(d.keys.toSet(), {'texte', 'quantite', 'photoUrl', 'dateModif', 'modifiePar'});
      expect(d['modifiePar'], 'plusA');
    });

    test('modification d\'un chantier : sans signature ; sans quantité pour les travaux', () {
      final d = donneesModification(texte: 'Coffrage', general: false, modifieParId: 'plusA');
      expect(d.keys.toSet(), {'texte'});
      final avecQuantite = donneesModification(texte: 'Clous', quantite: '', general: false);
      expect(avecQuantite.keys.toSet(), {'texte', 'quantite'});
    });
  });
}
