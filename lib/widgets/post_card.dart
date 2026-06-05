import 'package:flutter/material.dart';
import '../models/community.dart';

class PostCard extends StatelessWidget {
  final CommunityPost post;
  final bool featured;
  const PostCard({super.key, required this.post, this.featured = false});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: scheme.surfaceContainerLow,
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ListTile(
            leading: CircleAvatar(backgroundImage: NetworkImage(post.avatar)),
            title: Row(
              children: [
                Flexible(
                  child: Text(
                    post.author,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
                if (featured) ...[
                  const SizedBox(width: 8),
                  Badge(
                    label: const Text('精选'),
                    backgroundColor: scheme.primary,
                  ),
                ],
              ],
            ),
            subtitle: Text('${post.time} · Blinlin 论坛'),
            trailing: IconButton(
              onPressed: () {},
              icon: const Icon(Icons.more_horiz_rounded),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  post.title,
                  maxLines: featured ? 3 : 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                Text(
                  post.content,
                  maxLines: featured ? 4 : 3,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: scheme.onSurfaceVariant,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
          if (post.image != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: AspectRatio(
                  aspectRatio: featured ? 16 / 9 : 1.9,
                  child: Image.network(post.image!, fit: BoxFit.cover),
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
            child: Row(
              children: [
                TextButton.icon(
                  onPressed: () {},
                  icon: const Icon(Icons.favorite_border_rounded),
                  label: Text('${post.likes}'),
                ),
                TextButton.icon(
                  onPressed: () {},
                  icon: const Icon(Icons.mode_comment_outlined),
                  label: Text('${post.comments}'),
                ),
                TextButton.icon(
                  onPressed: () {},
                  icon: const Icon(Icons.ios_share_rounded),
                  label: const Text('分享'),
                ),
                const Spacer(),
                IconButton(
                  onPressed: () {},
                  icon: const Icon(Icons.bookmark_border_rounded),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
