import 'dart:math';

import 'package:flutter/material.dart';

enum _Mode { charpente, beton, conversion, materiaux }

const Color _casing = Color(0xFFEAE2D0);
const Color _lcdBg = Color(0xFFB7C4A8);
const Color _texteLCD = Color(0xFF1E2E20);
const Color _boutonChiffreBg = Color(0xFFDDD2B8);
const Color _boutonChiffreBorder = Color(0xFFB8AC90);
const Color _boutonChiffreTexte = Color(0xFF2C2A22);
const Color _boutonOperateur = Color(0xFF2F4A34);
const Color _boutonRouille = Color(0xFF8A3B24);
const Color _boutonEffacer = Color(0xFF6B2A1C);
const Color _texteClaire = Color(0xFFEAE2D0);

class CalculatriceScreen extends StatefulWidget {
  const CalculatriceScreen({super.key});

  @override
  State<CalculatriceScreen> createState() => _CalculatriceScreenState();
}

class _CalculatriceScreenState extends State<CalculatriceScreen> {
  _Mode _mode = _Mode.charpente;

  String _entreeCharpente = '';
  double? _feet;
  double? _inches;
  int? _fracNum;
  int? _fracDen;
  bool _enAttenteDenominateur = false;
  bool _uniteUtiliseeDansFormule = false;

  double? _accumulateur;
  String? _operateurEnAttente;
  String _formulePrecedente = '';
  double? _resultatFinal;
  bool _resultatFormuleEnPieds = true;

