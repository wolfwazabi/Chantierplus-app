// Extras : plusieurs photos (6 au plus) avec leurs chemins dans le Storage ; ajout,
// modification (photos retirées supprimées du Storage, nouvelles nettoyées en cas
// d'échec), suppression. Firestore et le Storage sont remplacés par des doubles.
import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:construction_app/models/employee.dart';
import 'package:construction_app/models/extra_chantier.dart';
import 'package:construction_app/screens/extras/extras_tab.dart';
import 'package:construction_app/services/app_session.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';

final Uint8List _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
);
XFile _photo(String nom) =>
    XFile.fromData(_png, name: nom, mimeType: 'image/png');
Finder _cle(String k) => find.byKey(ValueKey(k));
String _lien(String n) =>
    'https://firebasestorage.googleapis.com/v0/b/chantierplus-mtl/o/$n.jpg';
String _chemin(String n) => 'chantiers/A/c1/chantier_extras/$n.jpg';

Employee _emp(String id, String nom, EmployeeRole role) =>
    Employee(id: id, companyId: 'A', companyNom: 'Alpha', nom: nom, role: role);

ExtraChantier _extra(String id, {List<String> noms = const []}) =>
    ExtraChantier(
      id: id,
      companyId: 'A',
      chantierId: 'c1',
      description: 'Cloison $id',
      mainOeuvre: '3 gars — 4 h',
      dateTravaux: '2026-10-01',
      photos: [for (final n in noms) _lien(n)],
      chemins: [for (final n in noms) _chemin(n)],
      ajouteParNom: 'Plus A',
    );

