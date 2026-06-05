import 'package:flutter/material.dart';
import '../models/user_session.dart';
import '../services/api_service.dart';
import '../services/auth_store.dart';
import '../widgets/gradient_shell.dart';

class LoginScreen extends StatefulWidget {
  final void Function(UserSession) onLogin;
  const LoginScreen({super.key, required this.onLogin});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final api = const ApiService();
  final store = AuthStore();
  final username = TextEditingController(text: 'abcd');
  final password = TextEditingController(text: '123456');
  bool loading = false;
  String? error;

  Future<void> submit() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final session = await api.login(username.text.trim(), password.text);
      await store.save(session);
      widget.onLogin(session);
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: GradientShell(
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(color: const Color(0xFF101828), borderRadius: BorderRadius.circular(28)),
                      child: const Icon(Icons.forum_rounded, color: Colors.white, size: 34),
                    ),
                    const SizedBox(height: 24),
                    const Text('Blinlin', style: TextStyle(fontSize: 48, fontWeight: FontWeight.w900, letterSpacing: -2)),
                    Text('社区动态和即时通讯汇聚在一个优雅的空间。', style: TextStyle(fontSize: 16, height: 1.6, color: Colors.black.withOpacity(.58))),
                    const SizedBox(height: 28),
                    _field(username, '账号', Icons.person_rounded),
                    const SizedBox(height: 14),
                    _field(password, '密码', Icons.lock_rounded, obscure: true),
                    if (error != null) ...[
                      const SizedBox(height: 12),
                      Text(error!, style: const TextStyle(color: Colors.red, fontWeight: FontWeight.w700)),
                    ],
                    const SizedBox(height: 22),
                    SizedBox(
                      width: double.infinity,
                      height: 58,
                      child: FilledButton(
                        style: FilledButton.styleFrom(backgroundColor: const Color(0xFF101828), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20))),
                        onPressed: loading ? null : submit,
                        child: loading ? const CircularProgressIndicator(color: Colors.white) : const Text('进入社区', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _field(TextEditingController c, String label, IconData icon, {bool obscure = false}) {
    return TextField(
      controller: c,
      obscureText: obscure,
      decoration: InputDecoration(
        prefixIcon: Icon(icon),
        labelText: label,
        filled: true,
        fillColor: Colors.white.withOpacity(.82),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none),
      ),
    );
  }
}
