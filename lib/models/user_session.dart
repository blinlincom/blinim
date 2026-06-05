class UserSession {
  final int id;
  final String username;
  final String token;
  final String? nickname;
  const UserSession({required this.id, required this.username, required this.token, this.nickname});
  factory UserSession.fromJson(Map<String, dynamic> json) => UserSession(
    id: int.tryParse('${json['id']}') ?? 0,
    username: '${json['username'] ?? ''}',
    token: '${json['usertoken'] ?? json['token'] ?? ''}',
    nickname: json['nickname']?.toString(),
  );
  Map<String, dynamic> toJson() => {'id': id, 'username': username, 'usertoken': token, 'nickname': nickname};
}
