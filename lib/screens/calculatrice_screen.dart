import 'dart:math';

import 'package:flutter/material.dart';

import '../services/preferences.dart';
import '../services/theme_compagnie.dart';

/// Calculatrice affichée. On bascule en touchant deux fois l'onglet
/// Calculatrice de la barre du bas (voir main.dart).
enum ModeCalculatrice { charpente, beton }

/// Levée par l'évaluation quand une division par zéro survient.
class _DivisionParZero implements Exception {
  const _DivisionParZero();
}

const Color _casing = Color(0xFFEAE2D0);
const Color _boutonChiffreBg = Color(0xFFDDD2B8);
const Color _boutonChiffreBorder = Color(0xFFB8AC90);
const Color _boutonChiffreTexte = Color(0xFF2C2A22);
const Color _boutonEffacer = Color(0xFF6B2A1C);
const Color _texteClaire = Color(0xFFEAE2D0);

class CalculatriceScreen extends StatefulWidget {
  const CalculatriceScreen({super.key});

  /// Mode affiché (charpente ou béton), partagé avec la barre d'onglets.
  static final ValueNotifier<ModeCalculatrice> mode = ValueNotifier(
    ModeCalculatrice.charpente,
  );

  @override
  State<CalculatriceScreen> createState() => _CalculatriceScreenState();
}

class _CalculatriceScreenState extends State<CalculatriceScreen> {
  // Couleurs tirées de la couleur de la compagnie (thème) ; les chiffres
  // (beige) et AC (rouge) gardent leurs couleurs fixes.
  Color get _boutonOperateur => Theme.of(context).colorScheme.primary;
  Color get _boutonFonction => ThemeCompagnie.variante(_boutonOperateur);

  /// Écran : la couleur de l'app en plus foncé, texte clair lisible.
  Color get _lcdBg => Color.lerp(_boutonOperateur, Colors.black, 0.45)!;
  Color get _texteLcd => ThemeCompagnie.texteSur(_lcdBg);
  Color get _texteLcdSecondaire => Color.lerp(_texteLcd, _lcdBg, 0.25)!;

  /// Texte lisible sur une touche (contraste WCAG ≥ 4,5:1).
  Color _texteSur(Color fond) => ThemeCompagnie.texteSur(fond);

  ModeCalculatrice get _mode => CalculatriceScreen.mode.value;

  /// Unités de l'utilisateur. Base de calcul : pouces en impérial,
  /// millimètres en métrique.
  bool get _metrique => Preferences.estMetrique;

  @override
  void initState() {
    super.initState();
    CalculatriceScreen.mode.addListener(_changementMode);
    Preferences.unites.addListener(_changementUnites);
  }

  @override
  void dispose() {
    CalculatriceScreen.mode.removeListener(_changementMode);
    Preferences.unites.removeListener(_changementUnites);
    super.dispose();
  }

  void _changementMode() => _effacerToutAutre();

  /// Changer d'unités change la base de calcul (pouces ↔ mm) : les valeurs
  /// en cours, la mémoire et RUN/RISE/DIAG n'ont plus de sens, on repart à zéro.
  void _changementUnites() {
    _toutEffacerCharpente();
    setState(() => _memoire = null);
    _effacerToutAutre();
  }

  // Saisie métrique en cours (m, cm, mm).
  double? _metres;
  double? _centimetres;
  double? _millimetres;

  String _entreeCharpente = '';
  double? _feet;
  double? _inches;
  int? _fracNum;
  int? _fracDen;
  bool _enAttenteDenominateur = false;
  bool _uniteUtiliseeDansFormule = false;

  /// Expression en cours : nombres (en pouces), opérateurs et parenthèses.
  final List<Object> _jetons = [];

  /// Message affiché à la place du résultat (ex. division par zéro).
  String? _erreur;

  /// Texte affiché de chaque jeton de l'expression (même ordre que _jetons).
  final List<String> _textes = [];

  /// Formule affichée, construite à partir des textes des jetons.
  String get _formulePrecedente => _joindreTextes(_textes);

  /// « ( » collée à ce qui suit, « ) » collée à ce qui précède :
  /// ['(', '1', '+', '8', ')'] → « (1 + 8) ».
  static String _joindreTextes(List<String> textes) {
    final b = StringBuffer();
    for (final t in textes) {
      if (t == ')') {
        final avant = b.toString().trimRight();
        b
          ..clear()
          ..write('$avant) ');
      } else if (t == '(') {
        b.write('(');
      } else {
        b.write('$t ');
      }
    }
    return b.toString();
  }

  double? _resultatFinal;

  double? _rise;
  double? _run;
  double? _diag;
  bool _afficherEnPieds = true;

  double? _memoire;
  final List<Map<String, String>> _historique = [];

  List<String>? _conversionExtra;

  double? get _pitch {
    if (_rise != null && _run != null && _run != 0) {
      return (_rise! / _run!) * 12;
    }
    return null;
  }

  double? get _pitchDegres {
    if (_rise != null && _run != null && _run != 0) {
      return atan(_rise! / _run!) * 180 / pi;
    }
    return null;
  }

  bool get _operandeVide =>
      _feet == null &&
      _inches == null &&
      _fracNum == null &&
      _metres == null &&
      _centimetres == null &&
      _millimetres == null &&
      _entreeCharpente.isEmpty;

  void _finaliserFraction() {
    if (_enAttenteDenominateur && _entreeCharpente.isNotEmpty) {
      _fracDen = int.tryParse(_entreeCharpente) ?? 16;
      _entreeCharpente = '';
      _enAttenteDenominateur = false;
    }
  }

  double _valeurOperandeCourant() {
    _finaliserFraction();
    double total = 0;
    if (_feet != null) total += _feet! * 12;
    if (_metres != null) total += _metres! * 1000;
    if (_centimetres != null) total += _centimetres! * 10;
    if (_millimetres != null) total += _millimetres!;
    if (_inches != null) total += _inches!;
    if (_fracNum != null && _fracDen != null && _fracDen != 0) {
      total += _fracNum! / _fracDen!;
    }
    if (_entreeCharpente.isNotEmpty) {
      total += double.tryParse(_entreeCharpente) ?? 0;
    }
    return total;
  }