void main() {
  tearDown(() => AppSession.notifier.value = null);

  final ajouts = <Map<String, dynamic>>[];
  final modifs = <(String, Map<String, dynamic>)>[];
  final supprimes = <String>[]; // fiches supprimées
  final fichiersSupprimes = <String>[]; // chemins supprimés du Storage
  final chemins = <String>[]; // chemins envoyés
  var echecAjout = false;
  var echecModif = false;
  var echecEnvoiApres =
      -1; // envoi qui échoue à partir de cette position (-1 : jamais)
  var galerie = <XFile>[];
  XFile? camera;

  Future<void> ouvrir(
    WidgetTester tester, {
    Employee? moi,
    List<ExtraChantier> extras = const [],
  }) async {
    tester.view.physicalSize = const Size(800, 2200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    ajouts.clear();
    modifs.clear();
    supprimes.clear();
    fichiersSupprimes.clear();
    chemins.clear();
    echecAjout = false;
    echecModif = false;
    echecEnvoiApres = -1;
    galerie = [];
    camera = null;
    AppSession.notifier.value =
        moi ?? _emp('plusA', 'Plus A', EmployeeRole.plus);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ExtrasTab(
            chantierId: 'c1',
            companyId: 'A',
            connecte: true,
            flux: Stream.value(extras),
            ajouterDoc: (d) async {
              if (echecAjout) throw StateError('refusé');
              ajouts.add(d);
            },
            modifierDoc: (id, d) async {
              if (echecModif) throw StateError('refusé');
              modifs.add((id, d));
            },
            supprimerDoc: (id) async => supprimes.add(id),
            televerser: (chemin, octets) async {
              if (echecEnvoiApres >= 0 && chemins.length >= echecEnvoiApres) {
                throw StateError('réseau coupé');
              }
              chemins.add(chemin);
              return _lien('envoyee${chemins.length}');
            },
            supprimerFichier: (chemin) async => fichiersSupprimes.add(chemin),
            prendrePhoto: () async => camera,
            choisirPhotos: (limite) async => galerie,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> remplir(WidgetTester tester, {int formulaire = 0}) async {
    final description = _cle('extra_description').at(formulaire);
    final main = _cle('extra_main_oeuvre').at(formulaire);
    await tester.enterText(description, 'Cloison');
    await tester.enterText(main, '3 gars — 4 h');
    await tester.pump();
  }

  Future<void> galerieChoisir(WidgetTester tester) async {
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

  Future<void> valider(WidgetTester tester) async {
    await tester.tap(_cle('extra_valider').last);
    await tester.pumpAndSettle();
  }

  Future<void> ouvrirEdition(WidgetTester tester, String id) async {
    await tester.tap(_cle('extra_menu_$id'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Modifier'));
    await tester.pumpAndSettle();
  }

  // ===========================================================================
  group('ajouter un extra avec plusieurs photos', () {
    testWidgets('sans photo : aucun champ de photo écrit', (tester) async {
      await ouvrir(tester);
      await remplir(tester);
      await valider(tester);
      final d = ajouts.single;
      for (final cle in [
        'photoUrl',
        'cheminPhoto',
        'photoUrls',
        'cheminsPhotos',
      ]) {
        expect(d.containsKey(cle), isFalse, reason: cle);
      }
      expect(find.text('Extra ajouté.'), findsOneWidget);
    });

    testWidgets(
      '3 photos : liens et chemins alignés, la première aussi à part',
      (tester) async {
        await ouvrir(tester);
        await remplir(tester);
        galerie = [_photo('a.jpg'), _photo('b.jpg'), _photo('c.jpg')];
        await galerieChoisir(tester);
        expect(find.text('Ajouter des photos (3/6)'), findsOneWidget);
        await valider(tester);
        final d = ajouts.single;
        expect(chemins.length, 3);
        for (final c in chemins) {
          expect(c, startsWith('chantiers/A/c1/chantier_extras/'));
        }
        expect(d['photoUrls'], [
          _lien('envoyee1'),
          _lien('envoyee2'),
          _lien('envoyee3'),
        ]);
        expect(d['cheminsPhotos'], chemins);
        expect(d['photoUrl'], _lien('envoyee1'));
        expect(d['cheminPhoto'], chemins.first);
        expect(d['ajoutePar'], 'plusA');
        // Le formulaire est vidé, aperçus compris.
        expect(find.text('Ajouter des photos'), findsOneWidget);
      },
    );

    testWidgets('appareil photo + galerie, 6 au plus', (tester) async {
      await ouvrir(tester);
      await remplir(tester);
      camera = _photo('prise.jpg');
      await prendre(tester);
      galerie = [for (var i = 0; i < 8; i++) _photo('g$i.jpg')];
      await galerieChoisir(tester);
      expect(find.text('Maximum atteint (6/6)'), findsOneWidget);
      expect(find.textContaining('ignorées'), findsOneWidget);
      await valider(tester);
      expect((ajouts.single['photoUrls'] as List).length, 6);
    });

    testWidgets(
      'l\'envoi d\'une photo échoue : celles déjà envoyées sont retirées du Storage',
      (tester) async {
        await ouvrir(tester);
        await remplir(tester);
        galerie = [_photo('a.jpg'), _photo('b.jpg'), _photo('c.jpg')];
        await galerieChoisir(tester);
        echecEnvoiApres = 2; // la 3e échoue
        await valider(tester);
        expect(ajouts, isEmpty);
        expect(
          fichiersSupprimes.toSet(),
          chemins.toSet(),
        ); // les 2 envoyées, nettoyées
        expect(fichiersSupprimes.length, 2);
        expect(
          find.text('Impossible d\'ajouter l\'extra. Réessayez.'),
          findsOneWidget,
        );
        // La saisie reste.
        expect(
          tester
              .widget<TextField>(_cle('extra_description').first)
              .controller!
              .text,
          'Cloison',
        );
      },
    );

    testWidgets(
      'la fiche ne peut pas être créée : les photos envoyées sont retirées du Storage',
      (tester) async {
        await ouvrir(tester);
        await remplir(tester);
        galerie = [_photo('a.jpg'), _photo('b.jpg')];
        await galerieChoisir(tester);
        echecAjout = true;
        await valider(tester);
        expect(fichiersSupprimes.toSet(), chemins.toSet());
        expect(chemins.length, 2);
      },
    );
  });

  // ===========================================================================
  group('modifier les photos d\'un extra', () {
    testWidgets(
      'retirer la première, en ajouter une : liste, chemins et fichier retiré suivent',
      (tester) async {
        await ouvrir(
          tester,
          extras: [
            _extra('x1', noms: ['a', 'b', 'c']),
          ],
        );
        await ouvrirEdition(tester, 'x1');
        await tester.tap(_cle('photo_retirer_existante_0'));
        await tester.pumpAndSettle();
        camera = _photo('neuve.jpg');
        await prendre(tester);
        await valider(tester);
        final (id, maj) = modifs.single;
        expect(id, 'x1');
        expect(maj['photoUrl'], _lien('b'));
        expect(maj['cheminPhoto'], _chemin('b'));
        expect(maj['photoUrls'], [_lien('b'), _lien('c'), _lien('envoyee1')]);
        expect(maj['cheminsPhotos'], [
          _chemin('b'),
          _chemin('c'),
          chemins.single,
        ]);
        // Seule la photo retirée disparaît du Storage, après la mise à jour.
        expect(fichiersSupprimes, [_chemin('a')]);
        expect(find.text('Extra modifié.'), findsOneWidget);
      },
    );

    testWidgets(
      'sans changer les photos : elles ne sont ni réécrites ni supprimées',
      (tester) async {
        await ouvrir(
          tester,
          extras: [
            _extra('x1', noms: ['a', 'b']),
          ],
        );
        await ouvrirEdition(tester, 'x1');
        await tester.enterText(_cle('extra_main_oeuvre').last, '4 gars — 5 h');
        await valider(tester);
        final maj = modifs.single.$2;
        expect(maj['mainOeuvre'], '4 gars — 5 h');
        for (final cle in [
          'photoUrl',
          'cheminPhoto',
          'photoUrls',
          'cheminsPhotos',
        ]) {
          expect(maj.containsKey(cle), isFalse, reason: cle);
        }
        expect(fichiersSupprimes, isEmpty);
        expect(chemins, isEmpty);
      },
    );

    testWidgets(
      'tout retirer : les quatre champs supprimés, tous les fichiers retirés du Storage',
      (tester) async {
        await ouvrir(
          tester,
          extras: [
            _extra('x1', noms: ['a', 'b']),
          ],
        );
        await ouvrirEdition(tester, 'x1');
        await tester.tap(_cle('photo_retirer_existante_1'));
        await tester.pumpAndSettle();
        await tester.tap(_cle('photo_retirer_existante_0'));
        await tester.pumpAndSettle();
        await valider(tester);
        final maj = modifs.single.$2;
        for (final cle in [
          'photoUrl',
          'cheminPhoto',
          'photoUrls',
          'cheminsPhotos',
        ]) {
          expect(maj[cle], isA<FieldValue>(), reason: cle);
        }
        expect(fichiersSupprimes.toSet(), {_chemin('a'), _chemin('b')});
      },
    );

    testWidgets(
      'échec de la mise à jour : les nouvelles photos sont nettoyées, les anciennes gardées',
      (tester) async {
        await ouvrir(
          tester,
          extras: [
            _extra('x1', noms: ['a']),
          ],
        );
        await ouvrirEdition(tester, 'x1');
        camera = _photo('neuve.jpg');
        await prendre(tester);
        echecModif = true;
        await valider(tester);
        expect(
          find.text('Impossible de modifier l\'extra. Réessayez.'),
          findsOneWidget,
        );
        expect(fichiersSupprimes, chemins); // seulement la nouvelle
        expect(fichiersSupprimes, isNot(contains(_chemin('a'))));
      },
    );

    testWidgets(
      'un ancien extra (photoUrl + cheminPhoto) se modifie comme les autres',
      (tester) async {
        final ancien = ExtraChantier.fromFirestore('old', {
          'companyId': 'A',
          'chantierId': 'c1',
          'description': 'Ancien',
          'mainOeuvre': '2 gars',
          'dateTravaux': '2026-09-01',
          'photoUrl': _lien('vieille'),
          'cheminPhoto': _chemin('vieille'),
        });
        await ouvrir(tester, extras: [ancien]);
        await ouvrirEdition(tester, 'old');
        camera = _photo('neuve.jpg');
        await prendre(tester);
        await valider(tester);
        final maj = modifs.single.$2;
        expect(maj['photoUrls'], [_lien('vieille'), _lien('envoyee1')]);
        expect(maj['cheminsPhotos'], [_chemin('vieille'), chemins.single]);
        expect(fichiersSupprimes, isEmpty); // la vieille photo est gardée
      },
    );
  });

  // ===========================================================================
  group('afficher et supprimer', () {
    testWidgets('une vignette avec le nombre de photos', (tester) async {
      await ouvrir(
        tester,
        extras: [
          _extra('x1', noms: ['a', 'b', 'c']),
          _extra('x2', noms: ['d']),
          _extra('x3'),
        ],
      );
      expect(
        find.descendant(
          of: _cle('extra_x1'),
          matching: _cle('vignette_nombre'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: _cle('extra_x2'),
          matching: _cle('vignette_photos'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: _cle('extra_x2'),
          matching: _cle('vignette_nombre'),
        ),
        findsNothing,
      );
      expect(
        find.descendant(
          of: _cle('extra_x3'),
          matching: _cle('vignette_photos'),
        ),
        findsNothing,
      );
    });

    testWidgets('admin : supprimer retire la fiche puis tous les fichiers', (
      tester,
    ) async {
      await ouvrir(
        tester,
        moi: _emp('adminA', 'Admin A', EmployeeRole.admin),
        extras: [
          _extra('x1', noms: ['a', 'b']),
        ],
      );
      await tester.tap(_cle('extra_menu_x1'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Supprimer'));
      await tester.pumpAndSettle();
      await tester.tap(_cle('extra_confirmer_suppression'));
      await tester.pumpAndSettle();
      expect(supprimes, ['x1']);
      expect(fichiersSupprimes.toSet(), {_chemin('a'), _chemin('b')});
      expect(find.text('Extra supprimé.'), findsOneWidget);
    });

    testWidgets('contremaître : pas de « Supprimer » (seulement un admin)', (
      tester,
    ) async {
      await ouvrir(
        tester,
        extras: [
          _extra('x1', noms: ['a']),
        ],
      );
      await tester.tap(_cle('extra_menu_x1'));
      await tester.pumpAndSettle();
      expect(find.text('Modifier'), findsOneWidget);
      expect(find.text('Supprimer'), findsNothing);
    });
  });
}
