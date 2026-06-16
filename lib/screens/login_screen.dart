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
  final captcha = TextEditingController();
  AppLoginConfig? loginConfig;
  bool loadingConfig = true;
  bool loading = false;
  String? error;
  int captchaRefresh = 0;

  @override
  void initState() {
    super.initState();
    unawaited(loadLoginConfig());
  }

  Future<void> loadLoginConfig() async {
    setState(() {
      loadingConfig = true;
      error = null;
    });
    try {
      final next = await api.getLoginConfig();
      if (mounted) setState(() => loginConfig = next);
    } catch (e) {
      if (mounted) setState(() => error = '登录配置读取失败：$e');
    } finally {
      if (mounted) setState(() => loadingConfig = false);
    }
  }

  Future<void> submit() async {
    final cfg = loginConfig;
    if (cfg != null && !cfg.loginEnabled) {
      setState(
        () => error = cfg.closingPrompt.isEmpty
            ? '当前应用暂未开放登录'
            : cfg.closingPrompt,
      );
      return;
    }
    if (cfg?.imageCaptchaRequired == true && captcha.text.trim().isEmpty) {
      setState(() => error = '请输入图片验证码');
      return;
    }
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final session = await api.login(
        username.text.trim(),
        password.text,
        captcha: captcha.text.trim(),
      );
      await store.save(session);
      await widget.onLogin(session);
    } catch (e) {
      if (mounted) {
        setState(() {
          error = '$e';
          captchaRefresh++;
          captcha.clear();
        });
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> openRegister() async {
    final result = await Navigator.push<Object>(
      context,
      MaterialPageRoute(builder: (_) => const _RegisterScreen()),
    );
    if (result is UserSession) {
      await store.save(result);
      await widget.onLogin(result);
      return;
    }
    if (result is _RegisteredCredentials && mounted) {
      setState(() {
        username.text = result.username;
        password.text = result.password;
        captcha.clear();
        captchaRefresh++;
        error = result.message;
      });
    }
  }

  Uri get loginCaptchaUri {
    final uri = api.imageVerificationCodeUri(type: 1);
    return uri.replace(
      queryParameters: {...uri.queryParameters, 'refresh': '$captchaRefresh'},
    );
  }

  @override
  void dispose() {
    username.dispose();
    password.dispose();
    captcha.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: PageBackdrop(
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(26, 24, 26, 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 430),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 24),
                  const Center(child: BrandMark(size: 72)),
                  const SizedBox(height: 18),
                  const Text(
                    '搭个话',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: BlinStyle.ink,
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    '安全连接即时消息和音视频通话',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: BlinStyle.subtle,
                      fontSize: 14,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                  const SizedBox(height: 34),
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
                  if (loginConfig?.imageCaptchaRequired == true) ...[
                    const SizedBox(height: 12),
                    _ImageCaptchaBox(
                      uri: loginCaptchaUri,
                      onRefresh: () => setState(() => captchaRefresh++),
                    ),
                    const SizedBox(height: 12),
                    _RegisterTextField(
                      controller: captcha,
                      icon: Icons.verified_outlined,
                      label: '图片验证码',
                      keyboardType: TextInputType.number,
                      textInputAction: TextInputAction.done,
                    ),
                  ],
                  if (error != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      error!,
                      style: const TextStyle(color: BlinStyle.danger),
                    ),
                  ],
                  const SizedBox(height: 18),
                  FilledButton(
                    onPressed: loading || loadingConfig ? null : submit,
                    child: loading || loadingConfig
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('登录'),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton(
                    onPressed: loading ? null : () => unawaited(openRegister()),
                    child: const Text('注册账号'),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    '测试账号：abcd / 123456，abcc / 123456',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall,
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

class _RegisteredCredentials {
  final String username;
  final String password;
  final String message;

  const _RegisteredCredentials({
    required this.username,
    required this.password,
    required this.message,
  });
}

class _RegisterScreen extends StatefulWidget {
  const _RegisterScreen();

  @override
  State<_RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<_RegisterScreen> {
  final api = const ApiService();
  final username = TextEditingController();
  final password = TextEditingController();
  final confirmPassword = TextEditingController();
  final email = TextEditingController();
  final mobile = TextEditingController();
  final captcha = TextEditingController();
  final inviteCode = TextEditingController();
  AppRegistrationConfig? config;
  AppLoginConfig? loginConfig;
  bool loadingConfig = true;
  bool submitting = false;
  bool sendingCode = false;
  String? error;
  int captchaRefresh = 0;

  @override
  void initState() {
    super.initState();
    unawaited(loadConfig());
  }

  Future<void> loadConfig() async {
    setState(() {
      loadingConfig = true;
      error = null;
    });
    try {
      final next = await api.getRegistrationConfig();
      final nextLogin = await api.getLoginConfig();
      if (mounted) {
        setState(() {
          config = next;
          loginConfig = nextLogin;
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = '注册配置读取失败：$e');
    } finally {
      if (mounted) setState(() => loadingConfig = false);
    }
  }

  @override
  void dispose() {
    username.dispose();
    password.dispose();
    confirmPassword.dispose();
    email.dispose();
    mobile.dispose();
    captcha.dispose();
    inviteCode.dispose();
    super.dispose();
  }

  String? validateInput() {
    final cfg = config;
    if (cfg == null) return '注册配置未加载完成';
    if (!cfg.registrationEnabled) {
      return cfg.closingPrompt.isEmpty ? '当前应用暂未开放注册' : cfg.closingPrompt;
    }
    final needsAccount = !cfg.mobileCodeRequired;
    if (needsAccount) {
      final account = username.text.trim();
      if (!RegExp(r'^[A-Za-z0-9]{4,8}$').hasMatch(account)) {
        return '账号只能使用 4-8 位英文或数字';
      }
    }
    if (password.text.length < 5) return '密码至少 5 位';
    if (password.text != confirmPassword.text) return '两次输入的密码不一致';
    if (cfg.emailCodeRequired && email.text.trim().isEmpty) return '请输入邮箱';
    if (cfg.mobileCodeRequired && mobile.text.trim().isEmpty) return '请输入手机号';
    if (cfg.codeRequired && captcha.text.trim().isEmpty) return '请输入验证码';
    return null;
  }

  Future<void> sendCode() async {
    final cfg = config;
    if (cfg == null || sendingCode) return;
    setState(() {
      sendingCode = true;
      error = null;
    });
    try {
      String msg;
      if (cfg.emailCodeRequired) {
        final value = email.text.trim();
        if (value.isEmpty) throw ApiException('请先输入邮箱');
        msg = await api.sendEmailVerificationCode(email: value, type: 1);
      } else if (cfg.mobileCodeRequired) {
        final value = mobile.text.trim();
        if (value.isEmpty) throw ApiException('请先输入手机号');
        msg = await api.sendMobileVerificationCode(mobile: value, type: 2);
      } else {
        return;
      }
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(msg)));
      }
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => sendingCode = false);
    }
  }

  Future<void> submit() async {
    final validation = validateInput();
    if (validation != null) {
      setState(() => error = validation);
      return;
    }
    setState(() {
      submitting = true;
      error = null;
    });
    try {
      await api.register(
        username: config?.mobileCodeRequired == true
            ? ''
            : username.text.trim(),
        password: password.text,
        email: email.text.trim(),
        mobile: mobile.text.trim(),
        captcha: captcha.text.trim(),
        inviteCode: inviteCode.text.trim(),
      );
      final loginCfg = loginConfig;
      if (loginCfg != null &&
          (!loginCfg.loginEnabled || loginCfg.imageCaptchaRequired)) {
        final message = !loginCfg.loginEnabled
            ? (loginCfg.closingPrompt.isEmpty
                  ? '注册成功，当前应用暂未开放登录'
                  : loginCfg.closingPrompt)
            : '注册成功，请输入图片验证码登录';
        if (mounted) {
          Navigator.pop(
            context,
            _RegisteredCredentials(
              username: username.text.trim(),
              password: password.text,
              message: message,
            ),
          );
        }
        return;
      }
      final session = await api.login(username.text.trim(), password.text);
      if (mounted) Navigator.pop(context, session);
    } catch (e) {
      if (mounted) {
        setState(() {
          error = '$e';
          captchaRefresh++;
          captcha.clear();
        });
      }
    } finally {
      if (mounted) setState(() => submitting = false);
    }
  }

  Uri get imageCaptchaUri {
    final uri = api.imageVerificationCodeUri(type: 2);
    return uri.replace(
      queryParameters: {...uri.queryParameters, 'refresh': '$captchaRefresh'},
    );
  }

  @override
  Widget build(BuildContext context) {
    final cfg = config;
    return Scaffold(
      body: PageBackdrop(
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(26, 20, 26, 24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 430),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.arrow_back_rounded),
                      ),
                    ),
                    const Center(child: BrandMark(size: 64)),
                    const SizedBox(height: 16),
                    const Text(
                      '注册账号',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: BlinStyle.ink,
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      '创建账号后自动登录',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: BlinStyle.subtle, fontSize: 14),
                    ),
                    const SizedBox(height: 26),
                    if (loadingConfig)
                      const Center(child: CircularProgressIndicator())
                    else if (cfg != null && !cfg.registrationEnabled)
                      _RegisterClosedCard(
                        message: cfg.closingPrompt.isEmpty
                            ? '当前应用暂未开放注册'
                            : cfg.closingPrompt,
                        onRetry: loadConfig,
                      )
                    else ...[
                      if (cfg?.mobileCodeRequired != true) ...[
                        _RegisterTextField(
                          controller: username,
                          icon: Icons.alternate_email_outlined,
                          label: '账号',
                          textInputAction: TextInputAction.next,
                        ),
                        const SizedBox(height: 12),
                      ],
                      _RegisterTextField(
                        controller: password,
                        icon: Icons.lock_outline_rounded,
                        label: '密码',
                        obscureText: true,
                        textInputAction: TextInputAction.next,
                      ),
                      const SizedBox(height: 12),
                      _RegisterTextField(
                        controller: confirmPassword,
                        icon: Icons.lock_reset_rounded,
                        label: '确认密码',
                        obscureText: true,
                        textInputAction: TextInputAction.next,
                      ),
                      if (cfg?.emailCodeRequired == true) ...[
                        const SizedBox(height: 12),
                        _RegisterTextField(
                          controller: email,
                          icon: Icons.email_outlined,
                          label: '邮箱',
                          keyboardType: TextInputType.emailAddress,
                          textInputAction: TextInputAction.next,
                        ),
                      ],
                      if (cfg?.mobileCodeRequired == true) ...[
                        const SizedBox(height: 12),
                        _RegisterTextField(
                          controller: mobile,
                          icon: Icons.phone_iphone_rounded,
                          label: '手机号',
                          keyboardType: TextInputType.phone,
                          textInputAction: TextInputAction.next,
                        ),
                      ],
                      if (cfg?.imageCaptchaRequired == true) ...[
                        const SizedBox(height: 12),
                        _ImageCaptchaBox(
                          uri: imageCaptchaUri,
                          onRefresh: () => setState(() => captchaRefresh++),
                        ),
                      ],
                      if (cfg?.codeRequired == true) ...[
                        const SizedBox(height: 12),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: _RegisterTextField(
                                controller: captcha,
                                icon: Icons.verified_outlined,
                                label: '验证码',
                                keyboardType: TextInputType.number,
                                textInputAction: TextInputAction.next,
                              ),
                            ),
                            if (cfg?.emailCodeRequired == true ||
                                cfg?.mobileCodeRequired == true) ...[
                              const SizedBox(width: 10),
                              SizedBox(
                                height: 56,
                                child: OutlinedButton(
                                  onPressed: sendingCode ? null : sendCode,
                                  child: sendingCode
                                      ? const SizedBox(
                                          width: 16,
                                          height: 16,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : const Text('发送验证码'),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                      if (cfg?.invitationEnabled == true) ...[
                        const SizedBox(height: 12),
                        _RegisterTextField(
                          controller: inviteCode,
                          icon: Icons.card_giftcard_rounded,
                          label: '邀请码（可选）',
                          textInputAction: TextInputAction.done,
                        ),
                      ],
                      if (error != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          error!,
                          style: const TextStyle(color: BlinStyle.danger),
                        ),
                      ],
                      const SizedBox(height: 18),
                      FilledButton(
                        onPressed: submitting ? null : submit,
                        child: submitting
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text('注册并登录'),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RegisterTextField extends StatelessWidget {
  final TextEditingController controller;
  final IconData icon;
  final String label;
  final bool obscureText;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;

  const _RegisterTextField({
    required this.controller,
    required this.icon,
    required this.label,
    this.obscureText = false,
    this.keyboardType,
    this.textInputAction,
  });

  @override
  Widget build(BuildContext context) => TextField(
    controller: controller,
    obscureText: obscureText,
    keyboardType: keyboardType,
    textInputAction: textInputAction,
    decoration: InputDecoration(prefixIcon: Icon(icon), labelText: label),
  );
}

class _ImageCaptchaBox extends StatelessWidget {
  final Uri uri;
  final VoidCallback onRefresh;
  const _ImageCaptchaBox({required this.uri, required this.onRefresh});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: BlinStyle.surface(context),
      borderRadius: BorderRadius.circular(BlinStyle.cardRadius),
      border: Border.all(color: BlinStyle.hairline(context, .7).color),
    ),
    child: Row(
      children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.network(
              uri.toString(),
              height: 48,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) => Container(
                height: 48,
                alignment: Alignment.center,
                color: BlinStyle.softFill,
                child: const Text('验证码加载失败'),
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        IconButton(
          onPressed: onRefresh,
          icon: const Icon(Icons.refresh_rounded),
          tooltip: '刷新验证码',
        ),
      ],
    ),
  );
}

class _RegisterClosedCard extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _RegisterClosedCard({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: BlinStyle.surface(context),
      borderRadius: BorderRadius.circular(BlinStyle.cardRadius),
      boxShadow: [BlinStyle.softShadow(.10)],
    ),
    child: Column(
      children: [
        const Icon(
          Icons.lock_clock_outlined,
          color: BlinStyle.subtle,
          size: 38,
        ),
        const SizedBox(height: 10),
        Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(color: BlinStyle.ink, fontSize: 15),
        ),
        const SizedBox(height: 14),
        OutlinedButton(onPressed: onRetry, child: const Text('重新检查')),
      ],
    ),
  );
}
