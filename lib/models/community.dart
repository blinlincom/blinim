class CommunityPost {
  final int id;
  final String author;
  final String avatar;
  final String title;
  final String content;
  final String? image;
  final int likes;
  final int comments;
  final String time;
  const CommunityPost({required this.id, required this.author, required this.avatar, required this.title, required this.content, this.image, required this.likes, required this.comments, required this.time});
}
