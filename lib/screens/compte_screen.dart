import 'package:flutter/material.dart';
import '../models/employee.dart';
import '../services/app_session.dart';

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
  int _mode = 0; // 0 = connexion compagnie, 1 = inscription compagnie, 2 = individuel

  final _numeroCtrl = TextEditingController();
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
  bool _individuelEnCours = false;
  String? _individuelErreur;

  Future<void> _seConnecter() async {
    final numero = _numeroCtrl.text.trim();
    final pin = _pinCtrl.text.trim();

    if (numero.isEmpty || pin.isEmpty) {
      setState(() => _erreur = 'Veuillez remplir les deux champs.');
      return;
    }

    setState(() {
      _enCours = true;
      _erreur = null;
    });

    final erreur = await AppSession.connecterAvecNumeroEtPin(numero, pin);

    if (erreur != null) {
      setState(() {
        _erreur = erreur;
        _enCours = false;
      });
      return;
    }

    _numeroCtrl.clear();
    _pinCtrl.clear();
    setState(() => _enCours = false);
  }

  Future<void> _seDeconnecter() async {
    await AppSession.deconnecter();
  }

  Future<void> _soumettreInscription() async {
    if (_nomEntrepriseCtrl.text.trim().isEmpty ||
        _nomLegalCtrl.text.trim().isEmpty ||
        _secteurChoisi == null ||
        _nomAdminCtrl.text.trim().isEmpty ||
        _pinAdminCtrl.text.trim().isEmpty ||
        _emailAdminCtrl.text.trim().isEmpty) {
      setState(() => _inscriptionErreur = 'Veuillez remplir tous les champs requis.');
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
        _inscriptionErreur = 'Erreur : $e';
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

    setState(() {
      _individuelErreur = erreur;
      _individuelEnCours = false;
    });
  }

  String _libelleRole(Employee employee) {
    if (employee.estIndividuel) return 'Compte individuel';
    if (employee.estProprietaire) return 'Propriétaire';
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
                  const CircleAvatar(
                    radius: 40,
                    backgroundColor: Colors.orange,
                    child: Icon(Icons.person, size: 40, color: Colors.white),
                  ),
                  const SizedBox(height: 16),
                  Text(employee.nom, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text(_libelleRole(employee), style: TextStyle(color: Colors.grey.shade600, fontSize: 15)),
                  if (employee.companyNom != null) ...[
                    const SizedBox(height: 2),
                    Text(employee.companyNom!, style: TextStyle(color: Colors.grey.shade500, fontSize: 13)),
                  ],
                  if (employee.estSuperAdmin) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.purple.shade50,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text('Super Admin', style: TextStyle(color: Colors.purple.shade700, fontSize: 12, fontWeight: FontWeight.w600)),
                    ),
                  ],
                  const SizedBox(height: 32),
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
                  Icon(Icons.construction, size: 56, color: Colors.orange.shade700),
                  const SizedBox(height: 16),
                  ToggleButtons(
                    isSelected: [_mode == 0, _mode == 1, _mode == 2],
                    onPressed: (index) => setState(() {
                      _mode = index;
                      _numeroAttribue = null;
                    }),
                    borderRadius: BorderRadius.circular(8),
                    children: const [
                      Padding(padding: EdgeInsets.symmetric(horizontal: 12, vertical: 10), child: Text('Se connecter')),
                      Padding(padding: EdgeInsets.symmetric(horizontal: 12, vertical: 10), child: Text('Inscrire compagnie')),
                      Padding(padding: EdgeInsets.symmetric(horizontal: 12, vertical: 10), child: Text('Particuliers')),
                    ],
                  ),
                  const SizedBox(height: 24),
                  if (_mode == 0)
                    _formulaireConnexion()
                  else if (_mode == 1)
                    _formulaireInscription()
                  else
                    _formulaireIndividuel(),
                ],
              ),
            ),
          ),
        );
      },
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
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
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
          decoration: const InputDecoration(labelText: 'Votre courriel (propriétaire)'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
          FilledButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await AppSession.demanderNumeroCompagnie(emailCtrl.text.trim());
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Si ce courriel est associé à une compagnie, vous recevrez un message.')),
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
              decoration: const InputDecoration(labelText: 'Numéro de compagnie'),
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
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
          FilledButton(
            onPressed: () async {
              final numero = numeroCtrl.text.trim();
              final email = emailCtrl.text.trim();
              Navigator.pop(ctx);
              await AppSession.demanderCodeReinitialisation(numero, email);
              if (!mounted) return;
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
                decoration: const InputDecoration(labelText: 'Code (6 chiffres)'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: nouveauPinCtrl,
                keyboardType: TextInputType.number,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Nouveau NIP'),
              ),
              if (erreurCode != null) ...[
                const SizedBox(height: 8),
                Text(erreurCode!, style: const TextStyle(color: Colors.red)),
              ],
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
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
                        content: Text('NIP réinitialisé avec succès. Vous pouvez vous connecter.'),
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
              Text('Votre numéro de compagnie : $_numeroAttribue', style: const TextStyle(fontWeight: FontWeight.bold)),
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
        const Text('Informations sur la compagnie', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        TextField(
          controller: _nomEntrepriseCtrl,
          decoration: const InputDecoration(labelText: 'Nom d\'entreprise', border: OutlineInputBorder()),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _nomLegalCtrl,
          decoration: const InputDecoration(labelText: 'Nom légal', border: OutlineInputBorder()),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          initialValue: _secteurChoisi,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Secteur / métier', border: OutlineInputBorder()),
          items: metiersQuebec.map((m) => DropdownMenuItem(value: m, child: Text(m))).toList(),
          onChanged: (v) => setState(() => _secteurChoisi = v),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _nombreEmployesCtrl,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Nombre d\'employés (approx.)', border: OutlineInputBorder()),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _telephoneCtrl,
          keyboardType: TextInputType.phone,
          decoration: const InputDecoration(labelText: 'Téléphone', border: OutlineInputBorder()),
        ),
        const SizedBox(height: 20),
        const Text('Votre compte administrateur (propriétaire)', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        TextField(
          controller: _nomAdminCtrl,
          decoration: const InputDecoration(labelText: 'Votre nom', border: OutlineInputBorder()),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _pinAdminCtrl,
          keyboardType: TextInputType.number,
          obscureText: true,
          decoration: const InputDecoration(labelText: 'Choisissez un NIP', border: OutlineInputBorder()),
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
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
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
          onSelectionChanged: (s) => setState(() => _modeInscriptionIndividuel = s.first),
        ),
        const SizedBox(height: 16),
        if (_modeInscriptionIndividuel) ...[
          TextField(
            controller: _nomIndividuelCtrl,
            decoration: const InputDecoration(labelText: 'Votre nom', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
        ],
        TextField(
          controller: _emailIndividuelCtrl,
          keyboardType: TextInputType.emailAddress,
          decoration: const InputDecoration(labelText: 'Courriel', border: OutlineInputBorder()),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _motDePasseIndividuelCtrl,
          obscureText: true,
          decoration: const InputDecoration(labelText: 'Mot de passe', border: OutlineInputBorder()),
        ),
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
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : Text(_modeInscriptionIndividuel ? 'Créer mon compte' : 'Se connecter'),
          ),
        ),
        if (!_modeInscriptionIndividuel)
          TextButton(
            onPressed: () async {
              if (_emailIndividuelCtrl.text.trim().isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Entrez votre courriel ci-dessus d\'abord.')),
                );
                return;
              }
              final email = _emailIndividuelCtrl.text.trim();
              await AppSession.reinitialiserMotDePasse(email);
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Courriel de réinitialisation envoyé si ce compte existe.')),
              );
            },
            child: const Text('Mot de passe oublié ?'),
          ),
      ],
    );
  }
}