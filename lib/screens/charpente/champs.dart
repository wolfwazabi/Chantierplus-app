import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../charpente/unites.dart';
import '../../services/preferences.dart';

/// Champ de saisie d'une longueur (en pouces à l'interne) : accepte 10'6", 10-6,
/// 126" ou des mètres, selon le système d'unités choisi. Un nombre seul vaut
/// des pieds en impérial et des mètres en métrique.
class ChampLongueur extends StatefulWidget {
  final String label;

  /// Valeur courante en pouces.
  final double valeur;
  final ValueChanged<double> onChange;

  /// Bornes en pouces (incluses).
  final double min;
  final double max;
  final String? aide;
  final bool? metrique;

  const ChampLongueur({
    super.key,
    required this.label,
    required this.valeur,
    required this.onChange,
    this.min = 0.01,
    this.max = pouceMaxSaisie,
    this.aide,
    this.metrique,
  });

  @override
  State<ChampLongueur> createState() => _ChampLongueurState();
}

class _ChampLongueurState extends State<ChampLongueur> {
  late final TextEditingController _ctrl;
  String? _erreur;

  bool get _metrique => widget.metrique ?? Preferences.estMetrique;

  String _formater(double v) =>
      _metrique ? formatMetrique(v) : formatImperial(v);

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: _formater(widget.valeur));
  }

  @override
  void didUpdateWidget(ChampLongueur old) {
    super.didUpdateWidget(old);
    // Valeur changée de l'extérieur (assistant, unités) : le texte suit, sauf si
    // le texte tapé donne déjà cette valeur.
    final lu = _lire(_ctrl.text);
    if (lu == null || (lu - widget.valeur).abs() > 1e-6) {
      if (old.valeur != widget.valeur || old.metrique != widget.metrique) {
        _ctrl.text = _formater(widget.valeur);
        _erreur = null;
      }
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  double? _lire(String t) {
    try {
      return lireLongueur(t, metrique: _metrique);
    } on MesureInvalide {
      return null;
    }
  }

  void _modifie(String t) {
    try {
      final v = lireLongueur(t, metrique: _metrique);
      if (v < widget.min - 1e-9 || v > widget.max + 1e-9) {
        setState(
          () => _erreur =
              'Entre ${formatLongueur(widget.min, metrique: _metrique)} et '
              '${formatLongueur(widget.max, metrique: _metrique)}.',
        );
        return;
      }
      setState(() => _erreur = null);
      widget.onChange(v);
    } on MesureInvalide catch (e) {
      setState(() => _erreur = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _ctrl,
      keyboardType: _metrique
          ? const TextInputType.numberWithOptions(decimal: true)
          : TextInputType.text,
      decoration: InputDecoration(
        labelText: widget.label,
        helperText:
            widget.aide ??
            (_metrique
                ? 'En mètres (3,2) ou en millimètres (850 mm)'
                : 'Ex. : 10\'6"  ·  10-6  ·  126"  (un nombre seul = pieds)'),
        helperMaxLines: 2,
        errorText: _erreur,
        errorMaxLines: 2,
        border: const OutlineInputBorder(),
        isDense: true,
      ),
      onChanged: _modifie,
    );
  }
}

/// Champ numérique simple (angle, pourcentage, entraxe en pouces…).
class ChampNombre extends StatefulWidget {
  final String label;
  final double valeur;
  final ValueChanged<double> onChange;
  final double min;
  final double max;
  final int decimales;
  final String? suffixe;
  final String? aide;

  const ChampNombre({
    super.key,
    required this.label,
    required this.valeur,
    required this.onChange,
    this.min = 0,
    this.max = 1e6,
    this.decimales = 1,
    this.suffixe,
    this.aide,
  });

  @override
  State<ChampNombre> createState() => _ChampNombreState();
}

class _ChampNombreState extends State<ChampNombre> {
  late final TextEditingController _ctrl;
  String? _erreur;

  String _formater(double v) => formatNombre(v, decimales: widget.decimales);

  double? _lire(String t) =>
      double.tryParse(t.trim().replaceAll(',', '.').replaceAll('°', ''));

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: _formater(widget.valeur));
  }

  @override
  void didUpdateWidget(ChampNombre old) {
    super.didUpdateWidget(old);
    final lu = _lire(_ctrl.text);
    if ((lu == null || (lu - widget.valeur).abs() > 1e-9) &&
        old.valeur != widget.valeur) {
      _ctrl.text = _formater(widget.valeur);
      _erreur = null;
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _modifie(String t) {
    final v = _lire(t);
    if (v == null || !v.isFinite) {
      setState(() => _erreur = 'Nombre invalide.');
      return;
    }
    if (v < widget.min || v > widget.max) {
      setState(
        () => _erreur =
            'Entre ${formatNombre(widget.min, decimales: widget.decimales)} et '
            '${formatNombre(widget.max, decimales: widget.decimales)}.',
      );
      return;
    }
    setState(() => _erreur = null);
    widget.onChange(v);
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _ctrl,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,°]'))],
      decoration: InputDecoration(
        labelText: widget.label,
        suffixText: widget.suffixe,
        helperText: widget.aide,
        helperMaxLines: 2,
        errorText: _erreur,
        border: const OutlineInputBorder(),
        isDense: true,
      ),
      onChanged: _modifie,
    );
  }
}

/// Titre de section dans un formulaire.
class TitreSection extends StatelessWidget {
  final String texte;
  final String? aide;
  const TitreSection(this.texte, {super.key, this.aide});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            texte,
            style: Theme.of(context).textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          if (aide != null)
            Text(aide!, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}

/// Bloc d'avertissements (ambre) ou d'erreur (rouge).
class BlocMessages extends StatelessWidget {
  final List<String> messages;
  final bool erreur;
  const BlocMessages(this.messages, {super.key, this.erreur = false});

  @override
  Widget build(BuildContext context) {
    if (messages.isEmpty) {
      return const SizedBox.shrink();
    }
    final scheme = Theme.of(context).colorScheme;
    final fond = erreur ? scheme.errorContainer : const Color(0xFFFFF3CD);
    final texte = erreur ? scheme.onErrorContainer : const Color(0xFF5C4400);
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: fond,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final m in messages)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    erreur ? Icons.error_outline : Icons.warning_amber,
                    size: 18,
                    color: texte,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(m, style: TextStyle(color: texte)),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
