class UserSession {
  static const String defaultAvatar =
      'https://api.dicebear.com/7.x/initials/png?seed=Blinlin';

  final int id;
  final String username;
  final String token;
  final String? nickname;
  final String avatar;

  const UserSession({
    required this.id,
    required this.username,
    required this.token,
    this.nickname,
    this.avatar = defaultAvatar,
  });

  UserSession copyWith({
    int? id,
    String? username,
    String? token,
    String? nickname,
    String? avatar,
  }) => UserSession(
    id: id ?? this.id,
    username: username ?? this.username,
    token: token ?? this.token,
    nickname: nickname ?? this.nickname,
    avatar: avatar ?? this.avatar,
  );

  factory UserSession.fromJson(Map<String, dynamic> json) {
    final avatar = _pickAvatar(json);
    return UserSession(
      id: int.tryParse('${json['id']}') ?? 0,
      username: '${json['username'] ?? ''}',
      token: '${json['usertoken'] ?? json['token'] ?? ''}',
      nickname: json['nickname']?.toString(),
      avatar: avatar.isEmpty ? defaultAvatar : avatar,
    );
  }

  static String _pickAvatar(Map<String, dynamic> json) {
    for (final key in const [
      'avatar',
      'headimg',
      'head_img',
      'head_image',
      'userpic',
      'user_pic',
      'face',
      'photo',
      'portrait',
    ]) {
      final value = json[key];
      if (value != null && '$value'.trim().isNotEmpty && '$value' != 'null') {
        return '$value'.trim();
      }
    }
    return '';
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'username': username,
    'usertoken': token,
    'nickname': nickname,
    'avatar': avatar,
  };
}
