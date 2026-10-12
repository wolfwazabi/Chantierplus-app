import 'package:flutter/material.dart';

import '../../models/extra_chantier.dart';
import '../../widgets/photos_multiples.dart';

/// Ce que l'utilisateur a saisi dans le formulaire d'un extra.
class ExtraSaisie {
  final String description;

  /// Main-d'œuvre et temps, en texte libre (« 3 gars, 1 compagnon, 1 apprenti »).
  final String mainOeuvre;
  final DateTime date;

  /// Photos déjà enregistrées que l'on garde, dans l'ordre (modification seulement).
  final List<String> conservees;

  /// Nouvelles photos choisies (prises avec l'app ou de la galerie), à envoyer.
  final List<PhotoEnAttente> nouvelles;

  const ExtraSaisie({
    required this.description,
    required this.mainOeuvre,
    required this.date,
    this.conservees = const [],
    this.nouvelles = const [],
  });
}

/// Formulaire d'un extra : description, main-d'œuvre et temps (texte libre),
/// date, photo facultative. Sert à ajouter et à modifier.
class FormulaireExtra extends StatefulWidget {
  final ExtraChantier? initial;
  final bool connecte;
  final String libelleBouton;

  /// Enregistre la saisie ; retourne true si c'est réussi (le formulaire
  /// d'ajout se vide alors).
  final Future<bool> Function(ExtraSaisie saisie) onValider;

  /// Tests : remplacent l'appareil photo et la galerie.
  @visibleForTesting
  final PrendrePhoto? prendrePhoto;
  @visibleForTesting
  final ChoisirPhotos? choisirPhotos;

  const FormulaireExtra({
    super.key,
    this.initial,
    required this.connecte,
    required this.libelleBouton,
    required this.onValider,
    this.prendrePhoto,
    this.choisirPhotos,
  });

  @override
  State<FormulaireExtra> createState() => _FormulaireExtraState();
}

class _FormulaireExtraState extends State<FormulaireExtra> {
  late final TextEditingController _description;
  late final TextEditingController _mainOeuvre;
  late DateTime _date;
  late final ControleurPhotos _photos;
  bool _enCours = false;
  String? _erreur;

  @override
  void initState() {
    super.initState();
    final e = widget.initial;
    _description = TextEditingController(text: e?.description ?? '');
    _mainOeuvre = TextEditingController(text: e?.mainOeuvre ?? '');
    _date = (e == null ? null : lireDateIso(e.dateTravaux)) ?? DateTime.now();
    _photos = ControleurPhotos(existantes: e?.photos ?? const []);
  }

  @override
  void dispose() {
    _description.dispose();
    _mainOeuvre.dispose();
    _photos.dispose();
    super.dispose();
  }

  Future<void> _choisirDate() async {
    final aujourdhui = DateTime.now();
    final choisie = await showDatePicker(
      context: context,
      initialDate: _date.isAfter(aujourdhui) ? aujourdhui : _date,
      firstDate: DateTime(2020),
      lastDate: aujourdhui,
    );
    if (choisie != null) setState(() => _date = choisie);
  }

  Future<void> _valider() async {
    final description = _description.text.trim();
    final mainOeuvre = _mainOeuvre.text.trim();
    String? erreur;
    if (description.isEmpty) {
      erreur = 'Décrivez les travaux effectués.';
    } else if (mainOeuvre.isEmpty) {
      erreur = 'Indiquez la main-d\'œuvre et le temps (ex. 3 gars, 4 h).';
    }
    if (erreur != null) {
      setState(() => _erreur = erreur);
      return;
    }
    setState(() {
      _erreur = null;
      _enCours = true;
    });
    final saisie = ExtraSaisie(
      description: description,
      mainOeuvre: mainOeuvre,
      date: _date,
      conservees: [..._photos.existantes],
      nouvelles: [..._photos.nouvelles],
    );
    bool ok = false;
    try {
      ok = await widget.onValider(saisie);
    } finally {
      if (mounted) setState(() => _enCours = false);
    }
    if (ok && mounted && widget.initial == null) {
      _description.clear();
      _mainOeuvre.clear();
      _photos.vider();
      setState(() => _date = DateTime.now());
    }
  }

  @override
  Widget build(BuildContext context) {
    final connecte = widget.connecte;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          key: const ValueKey('extra_description'),
          controller: _description,
          enabled: connecte,
          minLines: 2,
          maxLines: 4,
          maxLength: maxDescription,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            labelText: 'Description des travaux effectués',
            border: OutlineInputBorder(),
            isDense: true,
            counterText: '',
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          key: const ValueKey('extra_main_oeuvre'),
          controller: _mainOeuvre,
          enabled: connecte,
          minLines: 1,
          maxLines: 3,
          maxLength: maxMainOeuvre,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            labelText: 'Main-d\'œuvre et temps',
            hintText: 'ex. : 3 gars, 1 compagnon, 1 apprenti — 4 h',
            border: OutlineInputBorder(),
            isDense: true,
            counterText: '',
          ),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          key: const ValueKey('extra_date'),
          onPressed: connecte ? _choisirDate : null,
          icon: const Icon(Icons.event, size: 18),
          label: Text('Date : ${dateAffichee(dateIso(_date))}'),
        ),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: SelecteurPhotos(
                controleur: _photos,
                actif: connecte && !_enCours,
                prendre: widget.prendrePhoto,
                choisir: widget.choisirPhotos,
              ),
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              key: const ValueKey('extra_valider'),
              onPressed: (!connecte || _enCours) ? null : _valider,
              icon: _enCours
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.add),
              label: Text(widget.libelleBouton),
            ),
          ],
        ),
        if (_erreur != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              _erreur!,
              key: const ValueKey('extra_erreur'),
              style: const TextStyle(color: Colors.red, fontSize: 13),
            ),
          ),
      ],
    );
  }
}
