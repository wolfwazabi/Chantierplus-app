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
  final _focus = FocusNode();
  String? _erreur;

  bool get _metrique => widget.metrique ?? Preferences.estMetrique;

  String _formater(double v) =>
      _metrique ? formatMetrique(v) : formatImperial(v);

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: _formater(widget.valeur));
    // L'exemple de saisie n'apparaît que pendant la saisie : l'écran reste léger.
    _focus.addListener(() {
      if (mounted) setState(() {});
    });
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
    _focus.dispose();
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
      focusNode: _focus,
      keyboardType: _metrique
          ? const TextInputType.numberWithOptions(decimal: true)
          : TextInputType.text,
      decoration: InputDecoration(
        labelText: widget.label,
        helperText:
            widget.aide ??
            (!_focus.hasFocus
                ? null
                : _metrique
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

  /// Appelé quand le texte tapé n'est pas une valeur permise.
  final VoidCallback? onInvalide;

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
    this.onInvalide,
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
      widget.onInvalide?.call();
      return;
    }
    if (v < widget.min || v > widget.max) {
      setState(
        () => _erreur =
            'Entre ${formatNombre(widget.min, decimales: widget.decimales)} et '
            '${formatNombre(widget.max, decimales: widget.decimales)}.',
      );
      widget.onInvalide?.call();
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

/// Entraxes proposés dans le menu (pouces) ; « Autre… » permet n'importe quelle valeur.
const entraxesCourants = <double>[12, 16, 19.2, 24];

/// Menu de l'entraxe (centre à centre, en pouces) : les valeurs courantes, la valeur actuelle
/// si elle est autre, et « Autre… » qui demande une valeur.
class ChoixEntraxe extends StatelessWidget {
  final double valeur;
  final ValueChanged<double> onChange;
  final String label;

  const ChoixEntraxe({
    super.key,
    required this.valeur,
    required this.onChange,
    this.label = 'Entraxe',
  });

  static const double _autre = -1;

  static String libelle(double po) {
    final texte = '${formatNombre(po, decimales: 2)} po';
    return Preferences.estMetrique
        ? '$texte (${(po * 25.4).round()} mm)'
        : texte;
  }

  Future<void> _demander(BuildContext context) async {
    final v = await showDialog<double>(
      context: context,
      builder: (ctx) => _DialogueEntraxe(initiale: valeur),
    );
    if (v != null) onChange(v);
  }

  @override
  Widget build(BuildContext context) {
    final courante = entraxesCourants.any((e) => (e - valeur).abs() < 1e-9);
    return DropdownButtonFormField<double>(
      key: ValueKey('entraxe_menu_$valeur'),
      initialValue: valeur,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        isDense: true,
      ),
      items: [
        for (final e in entraxesCourants)
          DropdownMenuItem(value: e, child: Text(libelle(e))),
        if (!courante)
          DropdownMenuItem(value: valeur, child: Text(libelle(valeur))),
        const DropdownMenuItem(value: _autre, child: Text('Autre…')),
      ],
      onChanged: (v) {
        if (v == null) return;
        if (v == _autre) {
          _demander(context);
        } else if ((v - valeur).abs() > 1e-9) {
          onChange(v);
        }
      },
    );
  }
}

class _DialogueEntraxe extends StatefulWidget {
  final double initiale;
  const _DialogueEntraxe({required this.initiale});

  @override
  State<_DialogueEntraxe> createState() => _DialogueEntraxeState();
}

class _DialogueEntraxeState extends State<_DialogueEntraxe> {
  late double _valeur = widget.initiale;
  bool _valide = true;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Entraxe'),
      content: ChampNombre(
        key: const ValueKey('entraxe_autre'),
        label: 'Centre à centre',
        valeur: _valeur,
        min: 6,
        max: 48,
        decimales: 2,
        suffixe: 'po',
        onChange: (v) => setState(() {
          _valeur = v;
          _valide = true;
        }),
        onInvalide: () => setState(() => _valide = false),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Annuler'),
        ),
        FilledButton(
          key: const ValueKey('entraxe_autre_ok'),
          onPressed: _valide ? () => Navigator.pop(context, _valeur) : null,
          child: const Text('OK'),
        ),
      ],
    );
  }
}

/// Groupe de réglages replié : son titre et le résumé des valeurs actuelles ; les champs
/// s'affichent quand on l'ouvre. Clé : `groupe_<cle>`.
class SectionRepliable extends StatelessWidget {
  final String cle;
  final String titre;
  final String resume;
  final List<Widget> enfants;

  const SectionRepliable({
    super.key,
    required this.cle,
    required this.titre,
    required this.resume,
    required this.enfants,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Le groupe reste ouvert ou fermé quand on change d'onglet : son état est gardé dans la page,
    // sous un identifiant à lui (une PageStorageKey le mêlerait à celui des champs de texte).
    final memoire = PageStorage.maybeOf(context);
    final identifiant = 'groupe_$cle';
    return ExpansionTile(
      key: ValueKey(identifiant),
      initiallyExpanded:
          memoire?.readState(context, identifier: identifiant) == true,
      onExpansionChanged: (v) =>
          memoire?.writeState(context, v, identifier: identifiant),
      tilePadding: EdgeInsets.zero,
      childrenPadding: const EdgeInsets.only(bottom: 12),
      expandedCrossAxisAlignment: CrossAxisAlignment.start,
      expandedAlignment: Alignment.centerLeft,
      shape: const Border(),
      collapsedShape: const Border(),
      title: Text(titre),
      subtitle: Text(
        resume,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
      children: enfants,
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
