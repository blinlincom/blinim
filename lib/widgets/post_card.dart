import 'package:flutter/material.dart';
import '../models/community.dart';

class PostCard extends StatelessWidget {
  final CommunityPost post;
  const PostCard({super.key, required this.post});
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(18, 10, 18, 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white.withOpacity(.78), borderRadius: BorderRadius.circular(30), border: Border.all(color: Colors.white.withOpacity(.75)), boxShadow: [BoxShadow(color: Colors.black.withOpacity(.06), blurRadius: 30, offset: const Offset(0, 18))]),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          CircleAvatar(radius: 22, backgroundImage: NetworkImage(post.avatar)),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(post.author, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)), Text(post.time, style: TextStyle(color: Colors.black.withOpacity(.45), fontSize: 12))])),
          Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7), decoration: BoxDecoration(color: const Color(0xFF101828), borderRadius: BorderRadius.circular(99)), child: const Text('关注', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)))
        ]),
        const SizedBox(height: 14),
        Text(post.title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, height: 1.12)),
        const SizedBox(height: 8),
        Text(post.content, style: TextStyle(fontSize: 14, height: 1.55, color: Colors.black.withOpacity(.66))),
        if (post.image != null) ...[const SizedBox(height: 14), ClipRRect(borderRadius: BorderRadius.circular(24), child: AspectRatio(aspectRatio: 16/9, child: Image.network(post.image!, fit: BoxFit.cover)))],
        const SizedBox(height: 14),
        Row(children: [
          _Pill(icon: Icons.favorite_rounded, label: '${post.likes}'),
          const SizedBox(width: 10),
          _Pill(icon: Icons.mode_comment_rounded, label: '${post.comments}'),
          const Spacer(),
          const Icon(Icons.bookmark_border_rounded),
        ])
      ]),
    );
  }
}

class _Pill extends StatelessWidget { final IconData icon; final String label; const _Pill({required this.icon, required this.label}); @override Widget build(BuildContext context)=>Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), decoration: BoxDecoration(color: const Color(0xFFF3F5F7), borderRadius: BorderRadius.circular(99)), child: Row(children: [Icon(icon, size: 17), const SizedBox(width: 6), Text(label, style: const TextStyle(fontWeight: FontWeight.w700))])); }
