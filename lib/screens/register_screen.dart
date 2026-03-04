import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import 'home_screen.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  bool _isSubmitting = false;
  String? _errorMessage;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _register() async {
    final auth = Provider.of<AuthService>(context, listen: false);
    if (_passwordController.text != _confirmController.text) {
      setState(() {
        _errorMessage = 'Passwoerter stimmen nicht ueberein.';
      });
      return;
    }
    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });
    try {
      if (auth.isGuest) {
        await auth.upgradeGuestToAccount(
          _emailController.text,
          _passwordController.text,
        );
      } else {
        await auth.register(_emailController.text, _passwordController.text);
      }
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

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();

    return Scaffold(
      appBar: AppBar(title: Text('Registrieren')),
      body: Padding(
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
            if (auth.isGuest)
              Card(
                color: Colors.teal.shade900,
                child: const Padding(
                  padding: EdgeInsets.all(12),
                  child: Text(
                    'Du bist aktuell als Gast angemeldet. Mit der Registrierung wird deine Session als Konto uebernommen.',
                    style: TextStyle(color: Colors.white),
                  ),
                ),
              ),
            if (auth.isGuest) const SizedBox(height: 12),
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
            TextField(
              controller: _confirmController,
              decoration: InputDecoration(labelText: 'Passwort bestaetigen'),
              obscureText: true,
              enabled: !_isSubmitting,
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _isSubmitting ? null : _register,
              child: const Text('Registrieren'),
            ),
          ],
        ),
      ),
    );
  }
}
