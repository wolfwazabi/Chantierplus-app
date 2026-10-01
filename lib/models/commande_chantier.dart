import 'package:cloud_firestore/cloud_firestore.dart';

import '../charpente/commande.dart';

/// Commande de matériaux enregistrée pour un chantier (collection
/// chantier_commandes) : la liste d'achat du calcul de charpente et son suivi.
class CommandeChantier {
  final String id;
  final String nom;

  /// brouillon → commandee → recue.
  final String statut;
  final List<LigneCommande> lignes;

  /// Projet de calcul (JSON), pour rouvrir le calcul.
  final String? projet;
  final String notes;
  final String fournisseur;
  final String ajouteParNom;
  final DateTime? dateAjout;
  final DateTime? dateCommande;

  const CommandeChantier({
    required this.id,
    required this.nom,
    required this.statut,
    required this.lignes,
    this.projet,
    this.notes = '',
    this.fournisseur = '',
    this.ajouteParNom = '',
    this.dateAjout,
    this.dateCommande,
  });

  static const statuts = ['brouillon', 'commandee', 'recue'];

  static String libelleStatut(String s) => switch (s) {
    'commandee' => 'Commandée',
    'recue' => 'Reçue',
    _ => 'Brouillon',
  };

  factory CommandeChantier.fromFirestore(String id, Map<String, dynamic> data) {
    final lignes = <LigneCommande>[];
    final brutes = data['lignes'];
    if (brutes is List) {
      for (final l in brutes) {
        try {
          lignes.add(LigneCommande.fromJson(l));
        } on FormatException {
          // Ligne illisible : ignorée plutôt que de bloquer toute la commande.
        }
      }
    }
    DateTime? date(Object? v) => v is Timestamp ? v.toDate() : null;
    final statut = data['statut'];
    return CommandeChantier(
      id: id,
      nom: data['nom'] is String ? data['nom'] : 'Commande',
      statut: statuts.contains(statut) ? statut : 'brouillon',
      lignes: lignes,
      projet: data['projet'] is String ? data['projet'] : null,
      notes: data['notes'] is String ? data['notes'] : '',
      fournisseur: data['fournisseur'] is String ? data['fournisseur'] : '',
      ajouteParNom: data['ajouteParNom'] is String ? data['ajouteParNom'] : '',
      dateAjout: date(data['dateAjout']),
      dateCommande: date(data['dateCommande']),
    );
  }

  Commande get commande => Commande(lignes);
}
