import 'package:construction_app/services/photos.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  bool peut(String chemin, TargetPlatform p, {bool web = false}) =>
      Photos.peutSupprimerCopie(chemin, p, web);

  test('iPhone et Android : on supprime la copie « image_picker_… »', () {
    expect(
      peut('/private/var/tmp/image_picker_ABC-123.jpg', TargetPlatform.iOS),
      isTrue,
    );
    expect(
      peut(
        '/data/user/0/app.chantierplus/cache/image_picker_9.jpg',
        TargetPlatform.android,
      ),
      isTrue,
    );
  });

  test('jamais un fichier qui n\'est pas une copie du sélecteur', () {
    expect(
      peut(
        '/storage/emulated/0/DCIM/Camera/IMG_0001.jpg',
        TargetPlatform.android,
      ),
      isFalse,
    );
    expect(
      peut(
        '/private/var/mobile/Media/DCIM/100APPLE/IMG_0001.JPG',
        TargetPlatform.iOS,
      ),
      isFalse,
    );
    expect(
      peut('/tmp/image_pickerfake/IMG_0001.jpg', TargetPlatform.iOS),
      isFalse,
    );
  });

  test(
    'ordinateur et web : jamais (le fichier est l\'original de l\'utilisateur)',
    () {
      expect(
        peut(
          r'C:\Users\moi\Pictures\image_picker_1.jpg',
          TargetPlatform.windows,
        ),
        isFalse,
      );
      expect(
        peut('/Users/moi/Pictures/image_picker_1.jpg', TargetPlatform.macOS),
        isFalse,
      );
      expect(
        peut('/home/moi/image_picker_1.jpg', TargetPlatform.linux),
        isFalse,
      );
      expect(
        peut('image_picker_1.jpg', TargetPlatform.android, web: true),
        isFalse,
      );
    },
  );

  test('chemins avec barres obliques inverses : le nom est bien extrait', () {
    expect(
      peut(r'C:\cache\image_picker_1.jpg', TargetPlatform.android),
      isTrue,
    );
  });
}
