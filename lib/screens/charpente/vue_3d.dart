import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../charpente/geometrie.dart';
import '../../charpente/scene.dart';
import '../../charpente/vue3d_core.dart';
import '../../services/theme_compagnie.dart';

/// Couches du plancher : 0 aucune, 1 solives, 2 + sous-plancher.
/// Couches des murs : 0 aucune, 1 ossature, 2 + feuilles, 3 + membrane,
/// 4 + fourrures, 5 + revêtement.
const _libellesPlancher = ['Aucun', 'Solives', '+ Sous-plancher'];
const _libellesMurs = [
  'Aucun',
  'Ossature',
  '+ Feuilles',
  '+ Membrane',
  '+ Fourrures',
  '+ Revêtement',
];

const _calquesPlancher = [Calque.solives, Calque.sousPlancher];
const _calquesMurs = [
  Calque.ossature,
  Calque.panneaux,
  Calque.membrane,
  Calque.fourrures,
  Calque.revetement,
];

Color _couleurDe(Matiere m) => switch (m) {
  Matiere.bois => const Color(0xFFD8B27A),
  Matiere.rive => const Color(0xFFC79A5C),
  Matiere.linteau => const Color(0xFFB27C3E),
  Matiere.sousPlancher => const Color(0xFFE6CC98),
  Matiere.osb => const Color(0xFFCDAA6C),
  Matiere.isolant => const Color(0xFFA9BCCB),
  Matiere.membrane => const Color(0xFFF1F3F5),
  Matiere.fourrure => const Color(0xFFE2C79B),
  Matiere.revetement => const Color(0xFF8099AD),
};

Color _ombre(Color base, double intensite) => Color.fromARGB(
  255,
  (((base.r * 255.0).round()) * intensite).round().clamp(0, 255),
  (((base.g * 255.0).round()) * intensite).round().clamp(0, 255),
  (((base.b * 255.0).round()) * intensite).round().clamp(0, 255),
);

/// Vue 3D d'une scène : rotation à un doigt, zoom et déplacement à deux
/// doigts (molette sur ordinateur), couches, cotes, fiche d'une pièce au toucher.
///
/// Le geste prend toute la place dans la zone de dessin (le défilement de la
/// page et le changement d'onglet ne s'en mêlent pas) : la vue 3D complète est
/// donc placée dans une zone qui ne défile pas.
class Vue3D extends StatefulWidget {
  final Scene scene;

  /// Avec les contrôles (couches, cotes, vues) et la fiche des pièces.
  final bool controles;

  /// Hauteur de la zone de dessin ; null : toute la place disponible.
  final double? hauteur;

  /// Faux : image fixe (aperçu dans un formulaire qui défile) ; un toucher
  /// appelle [onTap].
  final bool interactif;
  final VoidCallback? onTap;

  const Vue3D({
    super.key,
    required this.scene,
    this.controles = true,
    this.hauteur,
    this.interactif = true,
    this.onTap,
  });

  @override
  State<Vue3D> createState() => _Vue3DState();
}

/// Reconnaît le geste (rotation, pincement) dès le premier contact : l'arène
/// des gestes lui donne la victoire avant le défilement ou le balayage d'onglet.
class _GesteImmediat extends ScaleGestureRecognizer {
  @override
  void addAllowedPointer(PointerDownEvent event) {
    super.addAllowedPointer(event);
    resolve(GestureDisposition.accepted);
  }
}

class _Vue3DState extends State<Vue3D> {
  Camera? _camera;
  Size _taille = Size.zero;
  Scene? _sceneAjustee;
  double _echelleAjustee = 1;

  int _etapePlancher = 2;
  int _etapeMurs = 5;
  bool _cotes = false;
  String? _groupe;

  // Geste en cours.
  double _echelleDebut = 1;
  Pt _decalageDebut = const Pt(0, 0);
  Offset _focaleDebut = Offset.zero;
  Offset _positionDebut = Offset.zero;
  double _deplacement = 0;
  int _maxDoigts = 1;
  DateTime _heureDebut = DateTime.now();
  DateTime? _dernierToucher;

