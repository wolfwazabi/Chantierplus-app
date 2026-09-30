import 'package:flutter/material.dart';

import '../models/employee.dart';
import '../services/app_session.dart';
import '../services/fonctions.dart';
import '../services/preferences.dart';
import 'preferences_screen.dart';
import '../services/theme_compagnie.dart';

const List<String> metiersQuebec = [
  'Charpentier-menuisier',
  'Électricien',
  'Plombier',
  'Tuyauteur',
  'Ferblantier',
  'Poseur de systèmes intérieurs',
  'Peintre',
  'Carreleur',
  'Calorifugeur',
  'Cimentier-applicateur',
  'Briqueteur-maçon',
  'Grutier',
  'Opérateur d\'équipement lourd',
  'Mécanicien de chantier',
  'Monteur-assembleur',
  'Monteur de charpentes métalliques',
  'Chaudronnier',
  'Soudeur en tuyauterie',
  'Poseur de revêtements souples',
  'Vitrier',
  'Couvreur',
  'Arpenteur',
  'Ferrailleur',
  'Tireur de joints',
  'Excavation / Terrassement',
  'Isolateur',
  'Serrurier de bâtiment',
  'Frigoriste',
  'Entrepreneur général',
  'Autre',
];

class CompteScreen extends StatefulWidget {
  const CompteScreen({super.key});

  @override
  State<CompteScreen> createState() => _CompteScreenState();
}

class _CompteScreenState extends State<CompteScreen> {
  int _mode =
      0; // 0 = connexion compagnie, 1 = inscription compagnie, 2 = individuel

  final _numeroCtrl = TextEditingController();
  final _courrielCtrl = TextEditingController();
  final _pinCtrl = TextEditingController();
  bool _enCours = false;
  String? _erreur;

  final _nomEntrepriseCtrl = TextEditingController();
  final _nomLegalCtrl = TextEditingController();
  final _telephoneCtrl = TextEditingController();
  final _nombreEmployesCtrl = TextEditingController();
  final _nomAdminCtrl = TextEditingController();
  final _pinAdminCtrl = TextEditingController();
  final _emailAdminCtrl = TextEditingController();
  String? _secteurChoisi;
  bool _inscriptionEnCours = false;
  String? _inscriptionErreur;
  String? _numeroAttribue;

  final _emailIndividuelCtrl = TextEditingController();
  final _motDePasseIndividuelCtrl = TextEditingController();
  final _nomIndividuelCtrl = TextEditingController();
  bool _modeInscriptionIndividuel = false;
  bool _resterConnecte = Preferences.resterConnecte;
  bool _individuelEnCours = false;
  String? _individuelErreur;

  Future<void> _seConnecter() async {
    final numero = _numeroCtrl.text.trim();
    final courriel = _courrielCtrl.text.trim();
    final pin = _pinCtrl.text.trim();

    if (numero.isEmpty || courriel.isEmpty || pin.isEmpty) {
      setState(
        () => _erreur =
            'Entrez votre numéro de compagnie, votre courriel et votre NIP.',
      );
      return;
    }

    setState(() {
      _enCours = true;
      _erreur = null;
    });

    final erreur = await AppSession.connecterEmploye(
      numeroCompagnie: numero,
      courriel: courriel,
      pin: pin,
    );

    if (erreur != null) {
      setState(() {
        _erreur = erreur;
        _enCours = false;
      });
      return;
    }

    await Preferences.choisirResterConnecte(_resterConnecte);
    _numeroCtrl.clear();
    _courrielCtrl.clear();
    _pinCtrl.clear();
    if (mounted) setState(() => _enCours = false);
  }

