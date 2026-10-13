import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:construction_app/services/selecteur_plans.dart';

/// La lecture du garage telle que le serveur la renvoie (fixture partagée avec les tests du
/// serveur : tests/rules/lecture_plans.unit.test.mjs). Copie neuve à chaque appel.
Map<String, dynamic> lectureGarage() => jsonDecode(
  File('test/charpente/lecture_plan_garage.json').readAsStringSync(),
) as Map<String, dynamic>;

/// Même contenu, avec des cartes `Map<Object?, Object?>` comme celles de la plateforme.
Map<String, dynamic> enCartesGeneriques(Map<String, dynamic> j) {
  Object? copie(Object? v) {
    if (v is Map) {
      return <Object?, Object?>{
        for (final e in v.entries) e.key: copie(e.value),
      };
    }
    if (v is List) return <Object?>[for (final e in v) copie(e)];
    return v;
  }

  return {for (final e in j.entries) e.key: copie(e.value)};
}

/// Un fichier de plan de [octets] octets (le contenu n'a pas d'importance pour l'écran).
PlanFichier planFaux(String nom, {int octets = 1000}) =>
    PlanFichier(nom, Uint8List(octets));

/// Choix de fichiers prévus d'avance pour chaque bouton.
class SelecteurPlansFaux implements SelecteurPlans {
  final List<ChoixPlans> fichiers;
  final List<ChoixPlans> photos;
  final List<ChoixPlans> galerie;

  /// Si non nul, chaque bouton lance cette erreur.
  Object? erreur;

  int appelsFichiers = 0;
  int appelsPhoto = 0;
  int appelsGalerie = 0;

  SelecteurPlansFaux({
    List<ChoixPlans>? fichiers,
    List<ChoixPlans>? photos,
    List<ChoixPlans>? galerie,
  }) : fichiers = fichiers ?? [],
       photos = photos ?? [],
       galerie = galerie ?? [];

  ChoixPlans _suivant(List<ChoixPlans> file) {
    final e = erreur;
    if (e != null) throw e;
    return file.isEmpty ? const ChoixPlans() : file.removeAt(0);
  }

  @override
  Future<ChoixPlans> choisirFichiers() async {
    appelsFichiers++;
    return _suivant(fichiers);
  }

  @override
  Future<ChoixPlans> prendrePhoto() async {
    appelsPhoto++;
    return _suivant(photos);
  }

  @override
  Future<ChoixPlans> choisirPhotos() async {
    appelsGalerie++;
    return _suivant(galerie);
  }
}
