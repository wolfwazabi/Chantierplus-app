import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';

import 'fichier_temporaire.dart';

/// Photos de chantier.
///
/// Une photo prise avec l'app n'est PAS enregistrée dans la pellicule du
/// téléphone : le sélecteur la garde dans un dossier temporaire de l'app, elle
/// part vers le serveur, puis la copie temporaire est supprimée. Rien ne
/// s'ajoute donc aux photos personnelles ni à l'espace utilisé.
class Photos {
  static final ImagePicker _selecteur = ImagePicker();

  // Réduction : assez pour lire un plan ou un défaut, sans envoyer 12 Mpx.
  static const int _cote = 2400;
  static const int _qualite = 80;

  /// Prend une photo avec l'appareil photo (jamais copiée dans la pellicule).
  static Future<XFile?> prendre() => _selecteur.pickImage(
    source: ImageSource.camera,
    maxWidth: _cote.toDouble(),
    maxHeight: _cote.toDouble(),
    imageQuality: _qualite,
  );

  /// Choisit une photo déjà dans la galerie.
  static Future<XFile?> choisir() => _selecteur.pickImage(
    source: ImageSource.gallery,
    maxWidth: _cote.toDouble(),
    maxHeight: _cote.toDouble(),
    imageQuality: _qualite,
  );

  static Future<List<XFile>> choisirPlusieurs() => _selecteur.pickMultiImage(
    maxWidth: _cote.toDouble(),
    maxHeight: _cote.toDouble(),
    imageQuality: _qualite,
  );

  /// Supprime la copie temporaire d'une photo une fois envoyée (ou abandonnée).
  ///
  /// Seulement sur iPhone et Android, où le sélecteur travaille sur une COPIE
  /// nommée « image_picker_… » : sur ordinateur, il renvoie le fichier original
  /// de l'utilisateur, qu'il ne faut jamais supprimer.
  static Future<void> supprimerTemporaire(XFile photo) async {
    if (!peutSupprimerCopie(photo.path, defaultTargetPlatform, kIsWeb)) return;
    await supprimerFichier(photo.path);
  }

  @visibleForTesting
  static bool peutSupprimerCopie(
    String chemin,
    TargetPlatform plateforme,
    bool web,
  ) {
    if (web) return false;
    if (plateforme != TargetPlatform.android &&
        plateforme != TargetPlatform.iOS) {
      return false;
    }
    final nom = chemin.replaceAll(r'\', '/').split('/').last;
    return nom.startsWith('image_picker');
  }
}
