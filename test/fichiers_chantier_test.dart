import 'package:construction_app/services/fichiers_chantier.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late List<String> journal;

  SupprimerFichier fichierQui([Map<String, Object> echecs = const {}]) =>
      (chemin) async {
        journal.add('fichier:$chemin');
        final e = echecs[chemin];
        if (e != null) throw e;
      };

  SupprimerFiche ficheQui([Set<String> echecs = const {}]) =>
      (collection, id) async {
        journal.add('fiche:$collection/$id');
        if (echecs.contains(id)) throw StateError('refusé');
      };

  setUp(() => journal = []);

  group('supprimerElementsChantier', () {
    test('le fichier du Storage part avant la fiche', () async {
      final r = await supprimerElementsChantier('chantier_photos', const [
        ElementChantier('p1', 'chantiers/A/c/photos/1.jpg'),
      ], supprimerFichier: fichierQui(), supprimerFiche: ficheQui());
      expect(journal, [
        'fichier:chantiers/A/c/photos/1.jpg',
        'fiche:chantier_photos/p1',
      ]);
      expect(r.supprimes, 1);
      expect(r.toutSupprime, isTrue);
    });

    test('un fichier déjà absent du Storage n\'empêche pas la suppression', () async {
      final r = await supprimerElementsChantier(
        'chantier_documents',
        const [ElementChantier('d1', 'chantiers/A/c/documents/plan.pdf')],
        supprimerFichier: fichierQui({
          'chantiers/A/c/documents/plan.pdf': FirebaseException(
            plugin: 'firebase_storage',
            code: 'object-not-found',
          ),
        }),
        supprimerFiche: ficheQui(),
      );
      expect(journal.last, 'fiche:chantier_documents/d1');
      expect(r.supprimes, 1);
      expect(r.echecs, 0);
    });

    test('fichier impossible à supprimer : la fiche reste, les autres continuent', () async {
      final r = await supprimerElementsChantier(
        'chantier_photos',
        const [
          ElementChantier('p1', 'a.jpg'),
          ElementChantier('p2', 'b.jpg'),
          ElementChantier('p3', 'c.jpg'),
        ],
        supprimerFichier: fichierQui({
          'b.jpg': FirebaseException(
            plugin: 'firebase_storage',
            code: 'unauthorized',
          ),
        }),
        supprimerFiche: ficheQui(),
      );
      expect(journal, [
        'fichier:a.jpg',
        'fiche:chantier_photos/p1',
        'fichier:b.jpg', // refusé : pas de fiche supprimée pour p2
        'fichier:c.jpg',
        'fiche:chantier_photos/p3',
      ]);
      expect(r.supprimes, 2);
      expect(r.echecs, 1);
      expect(r.toutSupprime, isFalse);
    });

    test('toute autre erreur de Storage (réseau, droits) compte comme un échec', () async {
      final r = await supprimerElementsChantier(
        'chantier_photos',
        const [ElementChantier('p1', 'a.jpg')],
        supprimerFichier: fichierQui({'a.jpg': StateError('réseau')}),
        supprimerFiche: ficheQui(),
      );
      expect(journal, ['fichier:a.jpg']);
      expect(r.echecs, 1);
    });

    test('fiche refusée : comptée comme échec', () async {
      final r = await supprimerElementsChantier(
        'chantier_photos',
        const [ElementChantier('p1', 'a.jpg'), ElementChantier('p2', 'b.jpg')],
        supprimerFichier: fichierQui(),
        supprimerFiche: ficheQui({'p1'}),
      );
      expect(r.supprimes, 1);
      expect(r.echecs, 1);
    });

    test('un élément sans fichier : seule la fiche est supprimée', () async {
      final r = await supprimerElementsChantier(
        'chantier_documents',
        const [ElementChantier('d1', null), ElementChantier('d2', '')],
        supprimerFichier: fichierQui(),
        supprimerFiche: ficheQui(),
      );
      expect(journal, [
        'fiche:chantier_documents/d1',
        'fiche:chantier_documents/d2',
      ]);
      expect(r.supprimes, 2);
    });

    test('seules les photos et les documents peuvent être supprimés ainsi', () {
      for (final collection in ['chantiers', 'companies', 'employees', 'feuilles_temps', '']) {
        expect(
          () => supprimerElementsChantier(
            collection,
            const [ElementChantier('x', null)],
            supprimerFichier: fichierQui(),
            supprimerFiche: ficheQui(),
          ),
          throwsArgumentError,
          reason: collection,
        );
      }
      expect(journal, isEmpty);
    });
  });

  group('messageSuppression', () {
    String message(int ok, int ko) => messageSuppression(
      ResultatSuppression(ok, ko),
      singulier: 'photo supprimée',
      pluriel: 'photos supprimées',
    );

    test('tout est supprimé', () {
      expect(message(1, 0), '1 photo supprimée.');
      expect(message(3, 0), '3 photos supprimées.');
    });

    test('rien n\'a pu être supprimé', () {
      expect(
        message(0, 2),
        'Suppression impossible. Vérifiez votre connexion et réessayez.',
      );
    });

    test('suppression partielle : dit combien n\'ont pas pu l\'être', () {
      expect(
        message(2, 1),
        '2 photos supprimées ; 1 n\'a pas pu l\'être. Réessayez.',
      );
      expect(
        message(1, 2),
        '1 photo supprimée ; 2 n\'ont pas pu l\'être. Réessayez.',
      );
    });

    test('aucun élément', () {
      expect(message(0, 0), 'Rien à supprimer.');
    });
  });
}
