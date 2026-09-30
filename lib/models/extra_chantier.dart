import 'package:cloud_firestore/cloud_firestore.dart';

/// Extra d'un chantier : travaux supplémentaires effectués (description,
/// nombre d'hommes, temps, date, photo facultative).
class ExtraChantier {
  final String id;
  final String companyId;
  final String chantierId;
  final String description;
  final int nombreHommes;
  final double heures;

  /// Date des travaux, « AAAA-MM-JJ ».
  final String dateTravaux;
  final String? photoUrl;
  final String? cheminPhoto;
  final String ajouteParNom;
  final DateTime? dateAjout;

  const ExtraChantier({
    required this.id,
    required this.companyId,
    required this.chantierId,
    required this.description,
    required this.nombreHommes,
    required this.heures,
    required this.dateTravaux,
    this.photoUrl,
    this.cheminPhoto,
    this.ajouteParNom = '',
    this.dateAjout,
  });

  factory ExtraChantier.fromFirestore(String id, Map<String, dynamic> data) {
    final ajout = data['dateAjout'];
    return ExtraChantier(
      id: id,
      companyId: data['companyId'] ?? '',
      chantierId: data['chantierId'] ?? '',
      description: data['description'] ?? '',
      nombreHommes: (data['nombreHommes'] as num?)?.toInt() ?? 0,
      heures: (data['heures'] as num?)?.toDouble() ?? 0,
      dateTravaux: data['dateTravaux'] ?? '',
      photoUrl: data['photoUrl'] as String?,
      cheminPhoto: data['cheminPhoto'] as String?,
      ajouteParNom: data['ajouteParNom'] ?? '',
      dateAjout: ajout is Timestamp ? ajout.toDate() : null,
    );
  }

  /// Heures-homme : nombre d'hommes × temps de chacun.
  double get heuresHommes => nombreHommes * heures;
}

// ---------------------------------------------------------------------------
// Saisie (mêmes bornes que firestore.rules)
// ---------------------------------------------------------------------------

const int maxHommes = 500;
const double maxHeures = 1000;

/// Nombre d'hommes : entier de 1 à 500, sinon null.
int? lireNombreHommes(String texte) {
  final v = int.tryParse(texte.trim());
  return v != null && v >= 1 && v <= maxHommes ? v : null;
}

/// Temps en heures (virgule ou point) : plus de 0 et au plus 1000, arrondi au
/// centième ; sinon null.
double? lireHeures(String texte) {
  final v = double.tryParse(texte.trim().replaceAll(',', '.'));
  if (v == null || !v.isFinite || v > maxHeures) return null;
  final arrondi = (v * 100).round() / 100;
  // Après arrondi : 0.001 donnerait 0, que le serveur refuse.
  return arrondi > 0 ? arrondi : null;
}

/// « 3.5 », « 7 », « 3.25 » : sans zéros inutiles.
String formatNombre(double v) {
  final s = v.toStringAsFixed(2);
  return s.replaceFirst(RegExp(r'\.?0+$'), '');
}

String formatHommes(int n) => n > 1 ? '$n hommes' : '$n homme';

/// « 2 hommes × 3.5 h = 7 h-homme ».
String resumeTemps(int hommes, double heures) =>
    '${formatHommes(hommes)} × ${formatNombre(heures)} h = '
    '${formatNombre(hommes * heures)} h-homme';

String dateIso(DateTime d) {
  final a = d.year.toString().padLeft(4, '0');
  final m = d.month.toString().padLeft(2, '0');
  final j = d.day.toString().padLeft(2, '0');
  return '$a-$m-$j';
}

/// « 2026-10-01 » → « 01/10/2026 » ; texte inchangé s'il n'est pas une date.
String dateAffichee(String iso) {
  final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(iso);
  return m == null ? iso : '${m[3]}/${m[2]}/${m[1]}';
}

DateTime? lireDateIso(String iso) {
  final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(iso);
  if (m == null) return null;
  final d = DateTime(int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!));
  return dateIso(d) == iso ? d : null;
}
