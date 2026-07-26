import 'package:flutter/material.dart';

/// Shown briefly at startup while [AuthProvider] checks for a saved
/// session. The router moves away from here automatically once that
/// check finishes.
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}
