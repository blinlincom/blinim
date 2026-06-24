import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/api_service.dart';
import 'blin_style.dart';

String _newPaymentCaptchaKey() =>
    'payment_${DateTime.now().microsecondsSinceEpoch}';

Future<String?> showPaymentPasswordSheet(
  BuildContext context, {
  required String token,
  required String title,
  required String amount,
}) async {
  final api = const ApiService();
  PaymentPasswordStatus status;
  try {
    status = await api.getPaymentPasswordStatus(token);
  } catch (e) {
    if (!context.mounted) return null;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('支付密码状态读取失败：$e')));
    return null;
  }
  if (!context.mounted) return null;
  if (!status.hasPassword || status.walletLocked) {
    final opened = await _showPaymentPasswordRequiredDialog(
      context,
      token: token,
      locked: status.walletLocked,
      reason: status.walletLockReason,
    );
    if (opened == true && context.mounted) {
      return showPaymentPasswordSheet(
        context,
        token: token,
        title: title,
        amount: amount,
      );
    }
    return null;
  }
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: BlinStyle.surface(context),
    builder: (_) => _PaymentPasswordPrompt(
      token: token,
      title: title,
      amount: amount,
      initialStatus: status,
    ),
  );
}

Future<bool?> _showPaymentPasswordRequiredDialog(
  BuildContext context, {
  required String token,
  required bool locked,
  String reason = '',
}) {
  final lockText = reason.trim().isEmpty
      ? '钱包已锁定，暂时无法使用钱包。'
      : '钱包已锁定，暂时无法使用钱包。原因：${reason.trim()}';
  return showDialog<bool>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: .28),
    builder: (dialogContext) => Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24),
      backgroundColor: Colors.transparent,
      child: SoftCard(
        padding: const EdgeInsets.fromLTRB(20, 22, 20, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            NativeIconBox(
              icon: locked
                  ? Icons.lock_outline_rounded
                  : Icons.password_rounded,
              color: locked ? BlinStyle.danger : BlinStyle.primary,
              size: 58,
            ),
            const SizedBox(height: 16),
            Text(
              locked ? '钱包已锁定' : '设置支付密码',
              style: Theme.of(dialogContext).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              locked ? lockText : '发红包和转账前需要先设置6位数字支付密码。',
              style: Theme.of(dialogContext).textTheme.bodyMedium,
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(dialogContext, false),
                    child: const Text('取消'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: () async {
                      final ok = await Navigator.push<bool>(
                        dialogContext,
                        MaterialPageRoute(
                          builder: (_) => PaymentPasswordScreen(
                            token: token,
                            recoveryFirst: locked,
                          ),
                        ),
                      );
                      if (!dialogContext.mounted) return;
                      Navigator.pop(dialogContext, ok == true);
                    },
                    child: Text(locked ? '找回密码' : '去设置'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

class _PaymentPasswordPrompt extends StatefulWidget {
  final String token;
  final String title;
  final String amount;
  final PaymentPasswordStatus initialStatus;

  const _PaymentPasswordPrompt({
    required this.token,
    required this.title,
    required this.amount,
    required this.initialStatus,
  });

  @override
  State<_PaymentPasswordPrompt> createState() => _PaymentPasswordPromptState();
}

class _PaymentPasswordPromptState extends State<_PaymentPasswordPrompt> {
  final api = const ApiService();
  final controller = TextEditingController();
  bool verifying = false;
  String? error;

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  Future<void> verify() async {
    final password = controller.text.trim();
    if (!RegExp(r'^\d{6}$').hasMatch(password)) {
      setState(() => error = '请输入6位数字支付密码');
      return;
    }
    setState(() {
      verifying = true;
      error = null;
    });
    try {
      await api.verifyPaymentPassword(token: widget.token, password: password);
      if (mounted) Navigator.pop(context, password);
    } catch (e) {
      if (!mounted) return;
      controller.clear();
      setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => verifying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 4, 20, 20 + bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const NativeIconBox(
                  icon: Icons.lock_outline_rounded,
                  color: BlinStyle.primary,
                  size: 44,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.title,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 3),
                      Text(
                        widget.amount.trim().isEmpty
                            ? '请输入支付密码'
                            : '支付金额 ¥${widget.amount}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            TextField(
              controller: controller,
              autofocus: true,
              obscureText: true,
              maxLength: 6,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(
                labelText: '支付密码',
                counterText: '',
                errorText: error,
              ),
              onSubmitted: (_) => unawaited(verify()),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                TextButton(
                  onPressed: verifying
                      ? null
                      : () async {
                          final ok = await Navigator.push<bool>(
                            context,
                            MaterialPageRoute(
                              builder: (_) => PaymentPasswordScreen(
                                token: widget.token,
                                recoveryFirst: true,
                              ),
                            ),
                          );
                          if (ok == true && mounted) {
                            controller.clear();
                            setState(() => error = null);
                          }
                        },
                  child: const Text('忘记密码'),
                ),
                const Spacer(),
                OutlinedButton(
                  onPressed: verifying ? null : () => Navigator.pop(context),
                  child: const Text('取消'),
                ),
                const SizedBox(width: 10),
                FilledButton(
                  onPressed: verifying ? null : () => unawaited(verify()),
                  child: verifying
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('确认'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PaymentImageCaptchaBox extends StatelessWidget {
  final Future<Uri> uriFuture;
  final VoidCallback onRefresh;

  const _PaymentImageCaptchaBox({
    required this.uriFuture,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: BlinStyle.surface(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: BlinStyle.hairline(context, .7).color),
      ),
      child: Row(
        children: [
          const NativeIconBox(
            icon: Icons.image_search_outlined,
            color: BlinStyle.primary,
            size: 38,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: FutureBuilder<Uri>(
              future: uriFuture,
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return Container(
                    height: 46,
                    alignment: Alignment.center,
                    color: BlinStyle.surface(context),
                    child: snapshot.hasError
                        ? Text(
                            '验证码加载失败',
                            style: Theme.of(context).textTheme.bodySmall,
                          )
                        : const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                  );
                }
                final uri = snapshot.data!;
                return ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.network(
                    key: ValueKey(uri.toString()),
                    uri.toString(),
                    height: 46,
                    fit: BoxFit.cover,
                    webHtmlElementStrategy: WebHtmlElementStrategy.fallback,
                    errorBuilder: (context, error, stackTrace) => Container(
                      height: 46,
                      alignment: Alignment.center,
                      color: BlinStyle.surface(context),
                      child: Text(
                        '验证码加载失败',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ),
                );
              },
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
}

class PaymentPasswordScreen extends StatefulWidget {
  final String token;
  final bool recoveryFirst;

  const PaymentPasswordScreen({
    super.key,
    required this.token,
    this.recoveryFirst = false,
  });

  @override
  State<PaymentPasswordScreen> createState() => _PaymentPasswordScreenState();
}

class _PaymentPasswordScreenState extends State<PaymentPasswordScreen> {
  final api = const ApiService();
  final oldPassword = TextEditingController();
  final password = TextEditingController();
  final confirm = TextEditingController();
  final code = TextEditingController();
  final imageCaptcha = TextEditingController();
  PaymentPasswordStatus? status;
  bool loading = true;
  bool saving = false;
  bool sendingCode = false;
  int codeCountdown = 0;
  int captchaRefresh = 0;
  String captchaKey = _newPaymentCaptchaKey();
  late Future<Uri> imageCaptchaUriFuture;
  Timer? codeTimer;
  bool recoveryMode = false;
  String method = 'mobile';
  String? error;

  @override
  void initState() {
    super.initState();
    recoveryMode = widget.recoveryFirst;
    imageCaptchaUriFuture = _buildImageCaptchaUri();
    unawaited(load());
  }

  @override
  void dispose() {
    oldPassword.dispose();
    password.dispose();
    confirm.dispose();
    code.dispose();
    imageCaptcha.dispose();
    codeTimer?.cancel();
    super.dispose();
  }

  Future<Uri> _buildImageCaptchaUri() {
    return api.imageVerificationCodeUri(
      type: 3,
      refresh: captchaRefresh,
      captchaKey: captchaKey,
    );
  }

  void refreshCaptchaState() {
    captchaRefresh++;
    captchaKey = _newPaymentCaptchaKey();
    imageCaptchaUriFuture = _buildImageCaptchaUri();
    imageCaptcha.clear();
  }

  Future<void> load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final cached = await api.loadCachedPaymentPasswordStatus(widget.token);
      if (cached != null && mounted) {
        setState(() {
          status = cached;
          loading = false;
        });
      }
      final next = await api.getPaymentPasswordStatus(widget.token);
      if (!mounted) return;
      setState(() {
        status = next;
        if (!next.hasPassword) recoveryMode = false;
        if (method == 'mobile' && !next.mobileBound && next.emailBound) {
          method = 'email';
        }
        if (method == 'email' && !next.emailBound && next.mobileBound) {
          method = 'mobile';
        }
      });
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  bool get hasPassword => status?.hasPassword == true;
  bool get canUseMobile => status?.mobileBound == true;
  bool get canUseEmail => status?.emailBound == true;
  bool get canRecover => canUseMobile || canUseEmail;

  Future<void> sendCode() async {
    if (sendingCode || codeCountdown > 0) return;
    if (method == 'mobile' && !canUseMobile) {
      setState(() => error = '当前账号未绑定手机号');
      return;
    }
    if (method == 'email' && !canUseEmail) {
      setState(() => error = '当前账号未绑定邮箱');
      return;
    }
    if (imageCaptcha.text.trim().isEmpty) {
      setState(() => error = '请输入图片验证码');
      return;
    }
    setState(() {
      sendingCode = true;
      error = null;
    });
    try {
      final msg = await api.sendPaymentPasswordVerificationCode(
        token: widget.token,
        method: method,
        captcha: imageCaptcha.text.trim(),
        captchaKey: captchaKey,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      startCodeCountdown();
    } catch (e) {
      if (mounted) {
        setState(() {
          error = '$e';
          refreshCaptchaState();
        });
      }
    } finally {
      if (mounted) setState(() => sendingCode = false);
    }
  }

  void startCodeCountdown() {
    codeTimer?.cancel();
    setState(() => codeCountdown = 60);
    codeTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (codeCountdown <= 1) {
        timer.cancel();
        setState(() => codeCountdown = 0);
      } else {
        setState(() => codeCountdown--);
      }
    });
  }

  Future<void> submit() async {
    final next = password.text.trim();
    final again = confirm.text.trim();
    if (!RegExp(r'^\d{6}$').hasMatch(next)) {
      setState(() => error = '支付密码必须是6位数字');
      return;
    }
    if (next != again) {
      setState(() => error = '两次输入的支付密码不一致');
      return;
    }
    if (hasPassword && !recoveryMode && oldPassword.text.trim().isEmpty) {
      setState(() => error = '请输入原支付密码');
      return;
    }
    if (recoveryMode && code.text.trim().isEmpty) {
      setState(() => error = '请输入验证码');
      return;
    }
    if (recoveryMode && !canRecover) {
      setState(() => error = '当前账号未绑定手机号或邮箱，无法通过验证码找回，请至设置页面绑定邮箱或手机号，再进行找回！');
      return;
    }
    setState(() {
      saving = true;
      error = null;
    });
    try {
      final nextStatus = await api.setPaymentPassword(
        token: widget.token,
        password: next,
        confirmPassword: again,
        oldPassword: recoveryMode ? '' : oldPassword.text.trim(),
        verificationMethod: recoveryMode ? method : '',
        verificationCode: recoveryMode ? code.text.trim() : '',
      );
      if (!mounted) return;
      setState(() => status = nextStatus);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('支付密码已更新')));
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final subtitle = status?.walletLocked == true
        ? '钱包已锁定，请通过验证找回'
        : hasPassword
        ? '修改或找回6位数字支付密码'
        : '设置后才能发红包和转账';
    return Scaffold(
      body: PageBackdrop(
        child: Column(
          children: [
            AppTopBar(
              title: '支付密码',
              subtitle: subtitle,
              leading: IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.arrow_back_rounded),
              ),
            ),
            Expanded(
              child: ModuleContent(
                child: ListView(
                  padding: EdgeInsets.zero,
                  children: [
                    if (loading)
                      const LinearProgressIndicator(minHeight: 2)
                    else ...[
                      _buildStatusCard(context),
                      const SizedBox(height: 14),
                      if (hasPassword) _buildModeSwitch(context),
                      const SizedBox(height: 14),
                      _buildForm(context),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusCard(BuildContext context) {
    final s = status;
    return SoftCard(
      child: Row(
        children: [
          NativeIconBox(
            icon: s?.walletLocked == true
                ? Icons.lock_rounded
                : Icons.verified_user_outlined,
            color: s?.walletLocked == true
                ? BlinStyle.danger
                : BlinStyle.primary,
            size: 48,
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  s?.walletLocked == true
                      ? '钱包已锁定'
                      : hasPassword
                      ? '已设置支付密码'
                      : '未设置支付密码',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 4),
                Text(
                  s?.walletLocked == true
                      ? (s?.walletLockReason.isNotEmpty == true
                            ? '原因：${s!.walletLockReason}'
                            : '暂时无法使用钱包')
                      : hasPassword
                      ? '剩余可输入 ${s?.remainingAttempts ?? 3} 次'
                      : '设置6位数字密码保护支付',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModeSwitch(BuildContext context) {
    return SegmentedButton<bool>(
      segments: const [
        ButtonSegment(
          value: false,
          icon: Icon(Icons.password_rounded),
          label: Text('修改'),
        ),
        ButtonSegment(
          value: true,
          icon: Icon(Icons.sms_outlined),
          label: Text('找回'),
        ),
      ],
      selected: {recoveryMode},
      onSelectionChanged: saving
          ? null
          : (values) => setState(() {
              recoveryMode = values.first;
              error = null;
            }),
    );
  }

  Widget _buildForm(BuildContext context) {
    return SoftCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (error != null) ...[
            Text(
              error!,
              style: const TextStyle(
                color: BlinStyle.danger,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
          ],
          if (hasPassword && !recoveryMode) ...[
            _passwordField(oldPassword, '原支付密码'),
            const SizedBox(height: 12),
          ],
          if (recoveryMode) ...[
            _buildVerificationMethod(context),
            const SizedBox(height: 12),
            if (canRecover) ...[
              _PaymentImageCaptchaBox(
                uriFuture: imageCaptchaUriFuture,
                onRefresh: () {
                  setState(refreshCaptchaState);
                },
              ),
              const SizedBox(height: 12),
              TextField(
                controller: imageCaptcha,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: '图片验证码',
                  prefixIcon: Icon(Icons.image_search_outlined),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: code,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: const InputDecoration(labelText: '验证码'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  OutlinedButton(
                    onPressed: (sendingCode || codeCountdown > 0)
                        ? null
                        : () => unawaited(sendCode()),
                    child: Text(
                      sendingCode
                          ? '发送中'
                          : codeCountdown > 0
                          ? '$codeCountdown秒后重发'
                          : '发送验证码',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
            ],
          ],
          _passwordField(password, '新支付密码'),
          const SizedBox(height: 12),
          _passwordField(confirm, '确认支付密码'),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: saving || (recoveryMode && !canRecover)
                  ? null
                  : () => unawaited(submit()),
              child: saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(hasPassword ? '保存' : '设置支付密码'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVerificationMethod(BuildContext context) {
    if (!canRecover) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: BlinStyle.danger.withValues(alpha: .08),
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Text(
          '当前账号未绑定手机号或邮箱，无法通过验证码找回，请至设置页面绑定邮箱或手机号，再进行找回！',
          style: TextStyle(
            color: BlinStyle.danger,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
    }
    final items = <ButtonSegment<String>>[
      if (canUseMobile)
        ButtonSegment(
          value: 'mobile',
          icon: const Icon(Icons.phone_android_rounded),
          label: Text(
            status?.maskedMobile.isNotEmpty == true
                ? status!.maskedMobile
                : '手机号',
          ),
        ),
      if (canUseEmail)
        ButtonSegment(
          value: 'email',
          icon: const Icon(Icons.mail_outline_rounded),
          label: Text(
            status?.maskedEmail.isNotEmpty == true ? status!.maskedEmail : '邮箱',
          ),
        ),
    ];
    final selectedMethod = items.any((item) => item.value == method)
        ? method
        : items.first.value;
    return SegmentedButton<String>(
      segments: items,
      selected: {selectedMethod},
      onSelectionChanged: saving
          ? null
          : (values) => setState(() {
              method = values.first;
              error = null;
            }),
    );
  }

  Widget _passwordField(TextEditingController controller, String label) {
    return TextField(
      controller: controller,
      obscureText: true,
      maxLength: 6,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      decoration: InputDecoration(labelText: label, counterText: ''),
    );
  }
}
