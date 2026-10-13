import 'package:flutter/material.dart';

import '../../models/ancien_employe.dart';
import '../../services/app_session.dart';
import '../../services/fiches_employes.dart';
import '../../services/fonctions.dart';
import '../../widgets/lien_invitation.dart';
import '../../widgets/actualiser.dart';

/// Anciens employés : accès retiré, nom et courriel gardés 24 mois (loi 25) pour pouvoir
/// les réactiver (employés saisonniers). L'admin peut aussi supprimer une fiche tout de
/// suite (droit à l'effacement). Rien d'autre n'est conservé : pas de NIP, pas de note.
class AnciensEmployesScreen extends StatelessWidget {
  /// Tests : remplacent la lecture des fiches et l'appel aux fonctions.
  @visibleForTesting
  final FluxFiches? flux;
  @visibleForTesting
  final AppelFonction? appelerFonction;

  const AnciensEmployesScreen({super.key, this.flux, this.appelerFonction});

  AppelFonction get _appeler => appelerFonction ?? Fonctions.appeler;

  Future<void> _reactiver(BuildContext context, AncienEmploye e) async {
    final confirme = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Réactiver cet employé ?'),
        content: Text(
          '${e.nom} recevra un courriel à ${e.courriel} avec un lien pour '
          'créer un nouveau NIP. L\'ancien NIP n\'est pas conservé.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            key: const ValueKey('ancien_confirmer_reactivation'),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Réactiver'),
          ),
        ],
      ),
    );
    if (confirme != true || !context.mounted) return;
    final messages = ScaffoldMessenger.of(context);
    try {
      final r = await _appeler('reactiverEmploye', {'employeeId': e.id});
      if (!context.mounted) return;
      final lien = r['lienInvitation'];
      if (lien is String) {
        await afficherLienDeSecours(context, e.nom, lien);
      } else {
        messages.showSnackBar(
          SnackBar(
            content: Text(
              '${e.nom} est réactivé : courriel envoyé à ${e.courriel}.',
            ),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (err) {
      messages.showSnackBar(
        SnackBar(
          content: Text(
            Fonctions.message(err, 'Erreur lors de la réactivation.'),
          ),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _supprimer(BuildContext context, AncienEmploye e) async {
    final confirme = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Supprimer cette fiche ?'),
        content: Text(
          'Le nom et le courriel de ${e.nom} sont effacés tout de suite. '
          'C\'est irréversible : pour le réactiver, il faudra le recréer. Les '
          'feuilles de temps déjà enregistrées restent dans les registres de '
          'la compagnie.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler'),
          ),
          TextButton(
            key: const ValueKey('ancien_confirmer_suppression'),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Supprimer', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirme != true || !context.mounted) return;
    final messages = ScaffoldMessenger.of(context);
    try {
      await _appeler('supprimerEmploye', {'employeeId': e.id});
      messages.showSnackBar(const SnackBar(content: Text('Fiche supprimée.')));
    } catch (err) {
      messages.showSnackBar(
        SnackBar(
          content: Text(Fonctions.message(err, 'Suppression impossible.')),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final companyId = AppSession.current?.companyId;

    return Scaffold(
      appBar: AppBar(title: const Text('Anciens employés')),
      body: companyId == null
          ? const Center(child: Text('Aucune compagnie associée.'))
          : FluxActualisable<List<MapEntry<String, Map<String, dynamic>>>>(
              creerFlux: () => flux ?? fluxFichesEmployes(companyId),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(child: Text('Erreur : ${snapshot.error}'));
                }
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final anciens = anciensEmployes(snapshot.data!);
                return Column(
                  children: [
                    const Padding(
                      padding: EdgeInsets.fromLTRB(16, 12, 16, 8),
                      child: Text(
                        'Ces personnes n\'ont plus accès à l\'application. Leur nom '
                        'et leur courriel sont gardés 24 mois pour pouvoir les '
                        'réactiver, puis supprimés automatiquement.',
                        key: ValueKey('anciens_explication'),
                        style: TextStyle(fontSize: 13),
                      ),
                    ),
                    const Divider(height: 1),
                    Expanded(
                      child: anciens.isEmpty
                          ? messageActualisable(
                              const Text(
                                'Aucun ancien employé.',
                                key: ValueKey('anciens_vide'),
                              ),
                            )
                          : ListView.builder(
                              itemCount: anciens.length,
                              itemBuilder: (context, i) {
                                final e = anciens[i];
                                return ListTile(
                                  key: ValueKey('ancien_${e.id}'),
                                  isThreeLine: true,
                                  leading: CircleAvatar(
                                    backgroundColor: Colors.grey.shade500,
                                    child: Text(
                                      e.nom.isNotEmpty
                                          ? e.nom[0].toUpperCase()
                                          : '?',
                                      style: const TextStyle(
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                  title: Text(e.nom),
                                  subtitle: Text(
                                    '${e.courriel}\n'
                                    'Retiré le ${e.retireLeAffiche} • ${e.motif}\n'
                                    'Suppression automatique le ${e.supprimeApresLeAffiche}',
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                  trailing: PopupMenuButton<String>(
                                    key: ValueKey('ancien_menu_${e.id}'),
                                    onSelected: (v) {
                                      if (v == 'reactiver') {
                                        _reactiver(context, e);
                                      } else if (v == 'supprimer') {
                                        _supprimer(context, e);
                                      }
                                    },
                                    itemBuilder: (ctx) => const [
                                      PopupMenuItem(
                                        value: 'reactiver',
                                        child: Text('Réactiver'),
                                      ),
                                      PopupMenuItem(
                                        value: 'supprimer',
                                        child: Text(
                                          'Supprimer la fiche maintenant',
                                          style: TextStyle(color: Colors.red),
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                );
              },
            ),
    );
  }
}
