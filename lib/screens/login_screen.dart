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
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      gradient: BlinStyle.brandGradient,
                      borderRadius: BorderRadius.circular(34),
                      boxShadow: [BlinStyle.softShadow(.18)],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 52,
                              height: 52,
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: .22),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: const Icon(
                                Icons.hub_rounded,
                                color: Colors.white,
                                size: 30,
                              ),
                            ),
                            const Spacer(),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 7,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: .2),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: const Text(
                                'PHP + IM',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 34),
                        const Text(
                          'Blinlin\n年轻社区',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 42,
                            height: 1.02,
                            letterSpacing: -1.6,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          '动态、发现、消息、个人资产都在一个轻盈空间里。',
                          style: TextStyle(
                            color: Color(0xEEFFFFFF),
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
                    radius: 30,
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text(
                          '账号登录',
                          style: TextStyle(
                            color: BlinStyle.ink,
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 14),
                        TextField(
                          controller: username,
                          textInputAction: TextInputAction.next,
                          decoration: const InputDecoration(
                            prefixIcon: Icon(Icons.person_rounded),
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
                              color: Colors.red,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                        const SizedBox(height: 16),
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
                          label: const Text('进入 Blinlin'),
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
                      fontWeight: FontWeight.w700,
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
