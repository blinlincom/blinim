import 'package:flutter/material.dart';
import '../models/community.dart';

const _forumBlue = Color(0xFF2F6BFF);
const _ink = Color(0xFF17233D);
const _muted = Color(0xFF778399);
const _line = Color(0xFFE8EEF7);

class PostCard extends StatelessWidget {
  final CommunityPost post;
  final bool featured;
  const PostCard({super.key, required this.post, this.featured = false});

  @override
  Widget build(BuildContext context) {
    final isTop = post.title.contains('置顶');
    final isDigest = post.title.contains('精华') || featured;
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 13, 14, 0),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundImage: NetworkImage(post.avatar),
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              post.author,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: _ink,
                                fontWeight: FontWeight.w900,
                                fontSize: 13,
                              ),
                            ),
                          ),
                          if (isTop)
                            const _Tag(text: '置顶', color: Color(0xFFFF7A00)),
                          if (isDigest)
                            const _Tag(text: '精华', color: _forumBlue),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${post.time} · Blinlin 吧',
                        style: const TextStyle(
                          color: _muted,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () {},
                  icon: const Icon(Icons.more_horiz_rounded, color: _muted),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
            child: Text(
              post.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: _ink,
                fontSize: 17,
                height: 1.25,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 7, 14, 0),
            child: Text(
              post.content,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFF46546A),
                fontSize: 14,
                height: 1.45,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          if (post.image != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: AspectRatio(
                  aspectRatio: 16 / 9,
                  child: Image.network(post.image!, fit: BoxFit.cover),
                ),
              ),
            ),
          const SizedBox(height: 10),
          const Divider(height: 1, color: _line),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 2, 8, 2),
            child: Row(
              children: [
                _Action(
                  icon: Icons.remove_red_eye_outlined,
                  text: '${post.likes + post.comments * 9} 浏览',
                ),
                _Action(
                  icon: Icons.mode_comment_outlined,
                  text: '${post.comments} 回复',
                ),
                _Action(
                  icon: Icons.thumb_up_alt_outlined,
                  text: '${post.likes} 赞',
                ),
                const Spacer(),
                TextButton(onPressed: () {}, child: const Text('进贴')),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  final String text;
  final Color color;
  const _Tag({required this.text, required this.color});
  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(left: 6),
    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .1),
      borderRadius: BorderRadius.circular(4),
      border: Border.all(color: color.withValues(alpha: .28)),
    ),
    child: Text(
      text,
      style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w900),
    ),
  );
}

class _Action extends StatelessWidget {
  final IconData icon;
  final String text;
  const _Action({required this.icon, required this.text});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 6),
    child: Row(
      children: [
        Icon(icon, size: 16, color: _muted),
        const SizedBox(width: 3),
        Text(
          text,
          style: const TextStyle(
            color: _muted,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    ),
  );
}
