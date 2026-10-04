import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';

import '../config.dart';
import '../models/portfolio.dart';
import '../models/service_request.dart';

typedef CampusStayStudent = ({String name, String phone, String email, String school, String hostel});

/// All Firebase access for the app goes through here.
class Api {
  Api._();

  static final _db = FirebaseFirestore.instance;
  static final _storage = FirebaseStorage.instance;
  static final _functions = FirebaseFunctions.instanceFor(region: kFunctionsRegion);

  static CollectionReference<Map<String, dynamic>> get _providers => _db.collection('providers');
  static CollectionReference<Map<String, dynamic>> get _requests => _db.collection('serviceRequests');

  // ---------------------------------------------------------------- portfolios

  /// Resolves a public slug to its portfolio. Returns null when the slug does
  /// not exist or the provider is suspended (rules deny the read).
  static Future<Portfolio?> portfolioBySlug(String slug) async {
    try {
      final s = await _db.doc('slugs/$slug').get();
      final providerId = s.data()?['providerId'] as String?;
      if (providerId == null) return null;
      final doc = await _providers.doc(providerId).get();
      return doc.exists ? Portfolio.fromDoc(doc) : null;
    } on FirebaseException catch (e) {
      if (e.code == 'permission-denied') return null;
      rethrow;
    }
  }

  static Stream<Portfolio?> watchPortfolio(String id) =>
      _providers.doc(id).snapshots().map((d) => d.exists ? Portfolio.fromDoc(d) : null);

  static Stream<List<Portfolio>> watchAllPortfolios() => _providers
      .orderBy('createdAt', descending: true)
      .snapshots()
      .map((q) => q.docs.map(Portfolio.fromDoc).toList());

  static Future<void> updatePortfolio(String id, Map<String, dynamic> data) =>
      _providers.doc(id).update({...data, 'updatedAt': FieldValue.serverTimestamp()});

  /// Uploads a public portfolio image and returns its download URL.
  static Future<String> uploadPortfolioImage(String providerId, XFile file, String kind) async {
    final bytes = await file.readAsBytes();
    final ext = _ext(file.name);
    final ref = _storage.ref('portfolios/$providerId/$kind/${DateTime.now().millisecondsSinceEpoch}.$ext');
    await ref.putData(bytes, SettableMetadata(contentType: _contentType(file, ext)));
    return ref.getDownloadURL();
  }

  /// Admin only. Imports/refreshes providers from Campus Stay now
  /// (it also runs automatically every 30 minutes).
  static Future<({int created, int updated, int removed, int total})> syncCampusStay() async {
    final res = await _functions.httpsCallable('syncCampusStay').call();
    final m = Map<String, dynamic>.from(res.data as Map);
    int n(String k) => (m[k] as num?)?.toInt() ?? 0;
    return (created: n('created'), updated: n('updated'), removed: n('removed'), total: n('total'));
  }

  /// Admin only: when the last Campus Stay sync finished.
  static Stream<DateTime?> watchLastSync() =>
      _db.doc('config/sync').snapshots().map((d) => (d.data()?['lastSyncedAt'] as Timestamp?)?.toDate());

  /// Makes the signed-in Google account the admin if it is the allowed
  /// ADMIN_EMAIL and no admin exists yet (or it already is the admin).
  static Future<void> claimAdmin() => _functions.httpsCallable('claimAdmin').call();

  /// Admin only. Creates (or links) the login the provider uses for their dashboard.
  /// Returns true when the email already had an account (its password is unchanged).
  static Future<bool> createProviderAccount({
    required String providerId,
    required String email,
    required String password,
    required String displayName,
  }) async {
    final res = await _functions.httpsCallable('createProviderAccount').call({
      'providerId': providerId,
      'email': email,
      'password': password,
      'displayName': displayName,
    });
    return (res.data as Map)['existed'] == true;
  }

  /// Admin only: login emails linked to a provider.
  static Future<List<String>> providerAccountEmails(String providerId) async {
    final q = await _db.collection('users').where('providerId', isEqualTo: providerId).get();
    return q.docs.map((d) => d.data()['email'] as String? ?? d.id).toList();
  }

  // ------------------------------------------------------------------ requests

  static Stream<List<ServiceRequest>> watchProviderRequests(String providerId) => _requests
      .where('providerId', isEqualTo: providerId)
      .orderBy('createdAt', descending: true)
      .limit(300)
      .snapshots()
      .map((q) => q.docs.map(ServiceRequest.fromDoc).toList());