  // Ordre d'affichage mis en mémoire : il ne dépend que de l'angle de vue et des
  // pièces visibles.
  List<Solide> _visibles = const [];
  List<int> _ordre = const [];
  double _ordreAzimut = double.nan;
  double _ordreElevation = double.nan;

  @override
  void didUpdateWidget(Vue3D old) {
    super.didUpdateWidget(old);
    if (!identical(old.scene, widget.scene)) {
      // Nouvelle scène : cadrée à nouveau (voir _cameraPour), même angle de vue.
      _groupe = null;
      _ordre = const [];
    }
  }

  bool _estVisible(Calque c) {
    final p = _calquesPlancher.indexOf(c);
    if (p >= 0) {
      return p < _etapePlancher;
    }
    final m = _calquesMurs.indexOf(c);
    return m >= 0 && m < _etapeMurs;
  }

  void _recalculerVisibles() {
    _visibles = [
      for (final s in widget.scene.solides)
        if (_estVisible(s.calque)) s,
    ];
    _ordre = const [];
  }

  Camera _cameraPour(Size taille) {
    var c = _camera;
    if (c == null ||
        taille != _taille ||
        !identical(_sceneAjustee, widget.scene)) {
      final az = c?.azimut ?? -0.6;
      final el = c?.elevation ?? 0.55;
      c = Camera.pourScene(
        widget.scene,
        taille.width,
        taille.height,
        azimut: az,
        elevation: el,
      );
      _echelleAjustee = c.echelle;
      _taille = taille;
      _sceneAjustee = widget.scene;
      _camera = c;
      _recalculerVisibles();
    }
    return c;
  }

  void _vue(double azimut, double elevation) {
    final c = _camera;
    if (c == null) {
      return;
    }
    setState(() {
      _camera = Camera.pourScene(
        widget.scene,
        _taille.width,
        _taille.height,
        azimut: azimut,
        elevation: elevation,
      );
      _echelleAjustee = _camera!.echelle;
      _ordre = const [];
    });
  }

  void _zoomer(double facteur, Offset focale) {
    final c = _camera;
    if (c == null) {
      return;
    }
    final e = (c.echelle * facteur).clamp(
      _echelleAjustee * 0.2,
      _echelleAjustee * 30,
    );
    final k = e / c.echelle;
    final centre = Offset(_taille.width / 2, _taille.height / 2);
    final f = focale - centre;
    setState(() {
      _camera = c.avec(
        echelle: e,
        decalage: Pt(
          f.dx - (f.dx - c.decalage.x) * k,
          f.dy - (f.dy - c.decalage.y) * k,
        ),
      );
    });
  }

  void _toucher(Offset p) {
    final c = _camera;
    if (c == null) {
      return;
    }
    final impact = choisir(
      _visibles,
      c,
      Pt(p.dx, p.dy),
      _taille.width,
      _taille.height,
    );
    setState(() => _groupe = impact?.solide.groupe);
  }

  void _debutGeste(ScaleStartDetails d) {
    final c = _camera;
    if (c == null) {
      return;
    }
    _echelleDebut = c.echelle;
    _decalageDebut = c.decalage;
    _focaleDebut = d.localFocalPoint;
    _positionDebut = d.localFocalPoint;
    _deplacement = 0;
    _maxDoigts = d.pointerCount;
    _heureDebut = DateTime.now();
  }

  void _majGeste(ScaleUpdateDetails d) {
    final c = _camera;
    if (c == null) {
      return;
    }
    _maxDoigts = math.max(_maxDoigts, d.pointerCount);
    _deplacement = math.max(
      _deplacement,
      (d.localFocalPoint - _positionDebut).distance,
    );
    if (d.pointerCount >= 2) {
      final e = (_echelleDebut * d.scale).clamp(
        _echelleAjustee * 0.2,
        _echelleAjustee * 30,
      );
      final k = e / _echelleDebut;
      final centre = Offset(_taille.width / 2, _taille.height / 2);
      final f0 = _focaleDebut - centre;
      final pan = d.localFocalPoint - _focaleDebut;
      setState(() {
        _camera = c.avec(
          echelle: e,
          decalage: Pt(
            f0.dx - (f0.dx - _decalageDebut.x) * k + pan.dx,
            f0.dy - (f0.dy - _decalageDebut.y) * k + pan.dy,
          ),
        );
      });
    } else if (_deplacement > 4) {
      setState(() {
        _camera = c.avec(
          azimut: c.azimut - d.focalPointDelta.dx * 0.01,
          elevation: (c.elevation + d.focalPointDelta.dy * 0.01).clamp(
            0.05,
            math.pi / 2,
          ),
        );
      });
    }
  }

