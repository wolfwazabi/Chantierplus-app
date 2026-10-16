// Admin > Notifications : les catégories reçues sur le téléphone, chacune activable ou fermée.
import 'package:construction_app/screens/admin/notifications_admin_screen.dart';
import 'package:construction_app/services/notifications_push.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _Source extends SourcePreferencesNotifications {
  Map<String, bool> etat;
  final List<MapEntry<String, bool>> ecrits = [];
  bool echec = false;
  _Source(this.etat);

  @override
  Future<Map<String, bool>> lire() async => {...etat};

  @override
  Future<void> ecrire(String categorie, bool voulue) async {
    if (echec) throw Exception('hors ligne');
    ecrits.add(MapEntry(categorie, voulue));
    etat = {...etat, categorie: voulue};
  }
}

Map<String, bool> _toutes([bool v = true]) => {
  for (final c in categoriesNotification) c.cle: v,
};

Future<void> _ouvrir(WidgetTester t, _Source s) async {
  t.view.physicalSize = const Size(900, 2400);
  t.view.devicePixelRatio = 2;
  addTearDown(t.view.reset);
  await t.pumpWidget(MaterialApp(home: NotificationsAdminScreen(source: s)));
  await t.pumpAndSettle();
}

bool _active(WidgetTester t, String cle) =>
    t.widget<SwitchListTile>(find.byKey(ValueKey('notif_$cle'))).value;

void main() {
  test('les six catégories de l\'entrepreneur, comme sur le serveur', () {
    expect(
      [for (final c in categoriesNotification) c.cle],
      ['extras', 'travaux', 'materiel', 'heures', 'photos', 'documents'],
    );
  });

  testWidgets('chaque catégorie s\'active ou se ferme, et le choix est gardé', (
    t,
  ) async {
    final s = _Source(_toutes()..['photos'] = false);
    await _ouvrir(t, s);
    for (final nom in [
      'Extras',
      'Travaux à compléter',
      'Matériel manquant',
      'Heures',
      'Photos',
      'Documents',
    ]) {
      expect(find.text(nom), findsOneWidget, reason: nom);
    }
    expect(_active(t, 'extras'), isTrue);
    expect(_active(t, 'photos'), isFalse);
    await t.tap(find.byKey(const ValueKey('notif_heures')));
    await t.pumpAndSettle();
    expect([for (final e in s.ecrits) '${e.key}=${e.value}'], ['heures=false']);
    expect(_active(t, 'heures'), isFalse);
  });

  testWidgets(
    'changement non enregistré (réseau) : remis comme avant, message',
    (t) async {
      final s = _Source(_toutes())..echec = true;
      await _ouvrir(t, s);
      await t.tap(find.byKey(const ValueKey('notif_extras')));
      await t.pumpAndSettle();
      expect(_active(t, 'extras'), isTrue);
      expect(find.textContaining('non enregistré'), findsOneWidget);
    },
  );
}