  static Stream<List<ServiceRequest>> watchAllRequests() => _requests
      .orderBy('createdAt', descending: true)
      .limit(300)
      .snapshots()
      .map((q) => q.docs.map(ServiceRequest.fromDoc).toList());

  static Stream<ServiceRequest?> watchRequest(String id) =>
      _requests.doc(id).snapshots().map((d) => d.exists ? ServiceRequest.fromDoc(d) : null);

  static Future<void> updateRequestStatus(String requestId, String status, {String note = ''}) => _functions
      .httpsCallable('updateRequestStatus')
      .call({'requestId': requestId, 'status': status, 'note': note});

  /// Students don't have accounts; an anonymous session lets them upload
  /// photos and call `submitRequest` without exposing anything else.
  static Future<User> _ensureSignedIn() async {
    final auth = FirebaseAuth.instance;
    return auth.currentUser ?? (await auth.signInAnonymously()).user!;
  }

  /// Uploads a student's photos to their temporary upload folder. The
  /// `submitRequest` function moves them into the private request folder.
  static Future<List<String>> uploadRequestPhotos(List<XFile> files) async {
    final user = await _ensureSignedIn();
    final paths = <String>[];
    for (var i = 0; i < files.length; i++) {
      final f = files[i];
      final ext = _ext(f.name);
      final path = 'uploads/${user.uid}/${DateTime.now().millisecondsSinceEpoch}_$i.$ext';
      await _storage
          .ref(path)
          .putData(await f.readAsBytes(), SettableMetadata(contentType: _contentType(f, ext)));
      paths.add(path);
    }
    return paths;
  }

  /// Signs the student in with Google and returns their Campus Stay details
  /// (name, phone, email, school, hostel) to pre-fill the request form.
  /// Throws a [FirebaseFunctionsException] (not-found) for non-students.
  static Future<CampusStayStudent> campusStayProfile() async {
    final auth = FirebaseAuth.instance;
    final isGoogle = auth.currentUser?.providerData.any((p) => p.providerId == 'google.com') ?? false;
    if (!isGoogle) {
      await auth.signInWithPopup(GoogleAuthProvider()..setCustomParameters({'prompt': 'select_account'}));
    }
    final res = await _functions.httpsCallable('campusStayProfile').call();
    final m = Map<String, dynamic>.from(res.data as Map);
    String f(String k) => m[k] as String? ?? '';
    return (name: f('name'), phone: f('phone'), email: f('email'), school: f('school'), hostel: f('hostel'));
  }

  /// Returns the request reference number, e.g. `PD-0007`.
  static Future<String> submitRequest(Map<String, dynamic> data) async {
    await _ensureSignedIn();
    final res = await _functions.httpsCallable('submitRequest').call(data);
    return (res.data as Map)['ref'] as String;
  }

  static Future<String> attachmentUrl(String path) => _storage.ref(path).getDownloadURL();

  // --------------------------------------------------------------------- stats

  static Future<int> count(Query<Map<String, dynamic>> q) async => (await q.count().get()).count ?? 0;

  static Query<Map<String, dynamic>> get allProvidersQuery => _providers;
  static Query<Map<String, dynamic>> get allRequestsQuery => _requests;

  // ------------------------------------------------------------------- helpers

  static String _ext(String name) {
    final dot = name.lastIndexOf('.');
    return dot == -1 ? 'jpg' : name.substring(dot + 1).toLowerCase();
  }

  static String _contentType(XFile f, String ext) =>
      f.mimeType ??
      (ext == 'png'
          ? 'image/png'
          : ext == 'webp'
          ? 'image/webp'
          : 'image/jpeg');
}

/// Turns Firebase/Functions errors into a message a person can act on.
String friendlyError(Object e) {
  if (e is FirebaseFunctionsException) return e.message ?? e.code;
  if (e is FirebaseAuthException) {
    return switch (e.code) {
      'invalid-credential' || 'wrong-password' || 'user-not-found' => 'Wrong email or password.',
      'too-many-requests' => 'Too many attempts. Try again in a few minutes.',
      _ => e.message ?? e.code,
    };
  }
  if (e is FirebaseException) {
    if (e.code == 'permission-denied') return 'You don\'t have permission to do that.';
    return e.message ?? e.code;
  }
  return e.toString();
}
