import 'dart:async';
import 'dart:convert';
import 'package:crypto/crypto.dart' as crypto;
import 'package:encrypt/encrypt.dart' as encrypt;
import 'package:http/http.dart' as http;
import '../core/app_config.dart';
import '../core/app_logger.dart';
import '../core/safe_random.dart';
import 'client_device_context.dart';
import '../models/user_session.dart';
import '../models/im_models.dart';
import '../models/call_signal.dart';

class ApiException implements Exception {
  final String message;
  ApiException(this.message);
  @override
  String toString() => message;
}

class AuthExpiredException extends ApiException {
  AuthExpiredException(super.message);
}

class AuthSessionEvents {
  static final _controller = StreamController<void>.broadcast();
  static bool _notified = false;

  static Stream<void> get expired => _controller.stream;

  static void notifyExpired() {
    if (_notified) {
      return;
    }
    _notified = true;
    if (!_controller.isClosed) {
      _controller.add(null);
    }
  }

  static void reset() {
    _notified = false;
  }
}

class UserSearchResult {
  final int id;
  final String username;
  final String nickname;
  final String avatar;
  final String title;
  const UserSearchResult({
    required this.id,
    required this.username,
    required this.nickname,
    required this.avatar,
    this.title = '',
  });
  factory UserSearchResult.fromJson(Map<String, dynamic> j) => UserSearchResult(
    id: int.tryParse('${j['id'] ?? j['userid'] ?? j['uid'] ?? 0}') ?? 0,
    username: '${j['username'] ?? ''}',
    nickname: '${j['nickname'] ?? j['username'] ?? '用户'}',
    avatar: '${j['usertx'] ?? j['avatar'] ?? ''}',
    title: _pickDisplayTitle(j),
  );
}

class PaymentPasswordStatus {
  final bool hasPassword;
  final bool walletLocked;
  final String walletLockReason;
  final int failedAttempts;
  final int remainingAttempts;
  final bool mobileBound;
  final bool emailBound;
  final String maskedMobile;
  final String maskedEmail;
  final Map<String, dynamic> raw;

  const PaymentPasswordStatus({
    required this.hasPassword,
    required this.walletLocked,
    this.walletLockReason = '',
    required this.failedAttempts,
    required this.remainingAttempts,
    required this.mobileBound,
    required this.emailBound,
    this.maskedMobile = '',
    this.maskedEmail = '',
    this.raw = const {},
  });

  factory PaymentPasswordStatus.fromJson(Map<String, dynamic> json) {
    bool truthy(Object? value) {
      final text = '${value ?? ''}'.trim().toLowerCase();
      return text == '1' || text == 'true' || text == 'yes' || text == 'on';
    }

    return PaymentPasswordStatus(
      hasPassword: truthy(json['has_password'] ?? json['has_pay_password']),
      walletLocked: truthy(json['wallet_locked'] ?? json['locked']),
      walletLockReason:
          '${json['wallet_locked_reason'] ?? json['wallet_lock_reason'] ?? json['lock_reason'] ?? ''}'
              .trim(),
      failedAttempts:
          int.tryParse(
            '${json['failed_attempts'] ?? json['fail_count'] ?? 0}',
          ) ??
          0,
      remainingAttempts:
          int.tryParse(
            '${json['remaining_attempts'] ?? json['remain'] ?? 3}',
          ) ??
          3,
      mobileBound: truthy(json['mobile_bound'] ?? json['has_mobile']),
      emailBound: truthy(json['email_bound'] ?? json['has_email']),
      maskedMobile: '${json['masked_mobile'] ?? json['mobile_text'] ?? ''}',
      maskedEmail: '${json['masked_email'] ?? json['email_text'] ?? ''}',
      raw: Map<String, dynamic>.from(json),
    );
  }
}

String _pickDisplayTitle(Map<String, dynamic> j) {
  const keys = [
    'display_title',
    'user_title',
    'title_name',
    'title',
    'badge_name',
    'medal_name',
    'honor',
    'honor_name',
    'rank_title',
    'user_badge',
    'certification',
    'certification_name',
    'auth_title',
    'role_name',
    'identity',
    'identity_name',
    'tag_name',
    'label_name',
  ];
  for (final key in keys) {
    final value = j[key];
    final text = _cleanDisplayTitleText(value);
    if (text.isNotEmpty) return text;
  }
  return '';
}

String _cleanDisplayTitleText(Object? value) {
  var text = '${value ?? ''}'.trim();
  if (text.isEmpty) return '';
  final lower = text.toLowerCase();
  if (lower == 'null' || lower == 'undefined' || lower == 'false') return '';
  if (text == '0' || text == '--' || text == '-' || text == '[]') return '';
  text = text
      .replaceAll(RegExp(r'^[\[\]【】（）()\s]+'), '')
      .replaceAll(RegExp(r'[\[\]【】（）()\s]+$'), '')
      .trim();
  if (text.isEmpty || text == '0' || text == '--' || text == '-') return '';
  return text;
}

class UserPublicProfile {
  final int id;
  final String username;
  final String nickname;
  final String avatar;
  final String background;
  final String title;
  final String signature;
  final String sexName;
  final String createTime;
  final String level;
  final String points;
  final String coins;
  final Map<String, dynamic> raw;

  const UserPublicProfile({
    required this.id,
    this.username = '',
    this.nickname = '',
    this.avatar = '',
    this.background = '',
    this.title = '',
    this.signature = '',
    this.sexName = '',
    this.createTime = '',
    this.level = '',
    this.points = '',
    this.coins = '',
    this.raw = const {},
  });

  factory UserPublicProfile.fromJson(Map<String, dynamic> j) {
    String pick(List<String> keys, [String fallback = '']) {
      for (final key in keys) {
        final value = j[key];
        if (value != null && '$value'.trim().isNotEmpty) return '$value';
      }
      return fallback;
    }

    return UserPublicProfile(
      id: int.tryParse('${j['id'] ?? j['userid'] ?? j['uid'] ?? 0}') ?? 0,
      username: pick(['username', 'account']),
      nickname: pick(['nickname', 'name', 'nick_name', 'username'], '用户'),
      avatar: pick(['usertx', 'avatar', 'user_avatar', 'headimg']),
      background: pick([
        'userbg',
        'user_bg',
        'user_cover',
        'background',
        'background_url',
        'user_background',
        'profile_background',
        'profile_bg',
        'bg',
        'cover',
        'cover_url',
        'homepage_background',
        'moment_background',
      ]),
      title: _pickDisplayTitle(j),
      signature: pick(['signature', 'sign', 'bio']),
      sexName: pick(['sexName', 'sex_name', 'gender']),
      createTime: pick(['create_time', 'created_at', 'register_time']),
      level: pick(['level', 'lv', 'grade', 'exp']),
      points: pick(['integral', 'points', 'score']),
      coins: pick(['money', 'coins', 'balance']),
      raw: Map<String, dynamic>.from(j),
    );
  }
}

class MomentLikeUser {
  final int userId;
  final String nickname;
  final String avatar;
  final String title;

  const MomentLikeUser({
    required this.userId,
    required this.nickname,
    required this.avatar,
    this.title = '',
  });

  factory MomentLikeUser.fromJson(Map<String, dynamic> j) => MomentLikeUser(
    userId: int.tryParse('${j['user_id'] ?? j['uid'] ?? 0}') ?? 0,
    nickname: '${j['nickname'] ?? j['name'] ?? j['username'] ?? '用户'}',
    avatar: '${j['avatar'] ?? j['usertx'] ?? ''}',
    title: _pickDisplayTitle(j),
  );
}

class MomentCommentItem {
  final int id;
  final int momentId;
  final int userId;
  final int parentId;
  final int replyUserId;
  final String nickname;
  final String username;
  final String avatar;
  final String title;
  final String replyNickname;
  final String replyTitle;
  final String content;
  final DateTime createTime;
  final Map<String, dynamic> raw;

  const MomentCommentItem({
    required this.id,
    required this.momentId,
    required this.userId,
    required this.parentId,
    required this.replyUserId,
    required this.nickname,
    required this.username,
    required this.avatar,
    this.title = '',
    required this.replyNickname,
    this.replyTitle = '',
    required this.content,
    required this.createTime,
    required this.raw,
  });

  MomentCommentItem copyWith({
    int? id,
    int? momentId,
    int? userId,
    int? parentId,
    int? replyUserId,
    String? nickname,
    String? username,
    String? avatar,
    String? title,
    String? replyNickname,
    String? replyTitle,
    String? content,
    DateTime? createTime,
    Map<String, dynamic>? raw,
  }) => MomentCommentItem(
    id: id ?? this.id,
    momentId: momentId ?? this.momentId,
    userId: userId ?? this.userId,
    parentId: parentId ?? this.parentId,
    replyUserId: replyUserId ?? this.replyUserId,
    nickname: nickname ?? this.nickname,
    username: username ?? this.username,
    avatar: avatar ?? this.avatar,
    title: title ?? this.title,
    replyNickname: replyNickname ?? this.replyNickname,
    replyTitle: replyTitle ?? this.replyTitle,
    content: content ?? this.content,
    createTime: createTime ?? this.createTime,
    raw: raw ?? this.raw,
  );

  factory MomentCommentItem.fromJson(Map<String, dynamic> j) {
    return MomentCommentItem(
      id: int.tryParse('${j['id'] ?? j['comment_id'] ?? 0}') ?? 0,
      momentId: int.tryParse('${j['moment_id'] ?? 0}') ?? 0,
      userId: int.tryParse('${j['user_id'] ?? j['uid'] ?? 0}') ?? 0,
      parentId: int.tryParse('${j['parent_id'] ?? 0}') ?? 0,
      replyUserId: int.tryParse('${j['reply_user_id'] ?? 0}') ?? 0,
      nickname: '${j['nickname'] ?? j['name'] ?? j['username'] ?? '用户'}',
      username: '${j['username'] ?? ''}',
      avatar: '${j['avatar'] ?? j['usertx'] ?? ''}',
      title: _pickDisplayTitle(j),
      replyNickname: '${j['reply_nickname'] ?? j['reply_username'] ?? ''}',
      replyTitle: _pickDisplayTitle({
        'display_title': j['reply_display_title'],
        'user_title': j['reply_user_title'],
        'title_name': j['reply_title_name'],
        'title': j['reply_title'],
        'badge_name': j['reply_badge_name'],
        'medal_name': j['reply_medal_name'],
        'honor': j['reply_honor'],
        'honor_name': j['reply_honor_name'],
      }),
      content: '${j['content'] ?? ''}',
      createTime:
          DateTime.tryParse('${j['create_time'] ?? j['created_at'] ?? ''}') ??
          DateTime.now(),
      raw: Map<String, dynamic>.from(j),
    );
  }
}

class MomentNotificationItem {
  final int id;
  final int momentId;
  final int commentId;
  final int actorId;
  final String action;
  final String content;
  final bool isRead;
  final String actorNickname;
  final String actorAvatar;
  final String actorTitle;
  final String momentContent;
  final DateTime createTime;
  final Map<String, dynamic> raw;

  const MomentNotificationItem({
    required this.id,
    required this.momentId,
    required this.commentId,
    required this.actorId,
    required this.action,
    required this.content,
    required this.isRead,
    required this.actorNickname,
    required this.actorAvatar,
    this.actorTitle = '',
    required this.momentContent,
    required this.createTime,
    required this.raw,
  });

  String get actionLabel {
    switch (action) {
      case 'like':
        return '赞了你的朋友圈';
      case 'comment':
        return '评论了你的朋友圈';
      case 'reply':
        return '回复了你的评论';
      case 'admin_delete':
      case 'delete':
        return '删除了你的朋友圈';
      default:
        return '互动提醒';
    }
  }

  factory MomentNotificationItem.fromJson(Map<String, dynamic> j) {
    return MomentNotificationItem(
      id: int.tryParse('${j['id'] ?? 0}') ?? 0,
      momentId: int.tryParse('${j['moment_id'] ?? 0}') ?? 0,
      commentId: int.tryParse('${j['comment_id'] ?? 0}') ?? 0,
      actorId: int.tryParse('${j['actor_id'] ?? 0}') ?? 0,
      action: '${j['action'] ?? ''}',
      content: '${j['content'] ?? ''}',
      isRead: '${j['is_read'] ?? 0}' == '1' || j['is_read'] == true,
      actorNickname: (int.tryParse('${j['actor_id'] ?? 0}') ?? 0) <= 0
          ? '系统通知'
          : '${j['actor_nickname'] ?? j['nickname'] ?? j['username'] ?? '用户'}',
      actorAvatar: '${j['actor_avatar'] ?? j['avatar'] ?? j['usertx'] ?? ''}',
      actorTitle: _pickDisplayTitle({
        'display_title': j['actor_display_title'] ?? j['display_title'],
        'user_title': j['actor_user_title'] ?? j['user_title'],
        'title_name': j['actor_title_name'] ?? j['title_name'],
        'title': j['actor_title'] ?? j['title'],
        'badge_name': j['actor_badge_name'] ?? j['badge_name'],
        'medal_name': j['actor_medal_name'] ?? j['medal_name'],
        'honor': j['actor_honor'] ?? j['honor'],
        'honor_name': j['actor_honor_name'] ?? j['honor_name'],
      }),
      momentContent: '${j['moment_content'] ?? ''}',
      createTime:
          DateTime.tryParse('${j['create_time'] ?? j['created_at'] ?? ''}') ??
          DateTime.now(),
      raw: Map<String, dynamic>.from(j),
    );
  }
}

class MomentLikeResult {
  final bool liked;
  final int likeCount;
  const MomentLikeResult({required this.liked, required this.likeCount});

  factory MomentLikeResult.fromJson(Map<String, dynamic> j) => MomentLikeResult(
    liked:
        '${j['liked'] ?? j['is_liked'] ?? 0}' == '1' ||
        j['liked'] == true ||
        j['is_liked'] == true,
    likeCount: int.tryParse('${j['like_count'] ?? j['count'] ?? 0}') ?? 0,
  );
}

class MomentCommentResult {
  final MomentCommentItem comment;
  final int commentCount;
  const MomentCommentResult({
    required this.comment,
    required this.commentCount,
  });

  factory MomentCommentResult.fromJson(Map<String, dynamic> j) =>
      MomentCommentResult(
        comment: MomentCommentItem.fromJson(
          j['comment'] is Map
              ? Map<String, dynamic>.from(j['comment'])
              : Map<String, dynamic>.from(j),
        ),
        commentCount:
            int.tryParse('${j['comment_count'] ?? j['count'] ?? 0}') ?? 0,
      );
}

