import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

import 'app_session.dart';

/// Numéro de build de cette app, donné à la compilation par Codemagic
/// (`--dart-define=NUMERO_BUILD=…`). 0 : build de développement (rien n'est annoncé
/// ni proposé).
const int numeroBuildCompile = int.fromEnvironment('NUMERO_BUILD');

/// Identifiant de l'app dans App Store Connect (le même que dans codemagic.yaml).
const String idAppleApp = '6817907454';

/// Mise à jour de l'app (demande de l'entrepreneur, 16 oct. 2026) : une pastille sur
/// « Compte » et un bouton « Mettre à jour l'app » sous « Préférences » quand une
/// version plus récente existe.
///
/// La dernière version connue est dans `version_app/{plateforme}` ({build, le}). Elle
/// est annoncée par le premier téléphone d'admin qui ouvre une version plus récente :
/// un build qui roule sur un téléphone est forcément disponible dans TestFlight.
/// Aucune clé à saisir. iPhone seulement pour l'instant (TestFlight) ; Android le
/// sera avec un lien vers le Play Store.
class VersionApp {
  VersionApp._();

  /// Vrai : une version plus récente que celle-ci est disponible.
  static final majDisponible = ValueNotifier<bool>(false);

  /// Tests : remplacent le numéro compilé, la plateforme, Firestore et l'ouverture du lien.
  @visibleForTesting
  static int buildLocal = numeroBuildCompile;
  @visibleForTesting
  static String? plateformeForcee;
  @visibleForTesting
  static Stream<int?> Function(String plateforme)? fluxDerniere;
  @visibleForTesting
  static Future<void> Function(String plateforme, int build)? annoncer;
  @visibleForTesting
  static Future<bool> Function(Uri lien)? ouvrirLien;

  static StreamSubscription<int?>? _abonnement;
  static bool _charge = false;
  static int? _derniere;

  /// 'ios' sur un iPhone ; null ailleurs (pas encore de canal de mise à jour).
  static String? get plateforme {
    if (plateformeForcee != null) return plateformeForcee;
    if (kIsWeb) return null;
    return defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : null;
  }

  /// La page de l'app dans TestFlight (le bouton « Mettre à jour » y est).
  static Uri? lien(String plateforme) => plateforme == 'ios'
      ? Uri.parse('itms-beta://beta.itunes.apple.com/v1/app/$idAppleApp')
      : null;

  /// Écoute la dernière version connue (au démarrage de l'app).
  static void demarrer() {
    final p = plateforme;
    if (buildLocal <= 0 || p == null || _abonnement != null) return;
    _abonnement = (fluxDerniere ?? _lire)(p).listen((build) {
      _charge = true;
      _derniere = build;
      majDisponible.value = build != null && build > buildLocal;
      unawaited(annoncerSiPlusRecente());
    }, onError: (_) {});
  }

  /// Le téléphone d'un admin qui roule une version plus récente que la dernière connue
  /// l'annonce aux autres.
  static Future<void> annoncerSiPlusRecente() async {
    final p = plateforme;
    if (p == null || buildLocal <= 0 || !_charge || !AppSession.estAdmin) {
      return;
    }
    if (_derniere != null && _derniere! >= buildLocal) return;
    try {
      await (annoncer ?? _ecrire)(p, buildLocal);
    } catch (_) {
      // Un autre l'a annoncée en même temps, ou pas de réseau : rien de grave.
    }
  }

  /// Ouvre TestFlight à la page de l'app. Faux si rien n'a pu s'ouvrir.
  static Future<bool> ouvrirMiseAJour() async {
    final p = plateforme;
    final l = p == null ? null : lien(p);
    if (l == null) return false;
    final ouvrir =
        ouvrirLien ??
        (Uri u) => launchUrl(u, mode: LaunchMode.externalApplication);
    for (final u in [
      l,
      Uri.parse('https://beta.itunes.apple.com/v1/app/$idAppleApp'),
    ]) {
      try {
        if (await ouvrir(u)) return true;
      } catch (_) {}
    }
    return false;
  }

  static Stream<int?> _lire(String p) => FirebaseFirestore.instance
      .collection('version_app')
      .doc(p)
      .snapshots()
      .map((d) => (d.data()?['build'] as num?)?.toInt());

  static Future<void> _ecrire(String p, int build) => FirebaseFirestore.instance
      .collection('version_app')
      .doc(p)
      .set({'build': build, 'le': FieldValue.serverTimestamp()});

  /// Tests : remet tout à l'état de départ.
  @visibleForTesting
  static Future<void> reinitialiser() async {
    await _abonnement?.cancel();
    _abonnement = null;
    _charge = false;
    _derniere = null;
    majDisponible.value = false;
    buildLocal = numeroBuildCompile;
    plateformeForcee = null;
    fluxDerniere = null;
    annoncer = null;
    ouvrirLien = null;
  }
}
