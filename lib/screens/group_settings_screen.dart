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
  const GroupSettingsScreen({super.key, required this.session, required this.initialGroup});
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

  bool get isOwner => group.isOwner || group.ownerId == widget.session.id;
  bool get canManage => group.isAdmin || group.ownerId == widget.session.id;

  @override
  void initState() { super.initState(); unawaited(load()); }

  Future<void> load() async {
    setState(() => loading = true);
    try {
      try { group = await api.getImGroupInfo(token: widget.session.token, groupId: group.id); } catch (_) {}
      members = await api.getImGroupMembers(token: widget.session.token, groupId: group.id);
      try { friends = await api.getFriends(widget.session.token); } catch (_) {}
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) _toast('群资料读取失败：$e');
    } finally { if (mounted) setState(() => loading = false); }
  }

  Future<void> renameGroup() async {
    final c = TextEditingController(text: group.name);
    final name = await showDialog<String>(context: context, builder: (_) => AlertDialog(title: const Text('修改群名称'), content: TextField(controller: c, decoration: const InputDecoration(labelText: '群名称')), actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')), FilledButton(onPressed: () => Navigator.pop(context, c.text.trim()), child: const Text('保存'))]));
    c.dispose();
    if (name == null || name.isEmpty) return;
    await _run('修改群名称', () async { final g = await api.updateImGroup(token: widget.session.token, groupId: group.id, name: name); setState(() => group = group.copyWith(name: g.name)); });
  }

  Future<void> changeAvatar() async {
    final r = await FilePicker.platform.pickFiles(type: FileType.image, allowMultiple: false, withData: true);
    final f = r == null || r.files.isEmpty ? null : r.files.first;
    if (f == null || f.bytes == null) return;
    await _run('修改群头像', () async { final up = await api.uploadChatFile(token: widget.session.token, bytes: f.bytes!, filename: f.name); final url = '${up['url'] ?? up['path'] ?? up['file_url'] ?? up['src'] ?? ''}'.trim(); if (url.isEmpty) throw ApiException('上传后没有返回头像地址'); final g = await api.updateImGroup(token: widget.session.token, groupId: group.id, avatar: url); setState(() => group = group.copyWith(avatar: g.avatar.isEmpty ? url : g.avatar)); });
  }

  Future<void> addMembers() async {
    final existing = members.map((m) => m.userId).toSet();
    final candidates = friends.where((f) => !existing.contains(f.id)).toList();
    final selected = <int>{};
    final ok = await showDialog<bool>(context: context, builder: (_) => StatefulBuilder(builder: (context, setDialogState) => AlertDialog(title: const Text('添加群成员'), content: SizedBox(width: double.maxFinite, child: candidates.isEmpty ? const Text('暂无可添加好友') : ListView(shrinkWrap: true, children: [for (final u in candidates) CheckboxListTile(value: selected.contains(u.id), onChanged: (v) => setDialogState(() => v == true ? selected.add(u.id) : selected.remove(u.id)), title: Text(u.nickname), subtitle: Text('ID ${u.id}'))])), actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')), FilledButton(onPressed: selected.isEmpty ? null : () => Navigator.pop(context, true), child: const Text('添加'))])));
    if (ok == true && selected.isNotEmpty) await _run('添加成员', () async { await api.addImGroupMembers(token: widget.session.token, groupId: group.id, userIds: selected.toList()); await load(); });
  }

  Future<bool> _confirm(String title, String text) async => await showDialog<bool>(context: context, builder: (_) => AlertDialog(title: Text(title), content: Text(text), actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')), FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('确定'))])) ?? false;
  Future<void> setAdmin(ImGroupMember m, bool admin) => _run(admin ? '设置管理员' : '取消管理员', () async { await api.setImGroupAdmin(token: widget.session.token, groupId: group.id, userId: m.userId, admin: admin); await load(); });
  Future<void> removeMember(ImGroupMember m) async { if (!await _confirm('移除成员', '确定移除 ${m.nickname} 吗？')) return; await _run('移除成员', () async { await api.removeImGroupMember(token: widget.session.token, groupId: group.id, userId: m.userId); await load(); }); }
  Future<void> transferOwner(ImGroupMember m) async { if (!await _confirm('转让群主', '确定转让给 ${m.nickname} 吗？')) return; await _run('转让群主', () async { await api.transferImGroup(token: widget.session.token, groupId: group.id, userId: m.userId); await load(); }); }
  Future<void> leaveOrDismiss() async { if (!await _confirm(isOwner ? '解散群聊' : '退出群聊', isOwner ? '确定解散该群吗？' : '确定退出该群吗？')) return; await _run(isOwner ? '解散群聊' : '退出群聊', () async { if (isOwner) { await api.dismissImGroup(token: widget.session.token, groupId: group.id); } else { await api.leaveImGroup(token: widget.session.token, groupId: group.id); } if (mounted) Navigator.pop(context, group); }); }

  Future<void> _run(String title, Future<void> Function() task) async { if (saving) return; setState(() => saving = true); try { await task(); _toast('$title成功'); } catch (e) { _toast('$title失败：$e'); } finally { if (mounted) setState(() => saving = false); } }
  void _toast(String text) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text))); }

  @override
  Widget build(BuildContext context) => Scaffold(body: PageBackdrop(child: SafeArea(child: loading ? const Center(child: CircularProgressIndicator()) : ListView(padding: const EdgeInsets.all(16), children: [
    Row(children: [IconButton(onPressed: () => Navigator.pop(context, group), icon: const Icon(Icons.arrow_back_rounded)), const Text('群管理', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900)), const Spacer(), IconButton(onPressed: load, icon: const Icon(Icons.refresh_rounded))]),
    SoftCard(child: Column(children: [GestureDetector(onTap: canManage ? changeAvatar : null, child: CircleAvatar(radius: 38, backgroundImage: group.avatar.isNotEmpty ? CachedNetworkImageProvider(group.avatar) : null, child: group.avatar.isEmpty ? const Icon(Icons.groups_rounded, size: 34) : null)), ListTile(title: Text(group.name, style: const TextStyle(fontWeight: FontWeight.w900)), subtitle: Text('${group.memberCount}人 · ${group.groupNo} · ${group.myRole}'), trailing: canManage ? const Icon(Icons.edit_rounded) : null, onTap: canManage ? renameGroup : null)])),
    Row(children: [const Text('成员管理', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)), const Spacer(), if (canManage) TextButton.icon(onPressed: addMembers, icon: const Icon(Icons.person_add_alt_1_rounded), label: const Text('添加'))]),
    for (final m in members) SoftCard(margin: const EdgeInsets.only(bottom: 8), padding: EdgeInsets.zero, child: ListTile(leading: CircleAvatar(backgroundImage: m.avatar.isNotEmpty ? CachedNetworkImageProvider(m.avatar) : null, child: m.avatar.isEmpty ? Text(m.nickname.characters.first) : null), title: Text(m.nickname, style: const TextStyle(fontWeight: FontWeight.w800)), subtitle: Text('ID ${m.userId} · ${m.role}'), trailing: canManage && m.userId != widget.session.id ? PopupMenuButton<String>(onSelected: (v) { if (v == 'admin') unawaited(setAdmin(m, true)); if (v == 'member') unawaited(setAdmin(m, false)); if (v == 'remove') unawaited(removeMember(m)); if (v == 'transfer') unawaited(transferOwner(m)); }, itemBuilder: (_) => [if (!m.isAdmin) const PopupMenuItem(value: 'admin', child: Text('设为管理员')), if (m.isAdmin && isOwner) const PopupMenuItem(value: 'member', child: Text('取消管理员')), if (isOwner) const PopupMenuItem(value: 'transfer', child: Text('转让群主')), if (!m.isOwner) const PopupMenuItem(value: 'remove', child: Text('移出群聊'))]) : null)),
    const SizedBox(height: 14),
    FilledButton.icon(style: FilledButton.styleFrom(backgroundColor: Colors.redAccent), onPressed: saving ? null : leaveOrDismiss, icon: Icon(isOwner ? Icons.delete_forever_rounded : Icons.logout_rounded), label: Text(isOwner ? '解散群聊' : '退出群聊')),
  ]))));
}
