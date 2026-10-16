import 'dart:async';
import 'dart:io' show Platform;

import 'package:app_settings/app_settings.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'app_session.dart';

/// Une catégorie de notifications : clé (comme sur le serveur), nom et explication.
class CategorieNotification {
  final String cle;
  final String nom;
  final String explication;
  final IconData icone;
  const CategorieNotification(this.cle, this.nom, this.explication, this.icone);
}

/// Les catégories choisies par l'entrepreneur (16 oct. 2026), dans l'ordre de l'écran.
const categoriesNotification = [
  CategorieNotification(
    'extras',
    'Extras',
    'Un extra est entré sur un chantier',
    Icons.add_task,
  ),
  CategorieNotification(
    'travaux',
    'Travaux à compléter',
    'Un travail à compléter est entré',
    Icons.assignment_outlined,
  ),
  CategorieNotification(
    'materiel',
    'Matériel manquant',
    'Du matériel manquant est entré (chantier ou Général)',
    Icons.shopping_cart_outlined,
  ),
  CategorieNotification(
    'heures',
    'Heures',
    'Un employé envoie ou corrige ses heures',
    Icons.schedule,
  ),
  CategorieNotification(
    'photos',
    'Photos',
    'Des photos sont ajoutées (un envoi = une notification)',
    Icons.photo_library_outlined,
  ),
  CategorieNotification(
    'documents',
    'Documents',
    'Un document est déposé dans un chantier',
    Icons.description_outlined,
  ),
];

/// La permission des notifications sur ce téléphone.
enum PermissionNotifications {
  /// Permises (ou provisoires sur iPhone).
  permises,

  /// Refusées : seuls les réglages du téléphone peuvent les rouvrir.
  bloquees,

  /// Jamais demandées : le téléphone posera la question.
  aDemander,

  /// Pas un téléphone d'admin (web, particulier) ou état illisible.
  sansObjet,
}

/// Notifications sur le téléphone des admins (Firebase Cloud Messaging). Le serveur les envoie
/// (voir functions/src/notifications.js) ; ici :
///  - l'appareil d'un admin connecté demande la permission et enregistre son jeton
///    (appareils_notifications/{uid de sa session}) ; il l'efface à la déconnexion ;
///  - les catégories voulues sont les préférences de l'admin (preferences_notifications/{id},
///    absent = toutes) ;
///  - au premier plan, la notification s'affiche dans un bandeau en bas de l'écran.
class NotificationsPush {
  NotificationsPush._();

  /// Pour afficher une notification reçue pendant que l'app est ouverte.
  static final messager = GlobalKey<ScaffoldMessengerState>();

  static StreamSubscription<String>? _rafraichissement;
  static StreamSubscription<RemoteMessage>? _premierPlan;

  /// Téléphone d'un admin (pas le web, pas un particulier).
  static bool get _disponible =>
      !kIsWeb &&
      (Platform.isAndroid || Platform.isIOS) &&
      AppSession.estAdmin &&
      FirebaseAuth.instance.currentUser?.isAnonymous == true;

  /// Après la connexion d'un admin (et au démarrage) : permission, puis jeton enregistré. Ne
  /// lance jamais : sans notifications, l'app marche quand même.
  static Future<void> activer() async {
    if (!_disponible) return;
    try {
      final m = FirebaseMessaging.instance;
      final permission = await m.requestPermission();
      if (permission.authorizationStatus == AuthorizationStatus.denied) return;
      if (Platform.isIOS) {
        await m.setForegroundNotificationPresentationOptions(
          alert: true,
          badge: true,
          sound: true,
        );
        // Sans jeton Apple (simulateur, clé APNs absente), pas de jeton FCM.
        if (await m.getAPNSToken() == null) return;
      }
      final jeton = await m.getToken();
      if (jeton != null) await _enregistrer(jeton);
      _rafraichissement ??= m.onTokenRefresh.listen(_enregistrer);
      // Android n'affiche pas une notification reçue au premier plan : un bandeau la montre.
      _premierPlan ??= FirebaseMessaging.onMessage.listen((message) {
        final n = message.notification;
        if (n == null) return;
        messager.currentState?.showSnackBar(
          SnackBar(
            content: Text(
              [
                n.title,
                n.body,
              ].whereType<String>().where((t) => t.isNotEmpty).join('\n'),
            ),
            duration: const Duration(seconds: 5),
          ),
        );
      });
    } catch (e) {
      debugPrint('Notifications non activées : $e');
    }
  }

  static Future<void> _enregistrer(String jeton) async {
    final e = AppSession.current;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (e == null || uid == null || !AppSession.estAdmin) return;
    await FirebaseFirestore.instance
        .collection('appareils_notifications')
        .doc(uid)
        .set({
          'companyId': e.companyId,
          'employeeId': e.id,
          'jeton': jeton,
          'plateforme': Platform.isIOS ? 'ios' : 'android',
          'majLe': FieldValue.serverTimestamp(),
        });
  }

  /// La permission actuelle (sans rien demander).
  static Future<PermissionNotifications> etatPermission() async {
    if (!_disponible) return PermissionNotifications.sansObjet;
    try {
      final s = await FirebaseMessaging.instance.getNotificationSettings();
      return switch (s.authorizationStatus) {
        AuthorizationStatus.denied => PermissionNotifications.bloquees,
        AuthorizationStatus.notDetermined => PermissionNotifications.aDemander,
        _ => PermissionNotifications.permises,
      };
    } catch (_) {
      return PermissionNotifications.sansObjet;
    }
  }

  /// Ouvre les réglages des notifications de Chantier+ dans le téléphone (iPhone : iOS 15.4
  /// et plus ; avant, les réglages de l'app).
  static Future<void> ouvrirReglages() =>
      AppSettings.openAppSettings(type: AppSettingsType.notification);

  /// Avant la déconnexion : ce téléphone ne reçoit plus rien.
  static Future<void> desactiver() async {
    await _rafraichissement?.cancel();
    _rafraichissement = null;
    await _premierPlan?.cancel();
    _premierPlan = null;
    if (kIsWeb) return;
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return;
      await FirebaseFirestore.instance
          .collection('appareils_notifications')
          .doc(uid)
          .delete();
      await FirebaseMessaging.instance.deleteToken();
    } catch (_) {}
  }
}

/// Les préférences de notification de l'admin connecté : lire et écrire (remplaçables dans les
/// tests).
class SourcePreferencesNotifications {
  const SourcePreferencesNotifications();

  DocumentReference<Map<String, dynamic>>? get _ref {
    final e = AppSession.current;
    return e == null
        ? null
        : FirebaseFirestore.instance
              .collection('preferences_notifications')
              .doc(e.id);
  }

  /// Les catégories voulues (absent = oui).
  Future<Map<String, bool>> lire() async {
    final d = (await _ref?.get())?.data() ?? const {};
    return {for (final c in categoriesNotification) c.cle: d[c.cle] != false};
  }

  Future<void> ecrire(String categorie, bool voulue) async {
    final e = AppSession.current;
    final ref = _ref;
    if (e == null || ref == null) return;
    await ref.set({
      'companyId': e.companyId,
      categorie: voulue,
    }, SetOptions(merge: true));
  }
}
