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
      child: SafeArea(
        child: ModuleContent(
          padding: const EdgeInsets.fromLTRB(
            BlinStyle.pagePadding,
            18,
            BlinStyle.pagePadding,
            BlinStyle.pagePadding,
          ),
          child: Center(
            child: SingleChildScrollView(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 430),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const _LoginBrand(),
                    const SizedBox(height: 32),
                    Text('欢迎回来', style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 8),
                    Text(
                      '登录后继续处理消息、社区动态和音视频通话。',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 24),
                    SoftCard(
                      padding: const EdgeInsets.all(18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          TextField(
                            controller: username,
                            textInputAction: TextInputAction.next,
                            decoration: const InputDecoration(
                              prefixIcon: Icon(Icons.alternate_email_outlined),
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
                            const SizedBox(height: 12),
                            Text(
                              error!,
                              style: const TextStyle(color: BlinStyle.danger),
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
    ),
  );
}

class _LoginBrand extends StatelessWidget {
  const _LoginBrand();

  @override
  Widget build(BuildContext context) => SoftCard(
    padding: const EdgeInsets.all(18),
    loud: true,
    child: const InfoLine(
      avatar: BrandMark(size: 54),
      title: '搭个话',
      subtitle: '商业化社区即时通讯',
      meta: 'IM / Community / Audio & Video',
    ),
  );
}
