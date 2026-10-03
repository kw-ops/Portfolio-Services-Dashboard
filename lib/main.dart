import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'app/router.dart';
import 'app/session.dart';
import 'app/theme.dart';
import 'firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  session = Session();
  runApp(const PsdApp());
}

class PsdApp extends StatelessWidget {
  const PsdApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp.router(
        title: 'Campus Stay Services',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(),
        routerConfig: router,
      );
}
