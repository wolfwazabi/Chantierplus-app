// Documents d'un chantier : l'admin voit « Déposer des documents » et les corbeilles
// (onglet Documents de Admin → Chantiers), et les noms des onglets se lisent sur la
// barre de la couleur de la compagnie (pas vert sur vert).
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:construction_app/models/chantier.dart';
import 'package:construction_app/models/employee.dart';
import 'package:construction_app/screens/admin/chantiers_gestion_screen.dart';
import 'package:construction_app/screens/admin/dossier_chantier_screen.dart';
import 'package:construction_app/screens/documents/documents_chantier.dart';
import 'package:construction_app/services/app_session.dart';
import 'package:construction_app/services/theme_compagnie.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'doubles/source_materiel_vide.dart';

const _chalet = Chantier(
  id: 'c1',
  companyId: 'A',
  nom: 'Chalet Nord',
  adresse: '1 rue des Pins',
);

Employee _employe(EmployeeRole role) => Employee(
  id: 'e1',
  companyId: 'A',
  companyNom: 'Alpha',
  nom: 'Alex',
  role: role,
);

/// Rapport de contraste WCAG entre deux couleurs (1 à 21).
double _contraste(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  return (max(la, lb) + 0.05) / (min(la, lb) + 0.05);
}

List<MapEntry<String, Map<String, dynamic>>> _docs() => [
  MapEntry('d1', {
    'nom': 'Plan etage.pdf',
    'taille': 2 * 1024 * 1024,
    'dateAjout': Timestamp.fromDate(DateTime(2026, 10, 3)),
    'url': 'https://exemple.test/plan.pdf',
  }),
  MapEntry('d2', {
    'nom': 'Devis.xlsx',
    'taille': 40 * 1024,
    'dateAjout': Timestamp.fromDate(DateTime(2026, 9, 28)),
    'url': 'https://exemple.test/devis.xlsx',
  }),
];

Widget _documents({
  required bool peutGerer,
  List<MapEntry<String, Map<String, dynamic>>>? docs,
}) => MaterialApp(
  home: Scaffold(
    body: DocumentsChantier(
      companyId: 'A',
      chantierId: 'c1',
      peutGerer: peutGerer,
      fluxDocuments: Stream.value(docs ?? _docs()),
    ),
  ),
);

