import 'dart:typed_data';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../models/photos_entree.dart';
import '../services/photos.dart';
import '../services/stockage.dart';

/// Une photo choisie, pas encore envoyée (ses octets sont gardés en mémoire : on
/// peut réessayer l'envoi sans la rechoisir).
class PhotoEnAttente {
  final String nom;
  final Uint8List octets;
  const PhotoEnAttente(this.nom, this.octets);
}

/// Prend une photo avec l'appareil (null : annulé).
typedef PrendrePhoto = Future<XFile?> Function();

/// Choisit jusqu'à [limite] photos dans la galerie.
typedef ChoisirPhotos = Future<List<XFile>> Function(int limite);

/// Envoie des octets au Storage et rend le lien de téléchargement.
typedef Televerser = Future<String> Function(String chemin, Uint8List octets);

/// Les photos d'une demande en cours de saisie ou de modification : celles déjà
/// enregistrées (liens) et les nouvelles (à envoyer), jusqu'à [maxPhotosParEntree].
class ControleurPhotos extends ChangeNotifier {
  final List<String> _initiales;
  final List<String> existantes;
  final List<PhotoEnAttente> nouvelles = [];

  ControleurPhotos({List<String> existantes = const []})
    : _initiales = [...existantes],
      existantes = [...existantes];

  int get total => existantes.length + nouvelles.length;
  int get restantes => maxPhotosParEntree - total;

  /// Photos enregistrées que l'utilisateur a retirées.
  List<String> get retirees =>
      _initiales.where((u) => !existantes.contains(u)).toList();

  /// Vrai si les photos diffèrent de celles du départ.
  bool get modifiees => retirees.isNotEmpty || nouvelles.isNotEmpty;

  /// Ajoute des photos jusqu'au maximum ; rend le nombre de photos ignorées.
  int ajouter(Iterable<PhotoEnAttente> photos) {
    var ignorees = 0;
    for (final p in photos) {
      if (restantes <= 0) {
        ignorees++;
      } else {
        nouvelles.add(p);
      }
    }
    notifyListeners();
    return ignorees;
  }

  void retirerExistante(int index) {
    if (index < 0 || index >= existantes.length) return;
    existantes.removeAt(index);
    notifyListeners();
  }

  void retirerNouvelle(int index) {
    if (index < 0 || index >= nouvelles.length) return;
    nouvelles.removeAt(index);
    notifyListeners();
  }

  void vider() {
    existantes.clear();
    nouvelles.clear();
    notifyListeners();
  }
}

String _nomPropre(String nom) {
  final propre = nom
      .replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_')
      .replaceAll(RegExp(r'_+'), '_');
  if (propre.isEmpty) return 'photo.jpg';
  return propre.length > 80 ? propre.substring(propre.length - 80) : propre;
}

Future<String> _televerserReel(String chemin, Uint8List octets) async {
  final ref = Stockage.instance.ref().child(chemin);
  await ref.putData(octets, SettableMetadata(contentType: 'image/jpeg'));
  return ref.getDownloadURL();
}

/// Une photo envoyée : son lien et son chemin dans le Storage.
class PhotoEnvoyee {
  final String url;
  final String chemin;
  const PhotoEnvoyee(this.url, this.chemin);
}

/// Supprime un fichier du Storage (par son chemin).
typedef SupprimerPhoto = Future<void> Function(String chemin);

Future<void> _supprimerReel(String chemin) =>
    Stockage.instance.ref().child(chemin).delete();

/// Supprime des fichiers du Storage, un échec n'arrête pas les suivants (nettoyage).
Future<void> supprimerPhotosStorage(
  Iterable<String> chemins, {
  SupprimerPhoto? supprimer,
}) async {
  final suppr = supprimer ?? _supprimerReel;
  for (final c in chemins) {
    try {
      await suppr(c);
    } catch (_) {}
  }
}

