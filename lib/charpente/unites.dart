import 'dart:math' as math;

/// Mesures du calcul de charpente.
///
/// Tout le moteur travaille en POUCES (double). Ce fichier lit ce que
/// l'utilisateur tape (10'6", 126, 3,2 m…) et l'affiche (10' 6 1/2", 3 200 mm).

const double mmParPouce = 25.4;
const double pouceMaxSaisie =
    12000; // 1000 pi : au-delà, c'est une faute de frappe.

double mmEnPouces(double mm) => mm / mmParPouce;
double poucesEnMm(double po) => po * mmParPouce;

const Map<String, String> _fractionsUnicode = {
  '½': ' 1/2',
  '¼': ' 1/4',
  '¾': ' 3/4',
  '⅛': ' 1/8',
  '⅜': ' 3/8',
  '⅝': ' 5/8',
  '⅞': ' 7/8',
  '⅙': ' 1/6',
  '⅓': ' 1/3',
  '⅔': ' 2/3',
};

String _normaliser(String texte) {
  var s = texte.trim().toLowerCase();
  _fractionsUnicode.forEach((k, v) => s = s.replaceAll(k, v));
  s = s
      .replaceAll(RegExp('[’‘′`´]'), "'")
      .replaceAll(RegExp('[”“″]'), '"')
      .replaceAll("''", '"')
      .replaceAll(',', '.');
  // Mots : « 10 pi 6 po », « 10 ft 6 in ».
  s = s
      .replaceAll(
        RegExp(r'(?<=[0-9/.\s])(pi|pieds?|ft|feet|foot)(?![a-z])\.?'),
        "'",
      )
      .replaceAll(
        RegExp(r'(?<=[0-9/.\s])(po|pouces?|in|inch(es)?)(?![a-z])\.?'),
        '"',
      );
  return s.replaceAll(RegExp(r'\s+'), ' ').trim();
}

/// Erreur de lecture, avec un message à afficher à l'utilisateur.
class MesureInvalide implements Exception {
  final String message;
  const MesureInvalide(this.message);
  @override
  String toString() => message;
}

/// « 6 », « 6.5 », « 1/2 », « 6 1/2 » (pouces entiers + fraction) → nombre.
double _lireNombreAvecFraction(String t) {
  final s = t.trim();
  if (s.isEmpty) return 0;
  final parts = s.split(RegExp(r'[\s-]+')).where((p) => p.isNotEmpty).toList();
  var total = 0.0;
  for (final p in parts) {
    if (p.contains('/')) {
      final f = p.split('/');
      if (f.length != 2) throw const MesureInvalide('Fraction invalide.');
      final a = double.tryParse(f[0]);
      final b = double.tryParse(f[1]);
      if (a == null || b == null || b == 0) {
        throw const MesureInvalide('Fraction invalide.');
      }
      total += a / b;
    } else {
      // Pas de notation scientifique (« 1e3 »), de « Infinity » ni de « NaN ».
      if (!RegExp(r'^(\d+(\.\d*)?|\.\d+)$').hasMatch(p)) {
        throw const MesureInvalide('Nombre invalide.');
      }
      total += double.parse(p);
    }
  }
  return total;
}

/// Lit une longueur impériale et retourne des POUCES.
///
/// Formes acceptées : `10'6"`, `10' 6 1/2"`, `10-6`, `10 6`, `126"`, `10.5'`,
/// `13'`, `13` (sans symbole : des PIEDS), `10 pi 6 po`.
/// Lance [MesureInvalide] si le texte n'est pas une mesure.
double lireLongueurImperiale(String texte) {
  final s = _normaliser(texte);
  if (s.isEmpty) throw const MesureInvalide('Entrez une mesure.');
  if (s.startsWith('-')) {
    throw const MesureInvalide('La mesure doit être positive.');
  }
  double pouces;

  final iPied = s.indexOf("'");
  if (iPied >= 0) {
    final pieds = s.substring(0, iPied).trim();
    var reste = s.substring(iPied + 1).trim();
    if (reste.contains("'")) {
      throw const MesureInvalide('Un seul symbole pi (\') permis.');
    }
    if (reste.endsWith('"')) {
      reste = reste.substring(0, reste.length - 1).trim();
    }
    if (reste.contains('"')) {
      throw const MesureInvalide('Symbole po (") mal placé.');
    }
    if (pieds.isEmpty) {
      throw const MesureInvalide('Nombre de pieds manquant avant \'.');
    }
    final p = _lireNombreAvecFraction(pieds);
    pouces = p * 12 + (reste.isEmpty ? 0 : _lireNombreAvecFraction(reste));
  } else if (s.contains('"')) {
    if (!s.endsWith('"') || s.indexOf('"') != s.length - 1) {
      throw const MesureInvalide('Symbole po (") mal placé.');
    }
    pouces = _lireNombreAvecFraction(s.substring(0, s.length - 1));
  } else {
    // Sans symbole : « 13 » = 13 pi ; « 10-6 » ou « 10 6 » = 10 pi 6 po.
    final jetons = s
        .split(RegExp(r'[\s-]+'))
        .where((p) => p.isNotEmpty)
        .toList();
    if (jetons.any((j) => j.contains('/')) && jetons.length <= 2) {
      throw const MesureInvalide(
        'Précisez les unités avec \' (pieds) ou " (pouces).',
      );
    }
    if (jetons.length == 1) {
      pouces = _lireNombreAvecFraction(jetons[0]) * 12;
    } else if (jetons.length == 2) {
      pouces =
          _lireNombreAvecFraction(jetons[0]) * 12 +
          _lireNombreAvecFraction(jetons[1]);
    } else if (jetons.length == 3 && jetons[2].contains('/')) {
      pouces =
          _lireNombreAvecFraction(jetons[0]) * 12 +
          _lireNombreAvecFraction('${jetons[1]} ${jetons[2]}');
    } else {
      throw const MesureInvalide(
        'Mesure non reconnue. Exemple : 10\'6" ou 13\'.',
      );
    }
  }
  if (!pouces.isFinite || pouces < 0) {
    throw const MesureInvalide('Mesure invalide.');
  }
  if (pouces > pouceMaxSaisie) {
    throw const MesureInvalide('Mesure trop grande.');
  }
  return pouces;
}

