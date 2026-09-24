import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/employee.dart';

/// État de connexion de l'application.
///
/// L'identité n'est jamais déduite de données locales : pour un employé, elle
/// provient du document sessions/{uid} écrit par la Cloud Function
/// connexionEmploye ; pour un compte courriel, de Firebase Auth (et du claim
/// superAdmin pour le super-admin).
class AppSession {
  static final ValueNotifier<Employee?> notifier = ValueNotifier<Employee?>(
    null,
  );
  static Employee? get current => notifier.value;

  static StreamSubscription<DocumentSnapshot>? _ecouteSuppression;

  // Anciennes clés (versions précédentes) : effacées au démarrage.
  static const _anciennesCles = ['employee_id', 'company_id', 'is_individuel'];

  static bool get estConnecte => current != null;
  static bool get estSuperAdmin => current?.estSuperAdmin == true;
  static bool get estAdmin => current?.role == EmployeeRole.admin;
  static bool get estProprietaire => current?.estProprietaire == true;
  static bool get estPlusOuAdmin =>
      current?.role == EmployeeRole.admin || current?.role == EmployeeRole.plus;

  static FirebaseFirestore get _db => FirebaseFirestore.instance;
  static FirebaseFunctions get _fonctions => FirebaseFunctions.instance;

  // ==================== RECONNEXION AUTOMATIQUE ====================

