import 'dart:async';
import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../models/im_models.dart';
import '../models/user_session.dart';
import '../services/api_service.dart';
import '../services/conversation_preferences.dart';
import '../services/group_profile_events.dart';
import '../widgets/blin_style.dart';

class GroupSettingsScreen extends StatefulWidget {
  final UserSession session;
  final ImGroup initialGroup;
  final bool muteNotifications;
  final bool pinnedChat;
  final bool screenshotNoticeEnabled;
  final VoidCallback? onSearchHistory;
  final ValueChanged<bool>? onMuteChanged;
  final ValueChanged<bool>? onPinChanged;
  final VoidCallback? onClearHistory;
  final VoidCallback? onLocalSettingsChanged;
  const GroupSettingsScreen({
    super.key,
    required this.session,
    required this.initialGroup,
    this.muteNotifications = false,
    this.pinnedChat = false,
    this.screenshotNoticeEnabled = false,
    this.onSearchHistory,
    this.onMuteChanged,
    this.onPinChanged,
    this.onClearHistory,
    this.onLocalSettingsChanged,
  });

  @override
  State<GroupSettingsScreen> createState() => _GroupSettingsScreenState();
}

class _GroupSettingsScreenState extends State<GroupSettingsScreen> {
  final api = const ApiService();
  late ImGroup group = widget.initialGroup;
  List<ImGroupMember> members = [];
  List<UserSearchResult> friends = [];
  bool loading = true;
  bool saving = false;
  late bool muteNotifications = widget.muteNotifications;
  late bool pinnedChat = widget.pinnedChat;
  bool saveToContacts = false;
  String groupRemark = '';
  bool showUserId = false;
  bool screenshotNoticeLocked = false;
  final Map<int, ImOnlineStatus> memberOnline = {};

  bool get isOwner => group.isOwner || group.ownerId == widget.session.id;
  bool get canManage => group.isAdmin || group.ownerId == widget.session.id;
  String get noticePreview {
    if (!group.noticeEnabled) return '已关闭';
    final text = group.notice.trim();
    return text.isEmpty ? '暂无群公告' : text;
  }

  @override
  void initState() {
    super.initState();
    unawaited(load());
  }

