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
  _permission();

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

/// Le téléphone : la permission lue (une liste qui avance à chaque lecture), les demandes et
/// les ouvertures des réglages.
class _Telephone {
  final List<PermissionNotifications> etats;
  var lectures = 0;
  var demandes = 0;
  var reglages = 0;
  _Telephone(this.etats);

  Future<PermissionNotifications> lire() async =>
      etats[(lectures++).clamp(0, etats.length - 1)];
}

Future<void> _ouvrirAvec(WidgetTester t, _Source s, _Telephone tel) async {
  t.view.physicalSize = const Size(900, 2400);
  t.view.devicePixelRatio = 2;
  addTearDown(t.view.reset);
  await t.pumpWidget(
    MaterialApp(
      home: NotificationsAdminScreen(
        source: s,
        lirePermission: tel.lire,
        demanderPermission: () async => tel.demandes++,
        ouvrirReglages: () async => tel.reglages++,
      ),
    ),
  );
  await t.pumpAndSettle();
}

void _permission() {
  group('permission du téléphone', () {
    testWidgets('permises : pas de bandeau, rien à demander', (t) async {
      final tel = _Telephone([PermissionNotifications.permises]);
      await _ouvrirAvec(t, _Source(_toutes()), tel);
      expect(find.byKey(const ValueKey('notif_bloquees')), findsNothing);
      expect(tel.demandes, 0);
    });

    testWidgets('jamais demandées : le téléphone pose la question', (t) async {
      final tel = _Telephone([
        PermissionNotifications.aDemander,
        PermissionNotifications.permises,
      ]);
      await _ouvrirAvec(t, _Source(_toutes()), tel);
      expect(tel.demandes, 1);
      expect(find.byKey(const ValueKey('notif_bloquees')), findsNothing);
    });

    testWidgets(
      'bloquées : bandeau et bouton vers les réglages ; au retour, permises',
      (t) async {
        final tel = _Telephone([
          PermissionNotifications.bloquees,
          PermissionNotifications.permises,
        ]);
        await _ouvrirAvec(t, _Source(_toutes()), tel);
        expect(find.byKey(const ValueKey('notif_bloquees')), findsOneWidget);
        expect(find.textContaining('bloquées'), findsOneWidget);
        await t.tap(find.byKey(const ValueKey('notif_ouvrir_reglages')));
        await t.pumpAndSettle();
        expect(tel.reglages, 1);
        // Retour dans l'app : permises, le jeton est enregistré, le bandeau part.
        t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
        await t.pumpAndSettle();
        expect(find.byKey(const ValueKey('notif_bloquees')), findsNothing);
        expect(tel.demandes, 1);
      },
    );

    testWidgets('bloquées : activer une catégorie propose les réglages', (
      t,
    ) async {
      final s = _Source(_toutes()..['photos'] = false);
      final tel = _Telephone([PermissionNotifications.bloquees]);
      await _ouvrirAvec(t, s, tel);
      // Fermer une catégorie : rien à proposer.
      await t.tap(find.byKey(const ValueKey('notif_extras')));
      await t.pumpAndSettle();
      expect(find.text('Notifications bloquées'), findsNothing);
      // L'activer : le choix est gardé, puis les réglages sont proposés.
      await t.tap(find.byKey(const ValueKey('notif_photos')));
      await t.pumpAndSettle();
      expect(
        [for (final e in s.ecrits) '${e.key}=${e.value}'],
        ['extras=false', 'photos=true'],
      );
      expect(find.text('Notifications bloquées'), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('notif_dialogue_reglages')));
      await t.pumpAndSettle();
      expect(tel.reglages, 1);
      // « Plus tard » : rien n'est ouvert.
      await t.tap(find.byKey(const ValueKey('notif_extras')));
      await t.pumpAndSettle();
      await t.tap(find.text('Plus tard'));
      await t.pumpAndSettle();
      expect(tel.reglages, 1);
    });
  });
}