  /// Un doigt posé puis levé sans bouger : toucher (pièce) ; deux touchers
  /// rapprochés : retour à la vue de départ.
  void _finGeste(ScaleEndDetails d) {
    final bref = DateTime.now().difference(_heureDebut).inMilliseconds < 500;
    if (_maxDoigts == 1 && _deplacement < 10 && bref) {
      final maintenant = DateTime.now();
      final dernier = _dernierToucher;
      if (dernier != null &&
          maintenant.difference(dernier).inMilliseconds < 350) {
        _dernierToucher = null;
        _vue(-0.6, 0.55);
      } else {
        _dernierToucher = maintenant;
        _toucher(_positionDebut);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scene = widget.scene;
    if (scene.estVide) {
      final vide = Container(
        alignment: Alignment.center,
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: const Text(
          'Rien à afficher : complétez le plancher ou les murs.',
        ),
      );
      return widget.hauteur == null
          ? vide
          : SizedBox(height: widget.hauteur, child: vide);
    }
    final calques = scene.parCalque;
    final aPlancher = _calquesPlancher.any(calques.containsKey);
    final aMurs = _calquesMurs.any(calques.containsKey);
    final info = _groupe == null ? null : scene.infos[_groupe];

    final dessin = LayoutBuilder(
      builder: (context, contraintes) {
        final taille = Size(contraintes.maxWidth, contraintes.maxHeight);
        final camera = _cameraPour(taille);
        if (_ordre.isEmpty ||
            _ordreAzimut != camera.azimut ||
            _ordreElevation != camera.elevation) {
          _ordre = ordreAffichage(_visibles, camera);
          _ordreAzimut = camera.azimut;
          _ordreElevation = camera.elevation;
        }
        final peinture = CustomPaint(
          size: taille,
          painter: _Peintre(
            solides: _visibles,
            ordre: _ordre,
            camera: camera,
            groupeChoisi: _groupe,
            cotes: _cotes
                ? [
                    for (final c in scene.cotes)
                      if (_estVisible(c.calque)) c,
                  ]
                : const [],
            fond: Theme.of(context).brightness == Brightness.dark
                ? const Color(0xFF22262B)
                : const Color(0xFFF3EFE6),
            accent: ThemeCompagnie.accentDe(context),
            texte: Theme.of(context).colorScheme.onSurface,
          ),
        );
        if (!widget.interactif) {
          return ClipRect(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: widget.onTap,
              child: peinture,
            ),
          );
        }
        return ClipRect(
          child: Listener(
            onPointerSignal: (e) {
              if (e is PointerScrollEvent) {
                _zoomer(math.exp(-e.scrollDelta.dy / 400), e.localPosition);
              }
            },
            child: RawGestureDetector(
              behavior: HitTestBehavior.opaque,
              gestures: {
                _GesteImmediat:
                    GestureRecognizerFactoryWithHandlers<_GesteImmediat>(
                      _GesteImmediat.new,
                      (r) {
                        r
                          ..onStart = _debutGeste
                          ..onUpdate = _majGeste
                          ..onEnd = _finGeste;
                      },
                    ),
              },
              child: peinture,
            ),
          ),
        );
      },
    );
    final zone = widget.hauteur == null
        ? dessin
        : SizedBox(height: widget.hauteur, child: dessin);

    if (!widget.controles) {
      return zone;
    }

    final bornee = widget.hauteur == null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (aPlancher)
          _Etapes(
            titre: 'Plancher',
            libelles: _libellesPlancher,
            valeur: _etapePlancher,
            onChange: (v) => setState(() {
              _etapePlancher = v;
              _groupe = null;
              _recalculerVisibles();
            }),
          ),
        if (aMurs)
          _Etapes(
            titre: 'Murs',
            libelles: _libellesMurs,
            valeur: _etapeMurs,
            onChange: (v) => setState(() {
              _etapeMurs = v;
              _groupe = null;
              _recalculerVisibles();
            }),
          ),
        const SizedBox(height: 4),
        Row(
          children: [
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    ActionChip(
                      key: const ValueKey('vue_3quarts'),
                      avatar: const Icon(Icons.view_in_ar, size: 16),
                      label: const Text('3D'),
                      onPressed: () => _vue(-0.6, 0.55),
                    ),
                    const SizedBox(width: 6),
                    ActionChip(
                      key: const ValueKey('vue_dessus'),
                      avatar: const Icon(Icons.crop_square, size: 16),
                      label: const Text('Dessus'),
                      onPressed: () => _vue(-math.pi / 2, math.pi / 2),
                    ),
                    const SizedBox(width: 6),
                    ActionChip(
                      key: const ValueKey('vue_face'),
                      avatar: const Icon(Icons.border_bottom, size: 16),
                      label: const Text('Face'),
                      onPressed: () => _vue(-math.pi / 2, 0.05),
                    ),
                  ],
                ),
              ),
            ),
            IconButton(
              key: const ValueKey('vue_legende'),
              tooltip: 'Légende des couleurs',
              icon: const Icon(Icons.palette_outlined),
              onPressed: () => showDialog<void>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Légende'),
                  content: const LegendeVue3D(),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('Fermer'),
                    ),
                  ],
                ),
              ),
            ),
            const Text('Cotes'),
            Switch(
              key: const ValueKey('vue_cotes'),
              value: _cotes,
              onChanged: (v) => setState(() => _cotes = v),
            ),
          ],
        ),
        if (bornee)
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: zone,
            ),
          )
        else
          ClipRRect(borderRadius: BorderRadius.circular(8), child: zone),
        const SizedBox(height: 6),
        if (info != null)
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 190),
            child: SingleChildScrollView(
              child: _Fiche(
                info: info,
                onFermer: () => setState(() => _groupe = null),
              ),
            ),
          )
        else
          Text(
            'Touchez une pièce pour voir sa mesure et sa coupe. Un doigt : '
            'tourner ; deux doigts : zoom et déplacement ; double toucher : '
            'vue de départ.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
      ],
    );
  }
}

