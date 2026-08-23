import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

/// Connection details for the `luqma-edku` project.
///
/// Hand-written rather than produced by `flutterfire configure`, and shared by all three
/// apps: they sit on one project, so the only thing that differs between them is the app
/// id. A generated file per app would be four copies of the same thing drifting apart.
///
/// None of this is secret. A Firebase config identifies a project; it grants nothing. The
/// key is in every APK and in the JavaScript of every Firebase web app on the internet.
/// What actually decides who can read what is the signed-in user and the security rules
/// in `firebase/firestore.rules`.
abstract final class LuqmaFirebase {
  const LuqmaFirebase._();

  static const projectId = 'luqma-edku';
  static const messagingSenderId = '718707520076';
  static const storageBucket = '$projectId.firebasestorage.app';

  /// One key for all three Android apps — that is how Firebase issues it.
  static const _androidApiKey = 'AIzaSyDNRBrTJYXXKs0yyskVw9omWKgEMjAspOk';

  /// The **web** OAuth client id, which Google Sign-In on Android needs in order to ask
  /// for an ID token Firebase will accept.
  ///
  /// Normally the plugin reads this out of `google-services.json` as
  /// `default_web_client_id`. This project does not ship that file — see the note at the
  /// top of this class — so it is passed explicitly instead.
  ///
  /// Firebase creates it the moment Google is enabled as a sign-in provider. Until then
  /// it is empty and sign-in fails on a real device with a clear message; see
  /// `googleCredential()` in CustomerApp.
  ///
  /// Not a secret. It identifies the project's OAuth client and grants nothing on its
  /// own — it is in the `google-services.json` of every Firebase Android app there is.
  static const googleServerClientId = '';

  static const _android = FirebaseOptions(
    apiKey: _androidApiKey,
    appId: '1:718707520076:android:7f8b0bee40fcc31bc8fae9',
    messagingSenderId: messagingSenderId,
    projectId: projectId,
    storageBucket: storageBucket,
  );

  static const _web = FirebaseOptions(
    apiKey: 'AIzaSyCdJEYzMYLh0mUbtEh7C9Y4sfbpOBPqa2k',
    appId: '1:718707520076:web:884c309df2fac873c8fae9',
    messagingSenderId: messagingSenderId,
    projectId: projectId,
    authDomain: '$projectId.firebaseapp.com',
    storageBucket: storageBucket,
  );

  static const _customerAndroid = FirebaseOptions(
    apiKey: _androidApiKey,
    appId: '1:718707520076:android:b605590f4cf06ff8c8fae9',
    messagingSenderId: messagingSenderId,
    projectId: projectId,
    storageBucket: storageBucket,
  );

  static const _merchantAndroid = FirebaseOptions(
    apiKey: _androidApiKey,
    appId: '1:718707520076:android:3d3a03064a162165c8fae9',
    messagingSenderId: messagingSenderId,
    projectId: projectId,
    storageBucket: storageBucket,
  );

  /// AdminApp is the one Luqma app that runs in a browser as well as on a phone, so it
  /// is the one that has to pick.
  static FirebaseOptions get admin => kIsWeb ? _web : _android;

  static FirebaseOptions get customer => _customerAndroid;
  static FirebaseOptions get merchant => _merchantAndroid;
}
