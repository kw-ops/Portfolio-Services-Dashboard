import 'package:firebase_core/firebase_core.dart';

/// Web config for the `portfolio-services-dashboard` Firebase project.
/// These values are public identifiers, not secrets — access is controlled
/// by firestore.rules and storage.rules.
class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform => web;

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyDgSQ8s-9ez3-X5voPF4ezAFT-0_tNFmKE',
    authDomain: 'portfolio-services-dashboard.firebaseapp.com',
    projectId: 'portfolio-services-dashboard',
    storageBucket: 'portfolio-services-dashboard.firebasestorage.app',
    messagingSenderId: '145815525368',
    appId: '1:145815525368:web:78a28d619c6de7abc7680d',
    measurementId: 'G-XLW0V5KHCP',
  );
}