/// Envoie les photos une à une dans [dossier] et rend leurs liens et chemins, dans
/// l'ordre. Si l'une échoue, les photos déjà envoyées sont retirées du Storage (pas
/// de fichier orphelin) et l'erreur remonte.
Future<List<PhotoEnvoyee>> televerserPhotos(
  List<PhotoEnAttente> photos, {
  required String dossier,
  Televerser? televerser,
  SupprimerPhoto? supprimer,
  void Function(int faites, int total)? progression,
}) async {
  final envoyer = televerser ?? _televerserReel;
  final faites = <PhotoEnvoyee>[];
  final base = DateTime.now().millisecondsSinceEpoch;
  try {
    for (var i = 0; i < photos.length; i++) {
      final p = photos[i];
      final chemin = '$dossier/${base}_${i}_${_nomPropre(p.nom)}';
      faites.add(PhotoEnvoyee(await envoyer(chemin, p.octets), chemin));
      progression?.call(i + 1, photos.length);
    }
  } catch (_) {
    await supprimerPhotosStorage([for (final f in faites) f.chemin], supprimer: supprimer);
    rethrow;
  }
  return faites;
}

/// Comme [televerserPhotos], mais ne rend que les liens.
Future<List<String>> envoyerPhotos(
  List<PhotoEnAttente> photos, {
  required String dossier,
  Televerser? televerser,
  SupprimerPhoto? supprimer,
  void Function(int faites, int total)? progression,
}) async => [
  for (final p in await televerserPhotos(
    photos,
    dossier: dossier,
    televerser: televerser,
    supprimer: supprimer,
    progression: progression,
  ))
    p.url,
];

Future<PhotoEnAttente?> _lire(XFile f) async {
  try {
    final octets = await f.readAsBytes();
    // La copie temporaire ne reste pas dans le téléphone.
    await Photos.supprimerTemporaire(f);
    return PhotoEnAttente(f.name, octets);
  } catch (_) {
    return null;
  }
}

Future<List<XFile>> _galerieReelle(int limite) async {
  if (limite >= 2) return Photos.choisirPlusieurs(limite: limite);
  final une = await Photos.choisir();
  return une == null ? <XFile>[] : [une];
}

/// Les aperçus des photos d'une demande (avec « retirer ») et le bouton pour en
/// ajouter : prendre une photo ou en choisir plusieurs dans la galerie.
class SelecteurPhotos extends StatelessWidget {
  final ControleurPhotos controleur;
  final bool actif;

  /// Tests : remplacent l'appareil photo et la galerie.
  @visibleForTesting
  final PrendrePhoto? prendre;
  @visibleForTesting
  final ChoisirPhotos? choisir;

  const SelecteurPhotos({
    super.key,
    required this.controleur,
    this.actif = true,
    this.prendre,
    this.choisir,
  });

