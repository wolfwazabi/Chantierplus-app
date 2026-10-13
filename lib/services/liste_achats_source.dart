import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/liste_achats.dart';
import '../models/materiel_general.dart';

/// Accès aux données de la Liste d'achats (admin). Une interface pour que
/// l'écran se teste sans Firebase.
abstract class SourceListeAchats {
  /// Tous les articles de la compagnie, en direct.
  Stream<List<ArticleAchat>> articles(String companyId);

  /// Marque un article acheté, ou le remet à acheter. La demande de Général d'où il
  /// vient suit : « faite » quand l'article est acheté, de nouveau en cours sinon.
  Future<void> definirAchete(
    ArticleAchat article,
    bool achete, {
    required String employeId,
  });

  /// Retire l'article de la liste ; la demande d'origine redevient ordinaire.
  Future<void> supprimer(ArticleAchat article, {required String employeId});
}

class SourceListeAchatsFirestore implements SourceListeAchats {
  FirebaseFirestore get _db => FirebaseFirestore.instance;

  @override
  Stream<List<ArticleAchat>> articles(String companyId) => _db
      .collection('liste_achats')
      .where('companyId', isEqualTo: companyId)
      .snapshots()
      .map(
        (s) => [for (final d in s.docs) ArticleAchat.fromMap(d.id, d.data())],
      );

  /// Met à jour la demande d'origine sans faire échouer l'opération principale :
  /// elle a pu être supprimée entre-temps.
  Future<void> _majOrigine(
    ArticleAchat article,
    Map<String, dynamic> donnees,
  ) async {
    if (article.origineId.isEmpty) return;
    try {
      await _db
          .collection('chantier_materiel')
          .doc(article.origineId)
          .update(donnees);
    } catch (_) {
      // Demande disparue : rien à mettre à jour.
    }
  }

  @override
  Future<void> definirAchete(
    ArticleAchat article,
    bool achete, {
    required String employeId,
  }) async {
    await _db.collection('liste_achats').doc(article.id).update({
      'complete': achete,
      'dateComplete': achete
          ? FieldValue.serverTimestamp()
          : FieldValue.delete(),
    });
    await _majOrigine(
      article,
      donneesCompletion(
        complete: achete,
        general: true,
        modifieParId: employeId,
      ),
    );
  }

  @override
  Future<void> supprimer(
    ArticleAchat article, {
    required String employeId,
  }) async {
    await _db.collection('liste_achats').doc(article.id).delete();
    await _majOrigine(article, donneesRetirerTransfert(employeId));
  }
}