  Future<void> load() async {
    setState(() => loading = true);
    try {
      try {
        final latest = await api.getImGroupInfo(
          token: widget.session.token,
          groupId: group.id,
        );
        _publishGroup(latest);
      } catch (_) {}
      members = await api.getImGroupMembers(
        token: widget.session.token,
        groupId: group.id,
      );
      await _loadMemberOnlineStatus();
      try {
        friends = await api.getFriends(widget.session.token);
      } catch (_) {}
      try {
        final config = await api.getUserInfoConfig();
        showUserId = config.showUserId;
      } catch (_) {}
      screenshotNoticeLocked = !widget.screenshotNoticeEnabled;
      try {
        final saved = await ConversationPreferences.loadSavedGroups(
          widget.session.id,
        );
        saveToContacts = saved.contains(group.id);
        groupRemark = await ConversationPreferences.loadGroupRemark(
          widget.session.id,
          group.id,
        );
      } catch (_) {}
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) _toast('群资料读取失败：$e');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  void _publishGroup(ImGroup next) {
    group = next;
    GroupProfileEvents.notify(next);
  }

  void _setGroup(ImGroup next) {
    if (!mounted) return;
    setState(() => _publishGroup(next));
  }

  void _closeWithGroup() {
    Navigator.pop(context, group);
  }

  Future<void> _loadMemberOnlineStatus() async {
    final next = <int, ImOnlineStatus>{};
    for (final member in members.take(20)) {
      try {
        next[member.userId] = await api.getImOnlineStatus(
          token: widget.session.token,
          userId: member.userId,
        );
      } catch (_) {}
    }
    if (mounted) {
      setState(() {
        memberOnline
          ..clear()
          ..addAll(next);
      });
    }
  }

  Future<void> renameGroup() async {
    if (!canManage) return;
    final c = TextEditingController(text: group.name);
    final name = await showDialog<String>(
      context: context,
      builder: (_) => Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 24),
        backgroundColor: Colors.transparent,
        child: SoftCard(
          padding: const EdgeInsets.fromLTRB(20, 22, 20, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const NativeIconBox(
                icon: Icons.drive_file_rename_outline_rounded,
                color: BlinStyle.primary,
                size: 58,
              ),
              const SizedBox(height: 16),
              Text('修改群名称', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              TextField(
                controller: c,
                decoration: const InputDecoration(labelText: '群名称'),
                autofocus: true,
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('取消'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: () => Navigator.pop(context, c.text.trim()),
                      child: const Text('保存'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    c.dispose();
    if (name == null || name.isEmpty) return;
    await _run('修改群名称', () async {
      final g = await api.updateImGroup(
        token: widget.session.token,
        groupId: group.id,
        name: name,
      );
      _setGroup(group.copyWith(name: g.name.isEmpty ? name : g.name));
    });
  }

  Future<void> changeAvatar() async {
    if (!canManage) return;
    final r = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: false,
      withData: true,
    );
    final f = r == null || r.files.isEmpty ? null : r.files.first;
    if (f == null || f.bytes == null) return;
    await _run('修改群头像', () async {
      final up = await api.uploadChatFile(
        token: widget.session.token,
        bytes: f.bytes!,
        filename: f.name,
      );
      final url =
          '${up['url'] ?? up['path'] ?? up['file_url'] ?? up['src'] ?? ''}'
              .trim();
      if (url.isEmpty) throw ApiException('上传后没有返回头像地址');
      final g = await api.updateImGroup(
        token: widget.session.token,
        groupId: group.id,
        avatar: url,
      );
      _setGroup(group.copyWith(avatar: g.avatar.isEmpty ? url : g.avatar));
    });
  }

  Future<void> showAvatarOptions() async {
    if (!canManage) return;
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: BlinStyle.surface(context),
      showDragHandle: false,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            NativeListRow(
              leading: const NativeIconBox(
                icon: Icons.photo_camera_back_outlined,
                color: BlinStyle.primary,
                size: 40,
              ),
              title: '上传群头像',
              subtitle: '从本机选择一张图片作为群头像',
              minHeight: 64,
              onTap: () => Navigator.pop(sheetContext, 'upload'),
            ),
            NativeListRow(
              leading: const NativeIconBox(
                icon: Icons.grid_view_rounded,
                color: BlinStyle.primary,
                size: 40,
              ),
              title: '用成员头像拼接',
              subtitle: '按当前群成员头像自动生成九宫格头像',
              minHeight: 64,
              onTap: () => Navigator.pop(sheetContext, 'collage'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || action == null) return;
    if (action == 'upload') {
      await changeAvatar();
    } else if (action == 'collage') {
      await generateAvatarFromMembers();
    }
  }

  Future<void> generateAvatarFromMembers() async {
    if (!canManage) return;
    await _run('生成群头像', () async {
      final g = await api.generateImGroupAvatar(
        token: widget.session.token,
        groupId: group.id,
      );
      _setGroup(
        group.copyWith(avatar: g.avatar.isEmpty ? group.avatar : g.avatar),
      );
    });
  }

  Future<void> addMembers() async {
    final existing = members.map((m) => m.userId).toSet();
    final candidates = friends.where((f) => !existing.contains(f.id)).toList();
    final selected = <int>{};
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setDialogState) => Dialog(
          insetPadding: const EdgeInsets.symmetric(horizontal: 24),
          backgroundColor: Colors.transparent,
          child: SoftCard(
            padding: const EdgeInsets.fromLTRB(20, 22, 20, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const NativeIconBox(
                  icon: Icons.group_add_outlined,
                  color: BlinStyle.primary,
                  size: 58,
                ),
                const SizedBox(height: 16),
                Text('添加群成员', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.maxFinite,
                  height: 320,
                  child: candidates.isEmpty
                      ? const Center(child: Text('暂无可添加好友'))
                      : ListView(
                          shrinkWrap: true,
                          children: [
                            for (final u in candidates)
                              CheckboxListTile(
                                value: selected.contains(u.id),
                                onChanged: (v) => setDialogState(
                                  () => v == true
                                      ? selected.add(u.id)
                                      : selected.remove(u.id),
                                ),
                                title: Text(u.nickname),
                                subtitle: Text(
                                  showUserId ? 'ID ${u.id}' : '@${u.username}',
                                ),
                              ),
                          ],
                        ),
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('取消'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        onPressed: selected.isEmpty
                            ? null
                            : () => Navigator.pop(context, true),
                        child: const Text('添加'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (ok == true && selected.isNotEmpty) {
      await _run('添加成员', () async {
        await api.addImGroupMembers(
          token: widget.session.token,
          groupId: group.id,
          userIds: selected.toList(),
        );
        await load();
      });
    }
  }

  Future<bool> _confirm(String title, String text) async =>
      await showDialog<bool>(
        context: context,
        builder: (_) => Dialog(
          insetPadding: const EdgeInsets.symmetric(horizontal: 24),
          backgroundColor: Colors.transparent,
          child: SoftCard(
            padding: const EdgeInsets.fromLTRB(20, 22, 20, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const NativeIconBox(
                  icon: Icons.info_outline_rounded,
                  color: BlinStyle.primary,
                  size: 58,
                ),
                const SizedBox(height: 16),
                Text(title, style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 8),
                Text(text, style: Theme.of(context).textTheme.bodyMedium),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('取消'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: const Text('确定'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ) ??
      false;

  Future<void> setAdmin(ImGroupMember m, bool admin) =>
      _run(admin ? '设置管理员' : '取消管理员', () async {
        await api.setImGroupAdmin(
          token: widget.session.token,
          groupId: group.id,
          userId: m.userId,
          admin: admin,
        );
        await load();
      });

  Future<void> removeMember(ImGroupMember m) async {
    if (!await _confirm('移除成员', '确定移除 ${m.nickname} 吗？')) return;
    await _run('移除成员', () async {
      await api.removeImGroupMember(
        token: widget.session.token,
        groupId: group.id,
        userId: m.userId,
      );
      await load();
    });
  }

  Future<void> transferOwner(ImGroupMember m) async {
    if (!await _confirm('转让群主', '确定转让给 ${m.nickname} 吗？')) return;
    await _run('转让群主', () async {
      await api.transferImGroup(
        token: widget.session.token,
        groupId: group.id,
        userId: m.userId,
      );
      await load();
    });
  }

  Future<void> leaveOrDismiss() async {
    final notice = isOwner ? '解散后该群将被关闭，所有成员都会退出，聊天记录也会删除且不可恢复。' : '确定退出该群吗？';
    if (!await _confirm(isOwner ? '解散群聊' : '退出群聊', notice)) {
      return;
    }
    await _run(isOwner ? '解散群聊' : '退出群聊', () async {
      if (isOwner) {
        await api.dismissImGroup(
          token: widget.session.token,
          groupId: group.id,
        );
      } else {
        await api.leaveImGroup(token: widget.session.token, groupId: group.id);
      }
      if (mounted) Navigator.pop(context, group);
    });
  }

  Future<void> openGroupQrCode() async {
    if (!group.qrEnabled) {
      _toast('群二维码已关闭');
      return;
    }
    String qrData;
    try {
      qrData = await api.getImGroupQr(
        token: widget.session.token,
        groupId: group.id,
      );
    } catch (e) {
      _toast('群二维码读取失败：$e');
      return;
    }
    if (!mounted) return;
    showDialog<void>(
      context: context,
      builder: (_) => Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 24),
        backgroundColor: Colors.transparent,
        child: SoftCard(
          padding: const EdgeInsets.fromLTRB(20, 22, 20, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('群二维码', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 14),
              Container(
                width: 210,
                height: 210,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: const Color(0xFFE5E7EB)),
                ),
                child: QrImageView(
                  data: qrData,
                  version: QrVersions.auto,
                  gapless: false,
                  backgroundColor: Colors.white,
                  eyeStyle: const QrEyeStyle(
                    eyeShape: QrEyeShape.square,
                    color: BlinStyle.ink,
                  ),
                  dataModuleStyle: const QrDataModuleStyle(
                    dataModuleShape: QrDataModuleShape.square,
                    color: BlinStyle.ink,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                group.name,
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
              Text(
                '群号 ${group.groupNo.isEmpty ? group.id : group.groupNo}',
                style: const TextStyle(color: BlinStyle.muted),
              ),
              const SizedBox(height: 18),
              FilledButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('知道了'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void showNotice() {
    showDialog<void>(
      context: context,
      builder: (_) => Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 24),
        backgroundColor: Colors.transparent,
        child: SoftCard(
          padding: const EdgeInsets.fromLTRB(20, 22, 20, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const NativeIconBox(
                icon: Icons.campaign_outlined,
                color: BlinStyle.primary,
                size: 58,
              ),
              const SizedBox(height: 16),
              Text('群公告', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 12),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 360),
                child: SingleChildScrollView(
                  child: group.noticeEnabled
                      ? _NoticeRichPreview(
                          text: group.notice.trim().isEmpty
                              ? '暂无群公告'
                              : group.notice,
                          richText: group.noticeRichText,
                        )
                      : const Text('群公告已关闭'),
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  if (_canEditNotice) ...[
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () {
                          Navigator.pop(context);
                          unawaited(editNotice());
                        },
                        child: const Text('编辑'),
                      ),
                    ),
                    const SizedBox(width: 12),
                  ],
                  Expanded(
                    child: FilledButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('确定'),
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

  bool get _canEditNotice => isOwner || (group.adminNoticeEnabled && canManage);

  Future<void> editNotice() async {
    if (!_canEditNotice) return;
    final draft = await Navigator.push<_NoticeDraft>(
      context,
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => _GroupNoticeEditorScreen(group: group),
      ),
    );
    if (draft == null) return;
    await _run('更新群公告', () async {
      final updated = await api.updateImGroup(
        token: widget.session.token,
        groupId: group.id,
        notice: draft.text,
        noticeRichText: draft.richText,
        noticeEnabled: draft.enabled,
      );
      _setGroup(
        group.copyWith(
          notice: updated.notice.isEmpty ? draft.text : updated.notice,
          noticeRichText: updated.noticeRichText.isEmpty
              ? draft.richText
              : updated.noticeRichText,
          noticeEnabled: updated.noticeEnabled,
        ),
      );
      if (draft.enabled && draft.text.trim().isNotEmpty) {
        try {
          await api.sendGroupMessage(
            token: widget.session.token,
            groupId: group.id,
            content: '@所有人 群公告已更新：${draft.text}',
            payload: {
              'msg_type': 'notice',
              'client_msg_no':
                  'group_notice_${group.id}_${DateTime.now().microsecondsSinceEpoch}',
              'from_user_id': widget.session.id,
              'to_uid': group.groupNo,
              'group_id': group.id,
              'group_no': group.groupNo,
              'nickname': widget.session.nickname ?? '群管理员',
              'avatar': widget.session.avatar,
              'content': {
                'text': '@所有人 群公告已更新：${draft.text}',
                'notice': draft.text,
                'notice_rich_text': draft.richText,
              },
              'create_time': DateTime.now().toIso8601String(),
            },
          );
        } catch (_) {}
      }
    });
  }

  Future<void> changeGroupNo() async {
    if (!isOwner) return;
    if (!group.groupNoChangeEnabled) {
      _toast('后台未开启群号修改');
      return;
    }
    final controller = TextEditingController(text: group.groupNo);
    final ruleHint = _groupNoRuleHint(group.groupNoRule);
    final rulePattern = _groupNoRulePattern(group.groupNoRule);
    final no = await showDialog<String>(
      context: context,
      builder: (_) => Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 24),
        backgroundColor: Colors.transparent,
        child: SoftCard(
          padding: const EdgeInsets.fromLTRB(20, 22, 20, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const NativeIconBox(
                icon: Icons.tag_rounded,
                color: BlinStyle.primary,
                size: 58,
              ),
              const SizedBox(height: 16),
              Text('修改群号', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                autofocus: true,
                decoration: InputDecoration(
                  labelText:
                      group.groupNoChangePaid && group.groupNoChangeAmount > 0
                      ? '需支付 ${group.groupNoChangeAmount.toStringAsFixed(2)}'
                      : '群号',
                  helperText: ruleHint,
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(rulePattern),
                ],
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('取消'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: () =>
                          Navigator.pop(context, controller.text.trim()),
                      child: const Text('保存'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    controller.dispose();
    if (no == null || no.isEmpty || no == group.groupNo) return;
    if (!RegExp(_groupNoRuleRegex(group.groupNoRule)).hasMatch(no)) {
      _toast(ruleHint);
      return;
    }
    await _run('修改群号', () async {
      final updated = await api.updateImGroup(
        token: widget.session.token,
        groupId: group.id,
        groupNo: no,
      );
      _setGroup(
        group.copyWith(groupNo: updated.groupNo.isEmpty ? no : updated.groupNo),
      );
    });
  }

  String _groupNoRuleRegex(String rule) {
    switch (rule) {
      case 'number':
        return r'^[0-9]{4,32}$';
      case 'letters':
        return r'^[A-Za-z]{4,32}$';
      case 'alnum_underscore':
        return r'^[A-Za-z0-9_]{4,32}$';
      case 'alnum':
      default:
        return r'^[A-Za-z0-9]{4,32}$';
    }
  }

  RegExp _groupNoRulePattern(String rule) {
    switch (rule) {
      case 'number':
        return RegExp(r'[0-9]');
      case 'letters':
        return RegExp(r'[A-Za-z]');
      case 'alnum_underscore':
        return RegExp(r'[A-Za-z0-9_]');
      case 'alnum':
      default:
        return RegExp(r'[A-Za-z0-9]');
    }
  }

  String _groupNoRuleHint(String rule) {
    switch (rule) {
      case 'number':
        return '群号只能是 4-32 位纯数字';
      case 'letters':
        return '群号只能是 4-32 位纯英文';
      case 'alnum_underscore':
        return '群号只能是 4-32 位英文、数字或下划线';
      case 'alnum':
      default:
        return '群号只能是 4-32 位英文或数字';
    }
  }

  Future<void> editGroupRemark() async {
    final controller = TextEditingController(text: groupRemark);
    final value = await showDialog<String>(
      context: context,
      builder: (_) => Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 24),
        backgroundColor: Colors.transparent,
        child: SoftCard(
          padding: const EdgeInsets.fromLTRB(20, 22, 20, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const NativeIconBox(
                icon: Icons.drive_file_rename_outline_rounded,
                color: BlinStyle.primary,
                size: 58,
              ),
              const SizedBox(height: 16),
              Text('设置群备注', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                autofocus: true,
                decoration: const InputDecoration(hintText: '只在自己的列表中显示'),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('取消'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: () =>
                          Navigator.pop(context, controller.text.trim()),
                      child: const Text('保存'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    controller.dispose();
    if (value == null) return;
    await ConversationPreferences.setGroupRemark(
      widget.session.id,
      group.id,
      value,
    );
    if (!mounted) return;
    setState(() => groupRemark = value.trim());
    widget.onLocalSettingsChanged?.call();
  }

  Future<void> setSaveToContacts(bool value) async {
    await ConversationPreferences.setSavedGroup(
      widget.session.id,
      group.id,
      value,
    );
    if (!mounted) return;
    setState(() => saveToContacts = value);
    widget.onLocalSettingsChanged?.call();
  }

  Future<void> _run(String title, Future<void> Function() task) async {
    if (saving) return;
    setState(() => saving = true);
    try {
      await task();
      _toast('$title成功');
    } catch (e) {
      _toast('$title失败：$e');
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  void _toast(String text) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: false,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) _closeWithGroup();
    },
    child: Scaffold(
      backgroundColor: BlinStyle.bg,
      body: PageBackdrop(
        child: Column(
          children: [
            _HeaderBar(
              title:
                  '聊天信息(${group.memberCount > 0 ? group.memberCount : members.length})',
              onBack: _closeWithGroup,
            ),
            Expanded(
              child: ModuleContent(
                child: loading
                    ? const Center(child: CircularProgressIndicator())
                    : ListView(
                        padding: EdgeInsets.zero,
                        children: [
                          _MemberGrid(
                            members: members,
                            canAdd: canManage,
                            memberOnline: memberOnline,
                            onAdd: addMembers,
                            onMemberAction: _openMemberAction,
                          ),
                          const SizedBox(height: 8),
                          _SettingSection(
                            children: [
                              _SettingRow(
                                title: '群聊名称',
                                value: group.name,
                                onTap: canManage ? renameGroup : null,
                              ),
                              _SettingRow(
                                title: '群头像',
                                trailing: _GroupAvatar(
                                  avatar: group.avatar,
                                  name: group.name,
                                  size: 42,
                                ),
                                onTap: canManage ? showAvatarOptions : null,
                              ),
                              _SettingRow(
                                title: '群二维码',
                                trailing: const Icon(
                                  Icons.qr_code_rounded,
                                  color: Color(0xFF9A9A9A),
                                ),
                                value: group.qrEnabled ? '已开启' : '已关闭',
                                onTap: group.qrEnabled
                                    ? () => unawaited(openGroupQrCode())
                                    : null,
                              ),
                              if (isOwner)
                                _SwitchRow(
                                  title: '群二维码开关',
                                  value: group.qrEnabled,
                                  onChanged: (v) => _run('更新二维码开关', () async {
                                    final updated = await api.updateImGroup(
                                      token: widget.session.token,
                                      groupId: group.id,
                                      qrEnabled: v,
                                    );
                                    _setGroup(
                                      group.copyWith(
                                        qrEnabled: updated.qrEnabled,
                                      ),
                                    );
                                  }),
                                ),
                              _SettingRow(
                                title: '群公告',
                                value: noticePreview,
                                onTap: showNotice,
                              ),
                              if (isOwner)
                                _SwitchRow(
                                  title: '群公告开关',
                                  value: group.noticeEnabled,
                                  onChanged: (v) => _run('更新群公告开关', () async {
                                    final updated = await api.updateImGroup(
                                      token: widget.session.token,
                                      groupId: group.id,
                                      noticeEnabled: v,
                                    );
                                    _setGroup(
                                      group.copyWith(
                                        noticeEnabled: updated.noticeEnabled,
                                      ),
                                    );
                                  }),
                                ),
                              if (isOwner)
                                _SwitchRow(
                                  title: '管理员可编辑公告',
                                  value: group.adminNoticeEnabled,
                                  onChanged: (v) => _run('更新公告权限', () async {
                                    final updated = await api.updateImGroup(
                                      token: widget.session.token,
                                      groupId: group.id,
                                      adminNoticeEnabled: v,
                                    );
                                    _setGroup(
                                      group.copyWith(
                                        adminNoticeEnabled:
                                            updated.adminNoticeEnabled,
                                      ),
                                    );
                                  }),
                                ),
                              _SettingRow(
                                title: '群号',
                                value: showUserId
                                    ? (group.groupNo.isEmpty
                                          ? '${group.id}'
                                          : group.groupNo)
                                    : '按后台配置隐藏',
                                onTap: isOwner ? changeGroupNo : null,
                              ),
                              _SettingRow(
                                title: '备注',
                                value: groupRemark.isEmpty
                                    ? '未设置'
                                    : groupRemark,
                                onTap: editGroupRemark,
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          _SettingSection(
                            children: [
                              _SettingRow(
                                title: '查找聊天记录',
                                onTap:
                                    widget.onSearchHistory ??
                                    () => _toast('聊天记录搜索暂不可用'),
                              ),
                              _SettingRow(
                                title: '清空聊天记录',
                                onTap:
                                    widget.onClearHistory ??
                                    () => _toast('清空聊天记录暂不可用'),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          _SettingSection(
                            children: [
                              _SwitchRow(
                                title: '消息免打扰',
                                value: muteNotifications,
                                onChanged: (v) {
                                  setState(() => muteNotifications = v);
                                  widget.onMuteChanged?.call(v);
                                },
                              ),
                              _SwitchRow(
                                title: '置顶聊天',
                                value: pinnedChat,
                                onChanged: (v) {
                                  setState(() => pinnedChat = v);
                                  widget.onPinChanged?.call(v);
                                },
                              ),
                              _SwitchRow(
                                title: '保存到通讯录',
                                value: saveToContacts,
                                onChanged: setSaveToContacts,
                              ),
                              _SwitchRow(
                                title: '截屏提醒',
                                value: group.screenshotNotifyEnabled,
                                enabled: widget.screenshotNoticeEnabled,
                                subtitle: screenshotNoticeLocked
                                    ? '后台未开启此功能'
                                    : '开启后群内截屏会提醒全体成员',
                                onChanged: screenshotNoticeLocked
                                    ? null
                                    : (v) => _run('更新截屏提醒', () async {
                                        final updated = await api.updateImGroup(
                                          token: widget.session.token,
                                          groupId: group.id,
                                          screenshotNotifyEnabled: v,
                                        );
                                        _setGroup(
                                          group.copyWith(
                                            screenshotNotifyEnabled:
                                                updated.screenshotNotifyEnabled,
                                          ),
                                        );
                                      }),
                              ),
                            ],
                          ),
                          if (members.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            _SettingSection(
                              children: [
                                _SettingRow(
                                  title: '成员管理',
                                  value: canManage
                                      ? '可设置管理员、移除成员'
                                      : '${members.length} 位成员',
                                  onTap: _showMembersSheet,
                                ),
                              ],
                            ),
                          ],
                          const SizedBox(height: 18),
                          Padding(
                            padding: EdgeInsets.zero,
                            child: FilledButton(
                              style: FilledButton.styleFrom(
                                backgroundColor: const Color(0xFFFFF2F3),
                                foregroundColor: BlinStyle.danger,
                                minimumSize: const Size.fromHeight(50),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                  side: const BorderSide(
                                    color: Color(0xFFFFD7DB),
                                  ),
                                ),
                              ),
                              onPressed: saving ? null : leaveOrDismiss,
                              child: Text(
                                isOwner ? '解散群聊' : '退出群聊',
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 30),
                        ],
                      ),
              ),
            ),
          ],
        ),
      ),
    ),
  );

  void _openMemberAction(ImGroupMember member) {
    if (!canManage || member.userId == widget.session.id) return;
    showModalBottomSheet<void>(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: _MemberAvatar(
                avatar: member.avatar,
                name: member.nickname,
                online: memberOnline[member.userId]?.online == true,
                size: 44,
              ),
              title: Text(
                member.nickname,
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
              subtitle: Text(
                [
                  if (member.username.isNotEmpty) '@${member.username}',
                  member.role,
                  if (showUserId) 'ID ${member.userId}',
                ].join(' · '),
              ),
            ),
            if (!member.isAdmin)
              ListTile(
                leading: const Icon(Icons.admin_panel_settings_rounded),
                title: const Text('设为管理员'),
                onTap: () {
                  Navigator.pop(context);
                  unawaited(setAdmin(member, true));
                },
              ),
            if (member.isAdmin && isOwner)
              ListTile(
                leading: const Icon(Icons.remove_moderator_rounded),
                title: const Text('取消管理员'),
                onTap: () {
                  Navigator.pop(context);
                  unawaited(setAdmin(member, false));
                },
              ),
            if (isOwner)
              ListTile(
                leading: const Icon(Icons.workspace_premium_rounded),
                title: const Text('转让群主'),
                onTap: () {
                  Navigator.pop(context);
                  unawaited(transferOwner(member));
                },
              ),
            if (!member.isOwner)
              ListTile(
                leading: const Icon(
                  Icons.person_remove_rounded,
                  color: Colors.redAccent,
                ),
                title: const Text(
                  '移出群聊',
                  style: TextStyle(color: Colors.redAccent),
                ),
                onTap: () {
                  Navigator.pop(context);
                  unawaited(removeMember(member));
                },
              ),
          ],
        ),
      ),
    );
  }

  void _showMembersSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * .72,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 16, 18, 8),
                child: Row(
                  children: [
                    Text(
                      '群成员(${members.length})',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const Spacer(),
                    if (canManage)
                      TextButton.icon(
                        onPressed: addMembers,
                        icon: const Icon(Icons.add_rounded),
                        label: const Text('添加'),
                      ),
                  ],
                ),
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: members.length,
                  itemBuilder: (_, i) {
                    final m = members[i];
                    return ListTile(
                      leading: _MemberAvatar(
                        avatar: m.avatar,
                        name: m.nickname,
                        online: memberOnline[m.userId]?.online == true,
                        size: 44,
                      ),
                      title: Text(
                        m.nickname,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      subtitle: Text(
                        [
                          if (m.username.isNotEmpty) '@${m.username}',
                          m.role,
                          if (showUserId) 'ID ${m.userId}',
                        ].join(' · '),
                      ),
                      trailing: canManage && m.userId != widget.session.id
                          ? const Icon(Icons.more_horiz_rounded)
                          : null,
                      onTap: () => _openMemberAction(m),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HeaderBar extends StatelessWidget {
  final String title;
  final VoidCallback onBack;
  const _HeaderBar({required this.title, required this.onBack});

  @override
  Widget build(BuildContext context) => AppTopBar(
    title: title,
    subtitle: '群设置',
    leading: IconButton(
      onPressed: onBack,
      icon: const Icon(Icons.arrow_back_rounded),
    ),
  );
}

class _MemberGrid extends StatelessWidget {
  final List<ImGroupMember> members;
  final bool canAdd;
  final Map<int, ImOnlineStatus> memberOnline;
  final VoidCallback onAdd;
  final ValueChanged<ImGroupMember> onMemberAction;
  const _MemberGrid({
    required this.members,
    required this.canAdd,
    required this.memberOnline,
    required this.onAdd,
    required this.onMemberAction,
  });

  @override
  Widget build(BuildContext context) {
    final shown = members.take(10).toList();
    return SoftCard(
      margin: EdgeInsets.zero,
      radius: BlinStyle.cardRadius,
      padding: const EdgeInsets.all(BlinStyle.cardPadding),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 5,
          mainAxisSpacing: 16,
          crossAxisSpacing: 10,
          childAspectRatio: .72,
        ),
        itemCount: shown.length + (canAdd ? 1 : 0),
        itemBuilder: (_, i) {
          if (canAdd && i == shown.length) {
            return _GridAddButton(onTap: onAdd);
          }
          final m = shown[i];
          return InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => onMemberAction(m),
            child: Column(
              children: [
                _MemberAvatar(
                  avatar: m.avatar,
                  name: m.nickname,
                  online: memberOnline[m.userId]?.online == true,
                  size: 58,
                ),
                const SizedBox(height: 7),
                Text(
                  m.nickname,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    color: BlinStyle.textPrimary(context),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _GridAddButton extends StatelessWidget {
  final VoidCallback onTap;
  const _GridAddButton({required this.onTap});

  @override
  Widget build(BuildContext context) => InkWell(
    borderRadius: BorderRadius.circular(12),
    onTap: onTap,
    child: Column(
      children: [
        const NativeIconBox(
          icon: Icons.add_rounded,
          color: BlinStyle.primary,
          size: 58,
        ),
      ],
    ),
  );
}

class _MemberAvatar extends StatelessWidget {
  final String avatar;
  final String name;
  final bool online;
  final double size;
  const _MemberAvatar({
    required this.avatar,
    required this.name,
    required this.online,
    required this.size,
  });

  @override
  Widget build(BuildContext context) => Stack(
    clipBehavior: Clip.none,
    children: [
      AppAvatar(imageUrl: avatar, name: name, size: size),
      Positioned(
        right: 1,
        bottom: 1,
        child: Container(
          width: size * .24,
          height: size * .24,
          decoration: BoxDecoration(
            color: online ? BlinStyle.success : BlinStyle.subtle,
            shape: BoxShape.circle,
            border: Border.all(color: BlinStyle.surface(context), width: 2),
          ),
        ),
      ),
    ],
  );
}

class _SettingSection extends StatelessWidget {
  final List<Widget> children;
  const _SettingSection({required this.children});

  @override
  Widget build(BuildContext context) => SoftCard(
    margin: EdgeInsets.zero,
    radius: BlinStyle.cardRadius,
    padding: EdgeInsets.zero,
    child: Column(children: children),
  );
}

class _SettingRow extends StatelessWidget {
  final String title;
  final String? value;
  final Widget? trailing;
  final VoidCallback? onTap;
  const _SettingRow({this.title = '', this.value, this.trailing, this.onTap});

  @override
  Widget build(BuildContext context) => NativeListRow(
    leading: NativeIconBox(
      icon: _settingIcon(title),
      color: onTap == null ? BlinStyle.subtle : BlinStyle.primary,
      size: 40,
    ),
    title: title,
    subtitle: value,
    minHeight: 66,
    onTap: onTap,
    trailing:
        trailing ??
        Icon(
          Icons.chevron_right_rounded,
          color: onTap == null ? BlinStyle.line : BlinStyle.subtle,
        ),
  );

  IconData _settingIcon(String text) {
    if (text.contains('二维码')) return Icons.qr_code_2_rounded;
    if (text.contains('头像')) return Icons.image_outlined;
    if (text.contains('公告')) return Icons.campaign_outlined;
    if (text.contains('群号')) return Icons.tag_rounded;
    if (text.contains('备注')) return Icons.drive_file_rename_outline_rounded;
    if (text.contains('免打扰')) return Icons.notifications_off_outlined;
    if (text.contains('置顶')) return Icons.push_pin_outlined;
    if (text.contains('截图')) return Icons.screenshot_monitor_outlined;
    if (text.contains('转让')) return Icons.manage_accounts_outlined;
    if (text.contains('解散')) return Icons.delete_forever_outlined;
    if (text.contains('退出')) return Icons.logout_rounded;
    return Icons.tune_rounded;
  }
}

class _SwitchRow extends StatelessWidget {
  final String title;
  final bool value;
  final String? subtitle;
  final bool enabled;
  final ValueChanged<bool>? onChanged;
  const _SwitchRow({
    required this.title,
    required this.value,
    this.subtitle,
    this.enabled = true,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) => NativeListRow(
    leading: NativeIconBox(
      icon: value ? Icons.toggle_on_outlined : Icons.toggle_off_outlined,
      color: enabled
          ? (value ? BlinStyle.primary : BlinStyle.subtle)
          : BlinStyle.subtle,
      size: 40,
    ),
    title: title,
    subtitle: subtitle,
    minHeight: 66,
    trailing: Switch(
      value: value,
      onChanged: enabled ? onChanged : null,
      activeThumbColor: BlinStyle.surface(context),
      activeTrackColor: BlinStyle.primary,
      inactiveThumbColor: BlinStyle.surface(context),
      inactiveTrackColor: BlinStyle.line,
    ),
    titleStyle: TextStyle(
      fontSize: 16,
      color: enabled ? BlinStyle.textPrimary(context) : BlinStyle.subtle,
      fontWeight: FontWeight.w600,
    ),
    subtitleStyle: const TextStyle(
      fontSize: 12,
      color: BlinStyle.subtle,
      fontWeight: FontWeight.w400,
    ),
  );
}

class _Avatar extends StatelessWidget {
  final String avatar;
  final String name;
  final double size;
  const _Avatar({required this.avatar, required this.name, required this.size});

  @override
  Widget build(BuildContext context) =>
      AppAvatar(imageUrl: avatar, name: name, size: size);
}

class _GroupAvatar extends StatelessWidget {
  final String avatar;
  final String name;
  final double size;
  const _GroupAvatar({
    required this.avatar,
    required this.name,
    required this.size,
  });

  @override
  Widget build(BuildContext context) =>
      _Avatar(avatar: avatar, name: name, size: size);
}

class _NoticeDraft {
  final bool enabled;
  final String text;
  final String richText;
  const _NoticeDraft({
    required this.enabled,
    required this.text,
    required this.richText,
  });
}

class _GroupNoticeEditorScreen extends StatefulWidget {
  final ImGroup group;
  const _GroupNoticeEditorScreen({required this.group});

  @override
  State<_GroupNoticeEditorScreen> createState() =>
      _GroupNoticeEditorScreenState();
}

class _GroupNoticeEditorScreenState extends State<_GroupNoticeEditorScreen> {
  late bool enabled = widget.group.noticeEnabled;
  late final TextEditingController titleController;
  late final TextEditingController bodyController;
  late final TextEditingController linkController;
  bool important = false;

  @override
  void initState() {
    super.initState();
    final decoded = _decodeNoticeRichText(widget.group.noticeRichText);
    titleController = TextEditingController(text: decoded.title);
    bodyController = TextEditingController(
      text: decoded.body.isEmpty ? widget.group.notice : decoded.body,
    );
    linkController = TextEditingController(text: decoded.link);
    important = decoded.important;
  }

  @override
  void dispose() {
    titleController.dispose();
    bodyController.dispose();
    linkController.dispose();
    super.dispose();
  }

  String _plainText() {
    final parts = [
      titleController.text.trim(),
      bodyController.text.trim(),
      linkController.text.trim(),
    ].where((text) => text.isNotEmpty).toList();
    return parts.join('\n');
  }

  String _richTextPayload() {
    final jsonText = jsonEncode({
      'type': 'group_notice_rich_text',
      'version': 1,
      'title': titleController.text.trim(),
      'body': bodyController.text.trim(),
      'link': linkController.text.trim(),
      'important': important,
    });
    return 'base64:${base64Encode(utf8.encode(jsonText))}';
  }

  void _submit() {
    Navigator.pop(
      context,
      _NoticeDraft(
        enabled: enabled,
        text: enabled ? _plainText() : '',
        richText: enabled ? _richTextPayload() : '',
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: BlinStyle.bg,
    body: PageBackdrop(
      child: Column(
        children: [
          AppTopBar(
            title: '编辑群公告',
            subtitle: enabled ? '富文本公告' : '公告已关闭',
            leading: IconButton(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.close_rounded),
            ),
            actions: [
              TextButton(
                onPressed: _submit,
                child: const Text(
                  '保存',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
          Expanded(
            child: ModuleContent(
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  SoftCard(
                    margin: EdgeInsets.zero,
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        const NativeIconBox(
                          icon: Icons.campaign_outlined,
                          color: BlinStyle.primary,
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Text(
                            '群公告',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        Switch(
                          value: enabled,
                          onChanged: (value) => setState(() => enabled = value),
                          activeThumbColor: Colors.white,
                          activeTrackColor: BlinStyle.cyan,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (enabled)
                    SoftCard(
                      margin: EdgeInsets.zero,
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          TextField(
                            controller: titleController,
                            textInputAction: TextInputAction.next,
                            decoration: const InputDecoration(
                              labelText: '标题',
                              prefixIcon: Icon(Icons.title_rounded),
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: bodyController,
                            minLines: 6,
                            maxLines: 12,
                            decoration: const InputDecoration(
                              labelText: '正文',
                              alignLabelWithHint: true,
                              prefixIcon: Icon(Icons.notes_rounded),
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: linkController,
                            keyboardType: TextInputType.url,
                            decoration: const InputDecoration(
                              labelText: '链接，可选',
                              prefixIcon: Icon(Icons.link_rounded),
                            ),
                          ),
                          const SizedBox(height: 12),
                          CheckboxListTile(
                            value: important,
                            onChanged: (value) =>
                                setState(() => important = value == true),
                            contentPadding: EdgeInsets.zero,
                            controlAffinity: ListTileControlAffinity.leading,
                            title: const Text('重点公告'),
                            subtitle: const Text('在公告预览中使用强调样式'),
                          ),
                        ],
                      ),
                    )
                  else
                    const SoftCard(
                      margin: EdgeInsets.zero,
                      padding: EdgeInsets.all(16),
                      child: Text(
                        '关闭后聊天页不再显示群公告入口，历史公告内容会保留，重新开启后可继续编辑。',
                        style: TextStyle(color: BlinStyle.muted),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class _NoticeRichData {
  final String title;
  final String body;
  final String link;
  final bool important;
  const _NoticeRichData({
    required this.title,
    required this.body,
    required this.link,
    required this.important,
  });
}

_NoticeRichData _decodeNoticeRichText(String raw) {
  var source = raw.trim();
  if (source.startsWith('base64:')) {
    try {
      source = utf8.decode(base64Decode(source.substring(7)));
    } catch (_) {}
  }
  if (source.isEmpty) {
    return const _NoticeRichData(
      title: '',
      body: '',
      link: '',
      important: false,
    );
  }
  try {
    final decoded = jsonDecode(source);
    if (decoded is Map) {
      return _NoticeRichData(
        title: '${decoded['title'] ?? ''}',
        body: '${decoded['body'] ?? decoded['content'] ?? ''}',
        link: '${decoded['link'] ?? decoded['url'] ?? ''}',
        important:
            decoded['important'] == true || '${decoded['important']}' == '1',
      );
    }
  } catch (_) {}
  return _NoticeRichData(title: '', body: source, link: '', important: false);
}

class _NoticeRichPreview extends StatelessWidget {
  final String text;
  final String richText;
  const _NoticeRichPreview({required this.text, required this.richText});

  @override
  Widget build(BuildContext context) {
    final data = _decodeNoticeRichText(richText);
    final title = data.title.trim();
    final body = data.body.trim().isEmpty ? text.trim() : data.body.trim();
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (title.isNotEmpty) ...[
          Row(
            children: [
              if (data.important) ...[
                const Icon(
                  Icons.priority_high_rounded,
                  color: BlinStyle.warning,
                  size: 18,
                ),
                const SizedBox(width: 4),
              ],
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
        ],
        Text(
          body.isEmpty ? '暂无群公告' : body,
          style: const TextStyle(fontSize: 14, height: 1.5),
        ),
        if (data.link.trim().isNotEmpty) ...[
          const SizedBox(height: 12),
          Row(
            children: [
              const Icon(
                Icons.link_rounded,
                size: 18,
                color: BlinStyle.primary,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  data.link.trim(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: BlinStyle.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}