  String _fmtNum(double v) {
    if (v == v.roundToDouble()) return v.toStringAsFixed(0);
    return v.toString();
  }

  String _texteOperandeEnCours() {
    final buffer = StringBuffer();
    if (_metres != null) buffer.write('${_fmtNum(_metres!)} m ');
    if (_centimetres != null) buffer.write('${_fmtNum(_centimetres!)} cm ');
    if (_millimetres != null) buffer.write('${_fmtNum(_millimetres!)} mm ');
    if (_feet != null) {
      buffer.write("${_fmtNum(_feet!)}' ");
    }

    final aDuPouceOuFraction = _inches != null || _fracNum != null;
    if (aDuPouceOuFraction) {
      final entierPo = _inches != null ? _fmtNum(_inches!) : '0';
      String fracStr = '';
      if (_fracNum != null) {
        if (_enAttenteDenominateur) {
          fracStr = ' $_fracNum/$_entreeCharpente';
        } else if (_fracDen != null) {
          int num = _fracNum!, den = _fracDen!;
          if (den != 0) {
            final g = _pgcd(num, den);
            if (g != 0) {
              num ~/= g;
              den ~/= g;
            }
          }
          fracStr = ' $num/$den';
        } else {
          fracStr = ' $_fracNum/';
        }
      }
      buffer.write('$entierPo$fracStr" ');
    }

    if (_entreeCharpente.isNotEmpty && !_enAttenteDenominateur) {
      buffer.write(_entreeCharpente);
    }
    return buffer.toString();
  }

  String _formatDecimal(double v) {
    if (v == v.roundToDouble()) return v.toStringAsFixed(0);
    String s = v.toStringAsFixed(4);
    s = s.replaceFirst(RegExp(r'0+$'), '');
    s = s.replaceFirst(RegExp(r'\.$'), '');
    return s;
  }

  String _formatResultat(double v) {
    return _uniteUtiliseeDansFormule ? _formatLongueur(v) : _formatDecimal(v);
  }

  /// Longueur (en pouces ou en mm selon les unités) → texte principal :
  /// 5' 6 1/2" ou 2 m 35 cm 4 mm.
  String _formatLongueur(double v) =>
      _metrique ? _formatMetrique(v) : _formatPiedsPoucesFraction(v);

  /// Vue secondaire compacte : 66 1/2" ou 2354 mm.
  String _formatLongueurAlt(double v) =>
      _metrique ? '${_formatDecimal(v)} mm' : _formatPoucesFraction(v);

  /// Millimètres → « 2 m 35 cm 4 mm » (au dixième de mm, zéros omis).
  String _formatMetrique(double mm) {
    final negatif = mm < 0;
    var dixiemes = (mm.abs() * 10).round();
    final metres = dixiemes ~/ 10000;
    dixiemes %= 10000;
    final centimetres = dixiemes ~/ 100;
    final resteMm = (dixiemes % 100) / 10;
    final parties = [
      if (metres > 0) '$metres m',
      if (centimetres > 0) '$centimetres cm',
      if (resteMm > 0) '${_formatDecimal(resteMm)} mm',
    ];
    if (parties.isEmpty) return '0 mm';
    return '${negatif ? '-' : ''}${parties.join(' ')}';
  }

  /// Réponse affichée ; la toucher alterne les vues : pi-po ↔ pouces, ou
  /// m cm mm → m → mm.
  int _vueResultat = 0;

  String _texteResultatVue(double v) {
    if (_metrique) {
      switch (_vueResultat % 3) {
        case 1:
          return '${_formatDecimal(v / 1000)} m';
        case 2:
          return '${_formatDecimal(v)} mm';
        default:
          return _formatMetrique(v);
      }
    }
    return _vueResultat.isEven
        ? _formatPiedsPoucesFraction(v)
        : _formatPoucesFraction(v);
  }

  // ==================== EXPRESSION (priorité des opérations) ====================
  //
  // L'expression est conservée en entier dans _jetons (nombres en pouces,
  // opérateurs + - × ÷ et parenthèses), puis évaluée selon la priorité des
  // opérations : parenthèses, puis × et ÷, puis + et −, de gauche à droite.
  // _textes contient le texte affiché de chaque jeton (voir _formulePrecedente).

  static const _operateurs = {'+', '-', '×', '÷'};

  bool _estOperateur(Object? jeton) => _operateurs.contains(jeton);

  /// Vrai si le dernier jeton termine une valeur (nombre ou « ) »).
  bool get _finitParUneValeur =>
      _jetons.isNotEmpty && (_jetons.last is double || _jetons.last == ')');

  int get _parenthesesOuvertes =>
      _jetons.where((j) => j == '(').length -
      _jetons.where((j) => j == ')').length;

  void _viderOperande() {
    _metres = null;
    _centimetres = null;
    _millimetres = null;
    _feet = null;
    _inches = null;
    _fracNum = null;
    _fracDen = null;
    _enAttenteDenominateur = false;
    _entreeCharpente = '';
  }

  /// Ajoute l'opérande en cours de saisie à l'expression.
  void _pousserOperande() {
    _finaliserFraction();
    if (_operandeVide) return;
    _jetons.add(_valeurOperandeCourant());
    _textes.add(_texteOperandeEnCours().trim());
    _viderOperande();
  }

  /// Multiplication implicite, comme en mathématiques : un nombre ou une
  /// « ( » collé à une valeur la multiplie, (2+3)4 = 20 et 2(3+1) = 8.
  void _multiplicationImplicite() {
    if (_finitParUneValeur) {
      _jetons.add('×');
      _textes.add('×');
    }
  }

  /// Retire l'opérateur final (texte et jeton), ex. « 2 + » → « 2 ».
  void _retirerOperateurFinal() {
    if (_jetons.isEmpty || !_estOperateur(_jetons.last)) return;
    _jetons.removeLast();
    _textes.removeLast();
  }

  static int _priorite(String op) => (op == '×' || op == '÷') ? 2 : 1;

