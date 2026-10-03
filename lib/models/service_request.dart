import 'package:cloud_firestore/cloud_firestore.dart';

class StatusChange {
  final String status;
  final DateTime? at;
  final String note;

  const StatusChange({required this.status, this.at, this.note = ''});

  factory StatusChange.fromMap(Map<String, dynamic> m) => StatusChange(
        status: m['status'] as String? ?? '',
        at: (m['at'] as Timestamp?)?.toDate(),
        note: m['note'] as String? ?? '',
      );
}

/// A student's request to a provider (`serviceRequests/{id}`).
/// Created only by the `submitRequest` Cloud Function.
class ServiceRequest {
  final String id;
  final String ref;
  final String providerId;
  final String providerName;
  final String serviceId;
  final String serviceName;
  final String studentName;
  final String studentPhone;
  final String studentEmail;

  /// True when the student signed in with their Campus Stay account.
  final bool studentVerified;
  final String studentSchool;
  final String location;
  final String preferredDate;
  final String preferredTime;
  final String description;
  final List<String> attachments;
  final String sourcePlatform;
  final String status;
  final List<StatusChange> statusHistory;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const ServiceRequest({
    required this.id,
    required this.ref,
    required this.providerId,
    required this.providerName,
    required this.serviceId,
    required this.serviceName,
    required this.studentName,
    required this.studentPhone,
    required this.studentEmail,
    this.studentVerified = false,
    this.studentSchool = '',
    required this.location,
    required this.preferredDate,
    required this.preferredTime,
    required this.description,
    required this.attachments,
    required this.sourcePlatform,
    required this.status,
    required this.statusHistory,
    this.createdAt,
    this.updatedAt,
  });

  factory ServiceRequest.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final m = doc.data() ?? {};
    return ServiceRequest(
      id: doc.id,
      ref: m['ref'] as String? ?? doc.id,
      providerId: m['providerId'] as String? ?? '',
      providerName: m['providerName'] as String? ?? '',
      serviceId: m['serviceId'] as String? ?? '',
      serviceName: m['serviceName'] as String? ?? '',
      studentName: m['studentName'] as String? ?? '',
      studentPhone: m['studentPhone'] as String? ?? '',
      studentEmail: m['studentEmail'] as String? ?? '',
      studentVerified: m['studentVerified'] as bool? ?? false,
      studentSchool: m['studentSchool'] as String? ?? '',
      location: m['location'] as String? ?? '',
      preferredDate: m['preferredDate'] as String? ?? '',
      preferredTime: m['preferredTime'] as String? ?? '',
      description: m['description'] as String? ?? '',
      attachments: List<String>.from(m['attachments'] as List? ?? const []),
      sourcePlatform: m['sourcePlatform'] as String? ?? 'direct',
      status: m['status'] as String? ?? 'pending',
      statusHistory: (m['statusHistory'] as List? ?? const [])
          .map((e) => StatusChange.fromMap(Map<String, dynamic>.from(e as Map)))
          .toList(),
      createdAt: (m['createdAt'] as Timestamp?)?.toDate(),
      updatedAt: (m['updatedAt'] as Timestamp?)?.toDate(),
    );
  }
}
