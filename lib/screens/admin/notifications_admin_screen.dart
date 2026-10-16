import 'package:flutter/material.dart';

import '../../services/notifications_push.dart';

/// Admin > Notifications : les catégories reçues sur le téléphone (chacune activable ou
/// fermée). Ces choix suivent l'admin sur tous ses appareils.
class NotificationsAdminScreen extends StatefulWidget {
  /// Lecture et écriture des préférences (remplaçables dans les tests).
  final SourcePreferencesNotifications source;

  const NotificationsAdminScreen({
    super.key,
    this.source = const SourcePreferencesNotifications(),
  });

  @override
  State<NotificationsAdminScreen> createState() =>
      _NotificationsAdminScreenState();
}

class _NotificationsAdminScreenState extends State<NotificationsAdminScreen> {
  Map<String, bool>? _voulues;
  String? _erreur;

  @override
  void initState() {
    super.initState();
    _charger();
  }

  Future<void> _charger() async {
    try {
      final v = await widget.source.lire();
      if (mounted) setState(() => _voulues = v);
    } catch (_) {
      if (mounted) {
        setState(() => _erreur = 'Impossible de charger vos choix. Réessayez.');
      }
    }
  }

  Future<void> _changer(String cle, bool voulue) async {
    final avant = _voulues![cle]!;
    setState(() => _voulues = {..._voulues!, cle: voulue});
    try {
      await widget.source.ecrire(cle, voulue);
    } catch (_) {
      if (!mounted) return;
      setState(() => _voulues = {..._voulues!, cle: avant});
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Changement non enregistré. Vérifiez votre réseau.'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final voulues = _voulues;
    return Scaffold(
      appBar: AppBar(title: const Text('Notifications')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Recevez une notification sur votre téléphone quand quelque chose est entré. '
            'Vous n\'êtes jamais averti de ce que vous entrez vous-même.',
          ),
          const SizedBox(height: 12),
          if (_erreur != null)
            Text(
              _erreur!,
              key: const ValueKey('notif_erreur'),
              style: const TextStyle(color: Colors.red),
            )
          else if (voulues == null)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            )
          else
            for (final c in categoriesNotification)
              SwitchListTile(
                key: ValueKey('notif_${c.cle}'),
                secondary: Icon(c.icone),
                title: Text(c.nom),
                subtitle: Text(c.explication),
                value: voulues[c.cle] ?? true,
                onChanged: (v) => _changer(c.cle, v),
              ),
          const SizedBox(height: 12),
          Text(
            'Si rien n\'arrive, vérifiez que les notifications de Chantier+ sont permises '
            'dans les réglages du téléphone.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
