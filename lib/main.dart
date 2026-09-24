import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'firebase_options.dart';
import 'models/employee.dart';
import 'services/app_session.dart';
import 'screens/compte_screen.dart';
import 'screens/calculatrice_screen.dart';
import 'screens/feuille_temps_screen.dart';
import 'screens/chantier_screen.dart';
import 'screens/admin/admin_home_screen.dart';
import 'screens/admin/compagnies_attente_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  if (FirebaseAuth.instance.currentUser == null) {
    await FirebaseAuth.instance.signInAnonymously();
  }
  await AppSession.tenterReconnexionAutomatique();
  runApp(const ConstructionApp());
}

class ConstructionApp extends StatelessWidget {
  const ConstructionApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Gestion Chantier',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFEAE2D0),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF2F4A34),
          primary: const Color(0xFF2F4A34),
          secondary: const Color(0xFF8A3B24),
          surface: const Color(0xFFDDD2B8),
          brightness: Brightness.light,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF2F4A34),
          foregroundColor: Color(0xFFEAE2D0),
        ),
        navigationBarTheme: NavigationBarThemeData(
          backgroundColor: const Color(0xFFDDD2B8),
          indicatorColor: const Color(0xFF2F4A34).withValues(alpha: 0.15),
          labelTextStyle: WidgetStateProperty.resolveWith((states) {
            final selectionne = states.contains(WidgetState.selected);
            return TextStyle(
              fontSize: 12,
              color: selectionne ? const Color(0xFF2F4A34) : const Color(0xFF8A8066),
              fontWeight: selectionne ? FontWeight.w600 : FontWeight.normal,
            );
          }),
          iconTheme: WidgetStateProperty.resolveWith((states) {
            final selectionne = states.contains(WidgetState.selected);
            return IconThemeData(
              color: selectionne ? const Color(0xFF2F4A34) : const Color(0xFF8A8066),
            );
          }),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF2F4A34),
            foregroundColor: const Color(0xFFEAE2D0),
          ),
        ),
      ),
      home: const HomePage(),
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
      _OngletInfo(
        'Chantier',
        Icons.construction_outlined,
        Icons.construction,
        ChantierScreen(),
      ),
    ];

    if (estAdmin) {
      onglets.add(_OngletInfo(
        'Admin',
        Icons.bar_chart_outlined,
        Icons.bar_chart,
        const AdminHomeScreen(),
      ));
    }

    if (employee.estSuperAdmin) {
      onglets.add(_OngletInfo(
        'Compagnies',
        Icons.business_outlined,
        Icons.business,
        const CompagniesAttenteScreen(),
      ));
    }

    onglets.add(_OngletInfo(
      'Compte',
      Icons.person_outline,
      Icons.person,
      const CompteScreen(),
    ));

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
        final indexSecurise = _selectedIndex < onglets.length ? _selectedIndex : 0;

        return Scaffold(
          body: SafeArea(child: onglets[indexSecurise].ecran),
          bottomNavigationBar: NavigationBar(
            selectedIndex: indexSecurise,
            onDestinationSelected: _onItemTapped,
            destinations: onglets
                .map((o) => NavigationDestination(
                      icon: Icon(o.icone),
                      selectedIcon: Icon(o.iconeSelectionne),
                      label: o.label,
                    ))
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