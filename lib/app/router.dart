import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../admin/admin_dashboard_page.dart';
import '../admin/admin_requests_page.dart';
import '../admin/provider_detail_page.dart';
import '../auth/login_page.dart';
import '../provider/edit_portfolio_page.dart';
import '../provider/provider_dashboard_page.dart';
import '../provider/request_detail_page.dart';
import '../public/landing_page.dart';
import '../public/portfolio_page.dart';
import '../public/service_request_page.dart';
import '../widgets/common.dart';
import 'session.dart';

/// Routes (hash URLs, so they work on GitHub Pages):
///   `#/p/<slug>`              public portfolio  ← the link pasted into Campus Stay
///   `#/p/<slug>/request`      service request form
///   #/login
///   #/dashboard/...           provider area
///   #/admin/...               PSD admin area
final router = GoRouter(
  routes: [
    GoRoute(path: '/', builder: (_, _) => const LandingPage()),
    GoRoute(path: '/login', builder: (_, _) => const LoginPage()),
    GoRoute(
      path: '/p/:slug',
      builder: (_, s) =>
          PortfolioPage(slug: s.pathParameters['slug']!, source: s.uri.queryParameters['source']),
      routes: [
        GoRoute(
          path: 'request',
          builder: (_, s) => ServiceRequestPage(
            slug: s.pathParameters['slug']!,
            source: s.uri.queryParameters['source'],
            serviceId: s.uri.queryParameters['service'],
          ),
        ),
      ],
    ),
    GoRoute(
      path: '/dashboard',
      builder: (_, _) => RoleGate(
        role: 'provider',
        builder: (_) => ProviderDashboardPage(providerId: session.profile!.providerId!),
      ),
      routes: [
        GoRoute(
          path: 'requests/:id',
          builder: (_, s) => RoleGate(
            role: 'provider',
            builder: (_) => RequestDetailPage(requestId: s.pathParameters['id']!, isAdmin: false),
          ),
        ),
        GoRoute(
          path: 'portfolio',
          builder: (_, _) => RoleGate(
            role: 'provider',
            builder: (_) => EditPortfolioPage(providerId: session.profile!.providerId!, isAdmin: false),
          ),
        ),
      ],
    ),
    GoRoute(
      path: '/admin',
      builder: (_, _) => RoleGate(role: 'admin', builder: (_) => const AdminDashboardPage()),
      routes: [
        GoRoute(
          path: 'providers/:id',
          builder: (_, s) => RoleGate(
            role: 'admin',
            builder: (_) => ProviderDetailPage(providerId: s.pathParameters['id']!),
          ),
        ),
        GoRoute(
          path: 'providers/:id/edit',
          builder: (_, s) => RoleGate(
            role: 'admin',
            builder: (_) => EditPortfolioPage(providerId: s.pathParameters['id']!, isAdmin: true),
          ),
        ),
        GoRoute(
          path: 'requests',
          builder: (_, s) => RoleGate(
            role: 'admin',
            builder: (_) => AdminRequestsPage(providerId: s.uri.queryParameters['provider']),
          ),
        ),
        GoRoute(
          path: 'requests/:id',
          builder: (_, s) => RoleGate(
            role: 'admin',
            builder: (_) => RequestDetailPage(requestId: s.pathParameters['id']!, isAdmin: true),
          ),
        ),
      ],
    ),
  ],
  errorBuilder: (context, state) => Scaffold(
    body: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Page not found'),
          TextButton(onPressed: () => context.go('/'), child: const Text('Home')),
        ],
      ),
    ),
  ),
);
