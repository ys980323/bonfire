import 'package:flutter/material.dart';
import 'screens/campfire_screen.dart';

class BonfireApp extends StatelessWidget {
  const BonfireApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Bonfire',
      theme: ThemeData.dark().copyWith(scaffoldBackgroundColor: Colors.black),
      home: const CampfireScreen(),
    );
  }
}
