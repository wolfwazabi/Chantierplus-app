import 'package:flutter/material.dart';

import '../../models/ancien_employe.dart';
import '../../models/nip_employe.dart';
import '../../services/app_session.dart';
import '../../services/fiches_employes.dart';
import '../../services/fonctions.dart';
import 'anciens_employes_screen.dart';
import 'employe_formulaire_screen.dart';
import '../../widgets/actualiser.dart';

class EmployesListeScreen extends StatelessWidget {
  /// Tests : remplacent la lecture des fiches et l'appel aux fonctions.
  @visibleForTesting
  final FluxFiches? flux;
  @visibleForTesting
  final AppelFonction? appelerFonction;

  const EmployesListeScreen({super.key, this.flux, this.appelerFonction});

  String _libelleRole(Map<String, dynamic> data) {
    if (data['estProprietaire'] == true) return 'Super-admin';
    switch (data['role']) {
      case 'admin':
        return 'Administrateur';
      case 'plus':
        return 'Contremaître';
      default:
        return 'Employé';
    }
  }

  Color _couleurRole(Map<String, dynamic> data) {
    if (data['estProprietaire'] == true) return Colors.purple.shade600;
    switch (data['role']) {
      case 'admin':
        return Colors.red.shade600;
      case 'plus':
        return Colors.blue.shade600;
      default:
        return Colors.grey.shade600;
    }
  }

  AppelFonction get _appeler => appelerFonction ?? Fonctions.appeler;

  /// Retire l'accès : plus aucune connexion et NIP détruit, mais nom et courriel restent
  /// 24 mois dans « Anciens employés » (pour le réactiver), puis sont supprimés.
  Future<void> _confirmerRetrait(
    BuildContext context,
    String docId,
    String nom,
  ) async {
    var motif = 'non-precise';
    final confirme = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('Retirer cet employé ?'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$nom sera immédiatement déconnecté et ne pourra plus se '
                  'reconnecter. Son NIP est détruit.',
                ),
                const SizedBox(height: 12),
                const Text(
                  'Pour pouvoir le réactiver plus tard (employé saisonnier), '
                  'son nom et son courriel sont gardés 24 mois dans « Anciens '
                  'employés », puis supprimés automatiquement. Vous pouvez '
                  'supprimer sa fiche tout de suite à cet endroit. Les feuilles '
                  'de temps déjà enregistrées restent dans les registres de la '
                  'compagnie.',
                  style: TextStyle(fontSize: 13),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  key: const ValueKey('employe_motif_retrait'),
                  isExpanded: true,
                  initialValue: motif,
                  decoration: const InputDecoration(
                    labelText: 'Motif du départ (facultatif)',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    for (final e in motifsRetrait.entries)
                      DropdownMenuItem(value: e.key, child: Text(e.value)),
                  ],
                  onChanged: (v) => setState(() => motif = v ?? motif),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Annuler'),
            ),
            TextButton(
              key: const ValueKey('employe_confirmer_retrait'),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Retirer', style: TextStyle(color: Colors.red)),
            ),
          ],
        ),
      ),
    );
    if (confirme != true || !context.mounted) return;
    final messages = ScaffoldMessenger.of(context);
    // Protection du super-admin, nettoyage des accès, dates : côté serveur.
    try {
      await _appeler('retirerAccesEmploye', {
        'employeeId': docId,
        'motif': motif,
      });
      messages.showSnackBar(
        SnackBar(
          content: Text(
            '$nom n\'a plus accès. Fiche gardée dans « Anciens employés ».',
          ),
        ),
      );
    } catch (e) {
      messages.showSnackBar(
        SnackBar(
          content: Text(Fonctions.message(e, 'Erreur lors du retrait.')),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final companyId = AppSession.current?.companyId;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Gestion des employés'),
        actions: [
          IconButton(
            key: const ValueKey('employes_anciens'),
            tooltip: 'Anciens employés',
            icon: const Icon(Icons.history),
            onPressed: companyId == null
                ? null
                : () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => AnciensEmployesScreen(
                        flux: flux,
                        appelerFonction: appelerFonction,
                      ),
                    ),
                  ),
          ),
        ],
      ),
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
                // Les anciens employés (actif == false) ont leur propre écran. Le
                // filtre se fait ici : Firestore ne sait pas chercher un champ absent.
                final docs =
                    snapshot.data!.where((f) => employeActif(f.value)).toList()
                      ..sort(
                        (a, b) => ((a.value['nom'] ?? '') as String).compareTo(
                          (b.value['nom'] ?? '') as String,
                        ),
                      );

                if (docs.isEmpty) {
                  return const Center(
                    child: Text('Aucun employé pour l\'instant.'),
                  );
                }
                return ListView.builder(
                  itemCount: docs.length,
                  itemBuilder: (context, index) {
                    final id = docs[index].key;
                    final data = docs[index].value;
                    final nom = (data['nom'] ?? '') as String;
                    final estProprietaire = data['estProprietaire'] == true;
                    final estMoi = id == AppSession.current?.id;
                    // Seul le super-admin de la compagnie gère les autres admins.
                    final gerable =
                        estMoi ||
                        data['role'] != 'admin' ||
                        AppSession.estProprietaire;

                    return ListTile(
                      key: ValueKey('employe_$id'),
                      leading: CircleAvatar(
                        backgroundColor: _couleurRole(data),
                        child: Text(
                          nom.isNotEmpty ? nom[0].toUpperCase() : '?',
                          style: const TextStyle(color: Colors.white),
                        ),
                      ),
                      title: Text(nom),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(_libelleRole(data)),
                          Text(
                            data['courriel'] ?? '',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade600,
                            ),
                          ),
                          // Pas encore de NIP : lien d'invitation non utilisé.
                          if (!nipCree(data))
                            const Text(
                              'Invitation en attente : NIP pas encore créé',
                              style: TextStyle(
                                fontSize: 12,
                                color: Color(0xFF9A5B00),
                              ),
                            ),
                        ],
                      ),
                      trailing: !gerable
                          ? null
                          : PopupMenuButton<String>(
                              key: ValueKey('employe_menu_$id'),
                              onSelected: (valeur) {
                                if (valeur == 'modifier') {
                                  Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) => EmployeFormulaireScreen(
                                        docId: id,
                                        donneesExistantes: data,
                                      ),
                                    ),
                                  );
                                } else if (valeur == 'supprimer') {
                                  _confirmerRetrait(context, id, nom);
                                }
                              },
                              itemBuilder: (ctx) => [
                                const PopupMenuItem(
                                  value: 'modifier',
                                  child: Text('Modifier'),
                                ),
                                if (!estProprietaire && !estMoi)
                                  const PopupMenuItem(
                                    value: 'supprimer',
                                    child: Text('Retirer'),
                                  ),
                              ],
                            ),
                    );
                  },
                );
              },
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const EmployeFormulaireScreen()),
          );
        },
        icon: const Icon(Icons.person_add),
        label: const Text('Ajouter'),
      ),
    );
  }
}
