import 'package:flutter/material.dart';
import '../models/community.dart';

class PostCard extends StatelessWidget {
  final CommunityPost post;
  final bool featured;

  const PostCard({super.key, required this.post, this.featured = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.fromLTRB(18, featured ? 14 : 10, 18, 14),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(.78),
        borderRadius: BorderRadius.circular(featured ? 34 : 30),
        border: Border.all(color: Colors.white.withOpacity(.78)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF24160D).withOpacity(featured ? .12 : .07),
            blurRadius: featured ? 38 : 28,
            offset: Offset(0, featured ? 24 : 16),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(featured ? 34 : 30),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: _PostHeader(post: post, featured: featured),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
              child: _PostBody(post: post, featured: featured),
            ),
            if (post.image != null) ...[
              const SizedBox(height: 14),
              _PostImage(url: post.image!, featured: featured),
            ],
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
              child: _PostActions(post: post),
            ),
          ],
        ),
      ),
    );
  }
}

class _PostHeader extends StatelessWidget {
  final CommunityPost post;
  final bool featured;
  const _PostHeader({required this.post, required this.featured});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const LinearGradient(
              colors: [Color(0xFFFF7A59), Color(0xFFFFC267)],
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFFF7A59).withOpacity(.18),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: CircleAvatar(
            radius: featured ? 23 : 21,
            backgroundColor: const Color(0xFFFFF4EA),
            backgroundImage: NetworkImage(post.avatar),
          ),
        ),
        const SizedBox(width: 12),
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
                        color: Color(0xFF20130D),
                        fontWeight: FontWeight.w900,
                        fontSize: 15,
                      ),
                    ),
                  ),
                  if (featured) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFF7A59).withOpacity(.13),
                        borderRadius: BorderRadius.circular(99),
                      ),
                      child: const Text(
                        '精选',
                        style: TextStyle(
                          color: Color(0xFFE45D3B),
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 4),
              Text(
                '${post.time} · Blinlin 论坛',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: const Color(0xFF20130D).withOpacity(.46),
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
        IconButton(
          visualDensity: VisualDensity.compact,
          onPressed: () {},
          icon: const Icon(Icons.more_horiz_rounded, color: Color(0xFF6E625A)),
        ),
      ],
    );
  }
}

class _PostBody extends StatelessWidget {
  final CommunityPost post;
  final bool featured;
  const _PostBody({required this.post, required this.featured});

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        post.title,
        maxLines: featured ? 3 : 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: const Color(0xFF20130D),
          fontSize: featured ? 22 : 19,
          fontWeight: FontWeight.w900,
          height: 1.12,
          letterSpacing: featured ? -.55 : -.25,
        ),
      ),
      const SizedBox(height: 8),
      Text(
        post.content,
        maxLines: featured ? 4 : 3,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: const Color(0xFF20130D).withOpacity(.66),
          fontSize: 14,
          height: 1.58,
          fontWeight: FontWeight.w600,
        ),
      ),
    ],
  );
}

class _PostImage extends StatelessWidget {
  final String url;
  final bool featured;
  const _PostImage({required this.url, required this.featured});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 12),
    child: ClipRRect(
      borderRadius: BorderRadius.circular(featured ? 28 : 24),
      child: AspectRatio(
        aspectRatio: featured ? 1.72 : 1.9,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.network(url, fit: BoxFit.cover),
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      const Color(0xFF20130D).withOpacity(.18),
                    ],
                  ),
                ),
              ),
            ),
            if (featured)
              Positioned(
                left: 12,
                bottom: 12,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(.86),
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: const Text(
                    '正在热议',
                    style: TextStyle(
                      color: Color(0xFF20130D),
                      fontWeight: FontWeight.w900,
                      fontSize: 12,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    ),
  );
}

class _PostActions extends StatelessWidget {
  final CommunityPost post;
  const _PostActions({required this.post});

  @override
  Widget build(BuildContext context) => Row(
    children: [
      _ActionPill(
        icon: Icons.favorite_rounded,
        label: '${post.likes}',
        active: true,
      ),
      const SizedBox(width: 9),
      _ActionPill(icon: Icons.mode_comment_rounded, label: '${post.comments}'),
      const SizedBox(width: 9),
      const _ActionPill(icon: Icons.ios_share_rounded, label: '分享'),
      const Spacer(),
      Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: const Color(0xFF20130D).withOpacity(.06),
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Icon(
          Icons.bookmark_border_rounded,
          color: Color(0xFF20130D),
          size: 21,
        ),
      ),
    ],
  );
}

class _ActionPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  const _ActionPill({
    required this.icon,
    required this.label,
    this.active = false,
  });

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
    decoration: BoxDecoration(
      color: active
          ? const Color(0xFFFF7A59).withOpacity(.12)
          : const Color(0xFF20130D).withOpacity(.055),
      borderRadius: BorderRadius.circular(99),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          icon,
          size: 16,
          color: active ? const Color(0xFFE45D3B) : const Color(0xFF4D4037),
        ),
        const SizedBox(width: 5),
        Text(
          label,
          style: TextStyle(
            color: active ? const Color(0xFFE45D3B) : const Color(0xFF4D4037),
            fontSize: 12,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    ),
  );
}
