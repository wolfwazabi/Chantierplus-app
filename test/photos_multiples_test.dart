// Plusieurs photos par demande de matériel ou de travaux (jusqu'à 6) : choix,
// retrait, envoi, modification, visionneuse ; et les demandes transférées à la Liste
// d'achats vues par leur auteur. Firestore et le Storage sont remplacés par des doubles.
import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:construction_app/models/chantier.dart';
import 'package:construction_app/models/employee.dart';
import 'package:construction_app/screens/chantier_screen.dart';
import 'package:construction_app/services/app_session.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';

// Une image PNG de 1 × 1 pixel (valide : les aperçus peuvent la décoder).
final Uint8List _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
);

XFile _photo(String nom) => XFile.fromData(_png, name: nom, mimeType: 'image/png');
Finder _cle(String k) => find.byKey(ValueKey(k));
String _lien(int n) => 'https://firebasestorage.googleapis.com/v0/b/x/o/photo$n.jpg';

Employee _emp(String id, String nom, EmployeeRole role) =>
    Employee(id: id, companyId: 'A', companyNom: 'Alpha', nom: nom, role: role);

const _chantiers = [
  Chantier(id: 'c1', companyId: 'A', nom: 'Atelier', adresse: '1 rue des Pins'),
];

void main() {
  tearDown(() => AppSession.notifier.value = null);

  // État partagé par le décor de chaque test.
  final ajouts = <(String, Map<String, dynamic>)>[];
  final modifs = <(String, String, Map<String, dynamic>)>[];
  final chemins = <String>[];
  final limites = <int>[];
  var echecEnvoi = 0; // nombre d'envois à refuser avant de réussir
  var galerie = <XFile>[];
  XFile? camera;

  Future<void> ouvrir(
    WidgetTester tester, {
    Employee? moi,
    List<MapEntry<String, Map<String, dynamic>>> flux = const [],
    bool general = false,
  }) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    ajouts.clear();
    modifs.clear();
    chemins.clear();
    limites.clear();
    echecEnvoi = 0;
    galerie = [];
    camera = null;
    AppSession.notifier.value = moi ?? _emp('plusA', 'Plus A', EmployeeRole.plus);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChantierScreen(
            fluxChantiers: Stream.value(_chantiers),
            fluxMateriel: Stream.value(flux),
            contenuOnglet: (nom, id) => nom == 'materiel' ? null : Text('ONGLET $nom'),
            ajouterEntree: (collection, data) async => ajouts.add((collection, data)),
            modifierEntree: (collection, id, data) async => modifs.add((collection, id, data)),
            televerserPhoto: (chemin, octets) async {
              if (echecEnvoi > 0) {
                echecEnvoi--;
                throw StateError('réseau coupé');
              }
              chemins.add(chemin);
              return _lien(chemins.length);
            },
            prendrePhoto: () async => camera,
            choisirPhotos: (limite) async {
              limites.add(limite);
              return galerie;
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    if (general) {
      await tester.tap(find.byType(DropdownButtonFormField<Chantier>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Général').last);
      await tester.pumpAndSettle();
    } else {
      await tester.tap(find.widgetWithText(Tab, 'Matériel'));
      await tester.pumpAndSettle();
    }
  }

  Future<void> choisirGalerie(WidgetTester tester) async {
    await tester.tap(_cle('photos_ajouter').last);
    await tester.pumpAndSettle();
    await tester.tap(_cle('photos_galerie'));
    await tester.pumpAndSettle();
  }

  Future<void> prendre(WidgetTester tester) async {
    await tester.tap(_cle('photos_ajouter').last);
    await tester.pumpAndSettle();
    await tester.tap(_cle('photos_prendre'));
    await tester.pumpAndSettle();
  }

  Future<void> ajouter(WidgetTester tester, String texte) async {
    await tester.enterText(find.byType(TextField).first, texte);
    await tester.tap(find.text('Ajouter'));
    await tester.pumpAndSettle();
  }

  // ===========================================================================
  group('ajouter une demande avec plusieurs photos', () {
    testWidgets('sans photo : « Ajouter des photos », et la demande part sans champ de photo', (tester) async {
      await ouvrir(tester);
      expect(find.text('Ajouter des photos'), findsOneWidget);
      await ajouter(tester, 'Clous 3 po');
      final data = ajouts.single.$2;
      expect(data.containsKey('photoUrl'), isFalse);
      expect(data.containsKey('photoUrls'), isFalse);
    });

    testWidgets('plusieurs photos de la galerie d\'un coup : un aperçu chacune', (tester) async {
      await ouvrir(tester);
      galerie = [_photo('a.jpg'), _photo('b.jpg'), _photo('c.jpg')];
      await choisirGalerie(tester);
      for (var i = 0; i < 3; i++) {
        expect(_cle('photo_retirer_nouvelle_$i'), findsOneWidget, reason: 'aperçu $i');
      }
      expect(find.text('Ajouter des photos (3/6)'), findsOneWidget);
      // La galerie a été ouverte avec le maximum permis.
      expect(limites, [6]);
    });

    testWidgets('retirer une photo avant l\'envoi', (tester) async {
      await ouvrir(tester);
      galerie = [_photo('a.jpg'), _photo('b.jpg'), _photo('c.jpg')];
      await choisirGalerie(tester);
      await tester.tap(_cle('photo_retirer_nouvelle_1'));
      await tester.pumpAndSettle();
      expect(_cle('photo_retirer_nouvelle_2'), findsNothing);
      expect(_cle('photo_retirer_nouvelle_1'), findsOneWidget);
      expect(find.text('Ajouter des photos (2/6)'), findsOneWidget);
    });

    testWidgets('envoi : toutes les photos, dans l\'ordre ; la première est photoUrl ; tout est vidé ensuite', (tester) async {
      await ouvrir(tester);
      galerie = [_photo('a.jpg'), _photo('b.jpg'), _photo('c.jpg')];
      await choisirGalerie(tester);
      await tester.tap(_cle('photo_retirer_nouvelle_1')); // on garde a et c
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).at(1), '2');
      await ajouter(tester, 'Clous 3 po');
      expect(chemins.length, 2);
      for (final c in chemins) {
        expect(c, startsWith('chantiers/A/c1/chantier_materiel/'));
      }
      expect(chemins[0], contains('_0_'));
      expect(chemins[1], contains('_1_'));
      expect(chemins[0], isNot(equals(chemins[1])));
      final (collection, data) = ajouts.single;
      expect(collection, 'chantier_materiel');
      expect(data['photoUrl'], _lien(1));
      expect(data['photoUrls'], [_lien(1), _lien(2)]);
      expect(data['texte'], 'Clous 3 po');
      expect(data['quantite'], '2');
      // Tout est vidé, prêt pour la demande suivante.
      expect(_cle('photo_retirer_nouvelle_0'), findsNothing);
      expect(find.text('Ajouter des photos'), findsOneWidget);
      expect(tester.widget<TextField>(find.byType(TextField).first).controller!.text, '');
    });

    testWidgets('l\'appareil photo et la galerie se combinent', (tester) async {
      await ouvrir(tester);
      camera = _photo('prise.jpg');
      await prendre(tester);
      galerie = [_photo('a.jpg'), _photo('b.jpg')];
      await choisirGalerie(tester);
      expect(find.text('Ajouter des photos (3/6)'), findsOneWidget);
      // La galerie reçoit le nombre de places restantes.
      expect(limites, [5]);
      await ajouter(tester, 'Niveau');
      expect((ajouts.single.$2['photoUrls'] as List).length, 3);
    });

    testWidgets('annuler l\'appareil photo ou la galerie : rien ne change', (tester) async {
      await ouvrir(tester);
      camera = null;
      await prendre(tester);
      galerie = [];
      await choisirGalerie(tester);
      expect(find.text('Ajouter des photos'), findsOneWidget);
    });

    testWidgets('maximum de 6 : les photos en trop sont ignorées, avec un message', (tester) async {
      await ouvrir(tester);
      galerie = [for (var i = 0; i < 9; i++) _photo('p$i.jpg')];
      await choisirGalerie(tester);
      expect(find.text('Maximum de 6 photos : 3 photos ignorées.'), findsOneWidget);
      expect(find.text('Maximum atteint (6/6)'), findsOneWidget);
      // Le bouton est désactivé tant qu'on n'en retire pas une.
      expect(tester.widget<OutlinedButton>(_cle('photos_ajouter')).onPressed, isNull);
      await tester.tap(_cle('photo_retirer_nouvelle_5'));
      await tester.pumpAndSettle();
      expect(tester.widget<OutlinedButton>(_cle('photos_ajouter')).onPressed, isNotNull);
      expect(find.text('Ajouter des photos (5/6)'), findsOneWidget);
    });

    testWidgets('échec de l\'envoi : message, tout reste à l\'écran, on réessaie sans rechoisir', (tester) async {
      await ouvrir(tester);
      galerie = [_photo('a.jpg'), _photo('b.jpg')];
      await choisirGalerie(tester);
      echecEnvoi = 1;
      await ajouter(tester, 'Niveau');
      expect(find.textContaining('n\'a pas pu être ajoutée'), findsOneWidget);
      expect(ajouts, isEmpty);
      expect(_cle('photo_retirer_nouvelle_1'), findsOneWidget); // photos gardées
      expect(tester.widget<TextField>(find.byType(TextField).first).controller!.text, 'Niveau');
      // Deuxième essai : tout part.
      await tester.tap(find.text('Ajouter'));
      await tester.pumpAndSettle();
      expect(ajouts.length, 1);
      expect(ajouts.single.$2['photoUrls'], [_lien(1), _lien(2)]);
    });

    testWidgets('Général : photos multiples ET auteur', (tester) async {
      await ouvrir(tester, general: true);
      galerie = [_photo('a.jpg'), _photo('b.jpg')];
      await choisirGalerie(tester);
      await ajouter(tester, 'Sangles');
      final data = ajouts.single.$2;
      expect(data['chantierId'], '_general');
      expect(data['ajoutePar'], 'plusA');
      expect(data['photoUrls'], [_lien(1), _lien(2)]);
      expect(chemins.first, startsWith('chantiers/A/_general/chantier_materiel/'));
    });
  });

  // ===========================================================================
  group('modifier les photos d\'une demande', () {
    List<MapEntry<String, Map<String, dynamic>>> demande({List<String>? photos, String? photoSeule}) => [
      MapEntry('m1', {
        'texte': 'Sangles', 'quantite': '4', 'complete': false,
        'dateAjout': Timestamp.fromDate(DateTime.utc(2026, 10, 3)),
        if (photos != null) ...{'photoUrl': photos.first, 'photoUrls': photos},
        'photoUrl': ?photoSeule,
      }),
    ];

    Future<void> ouvrirEdition(WidgetTester tester) async {
      await tester.tap(_cle('menu_m1'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Modifier'));
      await tester.pumpAndSettle();
    }

    testWidgets('les photos de la demande s\'affichent, avec leur retrait', (tester) async {
      await ouvrir(tester, flux: demande(photos: [_lien(7), _lien(8)]));
      await ouvrirEdition(tester);
      expect(_cle('photo_retirer_existante_0'), findsOneWidget);
      expect(_cle('photo_retirer_existante_1'), findsOneWidget);
      expect(find.text('Ajouter des photos (2/6)'), findsOneWidget);
    });

    testWidgets('une ancienne demande (photoUrl seule) montre sa photo', (tester) async {
      await ouvrir(tester, flux: demande(photoSeule: _lien(7)));
      await ouvrirEdition(tester);
      expect(_cle('photo_retirer_existante_0'), findsOneWidget);
      expect(_cle('photo_retirer_existante_1'), findsNothing);
    });

    testWidgets('retirer la première et en ajouter une : la liste suit, la première devient photoUrl', (tester) async {
      await ouvrir(tester, flux: demande(photos: [_lien(7), _lien(8)]));
      await ouvrirEdition(tester);
      await tester.tap(_cle('photo_retirer_existante_0'));
      await tester.pumpAndSettle();
      camera = _photo('neuve.jpg');
      await prendre(tester);
      await tester.tap(_cle('modifier_enregistrer'));
      await tester.pumpAndSettle();
      final (collection, id, data) = modifs.single;
      expect(collection, 'chantier_materiel');
      expect(id, 'm1');
      expect(data['photoUrl'], _lien(8));
      expect(data['photoUrls'], [_lien(8), _lien(1)]); // l'ancienne, puis la nouvelle
      expect(_cle('modifier_enregistrer'), findsNothing); // la feuille est fermée
    });

    testWidgets('sans changer les photos : elles ne sont pas réécrites', (tester) async {
      await ouvrir(tester, flux: demande(photos: [_lien(7), _lien(8)]));
      await ouvrirEdition(tester);
      await tester.enterText(find.widgetWithText(TextField, 'Sangles'), 'Sangles 2 po');
      await tester.tap(_cle('modifier_enregistrer'));
      await tester.pumpAndSettle();
      final data = modifs.single.$3;
      expect(data['texte'], 'Sangles 2 po');
      expect(data.containsKey('photoUrl'), isFalse);
      expect(data.containsKey('photoUrls'), isFalse);
      expect(chemins, isEmpty); // rien d'envoyé
    });

    testWidgets('tout retirer : les deux champs sont supprimés', (tester) async {
      await ouvrir(tester, flux: demande(photos: [_lien(7), _lien(8)]));
      await ouvrirEdition(tester);
      await tester.tap(_cle('photo_retirer_existante_1'));
      await tester.pumpAndSettle();
      await tester.tap(_cle('photo_retirer_existante_0'));
      await tester.pumpAndSettle();
      await tester.tap(_cle('modifier_enregistrer'));
      await tester.pumpAndSettle();
      final data = modifs.single.$3;
      expect(data['photoUrl'], isA<FieldValue>());
      expect(data['photoUrls'], isA<FieldValue>());
    });

    testWidgets('échec de l\'envoi : message, la feuille reste ouverte pour réessayer', (tester) async {
      await ouvrir(tester, flux: demande(photos: [_lien(7)]));
      await ouvrirEdition(tester);
      camera = _photo('neuve.jpg');
      await prendre(tester);
      echecEnvoi = 1;
      await tester.tap(_cle('modifier_enregistrer'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Modification impossible'), findsOneWidget);
      expect(modifs, isEmpty);
      expect(_cle('modifier_enregistrer'), findsOneWidget);
      await tester.tap(_cle('modifier_enregistrer'));
      await tester.pumpAndSettle();
      expect(modifs.length, 1);
    });
  });

  // ===========================================================================
  group('voir les photos d\'une demande', () {
    List<MapEntry<String, Map<String, dynamic>>> avec(List<String> photos) => [
      MapEntry('m1', {
        'texte': 'Sangles', 'complete': false,
        'dateAjout': Timestamp.fromDate(DateTime.utc(2026, 10, 3)),
        'photoUrl': photos.first, 'photoUrls': photos,
      }),
    ];

    testWidgets('plusieurs photos : une vignette avec le nombre', (tester) async {
      await ouvrir(tester, flux: avec([_lien(1), _lien(2), _lien(3)]));
      expect(_cle('vignette_photos'), findsOneWidget);
      expect(
        find.descendant(of: _cle('vignette_nombre'), matching: find.text('3')),
        findsOneWidget,
      );
    });

    testWidgets('une seule photo : pas de nombre', (tester) async {
      await ouvrir(tester, flux: avec([_lien(1)]));
      expect(_cle('vignette_photos'), findsOneWidget);
      expect(_cle('vignette_nombre'), findsNothing);
    });

    testWidgets('un toucher ouvre la visionneuse : on passe d\'une photo à l\'autre, puis on ferme', (tester) async {
      await ouvrir(tester, flux: avec([_lien(1), _lien(2), _lien(3)]));
      await tester.tap(_cle('vignette_photos'));
      await tester.pumpAndSettle();
      expect(_cle('galerie_photos'), findsOneWidget);
      expect(find.text('1 / 3'), findsOneWidget);
      await tester.fling(
        find.descendant(of: _cle('galerie_photos'), matching: find.byType(PageView)),
        const Offset(-500, 0),
        1500,
      );
      await tester.pumpAndSettle();
      expect(find.text('2 / 3'), findsOneWidget);
      await tester.tap(_cle('galerie_fermer'));
      await tester.pumpAndSettle();
      expect(_cle('galerie_photos'), findsNothing);
    });

    testWidgets('une demande sans photo : l\'icône habituelle, pas de vignette', (tester) async {
      await ouvrir(
        tester,
        flux: [
          MapEntry('m2', {
            'texte': 'Clous', 'complete': false,
            'dateAjout': Timestamp.fromDate(DateTime.utc(2026, 10, 3)),
          }),
        ],
      );
      expect(_cle('vignette_photos'), findsNothing);
      expect(find.byIcon(Icons.shopping_cart), findsWidgets);
    });
  });

  // ===========================================================================
  group('demande transférée à la Liste d\'achats : visible pour son auteur', () {
    List<MapEntry<String, Map<String, dynamic>>> donnees() => [
      MapEntry('m1', {
        'texte': 'Sangles', 'complete': false, 'ajoutePar': 'plusA', 'ajouteParNom': 'Plus A',
        'transfere': true, 'transfereParNom': 'Admin A',
        'dateAjout': Timestamp.fromDate(DateTime.utc(2026, 10, 3)),
      }),
      MapEntry('m2', {
        'texte': 'Cordes', 'complete': false, 'ajoutePar': 'plusA', 'ajouteParNom': 'Plus A',
        'dateAjout': Timestamp.fromDate(DateTime.utc(2026, 10, 2)),
      }),
      MapEntry('m3', {
        'texte': 'Bâche', 'complete': true, 'ajoutePar': 'plusA', 'ajouteParNom': 'Plus A',
        'transfere': true, 'transfereParNom': 'Admin A',
        'dateAjout': Timestamp.fromDate(DateTime.utc(2026, 10, 1)),
        'dateComplete': Timestamp.fromDate(DateTime.utc(2026, 10, 4)),
      }),
    ];

    testWidgets('le contremaître la voit avec la mention, sans pouvoir la modifier ni la supprimer', (tester) async {
      await ouvrir(tester, flux: donnees(), general: true);
      expect(find.text('Sangles'), findsOneWidget);
      expect(
        find.text('Dans la Liste d\'achats (transféré par Admin A)'),
        findsOneWidget,
      );
      expect(_cle('menu_m1'), findsNothing);
      expect(
        find.descendant(of: _cle('entree_m1'), matching: find.byIcon(Icons.delete_outline)),
        findsNothing,
      );
      // Sa demande ordinaire garde son menu et sa corbeille.
      expect(_cle('menu_m2'), findsOneWidget);
      expect(
        find.descendant(of: _cle('entree_m2'), matching: find.byIcon(Icons.delete_outline)),
        findsOneWidget,
      );
      expect(_cle('transfere_m2'), findsNothing);
    });

    testWidgets('une fois faite (achetée), elle passe dans l\'historique, sans actions', (tester) async {
      await ouvrir(tester, flux: donnees(), general: true);
      await tester.tap(find.text('Voir l\'historique'));
      await tester.pumpAndSettle();
      expect(find.text('Bâche'), findsOneWidget);
      expect(find.textContaining('Réglé le'), findsOneWidget);
      expect(_cle('transfere_m3'), findsNothing); // faite : plus de mention « en cours »
      expect(_cle('menu_m3'), findsNothing);
    });

    testWidgets('un admin garde tous les gestes sur une demande transférée', (tester) async {
      await ouvrir(
        tester,
        moi: _emp('adminA', 'Admin A', EmployeeRole.admin),
        flux: donnees(),
        general: true,
      );
      await tester.tap(_cle('filtre_plusA'));
      await tester.pumpAndSettle();
      expect(_cle('menu_m1'), findsOneWidget);
      expect(
        find.descendant(of: _cle('entree_m1'), matching: find.byIcon(Icons.delete_outline)),
        findsOneWidget,
      );
    });
  });
}