/// Couleurs de la vue 3D.
class LegendeVue3D extends StatelessWidget {
  const LegendeVue3D({super.key});

  @override
  Widget build(BuildContext context) {
    const items = [
      (Matiere.bois, 'Solives, montants, entremises'),
      (Matiere.rive, 'Solives de rive'),
      (Matiere.linteau, 'Linteaux'),
      (Matiere.sousPlancher, 'Sous-plancher'),
      (Matiere.osb, 'Feuilles des murs (OSB)'),
      (Matiere.isolant, 'OSB isolant R-4 (Isobrace)'),
      (Matiere.membrane, 'Membrane'),
      (Matiere.fourrure, 'Fourrures'),
      (Matiere.revetement, 'Revêtement'),
    ];
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final (m, t) in items)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              children: [
                Container(
                  width: 16,
                  height: 16,
                  decoration: BoxDecoration(
                    color: _couleurDe(m),
                    border: Border.all(color: Colors.black26),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(child: Text(t)),
              ],
            ),
          ),
      ],
    );
  }
}

class _Etapes extends StatelessWidget {
  final String titre;
  final List<String> libelles;
  final int valeur;
  final ValueChanged<int> onChange;
  const _Etapes({
    required this.titre,
    required this.libelles,
    required this.valeur,
    required this.onChange,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          SizedBox(
            width: 64,
            child: Text(
              titre,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Wrap(
                spacing: 6,
                children: [
                  for (var i = 0; i < libelles.length; i++)
                    ChoiceChip(
                      key: ValueKey('etape_${titre}_$i'),
                      label: Text(libelles[i]),
                      selected: valeur == i,
                      onSelected: (_) => onChange(i),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Fiche extends StatelessWidget {
  final InfoPiece info;
  final VoidCallback onFermer;
  const _Fiche({required this.info, required this.onFermer});

  @override
  Widget build(BuildContext context) {
    return Card(
      key: const ValueKey('vue_fiche'),
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    info.titre,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Fermer',
                  icon: const Icon(Icons.close),
                  onPressed: onFermer,
                ),
              ],
            ),
            for (final l in info.lignes)
              Padding(
                padding: const EdgeInsets.only(bottom: 2, right: 8),
                child: Text(l),
              ),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// Dessin
// =============================================================================

class _Peintre extends CustomPainter {
  final List<Solide> solides;
  final List<int> ordre;
  final Camera camera;
  final String? groupeChoisi;
  final List<Cote> cotes;
  final Color fond;
  final Color accent;
  final Color texte;

  _Peintre({
    required this.solides,
    required this.ordre,
    required this.camera,
    required this.groupeChoisi,
    required this.cotes,
    required this.fond,
    required this.accent,
    required this.texte,
  });

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = fond);
    final e = camera.oeil;
    final trait = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.6
      ..strokeJoin = StrokeJoin.round
      ..color = const Color(0x66000000);
    final remplissage = Paint()
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;
    final joint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8;
    final choisi = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..strokeJoin = StrokeJoin.round
      ..color = accent;
    final voile = Paint()
      ..style = PaintingStyle.fill
      ..color = accent.withValues(alpha: 0.35);

    for (final i in ordre) {
      final s = solides[i];
      final base = _couleurDe(s.matiere);
      final estChoisi = groupeChoisi != null && s.groupe == groupeChoisi;
      for (final f in s.faces) {
        if (f.normale.dot(e) <= 1e-9) {
          continue;
        }
        final chemin = Path()..fillType = PathFillType.evenOdd;
        for (final b in f.boucles) {
          for (var k = 0; k < b.length; k++) {
            final p = camera.projeter(b[k], size.width, size.height);
            if (k == 0) {
              chemin.moveTo(p.x, p.y);
            } else {
              chemin.lineTo(p.x, p.y);
            }
          }
          chemin.close();
        }
        final couleur = _ombre(base, eclairage(f, camera));
        remplissage.color = couleur;
        canvas.drawPath(chemin, remplissage);
        // Même couleur en trait fin : pas de fente entre deux faces voisines.
        joint.color = couleur;
        canvas.drawPath(chemin, joint);
        canvas.drawPath(chemin, trait);
        if (estChoisi) {
          canvas.drawPath(chemin, voile);
          canvas.drawPath(chemin, choisi);
        }
      }
    }

    for (final c in cotes) {
      final a = camera.projeter(c.a, size.width, size.height);
      final b = camera.projeter(c.b, size.width, size.height);
      final ligne = Paint()
        ..color = texte.withValues(alpha: 0.85)
        ..strokeWidth = 1.2;
      canvas.drawLine(Offset(a.x, a.y), Offset(b.x, b.y), ligne);
      for (final p in [a, b]) {
        canvas.drawCircle(Offset(p.x, p.y), 2.2, Paint()..color = ligne.color);
      }
      final tp = TextPainter(
        text: TextSpan(
          text: c.texte,
          style: TextStyle(
            color: texte,
            fontSize: 11,
            fontWeight: FontWeight.w600,
            backgroundColor: fond.withValues(alpha: 0.85),
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(
        canvas,
        Offset((a.x + b.x) / 2 - tp.width / 2, (a.y + b.y) / 2 - tp.height / 2),
      );
    }
  }

  @override
  bool shouldRepaint(_Peintre old) =>
      old.camera != camera ||
      old.ordre != ordre ||
      old.groupeChoisi != groupeChoisi ||
      old.cotes.length != cotes.length ||
      old.fond != fond;
}
