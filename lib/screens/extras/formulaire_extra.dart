import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../models/extra_chantier.dart';
import '../../services/photos.dart';

/// Ce que l'utilisateur a saisi dans le formulaire d'un extra.
class ExtraSaisie {
  final String description;

  /// Main-d'œuvre et temps, en texte libre (« 3 gars, 1 compagnon, 1 apprenti »).
  final String mainOeuvre;
  final DateTime date;

  /// Nouvelle photo choisie (prise avec l'app ou de la galerie), sinon null.
  final XFile? nouvellePhoto;

  /// La photo existante doit être retirée (modification seulement).
  final bool retirerPhoto;

  const ExtraSaisie({
    required this.description,
    required this.mainOeuvre,
    required this.date,
    this.nouvellePhoto,
    this.retirerPhoto = false,
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

  const FormulaireExtra({
    super.key,
    this.initial,
    required this.connecte,
    required this.libelleBouton,
    required this.onValider,
  });

  @override
  State<FormulaireExtra> createState() => _FormulaireExtraState();
}

class _FormulaireExtraState extends State<FormulaireExtra> {
  late final TextEditingController _description;
  late final TextEditingController _mainOeuvre;
  late DateTime _date;
  XFile? _photo;
  Uint8List? _apercu;
  late bool _photoExistante;
  bool _enCours = false;
  String? _erreur;

  @override
  void initState() {
    super.initState();
    final e = widget.initial;
    _description = TextEditingController(text: e?.description ?? '');
    _mainOeuvre = TextEditingController(text: e?.mainOeuvre ?? '');
    _date = (e == null ? null : lireDateIso(e.dateTravaux)) ?? DateTime.now();
    _photoExistante = e?.photoUrl != null;
  }

  @override
  void dispose() {
    _description.dispose();
    _mainOeuvre.dispose();
    _abandonnerPhoto();
    super.dispose();
  }

  /// Supprime la copie temporaire d'une photo choisie mais pas envoyée.
  void _abandonnerPhoto() {
    final p = _photo;
    if (p != null) Photos.supprimerTemporaire(p);
  }

  Future<void> _obtenirPhoto(Future<XFile?> Function() source) async {
    final image = await source();
    if (image == null) return;
    final octets = await image.readAsBytes();
    if (!mounted) return;
    _abandonnerPhoto();
    setState(() {
      _photo = image;
      _apercu = octets;
      _erreur = null;
    });
  }

  void _retirerPhoto() {
    _abandonnerPhoto();
    setState(() {
      _photo = null;
      _apercu = null;
      _photoExistante = false;
    });
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
      nouvellePhoto: _photo,
      retirerPhoto:
          _photo == null &&
          widget.initial?.photoUrl != null &&
          !_photoExistante,
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
      // La copie temporaire a été supprimée par l'envoi.
      setState(() {
        _photo = null;
        _apercu = null;
        _date = DateTime.now();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final connecte = widget.connecte;
    final aPhoto = _apercu != null || _photoExistante;

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
          children: [
            if (aPhoto) ...[
              Stack(
                clipBehavior: Clip.none,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: _apercu != null
                        ? Image.memory(
                            _apercu!,
                            width: 48,
                            height: 48,
                            fit: BoxFit.cover,
                          )
                        : Image.network(
                            widget.initial!.photoUrl!,
                            width: 48,
                            height: 48,
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => const SizedBox(
                              width: 48,
                              height: 48,
                              child: Icon(Icons.broken_image_outlined),
                            ),
                          ),
                  ),
                  Positioned(
                    top: -8,
                    right: -8,
                    child: IconButton(
                      key: const ValueKey('extra_retirer_photo'),
                      icon: const Icon(
                        Icons.cancel,
                        size: 18,
                        color: Colors.red,
                      ),
                      tooltip: 'Retirer la photo',
                      onPressed: _retirerPhoto,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 10),
            ],
            OutlinedButton.icon(
              key: const ValueKey('extra_prendre_photo'),
              onPressed: connecte ? () => _obtenirPhoto(Photos.prendre) : null,
              icon: const Icon(Icons.camera_alt, size: 18),
              label: Text(aPhoto ? 'Reprendre' : 'Photo'),
            ),
            const SizedBox(width: 6),
            IconButton(
              key: const ValueKey('extra_galerie'),
              tooltip: 'Choisir depuis la galerie',
              onPressed: connecte ? () => _obtenirPhoto(Photos.choisir) : null,
              icon: const Icon(Icons.photo_library_outlined),
            ),
            const Spacer(),
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