void main() {
  tearDown(() => AppSession.notifier.value = null);

  group('DocumentsChantier', () {
    testWidgets('admin : bouton de dépôt, documents et une corbeille chacun', (
      tester,
    ) async {
      AppSession.notifier.value = _employe(EmployeeRole.admin);
      await tester.pumpWidget(_documents(peutGerer: true));
      await tester.pumpAndSettle();
      expect(find.text('Déposer des documents'), findsOneWidget);
      expect(find.byIcon(Icons.upload_file), findsOneWidget);
      expect(find.text('Plan etage.pdf'), findsOneWidget);
      expect(find.text('Devis.xlsx'), findsOneWidget);
      expect(find.text('2.0 Mo • 03/10/2026'), findsOneWidget);
      expect(find.text('40 Ko • 28/09/2026'), findsOneWidget);
      expect(find.byTooltip('Supprimer'), findsNWidgets(2));
    });

    testWidgets('admin, aucun document : invitation à en déposer, bouton présent', (
      tester,
    ) async {
      AppSession.notifier.value = _employe(EmployeeRole.admin);
      await tester.pumpWidget(_documents(peutGerer: true, docs: const []));
      await tester.pumpAndSettle();
      expect(find.text('Déposer des documents'), findsOneWidget);
      expect(find.textContaining('Déposez des plans'), findsOneWidget);
    });

    testWidgets('consultation seule : ni dépôt ni corbeille', (tester) async {
      AppSession.notifier.value = _employe(EmployeeRole.plus);
      await tester.pumpWidget(_documents(peutGerer: false));
      await tester.pumpAndSettle();
      expect(find.text('Déposer des documents'), findsNothing);
      expect(find.byTooltip('Supprimer'), findsNothing);
      expect(find.text('Plan etage.pdf'), findsOneWidget);
      expect(find.byIcon(Icons.open_in_new), findsNWidgets(2));
    });
  });

  group('page du chantier : onglet Documents et lisibilité des onglets', () {
    Future<void> ouvrirChantier(WidgetTester tester, Color couleur) async {
      AppSession.notifier.value = _employe(EmployeeRole.admin);
      await tester.pumpWidget(
        MaterialApp(
          // Le vrai thème de la compagnie (barre du haut de sa couleur).
          theme: ThemeCompagnie.construire(couleur),
          home: ChantiersGestionScreen(
            fluxChantiers: Stream.value(const [_chalet]),
            sourceMateriel: SourceMaterielGeneralVide(),
            // Vraie page du chantier ; seuls les accès Firestore sont remplacés.
            pageChantier: (c) => DossierChantierScreen(
              chantier: c,
              fluxChantier: Stream.value(c),
              contenuResume: (_, c) => Text('RESUME ${c.id}'),
              contenuPhotos: (_, c) => Text('PHOTOS ${c.id}'),
              contenuDocuments: (companyId, c) => DocumentsChantier(
                companyId: companyId,
                chantierId: c.id,
                peutGerer: true,
                fluxDocuments: Stream.value(_docs()),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Chalet Nord'));
      await tester.pumpAndSettle();
    }

    // Couleur du texte réellement dessiné pour le nom d'un onglet.
    Color texteDe(WidgetTester tester, String onglet) => tester
        .widget<RichText>(
          find.descendant(
            of: find.widgetWithText(Tab, onglet),
            // Le texte (et non le dessin de l'icône, aussi un RichText).
            matching: find.byWidgetPredicate(
              (w) => w is RichText && w.text.toPlainText() == onglet,
            ),
          ),
        )
        .text
        .style!
        .color!;

    // Couleur de l'icône réellement dessinée.
    Color iconeDe(WidgetTester tester, IconData icone) =>
        IconTheme.of(tester.element(find.byIcon(icone))).color!;

    testWidgets('liste → chantier → onglet Documents : dépôt et corbeilles', (
      tester,
    ) async {
      await ouvrirChantier(tester, ThemeCompagnie.couleurParDefaut);
      expect(find.text('RESUME c1'), findsOneWidget);
      expect(find.text('Déposer des documents'), findsNothing);
      await tester.tap(find.widgetWithText(Tab, 'Documents'));
      await tester.pumpAndSettle();
      expect(find.text('Déposer des documents'), findsOneWidget);
      expect(find.text('Plan etage.pdf'), findsOneWidget);
      expect(find.byTooltip('Supprimer'), findsNWidgets(2));
    });

    for (final (nom, couleur) in [
      ('vert par défaut', ThemeCompagnie.couleurParDefaut),
      ('jaune chantier', const Color(0xFFF2B600)),
      ('bleu', const Color(0xFF1565C0)),
      ('blanc', const Color(0xFFFFFFFF)),
    ]) {
      testWidgets('$nom : noms des onglets lisibles sur la barre (≥ 4,5:1)', (
        tester,
      ) async {
        await ouvrirChantier(tester, couleur);
        // Résumé est choisi ; Photos et Documents ne le sont pas.
        for (final onglet in ['Résumé', 'Photos', 'Documents']) {
          expect(
            _contraste(couleur, texteDe(tester, onglet)),
            greaterThanOrEqualTo(4.5),
            reason: '$onglet sur $nom',
          );
        }
        expect(
          _contraste(couleur, iconeDe(tester, Icons.description_outlined)),
          greaterThanOrEqualTo(4.5),
        );
        // Même en changeant d'onglet, le texte reste lisible.
        await tester.tap(find.widgetWithText(Tab, 'Documents'));
        await tester.pumpAndSettle();
        for (final onglet in ['Résumé', 'Photos', 'Documents']) {
          expect(
            _contraste(couleur, texteDe(tester, onglet)),
            greaterThanOrEqualTo(4.5),
            reason: '$onglet (Documents choisi) sur $nom',
          );
        }
        // L'onglet choisi se distingue des autres.
        expect(texteDe(tester, 'Documents'), isNot(texteDe(tester, 'Résumé')));
      });
    }
  });
}
