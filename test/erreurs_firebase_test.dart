import 'package:construction_app/services/erreurs_firebase.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  FirebaseException e(String plugin, String code) =>
      FirebaseException(plugin: plugin, code: code);

  test('dit d\'où vient l\'erreur : stockage, base de données ou serveur', () {
    expect(
      detailErreurFirebase(e('firebase_storage', 'unauthorized')),
      'stockage des fichiers : unauthorized',
    );
    expect(
      detailErreurFirebase(e('cloud_firestore', 'permission-denied')),
      'base de données : permission-denied',
    );
    expect(
      detailErreurFirebase(e('cloud_functions', 'unavailable')),
      'serveur : unavailable',
    );
    expect(detailErreurFirebase(e('autre_plugin', 'x')), 'autre_plugin : x');
  });

  test('une erreur qui n\'est pas de Firebase : seulement son type', () {
    expect(detailErreurFirebase(StateError('x')), 'StateError');
    expect(detailErreurFirebase('texte'), 'String');
  });

  test('refus d\'accès : unauthorized et permission-denied seulement', () {
    expect(estRefusFirebase(e('firebase_storage', 'unauthorized')), isTrue);
    expect(estRefusFirebase(e('cloud_firestore', 'permission-denied')), isTrue);
    expect(
      estRefusFirebase(e('firebase_storage', 'retry-limit-exceeded')),
      isFalse,
    );
    expect(estRefusFirebase(e('cloud_firestore', 'unavailable')), isFalse);
    expect(estRefusFirebase(StateError('x')), isFalse);
  });
}
