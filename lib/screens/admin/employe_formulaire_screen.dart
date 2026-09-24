import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../services/app_session.dart';

class EmployeFormulaireScreen extends StatefulWidget {
  final String? docId;
  final Map<String, dynamic>? donneesExistantes;

  const EmployeFormulaireScreen({super.key, this.docId, this.donneesExistantes});

  @override
  State<EmployeFormulaireScreen> createState() => _EmployeFormulaireScreenState();
}

class _EmployeFormulaireScreenState extends State<EmployeFormulaireScreen> {
  late final TextEditingController _nomCtrl;
  late final TextEditingController _pinCtrl;
  String _role = 'employe';
  bool _enCours = false;
  String? _erreur;

  bool get _modeEdition => widget.docId != null;
  bool get _estProprietaireExistant => widget.donneesExistantes?['estProprietaire'] == true;

  @override
  void initState() {
    super.initState();
    final d = widget.donneesExistantes;
    _nomCtrl = TextEditingController(text: d?['nom'] ?? '');
    _pinCtrl = TextEditingController(text: d?['pin'] ?? '');
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

    if (nom.isEmpty || pin.isEmpty) {
      setState(() => _erreur = 'Veuillez remplir tous les champs.');
      return;
    }

    final companyId = AppSession.current?.companyId;
    if (companyId == null) {
      setState(() => _erreur = 'Aucune compagnie associée à votre compte.');
      return;
    }

    setState(() {
      _enCours = true;
      _erreur = null;
    });

    final data = {
      'nom': nom,
      'pin': pin,
      'role': _estProprietaireExistant ? 'admin' : _role,
    };

    try {
      if (_modeEdition) {
        await FirebaseFirestore.instance.collection('employees').doc(widget.docId).update(data);
      } else {
        final existant = await FirebaseFirestore.instance
            .collection('employees')
            .where('companyId', isEqualTo: companyId)
            .where('pin', isEqualTo: pin)
            .limit(1)
            .get();
        if (existant.docs.isNotEmpty) {
          setState(() {
            _erreur = 'Ce NIP est déjà utilisé par un autre employé de votre compagnie.';
            _enCours = false;
          });
          return;
        }
        await FirebaseFirestore.instance.collection('employees').add({
          ...data,
          'companyId': companyId,
          'estProprietaire': false,
        });
      }
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      setState(() {
        _erreur = 'Erreur : $e';
        _enCours = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_modeEdition ? 'Modifier l\'employé' : 'Ajouter un employé')),
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
              decoration: const InputDecoration(
                labelText: 'NIP',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.lock),
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
                style: FilledButton.styleFrom(padding: const EdgeInsets.all(16)),
                child: _enCours
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : Text(_modeEdition ? 'Enregistrer les modifications' : 'Créer l\'employé'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}