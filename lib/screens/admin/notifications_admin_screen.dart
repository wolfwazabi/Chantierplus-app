import 'package:flutter/material.dart';

import '../../services/notifications_push.dart';

/// Admin > Notifications : les catégories reçues sur le téléphone (chacune activable ou
/// fermée). Ces choix suivent l'admin sur tous ses appareils.
///
/// Le téléphone demande la permission à la première ouverture de l'app par un admin. Si
/// elle a été refusée, un bandeau le dit et ouvre les réglages du téléphone ; activer une
/// catégorie le propose aussi. Au retour des réglages, l'écran se met à jour.
class NotificationsAdminScreen extends StatefulWidget {
  /// Lecture et écriture des préférences (remplaçables dans les tests).
  final SourcePreferencesNotifications source;

  /// La permission du téléphone : lire, demander (et enregistrer le jeton), ouvrir les
  /// réglages (remplaçables dans les tests).
  final Future<PermissionNotifications> Function() lirePermission;
  final Future<void> Function() demanderPermission;
  final Future<void> Function() ouvrirReglages;

  const NotificationsAdminScreen({
    super.key,
    this.source = const SourcePreferencesNotifications(),
    this.lirePermission = NotificationsPush.etatPermission,
    this.demanderPermission = NotificationsPush.activer,
    this.ouvrirReglages = NotificationsPush.ouvrirReglages,
  });

  @override
  State<NotificationsAdminScreen> createState() =>
      _NotificationsAdminScreenState();
}

class _NotificationsAdminScreenState extends State<NotificationsAdminScreen>
    with WidgetsBindingObserver {
  Map<String, bool>? _voulues;
  String? _erreur;
  PermissionNotifications _permission = PermissionNotifications.sansObjet;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _charger();
    _verifierPermission();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Retour des réglages du téléphone : la permission a peut-être changé.
  @override
  void didChangeAppLifecycleState(AppLifecycleState etat) {
    if (etat == AppLifecycleState.resumed) _verifierPermission();
  }

  /// Lit la permission ; jamais demandée : le téléphone pose la question. Permise : le
  /// jeton de ce téléphone est (ré)enregistré.
  Future<void> _verifierPermission() async {
    try {
      var p = await widget.lirePermission();
      if (p == PermissionNotifications.aDemander ||
          (p == PermissionNotifications.permises &&
              _permission == PermissionNotifications.bloquees)) {
        await widget.demanderPermission();
        p = await widget.lirePermission();
      }
      if (mounted) setState(() => _permission = p);
    } catch (_) {}
  }

  Future<void> _ouvrirReglages() async {
    try {
      await widget.ouvrirReglages();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Ouvrez Réglages > Chantier+ > Notifications dans le téléphone.',
          ),
        ),
      );
    }
  }

  /// Une catégorie activée alors que le téléphone bloque tout : proposer les réglages.
  Future<void> _proposerReglages() async {
    final ouvrir = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Notifications bloquées'),
        content: const Text(
          'Pour les recevoir, permettez les notifications de Chantier+ dans les '
          'réglages du téléphone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Plus tard'),
          ),
          FilledButton(
            key: const ValueKey('notif_dialogue_reglages'),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Ouvrir les réglages'),
          ),
        ],
      ),
    );
    if (ouvrir == true) await _ouvrirReglages();
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
      if (voulue &&
          _permission == PermissionNotifications.bloquees &&
          mounted) {
        await _proposerReglages();
      }
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
          if (_permission == PermissionNotifications.bloquees)
            Card(
              key: const ValueKey('notif_bloquees'),
              color: Theme.of(context).colorScheme.errorContainer,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.notifications_off_outlined),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Les notifications de Chantier+ sont bloquées dans les '
                            'réglages du téléphone : vous ne recevrez rien.',
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerRight,
                      child: FilledButton.icon(
                        key: const ValueKey('notif_ouvrir_reglages'),
                        onPressed: _ouvrirReglages,
                        icon: const Icon(Icons.settings_outlined),
                        label: const Text('Ouvrir les réglages'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          if (_permission == PermissionNotifications.bloquees)
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
