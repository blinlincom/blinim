class CommunityPost {
  final int id;
  final String author;
  final String avatar;
  final String title;
  final String content;
  final String? image;
  final List<String> images;
  final String videoUrl;
  final String videoCover;
  final int likes;
  final int comments;
  final String time;
  const CommunityPost({
    required this.id,
    required this.author,
    required this.avatar,
    required this.title,
    required this.content,
    this.image,
    this.images = const [],
    this.videoUrl = '',
    this.videoCover = '',
    required this.likes,
    required this.comments,
    required this.time,
  });
}
