import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../models/im_models.dart';
import '../models/user_session.dart';
import '../services/api_service.dart';
import '../widgets/blin_style.dart';

class GroupSettingsScreen extends StatefulWidget {
  final UserSession session;
  final ImGroup initialGroup;
  const GroupSettingsScreen({
    super.key,
    required this.session,
    required this.initialGroup,
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
  bool muteNotifications = false;
  bool pinnedChat = false;
  bool saveToContacts = false;

  bool get isOwner => group.isOwner || group.ownerId == widget.session.id;
  bool get canManage => group.isAdmin || group.ownerId == widget.session.id;

  @override
  void initState() {
    super.initState();
    unawaited(load());
  }

  Future<void> load() async {
    setState(() => loading = true);
    try {
      try {
        group = await api.getImGroupInfo(
          token: widget.session.token,
          groupId: group.id,
        );
      } catch (_) {}
      members = await api.getImGroupMembers(
        token: widget.session.token,
        groupId: group.id,
      );
      try {
        friends = await api.getFriends(widget.session.token);
      } catch (_) {}
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) _toast('群资料读取失败：$e');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> renameGroup() async {
    if (!canManage) return;
    final c = TextEditingController(text: group.name);
    final name = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('修改群名称'),
        content: TextField(
          controller: c,
          decoration: const InputDecoration(labelText: '群名称'),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, c.text.trim()),
            child: const Text('保存'),
          ),
        ],
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
      setState(() => group = group.copyWith(name: g.name));
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
      setState(
        () => group = group.copyWith(avatar: g.avatar.isEmpty ? url : g.avatar),
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
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('添加群成员'),
          content: SizedBox(
            width: double.maxFinite,
            child: candidates.isEmpty
                ? const Text('暂无可添加好友')
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
                          subtitle: Text('ID ${u.id}'),
                        ),
                    ],
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: selected.isEmpty
                  ? null
                  : () => Navigator.pop(context, true),
              child: const Text('添加'),
            ),
          ],
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
        builder: (_) => AlertDialog(
          title: Text(title),
          content: Text(text),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('确定'),
            ),
          ],
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
    if (!await _confirm(
      isOwner ? '解散群聊' : '退出群聊',
      isOwner ? '确定解散该群吗？' : '确定退出该群吗？',
    )) {
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

  void openGroupQrCode() {
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('群二维码'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 190,
              height: 190,
              decoration: BoxDecoration(
                color: const Color(0xFFF2F4F7),
                borderRadius: BorderRadius.circular(18),
              ),
              child: const Icon(
                Icons.qr_code_2_rounded,
                size: 132,
                color: Color(0xFF8B96A8),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              group.name,
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
            Text(
              '群号 ${group.groupNo}',
              style: const TextStyle(color: BlinStyle.muted),
            ),
          ],
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('知道了'),
          ),
        ],
      ),
    );
  }

  void showNotice() {
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('群公告'),
        content: const Text('欢迎来到群聊，分享你的新鲜事。'),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('确定'),
          ),
        ],
      ),
    );
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
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: BlinStyle.bg,
    body: PageBackdrop(
      child: SafeArea(
        child: loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: EdgeInsets.zero,
              children: [
                _HeaderBar(
                  title:
                      '聊天信息(${group.memberCount > 0 ? group.memberCount : members.length})',
                  onBack: () => Navigator.pop(context, group),
                ),
                _MemberGrid(
                  members: members,
                  canAdd: canManage,
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
                      onTap: canManage ? changeAvatar : null,
                    ),
                    _SettingRow(
                      title: '群二维码',
                      trailing: const Icon(
                        Icons.qr_code_rounded,
                        color: Color(0xFF9A9A9A),
                      ),
                      onTap: openGroupQrCode,
                    ),
                    _SettingRow(
                      title: '群公告',
                      value: '欢迎来到群聊，分享你的新鲜事。',
                      onTap: showNotice,
                    ),
                    const _SettingRow(title: '备注'),
                  ],
                ),
                const SizedBox(height: 8),
                _SettingSection(
                  children: [
                    _SettingRow(
                      title: '查找聊天记录',
                      onTap: () => _toast('当前群聊记录可在聊天页上滑查看'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                _SettingSection(
                  children: [
                    _SwitchRow(
                      title: '消息免打扰',
                      value: muteNotifications,
                      onChanged: (v) => setState(() => muteNotifications = v),
                    ),
                    _SwitchRow(
                      title: '置顶聊天',
                      value: pinnedChat,
                      onChanged: (v) => setState(() => pinnedChat = v),
                    ),
                    _SwitchRow(
                      title: '保存到通讯录',
                      value: saveToContacts,
                      onChanged: (v) => setState(() => saveToContacts = v),
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
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFFFFF2F3),
                      foregroundColor: BlinStyle.danger,
                      minimumSize: const Size.fromHeight(50),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                        side: const BorderSide(color: Color(0xFFFFD7DB)),
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
              leading: CircleAvatar(
                backgroundImage: member.avatar.isNotEmpty
                    ? CachedNetworkImageProvider(member.avatar)
                    : null,
                child: member.avatar.isEmpty
                    ? Text(member.nickname.characters.first)
                    : null,
              ),
              title: Text(
                member.nickname,
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
              subtitle: Text('ID ${member.userId} · ${member.role}'),
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
                      leading: CircleAvatar(
                        backgroundImage: m.avatar.isNotEmpty
                            ? CachedNetworkImageProvider(m.avatar)
                            : null,
                        child: m.avatar.isEmpty
                            ? Text(m.nickname.characters.first)
                            : null,
                      ),
                      title: Text(
                        m.nickname,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      subtitle: Text('ID ${m.userId} · ${m.role}'),
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
  Widget build(BuildContext context) => Container(
    height: 62,
    color: const Color(0xFFF5F5F5),
    padding: const EdgeInsets.symmetric(horizontal: 6),
    child: Row(
      children: [
        IconButton(
          onPressed: onBack,
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
        ),
        Text(
          title,
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w600,
            color: Color(0xFF222222),
          ),
        ),
      ],
    ),
  );
}

class _MemberGrid extends StatelessWidget {
  final List<ImGroupMember> members;
  final bool canAdd;
  final VoidCallback onAdd;
  final ValueChanged<ImGroupMember> onMemberAction;
  const _MemberGrid({
    required this.members,
    required this.canAdd,
    required this.onAdd,
    required this.onMemberAction,
  });

  @override
  Widget build(BuildContext context) {
    final shown = members.take(10).toList();
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
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
                _Avatar(avatar: m.avatar, name: m.nickname, size: 58),
                const SizedBox(height: 7),
                Text(
                  m.nickname,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    color: Color(0xFF333333),
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
        Container(
          width: 58,
          height: 58,
          decoration: BoxDecoration(
            color: const Color(0xFFF9F9F9),
            borderRadius: BorderRadius.circular(29),
            border: Border.all(color: const Color(0xFFD8D8D8)),
          ),
          child: const Icon(
            Icons.add_rounded,
            size: 34,
            color: Color(0xFFB0B0B0),
          ),
        ),
      ],
    ),
  );
}

class _SettingSection extends StatelessWidget {
  final List<Widget> children;
  const _SettingSection({required this.children});

  @override
  Widget build(BuildContext context) => Container(
    color: Colors.white,
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
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: Container(
      constraints: const BoxConstraints(minHeight: 66),
      padding: const EdgeInsets.only(left: 20),
      child: Row(
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 17,
              color: Color(0xFF222222),
              fontWeight: FontWeight.w400,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: value == null
                ? const SizedBox.shrink()
                : Text(
                    value!,
                    textAlign: TextAlign.right,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 16,
                      color: Color(0xFF777777),
                    ),
                  ),
          ),
          if (trailing != null) ...[const SizedBox(width: 12), trailing!],
          const SizedBox(width: 8),
          const Icon(
            Icons.chevron_right_rounded,
            color: Color(0xFFC8C8C8),
            size: 30,
          ),
          const SizedBox(width: 12),
        ],
      ),
    ),
  );
}

class _SwitchRow extends StatelessWidget {
  final String title;
  final bool value;
  final ValueChanged<bool> onChanged;
  const _SwitchRow({
    required this.title,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(minHeight: 66),
    padding: const EdgeInsets.only(left: 20, right: 20),
    child: Row(
      children: [
        Text(
          title,
          style: const TextStyle(fontSize: 17, color: Color(0xFF222222)),
        ),
        const Spacer(),
        Switch(
          value: value,
          onChanged: onChanged,
          activeThumbColor: Colors.white,
          activeTrackColor: const Color(0xFF07C160),
          inactiveThumbColor: Colors.white,
          inactiveTrackColor: const Color(0xFFD6D6D6),
        ),
      ],
    ),
  );
}

class _Avatar extends StatelessWidget {
  final String avatar;
  final String name;
  final double size;
  const _Avatar({required this.avatar, required this.name, required this.size});

  @override
  Widget build(BuildContext context) => CircleAvatar(
    radius: size / 2,
    backgroundColor: const Color(0xFFEFEFEF),
    backgroundImage: avatar.isNotEmpty
        ? CachedNetworkImageProvider(avatar)
        : null,
    child: avatar.isEmpty
        ? Text(
            name.isEmpty ? '?' : name.characters.first,
            style: const TextStyle(
              color: Color(0xFF666666),
              fontWeight: FontWeight.w700,
            ),
          )
        : null,
  );
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
