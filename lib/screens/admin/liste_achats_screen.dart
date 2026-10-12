import 'package:flutter/material.dart';

import '../../models/liste_achats.dart';
import '../../services/app_session.dart';
import '../../services/liste_achats_source.dart';
import '../../services/theme_compagnie.dart';
import '../../widgets/confirmer_action.dart';
import '../../widgets/photos_multiples.dart';

/// Admin → Liste d'achats : le matériel que les admins ont transféré depuis
/// Général (appui long sur une demande), séparé par équipe (la personne qui l'a
/// demandée). Un admin marque chaque article acheté ou le supprime.
class ListeAchatsScreen extends StatefulWidget {
  /// Tests : remplace Firestore.
  @visibleForTesting
  final SourceListeAchats? source;

  const ListeAchatsScreen({super.key, this.source});

  @override
  State<ListeAchatsScreen> createState() => _ListeAchatsScreenState();
}

class _ListeAchatsScreenState extends State<ListeAchatsScreen> {
  late final SourceListeAchats _source;
  Stream<List<ArticleAchat>>? _articles;
  String _moiId = '';

  @override
  void initState() {
    super.initState();
    _source = widget.source ?? SourceListeAchatsFirestore();
    final moi = AppSession.current;
    if (moi != null && moi.companyId != null && AppSession.estAdmin) {
      _moiId = moi.id;
      _articles = _source.articles(moi.companyId!);
    }
  }

  void _message(String texte, {bool erreur = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(texte), backgroundColor: erreur ? Colors.red : null),
    );
  }

  Future<void> _definirAchete(ArticleAchat a, bool achete) async {
    try {
      await _source.definirAchete(a, achete, employeId: _moiId);
    } catch (_) {
      _message('Modification impossible. Réessayez.', erreur: true);
    }
  }

  Future<void> _supprimer(ArticleAchat a) async {
    final ok = await confirmerAction(
      context,
      titre: 'Retirer cet article ?',
      texte: '« ${a.texte} » sera retiré de la Liste d\'achats. Cette action est irréversible.',
      action: 'Retirer',
    );
    if (!ok) return;
    try {
      await _source.supprimer(a, employeId: _moiId);
      _message('Article retiré.');
    } catch (_) {
      _message('Suppression impossible.', erreur: true);
    }
  }

  static String _date(DateTime? d) {
    if (d == null) return '';
    final l = d.toLocal();
    String deux(int n) => n.toString().padLeft(2, '0');
    return '${deux(l.day)}/${deux(l.month)}';
  }

  Widget _ligne(ArticleAchat a, {required bool avecDemandeur}) {
    final detail = [
      if (a.quantite.isNotEmpty) 'Quantité : ${a.quantite}',
      if (avecDemandeur) 'Demandé par ${nomDemandeur(a)}',
      if (a.complete)
        'Acheté${a.dateComplete == null ? '' : ' le ${_date(a.dateComplete)}'}'
      else if (a.transfereParNom.isNotEmpty)
        'Transféré par ${a.transfereParNom}${a.dateAjout == null ? '' : ' le ${_date(a.dateAjout)}'}',
    ].join(' • ');
    return ListTile(
      key: ValueKey('article_${a.id}'),
      leading: a.photos.isNotEmpty
          ? VignettePhotos(urls: a.photos)
          : Icon(
              a.complete ? Icons.check_circle : Icons.shopping_cart_outlined,
              color: a.complete ? Colors.green : Colors.orange.shade800,
            ),
      title: Text(
        a.texte,
        style: TextStyle(
          decoration: a.complete ? TextDecoration.lineThrough : null,
          color: a.complete ? Colors.grey : null,
        ),
      ),
      subtitle: Text(detail, style: const TextStyle(fontSize: 12)),
      trailing: PopupMenuButton<String>(
        key: ValueKey('menu_article_${a.id}'),
        onSelected: (v) {
          if (v == 'supprimer') {
            _supprimer(a);
          } else {
            _definirAchete(a, v == 'achete');
          }
        },
        itemBuilder: (ctx) => [
          PopupMenuItem(
            value: a.complete ? 'a_acheter' : 'achete',
            child: Text(a.complete ? 'Remettre à acheter' : 'Marquer comme acheté'),
          ),
          const PopupMenuItem(
            value: 'supprimer',
            child: Text('Retirer de la liste', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_articles == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Liste d\'achats')),
        body: const Center(child: Text('Réservé aux administrateurs.')),
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Liste d\'achats')),
      body: StreamBuilder<List<ArticleAchat>>(
        stream: _articles,
        builder: (context, snap) {
          if (snap.hasError) {
            return const Center(child: Text('Impossible de charger la liste.'));
          }
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final articles = snap.data!;
          final groupes = grouperParDemandeur(articles);
          final achetes = articlesAchetes(articles);
          final aAcheter = groupes.fold<int>(0, (s, g) => s + g.articles.length);
          return ListView(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(4, 0, 4, 8),
                child: Text(
                  'Le matériel transféré depuis Général, séparé par équipe '
                  '(la personne qui l\'a demandé).',
                  key: ValueKey('aide_liste_achats'),
                  style: TextStyle(fontSize: 12, color: Colors.black54),
                ),
              ),
              if (articles.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    'La Liste d\'achats est vide. Dans Chantiers → Général, '
                    'appuyez longtemps sur une demande pour la transférer ici.',
                    key: ValueKey('achats_vide'),
                    textAlign: TextAlign.center,
                  ),
                )
              else ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
                  child: Text(
                    aAcheter == 0 ? 'Rien à acheter' : '$aAcheter à acheter',
                    key: const ValueKey('achats_total'),
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                for (final g in groupes)
                  Card(
                    key: ValueKey('equipe_${g.demandeParId}'),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ListTile(
                          leading: Icon(
                            Icons.person_outline,
                            color: ThemeCompagnie.accentDe(context),
                          ),
                          title: Text(
                            g.nom,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          subtitle: Text('${g.articles.length} à acheter'),
                        ),
                        const Divider(height: 1),
                        for (final a in g.articles) _ligne(a, avecDemandeur: false),
                      ],
                    ),
                  ),
                if (achetes.isNotEmpty)
                  Card(
                    child: ExpansionTile(
                      key: const ValueKey('achetes'),
                      shape: const Border(),
                      collapsedShape: const Border(),
                      leading: const Icon(Icons.check_circle_outline),
                      title: Text('Achetés (${achetes.length})'),
                      children: [
                        for (final a in achetes) _ligne(a, avecDemandeur: true),
                      ],
                    ),
                  ),
              ],
            ],
          );
        },
      ),
    );
  }
}
