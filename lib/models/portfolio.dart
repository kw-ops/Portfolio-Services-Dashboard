import 'package:cloud_firestore/cloud_firestore.dart';

class ServiceItem {
  final String id;
  final String name;
  final String description;
  final num? priceFrom;

  const ServiceItem({required this.id, required this.name, this.description = '', this.priceFrom});

  factory ServiceItem.fromMap(Map<String, dynamic> m) => ServiceItem(
    id: m['id'] as String? ?? '',
    name: m['name'] as String? ?? '',
    description: m['description'] as String? ?? '',
    priceFrom: m['priceFrom'] as num?,
  );

  Map<String, dynamic> toMap() => {
    'id': id,
    'name': name,
    'description': description,
    'priceFrom': priceFrom,
  };
}

/// A service provider and its public portfolio (`providers/{id}`).
///
/// Imported from Campus Stay's `service_providers` (same document id) by the
/// syncCampusStay function. Campus Stay owns name, description, category,
/// location, phone, whatsapp, services list, photos and status; the PSD-only
/// fields are slug, tagline, hours, email, logo, cover, extra gallery photos
/// and service prices/descriptions.
class Portfolio {
  final String id;
  final String slug;
  final String name;
  final String category;
  final String tagline;
  final String description;
  final String location;
  final String hours;
  final String phone;
  final String whatsapp;
  final String email;
  final String? logoUrl;
  final String? coverUrl;
  final List<String> gallery;
  final List<String> csPhotos;
  final List<ServiceItem> services;
  final String status;
  final String? campusStayId;
  final bool isVerified;
  final DateTime? syncedAt;
  final String? ownerUid;
  final int requestCounter;
  final DateTime? createdAt;

  const Portfolio({
    required this.id,
    required this.slug,
    required this.name,
    required this.category,
    this.tagline = '',
    this.description = '',
    this.location = '',
    this.hours = '',
    this.phone = '',
    this.whatsapp = '',
    this.email = '',
    this.logoUrl,
    this.coverUrl,
    this.gallery = const [],
    this.csPhotos = const [],
    this.services = const [],
    this.status = 'active',
    this.campusStayId,
    this.isVerified = false,
    this.syncedAt,
    this.ownerUid,
    this.requestCounter = 0,
    this.createdAt,
  });

  bool get isActive => status == 'active';

  /// PSD cover if one was uploaded, otherwise the first Campus Stay photo.
  String? get coverImage => coverUrl ?? (csPhotos.isNotEmpty ? csPhotos.first : null);

  /// Campus Stay photos followed by extra photos added in PSD.
  List<String> get photos => [...csPhotos, ...gallery];

  factory Portfolio.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final m = doc.data() ?? {};
    return Portfolio(
      id: doc.id,
      slug: m['slug'] as String? ?? '',
      name: m['name'] as String? ?? '',
      category: m['category'] as String? ?? '',
      tagline: m['tagline'] as String? ?? '',
      description: m['description'] as String? ?? '',
      location: m['location'] as String? ?? '',
      hours: m['hours'] as String? ?? '',
      phone: m['phone'] as String? ?? '',
      whatsapp: m['whatsapp'] as String? ?? '',
      email: m['email'] as String? ?? '',
      logoUrl: m['logoUrl'] as String?,
      coverUrl: m['coverUrl'] as String?,
      gallery: List<String>.from(m['gallery'] as List? ?? const []),
      csPhotos: List<String>.from(m['csPhotos'] as List? ?? const []),
      services: (m['services'] as List? ?? const [])
          .map((e) => ServiceItem.fromMap(Map<String, dynamic>.from(e as Map)))
          .toList(),
      status: m['status'] as String? ?? 'active',
      campusStayId: m['campusStayId'] as String?,
      isVerified: m['isVerified'] as bool? ?? false,
      syncedAt: (m['syncedAt'] as Timestamp?)?.toDate(),
      ownerUid: m['ownerUid'] as String?,
      requestCounter: (m['requestCounter'] as num?)?.toInt() ?? 0,
      createdAt: (m['createdAt'] as Timestamp?)?.toDate(),
    );
  }
}