  /// Évalue une expression en respectant la priorité des opérations
  /// (algorithme de la gare de triage). Un opérateur final est ignoré et les
  /// parenthèses restées ouvertes sont fermées. Retourne null si l'expression
  /// est vide ; lance [_DivisionParZero] en cas de division par zéro.
  static double? evaluerExpression(List<Object> expression) {
    final jetons = [...expression];
    while (jetons.isNotEmpty && _operateurs.contains(jetons.last)) {
      jetons.removeLast();
    }
    var ouvertes = 0;
    for (final j in jetons) {
      if (j == '(') ouvertes++;
      if (j == ')') ouvertes--;
    }
    for (var i = 0; i < ouvertes; i++) {
      jetons.add(')');
    }
    // « ( ) » vide : rien à calculer.
    if (!jetons.any((j) => j is double)) return null;

    final valeurs = <double>[];
    final operateurs = <String>[];

    void appliquer() {
      final op = operateurs.removeLast();
      final b = valeurs.removeLast();
      final a = valeurs.removeLast();
      switch (op) {
        case '+':
          valeurs.add(a + b);
        case '-':
          valeurs.add(a - b);
        case '×':
          valeurs.add(a * b);
        case '÷':
          if (b == 0) throw const _DivisionParZero();
          valeurs.add(a / b);
      }
    }

    for (final j in jetons) {
      if (j is double) {
        valeurs.add(j);
      } else if (j == '(') {
        operateurs.add('(');
      } else if (j == ')') {
        while (operateurs.isNotEmpty && operateurs.last != '(') {
          appliquer();
        }
        if (operateurs.isNotEmpty) operateurs.removeLast();
      } else if (j is String) {
        // Gauche à droite à priorité égale : 10−4−3 = 3.
        while (operateurs.isNotEmpty &&
            operateurs.last != '(' &&
            _priorite(operateurs.last) >= _priorite(j)) {
          appliquer();
        }
        operateurs.add(j);
      }
    }
    while (operateurs.isNotEmpty) {
      if (operateurs.last == '(') {
        operateurs.removeLast();
      } else {
        appliquer();
      }
    }
    return valeurs.isEmpty ? null : valeurs.last;
  }

  /// Expression complète (jetons + opérande en cours), sans modifier l'état.
  List<Object> _expressionComplete() {
    _finaliserFraction();
    final expression = [..._jetons];
    if (!_operandeVide) {
      if (expression.isNotEmpty &&
          (expression.last is double || expression.last == ')')) {
        expression.add('×');
      }
      expression.add(_valeurOperandeCourant());
    }
    return expression;
  }

  void _appuyerChiffreCharpente(String chiffre) {
    setState(() {
      _erreur = null;
      if (_resultatFinal != null) {
        _resultatFinal = null;
        _textes.clear();
        _jetons.clear();
        _uniteUtiliseeDansFormule = false;
        _conversionExtra = null;
      }
      if (_operandeVide) _multiplicationImplicite();
      if (chiffre == '.' && _entreeCharpente.contains('.')) return;
      if (_entreeCharpente.isEmpty && chiffre == '.') {
        _entreeCharpente = '0.';
      } else if (_entreeCharpente == '0' && chiffre != '.') {
        _entreeCharpente = chiffre;
      } else {
        _entreeCharpente += chiffre;
      }
    });
  }

  void _effacerDernierCharpente() {
    setState(() {
      if (_entreeCharpente.isNotEmpty) {
        _entreeCharpente = _entreeCharpente.substring(
          0,
          _entreeCharpente.length - 1,
        );
      } else if (_enAttenteDenominateur) {
        _entreeCharpente = _fracNum?.toString() ?? '';
        _fracNum = null;
        _enAttenteDenominateur = false;
      } else if (_fracDen != null || _fracNum != null) {
        _fracNum = null;
        _fracDen = null;
      } else if (_inches != null) {
        _inches = null;
      } else if (_feet != null) {
        _feet = null;
      } else if (_millimetres != null) {
        _millimetres = null;
      } else if (_centimetres != null) {
        _centimetres = null;
      } else if (_metres != null) {
        _metres = null;
      }
    });
  }

  void _toutEffacerCharpente() {
    setState(() {
      _viderOperande();
      _jetons.clear();
      _erreur = null;
      _textes.clear();
      _resultatFinal = null;
      _rise = null;
      _run = null;
      _diag = null;
      _uniteUtiliseeDansFormule = false;
      _conversionExtra = null;
    });
  }

  void _reinitialiserSiResultat() {
    _erreur = null;
    if (_resultatFinal != null) {
      _resultatFinal = null;
      _textes.clear();
      _jetons.clear();
      _conversionExtra = null;
    }
  }

  void _committerUnite(void Function(double valeur) affecter) {
    if (_entreeCharpente.isEmpty) return;
    setState(() {
      _reinitialiserSiResultat();
      affecter(double.tryParse(_entreeCharpente) ?? 0);
      _entreeCharpente = '';
      _uniteUtiliseeDansFormule = true;
    });
  }

  void _committerMetres() => _committerUnite((v) => _metres = v);
  void _committerCentimetres() => _committerUnite((v) => _centimetres = v);
  void _committerMillimetres() => _committerUnite((v) => _millimetres = v);

  void _committerFeet() {
    if (_entreeCharpente.isEmpty) return;
    setState(() {
      _reinitialiserSiResultat();
      _finaliserFraction();
      _feet = double.tryParse(_entreeCharpente) ?? 0;
      _entreeCharpente = '';
      _uniteUtiliseeDansFormule = true;
    });
  }

  void _committerPouces() {
    if (_entreeCharpente.isEmpty) return;
    setState(() {
      _reinitialiserSiResultat();
      _finaliserFraction();
      _inches = double.tryParse(_entreeCharpente) ?? 0;
      _entreeCharpente = '';
      _uniteUtiliseeDansFormule = true;
    });
  }

  void _committerSeizieme() {
    setState(() {
      _reinitialiserSiResultat();
      if (_fracNum == null && _entreeCharpente.isNotEmpty) {
        _fracNum = int.tryParse(_entreeCharpente) ?? 0;
        _entreeCharpente = '';
        _enAttenteDenominateur = true;
        _uniteUtiliseeDansFormule = true;
      }
    });
  }

