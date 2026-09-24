import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/employee.dart';

class AppSession {
  static final ValueNotifier<Employee?> notifier = ValueNotifier<Employee?>(null);
  static Employee? get current => notifier.value;

  static StreamSubscription<DocumentSnapshot>? _ecouteSuppression;
  static const _cleEmployeeId = 'employee_id';
  static const _cleCompanyId = 'company_id';
  static const _cleIndividuel = 'is_individuel';

  static bool get estConnecte => current != null;
  static bool get estSuperAdmin => current?.estSuperAdmin == true;
  static bool get estAdmin => current?.role == EmployeeRole.admin;
  static bool get estProprietaire => current?.estProprietaire == true;
  static bool get estPlusOuAdmin =>
      current?.role == EmployeeRole.admin || current?.role == EmployeeRole.plus;

  static String? get _uid => FirebaseAuth.instance.currentUser?.uid;

  // ==================== RECONNEXION AUTOMATIQUE ====================

  static Future<void> tenterReconnexionAutomatique() async {
    final prefs = await SharedPreferences.getInstance();

    if (prefs.getBool(_cleIndividuel) == true) {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null && !user.isAnonymous) {
        try {
          final doc = await FirebaseFirestore.instance.collection('individus').doc(user.uid).get();
          notifier.value = Employee(
            id: user.uid,
            companyId: null,
            companyNom: null,
            nom: doc.exists ? (doc.data()!['nom'] ?? '') : '',
            role: EmployeeRole.employe,
            estIndividuel: true,
          );
          return;
        } catch (_) {}
      }
      await prefs.remove(_cleIndividuel);
    }

    final employeeId = prefs.getString(_cleEmployeeId);
    final companyId = prefs.getString(_cleCompanyId);
    if (employeeId == null || companyId == null) return;