  final List<(double?, String?)> _pileParentheses = [];

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
    return _uniteUtiliseeDansFormule
        ? _formatPiedsPoucesFraction(v)
        : _formatDecimal(v);
  }

  /// Juste après « ) », un nombre ou une « ( » tapé sans opérateur multiplie
  /// le groupe, comme en mathématiques : (2+3)4 = 20 et (2+3)(1+1) = 10.
  void _multiplicationImpliciteApresParenthese() {
    if (_accumulateur != null &&
        _operateurEnAttente == null &&
        _formulePrecedente.trimRight().endsWith(')')) {
      _operateurEnAttente = '×';
      _formulePrecedente += '× ';
    }
  }

  void _appuyerChiffreCharpente(String chiffre) {
    setState(() {
      if (_resultatFinal != null) {
        _resultatFinal = null;
        _formulePrecedente = '';
        _accumulateur = null;
        _operateurEnAttente = null;
        _pileParentheses.clear();
        _uniteUtiliseeDansFormule = false;
        _conversionExtra = null;
      }
      if (_operandeVide) _multiplicationImpliciteApresParenthese();
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
      }
    });
  }

  void _toutEffacerCharpente() {
    setState(() {
      _entreeCharpente = '';
      _feet = null;
      _inches = null;
      _fracNum = null;
      _fracDen = null;
      _enAttenteDenominateur = false;
      _accumulateur = null;
      _operateurEnAttente = null;
      _formulePrecedente = '';
      _resultatFinal = null;
      _rise = null;
      _run = null;
      _diag = null;
      _pileParentheses.clear();
      _uniteUtiliseeDansFormule = false;
      _conversionExtra = null;
    });
  }

  void _reinitialiserSiResultat() {
    if (_resultatFinal != null) {
      _resultatFinal = null;
      _formulePrecedente = '';
      _accumulateur = null;
      _operateurEnAttente = null;
      _pileParentheses.clear();
      _conversionExtra = null;
    }
  }

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

  double _appliquerOperation(double a, double b, String op) {
    switch (op) {
      case '+':
        return a + b;
      case '-':
        return a - b;
      case '×':
        return a * b;
      case '÷':
        return b == 0 ? 0 : a / b;
      default:
        return b;
    }
  }

  void _appuyerOperateurCharpente(String op) {
    setState(() {
      _conversionExtra = null;
      if (_resultatFinal != null) {
        _accumulateur = _resultatFinal;
        _formulePrecedente = '${_formatResultat(_accumulateur!)} $op ';
        _resultatFinal = null;
        _operateurEnAttente = op;
        _feet = null;
        _inches = null;
        _fracNum = null;
        _fracDen = null;
        _enAttenteDenominateur = false;
        _entreeCharpente = '';
        return;
      }

      _finaliserFraction();

      if (_operandeVide) {
        if (_operateurEnAttente != null &&
            _formulePrecedente.trim().isNotEmpty) {
          // Remplace l'opérateur qui vient d'être tapé.
          final trimmed = _formulePrecedente.trimRight();
          final sansOperateur = trimmed
              .substring(0, trimmed.length - 1)
              .trimRight();
          _formulePrecedente = '$sansOperateur $op ';
          _operateurEnAttente = op;
        } else if (_accumulateur != null) {
          // Juste après « ) » : le résultat du groupe devient l'opérande de
          // gauche. (Sans ce cas, l'opérateur était ignoré : (56"×2)+56'
          // donnait 56'.)
          _formulePrecedente += '$op ';
          _operateurEnAttente = op;
        }
        return;
      }

      final valeur = _valeurOperandeCourant();
      final texteOperande = _texteOperandeEnCours().trim();

      if (_accumulateur != null && _operateurEnAttente != null) {
        _accumulateur = _appliquerOperation(
          _accumulateur!,
          valeur,
          _operateurEnAttente!,
        );
      } else {
        _accumulateur = valeur;
      }
      _formulePrecedente += '$texteOperande $op ';
      _operateurEnAttente = op;
      _feet = null;
      _inches = null;
      _fracNum = null;
      _fracDen = null;
      _enAttenteDenominateur = false;
      _entreeCharpente = '';
    });
  }

  void _ouvrirParenthese() {
    setState(() {
      _finaliserFraction();
      _reinitialiserSiResultat();
      if (_operandeVide) {
        _multiplicationImpliciteApresParenthese();
      } else {
        // Nombre suivi de « ( » : multiplication implicite, 2(3+1) = 8.
        // (Sans ce cas, le nombre tapé avant la parenthèse était perdu.)
        final valeur = _valeurOperandeCourant();
        _accumulateur = _accumulateur != null && _operateurEnAttente != null
            ? _appliquerOperation(_accumulateur!, valeur, _operateurEnAttente!)
            : valeur;
        _formulePrecedente += '${_texteOperandeEnCours().trim()} × ';
        _operateurEnAttente = '×';
      }
      _pileParentheses.add((_accumulateur, _operateurEnAttente));
      _formulePrecedente += '( ';
      _accumulateur = null;
      _operateurEnAttente = null;
      _feet = null;
      _inches = null;
      _fracNum = null;
      _fracDen = null;
      _enAttenteDenominateur = false;
      _entreeCharpente = '';
      _resultatFinal = null;
      _conversionExtra = null;
    });
  }

  void _fermerParenthese() {
    if (_pileParentheses.isEmpty) return;
    setState(() {
      _finaliserFraction();
      final texteOperande = _texteOperandeEnCours().trim();
      double valeurInterieure;
      if (!_operandeVide) {
        final v = _valeurOperandeCourant();
        if (_accumulateur != null && _operateurEnAttente != null) {
          valeurInterieure = _appliquerOperation(
            _accumulateur!,
            v,
            _operateurEnAttente!,
          );
        } else {
          valeurInterieure = v;
        }
      } else if (_accumulateur != null) {
        valeurInterieure = _accumulateur!;
      } else {
        valeurInterieure = 0;
      }

      _formulePrecedente += texteOperande.isNotEmpty
          ? '$texteOperande) '
          : ') ';

      final frame = _pileParentheses.removeLast();
      final accExterieur = frame.$1;
      final opExterieur = frame.$2;
      double resultatGroupe = valeurInterieure;
      if (opExterieur != null) {
        resultatGroupe = _appliquerOperation(
          accExterieur ?? 0,
          resultatGroupe,
          opExterieur,
        );
      }
      _accumulateur = resultatGroupe;
      _operateurEnAttente = null;
      _feet = null;
      _inches = null;
      _fracNum = null;
      _fracDen = null;
      _enAttenteDenominateur = false;
      _entreeCharpente = '';
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
      _finaliserFraction();
      double? resultat;
      String formuleAffichee = (_formulePrecedente + _texteOperandeEnCours())
          .trim();

      if (!_operandeVide) {
        final valeur = _valeurOperandeCourant();
        if (_accumulateur != null && _operateurEnAttente != null) {
          resultat = _appliquerOperation(
            _accumulateur!,
            valeur,
            _operateurEnAttente!,
          );
        } else {
          resultat = valeur;
        }
      } else if (_accumulateur != null) {
        resultat = _accumulateur;
        formuleAffichee = _formulePrecedente.trim();
      } else {
        return;
      }

      if (formuleAffichee.isNotEmpty) {
        _ajouterHistorique(formuleAffichee, resultat!);
      }

      _resultatFinal = resultat;
      _formulePrecedente = '';
      _accumulateur = null;
      _operateurEnAttente = null;
      _feet = null;
      _inches = null;
      _fracNum = null;
      _fracDen = null;
      _enAttenteDenominateur = false;
      _entreeCharpente = '';
      _pileParentheses.clear();
    });
  }

  double? _valeurActuelle() {
    _finaliserFraction();
    if (_resultatFinal != null) return _resultatFinal;
    if (!_operandeVide) {
      final v = _valeurOperandeCourant();
      if (_accumulateur != null && _operateurEnAttente != null) {
        return _appliquerOperation(_accumulateur!, v, _operateurEnAttente!);
      }
      return v;
    }
    return _accumulateur;
  }

  void _appliquerRacine() {
    setState(() {
      final v = _valeurActuelle();
      if (v == null || v < 0) return;
      final resultat = sqrt(v);
      _ajouterHistorique('√(${_formatResultat(v)})', resultat);
      _resultatFinal = resultat;
      _formulePrecedente = '';
      _accumulateur = null;
      _operateurEnAttente = null;
      _feet = null;
      _inches = null;
      _fracNum = null;
      _fracDen = null;
      _entreeCharpente = '';
      _pileParentheses.clear();
      _conversionExtra = null;
    });
  }

  void _appliquerPourcent() {
    setState(() {
      final v = _valeurActuelle();
      if (v == null) return;
      final resultat = v / 100;
      _ajouterHistorique('${_formatResultat(v)} %', resultat);
      _resultatFinal = resultat;
      _formulePrecedente = '';
      _accumulateur = null;
      _operateurEnAttente = null;
      _feet = null;
      _inches = null;
      _fracNum = null;
      _fracDen = null;
      _entreeCharpente = '';
      _pileParentheses.clear();
      _conversionExtra = null;
    });
  }

  void _appliquerCarre() {
    setState(() {
      final v = _valeurActuelle();
      if (v == null) return;
      final resultat = v * v;
      _ajouterHistorique('(${_formatResultat(v)})²', resultat);
      _resultatFinal = resultat;
      _formulePrecedente = '';
      _accumulateur = null;
      _operateurEnAttente = null;
      _feet = null;
      _inches = null;
      _fracNum = null;
      _fracDen = null;
      _entreeCharpente = '';
      _pileParentheses.clear();
      _conversionExtra = null;
    });
  }

  void _appliquerCube() {
    setState(() {
      final v = _valeurActuelle();
      if (v == null) return;
      final resultat = v * v * v;
      _ajouterHistorique('(${_formatResultat(v)})³', resultat);
      _resultatFinal = resultat;
      _formulePrecedente = '';
      _accumulateur = null;
      _operateurEnAttente = null;
      _feet = null;
      _inches = null;
      _fracNum = null;
      _fracDen = null;
      _entreeCharpente = '';
      _pileParentheses.clear();
      _conversionExtra = null;
    });
  }

  void _appliquerConversion() {
    setState(() {
      final v = _valeurActuelle();
      if (v == null) return;
      final metres = v * 0.0254;
      final cm = metres * 100;
      _ajouterHistorique('Conv(${_formatDecimal(v)}")', v);
      _resultatFinal = v;
      _uniteUtiliseeDansFormule = true;
      _formulePrecedente = '';
      _accumulateur = null;
      _operateurEnAttente = null;
      _feet = null;
      _inches = null;
      _fracNum = null;
      _fracDen = null;
      _entreeCharpente = '';
      _pileParentheses.clear();
      _conversionExtra = [
        '${_formatPoucesFraction(v)} po',
        '${metres.toStringAsFixed(3)} m',
        '${cm.toStringAsFixed(1)} cm',
      ];
    });
  }

  void _memoirePlus() {
    final v = _valeurActuelle();
    if (v == null) return;
    setState(() => _memoire = (_memoire ?? 0) + v);
  }

  void _memoireRappel() {
    if (_memoire == null) return;
    setState(() {
      _resultatFinal = _memoire;
      _formulePrecedente = '';
      _accumulateur = null;
      _operateurEnAttente = null;
      _feet = null;
      _inches = null;
      _fracNum = null;
      _fracDen = null;
      _entreeCharpente = '';
      _pileParentheses.clear();
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
      _accumulateur = null;
      _operateurEnAttente = null;
      _formulePrecedente = '';
      _resultatFinal = null;
      _pileParentheses.clear();
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

  // ==================== BÉTON / CONVERSION / MATÉRIAUX ====================

  int _etape = 0;
  String _saisie = '';
  final List<double> _valeurs = [];
  String? _resultatTitre;
  List<String> _resultatLignes = [];
  bool _resultatAutreEnPieds = true;
  double? _resultatAutreLineaire;

  String _uniteBeton = 'pi';
  String _uniteConversion = 'pi';

  List<String> get _etapes {
    switch (_mode) {
      case _Mode.beton:
        return ['Longueur', 'Largeur', 'Épaisseur'];
      case _Mode.conversion:
        return ['Valeur'];
      case _Mode.materiaux:
        return ['Surface à couvrir (pi²)'];
      case _Mode.charpente:
        return [];
    }
  }

  bool get _termine => _etape >= _etapes.length;

  void _choisirMode(_Mode mode) {
    setState(() {
      _mode = mode;
      _etape = 0;
      _saisie = '';
      _valeurs.clear();
      _resultatTitre = null;
      _resultatLignes = [];
      _resultatAutreLineaire = null;
      _uniteBeton = 'pi';
      _uniteConversion = 'pi';
    });
  }

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
      _resultatAutreLineaire = null;
    });
  }

  double _convertirBeton(double valeurBrute) {
    final estEpaisseur = _etape == 2;
    if (estEpaisseur) {
      return _uniteBeton == 'pi' ? valeurBrute * 12 : valeurBrute;
    } else {
      return _uniteBeton == 'po' ? valeurBrute / 12 : valeurBrute;
    }
  }

  double _convertirConversionEnPouces(double valeurBrute) {
    switch (_uniteConversion) {
      case 'pi':
        return valeurBrute * 12;
      case 'm':
        return valeurBrute / 0.0254;
      case 'cm':
        return valeurBrute / 2.54;
      case 'mm':
        return valeurBrute / 25.4;
      case 'po':
      default:
        return valeurBrute;
    }
  }

  void _entreeAutre() {
    if (_termine) return;
    final valeurBrute = double.tryParse(_saisie) ?? 0;
    double valeur = valeurBrute;
    if (_mode == _Mode.beton) {
      valeur = _convertirBeton(valeurBrute);
    } else if (_mode == _Mode.conversion) {
      valeur = _convertirConversionEnPouces(valeurBrute);
    }
    setState(() {
      _valeurs.add(valeur);
      _saisie = '';
      _etape++;
      if (_mode == _Mode.beton) {
        _uniteBeton = _etape == 2 ? 'po' : 'pi';
      }
      if (_etape >= _etapes.length) {
        _calculerResultatAutre();
      }
    });
  }

  void _calculerResultatAutre() {
    switch (_mode) {
      case _Mode.beton:
        final lFeet = _valeurs[0];
        final wFeet = _valeurs[1];
        final eInches = _valeurs[2];
        final eFeet = eInches / 12;
        final volumeM3 = (lFeet * wFeet * eFeet) * 0.0283168;
        final sacs = volumeM3 / 0.02;
        _resultatTitre = 'Résultat béton';
        _resultatLignes = [
          'Volume : ${volumeM3.toStringAsFixed(3)} m³',
          'Sacs de béton (30kg) : ${sacs.ceil()}',
        ];
        _resultatAutreLineaire = null;
        break;
      case _Mode.conversion:
        final totalPouces = _valeurs[0];
        final metres = totalPouces * 0.0254;
        _resultatTitre = 'Résultat conversion';
        _resultatLignes = [
          '${metres.toStringAsFixed(3)} m',
          '${(metres * 100).toStringAsFixed(1)} cm',
        ];
        _resultatAutreLineaire = totalPouces;
        _resultatAutreEnPieds = true;
        break;
      case _Mode.materiaux:
        final feuilles = ((_valeurs[0] * 1.1) / 32).ceil();
        _resultatTitre = 'Résultat matériaux';
        _resultatLignes = [
          '$feuilles feuilles de gypse (4x8 pi)',
          '(incluant 10% de perte)',
        ];
        _resultatAutreLineaire = null;
        break;
      case _Mode.charpente:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: _casing,
      child: SafeArea(
        child: Column(
          children: [
            _boutonsMode(),
            const SizedBox(height: 8),
            _mode == _Mode.charpente ? _ecranCharpente() : _ecranAutre(),
            const SizedBox(height: 8),
            Expanded(
              child: _mode == _Mode.charpente
                  ? _clavierCharpente()
                  : _clavierAutre(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _boutonsMode() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _pillule('Charpente', _Mode.charpente),
            _pillule('Béton', _Mode.beton),
            _pillule('Conversion', _Mode.conversion),
            _pillule('Matériaux', _Mode.materiaux),
          ],
        ),
      ),
    );
  }

  Widget _pillule(String label, _Mode mode) {
    final actif = _mode == mode;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: ElevatedButton(
        onPressed: () => _choisirMode(mode),
        style: ElevatedButton.styleFrom(
          backgroundColor: actif ? _boutonRouille : _boutonOperateur,
          foregroundColor: _texteClaire,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
        ),
        child: Text(
          label,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
        ),
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
                      'PITCH ${_pitch!.toStringAsFixed(2)}/12',
                      style: const TextStyle(
                        color: _texteLCD,
                        fontSize: 11,
                        fontFamily: 'monospace',
                        letterSpacing: 1,
                      ),
                    ),
                  if (_memoire != null)
                    const Padding(
                      padding: EdgeInsets.only(left: 8),
                      child: Text(
                        'M',
                        style: TextStyle(
                          color: _texteLCD,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                ],
              ),
              InkWell(
                onTap: _ouvrirHistorique,
                child: const Icon(Icons.history, size: 18, color: _texteLCD),
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
                      ? _formatPiedsPoucesFraction(_diag!)
                      : _formatPoucesFraction(_diag!),
                  style: const TextStyle(
                    color: Color(0xFF3D5A3F),
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
                  ? () => setState(
                      () => _resultatFormuleEnPieds = !_resultatFormuleEnPieds,
                    )
                  : null,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerRight,
                child: Text(
                  _uniteUtiliseeDansFormule
                      ? (_resultatFormuleEnPieds
                            ? _formatPiedsPoucesFraction(_resultatFinal!)
                            : _formatPoucesFraction(_resultatFinal!))
                      : _formatDecimal(_resultatFinal!),
                  style: const TextStyle(
                    color: _texteLCD,
                    fontSize: 38,
                    fontWeight: FontWeight.w700,
                    fontFamily: 'monospace',
                  ),
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
                  style: const TextStyle(
                    color: _texteLCD,
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
                        style: const TextStyle(
                          color: Color(0xFF3D5A3F),
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

  Widget _clavierCharpente() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      child: Column(
        children: [
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _toucheMemoireGrande('RUN', _run, () => _stocker('run')),
                _toucheMemoireGrande('RISE', _rise, () => _stocker('rise')),
                _toucheMemoireDiagGrande(),
                _toucheFonctionGrande(
                  'AC',
                  _toutEffacerCharpente,
                  effacer: true,
                ),
              ],
            ),
          ),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _toucheFonctionGrande('Pi', _committerFeet, claire: true),
                _toucheFonctionGrande('Po', _committerPouces, claire: true),
                _toucheFonctionGrande('/', _committerSeizieme, claire: true),
                _toucheFonctionGrande(
                  '⌫',
                  _effacerDernierCharpente,
                  claire: true,
                ),
              ],
            ),
          ),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _toucheFonctionGrande('(', _ouvrirParenthese, rouille: true),
                _toucheFonctionGrande(')', _fermerParenthese, rouille: true),
                _toucheFonctionGrande('x²', _appliquerCarre, rouille: true),
                _toucheFonctionGrande('x³', _appliquerCube, rouille: true),
              ],
            ),
          ),
          SizedBox(
            height: 32,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _toucheExtraPetite('√x', _appliquerRacine),
                _toucheExtraPetite('%', _appliquerPourcent),
                _toucheExtraPetite('M+', _memoirePlus),
                _toucheExtraPetite('MR', _memoireRappel),
                _toucheExtraPetite('MC', _memoireEffacer),
                _toucheExtraPetite('Conv', _appliquerConversion, rouille: true),
              ],
            ),
          ),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _toucheChiffreGrande('7'),
                _toucheChiffreGrande('8'),
                _toucheChiffreGrande('9'),
                _toucheFonctionGrande(
                  '÷',
                  () => _appuyerOperateurCharpente('÷'),
                  operateur: true,
                ),
              ],
            ),
          ),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _toucheChiffreGrande('4'),
                _toucheChiffreGrande('5'),
                _toucheChiffreGrande('6'),
                _toucheFonctionGrande(
                  '×',
                  () => _appuyerOperateurCharpente('×'),
                  operateur: true,
                ),
              ],
            ),
          ),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _toucheChiffreGrande('1'),
                _toucheChiffreGrande('2'),
                _toucheChiffreGrande('3'),
                _toucheFonctionGrande(
                  '−',
                  () => _appuyerOperateurCharpente('-'),
                  operateur: true,
                ),
              ],
            ),
          ),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _toucheChiffreGrande('0'),
                _toucheChiffreGrande('.'),
                _toucheFonctionGrande(
                  '=',
                  _appuyerEgalCharpente,
                  rouille: true,
                ),
                _toucheFonctionGrande(
                  '+',
                  () => _appuyerOperateurCharpente('+'),
                  operateur: true,
                ),
              ],
            ),
          ),
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
          onPressed: onTap,
          style: ElevatedButton.styleFrom(
            backgroundColor: _boutonRouille,
            foregroundColor: _texteClaire,
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
                  valeur == null ? '—' : _formatPoucesFraction(valeur),
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
          onPressed: () => _stocker('diag'),
          style: ElevatedButton.styleFrom(
            backgroundColor: _boutonRouille,
            foregroundColor: _texteClaire,
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
                  _diag == null ? '—' : _formatPoucesFraction(_diag!),
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
    bool rouille = false,
  }) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.all(3),
        child: ElevatedButton(
          onPressed: onTap,
          style: ElevatedButton.styleFrom(
            backgroundColor: rouille ? _boutonRouille : _boutonOperateur,
            foregroundColor: _texteClaire,
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
    bool rouille = false,
  }) {
    Color bg;
    Color fg;
    if (effacer) {
      bg = _boutonEffacer;
      fg = _texteClaire;
    } else if (rouille) {
      bg = _boutonRouille;
      fg = _texteClaire;
    } else if (operateur) {
      bg = _boutonOperateur;
      fg = _texteClaire;
    } else if (claire) {
      bg = _boutonChiffreBg;
      fg = _boutonChiffreTexte;
    } else {
      bg = _boutonOperateur;
      fg = _texteClaire;
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
    final estLineaire = _resultatAutreLineaire != null && _termine;
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
              _termine
                  ? 'Résultat'
                  : (_etapes.isNotEmpty ? _etapes[_etape] : ''),
              style: const TextStyle(
                color: _texteLCD,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(height: 8),
          if (!_termine)
            Text(
              _saisie.isEmpty ? '0' : _saisie,
              style: const TextStyle(
                color: _texteLCD,
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
                style: const TextStyle(
                  color: _texteLCD,
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
                  style: const TextStyle(
                    color: _texteLCD,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
            if (estLineaire)
              GestureDetector(
                onTap: () => setState(
                  () => _resultatAutreEnPieds = !_resultatAutreEnPieds,
                ),
                child: Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      _resultatAutreEnPieds
                          ? _formatPiedsPoucesFraction(_resultatAutreLineaire!)
                          : _formatPoucesFraction(_resultatAutreLineaire!),
                      style: const TextStyle(
                        color: _texteLCD,
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
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
          if (_mode == _Mode.beton && !_termine) ...[
            SizedBox(
              height: 32,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _toucheUnite(
                    'Pi',
                    'pi',
                    _uniteBeton,
                    (u) => setState(() => _uniteBeton = u),
                  ),
                  _toucheUnite(
                    'Po',
                    'po',
                    _uniteBeton,
                    (u) => setState(() => _uniteBeton = u),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),
          ],
          if (_mode == _Mode.conversion && !_termine) ...[
            SizedBox(
              height: 32,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _toucheUnite(
                    'Pi',
                    'pi',
                    _uniteConversion,
                    (u) => setState(() => _uniteConversion = u),
                  ),
                  _toucheUnite(
                    'Po',
                    'po',
                    _uniteConversion,
                    (u) => setState(() => _uniteConversion = u),
                  ),
                  _toucheUnite(
                    'M',
                    'm',
                    _uniteConversion,
                    (u) => setState(() => _uniteConversion = u),
                  ),
                  _toucheUnite(
                    'CM',
                    'cm',
                    _uniteConversion,
                    (u) => setState(() => _uniteConversion = u),
                  ),
                  _toucheUnite(
                    'MM',
                    'mm',
                    _uniteConversion,
                    (u) => setState(() => _uniteConversion = u),
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
                _toucheFonctionAutre('↵', _entreeAutre, rouille: true),
              ],
            ),
          ),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(flex: 2, child: _toucheChiffreAutre('0')),
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
          onPressed: () => onChanged(valeur),
          style: ElevatedButton.styleFrom(
            backgroundColor: actif ? _boutonRouille : _boutonChiffreBg,
            foregroundColor: actif ? _texteClaire : _boutonChiffreTexte,
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

  Widget _toucheChiffreAutre(String chiffre) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.all(3),
        child: ElevatedButton(
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
    bool rouille = false,
    bool claire = false,
    bool effacer = false,
    bool vide = false,
  }) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.all(3),
        child: ElevatedButton(
          onPressed: vide ? null : onTap,
          style: ElevatedButton.styleFrom(
            backgroundColor: vide
                ? Colors.transparent
                : rouille
                ? _boutonRouille
                : effacer
                ? _boutonEffacer
                : claire
                ? _boutonChiffreBg
                : _boutonOperateur,
            foregroundColor: claire ? _boutonChiffreTexte : _texteClaire,
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
