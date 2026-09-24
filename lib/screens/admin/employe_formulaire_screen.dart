import 'package:flutter/material.dart';
import 'package:cloud_functions/cloud_functions.dart';

import '../../services/app_session.dart';

class EmployeFormulaireScreen extends StatefulWidget {
  final String? docId;
  final Map<String, dynamic>? donneesExistantes;

  const EmployeFormulaireScreen({
    super.key,
    this.docId,
    this.donneesExistantes,
  });

  @override
  State<EmployeFormulaireScreen> createState() =>
      _EmployeFormulaireScreenState();
}

class _EmployeFormulaireScreenState extends State<EmployeFormulaireScreen> {
  late final TextEditingController _nomCtrl;
  late final TextEditingController _pinCtrl;
  String _role = 'employe';
  bool _enCours = false;
  String? _erreur;

  bool get _modeEdition => widget.docId != null;
  bool get _estProprietaireExistant =>
      widget.donneesExistantes?['estProprietaire'] == true;

  @override
  void initState() {
    super.initState();
    final d = widget.donneesExistantes;
    _nomCtrl = TextEditingController(text: d?['nom'] ?? '');
    // Le NIP n'est jamais relu : en modification, vide = inchangé.
    _pinCtrl = TextEditingController();
    _role = d?['role'] ?? 'employe';
  }

  @override
  void dispose() {
    _nomCtrl.dispose();
    _pinCtrl.dispose();
    super.dispose();
  }

  Future<void> _enregistrer() async {
    final nom = _nomCtrl.text.trim();
    final pin = _pinCtrl.text.trim();

    if (nom.isEmpty || (!_modeEdition && pin.isEmpty)) {
      setState(() => _erreur = 'Veuillez remplir tous les champs.');
      return;
    }
    if (pin.isNotEmpty && !RegExp(r'^\d{4,8}$').hasMatch(pin)) {
      setState(() => _erreur = 'Le NIP doit contenir de 4 à 8 chiffres.');
      return;
    }
    if (AppSession.current?.companyId == null) {
      setState(() => _erreur = 'Aucune compagnie associée à votre compte.');
      return;
    }

    setState(() {
      _enCours = true;
      _erreur = null;
    });

    // Validation, unicité du NIP, hachage et protection du propriétaire :
    // appliqués côté serveur (Cloud Function enregistrerEmploye).
    try {
      await FirebaseFunctions.instance.httpsCallable('enregistrerEmploye').call(
        {
          'employeeId': widget.docId,
          'nom': nom,
          'role': _estProprietaireExistant ? 'admin' : _role,
          if (pin.isNotEmpty) 'pin': pin,
        },
      );
      if (mounted) Navigator.of(context).pop();
    } on FirebaseFunctionsException catch (e) {
      setState(() {
        _erreur = e.message ?? 'Erreur lors de l\'enregistrement.';
        _enCours = false;
      });
    } catch (_) {
      setState(() {
        _erreur = 'Erreur lors de l\'enregistrement. Vérifiez votre réseau.';
        _enCours = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _modeEdition ? 'Modifier l\'employé' : 'Ajouter un employé',
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _nomCtrl,
              decoration: const InputDecoration(
                labelText: 'Nom complet',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.person),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _pinCtrl,
              keyboardType: TextInputType.number,
              obscureText: true,
              maxLength: 8,
              decoration: InputDecoration(
                labelText: _modeEdition
                    ? 'Nouveau NIP (laisser vide pour conserver)'
                    : 'NIP (4 à 8 chiffres)',
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(Icons.lock),
              ),
            ),
            const SizedBox(height: 16),
            if (_estProprietaireExistant)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.purple.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  'Cette personne est propriétaire de la compagnie : son rôle ne peut pas être changé.',
                  style: TextStyle(fontSize: 13),
                ),
              )
            else ...[
              const Text('Rôle', style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'employe', label: Text('Employé')),
                  ButtonSegment(value: 'plus', label: Text('Contremaître')),
                  ButtonSegment(value: 'admin', label: Text('Admin')),
                ],
                selected: {_role},
                onSelectionChanged: (nouveauSet) {
                  setState(() => _role = nouveauSet.first);
                },
              ),
            ],
            if (_erreur != null) ...[
              const SizedBox(height: 16),
              Text(_erreur!, style: const TextStyle(color: Colors.red)),
            ],
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _enCours ? null : _enregistrer,
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.all(16),
                ),
                child: _enCours
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Text(
                        _modeEdition
                            ? 'Enregistrer les modifications'
                            : 'Créer l\'employé',
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