    try {
      final empDoc = await FirebaseFirestore.instance.collection('employees').doc(employeeId).get();
      final companyDoc = await FirebaseFirestore.instance.collection('companies').doc(companyId).get();

      if (empDoc.exists && companyDoc.exists && companyDoc.data()!['statut'] == 'approuvee') {
        final empData = empDoc.data()!;
        notifier.value = Employee(
          id: employeeId,
          companyId: companyId,
          companyNom: companyDoc.data()!['nomEntreprise'],
          nom: empData['nom'] ?? '',
          role: Employee.roleFromString(empData['role']),
          estProprietaire: empData['estProprietaire'] == true,
          estSuperAdmin: empData['superAdmin'] == true,
        );
        await _ecrireSession(employeeId, companyId);
        _demarrerEcouteSuppression(employeeId);
      } else {
        await _effacerPrefs();
      }
    } catch (_) {
      // Pas de réseau au démarrage : on reste déconnecté pour cette session
    }
  }

  // ==================== CONNEXION COMPAGNIE (numéro + NIP) ====================

  static Future<String?> connecterAvecNumeroEtPin(String numeroCompagnie, String pin) async {
    try {
      final callable = FirebaseFunctions.instance.httpsCallable('connexionEmploye');
      final resultat = await callable.call({
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
        estSuperAdmin: data['estSuperAdmin'] == true,
      );

      notifier.value = employee;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_cleEmployeeId, employee.id);
      await prefs.setString(_cleCompanyId, employee.companyId!);
      _demarrerEcouteSuppression(employee.id);

      return null;
    } on FirebaseFunctionsException catch (e) {
      switch (e.code) {
        case 'not-found':
          return e.message ?? 'Numéro de compagnie ou NIP invalide.';
        case 'invalid-argument':
          return 'Veuillez remplir les deux champs.';
        default:
          return 'Erreur de connexion : ${e.message}';
      }
    } catch (e) {
      return 'Erreur de connexion : $e';
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
    final callable = FirebaseFunctions.instance.httpsCallable('inscrireCompagnie');
    final resultat = await callable.call({
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

  static Future<void> demanderNumeroCompagnie(String email) async {
    final callable = FirebaseFunctions.instance.httpsCallable('recupererNumeroCompagnie');
    await callable.call({'email': email});
  }

  static Future<void> demanderCodeReinitialisation(String numeroCompagnie, String email) async {
    final callable = FirebaseFunctions.instance.httpsCallable('demanderReinitialisationNip');
    await callable.call({'numeroCompagnie': numeroCompagnie, 'email': email});
  }

  static Future<String?> validerReinitialisation({
    required String numeroCompagnie,
    required String email,
    required String code,
    required String nouveauPin,
  }) async {
    try {
      final callable = FirebaseFunctions.instance.httpsCallable('validerReinitialisationNip');
      await callable.call({
        'numeroCompagnie': numeroCompagnie,
        'email': email,
        'code': code,
        'nouveauPin': nouveauPin,
      });
      return null;
    } on FirebaseFunctionsException catch (e) {
      return e.message ?? 'Erreur de réinitialisation.';
    } catch (e) {
      return 'Erreur : $e';
    }
  }

  // ==================== COMPTE INDIVIDUEL (courriel + mot de passe) ====================

  static Future<String?> inscrireIndividuel(String nom, String email, String motDePasse) async {
    try {
      final cred = await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: email.trim(),
        password: motDePasse,
      );
      final uid = cred.user!.uid;

      await FirebaseFirestore.instance.collection('individus').doc(uid).set({
        'nom': nom.trim(),
        'email': email.trim(),
      });

      notifier.value = Employee(
        id: uid,
        companyId: null,
        companyNom: null,
        nom: nom.trim(),
        role: EmployeeRole.employe,
        estIndividuel: true,
      );

      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_cleIndividuel, true);

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
    } catch (e) {
      return 'Erreur : $e';
    }
  }

  static Future<String?> connecterIndividuel(String email, String motDePasse) async {
    try {
      final cred = await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email.trim(),
        password: motDePasse,
      );
      final uid = cred.user!.uid;

      final doc = await FirebaseFirestore.instance.collection('individus').doc(uid).get();
      final nom = doc.exists ? (doc.data()!['nom'] ?? '') : '';

      notifier.value = Employee(
        id: uid,
        companyId: null,
        companyNom: null,
        nom: nom,
        role: EmployeeRole.employe,
        estIndividuel: true,
      );

      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_cleIndividuel, true);

      return null;
    } on FirebaseAuthException catch (e) {
      switch (e.code) {
        case 'user-not-found':
        case 'wrong-password':
        case 'invalid-credential':
          return 'Courriel ou mot de passe invalide.';
        default:
          return e.message ?? 'Erreur de connexion.';
      }
    } catch (e) {
      return 'Erreur : $e';
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
    final etaitIndividuel = current?.estIndividuel == true;
    notifier.value = null;
    _ecouteSuppression?.cancel();
    _ecouteSuppression = null;
    await _effacerPrefs();

    if (etaitIndividuel) {
      await FirebaseAuth.instance.signOut();
      await FirebaseAuth.instance.signInAnonymously();
      return;
    }

    try {
      final uid = _uid;
      if (uid != null) {
        await FirebaseFirestore.instance.collection('sessions').doc(uid).delete();
      }
    } catch (_) {}
  }

  static Future<void> _effacerPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_cleEmployeeId);
    await prefs.remove(_cleCompanyId);
    await prefs.remove(_cleIndividuel);
  }

  static Future<void> _ecrireSession(String employeeId, String companyId) async {
    final uid = _uid;
    if (uid == null) return;
    await FirebaseFirestore.instance.collection('sessions').doc(uid).set({
      'employeeId': employeeId,
      'companyId': companyId,
    });
  }

  static void _demarrerEcouteSuppression(String id) {
    _ecouteSuppression?.cancel();
    _ecouteSuppression = FirebaseFirestore.instance
        .collection('employees')
        .doc(id)
        .snapshots()
        .listen((snap) {
      if (!snap.exists) {
        deconnecter();
      }
    });
  }
}