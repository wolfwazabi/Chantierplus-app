// Gestes de la vue 3D, avec de vrais événements tactiles (arène des gestes
// comprise) : un pincement doit zoomer sans jamais compter pour un toucher.
import 'package:construction_app/charpente/geometrie.dart';
import 'package:construction_app/charpente/plancher.dart';
import 'package:construction_app/charpente/scene.dart';
import 'package:construction_app/screens/charpente/charpente_screen.dart';
import 'package:construction_app/screens/charpente/vue_3d.dart';
import 'package:construction_app/services/preferences.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Scene _scene() => construireScene(
  plancher: calculerPlancher(
    SpecPlancher(
      forme: Polygone.rectangle(156, 126),
      etriers: ModeEtriers.deuxBouts,
    ),
  ),
);

dynamic _camera(WidgetTester t) => (t
    .widgetList<CustomPaint>(find.byType(CustomPaint))
    .firstWhere((c) => c.painter.runtimeType.toString() == '_Peintre')
    .painter as dynamic)
    .camera;

double _echelle(WidgetTester t) => _camera(t).echelle as double;
double _azimut(WidgetTester t) => _camera(t).azimut as double;

Finder get _zone => find.byKey(const ValueKey('vue3d_zone'));
Finder get _aide => find.textContaining('Touchez une pièce');
Finder _cle(String k) => find.byKey(ValueKey(k));

Future<List<TestGesture>> _poserDeuxDoigts(
  WidgetTester t, {
  required double ecart,
  Duration delai = const Duration(milliseconds: 80),
}) async {
  final c = t.getCenter(_zone);
  // Comme sur un téléphone : le premier doigt se pose, bouge un peu, puis le
  // second arrive quelques dizaines de millisecondes plus tard.
  final a = await t.startGesture(c + Offset(-ecart, 0), pointer: 11);
  await t.pump(const Duration(milliseconds: 16));
  await a.moveBy(const Offset(-1, 0));
  await t.pump(delai);
  final b = await t.startGesture(c + Offset(ecart, 0), pointer: 12);
  await t.pump();
  return [a, b];
}

Future<void> _ecarter(
  WidgetTester t,
  List<TestGesture> doigts, {
  required double debut,
  required double fin,
}) async {
  final c = t.getCenter(_zone);
  for (var i = 1; i <= 10; i++) {
    final d = debut + (fin - debut) * i / 10;
    await doigts[0].moveTo(c + Offset(-d, 0));
    await doigts[1].moveTo(c + Offset(d, 0));
    await t.pump(const Duration(milliseconds: 16));
  }
}

/// Deux doigts qui s'écartent (ou se rapprochent) autour du centre de la zone.
Future<void> _pincer(
  WidgetTester t, {
  required double debut,
  required double fin,
  Duration delai = const Duration(milliseconds: 80),
}) async {
  final doigts = await _poserDeuxDoigts(t, ecart: debut, delai: delai);
  await _ecarter(t, doigts, debut: debut, fin: fin);
  await doigts[0].up();
  await doigts[1].up();
  await t.pumpAndSettle();
}