  static Future<void> tenterReconnexionAutomatique() async {
    await _effacerAnciennesPrefs();
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      if (user.isAnonymous) {
        await _restaurerSessionEmploye(user.uid);
      } else {
        await _restaurerCompteCourriel(user);
      }
    } catch (_) {
      // Pas de réseau ou session invalide : on reste déconnecté.
      notifier.value = null;
    }
  }

  static Future<void> _restaurerSessionEmploye(String uid) async {
    final session = await _db.collection('sessions').doc(uid).get();
    final data = session.data();
    final employeeId = data?['employeeId'] as String?;
    final companyId = data?['companyId'] as String?;
    if (employeeId == null || companyId == null) return;

    // Les règles refusent ces lectures si l'employé a été retiré ou si la
    // compagnie n'est plus approuvée : l'exception mène à la déconnexion.
    final empDoc = await _db.collection('employees').doc(employeeId).get();
    final companyDoc = await _db.collection('companies').doc(companyId).get();
    if (!empDoc.exists || !companyDoc.exists) return;

    final empData = empDoc.data()!;
    notifier.value = Employee(
      id: employeeId,
      companyId: companyId,
      companyNom: companyDoc.data()!['nomEntreprise'],
      nom: empData['nom'] ?? '',
      role: Employee.roleFromString(empData['role']),
      estProprietaire: empData['estProprietaire'] == true,
    );
    _demarrerEcouteSuppression(employeeId);
  }

  static Future<void> _restaurerCompteCourriel(User user) async {
    final jeton = await user.getIdTokenResult(true);
    if (jeton.claims?['superAdmin'] == true) {
      notifier.value = _superAdmin(user);
      return;
    }
    final doc = await _db.collection('individus').doc(user.uid).get();
    notifier.value = Employee(
      id: user.uid,
      companyId: null,
      companyNom: null,
      nom: doc.exists ? (doc.data()!['nom'] ?? '') : '',
      role: EmployeeRole.employe,
      estIndividuel: true,
    );
  }

  static Employee _superAdmin(User user) => Employee(
    id: user.uid,
    companyId: null,
    companyNom: null,
    nom: user.displayName?.isNotEmpty == true
        ? user.displayName!
        : (user.email ?? 'Super-admin'),
    role: EmployeeRole.employe,
    estSuperAdmin: true,
  );

  // ==================== CONNEXION COMPAGNIE (numéro + NIP) ====================

  static Future<String?> connecterAvecNumeroEtPin(
    String numeroCompagnie,
    String pin,
  ) async {
    try {
      // La connexion employé exige un compte anonyme (voir connexionEmploye).
      final user = FirebaseAuth.instance.currentUser;
      if (user == null || !user.isAnonymous) {
        await FirebaseAuth.instance.signOut();
        await FirebaseAuth.instance.signInAnonymously();
      }
      final resultat = await _fonctions.httpsCallable('connexionEmploye').call({
        'numeroCompagnie': numeroCompagnie,
        'pin': pin,
      });

      final data = Map<String, dynamic>.from(resultat.data);
      final employee = Employee(
        id: data['id'],
        companyId: data['companyId'],
        companyNom: data['companyNom'],
        nom: data['nom'],
        role: Employee.roleFromString(data['role']),
        estProprietaire: data['estProprietaire'] == true,
      );

      notifier.value = employee;
      _demarrerEcouteSuppression(employee.id);
      return null;
    } on FirebaseFunctionsException catch (e) {
      switch (e.code) {
        case 'not-found':
        case 'resource-exhausted':
        case 'failed-precondition':
          return e.message ?? 'Numéro de compagnie ou NIP invalide.';
        case 'invalid-argument':
          return 'Veuillez remplir les deux champs.';
        default:
          return 'Erreur de connexion. Réessayez plus tard.';
      }
    } catch (_) {
      return 'Erreur de connexion. Vérifiez votre réseau.';
    }
  }

  static Future<String> inscrireCompagnie({
    required String nomEntreprise,
    required String nomLegal,
    required String secteur,
    int? nombreEmployes,
    required String telephone,
    required String nomAdmin,
    required String pinAdmin,
    required String emailAdmin,
  }) async {
    final resultat = await _fonctions.httpsCallable('inscrireCompagnie').call({
      'nomEntreprise': nomEntreprise,
      'nomLegal': nomLegal,
      'secteur': secteur,
      'nombreEmployes': nombreEmployes,
      'telephone': telephone,
      'nomAdmin': nomAdmin,
      'pinAdmin': pinAdmin,
      'emailAdmin': emailAdmin,
    });
    final data = Map<String, dynamic>.from(resultat.data);
    return data['numero'];
  }

  // ==================== RÉCUPÉRATION (compagnie) ====================
  // TODO : les Cloud Functions recupererNumeroCompagnie,
  // demanderReinitialisationNip et validerReinitialisationNip n'existent pas
  // encore côté serveur ; ces appels échouent tant qu'elles ne sont pas écrites.

  static Future<void> demanderNumeroCompagnie(String email) async {
    await _fonctions.httpsCallable('recupererNumeroCompagnie').call({
      'email': email,
    });
  }

  static Future<void> demanderCodeReinitialisation(
    String numeroCompagnie,
    String email,
  ) async {
    await _fonctions.httpsCallable('demanderReinitialisationNip').call({
      'numeroCompagnie': numeroCompagnie,
      'email': email,
    });
  }

  static Future<String?> validerReinitialisation({
    required String numeroCompagnie,
    required String email,
    required String code,
    required String nouveauPin,
  }) async {
    try {
      await _fonctions.httpsCallable('validerReinitialisationNip').call({
        'numeroCompagnie': numeroCompagnie,
        'email': email,
        'code': code,
        'nouveauPin': nouveauPin,
      });
      return null;
    } on FirebaseFunctionsException catch (e) {
      return e.message ?? 'Erreur de réinitialisation.';
    } catch (_) {
      return 'Erreur de réinitialisation. Réessayez plus tard.';
    }
  }

  // ==================== COMPTE COURRIEL (particulier / super-admin) ====================

  static Future<String?> inscrireIndividuel(
    String nom,
    String email,
    String motDePasse,
  ) async {
    try {
      final cred = await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: email.trim(),
        password: motDePasse,
      );
      final user = cred.user!;

      // Le courriel enregistré doit correspondre exactement à celui du jeton
      // (Firebase le normalise en minuscules) : exigé par les règles.
      await _db.collection('individus').doc(user.uid).set({
        'nom': nom.trim(),
        'email': user.email,
      });

      try {
        await user.sendEmailVerification();
      } catch (_) {}

      notifier.value = Employee(
        id: user.uid,
        companyId: null,
        companyNom: null,
        nom: nom.trim(),
        role: EmployeeRole.employe,
        estIndividuel: true,
      );
      return null;
    } on FirebaseAuthException catch (e) {
      switch (e.code) {
        case 'email-already-in-use':
          return 'Ce courriel est déjà utilisé.';
        case 'weak-password':
          return 'Mot de passe trop faible (minimum 6 caractères).';
        case 'invalid-email':
          return 'Courriel invalide.';
        default:
          return e.message ?? 'Erreur d\'inscription.';
      }
    } catch (_) {
      return 'Erreur d\'inscription. Réessayez plus tard.';
    }
  }

  static Future<String?> connecterIndividuel(
    String email,
    String motDePasse,
  ) async {
    try {
      // Quitter la session employé éventuelle avant de changer de compte.
      await _supprimerSessionEmploye();
      final cred = await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email.trim(),
        password: motDePasse,
      );
      final user = cred.user!;

      // Active le claim super-admin si ce compte est celui configuré côté
      // serveur (refus silencieux pour tous les autres comptes).
      if (user.emailVerified) {
        try {
          await _fonctions.httpsCallable('activerSuperAdmin').call();
        } catch (_) {}
      }

      await _restaurerCompteCourriel(user);
      return null;
    } on FirebaseAuthException catch (e) {
      switch (e.code) {
        case 'user-not-found':
        case 'wrong-password':
        case 'invalid-credential':
          return 'Courriel ou mot de passe invalide.';
        case 'too-many-requests':
          return 'Trop de tentatives. Réessayez plus tard.';
        default:
          return e.message ?? 'Erreur de connexion.';
      }
    } catch (_) {
      return 'Erreur de connexion. Réessayez plus tard.';
    }
  }

  static Future<String?> reinitialiserMotDePasse(String email) async {
    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email.trim());
      return null;
    } on FirebaseAuthException catch (e) {
      return e.message ?? 'Erreur.';
    }
  }

  // ==================== DÉCONNEXION ====================

  static Future<void> deconnecter() async {
    final user = FirebaseAuth.instance.currentUser;
    notifier.value = null;
    await _ecouteSuppression?.cancel();
    _ecouteSuppression = null;

    if (user != null && !user.isAnonymous) {
      await FirebaseAuth.instance.signOut();
      await FirebaseAuth.instance.signInAnonymously();
      return;
    }
    await _supprimerSessionEmploye();
  }

  static Future<void> _supprimerSessionEmploye() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || !user.isAnonymous) return;
    try {
      await _db.collection('sessions').doc(user.uid).delete();
    } catch (_) {}
  }

  static Future<void> _effacerAnciennesPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      for (final cle in _anciennesCles) {
        await prefs.remove(cle);
      }
    } catch (_) {}
  }

  /// Déconnecte l'employé dès que sa fiche disparaît. Une fois l'employé
  /// supprimé, les règles refusent la lecture : l'erreur déclenche aussi la
  /// déconnexion.
  static void _demarrerEcouteSuppression(String id) {
    _ecouteSuppression?.cancel();
    _ecouteSuppression = _db.collection('employees').doc(id).snapshots().listen(
      (snap) {
        if (!snap.exists) deconnecter();
      },
      onError: (_) => deconnecter(),
    );
  }
}