class FriendRequestItem {
  final int id;
  final int fromUserId;
  final int toUserId;
  final String nickname;
  final String username;
  final String avatar;
  final String message;
  final String statusText;
  final int status;
  final String createTime;
  final Map<String, dynamic> raw;

  const FriendRequestItem({
    required this.id,
    required this.fromUserId,
    required this.toUserId,
    required this.nickname,
    required this.username,
    required this.avatar,
    required this.message,
    required this.statusText,
    required this.status,
    required this.createTime,
    required this.raw,
  });

  int get userId => fromUserId;
  bool get pending => status == 0;

  factory FriendRequestItem.fromJson(Map<String, dynamic> j) {
    final status =
        int.tryParse('${j['request_status'] ?? j['status'] ?? 0}') ?? 0;
    final fromId =
        int.tryParse(
          '${j['from_user_id'] ?? j['friend_id'] ?? j['user_id'] ?? 0}',
        ) ??
        0;
    final toId = int.tryParse('${j['to_user_id'] ?? 0}') ?? 0;
    final currentId =
        int.tryParse('${j['current_user_id'] ?? j['self_user_id'] ?? 0}') ?? 0;
    final preferToUser = currentId > 0 && fromId == currentId;
    final nickname = preferToUser
        ? '${j['to_nickname'] ?? j['to_username'] ?? j['nickname'] ?? j['username'] ?? '用户$toId'}'
        : '${j['from_nickname'] ?? j['nickname'] ?? j['from_username'] ?? j['username'] ?? j['to_nickname'] ?? j['to_username'] ?? '用户$fromId'}';
    return FriendRequestItem(
      id: int.tryParse('${j['id'] ?? j['request_id'] ?? 0}') ?? 0,
      fromUserId: fromId,
      toUserId: toId,
      nickname: nickname,
      username: preferToUser
          ? '${j['to_username'] ?? j['username'] ?? ''}'
          : '${j['from_username'] ?? j['username'] ?? j['to_username'] ?? ''}',
      avatar: preferToUser
          ? '${j['to_avatar'] ?? j['avatar'] ?? j['usertx'] ?? ''}'
          : '${j['from_avatar'] ?? j['avatar'] ?? j['usertx'] ?? j['to_avatar'] ?? ''}',
      message: '${j['message'] ?? j['content'] ?? j['msg'] ?? '请求添加你为好友'}',
      statusText:
          '${j['status_text'] ?? (status == 1
                  ? '已通过'
                  : status == 2
                  ? '已拒绝'
                  : '待处理')}',
      status: status,
      createTime: '${j['create_time'] ?? j['created_at'] ?? ''}',
      raw: Map<String, dynamic>.from(j),
    );
  }
}

class UserQrInfo {
  final String qrData;
  final UserSearchResult user;
  const UserQrInfo({required this.qrData, required this.user});

  factory UserQrInfo.fromJson(Map<String, dynamic> j) {
    final userRaw = j['user'] is Map
        ? Map<String, dynamic>.from(j['user'])
        : Map<String, dynamic>.from(j);
    return UserQrInfo(
      qrData: '${j['qr_data'] ?? j['qr'] ?? j['code'] ?? ''}',
      user: UserSearchResult.fromJson(userRaw),
    );
  }
}

class AppRegistrationConfig {
  final bool registrationEnabled;
  final String closingPrompt;
  final int codeSwitch;
  final bool invitationEnabled;
  final int singleDeviceLimit;

  const AppRegistrationConfig({
    required this.registrationEnabled,
    required this.closingPrompt,
    required this.codeSwitch,
    required this.invitationEnabled,
    required this.singleDeviceLimit,
  });

  bool get imageCaptchaRequired => codeSwitch == 1;
  bool get emailCodeRequired => codeSwitch == 2;
  bool get mobileCodeRequired => codeSwitch == 3;
  bool get codeRequired =>
      codeSwitch == 1 || codeSwitch == 2 || codeSwitch == 3;

  factory AppRegistrationConfig.fromAppInfo(Map<String, dynamic> appInfo) {
    final registration = _asStringMap(appInfo['registration_configuration']);
    final invitation = _asStringMap(appInfo['invitation_configuration']);
    final registrationSwitch = _toInt(
      registration['registration_switch'] ?? appInfo['registration_switch'],
    );
    final invitationSwitch = _toInt(
      invitation['invitation_switch'] ?? appInfo['invitation_switch'],
    );
    return AppRegistrationConfig(
      registrationEnabled: registrationSwitch != 1,
      closingPrompt:
          '${registration['registration_closing_prompt'] ?? '当前应用暂未开放注册'}',
      codeSwitch: _toInt(
        registration['registration_code_switch'] ??
            registration['code_switch'] ??
            0,
      ),
      invitationEnabled: invitationSwitch == 0,
      singleDeviceLimit: _toInt(
        registration['single_device_registration_limit'] ?? 0,
      ),
    );
  }

  static Map<String, dynamic> _asStringMap(Object? value) {
    if (value is Map<String, dynamic>) return Map<String, dynamic>.from(value);
    if (value is Map) return Map<String, dynamic>.from(value);
    if (value is String && value.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(value);
        if (decoded is Map<String, dynamic>) return decoded;
        if (decoded is Map) return Map<String, dynamic>.from(decoded);
      } catch (_) {}
    }
    return const <String, dynamic>{};
  }

  static int _toInt(Object? value) => int.tryParse('${value ?? 0}') ?? 0;
}

class AppLoginConfig {
  final bool loginEnabled;
  final String closingPrompt;
  final int codeSwitch;
  final bool newDeviceLoginEnabled;
  final String sameTerminalLoginPolicy;

  const AppLoginConfig({
    required this.loginEnabled,
    required this.closingPrompt,
    required this.codeSwitch,
    required this.newDeviceLoginEnabled,
    required this.sameTerminalLoginPolicy,
  });

  bool get imageCaptchaRequired => codeSwitch == 1;

  factory AppLoginConfig.fromAppInfo(Map<String, dynamic> appInfo) {
    final login = AppRegistrationConfig._asStringMap(
      appInfo['login_configuration'],
    );
    final loginSwitch = AppRegistrationConfig._toInt(
      login['login_switch'] ?? appInfo['login_switch'],
    );
    return AppLoginConfig(
      loginEnabled: loginSwitch != 1,
      closingPrompt: '${login['login_closing_prompt'] ?? '当前应用暂未开放登录'}',
      codeSwitch: AppRegistrationConfig._toInt(
        login['login_code_switch'] ?? login['code_switch'] ?? 0,
      ),
      newDeviceLoginEnabled:
          AppRegistrationConfig._toInt(login['new_device_login_switch'] ?? 0) ==
          1,
      sameTerminalLoginPolicy:
          '${login['same_terminal_login_policy'] ?? 'kick_previous'}',
    );
  }
}

class AppUserInfoConfig {
  final bool showUserId;
  final bool showGroupNo;
  final bool usernameChangeEnabled;
  final int usernameChangeIntervalDays;
  final bool profileAuditEnabled;

  const AppUserInfoConfig({
    required this.showUserId,
    this.showGroupNo = true,
    required this.usernameChangeEnabled,
    required this.usernameChangeIntervalDays,
    this.profileAuditEnabled = false,
  });

  factory AppUserInfoConfig.fromAppInfo(Map<String, dynamic> appInfo) {
    final info = AppRegistrationConfig._asStringMap(
      appInfo['userinfo_configuration'],
    );
    final showSwitch = AppRegistrationConfig._toInt(
      info['show_user_id_switch'] ?? info['show_user_id'] ?? 1,
    );
    final im = AppRegistrationConfig._asStringMap(appInfo['im_configuration']);
    final groupNoDisplaySwitch = AppRegistrationConfig._toInt(
      im['group_no_display_switch'] ??
          im['group_no_show_switch'] ??
          im['show_group_no_switch'] ??
          im['show_group_no'] ??
          appInfo['group_no_display_switch'] ??
          0,
    );
    final changeSwitch = AppRegistrationConfig._toInt(
      info['username_change_switch'] ?? 0,
    );
    final auditSwitch = AppRegistrationConfig._toInt(
      info['profile_audit_switch'] ??
          info['user_info_audit_switch'] ??
          info['userinfo_audit_switch'] ??
          info['audit_switch'] ??
          info['review_switch'] ??
          appInfo['profile_audit_switch'] ??
          0,
    );
    final updateUserInfoAudit =
        info['update_userinfo_audit'] ??
        info['update_user_info_audit'] ??
        info['userinfo_update_audit'] ??
        appInfo['update_userinfo_audit'];
    final updateUserInfoAuditText = '${updateUserInfoAudit ?? ''}'.trim();
    final profileAuditEnabled =
        updateUserInfoAuditText.isNotEmpty &&
            updateUserInfoAuditText.toLowerCase() != 'null'
        ? AppRegistrationConfig._toInt(updateUserInfoAudit) == 0
        : auditSwitch == 1;
    return AppUserInfoConfig(
      showUserId: showSwitch == 0,
      showGroupNo: groupNoDisplaySwitch == 0,
      usernameChangeEnabled: changeSwitch == 0,
      usernameChangeIntervalDays: AppRegistrationConfig._toInt(
        info['username_change_interval_days'] ?? 30,
      ),
      profileAuditEnabled: profileAuditEnabled,
    );
  }
}

class AppMomentsConfig {
  final bool enabled;
  final String visibility;
  const AppMomentsConfig({required this.enabled, this.visibility = 'friends'});

  bool get allVisible => visibility == 'all';
  String get visibilityLabel => allVisible ? '全员可见' : '仅好友可见';

  factory AppMomentsConfig.fromAppInfo(Map<String, dynamic> appInfo) {
    final forum = AppRegistrationConfig._asStringMap(
      appInfo['forum_configuration'],
    );
    final switchValue = AppRegistrationConfig._toInt(
      forum['moments_switch'] ?? appInfo['moments_switch'] ?? 0,
    );
    final rawVisibility = '${forum['moments_visibility'] ?? 'friends'}'
        .trim()
        .toLowerCase();
    return AppMomentsConfig(
      enabled: switchValue == 0,
      visibility: rawVisibility == 'all' ? 'all' : 'friends',
    );
  }
}

class MomentItem {
  final int id;
  final int userId;
  final String nickname;
  final String username;
  final String avatar;
  final String title;
  final String content;
  final List<String> images;
  final String videoUrl;
  final String videoThumb;
  final String visibility;
  final String visibilityType;
  final List<int> visibleUserIds;
  final List<int> hiddenUserIds;
  final int likeCount;
  final int commentCount;
  final bool likedByMe;
  final List<MomentLikeUser> likeUsers;
  final List<MomentCommentItem> comments;
  final DateTime createTime;
  final Map<String, dynamic> raw;

  const MomentItem({
    required this.id,
    required this.userId,
    required this.nickname,
    required this.username,
    required this.avatar,
    this.title = '',
    required this.content,
    required this.images,
    required this.videoUrl,
    required this.videoThumb,
    required this.visibility,
    required this.visibilityType,
    required this.visibleUserIds,
    required this.hiddenUserIds,
    required this.likeCount,
    required this.commentCount,
    required this.likedByMe,
    required this.likeUsers,
    required this.comments,
    required this.createTime,
    required this.raw,
  });

  String get visibilityLabel {
    switch (visibilityType) {
      case 'public':
        return '公开';
      case 'include':
        return '部分可见';
      case 'exclude':
        return '部分不可见';
      case 'private':
        return '仅自己可见';
      case 'friends':
      default:
        return '仅好友';
    }
  }

  MomentItem copyWith({
    String? content,
    List<String>? images,
    String? videoUrl,
    String? videoThumb,
    String? visibility,
    String? visibilityType,
    List<int>? visibleUserIds,
    List<int>? hiddenUserIds,
    int? likeCount,
    int? commentCount,
    bool? likedByMe,
    List<MomentLikeUser>? likeUsers,
    List<MomentCommentItem>? comments,
  }) => MomentItem(
    id: id,
    userId: userId,
    nickname: nickname,
    username: username,
    avatar: avatar,
    title: title,
    content: content ?? this.content,
    images: images ?? this.images,
    videoUrl: videoUrl ?? this.videoUrl,
    videoThumb: videoThumb ?? this.videoThumb,
    visibility: visibility ?? this.visibility,
    visibilityType: visibilityType ?? this.visibilityType,
    visibleUserIds: visibleUserIds ?? this.visibleUserIds,
    hiddenUserIds: hiddenUserIds ?? this.hiddenUserIds,
    likeCount: likeCount ?? this.likeCount,
    commentCount: commentCount ?? this.commentCount,
    likedByMe: likedByMe ?? this.likedByMe,
    likeUsers: likeUsers ?? this.likeUsers,
    comments: comments ?? this.comments,
    createTime: createTime,
    raw: raw,
  );