  void _appuyerOperateurCharpente(String op) {
    setState(() {
      _conversionExtra = null;
      _erreur = null;
      if (_resultatFinal != null) {
        // Continuer à partir du résultat affiché.
        _jetons
          ..clear()
          ..add(_resultatFinal!);
        _textes
          ..clear()
          ..add(_formatResultat(_resultatFinal!));
        _resultatFinal = null;
        _viderOperande();
      } else {
        _pousserOperande();
      }

      if (_jetons.isEmpty || _jetons.last == '(') return; // rien à opérer
      if (_estOperateur(_jetons.last)) {
        // Remplace l'opérateur qui vient d'être tapé.
        _retirerOperateurFinal();
      }
      _jetons.add(op);
      _textes.add(op);
    });
  }

  void _ouvrirParenthese() {
    setState(() {
      _conversionExtra = null;
      _reinitialiserSiResultat();
      _pousserOperande();
      _multiplicationImplicite();
      _jetons.add('(');
      _textes.add('(');
    });
  }

  void _fermerParenthese() {
    if (_parenthesesOuvertes <= 0) return;
    setState(() {
      _pousserOperande();
      if (_jetons.last == '(') return; // « ( ) » vide : ignorée
      _retirerOperateurFinal();
      _jetons.add(')');
      _textes.add(')');
    });
  }

  void _ajouterHistorique(String formule, double resultat) {
    _historique.insert(0, {
      'formule': formule,
      'resultat': _formatResultat(resultat),
    });
    if (_historique.length > 50) _historique.removeLast();
  }

  void _appuyerEgalCharpente() {
    setState(() {
      _conversionExtra = null;
      final formuleAffichee = (_formulePrecedente + _texteOperandeEnCours())
          .trim();
      final expression = _expressionComplete();
      double? resultat;
      try {
        resultat = evaluerExpression(expression);
      } on _DivisionParZero {
        _erreur = 'Division par zéro';
      }
      if (resultat == null && _erreur == null) return;

      if (resultat != null && formuleAffichee.isNotEmpty) {
        _ajouterHistorique(formuleAffichee, resultat);
      }
      _resultatFinal = resultat;
      _textes.clear();
      _jetons.clear();
      _viderOperande();
    });
  }

  /// Valeur de toute l'expression en cours (ou du dernier résultat), utilisée
  /// par √, %, x², x³, Conv, M+ et RISE/RUN/DIAG. Null si rien à calculer ou
  /// division par zéro.
  double? _valeurActuelle() {
    if (_resultatFinal != null) return _resultatFinal;
    try {
      return evaluerExpression(_expressionComplete());
    } on _DivisionParZero {
      return null;
    }
  }

  // ==================== √, x², x³, % ====================
  //
  // Après « = » : s'applique à la réponse affichée.
  // Pendant la saisie : s'applique au dernier nombre, ou au groupe « ( … ) »
  // qui vient d'être fermé. 2 + 3 × 4² = 50 ; (2 + 3)² = 25.

  /// Index du « ( » correspondant au « ) » final de l'expression.
  int _indexParentheseOuvrante() {
    var profondeur = 0;
    for (var i = _jetons.length - 1; i >= 0; i--) {
      if (_jetons[i] == ')') profondeur++;
      if (_jetons[i] == '(') profondeur--;
      if (profondeur == 0) return i;
    }
    return 0;
  }

  /// Met un texte entre parenthèses s'il ne se lit pas comme un seul bloc :
  /// « 4 » reste « 4 », « 1' 6" » devient « (1' 6") », « 2² » devient « (2²) ».
  static String _bloc(String texte) {
    final estNombreSimple = RegExp(r'^[0-9.]+$').hasMatch(texte);
    final estGroupe = texte.startsWith('(') && texte.endsWith(')');
    return estNombreSimple || estGroupe ? texte : '($texte)';
  }

  void _appliquerAuDernierNombre({
    required double? Function(double v) calcul,
    required String Function(String bloc) libelle,
  }) {
    setState(() {
      _conversionExtra = null;
      if (_resultatFinal != null) {
        final v = _resultatFinal!;
        final r = calcul(v);
        if (r == null) return;
        _ajouterHistorique(libelle(_bloc(_formatResultat(v))), r);
        _resultatFinal = r;
        return;
      }

      _pousserOperande();
      if (_jetons.isEmpty) return;

      final int debut;
      final double? v;
      if (_jetons.last is double) {
        debut = _jetons.length - 1;
        v = _jetons.last as double;
      } else if (_jetons.last == ')') {
        debut = _indexParentheseOuvrante();
        double? valeurGroupe;
        try {
          valeurGroupe = evaluerExpression(_jetons.sublist(debut));
        } on _DivisionParZero {
          valeurGroupe = null;
        }
        v = valeurGroupe;
      } else {
        return; // juste après un opérateur ou « ( » : rien à quoi l'appliquer
      }
      if (v == null) return;
      final r = calcul(v);
      if (r == null) return;

      final texte = _joindreTextes(_textes.sublist(debut)).trim();
      _jetons
        ..removeRange(debut, _jetons.length)
        ..add(r);
      _textes
        ..removeRange(debut, _textes.length)
        ..add(libelle(_bloc(texte)));
    });
  }

  void _appliquerRacine() => _appliquerAuDernierNombre(
    calcul: (v) => v < 0 ? null : sqrt(v),
    libelle: (b) => '√$b',
  );

  void _appliquerPourcent() =>
      _appliquerAuDernierNombre(calcul: (v) => v / 100, libelle: (b) => '$b%');

  void _appliquerCarre() =>
      _appliquerAuDernierNombre(calcul: (v) => v * v, libelle: (b) => '$b²');

  void _appliquerCube() => _appliquerAuDernierNombre(
    calcul: (v) => v * v * v,
    libelle: (b) => '$b³',
  );

