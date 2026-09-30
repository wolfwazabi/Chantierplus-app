import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../models/extra_chantier.dart';
import '../../services/photos.dart';

/// Ce que l'utilisateur a saisi dans le formulaire d'un extra.
class ExtraSaisie {
  final String description;
  final int nombreHommes;
  final double heures;
  final DateTime date;

  /// Nouvelle photo choisie (prise avec l'app ou de la galerie), sinon null.
  final XFile? nouvellePhoto;

  /// La photo existante doit être retirée (modification seulement).
  final bool retirerPhoto;

  const ExtraSaisie({
    required this.description,
    required this.nombreHommes,
    required this.heures,
    required this.date,
    this.nouvellePhoto,
    this.retirerPhoto = false,
  });
}

/// Formulaire d'un extra : description, nombre d'hommes, temps, date, photo
/// facultative. Sert à ajouter et à modifier.
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
  late final TextEditingController _hommes;
  late final TextEditingController _heures;
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
    _hommes = TextEditingController(text: e == null ? '' : '${e.nombreHommes}');
    _heures = TextEditingController(
      text: e == null ? '' : formatNombre(e.heures),
    );
    _date = (e == null ? null : lireDateIso(e.dateTravaux)) ?? DateTime.now();
    _photoExistante = e?.photoUrl != null;
    for (final c in [_hommes, _heures]) {
      c.addListener(() => setState(() {}));
    }
  }

  @override
  void dispose() {
    _description.dispose();
    _hommes.dispose();
    _heures.dispose();
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
    final hommes = lireNombreHommes(_hommes.text);
    final heures = lireHeures(_heures.text);
    String? erreur;
    if (description.isEmpty) {
      erreur = 'Décrivez les travaux effectués.';
    } else if (hommes == null) {
      erreur = 'Nombre d\'hommes : un entier de 1 à $maxHommes.';
    } else if (heures == null) {
      erreur = 'Temps : un nombre d\'heures supérieur à 0 (ex. 3.5).';
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
      nombreHommes: hommes!,
      heures: heures!,
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
      _hommes.clear();
      _heures.clear();
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
    final hommes = lireNombreHommes(_hommes.text);
    final heures = lireHeures(_heures.text);
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
          maxLength: 2000,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            labelText: 'Description des travaux effectués',
            border: OutlineInputBorder(),
            isDense: true,
            counterText: '',
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                key: const ValueKey('extra_hommes'),
                controller: _hommes,
                enabled: connecte,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Hommes',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                key: const ValueKey('extra_heures'),
                controller: _heures,
                enabled: connecte,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Temps (h)',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                key: const ValueKey('extra_date'),
                onPressed: connecte ? _choisirDate : null,
                icon: const Icon(Icons.event, size: 18),
                label: Text(
                  dateAffichee(dateIso(_date)),
                  style: const TextStyle(fontSize: 12),
                ),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 14,
                  ),
                ),
              ),
            ),
          ],
        ),
        if (hommes != null && heures != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              resumeTemps(hommes, heures),
              key: const ValueKey('extra_resume'),
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
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
