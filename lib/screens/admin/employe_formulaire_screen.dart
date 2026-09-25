import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/app_session.dart';
import '../../services/fonctions.dart';

/// Création / modification d'un employé.
///
/// L'admin ne choisit jamais le NIP : un NIP aléatoire est généré par le
/// serveur et envoyé par courriel à l'employé, qui peut ensuite le changer.
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
  static final _formatCourriel = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]{2,}$');

  late final TextEditingController _nomCtrl;
  late final TextEditingController _courrielCtrl;
  String _role = 'employe';
  bool _enCours = false;
  String? _erreur;

  bool get _modeEdition => widget.docId != null;
  bool get _estMoi =>
      widget.docId != null && widget.docId == AppSession.current?.id;

  /// Seul le super-admin de la compagnie nomme, modifie ou retire un admin.
  bool get _peutGererAdmins => AppSession.estProprietaire;
  bool get _estProprietaireExistant =>
      widget.donneesExistantes?['estProprietaire'] == true;

  @override
  void initState() {
    super.initState();
    final d = widget.donneesExistantes;
    _nomCtrl = TextEditingController(text: d?['nom'] ?? '');
    _courrielCtrl = TextEditingController(text: d?['courriel'] ?? '');
    _role = d?['role'] ?? 'employe';
  }

  @override
  void dispose() {
    _nomCtrl.dispose();
    _courrielCtrl.dispose();
    super.dispose();
  }

  Future<void> _enregistrer({bool envoyerNouveauNip = false}) async {
    final nom = _nomCtrl.text.trim();
    final courriel = _courrielCtrl.text.trim();

    if (nom.isEmpty || courriel.isEmpty) {
      setState(() => _erreur = 'Entrez le nom complet et le courriel.');
      return;
    }
    if (!_formatCourriel.hasMatch(courriel)) {
      setState(() => _erreur = 'Courriel invalide.');
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

    // Validation, unicité du courriel, génération et envoi du NIP, protection
    // du propriétaire : côté serveur (Cloud Function enregistrerEmploye).
    try {
      final resultat = await Fonctions.appeler('enregistrerEmploye', {
        'employeeId': widget.docId,
        'nom': nom,
        'courriel': courriel,
        'role': _estProprietaireExistant ? 'admin' : _role,
        'envoyerNouveauNip': envoyerNouveauNip,
      });
      if (!mounted) return;

      final nipTemporaire = resultat['nipTemporaire'] as String?;
      if (nipTemporaire != null) {
        await _afficherNipTemporaire(nom, nipTemporaire);
      } else if (resultat['courrielEnvoye'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Le NIP a été envoyé à $courriel.'),
            backgroundColor: Colors.green,
          ),
        );
      }
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      setState(() {
        _erreur = Fonctions.message(e, 'Erreur lors de l\'enregistrement.');
        _enCours = false;
      });
    }
  }

  /// Solution de repli tant que l'envoi de courriels n'est pas configuré :
  /// le NIP est montré une seule fois à l'admin, qui le transmet en personne.
  Future<void> _afficherNipTemporaire(String nom, String nip) {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Courriel non envoyé'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'L\'envoi de courriels n\'est pas encore disponible. '
              'Transmettez ce NIP à $nom en personne ; il ne sera plus affiché.',
            ),
            const SizedBox(height: 16),
            Center(
              child: SelectableText(
                nip,
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 6,
                ),
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'L\'employé pourra le changer dans l\'onglet Compte.',
              style: TextStyle(fontSize: 13),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Clipboard.setData(ClipboardData(text: nip)),
            child: const Text('Copier'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('C\'est noté'),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmerNouveauNip() async {
    final confirme = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Envoyer un nouveau NIP ?'),
        content: Text(
          'Un nouveau NIP sera envoyé à ${_courrielCtrl.text.trim()}. '
          'L\'ancien ne fonctionnera plus et l\'employé sera déconnecté de ses appareils.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Envoyer'),
          ),
        ],
      ),
    );
    if (confirme == true) await _enregistrer(envoyerNouveauNip: true);
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
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Nom complet',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.person),
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
            if (!_modeEdition) ...[
              const SizedBox(height: 8),
              const Text(
                'Un NIP aléatoire sera envoyé à ce courriel. L\'employé pourra le changer.',
                style: TextStyle(fontSize: 13),
              ),
            ],
            const SizedBox(height: 16),
            if (_estMoi && !_estProprietaireExistant)
              const Text(
                'Vous ne pouvez pas changer votre propre rôle.',
                style: TextStyle(fontSize: 13),
              )
            else if (_estProprietaireExistant)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.purple.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  'Cette personne est le super-admin de la compagnie : son rôle ne peut pas être changé.',
                  style: TextStyle(fontSize: 13),
                ),
              )
            else ...[
              const Text('Rôle', style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              SegmentedButton<String>(
                segments: [
                  const ButtonSegment(value: 'employe', label: Text('Employé')),
                  const ButtonSegment(
                    value: 'plus',
                    label: Text('Contremaître'),
                  ),
                  // Seul le super-admin de la compagnie nomme des admins.
                  if (_peutGererAdmins)
                    const ButtonSegment(value: 'admin', label: Text('Admin')),
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
                onPressed: _enCours ? null : () => _enregistrer(),
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
                            : 'Créer l\'employé et envoyer son NIP',
                      ),
              ),
            ),
            if (_modeEdition) ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _enCours ? null : _confirmerNouveauNip,
                  icon: const Icon(Icons.send_outlined),
                  label: const Text('Envoyer un nouveau NIP'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
