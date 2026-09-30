import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../models/chantier.dart';
import '../../services/app_session.dart';
import '../documents/documents_chantier.dart';
import '../../widgets/recherche_chantier.dart';

/// Dépôt et suppression des documents de chantier (plans, devis, photos…).
/// Réservé aux admins, dont le super-admin de la compagnie.
class DocumentsAdminScreen extends StatefulWidget {
  const DocumentsAdminScreen({super.key});

  @override
  State<DocumentsAdminScreen> createState() => _DocumentsAdminScreenState();
}

class _DocumentsAdminScreenState extends State<DocumentsAdminScreen> {
  String? _chantierId;

  @override
  Widget build(BuildContext context) {
    final companyId = AppSession.current?.companyId;

    return Scaffold(
      appBar: AppBar(title: const Text('Documents des chantiers')),
      body: companyId == null
          ? const Center(child: Text('Aucune compagnie associée.'))
          : StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('chantiers')
                  .where('companyId', isEqualTo: companyId)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return const Center(
                    child: Text('Impossible de charger les chantiers.'),
                  );
                }
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final chantiers =
                    snapshot.data!.docs
                        .map((d) => Chantier.fromFirestore(d.id, d.data()))
                        .where((c) => !c.archive)
                        .toList()
                      ..sort((a, b) => a.nom.compareTo(b.nom));

                if (chantiers.isEmpty) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'Aucun chantier. Créez-en un dans Admin → Gérer les chantiers.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  );
                }
                if (_chantierId == null ||
                    !chantiers.any((c) => c.id == _chantierId)) {
                  _chantierId = chantiers.first.id;
                }

                return Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                      child: Row(
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              // La clé suit la valeur : la liste affiche aussi
                              // un chantier choisi par la recherche « … ».
                              key: ValueKey('chantier_$_chantierId'),
                              initialValue: _chantierId,
                              isExpanded: true,
                              decoration: const InputDecoration(
                                labelText: 'Chantier',
                                border: OutlineInputBorder(),
                                prefixIcon: Icon(Icons.construction),
                              ),
                              items: chantiers
                                  .map(
                                    (c) => DropdownMenuItem(
                                      value: c.id,
                                      child: Text(
                                        c.nom,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (id) =>
                                  setState(() => _chantierId = id),
                            ),
                          ),
                          const SizedBox(width: 6),
                          BoutonRechercheChantier(
                            chantiers: chantiers,
                            onChoisi: (c) => setState(() => _chantierId = c.id),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: DocumentsChantier(
                        key: ValueKey('docs_admin_$_chantierId'),
                        companyId: companyId,
                        chantierId: _chantierId!,
                        peutGerer: true,
                      ),
                    ),
                  ],
                );
              },
            ),
    );
  }
}
