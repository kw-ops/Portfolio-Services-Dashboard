import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_services_dashboard/app/theme.dart';
import 'package:portfolio_services_dashboard/models/portfolio.dart';
import 'package:portfolio_services_dashboard/models/service_request.dart';
import 'package:portfolio_services_dashboard/provider/request_detail_page.dart';
import 'package:portfolio_services_dashboard/public/portfolio_page.dart';
import 'package:portfolio_services_dashboard/widgets/common.dart';
import 'package:portfolio_services_dashboard/widgets/request_tile.dart';

/// Renders shared layout pieces at phone, tablet and desktop widths and
/// fails on any overflow ("RenderFlex overflowed…" is reported as an exception).
const sizes = {
  'small phone': Size(320, 640),
  'phone': Size(390, 844),
  'tablet': Size(820, 1180),
  'desktop': Size(1440, 900),
};

ServiceRequest _request({String status = 'pending'}) => ServiceRequest(
      id: 'r1',
      ref: 'PD-0001',
      providerId: 'p1',
      providerName: 'Plug Doctor Laptop & Phone Repairs Kumasi',
      serviceId: 'laptop-repair',
      serviceName: 'Laptop repair and Windows installation with data backup',
      studentName: 'Kwame Mensah-Bonsu Adjei',
      studentPhone: '0241234567',
      studentEmail: 'kwame@example.com',
      studentVerified: true,
      studentSchool: 'KNUST',
      location: 'Unity Hall, KNUST, Kumasi, Ashanti Region',
      preferredDate: '2026-10-10',
      preferredTime: '2:00 PM',
      description: 'My HP EliteBook turns off after about ten minutes of use and the fan is very loud.',
      attachments: const [],
      sourcePlatform: 'campus_stay',
      status: status,
      statusHistory: [
        StatusChange(status: 'pending', at: DateTime(2026, 10, 4, 14, 30)),
        StatusChange(status: 'accepted', at: DateTime(2026, 10, 4, 15), note: 'Will come by after lectures'),
      ],
      createdAt: DateTime(2026, 10, 4, 14, 30),
    );

const _portfolio = Portfolio(
  id: 'p1',
  slug: 'plug-doctor',
  name: 'Plug Doctor Laptop & Phone Repairs Kumasi',
  category: 'Appliance Repair · Laptop Repair',
  tagline: 'Fast, affordable laptop and phone repairs right on campus, same-day service available',
  description: 'We fix laptops, phones and tablets for students. Screen replacement, battery replacement, '
      'Windows and macOS installation, data recovery and more. Over 500 students served since 2022.',
  location: 'Ayeduase, Kwame Nkrumah University of Science and Technology, Kumasi',
  hours: 'Mon–Sat, 8am–8pm · Sunday by appointment',
  phone: '0241234567',
  email: 'plugdoctor.repairs.kumasi@example.com',
  isVerified: true,
  services: [
    ServiceItem(id: 'a', name: 'Screen replacement for all laptop brands', description: 'HP, Dell, Lenovo, Mac', priceFrom: 450),
    ServiceItem(id: 'b', name: 'Windows installation', priceFrom: 80),
    ServiceItem(id: 'c', name: 'Battery replacement'),
  ],
);

Future<void> _pump(WidgetTester tester, Size size, Widget child) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    theme: buildTheme(),
    home: Scaffold(body: SingleChildScrollView(child: Bounded(child: child))),
  ));
  await tester.pumpAndSettle();
}

void main() {
  for (final e in sizes.entries) {
    testWidgets('stats grid fits at ${e.key}', (tester) async {
      await _pump(
        tester,
        e.value,
        const StatGrid(children: [
          StatTile(label: 'Providers', value: '128'),
          StatTile(label: 'Active portfolios', value: '120'),
          StatTile(label: 'Total requests', value: '10482'),
          StatTile(label: 'New (pending)', value: '37'),
          StatTile(label: 'Completed', value: '9001'),
          StatTile(label: 'From Campus Stay', value: '8730'),
        ]),
      );
      expect(tester.takeException(), isNull);
      // At least two tiles per row on every screen.
      final first = tester.getRect(find.byType(StatTile).at(0));
      final second = tester.getRect(find.byType(StatTile).at(1));
      expect(second.top, first.top);
    });

    testWidgets('request tiles and filter bar fit at ${e.key}', (tester) async {
      await _pump(
        tester,
        e.value,
        Column(children: [
          RequestFilterBar(value: RequestFilter.open, requests: [_request()], onChanged: (_) {}),
          for (final s in ['pending', 'in_progress', 'cancelled'])
            RequestTile(request: _request(status: s), showProvider: true, onTap: () {}),
        ]),
      );
      expect(tester.takeException(), isNull);
    });
  }

  for (final e in sizes.entries) {
    testWidgets('public portfolio fits at ${e.key}', (tester) async {
      tester.view.physicalSize = e.value;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        theme: buildTheme(),
        home: PortfolioView(portfolio: _portfolio, source: 'campus_stay', onRequest: ([_]) {}),
      ));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Request a service'), findsOneWidget);
    });

    testWidgets('request detail fits at ${e.key}', (tester) async {
      await _pump(tester, e.value, RequestDetailBody(request: _request(status: 'accepted'), isAdmin: true));
      expect(tester.takeException(), isNull);
      expect(find.text('Mark scheduled'), findsOneWidget);
    });
  }
}
