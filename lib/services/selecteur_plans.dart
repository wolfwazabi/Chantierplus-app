import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';

import 'photos.dart';

/// Limites de l'envoi d'un plan : les mêmes que celles du serveur (functions/src/lecture_plans.js).
const int maxFichiersPlan = 5;
const int tailleMaxFichierPlan = 8 * 1024 * 1024;
const int tailleMaxTotalPlan = 12 * 1024 * 1024;
const List<String> extensionsPlan = ['pdf', 'jpg', 'jpeg', 'png', 'webp'];

/// Un fichier choisi pour la lecture d'un plan, déjà en mémoire.
class PlanFichier {
  final String nom;
  final Uint8List octets;
  const PlanFichier(this.nom, this.octets);

  int get taille => octets.length;
}

/// Ce que l'utilisateur a choisi, et les fichiers refusés avec la raison.
class ChoixPlans {
  final List<PlanFichier> fichiers;
  final List<String> refus;
  const ChoixPlans([this.fichiers = const [], this.refus = const []]);
}

String formaterTaillePlan(int octets) {
  if (octets < 1024) return '$octets o';
  if (octets < 1024 * 1024) return '${(octets / 1024).toStringAsFixed(0)} Ko';
  return '${(octets / (1024 * 1024)).toStringAsFixed(1)} Mo';
}

String _extension(String nom) {
  final i = nom.lastIndexOf('.');
  return i < 0 ? '' : nom.substring(i + 1).toLowerCase();
}

/// Pourquoi un fichier est refusé avant l'envoi (null : accepté). Le serveur vérifie de nouveau,
/// d'après le contenu réel du fichier.
String? raisonRefusPlan(String nom, int taille) {
  if (!extensionsPlan.contains(_extension(nom))) {
    return 'format non accepté (PDF, JPEG, PNG ou WebP seulement)';
  }
  if (taille <= 0) return 'fichier vide';
  if (taille > tailleMaxFichierPlan) {
    return 'trop volumineux (${formaterTaillePlan(taille)}, maximum '
        '${formaterTaillePlan(tailleMaxFichierPlan)})';
  }
  return null;
}

/// Choix des fichiers d'un plan : PDF ou images du téléphone, galerie, appareil photo.
/// Remplaçable dans les tests.
abstract class SelecteurPlans {
  Future<ChoixPlans> choisirFichiers();
  Future<ChoixPlans> prendrePhoto();
  Future<ChoixPlans> choisirPhotos();
}

class SelecteurPlansReel implements SelecteurPlans {
  const SelecteurPlansReel();

  @override
  Future<ChoixPlans> choisirFichiers() async {
    final choisis = await FilePicker.pickFiles(
      dialogTitle: 'Choisir un plan',
      type: FileType.custom,
      allowedExtensions: extensionsPlan,
    );
    final fichiers = <PlanFichier>[];
    final refus = <String>[];
    for (final f in choisis) {
      final raison = raisonRefusPlan(f.name, await f.length() ?? 0);
      if (raison != null) {
        refus.add('${f.name} : $raison');
        continue;
      }
      final octets = await f.readAsBytes();
      // La taille lue peut différer de celle annoncée : on revérifie.
      final encore = raisonRefusPlan(f.name, octets.length);
      if (encore != null) {
        refus.add('${f.name} : $encore');
      } else {
        fichiers.add(PlanFichier(f.name, octets));
      }
    }
    return ChoixPlans(fichiers, refus);
  }

  @override
  Future<ChoixPlans> prendrePhoto() async {
    final photo = await Photos.prendre();
    return photo == null ? const ChoixPlans() : _depuisPhotos([photo]);
  }

  @override
  Future<ChoixPlans> choisirPhotos() async {
    final photos = await Photos.choisirPlusieurs(limite: maxFichiersPlan);
    return _depuisPhotos(photos);
  }

  /// Les photos sont lues en mémoire, puis leur copie temporaire est supprimée.
  Future<ChoixPlans> _depuisPhotos(List<XFile> photos) async {
    final fichiers = <PlanFichier>[];
    final refus = <String>[];
    for (final p in photos) {
      try {
        final octets = await p.readAsBytes();
        final nom = p.name.isEmpty ? 'photo.jpg' : p.name;
        final raison = raisonRefusPlan(nom, octets.length);
        if (raison != null) {
          refus.add('$nom : $raison');
        } else {
          fichiers.add(PlanFichier(nom, octets));
        }
      } catch (e) {
        debugPrint('Photo de plan illisible : $e');
        refus.add('${p.name} : photo illisible');
      } finally {
        await Photos.supprimerTemporaire(p);
      }
    }
    return ChoixPlans(fichiers, refus);
  }
}
