import 'package:construction_app/models/chantier.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Map<String, dynamic> donnees([Map<String, dynamic> extra = const {}]) => {
    'companyId': 'A',
    'nom': 'Chantier A',
    'adresse': '1 rue A',
    ...extra,
  };

  test('un chantier sans champ « archive » est actif (données existantes)', () {
    expect(Chantier.fromFirestore('c1', donnees()).archive, isFalse);
  });

  test('archive: true → archivé ; archive: false → actif', () {
    expect(
      Chantier.fromFirestore('c1', donnees({'archive': true})).archive,
      isTrue,
    );
    expect(
      Chantier.fromFirestore('c1', donnees({'archive': false})).archive,
      isFalse,
    );
  });

  test('une valeur inattendue ne cache jamais un chantier par erreur', () {
    expect(
      Chantier.fromFirestore('c1', donnees({'archive': 'oui'})).archive,
      isFalse,
    );
    expect(
      Chantier.fromFirestore('c1', donnees({'archive': null})).archive,
      isFalse,
    );
  });

  test('l\'archivage ne change pas l\'identité du chantier', () {
    final actif = Chantier.fromFirestore('c1', donnees());
    final archive = Chantier.fromFirestore('c1', donnees({'archive': true}));
    expect(actif, archive);
  });
}
