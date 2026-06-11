import 'package:flutter/material.dart';
import '../models/user_session.dart';
import '../services/api_service.dart';
import '../services/auth_store.dart';
import '../widgets/blin_style.dart';

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
  void dispose() {
    username.dispose();
    password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: PageBackdrop(
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(22),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    padding: const EdgeInsets.fromLTRB(24, 24, 24, 28),
                    decoration: BoxDecoration(
                      gradient: BlinStyle.auroraGradient,
                      borderRadius: BorderRadius.circular(30),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: .14),
                      ),
                      boxShadow: [
                        BlinStyle.softShadow(.18),
                        BlinStyle.glowShadow(BlinStyle.purple, .14),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 58,
                              height: 58,
                              decoration: BoxDecoration(
                                gradient: BlinStyle.brandGradient,
                                borderRadius: BorderRadius.circular(22),
                                boxShadow: [
                                  BlinStyle.glowShadow(BlinStyle.cyan, .25),
                                ],
                              ),
                              child: const Icon(
                                Icons.hub_rounded,
                                color: Colors.white,
                                size: 32,
                              ),
                            ),
                            const Spacer(),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 7,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: .10),
                                borderRadius: BorderRadius.circular(999),
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: .18),
                                ),
                              ),
                              child: const Text(
                                'REALTIME SOCIAL',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  letterSpacing: .6,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 38),
                        const Text(
                          '搭个话',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 48,
                            height: .98,
                            letterSpacing: -1.4,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          '把动态、发现、消息和关系，放进一个有呼吸感的年轻社区。',
                          style: TextStyle(
                            color: Color(0xDFFFFFFF),
                            fontSize: 15,
                            height: 1.55,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  SoftCard(
                    radius: 26,
                    loud: true,
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text(
                          '欢迎回来',
                          style: TextStyle(
                            color: BlinStyle.ink,
                            fontSize: 24,
                            letterSpacing: -.3,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          '登录后继续你的社区会话',
                          style: TextStyle(
                            color: BlinStyle.muted,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 18),
                        TextField(
                          controller: username,
                          textInputAction: TextInputAction.next,
                          decoration: const InputDecoration(
                            prefixIcon: Icon(Icons.alternate_email_rounded),
                            labelText: '账号',
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: password,
                          obscureText: true,
                          onSubmitted: (_) => loading ? null : submit(),
                          decoration: const InputDecoration(
                            prefixIcon: Icon(Icons.lock_rounded),
                            labelText: '密码',
                          ),
                        ),
                        if (error != null) ...[
                          const SizedBox(height: 10),
                          Text(
                            error!,
                            style: const TextStyle(
                              color: BlinStyle.danger,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                        const SizedBox(height: 18),
                        FilledButton.icon(
                          onPressed: loading ? null : submit,
                          icon: loading
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.arrow_forward_rounded),
                          label: const Text('进入搭个话'),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    '测试账号：abcd / 123456，abcc / 123456',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: BlinStyle.muted,
                      fontWeight: FontWeight.w800,
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