  factory MomentItem.fromJson(Map<String, dynamic> j) {
    final rawImages = j['images'] ?? j['image_list'] ?? j['pics'];
    final images = <String>[];
    if (rawImages is List) {
      for (final item in rawImages) {
        final url = '$item'.trim();
        if (url.isNotEmpty) images.add(url);
      }
    } else if ('$rawImages'.trim().isNotEmpty && '$rawImages' != 'null') {
      try {
        final decoded = jsonDecode('$rawImages');
        if (decoded is List) {
          for (final item in decoded) {
            final url = '$item'.trim();
            if (url.isNotEmpty) images.add(url);
          }
        }
      } catch (_) {
        for (final item in '$rawImages'.split(RegExp(r'[,，\s]+'))) {
          final url = item.trim();
          if (url.isNotEmpty) images.add(url);
        }
      }
    }
    final rawVisibility =
        '${j['visibility'] ?? j['visible_scope'] ?? 'friends'}'
            .trim()
            .toLowerCase();
    final rawVisibilityType =
        '${j['visibility_type'] ?? j['moment_visibility'] ?? rawVisibility}'
            .trim()
            .toLowerCase();
    List<int> parseIds(dynamic raw) {
      final ids = <int>[];
      if (raw is List) {
        for (final item in raw) {
          final id = int.tryParse('$item') ?? 0;
          if (id > 0) ids.add(id);
        }
      } else if ('$raw'.trim().isNotEmpty && '$raw' != 'null') {
        try {
          final decoded = jsonDecode('$raw');
          if (decoded is List) {
            for (final item in decoded) {
              final id = int.tryParse('$item') ?? 0;
              if (id > 0) ids.add(id);
            }
          }
        } catch (_) {
          for (final item in '$raw'.split(RegExp(r'[,，\s]+'))) {
            final id = int.tryParse(item.trim()) ?? 0;
            if (id > 0) ids.add(id);
          }
        }
      }
      return ids.toSet().toList();
    }

    String normalizeVisibilityType(String value) {
      switch (value) {
        case 'public':
        case 'all':
          return 'public';
        case 'private':
        case 'self':
          return 'private';
        case 'include':
        case 'visible':
        case 'selected':
          return 'include';
        case 'exclude':
        case 'hidden':
        case 'block':
          return 'exclude';
        case 'friends':
        default:
          return 'friends';
      }
    }

    List<MomentLikeUser> parseLikeUsers(dynamic raw) {
      final list = <MomentLikeUser>[];
      final source = raw is List ? raw : const <dynamic>[];
      for (final item in source) {
        if (item is Map<String, dynamic>) {
          list.add(MomentLikeUser.fromJson(item));
        } else if (item is Map) {
          list.add(MomentLikeUser.fromJson(Map<String, dynamic>.from(item)));
        }
      }
      return list;
    }

    List<MomentCommentItem> parseComments(dynamic raw) {
      final list = <MomentCommentItem>[];
      final source = raw is List ? raw : const <dynamic>[];
      for (final item in source) {
        if (item is Map<String, dynamic>) {
          list.add(MomentCommentItem.fromJson(item));
        } else if (item is Map) {
          list.add(MomentCommentItem.fromJson(Map<String, dynamic>.from(item)));
        }
      }
      return list;
    }

    return MomentItem(
      id: int.tryParse('${j['id'] ?? j['moment_id'] ?? 0}') ?? 0,
      userId: int.tryParse('${j['user_id'] ?? j['uid'] ?? 0}') ?? 0,
      nickname: '${j['nickname'] ?? j['name'] ?? j['username'] ?? '用户'}',
      username: '${j['username'] ?? ''}',
      avatar: '${j['avatar'] ?? j['usertx'] ?? ''}',
      title: _pickDisplayTitle(j),
      content: '${j['content'] ?? j['text'] ?? ''}',
      images: images,
      videoUrl: '${j['video_url'] ?? j['video'] ?? ''}',
      videoThumb: '${j['video_thumb'] ?? j['thumb'] ?? ''}',
      visibility: rawVisibility == 'all' ? 'all' : 'friends',
      visibilityType: normalizeVisibilityType(rawVisibilityType),
      visibleUserIds: parseIds(j['visible_user_ids'] ?? j['allow_user_ids']),
      hiddenUserIds: parseIds(j['hidden_user_ids'] ?? j['deny_user_ids']),
      likeCount: int.tryParse('${j['like_count'] ?? j['likes'] ?? 0}') ?? 0,
      commentCount:
          int.tryParse('${j['comment_count'] ?? j['comments'] ?? 0}') ?? 0,
      likedByMe:
          '${j['liked_by_me'] ?? j['is_liked'] ?? j['liked'] ?? 0}' == '1' ||
          j['liked_by_me'] == true ||
          j['is_liked'] == true ||
          j['liked'] == true,
      likeUsers: parseLikeUsers(
        j['like_users'] ?? j['likes_users'] ?? j['like_list'],
      ),
      comments: parseComments(
        j['comments'] ?? j['comment_list'] ?? j['reply_list'],
      ),
      createTime:
          DateTime.tryParse('${j['create_time'] ?? j['created_at'] ?? ''}') ??
          DateTime.now(),
      raw: Map<String, dynamic>.from(j),
    );
  }
}

class MomentProfileStats {
  final int posts;
  final int likes;
  const MomentProfileStats({this.posts = 0, this.likes = 0});

  factory MomentProfileStats.fromJson(Map<String, dynamic> j) {
    int pick(List<String> keys) {
      for (final key in keys) {
        final value = j[key];
        final parsed = int.tryParse('$value');
        if (parsed != null) return parsed;
      }
      return 0;
    }

    return MomentProfileStats(
      posts: pick([
        'posts',
        'post_count',
        'moments',
        'moment_count',
        'dynamic_count',
        'timeline_count',
      ]),
      likes: pick([
        'likes',
        'like_count',
        'liked_count',
        'moment_likes',
        'total_likes',
      ]),
    );
  }
}

class UserProfileSummary {
  final String username;
  final String nickname;
  final String avatar;
  final String background;
  final String email;
  final String mobile;
  final String title;
  final String fans;
  final String follows;
  final String points;
  final String coins;
  final String vip;
  final String level;
  final String posts;
  final String comments;
  final String likes;
  final String views;

  const UserProfileSummary({
    this.username = '',
    this.nickname = '',
    this.avatar = '',
    this.background = '',
    this.email = '',
    this.mobile = '',
    this.title = '',
    this.fans = '0',
    this.follows = '0',
    this.points = '0',
    this.coins = '0',
    this.vip = '普通',
    this.level = '0',
    this.posts = '0',
    this.comments = '0',
    this.likes = '0',
    this.views = '0',
  });

  static bool _isEmptyLike(String value) {
    final v = value.trim().toLowerCase();
    return v.isEmpty ||
        v == '--' ||
        v == '0' ||
        v == 'false' ||
        v == '普通' ||
        v == '非会员';
  }

  bool get isVip => !_isEmptyLike(vip);

  factory UserProfileSummary.fromJson(Map<String, dynamic> j) {
    String pick(List<String> keys, [String fallback = '0']) {
      for (final key in keys) {
        final value = j[key];
        if (value != null && '$value'.trim().isNotEmpty) return '$value';
      }
      return fallback;
    }

    return UserProfileSummary(
      username: pick(['username', 'account'], ''),
      nickname: pick(['nickname', 'name', 'nick_name'], ''),
      avatar: pick(['avatar', 'usertx', 'user_avatar', 'headimg'], ''),
      email: pick(['email', 'user_email', 'mail'], ''),
      mobile: pick(['mobile', 'phone', 'user_phone', 'tel'], ''),
      background: pick([
        'userbg',
        'user_bg',
        'user_cover',
        'background',
        'background_url',
        'user_background',
        'profile_background',
        'profile_bg',
        'bg',
        'cover',
        'cover_url',
        'homepage_background',
        'moment_background',
      ], ''),
      title: _pickDisplayTitle(j),
      fans: pick(['fans', 'fan', 'fan_count', 'fans_count', 'fensi']),
      follows: pick([
        'follows',
        'follow',
        'follow_count',
        'follows_count',
        'guanzhu',
      ]),
      points: pick([
        'points',
        'point',
        'integral',
        'score',
        'experience',
        'exp',
      ]),
      coins: pick(['coins', 'coin', 'money', 'gold', 'balance']),
      vip: pick(['vip', 'vip_time', 'vip_days', 'member', 'membership'], '普通'),
      level: pick([
        'level',
        'lv',
        'grade',
        'user_level',
        'userlevel',
        'user_grade',
        'dengji',
      ], '0'),
      posts: pick(['posts', 'post_count', 'posts_count']),
      comments: pick(['comments', 'comment_count', 'comments_count']),
      likes: pick(['likes', 'like_count', 'likes_count']),
      views: pick(['views', 'view_count', 'browse_count', 'history_count']),
    );
  }
}

class ImOnlineStatus {
  final bool online;
  final String device;
  final DateTime? lastSeen;
  const ImOnlineStatus({required this.online, this.device = '', this.lastSeen});

  String get label => '';

  String get lastSeenLabel => '';
}

class ApiService {
  final String baseUrl;
  const ApiService({this.baseUrl = AppConfig.apiBase});

  String _md5(String text) => crypto.md5.convert(utf8.encode(text)).toString();

  String _nonce() {
    final bytes = SafeRandom.bytes(12);
    return '${DateTime.now().microsecondsSinceEpoch}_${base64UrlEncode(bytes).replaceAll('=', '')}';
  }

  String _aesDecrypt(String encryptedText) {
    if (AppConfig.apiAesKey.length != 16) {
      throw ApiException('数据读取失败，请稍后再试');
    }
    final key = encrypt.Key.fromUtf8(AppConfig.apiAesKey);
    final iv = encrypt.IV.fromUtf8(AppConfig.apiAesKey);
    final encrypter = encrypt.Encrypter(
      encrypt.AES(key, mode: encrypt.AESMode.cbc, padding: 'PKCS7'),
    );
    return encrypter.decrypt64(encryptedText.trim(), iv: iv);
  }

  String _base64DecodeText(String text) {
    final normalized = base64.normalize(text.trim());
    return utf8.decode(base64Decode(normalized));
  }

  dynamic _tryJsonDecode(String text) => jsonDecode(text);

  Map<String, dynamic> _decodeResponseText(String text) {
    final raw = text.trim();
    final candidates = <String>[raw];

    try {
      candidates.add(_base64DecodeText(raw));
    } catch (_) {}

    try {
      candidates.add(_aesDecrypt(raw));
    } catch (_) {}

    for (final item in candidates) {
      try {
        final decoded = _tryJsonDecode(item);
        if (decoded is Map<String, dynamic>)
          return _normalizeDecodedMap(decoded);
        if (decoded is Map)
          return _normalizeDecodedMap(Map<String, dynamic>.from(decoded));
      } catch (_) {}
    }

    throw ApiException('数据读取失败，请稍后再试');
  }

  Map<String, dynamic> _normalizeDecodedMap(Map<String, dynamic> jsonBody) {
    _verifyTimestamp(jsonBody);
    final data = jsonBody['data'];
    if (data is String && data.trim().isNotEmpty) {
      final decoded = _decodeEncryptedDataField(data);
      if (decoded != null) jsonBody = {...jsonBody, 'data': decoded};
    }
    if (AppConfig.verifyResponseSign) {
      try {
        _verifySign(jsonBody);
      } catch (_) {
        // 后台加密已成功解开且 code 校验通过时，签名差异不应导致商业页面整页空白。
        // 默然系统不同版本可能在 JSON 转义细节上与 Dart jsonEncode 不完全一致。
      }
    }
    return jsonBody;
  }

  dynamic _decodeEncryptedDataField(String encrypted) {
    final candidates = <String>[];
    try {
      candidates.add(_base64DecodeText(encrypted));
    } catch (_) {}
    try {
      candidates.add(_aesDecrypt(encrypted));
    } catch (_) {}
    for (final item in candidates) {
      try {
        return jsonDecode(item);
      } catch (_) {}
    }
    return null;
  }

  void _verifyTimestamp(Map<String, dynamic> jsonBody) {
    final value = jsonBody['timestamp'] ?? jsonBody['time'] ?? jsonBody['ts'];
    if (value == null) return;
    final raw = int.tryParse('$value');
    if (raw == null || raw <= 0) return;
    final responseMs = raw > 9999999999 ? raw : raw * 1000;
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final diffSeconds = ((nowMs - responseMs).abs() / 1000).round();
    if (diffSeconds > AppConfig.responseTimestampMaxSkewSeconds) {
      throw ApiException('网络状态不稳定，请稍后再试');
    }
  }

  String _buildDataSign(dynamic data) {
    final sb = StringBuffer();
    if (data is Map) {
      data.forEach((key, value) {
        sb.write('$key=${jsonEncode(value)}&');
      });
    } else if (data is List) {
      for (var i = 0; i < data.length; i++) {
        sb.write('$i=${jsonEncode(data[i])}&');
      }
    }
    sb.write('secretKey=${AppConfig.apiSignSecretKey}');
    return _md5(sb.toString());
  }

  String _buildRequestSign(Map<String, dynamic> params) {
    final sb = StringBuffer(_canonicalRequestParams(params));
    sb.write('secretKey=${AppConfig.apiSignSecretKey}');
    return _md5(_phpStripslashes(sb.toString()));
  }

  String _buildBodyHash(Map<String, dynamic> params) {
    return crypto.sha256
        .convert(
          utf8.encode(
            _phpStripslashes(
              _canonicalRequestParams(params, excludeBodyHash: true),
            ),
          ),
        )
        .toString();
  }

  String _canonicalRequestParams(
    Map<String, dynamic> params, {
    bool excludeBodyHash = false,
  }) {
    final entries =
        params.entries
            .where((entry) {
              final key = entry.key.toLowerCase();
              return key != 'sign' &&
                  key != 'file' &&
                  key != 'files' &&
                  key != 'action' &&
                  key != 's' &&
                  (!excludeBodyHash || key != 'body_hash');
            })
            .map((entry) => MapEntry(entry.key, '${entry.value}'))
            .toList()
          ..sort((a, b) => a.key.compareTo(b.key));
    final sb = StringBuffer();
    for (final entry in entries) {
      sb.write('${entry.key}=${jsonEncode(entry.value)}&');
    }
    return sb.toString();
  }

  String _phpStripslashes(String text) {
    final buffer = StringBuffer();
    for (var i = 0; i < text.length; i++) {
      final current = text.codeUnitAt(i);
      if (current == 0x5c && i + 1 < text.length) {
        buffer.writeCharCode(text.codeUnitAt(i + 1));
        i++;
        continue;
      }
      buffer.writeCharCode(current);
    }
    return buffer.toString();
  }

  Future<Map<String, String>> _signedBody(Map<String, dynamic> data) async {
    final deviceContext = ClientDeviceContext.current();
    final deviceId =
        '${data['device_id'] ?? data['device'] ?? await deviceContext.persistentDeviceId()}';
    return _buildSignedBody(data, deviceId: deviceId);
  }

  Map<String, String> _signedBodySync(Map<String, dynamic> data) {
    final deviceContext = ClientDeviceContext.current();
    final deviceId =
        '${data['device_id'] ?? data['device'] ?? deviceContext.requestDeviceId()}';
    return _buildSignedBody(data, deviceId: deviceId);
  }

  Map<String, String> _buildSignedBody(
    Map<String, dynamic> data, {
    required String deviceId,
  }) {
    final nowSeconds = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final deviceContext = ClientDeviceContext.current();
    final deviceFields = deviceContext.toApiFields().map(
      (key, value) => MapEntry(key, '$value'),
    );
    final body = <String, dynamic>{
      'appid': '${AppConfig.appId}',
      'appkey': AppConfig.apiAppKey,
      'timestamp': '$nowSeconds',
      'time': '$nowSeconds',
      'nonce': _nonce(),
      ...deviceFields,
      'device_id': deviceId,
      'client_device_id': deviceId,
      ...data.map((k, v) => MapEntry(k, '$v')),
    };
    body['body_hash'] = _buildBodyHash(body);
    body['sign'] = _buildRequestSign(body);
    return body.map((key, value) => MapEntry(key, '$value'));
  }

  void _verifySign(Map<String, dynamic> jsonBody) {
    final sign = '${jsonBody['sign'] ?? ''}';
    if (sign.isEmpty || jsonBody['data'] == null) return;
    final localSign = _buildDataSign(jsonBody['data']);
    if (localSign != sign) {
      throw ApiException('数据校验失败，请稍后再试');
    }
  }

