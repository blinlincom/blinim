import 'dart:async';

import 'package:flutter/material.dart';
import '../models/user_session.dart';
import '../services/api_service.dart';
import '../services/auth_store.dart';
import '../widgets/blin_style.dart';

class LoginScreen extends StatefulWidget {
  final FutureOr<void> Function(UserSession) onLogin;
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
      await widget.onLogin(session);
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
      child: Column(
        children: [
          const AppTopBar(title: '搭个话', subtitle: '即时消息和音视频通话'),
          Expanded(
            child: ModuleContent(
              child: Center(
                child: SingleChildScrollView(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const _LoginBrand(),
                        const SizedBox(height: BlinStyle.moduleGap),
                        SoftCard(
                          padding: const EdgeInsets.all(BlinStyle.cardPadding),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                '欢迎回来',
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '登录后继续你的即时通讯会话',
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),
                              const SizedBox(height: 16),
                              TextField(
                                controller: username,
                                textInputAction: TextInputAction.next,
                                decoration: const InputDecoration(
                                  prefixIcon: Icon(
                                    Icons.alternate_email_outlined,
                                  ),
                                  labelText: '账号',
                                ),
                              ),
                              const SizedBox(height: 12),
                              TextField(
                                controller: password,
                                obscureText: true,
                                onSubmitted: (_) => loading ? null : submit(),
                                decoration: const InputDecoration(
                                  prefixIcon: Icon(Icons.lock_outline_rounded),
                                  labelText: '密码',
                                ),
                              ),
                              if (error != null) ...[
                                const SizedBox(height: 10),
                                Text(
                                  error!,
                                  style: const TextStyle(
                                    color: BlinStyle.danger,
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
                                    : const Icon(Icons.arrow_forward_outlined),
                                label: const Text('进入搭个话'),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          '测试账号：abcd / 123456，abcc / 123456',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class _LoginBrand extends StatelessWidget {
  const _LoginBrand();

  @override
  Widget build(BuildContext context) => SoftCard(
    padding: const EdgeInsets.all(BlinStyle.cardPadding),
    child: const InfoLine(
      avatar: GradientIcon(icon: Icons.forum_outlined),
      title: '搭个话',
      subtitle: '现代即时通讯',
      meta: 'Flutter / IM / Audio & Video',
    ),
  );
}