/// Lit une longueur métrique et retourne des POUCES. `3.2 m`, `3200 mm`,
/// `320 cm` ; sans unité : des MÈTRES.
double lireLongueurMetrique(String texte) {
  final s = _normaliser(texte).replaceAll(RegExp(r'\s'), '');
  if (s.isEmpty) {
    throw const MesureInvalide('Entrez une mesure.');
  }
  final m = RegExp(r'^([0-9]+(?:\.[0-9]+)?)(mm|cm|m)?$').firstMatch(s);
  if (m == null) {
    throw const MesureInvalide(
      'Mesure non reconnue. Exemple : 3,2 m ou 3200 mm.',
    );
  }
  final v = double.parse(m[1]!);
  final mm = switch (m[2]) {
    'mm' => v,
    'cm' => v * 10,
    _ => v * 1000,
  };
  final pouces = mmEnPouces(mm);
  if (!pouces.isFinite) {
    throw const MesureInvalide('Mesure invalide.');
  }
  if (pouces > pouceMaxSaisie) {
    throw const MesureInvalide('Mesure trop grande.');
  }
  return pouces;
}

double lireLongueur(String texte, {required bool metrique}) =>
    metrique ? lireLongueurMetrique(texte) : lireLongueurImperiale(texte);

/// Angle en degrés (« 35 », « 35° », « 35,5 »), strictement entre 0 et 360.
double lireAngle(String texte) {
  final s = texte.trim().replaceAll('°', '').replaceAll(',', '.').trim();
  final v = double.tryParse(s);
  if (v == null || !v.isFinite) {
    throw const MesureInvalide('Angle invalide.');
  }
  if (v <= 0 || v >= 360) {
    throw const MesureInvalide('L\'angle doit être entre 0° et 360°.');
  }
  return v;
}

// -----------------------------------------------------------------------------
// Affichage
// -----------------------------------------------------------------------------

/// « 10' 6 1/2" », « 13' », « 6 1/2" », « 0" » (arrondi au 1/[denominateur] po).
String formatImperial(double pouces, {int denominateur = 16}) {
  if (!pouces.isFinite) {
    return '—';
  }
  final negatif = pouces < 0;
  final total = (pouces.abs() * denominateur).round(); // en fractions de pouce
  final entiers = total ~/ denominateur;
  var num = total % denominateur;
  var den = denominateur;
  if (num != 0) {
    final g = _pgcd(num, den);
    num ~/= g;
    den ~/= g;
  }
  final pieds = entiers ~/ 12;
  final pouceEntier = entiers % 12;
  final fraction = num == 0 ? '' : '$num/$den';
  final partiePouces = [
    if (pouceEntier > 0 || (pieds == 0 && num == 0)) '$pouceEntier',
    if (fraction.isNotEmpty) fraction,
  ].join(' ');
  final texte = pieds > 0
      ? (partiePouces.isEmpty ? "$pieds'" : "$pieds' $partiePouces\"")
      : '$partiePouces"';
  return negatif && total != 0 ? '-$texte' : texte;
}

int _pgcd(int a, int b) => b == 0 ? a : _pgcd(b, a % b);

/// « 3,2 m » (≥ 1 m, 2 décimales sans zéros inutiles) ou « 850 mm ».
String formatMetrique(double pouces) {
  if (!pouces.isFinite) return '—';
  final mm = poucesEnMm(pouces);
  if (mm.abs() >= 1000) {
    final m = (mm / 1000);
    return '${_sansZeros(m.toStringAsFixed(3))} m';
  }
  return '${mm.round()} mm';
}

String _sansZeros(String s) {
  final t = s.contains('.') ? s.replaceFirst(RegExp(r'\.?0+$'), '') : s;
  return t.replaceFirst('.', ',');
}

String formatLongueur(double pouces, {required bool metrique}) =>
    metrique ? formatMetrique(pouces) : formatImperial(pouces);

/// Longueur de planche commerciale : « 12' » (pieds entiers).
String formatPlanche(double pouces, {required bool metrique}) {
  if (metrique) {
    final m = poucesEnMm(pouces) / 1000;
    return '${_sansZeros(m.toStringAsFixed(2))} m';
  }
  final pi = pouces / 12;
  return pi == pi.roundToDouble() ? "${pi.round()}'" : formatImperial(pouces);
}

/// Nombre avec virgule décimale et sans zéros inutiles : 7.50 → « 7,5 ».
String formatNombre(double v, {int decimales = 2}) {
  if (!v.isFinite) return '—';
  return _sansZeros(v.toStringAsFixed(decimales));
}

/// Degrés : « 35° », « 35,5° ».
String formatAngle(double deg) => '${formatNombre(deg, decimales: 1)}°';

double degEnRad(double d) => d * math.pi / 180;
double radEnDeg(double r) => r * 180 / math.pi;