/// Touche la zone point par point jusqu'à ce qu'une pièce soit choisie.
Future<void> _toucherUnePiece(WidgetTester t) async {
  final rect = t.getRect(_zone);
  for (var y = 0.2; y < 0.9; y += 0.1) {
    for (var x = 0.15; x < 0.9; x += 0.07) {
      await t.tapAt(Offset(rect.left + rect.width * x, rect.top + rect.height * y));
      await t.pump(const Duration(seconds: 1));
      if (_aide.evaluate().isEmpty) return;
    }
  }
  fail('aucune pièce touchée : la zone ne contient rien à choisir');
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    Preferences.unites.value = SystemeUnites.imperial;
  });

  Future<void> ouvrir(WidgetTester t) async {
    t.view.physicalSize = const Size(800, 1600);
    t.view.devicePixelRatio = 2;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(12),
            child: Vue3D(scene: _scene(), horloge: () => t.binding.clock.now()),
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
  }

  group('pincement', () {
    testWidgets('deux doigts qui s\'écartent : zoom avant', (t) async {
      await ouvrir(t);
      final avant = _echelle(t);
      await _pincer(t, debut: 40, fin: 120);
      expect(_echelle(t), greaterThan(avant * 2));
    });

    testWidgets('deux doigts qui se rapprochent : zoom arrière', (t) async {
      await ouvrir(t);
      final avant = _echelle(t);
      await _pincer(t, debut: 120, fin: 40);
      expect(_echelle(t), lessThan(avant * 0.6));
    });

    testWidgets('un pincement ne choisit aucune pièce', (t) async {
      await ouvrir(t);
      expect(_aide, findsOneWidget);
      await _pincer(t, debut: 40, fin: 120);
      expect(_aide, findsOneWidget, reason: 'une pièce a été choisie par erreur');
    });

    testWidgets('lever un doigt puis l\'autre : ce n\'est pas un toucher', (
      t,
    ) async {
      await ouvrir(t);
      final doigts = await _poserDeuxDoigts(t, ecart: 40);
      await _ecarter(t, doigts, debut: 40, fin: 80);
      await doigts[0].up();
      await t.pump(const Duration(milliseconds: 16));
      await doigts[1].up();
      await t.pumpAndSettle();
      expect(_aide, findsOneWidget);
    });

    testWidgets('pincements successifs : le zoom s\'accumule', (t) async {
      await ouvrir(t);
      final avant = _echelle(t);
      await _pincer(t, debut: 40, fin: 80);
      final milieu = _echelle(t);
      expect(milieu, greaterThan(avant * 1.5));
      await _pincer(t, debut: 40, fin: 80, delai: const Duration(milliseconds: 30));
      expect(_echelle(t), greaterThan(milieu * 1.5));
    });

    testWidgets('un doigt : tourne sans zoomer ni choisir de pièce', (t) async {
      await ouvrir(t);
      final avant = _echelle(t);
      final az = _azimut(t);
      final g = await t.startGesture(t.getCenter(_zone), pointer: 21);
      for (var i = 1; i <= 8; i++) {
        await g.moveBy(const Offset(15, 0));
        await t.pump(const Duration(milliseconds: 16));
      }
      await g.up();
      await t.pumpAndSettle();
      expect(_echelle(t), avant);
      expect(_azimut(t), isNot(az));
      expect(_aide, findsOneWidget);
    });
  });

  group('toucher', () {
    testWidgets('un toucher bref sur une pièce la choisit', (t) async {
      await ouvrir(t);
      await _toucherUnePiece(t);
      expect(_aide, findsNothing);
    });

    testWidgets('double toucher : retour à la vue de départ', (t) async {
      await ouvrir(t);
      final depart = _echelle(t);
      await t.tap(_cle('zoom_plus'));
      await t.tap(_cle('zoom_plus'));
      await t.pump();
      expect(_echelle(t), greaterThan(depart * 1.5));
      final c = t.getCenter(_zone);
      await t.tapAt(c);
      await t.pump(const Duration(milliseconds: 100));
      await t.tapAt(c);
      await t.pumpAndSettle();
      expect(_echelle(t), closeTo(depart, depart * 0.001));
    });

    testWidgets('choisir une pièce garde le zoom choisi', (t) async {
      await ouvrir(t);
      await t.tap(_cle('zoom_plus'));
      await t.pump();
      final zoom = _echelle(t);
      await _toucherUnePiece(t);
      // La fiche de la pièce réduit la zone : le zoom (relatif au cadrage) reste.
      final apres = _echelle(t);
      await t.tap(_cle('vue_3quarts')); // cadrage de départ de la zone actuelle
      await t.pump();
      final cadrage = _echelle(t);
      expect(apres / cadrage, closeTo(1.4, 0.05));
      expect(zoom, greaterThan(0));
    });
  });

  group('boutons et molette', () {
    testWidgets('boutons + et − : zoom avant et arrière', (t) async {
      await ouvrir(t);
      final depart = _echelle(t);
      await t.tap(_cle('zoom_plus'));
      await t.pump();
      expect(_echelle(t), closeTo(depart * 1.4, 0.001));
      await t.tap(_cle('zoom_moins'));
      await t.tap(_cle('zoom_moins'));
      await t.pump();
      expect(_echelle(t), closeTo(depart / 1.4, 0.001));
    });

    testWidgets('le zoom des boutons a des limites', (t) async {
      await ouvrir(t);
      final depart = _echelle(t);
      for (var i = 0; i < 20; i++) {
        await t.tap(_cle('zoom_plus'));
      }
      await t.pump();
      expect(_echelle(t), closeTo(depart * 30, 0.01));
      for (var i = 0; i < 40; i++) {
        await t.tap(_cle('zoom_moins'));
      }
      await t.pump();
      expect(_echelle(t), closeTo(depart * 0.2, 0.001));
    });

    testWidgets('molette de souris : zoom', (t) async {
      await ouvrir(t);
      final avant = _echelle(t);
      final souris = TestPointer(31, PointerDeviceKind.mouse);
      await t.sendEventToBinding(souris.hover(t.getCenter(_zone)));
      await t.sendEventToBinding(souris.scroll(const Offset(0, -120)));
      await t.pump();
      expect(_echelle(t), greaterThan(avant));
    });
  });

  testWidgets('onglet 3D de l\'écran Charpente : le pincement zoome', (t) async {
    t.view.physicalSize = const Size(800, 1600);
    t.view.devicePixelRatio = 2;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: CharpenteScreen(
            companyId: 'A',
            chantierId: 'chA',
            connecte: true,
            listeEnregistrees: Text('(aucune commande)'),
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
    await t.tap(find.widgetWithText(Tab, '3D'));
    await t.pumpAndSettle();
    final avant = _echelle(t);
    await _pincer(t, debut: 40, fin: 120);
    expect(_echelle(t), greaterThan(avant * 2));
    expect(_aide, findsOneWidget);
  });
}