  void _appliquerConversion() {
    setState(() {
      final v = _valeurActuelle();
      if (v == null) return;
      // Conv affiche toujours pieds-pouces, pouces et mètres.
      final pouces = _metrique ? v / 25.4 : v;
      final metres = pouces * 0.0254;
      _ajouterHistorique(
        _metrique
            ? 'Conv(${_formatDecimal(v)} mm)'
            : 'Conv(${_formatDecimal(v)}")',
        v,
      );
      _resultatFinal = v;
      _uniteUtiliseeDansFormule = true;
      _textes.clear();
      _jetons.clear();
      _erreur = null;
      _viderOperande();
      _conversionExtra = [
        _formatPiedsPoucesFraction(pouces),
        '${_formatPoucesFraction(pouces).replaceAll('"', '')} po',
        '${metres.toStringAsFixed(3)} m',
        '${(metres * 100).toStringAsFixed(1)} cm',
      ];
    });
  }

  void _memoirePlus() {
    final v = _valeurActuelle();
    if (v == null) return;
    setState(() => _memoire = (_memoire ?? 0) + v);
  }

  void _memoireMoins() {
    final v = _valeurActuelle();
    if (v == null) return;
    setState(() => _memoire = (_memoire ?? 0) - v);
  }

  void _memoireRappel() {
    if (_memoire == null) return;
    setState(() {
      _resultatFinal = _memoire;
      _textes.clear();
      _jetons.clear();
      _erreur = null;
      _viderOperande();
      _conversionExtra = null;
    });
  }

  void _memoireEffacer() {
    setState(() => _memoire = null);
  }

