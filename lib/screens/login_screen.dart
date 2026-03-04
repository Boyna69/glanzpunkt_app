import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import 'home_screen.dart';
import 'register_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isSubmitting = false;
  String? _errorMessage;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });
    try {
      final auth = Provider.of<AuthService>(context, listen: false);
      await auth.login(_emailController.text, _passwordController.text);
      if (!mounted) {
        return;
      }
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const HomeScreen()),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(
        () => _errorMessage = error.toString().replaceFirst('Exception: ', ''),
      );
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  Future<void> _continueAsGuest() async {
    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });
    try {
      final auth = Provider.of<AuthService>(context, listen: false);
      await auth.loginAsGuest();
      if (!mounted) {
        return;
      }
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const HomeScreen()),
      );
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Login')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              if (_isSubmitting) const LinearProgressIndicator(),
              if (_errorMessage != null && _errorMessage!.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  _errorMessage!,
                  style: const TextStyle(color: Colors.redAccent),
                  textAlign: TextAlign.center,
                ),
              ],
              const SizedBox(height: 24),
              Image.asset(
                'assets/images/glanzpunkt_logo.png',
                width: 92,
                height: 92,
              ),
              const SizedBox(height: 12),
              const Text(
                'Mach aus jeder Waesche einen Glanzpunkt.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 30),
              TextField(
                controller: _emailController,
                decoration: InputDecoration(labelText: 'E-Mail'),
                enabled: !_isSubmitting,
              ),
              TextField(
                controller: _passwordController,
                decoration: InputDecoration(labelText: 'Passwort'),
                obscureText: true,
                enabled: !_isSubmitting,
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: _isSubmitting ? null : _login,
                child: const Text('Login'),
              ),
              OutlinedButton(
                onPressed: _isSubmitting ? null : _continueAsGuest,
                child: const Text('Als Gast fortfahren'),
              ),
              TextButton(
                onPressed: _isSubmitting
                    ? null
                    : () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const RegisterScreen(),
                        ),
                      ),
                child: const Text('Registrieren'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
