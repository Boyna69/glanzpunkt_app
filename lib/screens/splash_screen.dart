import 'package:flutter/material.dart';
import 'dart:async';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';

import 'login_screen.dart';
import 'home_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _bootstrapAndRoute();
  }

  Future<void> _bootstrapAndRoute() async {
    final auth = context.read<AuthService>();
    await Future.wait([
      Future<void>.delayed(const Duration(seconds: 3)),
      auth.ready,
    ]);
    if (!mounted) {
      return;
    }

    final destination = auth.isLoggedIn
        ? const HomeScreen()
        : const LoginScreen();
    Navigator.of(
      context,
    ).pushReplacement(MaterialPageRoute(builder: (_) => destination));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A1A2F),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset(
              'assets/images/glanzpunkt_logo.png',
              width: 128,
              height: 128,
            ),
            const SizedBox(height: 14),
            const Text(
              'Glanzpunkt',
              style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Schnell. Sauber. Smart.',
              style: TextStyle(color: Colors.white70),
            ),
          ],
        ),
      ),
    );
  }
}
