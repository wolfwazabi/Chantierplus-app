import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'firebase_options.dart';
import 'models/employee.dart';
import 'services/app_session.dart';
import 'services/preferences.dart';
import 'services/theme_compagnie.dart';
import 'screens/compte_screen.dart';
import 'screens/calculatrice_screen.dart';
import 'screens/feuille_temps_screen.dart';
import 'screens/chantier_screen.dart';
import 'screens/admin/admin_home_screen.dart';
import 'screens/admin/compagnies_attente_screen.dart';

// Clé de site reCAPTCHA Enterprise (web), fournie à la compilation :
// flutter build web --dart-define=RECAPTCHA_ENTERPRISE_SITE_KEY=...
const _cleRecaptchaWeb = String.fromEnvironment(
  'RECAPTCHA_ENTERPRISE_SITE_KEY',
);

/// Active App Check : atteste que les requêtes viennent de l'app authentique
/// (Play Integrity sur Android, App Attest sur iOS, reCAPTCHA Enterprise sur
/// le web). En développement, fournisseur de débogage : son jeton, affiché
/// dans la console, doit être enregistré dans la console Firebase.
/// L'app fonctionne même si l'attestation échoue, tant que l'application
/// d'App Check n'est pas imposée côté Firebase.
Future<void> _activerAppCheck() async {
  final plateformeMobile =
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);
  final webConfigure = kIsWeb && _cleRecaptchaWeb.isNotEmpty;
  if (!plateformeMobile && !webConfigure) return;
  try {
    await FirebaseAppCheck.instance.activate(
      providerWeb: webConfigure
          ? ReCaptchaEnterpriseProvider(_cleRecaptchaWeb)
          : null,
      providerAndroid: kReleaseMode
          ? const AndroidPlayIntegrityProvider()
          : const AndroidDebugProvider(),
      providerApple: kReleaseMode
          ? const AppleAppAttestWithDeviceCheckFallbackProvider()
          : const AppleDebugProvider(),
    );
  } catch (e) {
    debugPrint('App Check non activé : $e');
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await _activerAppCheck();
  // Attendre que Firebase ait restauré la session enregistrée : sur le web,
  // currentUser vaut null tant que la restauration n'est pas terminée, et un
  // nouveau compte anonyme ferait perdre la connexion à chaque lancement.
  final utilisateur = await FirebaseAuth.instance.authStateChanges().first;
  if (utilisateur == null) {
    await FirebaseAuth.instance.signInAnonymously();
  }
  await Preferences.charger();
  await AppSession.tenterReconnexionAutomatique();
  runApp(const ConstructionApp());
}

class ConstructionApp extends StatelessWidget {
  const ConstructionApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Couleur de la compagnie connectée (vert par défaut) : toute l'app se
    // redessine quand un admin la change.
    return ValueListenableBuilder<Color>(
      valueListenable: ThemeCompagnie.couleur,
      builder: (context, couleur, _) => MaterialApp(
        title: 'Chantier+',
        debugShowCheckedModeBanner: false,
        theme: ThemeCompagnie.construire(couleur),
        home: const HomePage(),
      ),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _selectedIndex = 0;

  List<_OngletInfo> _construireOnglets(Employee? employee) {
    if (employee == null) {
      return [
        _OngletInfo(
          'Calculatrice',
          Icons.calculate_outlined,
          Icons.calculate,
          const CalculatriceScreen(),
        ),
        _OngletInfo(
          'Temps',
          Icons.access_time_outlined,
          Icons.access_time,
          FeuilleTempsScreen(),
        ),
        _OngletInfo(
          'Chantier',
          Icons.construction_outlined,
          Icons.construction,
          ChantierScreen(),
        ),
        _OngletInfo(
          'Se connecter',
          Icons.login,
          Icons.login,
          const CompteScreen(),
        ),
      ];
    }

    if (employee.estIndividuel) {
      return [
        _OngletInfo(
          'Calculatrice',
          Icons.calculate_outlined,
          Icons.calculate,
          const CalculatriceScreen(),
        ),
        _OngletInfo(
          'Temps',
          Icons.access_time_outlined,
          Icons.access_time,
          FeuilleTempsScreen(),
        ),
        _OngletInfo(
          'Compte',
          Icons.person_outline,
          Icons.person,
          const CompteScreen(),
        ),
      ];
    }

    final estAdmin = employee.role == EmployeeRole.admin;
    // Photos, travaux et matériel : admin et contremaître seulement.
    final estGestionnaire = estAdmin || employee.role == EmployeeRole.plus;

    final onglets = <_OngletInfo>[
      _OngletInfo(
        'Calculatrice',
        Icons.calculate_outlined,
        Icons.calculate,
        const CalculatriceScreen(),
      ),
      _OngletInfo(
        'Temps',
        Icons.access_time_outlined,
        Icons.access_time,
        FeuilleTempsScreen(),
      ),
      if (estGestionnaire)
        _OngletInfo(
          'Chantier',
          Icons.construction_outlined,
          Icons.construction,
          ChantierScreen(),
        ),
    ];

    if (estAdmin) {
      onglets.add(
        _OngletInfo(
          'Admin',
          Icons.bar_chart_outlined,
          Icons.bar_chart,
          const AdminHomeScreen(),
        ),
      );
    }

    // Proprio de l'app (un seul compte, le vôtre) : gestion des compagnies.
    if (employee.estProprioApp) {
      onglets.add(
        _OngletInfo(
          'Compagnies',
          Icons.business_outlined,
          Icons.business,
          const CompagniesAttenteScreen(),
        ),
      );
    }

    onglets.add(
      _OngletInfo(
        'Compte',
        Icons.person_outline,
        Icons.person,
        const CompteScreen(),
      ),
    );

    return onglets;
  }

  void _onItemTapped(int index) {
    setState(() => _selectedIndex = index);
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Employee?>(
      valueListenable: AppSession.notifier,
      builder: (context, employee, _) {
        final onglets = _construireOnglets(employee);
        final indexSecurise = _selectedIndex < onglets.length
            ? _selectedIndex
            : 0;

        return Scaffold(
          body: SafeArea(child: onglets[indexSecurise].ecran),
          bottomNavigationBar: NavigationBar(
            selectedIndex: indexSecurise,
            onDestinationSelected: _onItemTapped,
            destinations: onglets
                .map(
                  (o) => NavigationDestination(
                    icon: Icon(o.icone),
                    selectedIcon: Icon(o.iconeSelectionne),
                    label: o.label,
                  ),
                )
                .toList(),
          ),
        );
      },
    );
  }
}

class _OngletInfo {
  final String label;
  final IconData icone;
  final IconData iconeSelectionne;
  final Widget ecran;
  _OngletInfo(this.label, this.icone, this.iconeSelectionne, this.ecran);
}