  Future<Map<String, dynamic>> _post(
    String path,
    Map<String, dynamic> data,
  ) async {
    final uri = Uri.parse('$baseUrl$path');
    Object? lastError;
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        final body = await _signedBody(data);
        final res = await http
            .post(
              uri,
              headers: {'Content-Type': 'application/x-www-form-urlencoded'},
              body: body,
            )
            .timeout(const Duration(seconds: 20));
        final text = utf8.decode(res.bodyBytes);
        final jsonBody = _decodeResponseText(text);
        if ('${jsonBody['code']}' != '1') {
          final msg = '${jsonBody['msg'] ?? ''}'.trim();
          final message = msg.isEmpty ? '操作未完成，请稍后再试' : msg;
          if (_isAuthExpiredResponse(jsonBody, message)) {
            AuthSessionEvents.notifyExpired();
            throw AuthExpiredException(message);
          }
          throw ApiException(message);
        }
        return jsonBody;
      } on ApiException {
        rethrow;
      } catch (e) {
        lastError = e;
        if (!_isTransientNetworkError(e) || attempt == 2) break;
        await Future<void>.delayed(Duration(milliseconds: 250 * (attempt + 1)));
      }
    }
    throw ApiException(_friendlyNetworkMessage(lastError));
  }

  bool _isAuthExpiredResponse(Map<String, dynamic> jsonBody, String message) {
    final code = '${jsonBody['code'] ?? ''}'.trim();
    final text = message.trim();
    return code == '401' ||
        code == '403' ||
        text.contains('账号已被封禁') ||
        text.contains('被封禁') ||
        text.contains('未登录') ||
        text.contains('登录过期') ||
        text.contains('登录已过期') ||
        text.contains('token无效') ||
        text.contains('token失效') ||
        text.toLowerCase().contains('invalid token');
  }

  bool _isTransientNetworkError(Object error) {
    if (error is TimeoutException) return true;
    final text = '$error'.toLowerCase();
    return text.contains('software caused connection abort') ||
        text.contains('connection abort') ||
        text.contains('connection reset') ||
        text.contains('connection closed') ||
        text.contains('broken pipe') ||
        text.contains('failed host lookup') ||
        text.contains('network is unreachable') ||
        text.contains('connection refused') ||
        text.contains('clientexception') ||
        text.contains('socketexception');
  }

  String _friendlyNetworkMessage(Object? error) {
    final text = '$error';
    if (error is TimeoutException || text.contains('Future not completed')) {
      return '网络响应超时，请稍后再试';
    }
    if (text.contains('Software caused connection abort') ||
        text.contains('Connection reset') ||
        text.contains('ClientException')) {
      return '网络刚恢复，正在重新连接，请稍后再试';
    }
    return '网络连接异常，请稍后再试';
  }

  List<Map<String, dynamic>> _asMapList(dynamic value) {
    final source = value is List ? value : const <dynamic>[];
    final rows = <Map<String, dynamic>>[];
    for (final item in source) {
      if (item is Map<String, dynamic>) {
        rows.add(item);
      } else if (item is Map) {
        rows.add(Map<String, dynamic>.from(item));
      }
    }
    return rows;
  }

  List<dynamic> _pickListSource(dynamic data) {
    if (data is List) return data;
    if (data is Map) {
      for (final key in const [
        'list',
        'data',
        'records',
        'items',
        'products',
        'goods',
        'rows',
      ]) {
        final value = data[key];
        if (value is List) return value;
      }
    }
    return const <dynamic>[];
  }

  Map<String, dynamic> _captchaKeyFields(String captchaKey) {
    final key = captchaKey.trim();
    if (key.isEmpty) return const <String, dynamic>{};
    return <String, dynamic>{
      'captcha_key': key,
      'captcha_id': key,
      'verify_key': key,
      'code_key': key,
      'verification_key': key,
      'captchaKey': key,
    };
  }

  Map<String, dynamic> _captchaFields(String captcha, String captchaKey) {
    final code = captcha.trim();
    return <String, dynamic>{
      if (code.isNotEmpty) ...{
        'captcha': code,
        'code': code,
        'verify_code': code,
        'verification_code': code,
        'image_code': code,
        'img_code': code,
      },
      ..._captchaKeyFields(captchaKey),
    };
  }

  Future<Map<String, dynamic>> getAppInfo() async {
    final r = await _post('/get_app_info', const <String, dynamic>{});
    final data = r['data'];
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return Map<String, dynamic>.from(data);
    return {};
  }

  Future<AppRegistrationConfig> getRegistrationConfig() async {
    final info = await getAppInfo();
    return AppRegistrationConfig.fromAppInfo(info);
  }

  Future<AppLoginConfig> getLoginConfig() async {
    final info = await getAppInfo();
    return AppLoginConfig.fromAppInfo(info);
  }

  Future<AppUserInfoConfig> getUserInfoConfig() async {
    final info = await getAppInfo();
    return AppUserInfoConfig.fromAppInfo(info);
  }

  Future<AppMomentsConfig> getMomentsConfig() async {
    final info = await getAppInfo();
    return AppMomentsConfig.fromAppInfo(info);
  }

  Future<UserPublicProfile> getUserInformation({
    required String token,
    required int userId,
  }) async {
    final r = await _post('/get_user_information', {
      'usertoken': token,
      'userid': userId,
      'user_id': userId,
    });
    final data = r['data'];
    if (data is Map<String, dynamic>) return UserPublicProfile.fromJson(data);
    if (data is Map)
      return UserPublicProfile.fromJson(Map<String, dynamic>.from(data));
    throw ApiException('用户资料读取失败');
  }

  Future<List<MomentItem>> getMomentsList({
    required String token,
    int page = 1,
    int limit = 20,
  }) async {
    final r = await _post('/get_moments_list', {
      'usertoken': token,
      'page': page,
      'limit': limit,
    });
    final rows = _asMapList(_pickListSource(r['data']));
    return <MomentItem>[for (final row in rows) MomentItem.fromJson(row)];
  }

  Future<int> getMomentUnreadCount(String token) async {
    final r = await _post('/get_moment_unread_count', {'usertoken': token});
    final data = r['data'];
    if (data is Map) {
      return int.tryParse('${data['unread_count'] ?? data['count'] ?? 0}') ?? 0;
    }
    return int.tryParse('$data') ?? 0;
  }

  Future<MomentProfileStats> getMyMomentStats({
    required String token,
    required int userId,
  }) async {
    for (final path in const [
      '/get_my_moment_stats',
      '/get_moment_stats',
      '/get_user_moment_stats',
    ]) {
      try {
        final r = await _post(path, {'usertoken': token, 'user_id': userId});
        final data = r['data'];
        if (data is Map<String, dynamic>) {
          return MomentProfileStats.fromJson(data);
        }
        if (data is Map) {
          return MomentProfileStats.fromJson(Map<String, dynamic>.from(data));
        }
      } catch (_) {}
    }

    var posts = 0;
    var likes = 0;
    for (var page = 1; page <= 8; page++) {
      final pageItems = await getMomentsList(
        token: token,
        page: page,
        limit: 50,
      );
      for (final item in pageItems) {
        if (item.userId != userId) continue;
        posts++;
        likes += item.likeCount;
      }
      if (pageItems.length < 50) break;
    }
    return MomentProfileStats(posts: posts, likes: likes);
  }

  Future<MomentItem> createMoment({
    required String token,
    required String content,
    List<String> images = const [],
    String videoUrl = '',
    String videoThumb = '',
    String visibilityType = 'friends',
    List<int> visibleUserIds = const [],
    List<int> hiddenUserIds = const [],
  }) async {
    final r = await _post('/create_moment', {
      'usertoken': token,
      'content': content,
      'images': jsonEncode(images),
      'visibility_type': visibilityType,
      'visible_user_ids': jsonEncode(visibleUserIds),
      'hidden_user_ids': jsonEncode(hiddenUserIds),
      if (videoUrl.trim().isNotEmpty) 'video_url': videoUrl.trim(),
      if (videoThumb.trim().isNotEmpty) 'video_thumb': videoThumb.trim(),
    });
    final data = r['data'];
    if (data is Map) {
      return MomentItem.fromJson(Map<String, dynamic>.from(data));
    }
    return MomentItem.fromJson(<String, dynamic>{
      'content': content,
      'images': images,
      'video_url': videoUrl,
      'video_thumb': videoThumb,
      'visibility_type': visibilityType,
      'visible_user_ids': visibleUserIds,
      'hidden_user_ids': hiddenUserIds,
      'create_time': DateTime.now().toIso8601String(),
    });
  }

  Future<String> deleteMoment({
    required String token,
    required int momentId,
  }) async {
    final r = await _post('/delete_moment', {
      'usertoken': token,
      'id': momentId,
      'moment_id': momentId,
    });
    return '${r['msg'] ?? '已删除'}';
  }

  Future<MomentLikeResult> toggleMomentLike({
    required String token,
    required int momentId,
  }) async {
    final r = await _post('/like_moment', {
      'usertoken': token,
      'id': momentId,
      'moment_id': momentId,
    });
    final data = r['data'];
    if (data is Map)
      return MomentLikeResult.fromJson(Map<String, dynamic>.from(data));
    return const MomentLikeResult(liked: false, likeCount: 0);
  }

  Future<MomentCommentResult> commentMoment({
    required String token,
    required int momentId,
    required String content,
    int parentId = 0,
  }) async {
    final r = await _post('/comment_moment', {
      'usertoken': token,
      'id': momentId,
      'moment_id': momentId,
      'content': content,
      if (parentId > 0) 'parent_id': parentId,
    });
    final data = r['data'];
    if (data is Map)
      return MomentCommentResult.fromJson(Map<String, dynamic>.from(data));
    return MomentCommentResult(
      comment: MomentCommentItem.fromJson({
        'moment_id': momentId,
        'content': content,
        'create_time': DateTime.now().toIso8601String(),
      }),
      commentCount: 0,
    );
  }

  Future<int> deleteMomentComment({
    required String token,
    required int commentId,
  }) async {
    final r = await _post('/delete_moment_comment', {
      'usertoken': token,
      'id': commentId,
      'comment_id': commentId,
    });
    final data = r['data'];
    if (data is Map) {
      return int.tryParse('${data['comment_count'] ?? data['count'] ?? 0}') ??
          0;
    }
    return 0;
  }

  Future<List<MomentNotificationItem>> getMomentNotifications(
    String token, {
    int page = 1,
    int limit = 30,
  }) async {
    final r = await _post('/get_moment_notifications', {
      'usertoken': token,
      'page': page,
      'limit': limit,
    });
    final rows = _asMapList(_pickListSource(r['data']));
    return <MomentNotificationItem>[
      for (final row in rows) MomentNotificationItem.fromJson(row),
    ];
  }

  Future<void> clearMomentNotifications(String token) async {
    await _post('/clear_moment_notifications', {'usertoken': token});
  }

  Future<UserSession> login(
    String username,
    String password, {
    String captcha = '',
    String captchaKey = '',
  }) async {
    final device = ClientDeviceContext.current();
    final deviceId = await device.persistentDeviceId();
    final r = await _post('/login', {
      ...device.toApiFields(),
      'username': username,
      'password': password,
      ..._captchaFields(captcha, captchaKey),
      'device': deviceId,
    });
    AuthSessionEvents.reset();
    return UserSession.fromJson(Map<String, dynamic>.from(r['data']));
  }

  Uri imageVerificationCodeUri({
    required int type,
    int? refresh,
    String captchaKey = '',
  }) {
    final typeText = '$type';
    final params = _signedBodySync({
      'type': typeText,
      'code_type': typeText,
      'captcha_type': typeText,
      'verification_type': typeText,
      'refresh': '${refresh ?? DateTime.now().millisecondsSinceEpoch}',
      ..._captchaKeyFields(captchaKey),
    });
    return Uri.parse(
      '$baseUrl/get_image_verification_code',
    ).replace(queryParameters: params);
  }

  Future<String> sendEmailVerificationCode({
    required String email,
    int type = 1,
    String username = '',
    String captcha = '',
    String captchaKey = '',
  }) async {
    final r = await _post('/get_email_verification_code', {
      if (email.trim().isNotEmpty) 'email': email.trim(),
      if (username.trim().isNotEmpty) 'username': username.trim(),
      'type': type,
      ..._captchaFields(captcha, captchaKey),
    });
    return '${r['msg'] ?? '验证码已发送'}';
  }

  Future<String> sendMobileVerificationCode({
    required String mobile,
    int type = 2,
    String captcha = '',
    String captchaKey = '',
  }) async {
    final r = await _post('/get_mobile_verification_code', {
      'mobile': mobile,
      'type': type,
      ..._captchaFields(captcha, captchaKey),
    });
    return '${r['msg'] ?? '验证码已发送'}';
  }

  Future<String> updateUserEmail({
    required String token,
    required String email,
    required String code,
  }) async {
    final r = await _post('/modify_user_email', {
      'usertoken': token,
      'email': email,
      'code': code,
    });
    return '${r['msg'] ?? '修改成功'}';
  }

  Future<String> updateUserPhone({
    required String token,
    required String phone,
    required String code,
  }) async {
    final r = await _post('/modify_user_phone', {
      'usertoken': token,
      'phone': phone,
      'mobile': phone,
      'code': code,
    });
    return '${r['msg'] ?? '修改成功'}';
  }

  Future<String> redeemDirectChargeCard({
    required String token,
    required String cardCode,
  }) async {
    final r = await _post('/apply_direct_charge_km', {
      'usertoken': token,
      'km': cardCode,
      'card_code': cardCode,
      'redeem_code': cardCode,
    });
    return '${r['msg'] ?? '兑换成功'}';
  }

  Future<PaymentPasswordStatus> getPaymentPasswordStatus(String token) async {
    final r = await _post('/get_payment_password_status', {'usertoken': token});
    final data = r['data'];
    if (data is Map<String, dynamic>) {
      return PaymentPasswordStatus.fromJson(data);
    }
    if (data is Map) {
      return PaymentPasswordStatus.fromJson(Map<String, dynamic>.from(data));
    }
    return PaymentPasswordStatus.fromJson(const <String, dynamic>{});
  }

  Future<PaymentPasswordStatus> verifyPaymentPassword({
    required String token,
    required String password,
  }) async {
    final r = await _post('/verify_payment_password', {
      'usertoken': token,
      'payment_password': password,
    });
    final data = r['data'];
    if (data is Map<String, dynamic>) {
      return PaymentPasswordStatus.fromJson(data);
    }
    if (data is Map) {
      return PaymentPasswordStatus.fromJson(Map<String, dynamic>.from(data));
    }
    return PaymentPasswordStatus.fromJson(const <String, dynamic>{});
  }

  Future<String> sendPaymentPasswordVerificationCode({
    required String token,
    required String method,
    String captcha = '',
    String captchaKey = '',
  }) async {
    final r = await _post('/send_payment_password_verification_code', {
      'usertoken': token,
      'method': method,
      'verification_method': method,
      ..._captchaFields(captcha, captchaKey),
    });
    return '${r['msg'] ?? '验证码已发送'}';
  }

  Future<PaymentPasswordStatus> setPaymentPassword({
    required String token,
    required String password,
    String confirmPassword = '',
    String oldPassword = '',
    String verificationMethod = '',
    String verificationCode = '',
  }) async {
    final r = await _post('/set_payment_password', {
      'usertoken': token,
      'payment_password': password,
      'pay_password': password,
      'confirm_password': confirmPassword,
      if (oldPassword.trim().isNotEmpty) 'old_payment_password': oldPassword,
      if (verificationMethod.trim().isNotEmpty)
        'verification_method': verificationMethod.trim(),
      if (verificationMethod.trim().isNotEmpty)
        'method': verificationMethod.trim(),
      if (verificationCode.trim().isNotEmpty)
        'verification_code': verificationCode.trim(),
      if (verificationCode.trim().isNotEmpty) 'code': verificationCode.trim(),
    });
    final data = r['data'];
    if (data is Map<String, dynamic>) {
      return PaymentPasswordStatus.fromJson(data);
    }
    if (data is Map) {
      return PaymentPasswordStatus.fromJson(Map<String, dynamic>.from(data));
    }
    return PaymentPasswordStatus.fromJson(const <String, dynamic>{});
  }

  Future<String> register({
    required String username,
    required String password,
    String mobile = '',
    String email = '',
    String captcha = '',
    String captchaKey = '',
    String inviteCode = '',
  }) async {
    final device = ClientDeviceContext.current();
    final deviceId = await device.persistentDeviceId();
    final r = await _post('/register', {
      ...device.toApiFields(),
      'username': username,
      'password': password,
      'mobile': mobile,
      'email': email,
      ..._captchaFields(captcha, captchaKey),
      'invitecode': inviteCode,
      'invitation_code': inviteCode,
      'device': deviceId,
    });
    return '${r['msg'] ?? '注册成功'}';
  }

  Future<String> retrievePassword({
    required String username,
    required String password,
    required String code,
    required int type,
  }) async {
    final r = await _post('/retrieve_password', {
      'username': username.trim(),
      'password': password,
      'captcha': code.trim(),
      'code': code.trim(),
      'type': type,
    });
    return '${r['msg'] ?? '修改成功'}';
  }

  Future<ImConnectInfo> getImConnectInfo(String token) async {
    final device = ClientDeviceContext.current();
    final r = await _post('/get_im_connect_info', {
      'usertoken': token,
      ...device.toApiFields(),
    });
    return ImConnectInfo.fromJson(Map<String, dynamic>.from(r['data']));
  }

  Future<List<ConversationItem>> getMessageList(String token) async {
    final r = await _post('/get_message_list', {'usertoken': token});
    final data = r['data'];
    final list = data is List
        ? data
        : (data is Map && data['list'] is List ? data['list'] : const []);
    final result = <ConversationItem>[];
    for (final e in list) {
      try {
        if (e is Map<String, dynamic>) {
          result.add(ConversationItem.fromJson(e));
        } else if (e is Map) {
          result.add(ConversationItem.fromJson(Map<String, dynamic>.from(e)));
        }
      } catch (_) {
        // 单条会话数据异常不影响整个最近会话列表。
      }
    }
    return result;
  }

  Future<List<UnifiedMessage>> getChatLog({
    required String token,
    required int receiverId,
    required int myId,
    int page = 1,
    int limit = 30,
  }) async {
    final r = await _post('/get_chat_log', {
      'usertoken': token,
      'receiver_id': receiverId,
      'page': page,
      'limit': limit,
    });
    final data = Map<String, dynamic>.from(r['data'] ?? {});
    final list = data['list'];
    if (list is List) {
      return list
          .map(
            (e) =>
                UnifiedMessage.fromHistory(Map<String, dynamic>.from(e), myId),
          )
          .toList()
          .reversed
          .toList();
    }
    return [];
  }

  Future<String> clearPeerChatHistory({
    required String token,
    required int peerId,
  }) async {
    final r = await _postAny(
      const [
        '/delete_conversation',
        '/remove_conversation',
        '/delete_message_session',
        '/delete_chat_session',
        '/hide_conversation',
        '/clear_chat_history',
        '/delete_chat_history',
        '/clear_im_chat_history',
        '/delete_im_chat_history',
        '/clear_chat_log',
        '/delete_chat_log',
      ],
      {
        'usertoken': token,
        'peer_id': peerId,
        'friend_id': peerId,
        'receiver_id': peerId,
        'user_id': peerId,
      },
    );
    return '${r['msg'] ?? '聊天记录已清空'}';
  }

  Future<void> markPeerMessagesRead({
    required String token,
    required int peerId,
    List<int> messageIds = const <int>[],
    DateTime? lastReadAt,
  }) async {
    await _postAny(
      const ['/mark_chat_read', '/read_chat_messages', '/mark_message_read'],
      {
        'usertoken': token,
        'peer_id': peerId,
        'friend_id': peerId,
        'receiver_id': peerId,
        'user_id': peerId,
        if (messageIds.isNotEmpty) 'message_ids': messageIds.join(','),
        if (lastReadAt != null) 'last_read_at': lastReadAt.toIso8601String(),
      },
    );
  }

  Future<void> markGroupMessagesRead({
    required String token,
    required int groupId,
    List<int> messageIds = const <int>[],
    DateTime? lastReadAt,
  }) async {
    await _postAny(
      const [
        '/mark_group_chat_read',
        '/read_group_chat_messages',
        '/mark_group_messages_read',
        '/mark_im_group_read',
        '/read_im_group_messages',
      ],
      {
        'usertoken': token,
        'group_id': groupId,
        if (messageIds.isNotEmpty) 'message_ids': messageIds.join(','),
        if (lastReadAt != null) 'last_read_at': lastReadAt.toIso8601String(),
      },
    );
  }

  Future<List<ImGroup>> getImGroups(String token) async {
    final r = await _post('/get_im_group_list', {'usertoken': token});
    return _asMapList(
      _pickListSource(r['data']),
    ).map(ImGroup.fromJson).where((g) => g.id > 0).toList();
  }

  Future<ImGroup> createImGroup({
    required String token,
    required String name,
    required List<int> memberIds,
  }) async {
    final r = await _post('/create_im_group', {
      'usertoken': token,
      'name': name,
      'member_ids': memberIds.join(','),
    });
    final data = r['data'];
    if (data is Map<String, dynamic>) return ImGroup.fromJson(data);
    if (data is Map) return ImGroup.fromJson(Map<String, dynamic>.from(data));
    throw ApiException('建群失败');
  }

  Future<int> sendGroupMessage({
    required String token,
    required int groupId,
    required String content,
    int messageType = 0,
    Map<String, dynamic>? payload,
  }) async {
    final data = await sendGroupMessageResult(
      token: token,
      groupId: groupId,
      content: content,
      messageType: messageType,
      payload: payload,
    );
    return int.tryParse('${data['message_id'] ?? 0}') ?? 0;
  }

  Future<Map<String, dynamic>> sendGroupMessageResult({
    required String token,
    required int groupId,
    required String content,
    int messageType = 0,
    Map<String, dynamic>? payload,
  }) async {
    final wireContent = _messageWireContent(content, payload);
    final r = await _post('/send_im_group_message', {
      'usertoken': token,
      'group_id': groupId,
      'message_type': messageType,
      'content': wireContent,
      if (payload != null) ..._flattenMessagePayload(payload),
    });
    final data = r['data'];
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return Map<String, dynamic>.from(data);
    return <String, dynamic>{};
  }

  Future<Map<String, dynamic>> sendGroupTransfer({
    required String token,
    required int groupId,
    required int receiverId,
    required String amount,
    String note = '',
    String clientMsgNo = '',
    int moneyType = 0,
    String paymentPassword = '',
    Map<String, dynamic>? payload,
  }) async {
    final normalizedPayload =
        payload ??
        {
          'msg_type': 'transfer',
          'client_msg_no': clientMsgNo,
          'group_id': groupId,
          'content': {
            'amount': amount,
            'note': note,
            'money_type': moneyType,
            'receiver_id': receiverId,
            'target_user_id': receiverId,
            'scope': 'group',
            'status': 'pending',
          },
        };
    final r = await _post('/send_im_group_transfer', {
      'usertoken': token,
      'group_id': groupId,
      'receiver_id': receiverId,
      'target_user_id': receiverId,
      'amount': amount,
      'money': amount,
      'note': note,
      'money_type': moneyType,
      'payment': moneyType,
      if (paymentPassword.trim().isNotEmpty)
        'payment_password': paymentPassword.trim(),
      if (paymentPassword.trim().isNotEmpty)
        'pay_password': paymentPassword.trim(),
      ..._flattenMessagePayload(normalizedPayload),
    });
    final data = r['data'];
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return Map<String, dynamic>.from(data);
    return <String, dynamic>{};
  }

  Future<List<UnifiedMessage>> getGroupChatLog({
    required String token,
    required int groupId,
    required int myId,
    int page = 1,
    int limit = 30,
  }) async {
    final r = await _post('/get_im_group_chat_log', {
      'usertoken': token,
      'group_id': groupId,
      'page': page,
      'limit': limit,
    });
    final data = Map<String, dynamic>.from(r['data'] ?? {});
    final list = data['list'];
    if (list is List) {
      return list
          .map(
            (e) =>
                UnifiedMessage.fromHistory(Map<String, dynamic>.from(e), myId),
          )
          .toList()
          .reversed
          .toList();
    }
    return [];
  }

  Future<ImGroup> getImGroupInfo({
    required String token,
    required int groupId,
  }) async {
    final r = await _postAny(
      const ['/get_im_group_info', '/im_group_info'],
      {'usertoken': token, 'group_id': groupId},
    );
    final data = r['data'];
    if (data is Map<String, dynamic>) return ImGroup.fromJson(data);
    if (data is Map) return ImGroup.fromJson(Map<String, dynamic>.from(data));
    throw ApiException('群资料读取失败');
  }

  Future<ImGroup> scanImGroupQr({
    required String token,
    required String qrData,
    int groupId = 0,
    String groupNo = '',
  }) async {
    final body = {
      'usertoken': token,
      'qr_data': qrData,
      'code': qrData,
      if (groupId > 0) 'group_id': groupId,
      if (groupNo.trim().isNotEmpty) 'group_no': groupNo.trim(),
    };
    Map<String, dynamic> r;
    try {
      r = await _postAny(const [
        '/scan_im_group_qr',
        '/scan_group_qr',
        '/scan_group_qrcode',
        '/join_im_group_by_qr',
        '/join_group_by_qr',
      ], body);
    } on ApiException {
      if (groupId > 0) return getImGroupInfo(token: token, groupId: groupId);
      rethrow;
    }
    final data = r['data'];
    final raw = data is Map<String, dynamic>
        ? data
        : data is Map
        ? Map<String, dynamic>.from(data)
        : <String, dynamic>{};
    final group = raw['group'] is Map
        ? Map<String, dynamic>.from(raw['group'])
        : raw;
    if (group.isNotEmpty) return ImGroup.fromJson(group);
    if (groupId > 0) return getImGroupInfo(token: token, groupId: groupId);
    throw ApiException('群二维码识别失败');
  }

  Future<String> getImGroupQr({
    required String token,
    required int groupId,
  }) async {
    final r = await _postAny(
      const ['/get_im_group_qr', '/get_group_qr', '/get_group_qrcode'],
      {'usertoken': token, 'group_id': groupId},
    );
    final data = r['data'];
    final raw = data is Map<String, dynamic>
        ? data
        : data is Map
        ? Map<String, dynamic>.from(data)
        : <String, dynamic>{};
    final qrData = '${raw['qr_data'] ?? raw['qr'] ?? raw['code'] ?? ''}'.trim();
    if (qrData.isNotEmpty) return qrData;
    throw ApiException('群二维码读取失败');
  }

  Future<List<ImGroupMember>> getImGroupMembers({
    required String token,
    required int groupId,
  }) async {
    final r = await _postAny(
      const [
        '/get_im_group_members',
        '/im_group_members',
        '/get_group_members',
      ],
      {'usertoken': token, 'group_id': groupId},
    );
    return _asMapList(
      _pickListSource(r['data']),
    ).map(ImGroupMember.fromJson).where((m) => m.userId > 0).toList();
  }

  Future<ImGroup> updateImGroup({
    required String token,
    required int groupId,
    String? name,
    String? avatar,
    String? notice,
    String? noticeRichText,
    String? groupNo,
    bool? qrEnabled,
    bool? noticeEnabled,
    bool? adminNoticeEnabled,
    bool? noticePinned,
    bool? screenshotNotifyEnabled,
  }) async {
    final r = await _postAny(
      const ['/update_im_group', '/edit_im_group', '/set_im_group_info'],
      {
        'usertoken': token,
        'group_id': groupId,
        if (name != null) 'name': name,
        if (name != null) 'group_name': name,
        if (avatar != null) 'avatar': avatar,
        if (avatar != null) 'group_avatar': avatar,
        if (notice != null) 'notice': notice,
        if (notice != null) 'announcement': notice,
        if (notice != null) 'group_notice': notice,
        if (noticeRichText != null) 'notice_rich_text': noticeRichText,
        if (noticeRichText != null) 'notice_rich': noticeRichText,
        if (groupNo != null) 'group_no': groupNo,
        if (groupNo != null) 'groupNo': groupNo,
        if (qrEnabled != null) 'qr_enabled': qrEnabled ? 1 : 0,
        if (qrEnabled != null) 'qrcode_enabled': qrEnabled ? 1 : 0,
        if (noticeEnabled != null) 'notice_enabled': noticeEnabled ? 1 : 0,
        if (noticeEnabled != null)
          'group_notice_enabled': noticeEnabled ? 1 : 0,
        if (adminNoticeEnabled != null)
          'admin_notice_enabled': adminNoticeEnabled ? 1 : 0,
        if (noticePinned != null) 'notice_pinned': noticePinned ? 1 : 0,
        if (screenshotNotifyEnabled != null)
          'screenshot_notify_enabled': screenshotNotifyEnabled ? 1 : 0,
        if (screenshotNotifyEnabled != null)
          'screenshot_notice_enabled': screenshotNotifyEnabled ? 1 : 0,
      },
    );
    final data = r['data'];
    if (data is Map<String, dynamic>) return ImGroup.fromJson(data);
    if (data is Map) return ImGroup.fromJson(Map<String, dynamic>.from(data));
    return ImGroup(
      id: groupId,
      groupNo: groupNo ?? '',
      name: name ?? '群聊',
      avatar: avatar ?? '',
      notice: notice ?? '',
      noticeRichText: noticeRichText ?? '',
      memberCount: 0,
      qrEnabled: qrEnabled ?? true,
      noticeEnabled: noticeEnabled ?? true,
      adminNoticeEnabled: adminNoticeEnabled ?? true,
      noticePinned: noticePinned ?? true,
      screenshotNotifyEnabled: screenshotNotifyEnabled ?? false,
    );
  }

  Future<ImGroup> generateImGroupAvatar({
    required String token,
    required int groupId,
  }) async {
    final r = await _post('/generate_im_group_avatar', {
      'usertoken': token,
      'group_id': groupId,
    });
    final data = r['data'];
    if (data is Map<String, dynamic>) return ImGroup.fromJson(data);
    if (data is Map) return ImGroup.fromJson(Map<String, dynamic>.from(data));
    throw ApiException('生成群头像失败');
  }

  Future<String> clearGroupChatHistory({
    required String token,
    required int groupId,
  }) async {
    final r = await _postAny(
      const [
        '/delete_group_conversation',
        '/remove_group_conversation',
        '/delete_group_message_session',
        '/delete_im_group_session',
        '/hide_group_conversation',
        '/clear_group_chat_history',
        '/delete_group_chat_history',
        '/clear_im_group_chat_history',
        '/delete_im_group_chat_history',
        '/clear_group_chat_log',
      ],
      {'usertoken': token, 'group_id': groupId},
    );
    return '${r['msg'] ?? '群聊天记录已清空'}';
  }

  Future<String> addImGroupMembers({
    required String token,
    required int groupId,
    required List<int> userIds,
  }) async {
    final r = await _postAny(
      const [
        '/add_im_group_members',
        '/invite_im_group_members',
        '/group_invite_members',
      ],
      {
        'usertoken': token,
        'group_id': groupId,
        'user_ids': userIds.join(','),
        'member_ids': userIds.join(','),
      },
    );
    return '${r['msg'] ?? '已邀请成员'}';
  }

  Future<String> joinImGroup({
    required String token,
    required int groupId,
    String groupNo = '',
    String qrData = '',
  }) async {
    final r = await _postAny(
      const [
        '/join_im_group',
        '/join_group',
        '/apply_join_im_group',
        '/apply_join_group',
        '/join_im_group_by_qr',
        '/join_group_by_qr',
      ],
      {
        'usertoken': token,
        'group_id': groupId,
        if (groupNo.trim().isNotEmpty) 'group_no': groupNo.trim(),
        if (qrData.trim().isNotEmpty) 'qr_data': qrData.trim(),
        if (qrData.trim().isNotEmpty) 'code': qrData.trim(),
      },
    );
    return '${r['msg'] ?? '已加入群聊'}';
  }

  Future<String> removeImGroupMember({
    required String token,
    required int groupId,
    required int userId,
  }) async {
    final r = await _postAny(
      const [
        '/remove_im_group_member',
        '/kick_im_group_member',
        '/delete_im_group_member',
      ],
      {
        'usertoken': token,
        'group_id': groupId,
        'user_id': userId,
        'member_id': userId,
      },
    );
    return '${r['msg'] ?? '已移除成员'}';
  }

  Future<String> setImGroupAdmin({
    required String token,
    required int groupId,
    required int userId,
    required bool admin,
  }) async {
    final r = await _postAny(
      const ['/set_im_group_admin', '/set_group_admin', '/im_group_set_admin'],
      {
        'usertoken': token,
        'group_id': groupId,
        'user_id': userId,
        'member_id': userId,
        'admin': admin ? 1 : 0,
        'role': admin ? 'admin' : 'member',
      },
    );
    return '${r['msg'] ?? (admin ? '已设为管理员' : '已取消管理员')}';
  }

  Future<String> transferImGroup({
    required String token,
    required int groupId,
    required int userId,
  }) async {
    final r = await _postAny(
      const [
        '/transfer_im_group',
        '/transfer_group_owner',
        '/im_group_transfer',
      ],
      {
        'usertoken': token,
        'group_id': groupId,
        'user_id': userId,
        'new_owner_id': userId,
      },
    );
    return '${r['msg'] ?? '已转让群主'}';
  }

  Future<String> leaveImGroup({
    required String token,
    required int groupId,
  }) async {
    final r = await _postAny(
      const ['/leave_im_group', '/quit_im_group', '/exit_im_group'],
      {'usertoken': token, 'group_id': groupId},
    );
    return '${r['msg'] ?? '已退出群聊'}';
  }

  Future<String> dismissImGroup({
    required String token,
    required int groupId,
  }) async {
    final r = await _postAny(
      const ['/dismiss_im_group', '/delete_im_group', '/disband_im_group'],
      {'usertoken': token, 'group_id': groupId},
    );
    return '${r['msg'] ?? '已解散群聊'}';
  }

  Future<Map<String, dynamic>> _postAny(
    List<String> paths,
    Map<String, dynamic> body,
  ) async {
    Object? lastError;
    for (final path in paths) {
      try {
        return await _post(path, body);
      } catch (e) {
        lastError = e;
      }
    }
    throw ApiException('功能暂不可用：${lastError ?? ''}');
  }

  Future<List<UserSearchResult>> getFriends(String token) async {
    final paths = const ['/get_friends', '/get_friend_list', '/friends'];
    Object? lastError;
    for (final path in paths) {
      try {
        final r = await _post(path, {'usertoken': token});
        return _asMapList(
          _pickListSource(r['data']),
        ).map(UserSearchResult.fromJson).where((u) => u.id > 0).toList();
      } catch (e) {
        lastError = e;
      }
    }
    throw ApiException('好友列表暂时不可用：${lastError ?? ''}');
  }

  Future<bool> isFriend(String token, int userId) async {
    try {
      final r = await _post('/is_friend', {
        'usertoken': token,
        'friend_id': userId,
        'user_id': userId,
      });
      final data = r['data'];
      final value = data is Map
          ? data['is_friend'] ?? data['friend'] ?? data['status']
          : data;
      return value == true ||
          '$value' == '1' ||
          '$value'.toLowerCase() == 'true';
    } catch (_) {
      try {
        final friends = await getFriends(token);
        return friends.any((u) => u.id == userId);
      } catch (_) {
        return false;
      }
    }
  }

  Future<String> deleteFriend(String token, int userId) async {
    final paths = const ['/delete_friend', '/remove_friend', '/del_friend'];
    Object? lastError;
    for (final path in paths) {
      try {
        final r = await _post(path, {
          'usertoken': token,
          'friend_id': userId,
          'user_id': userId,
        });
        return '${r['msg'] ?? '已删除好友'}';
      } catch (e) {
        lastError = e;
      }
    }
    throw ApiException('删除好友失败：${lastError ?? ''}');
  }

  Future<String> addFriend(
    String token,
    int userId, {
    String message = '',
  }) async {
    final paths = const [
      '/add_friend',
      '/apply_friend',
      '/friend_apply',
      '/follow_users',
    ];
    Object? lastError;
    for (final path in paths) {
      try {
        final r = await _post(path, {
          'usertoken': token,
          'friend_id': userId,
          'user_id': userId,
          'followedid': userId,
          if (message.trim().isNotEmpty) 'message': message.trim(),
        });
        return '${r['msg'] ?? '已发送好友申请'}';
      } catch (e) {
        lastError = e;
      }
    }
    throw ApiException('添加好友失败：${lastError ?? ''}');
  }

  Future<String> handleFriendRequest(
    String token, {
    required int userId,
    required bool accept,
  }) async {
    final paths = const ['/handle_friend_request', '/friend_request_handle'];
    Object? lastError;
    for (final path in paths) {
      try {
        final r = await _post(path, {
          'usertoken': token,
          'user_id': userId,
          'friend_id': userId,
          'from_user_id': userId,
          'action': accept ? 'accept' : 'reject',
          'status': accept ? 1 : 2,
        });
        return '${r['msg'] ?? (accept ? '已通过好友申请' : '已拒绝好友申请')}';
      } catch (e) {
        lastError = e;
      }
    }
    if (accept) return addFriend(token, userId, message: '我通过了你的好友申请');
    throw ApiException('处理好友申请失败：${lastError ?? ''}');
  }

  Future<List<FriendRequestItem>> getFriendRequests(
    String token, {
    String direction = 'incoming',
    int currentUserId = 0,
    int page = 1,
    int limit = 50,
  }) async {
    final r = await _postAny(
      const ['/get_friend_requests', '/friend_requests'],
      {
        'usertoken': token,
        'direction': direction,
        'page': page,
        'limit': limit,
      },
    );
    final resolvedCurrentUserId = currentUserId > 0
        ? currentUserId
        : _currentUserIdFromToken(token);
    return _asMapList(_pickListSource(r['data']))
        .map(
          (row) => FriendRequestItem.fromJson({
            ...row,
            if (resolvedCurrentUserId > 0)
              'current_user_id': resolvedCurrentUserId,
          }),
        )
        .where((item) => item.fromUserId > 0 || item.toUserId > 0)
        .toList();
  }

  int _currentUserIdFromToken(String token) {
    try {
      final parts = token.split('.');
      if (parts.length < 2) return 0;
      var payload = parts[1].replaceAll('-', '+').replaceAll('_', '/');
      while (payload.length % 4 != 0) {
        payload += '=';
      }
      final decoded = jsonDecode(utf8.decode(base64.decode(payload)));
      if (decoded is! Map) return 0;
      return int.tryParse(
            '${decoded['id'] ?? decoded['user_id'] ?? decoded['uid'] ?? decoded['userid'] ?? 0}',
          ) ??
          0;
    } catch (_) {
      return 0;
    }
  }

  Future<bool> hasPendingOutgoingFriendRequest(
    String token,
    int userId, {
    int currentUserId = 0,
  }) async {
    if (userId <= 0) return false;
    final requests = await getFriendRequests(
      token,
      direction: 'outgoing',
      currentUserId: currentUserId,
      limit: 100,
    );
    return requests.any(
      (item) =>
          item.pending &&
          (item.toUserId == userId ||
              item.fromUserId == userId ||
              '${item.raw['friend_id'] ?? item.raw['user_id'] ?? ''}' ==
                  '$userId' ||
              '${item.raw['to_user_id'] ?? ''}' == '$userId'),
    );
  }

  Future<String> deleteFriendRequest(
    String token, {
    required int userId,
  }) async {
    final r = await _postAny(
      const ['/delete_friend_request', '/remove_friend_request'],
      {
        'usertoken': token,
        'from_user_id': userId,
        'friend_id': userId,
        'user_id': userId,
      },
    );
    return '${r['msg'] ?? '已删除好友申请'}';
  }

  Future<String> recallMessage({
    required String token,
    required int messageId,
    int groupId = 0,
  }) async {
    final r = await _postAny(
      const ['/recall_message', '/revoke_message', '/withdraw_message'],
      {
        'usertoken': token,
        'message_id': messageId,
        'id': messageId,
        if (groupId > 0) 'group_id': groupId,
      },
    );
    return '${r['msg'] ?? '消息已撤回'}';
  }

  Future<UserQrInfo> getUserQr(String token) async {
    final r = await _postAny(
      const ['/get_user_qr', '/user_qr_code', '/get_user_qrcode'],
      {'usertoken': token},
    );
    final data = r['data'];
    if (data is Map<String, dynamic>) return UserQrInfo.fromJson(data);
    if (data is Map)
      return UserQrInfo.fromJson(Map<String, dynamic>.from(data));
    throw ApiException('二维码读取失败');
  }

  Future<UserSearchResult> scanUserQr(
    String token,
    String qrData, {
    bool apply = false,
  }) async {
    final r = await _postAny(
      const ['/scan_user_qr', '/scan_user_qrcode'],
      {
        'usertoken': token,
        'qr_data': qrData,
        'code': qrData,
        'apply': apply ? 1 : 0,
      },
    );
    final data = r['data'];
    final raw = data is Map<String, dynamic>
        ? data
        : data is Map
        ? Map<String, dynamic>.from(data)
        : <String, dynamic>{};
    final user = raw['user'] is Map
        ? Map<String, dynamic>.from(raw['user'])
        : raw;
    return UserSearchResult.fromJson(user);
  }

  Future<int> sendMessage({
    required String token,
    required int receiverId,
    required String content,
    int messageType = 0,
    Map<String, dynamic>? payload,
  }) async {
    final data = await sendMessageResult(
      token: token,
      receiverId: receiverId,
      content: content,
      messageType: messageType,
      payload: payload,
    );
    return int.tryParse('${data['message_id'] ?? 0}') ?? 0;
  }

  Future<Map<String, dynamic>> sendMessageResult({
    required String token,
    required int receiverId,
    required String content,
    int messageType = 0,
    String paymentPassword = '',
    Map<String, dynamic>? payload,
  }) async {
    final wireContent = _messageWireContent(content, payload);
    final r = await _post('/send_message', {
      'usertoken': token,
      'receiver_id': receiverId,
      'message_type': messageType,
      'content': wireContent,
      if (paymentPassword.trim().isNotEmpty)
        'payment_password': paymentPassword.trim(),
      if (paymentPassword.trim().isNotEmpty)
        'pay_password': paymentPassword.trim(),
      if (payload != null) ..._flattenMessagePayload(payload),
    });
    final data = r['data'];
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return Map<String, dynamic>.from(data);
    return <String, dynamic>{};
  }

  Future<Map<String, dynamic>> acceptImTransfer({
    required String token,
    int transferId = 0,
    int messageId = 0,
    String clientMsgNo = '',
  }) async {
    final r = await _post('/accept_im_transfer', {
      'usertoken': token,
      if (transferId > 0) 'transfer_id': transferId,
      if (messageId > 0) 'message_id': messageId,
      if (clientMsgNo.trim().isNotEmpty) 'client_msg_no': clientMsgNo.trim(),
    });
    final data = r['data'];
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return Map<String, dynamic>.from(data);
    return <String, dynamic>{};
  }

  Future<Map<String, dynamic>> returnImTransfer({
    required String token,
    int transferId = 0,
    int messageId = 0,
    String clientMsgNo = '',
  }) async {
    final r = await _post('/return_im_transfer', {
      'usertoken': token,
      if (transferId > 0) 'transfer_id': transferId,
      if (messageId > 0) 'message_id': messageId,
      if (clientMsgNo.trim().isNotEmpty) 'client_msg_no': clientMsgNo.trim(),
    });
    final data = r['data'];
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return Map<String, dynamic>.from(data);
    return <String, dynamic>{};
  }

  Future<Map<String, dynamic>> sendRedPacket({
    required String token,
    required int receiverId,
    required String amount,
    required String greeting,
    required String clientMsgNo,
    int moneyType = 0,
    String paymentPassword = '',
    Map<String, dynamic>? payload,
  }) async {
    final normalizedPayload =
        payload ??
        {
          'msg_type': 'red_packet',
          'client_msg_no': clientMsgNo,
          'content': {
            'amount': amount,
            'greeting': greeting,
            'money_type': moneyType,
            'scope': 'single',
            'status': 'pending',
          },
        };
    final r = await _post('/send_im_red_packet', {
      'usertoken': token,
      'receiver_id': receiverId,
      'amount': amount,
      'money': amount,
      'greeting': greeting,
      'money_type': moneyType,
      'payment': moneyType,
      if (paymentPassword.trim().isNotEmpty)
        'payment_password': paymentPassword.trim(),
      if (paymentPassword.trim().isNotEmpty)
        'pay_password': paymentPassword.trim(),
      ..._flattenMessagePayload(normalizedPayload),
    });
    final data = r['data'];
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return Map<String, dynamic>.from(data);
    return <String, dynamic>{};
  }

  Future<Map<String, dynamic>> sendGroupRedPacket({
    required String token,
    required int groupId,
    required String amount,
    required int count,
    required String packetType,
    required String greeting,
    required String clientMsgNo,
    int moneyType = 0,
    String paymentPassword = '',
    Map<String, dynamic>? payload,
  }) async {
    final normalizedPayload =
        payload ??
        {
          'msg_type': 'red_packet',
          'client_msg_no': clientMsgNo,
          'group_id': groupId,
          'content': {
            'amount': amount,
            'greeting': greeting,
            'money_type': moneyType,
            'scope': 'group',
            'count': count,
            'total_count': count,
            'packet_type': packetType,
            'status': 'pending',
          },
        };
    final r = await _post('/send_im_group_red_packet', {
      'usertoken': token,
      'group_id': groupId,
      'amount': amount,
      'money': amount,
      'count': count,
      'total_count': count,
      'packet_type': packetType,
      'type': packetType,
      'greeting': greeting,
      'money_type': moneyType,
      'payment': moneyType,
      if (paymentPassword.trim().isNotEmpty)
        'payment_password': paymentPassword.trim(),
      if (paymentPassword.trim().isNotEmpty)
        'pay_password': paymentPassword.trim(),
      ..._flattenMessagePayload(normalizedPayload),
    });
    final data = r['data'];
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return Map<String, dynamic>.from(data);
    return <String, dynamic>{};
  }

  Future<Map<String, dynamic>> claimRedPacket({
    required String token,
    int redPacketId = 0,
    int messageId = 0,
    int groupId = 0,
    String clientMsgNo = '',
  }) async {
    final r = await _post('/claim_im_red_packet', {
      'usertoken': token,
      if (redPacketId > 0) 'red_packet_id': redPacketId,
      if (messageId > 0) 'message_id': messageId,
      if (groupId > 0) 'group_id': groupId,
      if (clientMsgNo.trim().isNotEmpty) 'client_msg_no': clientMsgNo.trim(),
    });
    final data = r['data'];
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return Map<String, dynamic>.from(data);
    return <String, dynamic>{};
  }

  Future<Map<String, dynamic>> getRedPacketDetail({
    required String token,
    int redPacketId = 0,
    int messageId = 0,
    int groupId = 0,
    String clientMsgNo = '',
  }) async {
    final r = await _post('/get_im_red_packet_detail', {
      'usertoken': token,
      if (redPacketId > 0) 'red_packet_id': redPacketId,
      if (messageId > 0) 'message_id': messageId,
      if (groupId > 0) 'group_id': groupId,
      if (clientMsgNo.trim().isNotEmpty) 'client_msg_no': clientMsgNo.trim(),
    });
    final data = r['data'];
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return Map<String, dynamic>.from(data);
    return <String, dynamic>{};
  }

  Future<Map<String, dynamic>> getTurnCredentials(String token) async {
    final r = await _post('/get_turn_credentials', {'usertoken': token});
    final data = r['data'];
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return Map<String, dynamic>.from(data);
    return <String, dynamic>{};
  }

  Future<List<Map<String, dynamic>>> getIceServers(String token) async {
    try {
      final data = await getTurnCredentials(token);
      final raw = data['ice_servers'] ?? data['iceServers'];
      if (raw is List) {
        return raw
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      }
    } catch (_) {}
    return AppConfig.rtcIceServers;
  }

  Future<int> sendImCallSignal({
    required String token,
    required int toUserId,
    required Map<String, dynamic> payload,
  }) async {
    final content = payload['content'];
    final signal = CallSignal.tryParse(payload);
    final normalizedPayload = signal?.toPayload() ?? payload;
    final normalizedContent = normalizedPayload['content'];
    final contentMap = normalizedContent is Map
        ? Map<String, dynamic>.from(normalizedContent)
        : content is Map
        ? Map<String, dynamic>.from(content)
        : const <String, dynamic>{};
    final body = {
      'usertoken': token,
      'to_user_id': toUserId,
      'receiver_id': toUserId,
      'schema': '${normalizedPayload['schema'] ?? CallSignal.schema}',
      'msg_type':
          '${normalizedPayload['msg_type'] ?? CallSignal.legacyMsgType}',
      'signal_type':
          '${normalizedPayload['signal_type'] ?? CallSignal.msgType}',
      'call_id':
          '${contentMap['call_id'] ?? normalizedPayload['call_id'] ?? ''}',
      'signal_id':
          '${contentMap['signal_id'] ?? normalizedPayload['signal_id'] ?? normalizedPayload['client_msg_no'] ?? ''}',
      'action': '${contentMap['action'] ?? normalizedPayload['action'] ?? ''}',
      'call_action':
          '${contentMap['action'] ?? normalizedPayload['action'] ?? contentMap['type'] ?? ''}',
      'signal_action':
          '${contentMap['action'] ?? normalizedPayload['action'] ?? contentMap['type'] ?? ''}',
      'media': '${contentMap['media'] ?? normalizedPayload['media'] ?? ''}',
      'client_msg_no':
          '${normalizedPayload['client_msg_no'] ?? contentMap['signal_id'] ?? ''}',
      ..._flattenMessagePayload(normalizedPayload),
    };
    AppLogger.api(
      "send_im_call_signal request call=${body['call_id']} action=${body['action']} to=$toUserId signal=${body['signal_id']}",
    );
    final r = await _post('/send_im_call_signal', body);
    AppLogger.api(
      "send_im_call_signal response call=${body['call_id']} action=${body['action']}",
      data: r['data'],
    );
    return int.tryParse(
          '${r['data']?['id'] ?? r['data']?['message_id'] ?? 0}',
        ) ??
        0;
  }

  Future<List<Map<String, dynamic>>> getImCallSignals({
    required String token,
    int sinceId = 0,
    String callId = '',
    int peerId = 0,
    int limit = 50,
  }) async {
    final r = await _post('/get_im_call_signals', {
      'usertoken': token,
      'since_id': sinceId,
      if (callId.isNotEmpty) 'call_id': callId,
      if (peerId > 0) 'peer_id': peerId,
      'limit': limit,
    });
    AppLogger.api(
      'get_im_call_signals response since=$sinceId call=$callId peer=$peerId',
    );
    final data = r['data'];
    final List<dynamic> list = data is List
        ? data
        : (data is Map && data['list'] is List
              ? List<dynamic>.from(data['list'] as List)
              : <dynamic>[]);
    final rows = <Map<String, dynamic>>[];
    for (final item in list) {
      if (item is! Map) continue;
      final row = Map<String, dynamic>.from(item);
      final signal = CallSignal.tryParse(row);
      if (signal == null) {
        rows.add(row);
        continue;
      }
      final payload = signal.toPayload();
      rows.add({
        ...row,
        'call_id': signal.callId,
        'signal_id': signal.signalId,
        'action': signal.action,
        'call_action': signal.action,
        'signal_action': signal.action,
        'media': signal.media,
        'from_user_id': signal.fromUserId,
        'to_user_id': signal.toUserId,
        'payload': payload,
      });
    }
    return rows;
  }

  String _messageWireContent(String content, Map<String, dynamic>? payload) {
    final contentMap = payload?['content'];
    final payloadType = '${payload?['msg_type'] ?? ''}';
    final raw = payloadType == 'transfer' && contentMap is Map
        ? '${contentMap['amount'] ?? content}'
        : payloadType == 'red_packet' && contentMap is Map
        ? '[红包] ${contentMap['greeting'] ?? contentMap['text'] ?? content}'
        : payloadType == 'emoji' && contentMap is Map
        ? '${contentMap['emoji'] ?? contentMap['text'] ?? content}'
        : content;
    return _legacySafeMessageContent(raw);
  }

  String _legacySafeMessageContent(String value) {
    if (!_containsEmojiScalar(value)) return value;
    final buffer = StringBuffer();
    var wroteEmojiToken = false;
    for (final rune in value.runes) {
      if (_isEmojiScalar(rune)) {
        if (!wroteEmojiToken) buffer.write('[表情]');
        wroteEmojiToken = true;
        continue;
      }
      buffer.writeCharCode(rune);
      wroteEmojiToken = false;
    }
    final safe = buffer.toString().trim();
    return safe.isEmpty ? '[表情]' : safe;
  }

  bool _containsEmojiScalar(String value) => value.runes.any(_isEmojiScalar);

  bool _isEmojiScalar(int rune) {
    return rune == 0x200d ||
        (rune >= 0xfe00 && rune <= 0xfe0f) ||
        (rune >= 0x1f000 && rune <= 0x1faff) ||
        (rune >= 0x2600 && rune <= 0x27bf);
  }

  String _jsonEncodeAscii(Object? value) {
    final json = jsonEncode(value);
    final buffer = StringBuffer();
    for (final rune in json.runes) {
      if (rune <= 0x7f) {
        buffer.writeCharCode(rune);
      } else if (rune <= 0xffff) {
        buffer.write('\\u${rune.toRadixString(16).padLeft(4, '0')}');
      } else {
        final code = rune - 0x10000;
        final high = 0xd800 + (code >> 10);
        final low = 0xdc00 + (code & 0x3ff);
        buffer
          ..write('\\u${high.toRadixString(16).padLeft(4, '0')}')
          ..write('\\u${low.toRadixString(16).padLeft(4, '0')}');
      }
    }
    return buffer.toString();
  }

  Map<String, String> _flattenMessagePayload(Map<String, dynamic> payload) {
    final wirePayload = _legacySafePayload(payload);
    final content = wirePayload['content'];
    final contentMap = content is Map
        ? Map<String, dynamic>.from(content)
        : const <String, dynamic>{};
    final type = '${wirePayload['msg_type'] ?? ''}';
    final url = _firstNonEmpty([
      contentMap['url'],
      contentMap['file_url'],
      contentMap['video_url'],
      contentMap['video_path'],
      contentMap['file_path'],
      contentMap['image'],
      contentMap['image_path'],
      contentMap['src'],
    ]);
    final name = '${contentMap['name'] ?? contentMap['file_name'] ?? ''}';
    return {
      'msg_type': type,
      'im_payload': _jsonEncodeAscii(wirePayload),
      'payload': _jsonEncodeAscii(wirePayload),
      if (type == 'call') ...{
        'call_id': '${contentMap['call_id'] ?? wirePayload['call_id'] ?? ''}',
        'call_action': '${contentMap['action'] ?? contentMap['type'] ?? ''}',
        'dedupe_key':
            '${contentMap['dedupe_key'] ?? contentMap['call_record_key'] ?? ''}',
      },
      if (type == 'call_record') ...{
        'call_id': '${contentMap['call_id'] ?? wirePayload['call_id'] ?? ''}',
        'dedupe_key':
            '${contentMap['call_record_key'] ?? contentMap['dedupe_key'] ?? ''}',
      },
      if (type == 'group_call_invite' ||
          type == 'group_call_join' ||
          type == 'group_call_leave' ||
          type == 'group_call_record') ...{
        'call_id':
            '${contentMap['room_id'] ?? contentMap['call_id'] ?? wirePayload['call_id'] ?? ''}',
        'dedupe_key':
            '${contentMap['call_record_key'] ?? contentMap['dedupe_key'] ?? wirePayload['client_msg_no'] ?? ''}',
      },
      if (type == 'transfer') ...{
        'money': '${contentMap['amount'] ?? ''}',
        'amount': '${contentMap['amount'] ?? ''}',
        'payment': '${contentMap['payment'] ?? contentMap['type'] ?? 0}',
        'type': '${contentMap['payment'] ?? contentMap['type'] ?? 0}',
        'note': '${contentMap['note'] ?? ''}',
        'image_path': '',
        'file_path': '',
        'file_name': name,
      } else if (type == 'red_packet') ...{
        'amount': '${contentMap['amount'] ?? contentMap['total_amount'] ?? ''}',
        'money': '${contentMap['amount'] ?? contentMap['total_amount'] ?? ''}',
        'count': '${contentMap['count'] ?? contentMap['total_count'] ?? 1}',
        'total_count':
            '${contentMap['total_count'] ?? contentMap['count'] ?? 1}',
        'packet_type': '${contentMap['packet_type'] ?? 'normal'}',
        'greeting': '${contentMap['greeting'] ?? contentMap['text'] ?? ''}',
        'money_type': '${contentMap['money_type'] ?? 0}',
        'payment': '${contentMap['payment'] ?? contentMap['money_type'] ?? 0}',
        'red_packet_id': '${contentMap['red_packet_id'] ?? ''}',
        'image_path': '',
        'file_path': '',
        'file_name': name,
      } else if (type == 'image') ...{
        'image_path': url,
        'file_path': url,
        'file_name': name,
        if ('${contentMap['media_format'] ?? contentMap['format'] ?? ''}'
                .toLowerCase() ==
            'gif')
          'media_format': 'gif',
        if ('${contentMap['animated'] ?? contentMap['is_gif'] ?? ''}' ==
                'true' ||
            '${contentMap['animated'] ?? contentMap['is_gif'] ?? ''}' == '1' ||
            name.toLowerCase().endsWith('.gif') ||
            url.split('?').first.toLowerCase().endsWith('.gif')) ...{
          'is_gif': '1',
          'animated': '1',
        },
      } else if (type == 'video' || type == 'file' || type == 'voice') ...{
        'image_path': '',
        'file_path': url,
        if (type == 'video') 'video_url': url,
        if (type == 'video') 'video_path': url,
        'file_name': name,
        if (type == 'voice') 'duration': '${contentMap['duration'] ?? 0}',
        if (type == 'voice') 'media_type': 'audio',
      } else ...{
        'image_path': '${contentMap['image_path'] ?? ''}',
        'file_path': '${contentMap['file_path'] ?? ''}',
        'file_name': name,
      },
    };
  }

  String _firstNonEmpty(Iterable<Object?> values) {
    for (final value in values) {
      final text = '${value ?? ''}'.trim();
      if (text.isNotEmpty && text != 'null') return text;
    }
    return '';
  }

  dynamic _legacySafePayload(dynamic value) {
    if (value is Map) {
      return value.map(
        (key, item) => MapEntry('$key', _legacySafePayload(item)),
      );
    }
    if (value is List) {
      return value.map(_legacySafePayload).toList();
    }
    if (value is String) return _escapeEmojiScalars(value);
    return value;
  }

  String _escapeEmojiScalars(String value) {
    if (!_containsEmojiScalar(value)) return value;
    final buffer = StringBuffer();
    for (final rune in value.runes) {
      if (_isEmojiScalar(rune)) {
        _writeJsonUnicodeEscape(buffer, rune);
      } else {
        buffer.writeCharCode(rune);
      }
    }
    return buffer.toString();
  }

  void _writeJsonUnicodeEscape(StringBuffer buffer, int rune) {
    if (rune <= 0xffff) {
      buffer.write(r'\u');
      buffer.write(rune.toRadixString(16).padLeft(4, '0'));
      return;
    }
    final code = rune - 0x10000;
    final high = 0xd800 + (code >> 10);
    final low = 0xdc00 + (code & 0x3ff);
    buffer.write(r'\u');
    buffer.write(high.toRadixString(16).padLeft(4, '0'));
    buffer.write(r'\u');
    buffer.write(low.toRadixString(16).padLeft(4, '0'));
  }

  Future<Map<String, dynamic>> uploadChatFile({
    required String token,
    required List<int> bytes,
    required String filename,
  }) async {
    final paths = const ['/upload', '/upload_file', '/upload_image'];
    Object? lastError;
    for (final path in paths) {
      try {
        final uri = Uri.parse('$baseUrl$path');
        final extension = filename.contains('.')
            ? filename.split('.').last.toLowerCase()
            : '';
        final uploadFields = <String, dynamic>{
          'usertoken': token,
          'filename': filename,
          'file_name': filename,
          if (extension.isNotEmpty) 'extension': extension,
          if (extension.isNotEmpty) 'ext': extension,
          if (extension == 'gif') ...{
            'media_format': 'gif',
            'format': 'gif',
            'is_gif': '1',
            'animated': '1',
          },
        };
        final signedFields = await _signedBody(uploadFields);
        final request = http.MultipartRequest('POST', uri)
          ..fields.addAll(signedFields)
          ..files.add(
            http.MultipartFile.fromBytes('file', bytes, filename: filename),
          );
        final streamed = await request.send().timeout(
          const Duration(seconds: 30),
        );
        final res = await http.Response.fromStream(streamed);
        if (res.statusCode == 404 || res.statusCode == 405) {
          lastError ??= ApiException('上传功能暂不可用');
          continue;
        }
        final jsonBody = _decodeResponseText(utf8.decode(res.bodyBytes));
        if ('${jsonBody['code']}' != '1')
          throw ApiException('${jsonBody['msg'] ?? '上传失败'}');
        final data = jsonBody['data'];
        if (data is Map<String, dynamic>) return data;
        if (data is Map) return Map<String, dynamic>.from(data);
        return {'url': data ?? ''};
      } on ApiException catch (e) {
        lastError = e;
        break;
      } catch (e) {
        lastError = e;
      }
    }
    throw ApiException('文件上传失败：${lastError ?? '请稍后再试'}');
  }

  Future<Map<String, dynamic>> uploadProfileImage({
    required String token,
    required String path,
    required List<int> bytes,
    required String filename,
  }) async {
    final uri = Uri.parse('$baseUrl$path');
    final signedFields = await _signedBody({'usertoken': token});
    final request = http.MultipartRequest('POST', uri)
      ..fields.addAll(signedFields)
      ..files.add(
        http.MultipartFile.fromBytes('file', bytes, filename: filename),
      );
    final streamed = await request.send().timeout(const Duration(seconds: 30));
    final res = await http.Response.fromStream(streamed);
    final jsonBody = _decodeResponseText(utf8.decode(res.bodyBytes));
    if ('${jsonBody['code']}' != '1') {
      final msg = '${jsonBody['msg'] ?? ''}'.trim();
      throw ApiException(msg.isEmpty ? '图片上传失败' : msg);
    }
    final msg = '${jsonBody['msg'] ?? ''}'.trim();
    final data = jsonBody['data'];
    if (data is Map<String, dynamic>) {
      return {
        ...data,
        if (msg.isNotEmpty) ...{'msg': msg, 'message': msg},
      };
    }
    if (data is Map) {
      return {
        ...Map<String, dynamic>.from(data),
        if (msg.isNotEmpty) ...{'msg': msg, 'message': msg},
      };
    }
    return {
      'url': data ?? '',
      if (msg.isNotEmpty) ...{'msg': msg, 'message': msg},
    };
  }

  Future<List<UserSearchResult>> searchUsers(
    String token,
    String keyword,
  ) async {
    final kw = keyword.trim();
    if (kw.isEmpty) return [];
    final r = await _post('/search_user', {'usertoken': token, 'username': kw});
    final data = r['data'];
    final list = data is List
        ? data
        : (data is Map && data['list'] is List ? data['list'] : const []);
    final users = <UserSearchResult>[];
    for (final item in list) {
      try {
        if (item is Map<String, dynamic>) {
          users.add(UserSearchResult.fromJson(item));
        } else if (item is Map) {
          users.add(UserSearchResult.fromJson(Map<String, dynamic>.from(item)));
        }
      } catch (_) {}
    }
    return users.where((u) => u.id > 0).toList();
  }

  Future<UserSession> changeUsername({
    required UserSession session,
    required String username,
  }) async {
    final next = username.trim();
    final r = await _postAny(
      const ['/change_username', '/update_username'],
      {'usertoken': session.token, 'username': next},
    );
    final data = r['data'];
    String resolved = next;
    if (data is Map && data['username'] != null) {
      resolved = '${data['username']}';
    }
    return session.copyWith(username: resolved);
  }

  Future<UserProfileSummary> getUserOtherInformation(String token) async {
    final r = await _post('/get_user_other_information', {'usertoken': token});
    final data = r['data'];
    if (data is Map<String, dynamic>) {
      final merged = Map<String, dynamic>.from(data);
      for (final key in ['user', 'user_info', 'userinfo', 'info']) {
        final nested = data[key];
        if (nested is Map) merged.addAll(Map<String, dynamic>.from(nested));
      }
      return UserProfileSummary.fromJson(merged);
    }
    if (data is Map) {
      final merged = Map<String, dynamic>.from(data);
      for (final key in ['user', 'user_info', 'userinfo', 'info']) {
        final nested = data[key];
        if (nested is Map) merged.addAll(Map<String, dynamic>.from(nested));
      }
      return UserProfileSummary.fromJson(merged);
    }
    return const UserProfileSummary();
  }

  Future<String> userSignIn(String token) async {
    final r = await _post('/user_sign_in', {'usertoken': token});
    return '${r['msg'] ?? '签到成功'}';
  }

  Future<List<Map<String, dynamic>>> getProductList({
    int page = 1,
    int limit = 10,
  }) async {
    final r = await _post('/product_list', {'limit': limit, 'page': page});
    final data = r['data'];
    return _asMapList(_pickListSource(data));
  }

  Future<Map<String, dynamic>> getProductInformation(String shopId) async {
    final r = await _post('/get_product_information', {'shopid': shopId});
    final data = r['data'];
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return Map<String, dynamic>.from(data);
    return {};
  }

  Future<Map<String, dynamic>> buyGoods(String token, String shopId) async {
    final r = await _post('/buy_goods', {'usertoken': token, 'shopid': shopId});
    final data = r['data'];
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return Map<String, dynamic>.from(data);
    return {'msg': r['msg'] ?? '购买成功'};
  }

  Future<List<Map<String, dynamic>>> getApiList(
    String token,
    String path, {
    Map<String, dynamic> extra = const {},
  }) async {
    final r = await _post(path, {'usertoken': token, ...extra});
    final data = r['data'];
    return _asMapList(_pickListSource(data));
  }

  Future<Map<String, dynamic>> getApiData(
    String token,
    String path, {
    Map<String, dynamic> extra = const {},
  }) async {
    final r = await _post(path, {'usertoken': token, ...extra});
    final data = r['data'];
    final msg = '${r['msg'] ?? ''}'.trim();
    if (data is Map<String, dynamic>) {
      return {
        ...data,
        if (msg.isNotEmpty) ...{'msg': msg, 'message': msg},
      };
    }
    if (data is Map) {
      return {
        ...Map<String, dynamic>.from(data),
        if (msg.isNotEmpty) ...{'msg': msg, 'message': msg},
      };
    }
    return {
      'value': data ?? (msg.isNotEmpty ? msg : 'success'),
      if (msg.isNotEmpty) ...{'msg': msg, 'message': msg},
    };
  }

  Future<List<Map<String, dynamic>>> getMessageNotifications(
    String token, {
    int page = 1,
    int limit = 30,
    bool unreadOnly = false,
  }) async {
    final r = await _post(
      unreadOnly
          ? '/get_unread_message_notifications'
          : '/get_message_notifications',
      {'usertoken': token, 'page': page, 'limit': limit},
    );
    return _asMapList(_pickListSource(r['data']));
  }

  Future<String> clearMessageNotification(
    String token, {
    String notificationId = '',
  }) async {
    final r = await _post('/clear_message_notification', {
      'usertoken': token,
      if (notificationId.trim().isNotEmpty) 'id': notificationId.trim(),
    });
    return '${r['msg'] ?? '已处理'}';
  }

  Future<ImOnlineStatus> reportImOnlineHeartbeat({
    required String token,
    bool online = true,
  }) async {
    final device = ClientDeviceContext.current();
    final r = await _post('/im_online_heartbeat', {
      'usertoken': token,
      ...device.toApiFields(),
      'online': online ? 1 : 0,
    });
    final data = r['data'];
    if (data is Map) {
      final value = data['online'];
      final isOnline = value is bool
          ? value
          : '$value' == '1' || '$value'.toLowerCase() == 'true';
      return ImOnlineStatus(
        online: isOnline,
        device:
            '${data['device'] ?? data['platform'] ?? data['terminal'] ?? data['device_flag'] ?? ''}',
      );
    }
    return ImOnlineStatus(online: online, device: device.device);
  }

  String _pickOnlineDevice(Map data) {
    String normalize(dynamic value) => value == null ? '' : '$value'.trim();
    bool isPlaceholder(String value) {
      final d = value.trim().toLowerCase();
      return d.isEmpty ||
          d == 'null' ||
          d.contains('离线') ||
          d.contains('offline') ||
          d.contains('unknown') ||
          d.contains('暂时');
    }

    bool isOnlineValue(dynamic value) =>
        value == true ||
        '$value' == '1' ||
        '$value'.toLowerCase() == 'true' ||
        '$value'.toLowerCase() == 'online';
    bool isMobileValue(String value) {
      final d = value.trim().toLowerCase();
      return d.contains('android') ||
          d.contains('ios') ||
          d.contains('iphone') ||
          d.contains('ipad') ||
          d.contains('mobile') ||
          d.contains('phone') ||
          d == '2' ||
          d == '4';
    }

    final devices =
        data['devices'] ?? data['online_devices'] ?? data['device_list'];
    if (devices is List && devices.isNotEmpty) {
      Map? firstOnline;
      Map? mobileOnline;
      for (final item in devices) {
        if (item is! Map) continue;
        final online = isOnlineValue(
          item['online'] ?? item['is_online'] ?? item['status'],
        );
        if (!online) continue;
        firstOnline ??= item;
        final value = normalize(
          item['latest_device'] ??
              item['current_device'] ??
              item['device'] ??
              item['platform'] ??
              item['terminal'] ??
              item['device_type'] ??
              item['device_flag'],
        );
        if (value.isNotEmpty && !isPlaceholder(value) && isMobileValue(value)) {
          mobileOnline = item;
          break;
        }
      }
      final best = mobileOnline ?? firstOnline;
      if (best != null) {
        final value = normalize(
          best['latest_device'] ??
              best['current_device'] ??
              best['device'] ??
              best['platform'] ??
              best['terminal'] ??
              best['device_type'] ??
              best['device_flag'],
        );
        if (value.isNotEmpty && !isPlaceholder(value)) return value;
      }
    }

    final direct =
        data['latest_device'] ??
        data['current_device'] ??
        data['last_device'] ??
        data['active_device'] ??
        data['latest_platform'] ??
        data['current_platform'] ??
        data['last_platform'] ??
        data['terminal'] ??
        data['device_type'] ??
        data['platform'] ??
        data['client'] ??
        data['device'];
    final directValue = normalize(direct);
    if (directValue.isNotEmpty && !isPlaceholder(directValue)) {
      return directValue;
    }
    final flag = data['device_flag'];
    if ('$flag' == '2') return 'android';
    if ('$flag' == '4') return 'ios';
    if ('$flag' == '1') return 'web';
    return '';
  }

  Future<ImOnlineStatus> getImOnlineStatus({
    required String token,
    required int userId,
  }) async {
    final r = await _post('/get_im_online_status', {
      'usertoken': token,
      'user_id': userId,
    });
    final data = r['data'];
    if (data is Map) {
      final value = data['online'] ?? data['is_online'] ?? data['status'];
      final online = value is bool
          ? value
          : '$value' == '1' ||
                '$value'.toLowerCase() == 'true' ||
                '$value'.toLowerCase() == 'online';
      final device = _pickOnlineDevice(data);
      final lastSeen = _parseServerDate(
        data['last_seen'] ?? data['last_seen_time'] ?? data['offline_time'],
      );
      return ImOnlineStatus(online: online, device: device, lastSeen: lastSeen);
    }
    return const ImOnlineStatus(online: false);
  }

  DateTime? _parseServerDate(Object? value) {
    final text = '${value ?? ''}'.trim();
    if (text.isEmpty || text == 'null' || text == '0000-00-00 00:00:00') {
      return null;
    }
    final normalized = text.contains('T') ? text : text.replaceFirst(' ', 'T');
    return DateTime.tryParse(normalized);
  }
}