  Future<void> _ouvrirChoix(BuildContext context) async {
    final messager = ScaffoldMessenger.of(context);
    final choix = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              key: const ValueKey('photos_prendre'),
              leading: const Icon(Icons.camera_alt),
              title: const Text('Prendre une photo'),
              onTap: () => Navigator.pop(ctx, 'prendre'),
            ),
            ListTile(
              key: const ValueKey('photos_galerie'),
              leading: const Icon(Icons.photo_library),
              title: const Text('Choisir dans la galerie (plusieurs)'),
              onTap: () => Navigator.pop(ctx, 'galerie'),
            ),
          ],
        ),
      ),
    );
    if (choix == null) return;
    final List<XFile> fichiers;
    if (choix == 'prendre') {
      final f = await (prendre ?? Photos.prendre)();
      fichiers = f == null ? const [] : [f];
    } else {
      fichiers = await (choisir ?? _galerieReelle)(controleur.restantes);
    }
    final lues = <PhotoEnAttente>[];
    for (final f in fichiers) {
      final p = await _lire(f);
      if (p != null) lues.add(p);
    }
    final ignorees = controleur.ajouter(lues);
    if (ignorees > 0) {
      messager.showSnackBar(
        SnackBar(
          content: Text(
            'Maximum de $maxPhotosParEntree photos : '
            '$ignorees photo${ignorees > 1 ? 's' : ''} ignorée${ignorees > 1 ? 's' : ''}.',
          ),
        ),
      );
    }
  }

  Widget _vignette(Widget image, String cle, VoidCallback retirer) {
    return Padding(
      padding: const EdgeInsets.only(right: 10, top: 6),
      child: SizedBox(
        width: 56,
        height: 56,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: ClipRRect(borderRadius: BorderRadius.circular(6), child: image),
            ),
            Positioned(
              top: -8,
              right: -8,
              child: GestureDetector(
                key: ValueKey(cle),
                onTap: actif ? retirer : null,
                child: const Icon(Icons.cancel, size: 20, color: Colors.red),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controleur,
      builder: (context, _) {
        final c = controleur;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (c.total > 0)
              SizedBox(
                height: 66,
                child: ListView(
                  key: const ValueKey('photos_apercus'),
                  scrollDirection: Axis.horizontal,
                  children: [
                    for (var i = 0; i < c.existantes.length; i++)
                      _vignette(
                        Image.network(
                          c.existantes[i],
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) =>
                              const Icon(Icons.broken_image_outlined),
                        ),
                        'photo_retirer_existante_$i',
                        () => c.retirerExistante(i),
                      ),
                    for (var i = 0; i < c.nouvelles.length; i++)
                      _vignette(
                        Image.memory(c.nouvelles[i].octets, fit: BoxFit.cover),
                        'photo_retirer_nouvelle_$i',
                        () => c.retirerNouvelle(i),
                      ),
                  ],
                ),
              ),
            OutlinedButton.icon(
              key: const ValueKey('photos_ajouter'),
              onPressed: actif && c.restantes > 0 ? () => _ouvrirChoix(context) : null,
              icon: const Icon(Icons.add_a_photo_outlined, size: 18),
              label: Text(
                c.total == 0
                    ? 'Ajouter des photos'
                    : (c.restantes > 0
                          ? 'Ajouter des photos (${c.total}/$maxPhotosParEntree)'
                          : 'Maximum atteint (${c.total}/$maxPhotosParEntree)'),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Visionneuse plein écran : on glisse d'une photo à l'autre, on pince pour zoomer.
Future<void> ouvrirGaleriePhotos(
  BuildContext context,
  List<String> urls, {
  int index = 0,
}) {
  if (urls.isEmpty) return Future.value();
  return showDialog<void>(
    context: context,
    builder: (ctx) => Dialog.fullscreen(
      backgroundColor: Colors.black,
      child: _Galerie(urls: urls, index: index.clamp(0, urls.length - 1)),
    ),
  );
}

class _Galerie extends StatefulWidget {
  final List<String> urls;
  final int index;
  const _Galerie({required this.urls, required this.index});

  @override
  State<_Galerie> createState() => _GalerieState();
}

class _GalerieState extends State<_Galerie> {
  late final PageController _page = PageController(initialPage: widget.index);
  late int _courante = widget.index;

  @override
  void dispose() {
    _page.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      key: const ValueKey('galerie_photos'),
      children: [
        PageView.builder(
          controller: _page,
          itemCount: widget.urls.length,
          onPageChanged: (i) => setState(() => _courante = i),
          itemBuilder: (_, i) => InteractiveViewer(
            child: Center(
              child: Image.network(
                widget.urls[i],
                errorBuilder: (_, _, _) => const Icon(
                  Icons.broken_image_outlined,
                  color: Colors.white54,
                  size: 48,
                ),
              ),
            ),
          ),
        ),
        Positioned(
          top: 8,
          right: 8,
          child: SafeArea(
            child: IconButton(
              key: const ValueKey('galerie_fermer'),
              icon: const Icon(Icons.close, color: Colors.white),
              onPressed: () => Navigator.pop(context),
            ),
          ),
        ),
        if (widget.urls.length > 1)
          Positioned(
            bottom: 16,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Text(
                '${_courante + 1} / ${widget.urls.length}',
                key: const ValueKey('galerie_compteur'),
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
              ),
            ),
          ),
      ],
    );
  }
}

/// La première photo en vignette, avec le nombre de photos s'il y en a plusieurs ;
/// un toucher ouvre la visionneuse.
class VignettePhotos extends StatelessWidget {
  final List<String> urls;
  final double taille;
  const VignettePhotos({super.key, required this.urls, this.taille = 44});

  @override
  Widget build(BuildContext context) {
    if (urls.isEmpty) return SizedBox(width: taille, height: taille);
    return GestureDetector(
      key: const ValueKey('vignette_photos'),
      onTap: () => ouvrirGaleriePhotos(context, urls),
      child: SizedBox(
        width: taille,
        height: taille,
        child: Stack(
          children: [
            Positioned.fill(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: Image.network(
                  urls.first,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => const Icon(Icons.broken_image_outlined),
                ),
              ),
            ),
            if (urls.length > 1)
              Positioned(
                right: 0,
                bottom: 0,
                child: Container(
                  key: const ValueKey('vignette_nombre'),
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                  decoration: const BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.only(topLeft: Radius.circular(6)),
                  ),
                  child: Text(
                    '${urls.length}',
                    style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
