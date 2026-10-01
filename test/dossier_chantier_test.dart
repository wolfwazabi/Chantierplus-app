import 'package:construction_app/models/chantier.dart';
import 'package:construction_app/models/resume_chantier.dart';
import 'package:construction_app/screens/admin/dossiers_chantiers_screen.dart';
import 'package:construction_app/screens/admin/resume_heures_carte.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _reponse() => {
  'chantier': {
    'id': 'c1',
    'nom': 'Chalet Nord',
    'adresse': '1 rue des Pins',
    'archive': true,
  },
  'heures': {
    'totalHeures': 23.5,
    'totalVoyagementPaye': 0.75,
    'joursTravailles': 2,
    'journeesHomme': 3,
    'premierJour': '2026-10-05',
    'dernierJour': '2026-10-06',
    'parEmploye': [
      {
        'employeeId': 'e1',
        'nom': 'Marie',
        'heures': 15.75,
        'voyagementPaye': 0.75,
        'jours': 2,
      },
      {
        'employeeId': 'e2',
        'nom': 'Paul',
        'heures': 7.75,
        'voyagementPaye': 0,
        'jours': 1,
      },
    ],
  },
  'nombres': {
    'extras': 2,
    'materiel': 3,
    'photos': 40,
    'travaux': 5,
    'documents': 7,
  },
};

void main() {
  group('lecture de la réponse du serveur', () {
    test('résumé complet', () {
      final r = ResumeChantier.fromMap(_reponse());
      expect(r.nom, 'Chalet Nord');
      expect(r.archive, isTrue);
      expect(r.totalHeures, 23.5);
      expect(r.totalVoyagementPaye, 0.75);
      expect(r.joursTravailles, 2);
      expect(r.journeesHomme, 3);
      expect(r.premierJour, '2026-10-05');
      expect(r.parEmploye.map((e) => e.nom), ['Marie', 'Paul']);
      expect(r.parEmploye.first.heures, 15.75);
      expect(r.nbExtras, 2);
      expect(r.nbMateriel, 3);
      expect(r.nbPhotos, 40);
      expect(r.nbTravaux, 5);
      expect(r.nbDocuments, 7);
    });

    test('réponse vide ou abîmée : valeurs sûres, sans planter', () {
      final r = ResumeChantier.fromMap({});
      expect(r.totalHeures, 0);
      expect(r.parEmploye, isEmpty);
      expect(r.premierJour, isNull);
      final r2 = ResumeChantier.fromMap({
        'heures': {'totalHeures': 'beaucoup', 'parEmploye': 'x'},
        'nombres': null,
      });
      expect(r2.totalHeures, 0);
      expect(r2.nbPhotos, 0);
    });

    test('export', () {
      final e = ExportChantier.fromMap({
        'url': 'https://firebasestorage.googleapis.com/v0/b/b/o/x',
        'nom': 'Chantier - Chalet Nord.zip',
        'taille': 12345678,
        'fichiers': 4,
        'ignores': ['photos/p.jpg (introuvable)'],
      });
      expect(e.fichiers, 4);
      expect(e.ignores, hasLength(1));
      expect(ExportChantier.fromMap({}).ignores, isEmpty);
    });
  });

  group('affichage', () {
    test('heures avec virgule décimale et sans zéros inutiles', () {
      expect(formatHeures(23.5), '23,5');
      expect(formatHeures(8), '8');
      expect(formatHeures(7.75), '7,75');
      expect(formatHeures(0), '0');
      expect(formatHeures(100), '100');
    });
    test('taille lisible', () {
      expect(formatTaille(500), '500 o');
      expect(formatTaille(850 * 1024), '850 Ko');
      expect(formatTaille((12.4 * 1024 * 1024).round()), '12,4 Mo');
    });
  });

  group('carte des heures', () {
    Future<void> ouvrir(WidgetTester tester, Map<String, dynamic> data) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: ResumeHeuresCarte(resume: ResumeChantier.fromMap(data)),
            ),
          ),
        ),
      );
    }

    testWidgets('total, voyagement payé, période et heures par employé', (
      tester,
    ) async {
      await ouvrir(tester, _reponse());
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('resume_total_heures')))
            .data,
        '23,5 h',
      );
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('resume_voyagement')))
            .data,
        '+ 0,75 h de voyagement payé',
      );
      expect(find.textContaining('05/10/2026 au 06/10/2026'), findsOneWidget);
      expect(find.text('Marie'), findsOneWidget);
      expect(find.text('15,75 h'), findsOneWidget);
      expect(find.text('Paul'), findsOneWidget);
    });

    testWidgets('aucune heure : message clair, pas de voyagement', (
      tester,
    ) async {
      await ouvrir(tester, {
        'chantier': {'nom': 'X'},
        'heures': {
          'totalHeures': 0,
          'totalVoyagementPaye': 0,
          'parEmploye': [],
        },
      });
      expect(find.text('Aucune heure saisie sur ce chantier.'), findsOneWidget);
      expect(find.byKey(const ValueKey('resume_voyagement')), findsNothing);
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('resume_total_heures')))
            .data,
        '0 h',
      );
    });
  });

  group('liste des dossiers', () {
    const chantiers = [
      Chantier(
        id: '1',
        companyId: 'A',
        nom: 'Chalet Nord',
        adresse: '1 rue des Pins',
      ),
      Chantier(
        id: '2',
        companyId: 'A',
        nom: 'Garage',
        adresse: '2 rue Lac',
        archive: true,
      ),
      Chantier(
        id: '3',
        companyId: 'A',
        nom: 'Cuisine Tremblay',
        adresse: '3 av. Cartier',
        archive: true,
      ),
    ];

    List<String> ids(FiltreDossiers f, [String q = '']) =>
        filtrerDossiers(chantiers, f, q).map((c) => c.id).toList();

    test('tous : les archivés restent visibles pour l\'admin', () {
      expect(ids(FiltreDossiers.tous), ['1', '2', '3']);
    });
    test('actifs et archivés', () {
      expect(ids(FiltreDossiers.actifs), ['1']);
      expect(ids(FiltreDossiers.archives), ['2', '3']);
    });
    test('recherche par nom ou adresse, sans accents, avec le filtre', () {
      expect(ids(FiltreDossiers.tous, 'tremblay'), ['3']);
      expect(ids(FiltreDossiers.tous, 'lac'), ['2']);
      expect(ids(FiltreDossiers.actifs, 'garage'), isEmpty);
      expect(ids(FiltreDossiers.archives, 'rue'), ['2']);
    });
  });
}
