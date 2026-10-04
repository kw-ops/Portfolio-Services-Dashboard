import 'package:flutter/material.dart';

/// Region the Cloud Functions are deployed to (must match functions/index.js).
const String kFunctionsRegion = 'europe-west1';

/// Value of `?source=` that Campus Stay links carry.
const String kSourceCampusStay = 'campus_stay';

/// Request lifecycle. Allowed transitions are enforced by the
/// `updateRequestStatus` Cloud Function; this map only drives the UI.
const Map<String, List<String>> kNextStatuses = {
  'pending': ['accepted', 'rejected'],
  'accepted': ['scheduled', 'in_progress', 'cancelled'],
  'scheduled': ['in_progress', 'cancelled'],
  'in_progress': ['completed', 'cancelled'],
  'completed': [],
  'rejected': [],
  'cancelled': [],
};

const List<String> kStatusOrder = [
  'pending',
  'accepted',
  'scheduled',
  'in_progress',
  'completed',
  'rejected',
  'cancelled',
];

String statusLabel(String s) => switch (s) {
  'pending' => 'New',
  'accepted' => 'Accepted',
  'scheduled' => 'Scheduled',
  'in_progress' => 'In progress',
  'completed' => 'Completed',
  'rejected' => 'Rejected',
  'cancelled' => 'Cancelled',
  _ => s,
};

String statusActionLabel(String s) => switch (s) {
  'accepted' => 'Accept',
  'rejected' => 'Reject',
  'scheduled' => 'Mark scheduled',
  'in_progress' => 'Start work',
  'completed' => 'Mark completed',
  'cancelled' => 'Cancel',
  _ => statusLabel(s),
};

Color statusColor(String s) => switch (s) {
  'pending' => const Color(0xFFF59E0B),
  'accepted' => const Color(0xFF3B82F6),
  'scheduled' => const Color(0xFF8B5CF6),
  'in_progress' => const Color(0xFF0EA5E9),
  'completed' => const Color(0xFF10B981),
  'rejected' => const Color(0xFFEF4444),
  'cancelled' => const Color(0xFF6B7280),
  _ => Colors.grey,
};

String sourceLabel(String s) => s == kSourceCampusStay ? 'Campus Stay Ghana' : 'Direct link';

/// Public, permanent link for a portfolio — this is what gets pasted into
/// Campus Stay admin. Built from the current page address, so it is correct
/// on localhost and on GitHub Pages without any configuration.
String portfolioUrl(String slug, {bool campusStay = true}) {
  final base = Uri.base;
  final root = '${base.origin}${base.path}';
  return '$root#/p/$slug${campusStay ? '?source=$kSourceCampusStay' : ''}';
}

/// wa.me needs international format; converts Ghana local numbers (024…) to 23324….
String? whatsappLink(String? phone, {String? text}) {
  if (phone == null) return null;
  var digits = phone.replaceAll(RegExp(r'\D'), '');
  if (digits.isEmpty) return null;
  if (digits.startsWith('0')) digits = '233${digits.substring(1)}';
  final q = text == null ? '' : '?text=${Uri.encodeComponent(text)}';
  return 'https://wa.me/$digits$q';
}

/// "Plug Doctor & Co." -> "plug-doctor-and-co"
String slugify(String s) => s
    .toLowerCase()
    .replaceAll('&', ' and ')
    .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
    .replaceAll(RegExp(r'^-+|-+$'), '');
