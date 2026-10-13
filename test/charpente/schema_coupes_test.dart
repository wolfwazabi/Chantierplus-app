// Schémas des coupes et de la pente : mesures écrites (vérifiées à la main) et
// robustesse du dessin sur des escaliers très différents.
import 'package:construction_app/charpente/escalier.dart';
import 'package:construction_app/charpente/unites.dart';
import 'package:construction_app/screens/charpente/schema_coupes.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('mesures écrites sur les schémas', () {
    // 9 pi, 15 contremarches de 7,2 po, giron 10 1/4 po, marche de 1 1/2 po, 2×12.
    final r = calculerEscalier(const SpecEscalier(hauteurTotale: 108));
    final e = etiquettesCoupes(r, metrique: false);

    test('gabarit : contremarche, giron, diagonale et pente', () {
      expect(e.contremarche, '7 3/16"'); // 7,2 po au 1/16 po
      expect(e.giron, '10 1/4"');
      expect(
        e.diagonale,
        "1' 1/2\"",
      ); // √(7,2² + 10,25²) = 12,526 po = 1 pi 1/2 po
      expect(e.pente, '35,1°'); // atan(7,2 / 10,25)
      expect(e.angleHaut, '54,9°'); // 90° − pente
    });

    test('pied : coupe d\'aplomb (R − épaisseur) et coupe de niveau sur le plancher', () {
      expect(e.aplombBas, '5 11/16"'); // 7,2 − 1,5 = 5,7 po
      // Dessous de la planche : (11,25 − 5,7 × cos θ) ÷ sin θ = 11,4575 po.
      expect(e.niveauPied, '11 7/16"');
    });

    test('tête : coupe d\'aplomb (profondeur ÷ cos θ) et pointe du haut (H − épaisseur)', () {
      expect(
        e.aplombTete,
        "1' 1 3/4\"",
      ); // 11,25 ÷ 0,8183 = 13,748 po = 1 pi 1 3/4 po
      expect(e.pointeHaute, '8\' 10 1/2"'); // 108 − 1,5 = 106,5 po
    });

    test('angles des coupes depuis la coupe d\'équerre', () {
      expect(e.anglePlomb, '35,1°');
      expect(e.angleNiveau, '54,9°');
    });

    test('les mêmes valeurs que le résultat du calcul (rien d\'inventé)', () {
      expect(e.aplombBas, _imperial(r.hauteurDepart));
      expect(e.niveauPied, _imperial(r.coupePied));
      expect(e.aplombTete, _imperial(r.coupeTete));
      expect(e.pointeHaute, _imperial(r.hauteurPointeHaute));
    });

    test('métrique : tout en mm, aucun pouce', () {
      final m = calculerEscalier(
        const SpecEscalier(hauteurTotale: 108),
        metrique: true,
      );
      final em = etiquettesCoupes(m, metrique: true);
      for (final t in [
        em.contremarche,
        em.giron,
        em.diagonale,
        em.aplombBas,
        em.niveauPied,
        em.aplombTete,
      ]) {
        expect(t, contains('mm'), reason: t);
        expect(t, isNot(contains('"')), reason: t);
      }
      // 7,2 po = 182,9 mm ; 10 1/4 po = 260,35 mm.
      expect(em.contremarche, '183 mm');
      expect(em.pente, '35,1°'); // un angle ne change pas d'unité
    });
  });

  group('affichage', () {
    Future<void> montrer(
      WidgetTester t,
      ResultatEscalier r, {
      bool metrique = false,
      double largeur = 360,
    }) async {
      t.view.physicalSize = Size(largeur, 2400);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: SchemaCoupes(resultat: r, metrique: metrique),
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
    }

    testWidgets('trois schémas, chacun avec son titre et sa légende chiffrée', (
      t,
    ) async {
      final r = calculerEscalier(const SpecEscalier(hauteurTotale: 108));
      await montrer(t, r);
      for (final cle in ['schema_gabarit', 'schema_pied', 'schema_tete']) {
        expect(find.byKey(ValueKey(cle)), findsOneWidget, reason: cle);
        expect(
          find.descendant(
            of: find.byKey(ValueKey(cle)),
            matching: find.byType(CustomPaint),
          ),
          findsWidgets,
        );
      }
      expect(find.text('Pied du limon'), findsOneWidget);
      expect(find.text('Tête du limon'), findsOneWidget);
      expect(
        find.textContaining('Pente 35,1°', findRichText: true),
        findsOneWidget,
      );
      expect(
        find.textContaining('Coupe d\'aplomb de 5 11/16"', findRichText: true),
        findsOneWidget,
      );
      expect(
        find.textContaining('coupe de niveau de 11 7/16"', findRichText: true),
        findsOneWidget,
      );
      expect(
        find.textContaining("Coupe d'aplomb de 1' 1 3/4\"", findRichText: true),
        findsOneWidget,
      );
      expect(
        find.textContaining('8\' 10 1/2"', findRichText: true),
        findsOneWidget,
      );
    });

    final cas = <String, SpecEscalier>{
      'escalier ordinaire': const SpecEscalier(hauteurTotale: 108),
      'très raide (contremarche max, giron min)': const SpecEscalier(
        hauteurTotale: 94.5,
        nombreContremarches: 12,
        giron: 10.0625,
      ),
      'très doux (contremarche min, giron large)': const SpecEscalier(
        hauteurTotale: 60,
        nombreContremarches: 12,
        giron: 13.5,
      ),
      'trois contremarches seulement': const SpecEscalier(
        hauteurTotale: 22,
        nombreContremarches: 3,
      ),
      'deux contremarches (une seule marche)': const SpecEscalier(
        hauteurTotale: 14,
        nombreContremarches: 2,
      ),
      'limons en 2×10': const SpecEscalier(
        hauteurTotale: 108,
        section: SectionLimon.s2x10,
      ),
      'escalier commun': const SpecEscalier(
        hauteurTotale: 108,
        usage: UsageEscalier.commun,
      ),
      'très haut (3,6 m)': const SpecEscalier(hauteurTotale: 142),
    };
    for (final MapEntry(key: nom, value: spec) in cas.entries) {
      for (final largeur in [360.0, 800.0]) {
        testWidgets(
          '$nom, écran de ${largeur.toInt()} px : se dessine sans erreur',
          (t) async {
            final r = calculerEscalier(spec);
            await montrer(t, r, largeur: largeur);
            expect(t.takeException(), isNull);
            expect(find.byKey(const ValueKey('schema_coupes')), findsOneWidget);
          },
        );
      }
    }

    testWidgets('métrique : légendes en mm', (t) async {
      final r = calculerEscalier(
        const SpecEscalier(hauteurTotale: 108),
        metrique: true,
      );
      await montrer(t, r, metrique: true);
      expect(find.textContaining('mm', findRichText: true), findsWidgets);
      expect(find.textContaining('"', findRichText: true), findsNothing);
    });
  });
}

/// Même écriture que l'écran en impérial.
String _imperial(double po) => formatLongueur(po, metrique: false);
