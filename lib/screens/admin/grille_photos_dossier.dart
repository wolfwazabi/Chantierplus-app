import 'package:flutter/material.dart';

import '../../services/fichiers_chantier.dart';
import '../../widgets/confirmer_action.dart';

/// Une photo du dossier d'un chantier.
class PhotoDossier {
  final String id;
  final String url;
  final String? cheminStorage;
  const PhotoDossier(this.id, this.url, this.cheminStorage);

  ElementChantier get element => ElementChantier(id, cheminStorage);
}

/// Photos d'un chantier, pour l'admin : toucher une photo l'agrandit (avec un
/// bouton « Supprimer ») ; « Sélectionner » ou un appui long permet d'en choisir
/// plusieurs et de les supprimer d'un coup, après confirmation.
class GrillePhotosDossier extends StatefulWidget {
  final List<PhotoDossier> photos;

  /// Supprime les photos données (la confirmation est déjà faite).
  final Future<void> Function(List<PhotoDossier> photos) onSupprimer;

  /// Faux : consultation seulement (agrandir, sans sélection ni suppression).
  final bool peutSupprimer;
  final int colonnes;

  const GrillePhotosDossier({
    super.key,
    required this.photos,
    required this.onSupprimer,
    this.peutSupprimer = true,
    this.colonnes = 4,
  });

  @override
  State<GrillePhotosDossier> createState() => _GrillePhotosDossierState();
}

class _GrillePhotosDossierState extends State<GrillePhotosDossier> {
  bool _selection = false;
  bool _enCours = false;
  final Set<String> _choisies = {};

  /// Les photos choisies qui existent encore (une photo supprimée ailleurs
  /// sort de la sélection).
  List<PhotoDossier> get _choix =>
      widget.photos.where((p) => _choisies.contains(p.id)).toList();

  void _basculer(PhotoDossier p) {
    setState(() {
      if (!_choisies.remove(p.id)) _choisies.add(p.id);
    });
  }

  void _quitterSelection() {
    setState(() {
      _selection = false;
      _choisies.clear();
    });
  }

  Future<void> _confirmerEtSupprimer(List<PhotoDossier> photos) async {
    if (photos.isEmpty || _enCours) return;
    final n = photos.length;
    final ok = await confirmerAction(
      context,
      titre: n == 1 ? 'Supprimer cette photo ?' : 'Supprimer ces $n photos ?',
      texte:
          '${n == 1 ? 'Elle sera supprimée' : 'Elles seront supprimées'} '
          'définitivement pour tous. Cette action est irréversible.',
      action: 'Supprimer',
    );
    if (!ok || !mounted) return;
    setState(() => _enCours = true);
    try {
      await widget.onSupprimer(photos);
    } finally {
      if (mounted) {
        setState(() {
          _enCours = false;
          _selection = false;
          _choisies.clear();
        });
      }
    }
  }

  Future<void> _agrandir(PhotoDossier p) async {
    final supprimer = await showDialog<bool>(
      context: context,
      builder: (ctx) => Dialog(
        child: Stack(
          children: [
            InteractiveViewer(
              child: Image.network(
                p.url,
                errorBuilder: (_, _, _) => const SizedBox(
                  height: 200,
                  child: Center(child: Icon(Icons.broken_image_outlined)),
                ),
              ),
            ),
            Align(
              alignment: Alignment.topRight,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white),
                onPressed: () => Navigator.pop(ctx, false),
              ),
            ),
            if (widget.peutSupprimer)
              Align(
                alignment: Alignment.bottomLeft,
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: FilledButton.icon(
                    key: const ValueKey('photo_supprimer'),
                    style: FilledButton.styleFrom(backgroundColor: Colors.red),
                    onPressed: () => Navigator.pop(ctx, true),
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Supprimer'),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
    if (supprimer == true && mounted) await _confirmerEtSupprimer([p]);
  }

  Widget _barre() {
    if (!widget.peutSupprimer) {
      return const SizedBox.shrink();
    }
    if (!_selection) {
      return Align(
        alignment: Alignment.centerRight,
        child: TextButton.icon(
          key: const ValueKey('photos_selectionner'),
          onPressed: () => setState(() => _selection = true),
          icon: const Icon(Icons.check_circle_outline),
          label: const Text('Sélectionner'),
        ),
      );
    }
    final n = _choix.length;
    return Row(
      children: [
        Expanded(
          child: Text(
            key: const ValueKey('photos_nombre_selection'),
            n == 0
                ? 'Touchez les photos à supprimer'
                : '$n sélectionnée${n > 1 ? 's' : ''}',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
        TextButton(
          key: const ValueKey('photos_annuler_selection'),
          onPressed: _enCours ? null : _quitterSelection,
          child: const Text('Annuler'),
        ),
        FilledButton.icon(
          key: const ValueKey('photos_supprimer_selection'),
          style: FilledButton.styleFrom(backgroundColor: Colors.red),
          onPressed: n == 0 || _enCours
              ? null
              : () => _confirmerEtSupprimer(_choix),
          icon: const Icon(Icons.delete_outline),
          label: const Text('Supprimer'),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _barre(),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: widget.colonnes,
            crossAxisSpacing: 6,
            mainAxisSpacing: 6,
          ),
          itemCount: widget.photos.length,
          itemBuilder: (context, i) {
            final p = widget.photos[i];
            final choisie = _choisies.contains(p.id);
            return GestureDetector(
              key: ValueKey('photo_${p.id}'),
              onTap: _enCours
                  ? null
                  : _selection
                  ? () => _basculer(p)
                  : () => _agrandir(p),
              onLongPress: _enCours || _selection || !widget.peutSupprimer
                  ? null
                  : () => setState(() {
                      _selection = true;
                      _choisies.add(p.id);
                    }),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: Image.network(
                      p.url,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) =>
                          const Icon(Icons.broken_image_outlined),
                    ),
                  ),
                  if (_selection)
                    Positioned(
                      top: 4,
                      right: 4,
                      child: Icon(
                        choisie ? Icons.check_circle : Icons.circle_outlined,
                        key: ValueKey('${choisie ? 'choisie' : 'libre'}_${p.id}'),
                        color: choisie ? Colors.red : Colors.white,
                        shadows: const [Shadow(blurRadius: 4)],
                      ),
                    ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }
}