  void _ouvrirHistorique() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        return DraggableScrollableSheet(
          initialChildSize: 0.6,
          expand: false,
          builder: (ctx, scrollController) {
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Historique',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      if (_historique.isNotEmpty)
                        TextButton(
                          onPressed: () {
                            setState(() => _historique.clear());
                            Navigator.pop(ctx);
                          },
                          child: const Text('Effacer tout'),
                        ),
                    ],
                  ),
                ),
                Expanded(
                  child: _historique.isEmpty
                      ? const Center(
                          child: Text('Aucun calcul pour l\'instant.'),
                        )
                      : ListView.builder(
                          controller: scrollController,
                          itemCount: _historique.length,
                          itemBuilder: (ctx, i) {
                            final entree = _historique[i];
                            return ListTile(
                              title: Text(
                                entree['formule'] ?? '',
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: Colors.grey,
                                ),
                              ),
                              subtitle: Text(
                                entree['resultat'] ?? '',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _stocker(String role) {
    _finaliserFraction();
    final double? valeurBrute = _valeurActuelle();
    if (valeurBrute == null) return;
    final double valeur = valeurBrute;

    setState(() {
      switch (role) {
        case 'rise':
          _rise = valeur;
          break;
        case 'run':
          _run = valeur;
          break;
        case 'diag':
          _diag = valeur;
          break;
      }
      _entreeCharpente = '';
      _feet = null;
      _inches = null;
      _fracNum = null;
      _fracDen = null;
      _enAttenteDenominateur = false;
      _jetons.clear();
      _erreur = null;
      _textes.clear();
      _resultatFinal = null;
      _conversionExtra = null;
      _recalculerCharpente();
    });
  }

  void _recalculerCharpente() {
    if (_rise != null && _run != null) {
      _diag = sqrt(_rise! * _rise! + _run! * _run!);
    } else if (_rise != null && _diag != null && _diag! >= _rise!) {
      _run = sqrt(_diag! * _diag! - _rise! * _rise!);
    } else if (_run != null && _diag != null && _diag! >= _run!) {
      _rise = sqrt(_diag! * _diag! - _run! * _run!);
    }
  }

  int _pgcd(int a, int b) => b == 0 ? a : _pgcd(b, a % b);

  String _formatPoucesFraction(double pouces) {
    final negatif = pouces < 0;
    final v = pouces.abs();
    final totalSeiziemes = (v * 16).round();
    final seizieme = totalSeiziemes % 16;
    final entier = totalSeiziemes ~/ 16;
    String fracStr = '';
    if (seizieme != 0) {
      int num = seizieme, den = 16;
      final g = _pgcd(num, den);
      num ~/= g;
      den ~/= g;
      fracStr = ' $num/$den';
    }
    return '${negatif ? "-" : ""}$entier$fracStr"';
  }

  String _formatPiedsPoucesFraction(double pouces) {
    final negatif = pouces < 0;
    final v = pouces.abs();
    final totalSeiziemes = (v * 16).round();
    final seizieme = totalSeiziemes % 16;
    final totalPouces = totalSeiziemes ~/ 16;
    final pieds = totalPouces ~/ 12;
    final restePouces = totalPouces % 12;
    String fracStr = '';
    if (seizieme != 0) {
      int num = seizieme, den = 16;
      final g = _pgcd(num, den);
      num ~/= g;
      den ~/= g;
      fracStr = ' $num/$den';
    }
    final signe = negatif ? '-' : '';
    if (pieds > 0) {
      return "$signe$pieds' $restePouces$fracStr\"";
    }
    return "$signe$restePouces$fracStr\"";
  }

  // ==================== BÉTON ====================

  int _etape = 0;
  String _saisie = '';
  final List<double> _valeurs = []; // en mètres
  String? _resultatTitre;
  List<String> _resultatLignes = [];
  String? _noteResultat;

  /// Unité de la saisie en cours : pi/po en impérial, m/cm/mm en métrique.
  String _uniteBeton = 'pi';

  static const _etapes = ['Longueur', 'Largeur', 'Épaisseur'];

  /// Rendement d'un sac de béton prémélangé de 30 kg (≈ 14 L).
  static const _rendementSacM3 = 0.014;

  bool get _termine => _etape >= _etapes.length;

  /// Unités proposées pour l'étape en cours (la première est celle par défaut).
  List<String> get _unitesEtape => _metrique
      ? (_etape == 2 ? ['cm', 'mm'] : ['m', 'cm'])
      : (_etape == 2 ? ['po', 'pi'] : ['pi', 'po']);

  void _appuyerChiffreAutre(String chiffre) {
    if (_termine) return;
    setState(() {
      if (chiffre == '.' && _saisie.contains('.')) return;
      if (_saisie.isEmpty && chiffre == '.') {
        _saisie = '0.';
      } else if (_saisie == '0' && chiffre != '.') {
        _saisie = chiffre;
      } else {
        _saisie += chiffre;
      }
    });
  }

  void _effacerDernierAutre() {
    if (_saisie.isEmpty) return;
    setState(() {
      _saisie = _saisie.substring(0, _saisie.length - 1);
    });
  }

  void _effacerToutAutre() {
    setState(() {
      _etape = 0;
      _saisie = '';
      _valeurs.clear();
      _resultatTitre = null;
      _resultatLignes = [];
      _noteResultat = null;
      _uniteBeton = _unitesEtape.first;
    });
  }

  static double _enMetres(double valeur, String unite) {
    switch (unite) {
      case 'pi':
        return valeur * 0.3048;
      case 'po':
        return valeur * 0.0254;
      case 'cm':
        return valeur / 100;
      case 'mm':
        return valeur / 1000;
      case 'm':
      default:
        return valeur;
    }
  }

  void _entreeAutre() {
    if (_termine) return;
    final valeurBrute = double.tryParse(_saisie) ?? 0;
    setState(() {
      _valeurs.add(_enMetres(valeurBrute, _uniteBeton));
      _saisie = '';
      _etape++;
      if (_termine) {
        _calculerResultatAutre();
      } else {
        _uniteBeton = _unitesEtape.first;
      }
    });
  }

  void _calculerResultatAutre() {
    final volumeM3 = _valeurs[0] * _valeurs[1] * _valeurs[2];
    final sacs = (volumeM3 / _rendementSacM3).ceil();
    _resultatTitre = 'Résultat béton';
    if (_metrique) {
      _resultatLignes = [
        'Volume : ${volumeM3.toStringAsFixed(3)} m³',
        'Sacs de 30 kg : $sacs',
      ];
    } else {
      final pi3 = volumeM3 / 0.0283168466;
      final vg3 = pi3 / 27;
      _resultatLignes = [
        'Volume : ${vg3.toStringAsFixed(2)} vg³ (${pi3.toStringAsFixed(2)} pi³)',
        '${volumeM3.toStringAsFixed(3)} m³',
        'Sacs de 30 kg : $sacs',
      ];
    }
    _noteResultat = 'Rendement ≈ 14 L par sac de 30 kg ; prévoir 5 à 10 % de plus pour les pertes.';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: _casing,
      child: SafeArea(
        child: Column(
          children: [
            _enteteMode(),
            const SizedBox(height: 8),
            _mode == ModeCalculatrice.charpente
                ? _ecranCharpente()
                : _ecranAutre(),
            const SizedBox(height: 8),
            Expanded(
              child: _mode == ModeCalculatrice.charpente
                  ? _clavierCharpente()
                  : _clavierAutre(),
            ),
          ],
        ),
      ),
    );
  }

  /// En-tête : calculatrice affichée et unités. Toucher le titre bascule
  /// aussi entre charpente et béton.
  Widget _enteteMode() {
    final beton = _mode == ModeCalculatrice.beton;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      child: Row(
        children: [
          InkWell(
            key: const ValueKey('titre_mode_calculatrice'),
            onTap: () => CalculatriceScreen.mode.value = beton
                ? ModeCalculatrice.charpente
                : ModeCalculatrice.beton,
            child: Row(
              children: [
                Text(
                  beton ? 'Béton' : 'Charpente',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                    color: ThemeCompagnie.accentDe(context),
                  ),
                ),
                Icon(
                  Icons.swap_horiz,
                  size: 18,
                  color: ThemeCompagnie.accentDe(context),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Touchez deux fois l\'onglet pour ${beton ? 'la charpente' : 'le béton'}',
              style: const TextStyle(fontSize: 11, color: Color(0xFF6B6455)),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text(
            _metrique ? 'Métrique' : 'Impérial',
            style: const TextStyle(fontSize: 11, color: Color(0xFF6B6455)),
          ),
        ],
      ),
    );
  }

  Widget _ecranCharpente() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: _lcdBg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _boutonOperateur, width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  if (_pitch != null)
                    Text(
                      _metrique
                          ? 'PENTE ${(_pitch! / 12 * 100).toStringAsFixed(1)} %'
                          : 'PITCH ${_pitch!.toStringAsFixed(2)}/12',
                      style: TextStyle(
                        color: _texteLcd,
                        fontSize: 11,
                        fontFamily: 'monospace',
                        letterSpacing: 1,
                      ),
                    ),
                  if (_memoire != null)
                    Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: Text(
                        'M',
                        style: TextStyle(
                          color: _texteLcd,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                ],
              ),
              InkWell(
                onTap: _ouvrirHistorique,
                child: Icon(Icons.history, size: 18, color: _texteLcd),
              ),
            ],
          ),
          if (_diag != null)
            GestureDetector(
              onTap: () => setState(() => _afficherEnPieds = !_afficherEnPieds),
              child: Align(
                alignment: Alignment.centerRight,
                child: Text(
                  _afficherEnPieds
                      ? _formatLongueur(_diag!)
                      : _formatLongueurAlt(_diag!),
                  style: TextStyle(
                    color: _texteLcdSecondaire,
                    fontSize: 13,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
            ),
          const SizedBox(height: 2),
          if (_resultatFinal != null)
            GestureDetector(
              onTap: _uniteUtiliseeDansFormule
                  ? () => setState(() => _vueResultat++)
                  : null,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerRight,
                child: Text(
                  _uniteUtiliseeDansFormule
                      ? _texteResultatVue(_resultatFinal!)
                      : _formatDecimal(_resultatFinal!),
                  style: TextStyle(
                    color: _texteLcd,
                    fontSize: 38,
                    fontWeight: FontWeight.w700,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
            )
          else if (_erreur != null)
            Align(
              alignment: Alignment.centerRight,
              child: Text(
                _erreur!,
                style: TextStyle(
                  color: _texteLcd,
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  fontFamily: 'monospace',
                ),
              ),
            )
          else
            Align(
              alignment: Alignment.centerRight,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  (_formulePrecedente + _texteOperandeEnCours()).trim().isEmpty
                      ? '0'
                      : (_formulePrecedente + _texteOperandeEnCours()),
                  style: TextStyle(
                    color: _texteLcd,
                    fontSize: 26,
                    fontWeight: FontWeight.w600,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
            ),
          if (_conversionExtra != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: _conversionExtra!
                    .map(
                      (l) => Text(
                        l,
                        style: TextStyle(
                          color: _texteLcdSecondaire,
                          fontSize: 14,
                          fontFamily: 'monospace',
                        ),
                      ),
                    )
                    .toList(),
              ),
            ),
        ],
      ),
    );
  }

  /// Disposition « chantier classique » (modèle 1).
  Widget _clavierCharpente() {
    Widget rangee(List<Widget> touches) => Expanded(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: touches,
      ),
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      child: Column(
        children: [
          SizedBox(
            height: 34,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _toucheExtraPetite('M+', _memoirePlus),
                _toucheExtraPetite('M−', _memoireMoins),
                _toucheExtraPetite('MR', _memoireRappel),
                _toucheExtraPetite('MC', _memoireEffacer),
              ],
            ),
          ),
          rangee([
            _toucheMemoireGrande('RUN', _run, () => _stocker('run')),
            _toucheMemoireGrande('RISE', _rise, () => _stocker('rise')),
            _toucheMemoireDiagGrande(),
            _toucheFonctionGrande('Conv', _appliquerConversion, fonction: true),
          ]),
          rangee(
            _metrique
                ? [
                    _toucheFonctionGrande('m', _committerMetres, claire: true),
                    _toucheFonctionGrande(
                      'cm',
                      _committerCentimetres,
                      claire: true,
                    ),
                    _toucheFonctionGrande(
                      'mm',
                      _committerMillimetres,
                      claire: true,
                    ),
                    _toucheFonctionGrande(
                      '⌫',
                      _effacerDernierCharpente,
                      claire: true,
                    ),
                  ]
                : [
                    _toucheFonctionGrande('Pi', _committerFeet, claire: true),
                    _toucheFonctionGrande('Po', _committerPouces, claire: true),
                    _toucheFonctionGrande(
                      'x/y',
                      _committerSeizieme,
                      claire: true,
                    ),
                    _toucheFonctionGrande(
                      '⌫',
                      _effacerDernierCharpente,
                      claire: true,
                    ),
                  ],
          ),
          rangee([
            _toucheFonctionGrande('(', _ouvrirParenthese, fonction: true),
            _toucheFonctionGrande(')', _fermerParenthese, fonction: true),
            _toucheFonctionGrande('x²', _appliquerCarre, fonction: true),
            _toucheFonctionGrande('√x', _appliquerRacine, fonction: true),
          ]),
          rangee([
            _toucheChiffreGrande('7'),
            _toucheChiffreGrande('8'),
            _toucheChiffreGrande('9'),
            _toucheFonctionGrande(
              '÷',
              () => _appuyerOperateurCharpente('÷'),
              operateur: true,
            ),
          ]),
          rangee([
            _toucheChiffreGrande('4'),
            _toucheChiffreGrande('5'),
            _toucheChiffreGrande('6'),
            _toucheFonctionGrande(
              '×',
              () => _appuyerOperateurCharpente('×'),
              operateur: true,
            ),
          ]),
          rangee([
            _toucheChiffreGrande('1'),
            _toucheChiffreGrande('2'),
            _toucheChiffreGrande('3'),
            _toucheFonctionGrande(
              '−',
              () => _appuyerOperateurCharpente('-'),
              operateur: true,
            ),
          ]),
          rangee([
            _toucheFonctionGrande('AC', _toutEffacerCharpente, effacer: true),
            _toucheChiffreGrande('0'),
            _toucheChiffreGrande('.'),
            _toucheFonctionGrande(
              '+',
              () => _appuyerOperateurCharpente('+'),
              operateur: true,
            ),
          ]),
          rangee([
            _toucheFonctionGrande('x³', _appliquerCube, fonction: true),
            _toucheFonctionGrande('%', _appliquerPourcent, fonction: true),
            Expanded(
              flex: 2,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _toucheFonctionGrande(
                    '=',
                    _appuyerEgalCharpente,
                    operateur: true,
                  ),
                ],
              ),
            ),
          ]),
        ],
      ),
    );
  }

  Widget _toucheMemoireGrande(
    String label,
    double? valeur,
    VoidCallback onTap,
  ) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.all(3),
        child: ElevatedButton(
          key: ValueKey('touche_$label'),
          onPressed: onTap,
          style: ElevatedButton.styleFrom(
            backgroundColor: _boutonFonction,
            foregroundColor: _texteSur(_boutonFonction),
            padding: EdgeInsets.zero,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  valeur == null ? '—' : _formatLongueurAlt(valeur),
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _toucheMemoireDiagGrande() {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.all(3),
        child: ElevatedButton(
          key: const ValueKey('touche_DIAG'),
          onPressed: () => _stocker('diag'),
          style: ElevatedButton.styleFrom(
            backgroundColor: _boutonFonction,
            foregroundColor: _texteSur(_boutonFonction),
            padding: EdgeInsets.zero,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'DIAG',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text(
                  _diag == null ? '—' : _formatLongueurAlt(_diag!),
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (_pitchDegres != null)
                  Text(
                    '${_pitchDegres!.toStringAsFixed(1)}°',
                    style: const TextStyle(fontSize: 10),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _toucheExtraPetite(
    String label,
    VoidCallback onTap, {
    bool fonction = false,
  }) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.all(3),
        child: ElevatedButton(
          key: ValueKey('touche_$label'),
          onPressed: onTap,
          style: ElevatedButton.styleFrom(
            backgroundColor: fonction ? _boutonFonction : _boutonOperateur,
            foregroundColor: _texteSur(
              fonction ? _boutonFonction : _boutonOperateur,
            ),
            padding: EdgeInsets.zero,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          child: Text(
            label,
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
          ),
        ),
      ),
    );
  }

  Widget _toucheChiffreGrande(String chiffre) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.all(3),
        child: ElevatedButton(
          key: ValueKey('touche_$chiffre'),
          onPressed: () => _appuyerChiffreCharpente(chiffre),
          style: ElevatedButton.styleFrom(
            backgroundColor: _boutonChiffreBg,
            foregroundColor: _boutonChiffreTexte,
            side: const BorderSide(color: _boutonChiffreBorder),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          child: Text(
            chiffre,
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w600),
          ),
        ),
      ),
    );
  }

  Widget _toucheFonctionGrande(
    String label,
    VoidCallback onTap, {
    bool operateur = false,
    bool claire = false,
    bool effacer = false,
    bool fonction = false,
  }) {
    Color bg;
    Color fg;
    if (effacer) {
      bg = _boutonEffacer;
      fg = _texteClaire;
    } else if (fonction) {
      bg = _boutonFonction;
      fg = _texteSur(bg);
    } else if (operateur) {
      bg = _boutonOperateur;
      fg = _texteSur(bg);
    } else if (claire) {
      bg = _boutonChiffreBg;
      fg = _boutonChiffreTexte;
    } else {
      bg = _boutonOperateur;
      fg = _texteSur(bg);
    }
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.all(3),
        child: ElevatedButton(
          key: ValueKey('touche_$label'),
          onPressed: onTap,
          style: ElevatedButton.styleFrom(
            backgroundColor: bg,
            foregroundColor: fg,
            side: claire ? const BorderSide(color: _boutonChiffreBorder) : null,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          child: Text(
            label,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
          ),
        ),
      ),
    );
  }

  Widget _ecranAutre() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _lcdBg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _boutonOperateur, width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              _termine ? 'Résultat' : _etapes[_etape],
              style: TextStyle(
                color: _texteLcd,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(height: 8),
          if (!_termine)
            Text(
              '${_saisie.isEmpty ? '0' : _saisie} $_uniteBeton',
              style: TextStyle(
                color: _texteLcd,
                fontSize: 40,
                fontWeight: FontWeight.w700,
                fontFamily: 'monospace',
              ),
            ),
          if (_termine) ...[
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                _resultatTitre ?? '',
                style: TextStyle(
                  color: _texteLcd,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(height: 6),
            ..._resultatLignes.map(
              (l) => Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  l,
                  style: TextStyle(
                    color: _texteLcd,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
            if (_noteResultat != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    _noteResultat!,
                    style: TextStyle(color: _texteLcdSecondaire, fontSize: 12),
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _clavierAutre() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      child: Column(
        children: [
          if (!_termine) ...[
            SizedBox(
              height: 34,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final u in _unitesEtape)
                    _toucheUnite(
                      u,
                      u,
                      _uniteBeton,
                      (v) => setState(() => _uniteBeton = v),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 6),
          ],
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _toucheChiffreAutre('7'),
                _toucheChiffreAutre('8'),
                _toucheChiffreAutre('9'),
                _toucheFonctionAutre('⌫', _effacerDernierAutre, claire: true),
              ],
            ),
          ),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _toucheChiffreAutre('4'),
                _toucheChiffreAutre('5'),
                _toucheChiffreAutre('6'),
                _toucheFonctionAutre('AC', _effacerToutAutre, effacer: true),
              ],
            ),
          ),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _toucheChiffreAutre('1'),
                _toucheChiffreAutre('2'),
                _toucheChiffreAutre('3'),
                _toucheFonctionAutre('↵', _entreeAutre, fonction: true),
              ],
            ),
          ),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // (Avant : Expanded dans Expanded, la rangée ne s'affichait pas.)
                _toucheChiffreAutre('0', flex: 2),
                _toucheChiffreAutre('.'),
                _toucheFonctionAutre('', () {}, vide: true),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _toucheUnite(
    String label,
    String valeur,
    String actuel,
    ValueChanged<String> onChanged,
  ) {
    final actif = actuel == valeur;
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: ElevatedButton(
          key: ValueKey('touche_unite_$valeur'),
          onPressed: () => onChanged(valeur),
          style: ElevatedButton.styleFrom(
            backgroundColor: actif ? _boutonFonction : _boutonChiffreBg,
            foregroundColor: actif
                ? _texteSur(_boutonFonction)
                : _boutonChiffreTexte,
            padding: EdgeInsets.zero,
            side: actif ? null : const BorderSide(color: _boutonChiffreBorder),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          child: Text(
            label,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
          ),
        ),
      ),
    );
  }

  Widget _toucheChiffreAutre(String chiffre, {int flex = 1}) {
    return Expanded(
      flex: flex,
      child: Padding(
        padding: const EdgeInsets.all(3),
        child: ElevatedButton(
          key: ValueKey('touche_$chiffre'),
          onPressed: () => _appuyerChiffreAutre(chiffre),
          style: ElevatedButton.styleFrom(
            backgroundColor: _boutonChiffreBg,
            foregroundColor: _boutonChiffreTexte,
            side: const BorderSide(color: _boutonChiffreBorder),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          child: Text(
            chiffre,
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w600),
          ),
        ),
      ),
    );
  }

  Widget _toucheFonctionAutre(
    String label,
    VoidCallback onTap, {
    bool fonction = false,
    bool claire = false,
    bool effacer = false,
    bool vide = false,
  }) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.all(3),
        child: ElevatedButton(
          key: vide ? null : ValueKey('touche_$label'),
          onPressed: vide ? null : onTap,
          style: ElevatedButton.styleFrom(
            backgroundColor: vide
                ? Colors.transparent
                : fonction
                ? _boutonFonction
                : effacer
                ? _boutonEffacer
                : claire
                ? _boutonChiffreBg
                : _boutonOperateur,
            foregroundColor: claire
                ? _boutonChiffreTexte
                : fonction
                ? _texteSur(_boutonFonction)
                : effacer
                ? _texteClaire
                : _texteSur(_boutonOperateur),
            side: (claire && !vide)
                ? const BorderSide(color: _boutonChiffreBorder)
                : null,
            elevation: vide ? 0 : 1,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          child: Text(
            label,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
          ),
        ),
      ),
    );
  }
}