  @override
  void dispose() {
    for (final c in [
      _numeroCtrl,
      _courrielCtrl,
      _pinCtrl,
      _nomEntrepriseCtrl,
      _nomLegalCtrl,
      _telephoneCtrl,
      _nombreEmployesCtrl,
      _nomAdminCtrl,
      _pinAdminCtrl,
      _emailAdminCtrl,
      _emailIndividuelCtrl,
      _motDePasseIndividuelCtrl,
      _nomIndividuelCtrl,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  void _ouvrirPreferences() {
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const PreferencesScreen()));
  }

  Future<void> _seDeconnecter() async {
    await AppSession.deconnecter();
  }

  void _ouvrirChangementNip() {
    final actuelCtrl = TextEditingController();
    final nouveauCtrl = TextEditingController();
    final confirmationCtrl = TextEditingController();
    String? erreur;
    bool enCours = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          Future<void> confirmer() async {
            final nouveau = nouveauCtrl.text.trim();
            if (!RegExp(r'^\d{6,8}$').hasMatch(nouveau)) {
              setDialogState(
                () =>
                    erreur = 'Le nouveau NIP doit contenir de 6 à 8 chiffres.',
              );
              return;
            }
            if (nouveau != confirmationCtrl.text.trim()) {
              setDialogState(
                () => erreur = 'La confirmation ne correspond pas.',
              );
              return;
            }
            setDialogState(() {
              enCours = true;
              erreur = null;
            });
            final resultat = await AppSession.changerNip(
              actuelCtrl.text.trim(),
              nouveau,
            );
            if (resultat != null) {
              setDialogState(() {
                erreur = resultat;
                enCours = false;
              });
              return;
            }
            if (ctx.mounted) Navigator.pop(ctx);
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    'NIP modifié. Vos autres appareils ont été déconnectés.',
                  ),
                  backgroundColor: Colors.green,
                ),
              );
            }
          }

          InputDecoration champ(String libelle) =>
              InputDecoration(labelText: libelle, counterText: '');

          return AlertDialog(
            title: const Text('Changer mon NIP'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: actuelCtrl,
                  keyboardType: TextInputType.number,
                  obscureText: true,
                  maxLength: 8,
                  decoration: champ('NIP actuel'),
                ),
                TextField(
                  controller: nouveauCtrl,
                  keyboardType: TextInputType.number,
                  obscureText: true,
                  maxLength: 8,
                  decoration: champ('Nouveau NIP (6 à 8 chiffres)'),
                ),
                TextField(
                  controller: confirmationCtrl,
                  keyboardType: TextInputType.number,
                  obscureText: true,
                  maxLength: 8,
                  decoration: champ('Confirmer le nouveau NIP'),
                ),
                if (erreur != null) ...[
                  const SizedBox(height: 8),
                  Text(erreur!, style: const TextStyle(color: Colors.red)),
                ],
              ],
            ),
            actions: [
              TextButton(
                onPressed: enCours ? null : () => Navigator.pop(ctx),
                child: const Text('Annuler'),
              ),
              FilledButton(
                onPressed: enCours ? null : confirmer,
                child: const Text('Confirmer'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _soumettreInscription() async {
    if (_nomEntrepriseCtrl.text.trim().isEmpty ||
        _nomLegalCtrl.text.trim().isEmpty ||
        _secteurChoisi == null ||
        _nomAdminCtrl.text.trim().isEmpty ||
        _pinAdminCtrl.text.trim().isEmpty ||
        _emailAdminCtrl.text.trim().isEmpty) {
      setState(
        () => _inscriptionErreur = 'Veuillez remplir tous les champs requis.',
      );
      return;
    }
    if (!RegExp(r'^\d{6,8}$').hasMatch(_pinAdminCtrl.text.trim())) {
      setState(
        () => _inscriptionErreur = 'Le NIP doit contenir de 6 à 8 chiffres.',
      );
      return;
    }

    setState(() {
      _inscriptionEnCours = true;
      _inscriptionErreur = null;
    });

    try {
      final numero = await AppSession.inscrireCompagnie(
        nomEntreprise: _nomEntrepriseCtrl.text.trim(),
        nomLegal: _nomLegalCtrl.text.trim(),
        secteur: _secteurChoisi!,
        nombreEmployes: int.tryParse(_nombreEmployesCtrl.text.trim()),
        telephone: _telephoneCtrl.text.trim(),
        nomAdmin: _nomAdminCtrl.text.trim(),
        pinAdmin: _pinAdminCtrl.text.trim(),
        emailAdmin: _emailAdminCtrl.text.trim(),
      );

      setState(() {
        _numeroAttribue = numero;
        _inscriptionEnCours = false;
      });
    } catch (e) {
      setState(() {
        _inscriptionErreur = Fonctions.message(
          e,
          'Erreur lors de l\'inscription.',
        );
        _inscriptionEnCours = false;
      });
    }
  }

  Future<void> _soumettreIndividuel() async {
    setState(() {
      _individuelEnCours = true;
      _individuelErreur = null;
    });

    String? erreur;
    if (_modeInscriptionIndividuel) {
      if (_nomIndividuelCtrl.text.trim().isEmpty ||
          _emailIndividuelCtrl.text.trim().isEmpty ||
          _motDePasseIndividuelCtrl.text.isEmpty) {
        setState(() {
          _individuelErreur = 'Veuillez remplir tous les champs.';
          _individuelEnCours = false;
        });
        return;
      }
      erreur = await AppSession.inscrireIndividuel(
        _nomIndividuelCtrl.text.trim(),
        _emailIndividuelCtrl.text.trim(),
        _motDePasseIndividuelCtrl.text,
      );
    } else {
      erreur = await AppSession.connecterIndividuel(
        _emailIndividuelCtrl.text.trim(),
        _motDePasseIndividuelCtrl.text,
      );
    }

    if (erreur == null) {
      await Preferences.choisirResterConnecte(_resterConnecte);
    }
    if (!mounted) return;
    setState(() {
      _individuelErreur = erreur;
      _individuelEnCours = false;
    });
  }

  String _libelleRole(Employee employee) {
    if (employee.estIndividuel) return 'Compte individuel';
    if (employee.estProprietaire) return 'Super-admin';
    switch (employee.role) {
      case EmployeeRole.admin:
        return 'Administrateur';
      case EmployeeRole.plus:
        return 'Contremaître';
      case EmployeeRole.employe:
        return 'Employé';
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Employee?>(
      valueListenable: AppSession.notifier,
      builder: (context, employee, _) {
        if (employee != null) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircleAvatar(
                    radius: 40,
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    child: Icon(
                      Icons.person,
                      size: 40,
                      color: Theme.of(context).colorScheme.onPrimary,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    employee.nom,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _libelleRole(employee),
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 15),
                  ),
                  if (employee.companyNom != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      employee.companyNom!,
                      style: TextStyle(
                        color: Colors.grey.shade500,
                        fontSize: 13,
                      ),
                    ),
                  ],
                  if (employee.estProprioApp) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.purple.shade50,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        'Proprio de l\'application',
                        style: TextStyle(
                          color: Colors.purple.shade700,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 32),
                  if (!employee.estIndividuel) ...[
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _ouvrirChangementNip,
                        icon: const Icon(Icons.pin_outlined),
                        label: const Text('Changer mon NIP'),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      key: const ValueKey('bouton_preferences'),
                      onPressed: _ouvrirPreferences,
                      icon: const Icon(Icons.tune),
                      label: const Text('Préférences'),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _seDeconnecter,
                      icon: const Icon(Icons.logout),
                      label: const Text('Se déconnecter'),
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        return Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.construction,
                    size: 56,
                    color: ThemeCompagnie.accentDe(context),
                  ),
                  const SizedBox(height: 16),
                  ToggleButtons(
                    isSelected: [_mode == 0, _mode == 1, _mode == 2],
                    onPressed: (index) => setState(() {
                      _mode = index;
                      _numeroAttribue = null;
                    }),
                    borderRadius: BorderRadius.circular(8),
                    children: const [
                      Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        child: Text('Se connecter'),
                      ),
                      Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        child: Text('Inscrire compagnie'),
                      ),
                      Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        child: Text('Particuliers'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  if (_mode == 0)
                    _formulaireConnexion()
                  else if (_mode == 1)
                    _formulaireInscription()
                  else
                    _formulaireIndividuel(),
                  const SizedBox(height: 24),
                  // Accessible sans connexion : la calculatrice l'utilise.
                  TextButton.icon(
                    key: const ValueKey('bouton_preferences'),
                    onPressed: _ouvrirPreferences,
                    icon: const Icon(Icons.tune),
                    label: const Text('Préférences (unités de mesure)'),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _caseResterConnecte() {
    return CheckboxListTile(
      key: const ValueKey('rester_connecte'),
      value: _resterConnecte,
      onChanged: (v) => setState(() => _resterConnecte = v ?? true),
      title: const Text('Rester connecté'),
      subtitle: const Text(
        'Décochez sur un appareil partagé : vous serez déconnecté à la '
        'prochaine ouverture de l\'app.',
        style: TextStyle(fontSize: 12),
      ),
      controlAffinity: ListTileControlAffinity.leading,
      contentPadding: EdgeInsets.zero,
      dense: true,
    );
  }

  Widget _formulaireConnexion() {
    return Column(
      children: [
        TextField(
          controller: _numeroCtrl,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Numéro de compagnie',
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.business),
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _courrielCtrl,
          keyboardType: TextInputType.emailAddress,
          autocorrect: false,
          decoration: const InputDecoration(
            labelText: 'Courriel',
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.email_outlined),
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _pinCtrl,
          keyboardType: TextInputType.number,
          obscureText: true,
          decoration: const InputDecoration(
            labelText: 'NIP',
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.lock),
          ),
          onSubmitted: (_) => _seConnecter(),
        ),
        _caseResterConnecte(),
        if (_erreur != null) ...[
          const SizedBox(height: 12),
          Text(_erreur!, style: const TextStyle(color: Colors.red)),
        ],
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: _enCours ? null : _seConnecter,
            style: FilledButton.styleFrom(padding: const EdgeInsets.all(16)),
            child: _enCours
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Se connecter'),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TextButton(
              onPressed: _ouvrirNumeroOublie,
              child: const Text('Numéro de compangnie oublié ?'),
            ),
            const Text('•'),
            TextButton(
              onPressed: _ouvrirNipOublie,
              child: const Text('NIP oublié ?'),
            ),
          ],
        ),
      ],
    );
  }

  void _ouvrirNumeroOublie() {
    final emailCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Numéro de compagnie oublié'),
        content: TextField(
          controller: emailCtrl,
          keyboardType: TextInputType.emailAddress,
          decoration: const InputDecoration(labelText: 'Votre courriel'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.pop(ctx);
              final erreur = await AppSession.demanderNumeroCompagnie(
                emailCtrl.text.trim(),
              );
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    erreur ?? 'Si ce courriel est associé à une compagnie, vous recevrez un message.',
                  ),
                  backgroundColor: erreur == null ? null : Colors.red,
                ),
              );
            },
            child: const Text('Envoyer'),
          ),
        ],
      ),
    );
  }

  void _ouvrirNipOublie() {
    final numeroCtrl = TextEditingController();
    final emailCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('NIP oublié'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: numeroCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Numéro de compagnie',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: emailCtrl,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(labelText: 'Votre courriel'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () async {
              final numero = numeroCtrl.text.trim();
              final email = emailCtrl.text.trim();
              Navigator.pop(ctx);
              final erreur = await AppSession.demanderCodeReinitialisation(
                numero,
                email,
              );
              if (!mounted) return;
              if (erreur != null) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(erreur), backgroundColor: Colors.red),
                );
                return;
              }
              _ouvrirSaisieCode(numero, email);
            },
            child: const Text('Recevoir un code'),
          ),
        ],
      ),
    );
  }

  void _ouvrirSaisieCode(String numero, String email) {
    final codeCtrl = TextEditingController();
    final nouveauPinCtrl = TextEditingController();
    String? erreurCode;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Entrez le code reçu par courriel'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: codeCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Code (6 chiffres)',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: nouveauPinCtrl,
                keyboardType: TextInputType.number,
                obscureText: true,
                maxLength: 8,
                decoration: const InputDecoration(
                  labelText: 'Nouveau NIP (6 à 8 chiffres)',
                ),
              ),
              if (erreurCode != null) ...[
                const SizedBox(height: 8),
                Text(erreurCode!, style: const TextStyle(color: Colors.red)),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: () async {
                final erreur = await AppSession.validerReinitialisation(
                  numeroCompagnie: numero,
                  email: email,
                  code: codeCtrl.text.trim(),
                  nouveauPin: nouveauPinCtrl.text.trim(),
                );
                if (erreur != null) {
                  setDialogState(() => erreurCode = erreur);
                } else {
                  if (ctx.mounted) Navigator.pop(ctx);
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'NIP réinitialisé avec succès. Vous pouvez vous connecter.',
                        ),
                        backgroundColor: Colors.green,
                      ),
                    );
                  }
                }
              },
              child: const Text('Confirmer'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _formulaireInscription() {
    if (_numeroAttribue != null) {
      return Card(
        color: Colors.green.shade50,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              const Icon(Icons.check_circle, color: Colors.green, size: 48),
              const SizedBox(height: 12),
              const Text(
                'Demande envoyée !',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 8),
              Text(
                'Votre numéro de compagnie : $_numeroAttribue',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                'Votre inscription est en attente d\'approbation. Vous pourrez vous connecter dès qu\'elle sera approuvée.',
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Informations sur la compagnie',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _nomEntrepriseCtrl,
          decoration: const InputDecoration(
            labelText: 'Nom d\'entreprise',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _nomLegalCtrl,
          decoration: const InputDecoration(
            labelText: 'Nom légal',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          initialValue: _secteurChoisi,
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: 'Secteur / métier',
            border: OutlineInputBorder(),
          ),
          items: metiersQuebec
              .map((m) => DropdownMenuItem(value: m, child: Text(m)))
              .toList(),
          onChanged: (v) => setState(() => _secteurChoisi = v),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _nombreEmployesCtrl,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Nombre d\'employés (approx.)',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _telephoneCtrl,
          keyboardType: TextInputType.phone,
          decoration: const InputDecoration(
            labelText: 'Téléphone',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 20),
        const Text(
          'Votre compte administrateur (propriétaire)',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _nomAdminCtrl,
          decoration: const InputDecoration(
            labelText: 'Votre nom',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _pinAdminCtrl,
          keyboardType: TextInputType.number,
          obscureText: true,
          decoration: const InputDecoration(
            labelText: 'Choisissez un NIP (6 à 8 chiffres)',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _emailAdminCtrl,
          keyboardType: TextInputType.emailAddress,
          decoration: const InputDecoration(
            labelText: 'Courriel',
            border: OutlineInputBorder(),
            helperText: 'Utilisé pour récupérer votre numéro de compagnie ou réinitialiser votre NIP',
          ),
        ),
        if (_inscriptionErreur != null) ...[
          const SizedBox(height: 12),
          Text(_inscriptionErreur!, style: const TextStyle(color: Colors.red)),
        ],
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: _inscriptionEnCours ? null : _soumettreInscription,
            style: FilledButton.styleFrom(padding: const EdgeInsets.all(16)),
            child: _inscriptionEnCours
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Envoyer la demande'),
          ),
        ),
      ],
    );
  }

  Widget _formulaireIndividuel() {
    return Column(
      children: [
        SegmentedButton<bool>(
          segments: const [
            ButtonSegment(value: false, label: Text('Se connecter')),
            ButtonSegment(value: true, label: Text('Créer un compte')),
          ],
          selected: {_modeInscriptionIndividuel},
          onSelectionChanged: (s) =>
              setState(() => _modeInscriptionIndividuel = s.first),
        ),
        const SizedBox(height: 16),
        if (_modeInscriptionIndividuel) ...[
          TextField(
            controller: _nomIndividuelCtrl,
            decoration: const InputDecoration(
              labelText: 'Votre nom',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
        ],
        TextField(
          controller: _emailIndividuelCtrl,
          keyboardType: TextInputType.emailAddress,
          decoration: const InputDecoration(
            labelText: 'Courriel',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _motDePasseIndividuelCtrl,
          obscureText: true,
          decoration: const InputDecoration(
            labelText: 'Mot de passe',
            border: OutlineInputBorder(),
          ),
        ),
        _caseResterConnecte(),
        if (_individuelErreur != null) ...[
          const SizedBox(height: 12),
          Text(_individuelErreur!, style: const TextStyle(color: Colors.red)),
        ],
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: _individuelEnCours ? null : _soumettreIndividuel,
            style: FilledButton.styleFrom(padding: const EdgeInsets.all(16)),
            child: _individuelEnCours
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(
                    _modeInscriptionIndividuel
                        ? 'Créer mon compte'
                        : 'Se connecter',
                  ),
          ),
        ),
        if (!_modeInscriptionIndividuel)
          TextButton(
            onPressed: () async {
              if (_emailIndividuelCtrl.text.trim().isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Entrez votre courriel ci-dessus d\'abord.'),
                  ),
                );
                return;
              }
              final email = _emailIndividuelCtrl.text.trim();
              await AppSession.reinitialiserMotDePasse(email);
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    'Courriel de réinitialisation envoyé si ce compte existe.',
                  ),
                ),
              );
            },
            child: const Text('Mot de passe oublié ?'),
          ),
      ],
    );
  }
}
