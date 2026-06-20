import 'dart:async';

import 'package:flutter/material.dart';
import '../models/user_session.dart';
import '../services/api_service.dart';
import '../services/auth_store.dart';
import '../widgets/blin_style.dart';

String _newCaptchaKey(String scope) =>
    '${scope}_${DateTime.now().microsecondsSinceEpoch}';

class LoginScreen extends StatefulWidget {
  final FutureOr<void> Function(UserSession) onLogin;
  const LoginScreen({super.key, required this.onLogin});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final api = const ApiService();
  final store = AuthStore();
  final username = TextEditingController();
  final password = TextEditingController();
  final captcha = TextEditingController();
  AppLoginConfig? loginConfig;
  bool loadingConfig = true;
  bool loading = false;
  String? error;
  int captchaRefresh = 0;
  String captchaKey = _newCaptchaKey('login');
  late Uri _loginCaptchaUri;

  @override
  void initState() {
    super.initState();
    _loginCaptchaUri = _buildLoginCaptchaUri();
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
      if (mounted) setState(() => error = '登录信息读取失败：$e');
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
        captchaKey: captchaKey,
      );
      await store.save(session);
      await widget.onLogin(session);
    } catch (e) {
      if (mounted) {
        setState(() {
          error = '$e';
          refreshCaptchaState();
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
        refreshCaptchaState();
        error = result.message;
      });
    }
  }

  Uri _buildLoginCaptchaUri() {
    return api.imageVerificationCodeUri(
      type: 1,
      refresh: captchaRefresh,
      captchaKey: captchaKey,
    );
  }

  Uri get loginCaptchaUri => _loginCaptchaUri;

  void refreshCaptchaState() {
    captchaRefresh++;
    captchaKey = _newCaptchaKey('login');
    _loginCaptchaUri = _buildLoginCaptchaUri();
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
      child: _AuthScaffold(
        title: '搭个话',
        subtitle: '登录后进入消息、群聊和音视频通话',
        children: [
          const _AuthSectionTitle(title: '账号登录', subtitle: '使用账号和密码继续'),
          const SizedBox(height: 16),
          _RegisterTextField(
            controller: username,
            icon: Icons.alternate_email_outlined,
            label: '账号',
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 12),
          _RegisterTextField(
            controller: password,
            icon: Icons.lock_outline_rounded,
            label: '密码',
            obscureText: true,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => loading ? null : submit(),
          ),
          if (loginConfig?.imageCaptchaRequired == true) ...[
            const SizedBox(height: 16),
            _ImageCaptchaBox(
              uri: loginCaptchaUri,
              onRefresh: () {
                setState(() {
                  refreshCaptchaState();
                  captcha.clear();
                });
              },
            ),
            const SizedBox(height: 12),
            _RegisterTextField(
              controller: captcha,
              icon: Icons.verified_outlined,
              label: '图片验证码',
              keyboardType: TextInputType.text,
              textInputAction: TextInputAction.done,
            ),
          ],
          if (error != null) ...[
            const SizedBox(height: 14),
            _AuthErrorBanner(message: error!),
          ],
          const SizedBox(height: 18),
          SizedBox(
            height: 50,
            child: FilledButton(
              onPressed: loading || loadingConfig ? null : submit,
              child: loading || loadingConfig
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('登录'),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 48,
            child: OutlinedButton(
              onPressed: loading ? null : () => unawaited(openRegister()),
              child: const Text('注册账号'),
            ),
          ),
        ],
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

class _AuthScaffold extends StatelessWidget {
  final Widget? leading;
  final String title;
  final String subtitle;
  final List<Widget> children;

  const _AuthScaffold({
    required this.title,
    required this.subtitle,
    required this.children,
    this.leading,
  });

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _AuthHeader(leading: leading, title: title, subtitle: subtitle),
              const SizedBox(height: 20),
              SoftCard(
                padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: children,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _AuthHeader extends StatelessWidget {
  final Widget? leading;
  final String title;
  final String subtitle;

  const _AuthHeader({
    required this.title,
    required this.subtitle,
    this.leading,
  });

  @override
  Widget build(BuildContext context) => Row(
    children: [
      if (leading != null) ...[leading!, const SizedBox(width: 10)],
      const BrandMark(size: 50),
      const SizedBox(width: 14),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 5),
            Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    ],
  );
}

class _AuthSectionTitle extends StatelessWidget {
  final String title;
  final String subtitle;

  const _AuthSectionTitle({required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: TextStyle(
                color: BlinStyle.textPrimary(context),
                fontSize: 17,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    ],
  );
}

class _AuthErrorBanner extends StatelessWidget {
  final String message;
  const _AuthErrorBanner({required this.message});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: BlinStyle.danger.withValues(alpha: .08),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: BlinStyle.danger.withValues(alpha: .18)),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(
          Icons.info_outline_rounded,
          color: BlinStyle.danger,
          size: 20,
        ),
        const SizedBox(width: 9),
        Expanded(
          child: Text(
            message,
            style: const TextStyle(
              color: BlinStyle.danger,
              fontSize: 13,
              height: 1.35,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    ),
  );
}

class _AuthLoadingPanel extends StatelessWidget {
  final String message;
  const _AuthLoadingPanel({required this.message});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 18),
    child: Column(
      children: [
        const SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(strokeWidth: 2.4),
        ),
        const SizedBox(height: 12),
        Text(message, style: Theme.of(context).textTheme.bodySmall),
      ],
    ),
  );
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
  final imageCaptcha = TextEditingController();
  final inviteCode = TextEditingController();
  AppRegistrationConfig? config;
  AppLoginConfig? loginConfig;
  bool loadingConfig = true;
  bool submitting = false;
  bool sendingCode = false;
  String? error;
  int captchaRefresh = 0;
  String captchaKey = _newCaptchaKey('register');
  late Uri _registerCaptchaUri;

  @override
  void initState() {
    super.initState();
    _registerCaptchaUri = _buildRegisterCaptchaUri();
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
      if (mounted) setState(() => error = '注册信息读取失败：$e');
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
    imageCaptcha.dispose();
    inviteCode.dispose();
    super.dispose();
  }

  bool get needsImageCaptchaForCode =>
      config?.emailCodeRequired == true || config?.mobileCodeRequired == true;

  bool get showsImageCaptcha =>
      config?.imageCaptchaRequired == true || needsImageCaptchaForCode;

  String? validateInput() {
    final cfg = config;
    if (cfg == null) return '注册信息还没加载完成';
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
    if (needsImageCaptchaForCode && imageCaptcha.text.trim().isEmpty) {
      return '请输入图片验证码';
    }
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
        if (imageCaptcha.text.trim().isEmpty) {
          throw ApiException('请先输入图片验证码');
        }
        msg = await api.sendEmailVerificationCode(
          email: value,
          type: 1,
          captcha: imageCaptcha.text.trim(),
          captchaKey: captchaKey,
        );
      } else if (cfg.mobileCodeRequired) {
        final value = mobile.text.trim();
        if (value.isEmpty) throw ApiException('请先输入手机号');
        if (imageCaptcha.text.trim().isEmpty) {
          throw ApiException('请先输入图片验证码');
        }
        msg = await api.sendMobileVerificationCode(
          mobile: value,
          type: 2,
          captcha: imageCaptcha.text.trim(),
          captchaKey: captchaKey,
        );
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
        captchaKey: captchaKey,
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
          refreshCaptchaState();
          captcha.clear();
        });
      }
    } finally {
      if (mounted) setState(() => submitting = false);
    }
  }

  Uri _buildRegisterCaptchaUri() {
    return api.imageVerificationCodeUri(
      type: 2,
      refresh: captchaRefresh,
      captchaKey: captchaKey,
    );
  }

  Uri get imageCaptchaUri => _registerCaptchaUri;

  void refreshCaptchaState() {
    captchaRefresh++;
    captchaKey = _newCaptchaKey('register');
    _registerCaptchaUri = _buildRegisterCaptchaUri();
    imageCaptcha.clear();
  }

  @override
  Widget build(BuildContext context) {
    final cfg = config;
    return Scaffold(
      body: PageBackdrop(
        child: _AuthScaffold(
          leading: ShellAction(
            icon: Icons.arrow_back_rounded,
            onTap: () => Navigator.pop(context),
            tooltip: '返回',
          ),
          title: '注册账号',
          subtitle: '创建账号后继续使用聊天和通话',
          children: [
            if (loadingConfig)
              const _AuthLoadingPanel(message: '正在准备注册信息')
            else if (cfg != null && !cfg.registrationEnabled)
              _RegisterClosedCard(
                message: cfg.closingPrompt.isEmpty
                    ? '当前应用暂未开放注册'
                    : cfg.closingPrompt,
                onRetry: loadConfig,
              )
            else ...[
              const _AuthSectionTitle(title: '基础信息', subtitle: '账号、密码和身份信息'),
              const SizedBox(height: 16),
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
              if (showsImageCaptcha || cfg?.codeRequired == true) ...[
                const SizedBox(height: 18),
                const _AuthSectionTitle(title: '验证方式', subtitle: '按提示完成验证'),
              ],
              if (showsImageCaptcha) ...[
                const SizedBox(height: 12),
                _ImageCaptchaBox(
                  uri: imageCaptchaUri,
                  onRefresh: () {
                    setState(() {
                      refreshCaptchaState();
                    });
                  },
                ),
                const SizedBox(height: 12),
                _RegisterTextField(
                  controller: needsImageCaptchaForCode ? imageCaptcha : captcha,
                  icon: Icons.image_search_outlined,
                  label: '图片验证码',
                  keyboardType: TextInputType.text,
                  textInputAction: TextInputAction.next,
                ),
              ],
              if (cfg?.emailCodeRequired == true ||
                  cfg?.mobileCodeRequired == true) ...[
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: _RegisterTextField(
                        controller: captcha,
                        icon: Icons.verified_outlined,
                        label: cfg?.emailCodeRequired == true
                            ? '邮箱验证码'
                            : '短信验证码',
                        keyboardType: TextInputType.number,
                        textInputAction: TextInputAction.next,
                      ),
                    ),
                    const SizedBox(width: 10),
                    SizedBox(
                      height: 54,
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
                ),
              ] else if (cfg?.imageCaptchaRequired == true) ...[
                const SizedBox.shrink(),
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
                const SizedBox(height: 14),
                _AuthErrorBanner(message: error!),
              ],
              const SizedBox(height: 18),
              SizedBox(
                height: 50,
                child: FilledButton(
                  onPressed: submitting ? null : submit,
                  child: submitting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('注册并登录'),
                ),
              ),
            ],
          ],
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
  final ValueChanged<String>? onSubmitted;

  const _RegisterTextField({
    required this.controller,
    required this.icon,
    required this.label,
    this.obscureText = false,
    this.keyboardType,
    this.textInputAction,
    this.onSubmitted,
  });

  @override
  Widget build(BuildContext context) => TextField(
    controller: controller,
    obscureText: obscureText,
    keyboardType: keyboardType,
    textInputAction: textInputAction,
    onSubmitted: onSubmitted,
    decoration: InputDecoration(
      prefixIcon: Icon(icon, size: 21),
      labelText: label,
      filled: true,
      fillColor: BlinStyle.iconSurface(context),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: BlinStyle.hairline(context, .7).color),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: BlinStyle.hairline(context, .7).color),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: BlinStyle.primary, width: 1.4),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
    ),
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
      color: BlinStyle.iconSurface(context),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: BlinStyle.hairline(context, .7).color),
    ),
    child: Row(
      children: [
        Expanded(
          child: Row(
            children: [
              const NativeIconBox(
                icon: Icons.image_search_outlined,
                color: BlinStyle.primary,
                size: 38,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.network(
                    uri.toString(),
                    height: 46,
                    fit: BoxFit.cover,
                    webHtmlElementStrategy: WebHtmlElementStrategy.fallback,
                    errorBuilder: (context, error, stackTrace) => Container(
                      height: 46,
                      alignment: Alignment.center,
                      color: BlinStyle.surface(context),
                      child: const Text('验证码加载失败'),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        IconButton.filledTonal(
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
      color: BlinStyle.iconSurface(context),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: BlinStyle.hairline(context, .62).color),
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
        SizedBox(
          width: double.infinity,
          height: 46,
          child: OutlinedButton(onPressed: onRetry, child: const Text('重新检查')),
        ),
      ],
    ),
  );
}
