// Pastilles de la liste des chantiers (Admin → Chantiers) : les nouveautés de chaque chantier
// depuis la dernière visite du fil Activité.
import 'package:construction_app/models/activite.dart';
import 'package:construction_app/models/chantier.dart';
import 'package:construction_app/models/employee.dart';
import 'package:construction_app/screens/admin/chantiers_gestion_screen.dart';
import 'package:construction_app/services/app_session.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'doubles/faux_activite.dart';
import 'doubles/faux_materiel.dart';

Employee _admin() => Employee(
  id: 'adminA',
  companyId: 'A',
  companyNom: 'Alpha',
  nom: 'Zoé Admin',
  role: EmployeeRole.admin,
  estProprietaire: true,
);

const _garage = Chantier(
  id: 'c1',
  companyId: 'A',
  nom: 'Garage Tremblay',
  adresse: '12 rue des Pins',
);
const _chalet = Chantier(
  id: 'c2',
  companyId: 'A',
  nom: 'Chalet Nord',
  adresse: '5 chemin du Lac',
);

DateTime _d(int j, int h, int min) => DateTime(2026, 7, j, h, min);

Activite _a(
  String id,
  String chantierId,
  DateTime date, {
  String acteurId = 'felix',
  TypeActivite type = TypeActivite.photo,
}) => Activite(
  id: id,
  type: type,
  date: date,
  acteurId: acteurId,
  acteurNom: 'Félix',
  chantierId: chantierId,
);

void main() {
  tearDown(() => AppSession.notifier.value = null);

  group('nouvellesParChantier', () {
    final vu = _d(9, 12, 0);

    test('compte par chantier, seulement après la dernière visite', () {
      final r = nouvellesParChantier(
        [
          _a('p1', 'c1', _d(9, 17, 10)),
          _a('p2', 'c1', _d(9, 18, 0)),
          _a('m1', 'c2', _d(9, 17, 1), type: TypeActivite.materiel),
          _a('p0', 'c2', _d(9, 8, 0)), // avant la visite : déjà vu
        ],
        vu,
        'adminA',
      );
      expect(r, {'c1': 2, 'c2': 1});
    });

    test('ignore mes propres changements', () {
      final r = nouvellesParChantier(
        [
          _a('p1', 'c1', _d(9, 17, 10), acteurId: 'adminA'),
          _a('p2', 'c1', _d(9, 17, 20)),
        ],
        vu,
        'adminA',
      );
      expect(r, {'c1': 1});
    });

    test('ignore ce qui n\'a pas de chantier (heures, achats)', () {
      final r = nouvellesParChantier(
        [
          _a('h1', '', _d(9, 17, 10), type: TypeActivite.heures),
          _a('a1', '', _d(9, 17, 20), type: TypeActivite.achat),
        ],
        vu,
        'adminA',
      );
      expect(r, isEmpty);
    });

    test('sans visite enregistrée, rien n\'est nouveau', () {
      expect(
        nouvellesParChantier([_a('p1', 'c1', _d(9, 17, 10))], null, 'adminA'),
        isEmpty,
      );
    });

    test('Général compte comme un chantier à part', () {
      final r = nouvellesParChantier(
        [
          _a(
            'm1',
            idChantierGeneral,
            _d(9, 17, 10),
            type: TypeActivite.materiel,
          ),
        ],
        vu,
        'adminA',
      );
      expect(r, {idChantierGeneral: 1});
    });
  });

  group('liste des chantiers', () {
    Future<void> ouvrir(
      WidgetTester tester,
      SourceActiviteFausse source, {
      List<Chantier> chantiers = const [_garage, _chalet],
    }) async {
      AppSession.notifier.value = _admin();
      await tester.pumpWidget(
        MaterialApp(
          home: ChantiersGestionScreen(
            fluxChantiers: Stream.value(chantiers),
            sourceMateriel: SourceMaterielGeneralVide(),
            sourceActivite: source,
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    Finder pastille(String id) => find.byKey(ValueKey('pastille_$id'));

    String? nombreDe(WidgetTester tester, String id) {
      final f = find.descendant(of: pastille(id), matching: find.byType(Text));
      return f.evaluate().isEmpty ? null : tester.widget<Text>(f).data;
    }

    testWidgets(
      'une pastille avec le nombre de nouveautés sur chaque chantier',
      (tester) async {
        await ouvrir(
          tester,
          SourceActiviteFausse(
            vus: _d(9, 12, 0),
            activites: [
              _a('p1', 'c1', _d(9, 17, 10)),
              _a('p2', 'c1', _d(9, 17, 20)),
              _a('p3', 'c1', _d(9, 17, 30)),
              _a('m1', 'c2', _d(9, 17, 1), type: TypeActivite.materiel),
            ],
          ),
        );
        expect(nombreDe(tester, 'c1'), '3');
        expect(nombreDe(tester, 'c2'), '1');
      },
    );

    testWidgets('aucune pastille sur un chantier sans nouveauté', (
      tester,
    ) async {
      await ouvrir(
        tester,
        SourceActiviteFausse(
          vus: _d(9, 12, 0),
          activites: [
            _a('p1', 'c1', _d(9, 17, 10)),
            _a('p0', 'c2', _d(9, 8, 0)), // déjà vu
          ],
        ),
      );
      expect(nombreDe(tester, 'c1'), '1');
      expect(nombreDe(tester, 'c2'), isNull);
    });

    testWidgets('rien du tout : aucune pastille, la liste s\'affiche', (
      tester,
    ) async {
      await ouvrir(tester, SourceActiviteFausse(vus: _d(9, 12, 0)));
      expect(find.text('Garage Tremblay'), findsOneWidget);
      expect(find.text('Chalet Nord'), findsOneWidget);
      expect(nombreDe(tester, 'c1'), isNull);
      expect(nombreDe(tester, 'c2'), isNull);
    });

    testWidgets('les changements d\'un chantier inconnu ne cassent rien', (
      tester,
    ) async {
      await ouvrir(
        tester,
        SourceActiviteFausse(
          vus: _d(9, 12, 0),
          activites: [_a('p9', 'supprime', _d(9, 17, 10))],
        ),
      );
      expect(find.text('Garage Tremblay'), findsOneWidget);
      expect(nombreDe(tester, 'c1'), isNull);
    });

    testWidgets(
      'le menu de chaque chantier reste accessible avec la pastille',
      (tester) async {
        await ouvrir(
          tester,
          SourceActiviteFausse(
            vus: _d(9, 12, 0),
            activites: [_a('p1', 'c1', _d(9, 17, 10))],
          ),
        );
        expect(nombreDe(tester, 'c1'), '1');
        await tester.tap(find.byKey(const ValueKey('menu_c1')));
        await tester.pumpAndSettle();
        expect(find.text('Modifier'), findsOneWidget);
        expect(find.text('Archiver'), findsOneWidget);
      },
    );

    testWidgets('un employé non admin ne voit aucune pastille', (tester) async {
      AppSession.notifier.value = Employee(
        id: 'plus1',
        companyId: 'A',
        companyNom: 'Alpha',
        nom: 'Contremaître',
        role: EmployeeRole.plus,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: ChantiersGestionScreen(
            fluxChantiers: Stream.value(const [_garage]),
            sourceMateriel: SourceMaterielGeneralVide(),
            sourceActivite: SourceActiviteFausse(
              vus: _d(9, 12, 0),
              activites: [_a('p1', 'c1', _d(9, 17, 10))],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Réservé aux administrateurs.'), findsOneWidget);
      expect(pastille('c1'), findsNothing);
    });
  });
}
