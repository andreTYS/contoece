import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not supported for this platform.',
        );
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyCo9YRMQtJxJxzzfDzaBXZam44qWIJIp80',
    appId: '1:1036373712732:web:6382ee879c67c71674eb99',
    messagingSenderId: '1036373712732',
    projectId: 'contrataciones-790a0',
    authDomain: 'contrataciones-790a0.firebaseapp.com',
    storageBucket: 'contrataciones-790a0.firebasestorage.app',
    measurementId: 'G-WFJE12HN6K',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyAHt06UwWVL2XLcJ3jCycIEvjIQqaL0kSw',
    appId: '1:1036373712732:android:4075892a7732ba9474eb99',
    messagingSenderId: '1036373712732',
    projectId: 'contrataciones-790a0',
    storageBucket: 'contrataciones-790a0.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'TU_API_KEY_IOS',
    appId: 'TU_APP_ID_IOS',
    messagingSenderId: 'TU_SENDER_ID',
    projectId: 'TU_PROJECT_ID',
    storageBucket: 'TU_PROJECT_ID.appspot.com',
    iosClientId: 'TU_IOS_CLIENT_ID',
    iosBundleId: 'com.oece.contrataciones',
  );
}
