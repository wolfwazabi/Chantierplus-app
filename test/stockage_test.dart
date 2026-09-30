import 'dart:io';

import 'package:construction_app/services/stockage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('le stockage utilise le bucket de Montréal', () {
    expect(Stockage.bucket, 'gs://chantierplus-mtl');
  });

  test('aucun code n\'utilise l\'ancien bucket par défaut (États-Unis)', () {
    final fautifs = <String>[];
    for (final f in Directory('lib').listSync(recursive: true)) {
      if (f is! File || !f.path.endsWith('.dart')) continue;
      final chemin = f.path.replaceAll(r'\', '/');
      if (chemin.endsWith('services/stockage.dart')) continue;
      final contenu = f.readAsStringSync();
      if (contenu.contains('FirebaseStorage.instance')) fautifs.add(f.path);
    }
    expect(fautifs, isEmpty, reason: 'Utiliser Stockage.instance : $fautifs');
  });
}
