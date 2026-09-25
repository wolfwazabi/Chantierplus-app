import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/employee.dart';
import 'fonctions.dart';

/// État de connexion de l'application.
///
/// L'identité n'est jamais déduite de données locales : pour un employé, elle
/// provient du document sessions/{uid} écrit par la Cloud Function
/// connexionEmploye ; pour un particulier, de Firebase Auth.
class AppSession {
  static final ValueNotifier<Employee?> notifier = ValueNotifier<Employee?>(
    null,
  );
  static Employee? get current => notifier.value;

  static StreamSubscription<DocumentSnapshot>? _ecouteSuppression;

  // Clés des versions précédentes : effacées au démarrage.
  static const _anciennesCles = ['employee_id', 'company_id', 'is_individuel'];

  static bool get estConnecte => current != null;
  static bool get estProprioApp => current?.estProprioApp == true;
  static bool get estAdmin => current?.role == EmployeeRole.admin;
  static bool get estProprietaire => current?.estProprietaire == true;
  static bool get estPlusOuAdmin =>
      current?.role == EmployeeRole.admin || current?.role == EmployeeRole.plus;

  static FirebaseFirestore get _db => FirebaseFirestore.instance;

  // ==================== RECONNEXION AUTOMATIQUE ====================

  static Future<void> tenterReconnexionAutomatique() async {
    await _effacerAnciennesPrefs();
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      if (user.isAnonymous) {
        await _restaurerSessionEmploye(user.uid);
      } else {
        await _restaurerIndividu(user);
      }
    } catch (_) {
      // Pas de réseau ou session invalide : on reste déconnecté.
      notifier.value = null;
    }
  }

  static Future<void> _restaurerSessionEmploye(String uid) async {
    final session = (await _db.collection('sessions').doc(uid).get()).data();
    final employeeId = session?['employeeId'] as String?;
    final companyId = session?['companyId'] as String?;
    if (employeeId == null || companyId == null) return;

    // Les règles refusent ces lectures si l'employé a été retiré ou si la
    // compagnie n'est plus approuvée : l'exception mène à la déconnexion.
    final empDoc = await _db.collection('employees').doc(employeeId).get();
    final companyDoc = await _db.collection('companies').doc(companyId).get();
    if (!empDoc.exists || !companyDoc.exists) return;

    final emp = empDoc.data()!;
    notifier.value = Employee(
      id: employeeId,
      companyId: companyId,
      companyNom: companyDoc.data()!['nomEntreprise'],
      nom: emp['nom'] ?? '',
      role: Employee.roleFromString(emp['role']),
      estProprietaire: emp['estProprietaire'] == true,
      // Indicatif pour l'interface (écrit par le serveur à la connexion) ; les
      // règles et les fonctions revérifient config/proprio_app à chaque requête.
      estProprioApp:
          session?['proprioApp'] == true && session?['methode'] == 'courriel',
    );
    _demarrerEcouteSuppression(employeeId);
  }

  static Future<void> _restaurerIndividu(User user) async {
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

  // ==================== CONNEXION COMPAGNIE ====================

  /// Connexion par numéro de compagnie + courriel + NIP. Le courriel peut être
  /// vide pour un employé dont l'employeur ne l'a pas encore enregistré.
  static Future<String?> connecterEmploye({
    required String numeroCompagnie,
    required String courriel,
    required String pin,
  }) async {
    try {
      // La connexion employé exige un compte anonyme (voir connexionEmploye).
      final user = FirebaseAuth.instance.currentUser;
      if (user == null || !user.isAnonymous) {
        await FirebaseAuth.instance.signOut();
        await FirebaseAuth.instance.signInAnonymously();
      }
      final data = await Fonctions.appeler('connexionEmploye', {
        'numeroCompagnie': numeroCompagnie,
        if (courriel.isNotEmpty) 'courriel': courriel,
        'pin': pin,
      });

      final employee = Employee(
        id: data['id'],
        companyId: data['companyId'],
        companyNom: data['companyNom'],
        nom: data['nom'] ?? '',
        role: Employee.roleFromString(data['role']),
        estProprietaire: data['estProprietaire'] == true,
        estProprioApp: data['estProprioApp'] == true,
      );
      notifier.value = employee;
      _demarrerEcouteSuppression(employee.id);
      return null;
    } catch (e) {
      return Fonctions.message(e, 'Erreur de connexion. Réessayez plus tard.');
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
    final data = await Fonctions.appeler('inscrireCompagnie', {
      'nomEntreprise': nomEntreprise,
      'nomLegal': nomLegal,
      'secteur': secteur,
      'nombreEmployes': nombreEmployes,
      'telephone': telephone,
      'nomAdmin': nomAdmin,
      'pinAdmin': pinAdmin,
      'emailAdmin': emailAdmin,
    });
    return data['numero'];
  }

  // ==================== NIP ====================

  static Future<String?> changerNip(String nipActuel, String nouveauNip) async {
    try {
      await Fonctions.appeler('changerNip', {
        'nipActuel': nipActuel,
        'nouveauNip': nouveauNip,
      });
      return null;
    } catch (e) {
      return Fonctions.message(e, 'Impossible de changer le NIP.');
    }
  }

  /// Retourne null si la demande est partie, sinon un message d'erreur.
  static Future<String?> demanderNumeroCompagnie(String email) async {
    try {
      await Fonctions.appeler('recupererNumeroCompagnie', {'email': email});
      return null;
    } catch (e) {
      return Fonctions.message(e);
    }
  }

  /// Retourne null si la demande est partie, sinon un message d'erreur.
  static Future<String?> demanderCodeReinitialisation(
    String numeroCompagnie,
    String email,
  ) async {
    try {
      await Fonctions.appeler('demanderReinitialisationNip', {
        'numeroCompagnie': numeroCompagnie,
        'email': email,
      });
      return null;
    } catch (e) {
      return Fonctions.message(e);
    }
  }

  static Future<String?> validerReinitialisation({
    required String numeroCompagnie,
    required String email,
    required String code,
    required String nouveauPin,
  }) async {
    try {
      await Fonctions.appeler('validerReinitialisationNip', {
        'numeroCompagnie': numeroCompagnie,
        'email': email,
        'code': code,
        'nouveauPin': nouveauPin,
      });
      return null;
    } catch (e) {
      return Fonctions.message(e, 'Erreur de réinitialisation.');
    }
  }

  // ==================== PARTICULIER (courriel + mot de passe) ====================

  static Future<String?> inscrireIndividuel(
    String nom,
    String email,
    String motDePasse,
  ) async {
    try {
      await _supprimerSessionEmploye();
      final cred = await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: email.trim(),
        password: motDePasse,
      );
      final user = cred.user!;

      // Courriel tel que normalisé par Firebase (exigé par les règles).
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
      await _supprimerSessionEmploye();
      final cred = await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email.trim(),
        password: motDePasse,
      );
      await _restaurerIndividu(cred.user!);
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
