// Firebase project: smart-mushroom-farm-d76c6 (Realtime Database in Singapore).
// Written by hand from the Firebase console (Project settings -> Your apps).
// These are app identifiers, not passwords: the data is protected by the
// Realtime Database rules and sign-in.
//
// iOS is not registered yet. Add an Apple app in the console (bundle id
// ph.edu.mushroomfarm.mushroomFarm) and fill in `ios` when building for iPhone.

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) return web;
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      default:
        throw UnsupportedError('Firebase is not set up for $defaultTargetPlatform yet.');
    }
  }

  static const _apiKey = 'AIzaSyB0YMfOYx2R1ROLzKuzjdVHNLSm_sge36o';
  static const _projectId = 'smart-mushroom-farm-d76c6';
  static const _senderId = '668956168511';
  static const _databaseURL =
      'https://smart-mushroom-farm-d76c6-default-rtdb.asia-southeast1.firebasedatabase.app';
  static const _storageBucket = 'smart-mushroom-farm-d76c6.firebasestorage.app';

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: _apiKey,
    appId: '1:668956168511:android:756346214b1e723f30438a',
    messagingSenderId: _senderId,
    projectId: _projectId,
    databaseURL: _databaseURL,
    storageBucket: _storageBucket,
  );

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: _apiKey,
    appId: '1:668956168511:web:c2668e5aeced978030438a',
    messagingSenderId: _senderId,
    projectId: _projectId,
    authDomain: 'smart-mushroom-farm-d76c6.firebaseapp.com',
    databaseURL: _databaseURL,
    storageBucket: _storageBucket,
  );
}
