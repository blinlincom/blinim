import 'dart:async';
import 'dart:convert';
import 'package:audioplayers/audioplayers.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:video_player/video_player.dart';
import '../models/im_models.dart';
import '../models/user_session.dart';
import '../services/api_service.dart';
import '../services/chat_display_preferences.dart';
import '../services/conversation_preferences.dart';
import '../services/deleted_message_store.dart';
import '../services/failed_message_store.dart';
import '../services/file_download/file_downloader.dart';
import '../services/im_service.dart';
import '../services/screenshot_monitor.dart';
import '../utils/media_url.dart' as media_url;
import '../widgets/blin_style.dart';
import '../widgets/embedded_browser.dart';
import '../widgets/gif_sticker_panel.dart';
import '../widgets/link_text.dart';
import '../widgets/red_packet_widgets.dart';
import '../widgets/transfer_widgets.dart';
import 'call_screen.dart';

class ChatScreen extends StatefulWidget {
  final UserSession session;
  final ImService im;
  final int peerId;
  final String peerName;
  final String peerAvatar;
  final bool voiceMessageEnabled;
  final bool screenshotNoticeEnabled;
  const ChatScreen({
    super.key,
    required this.session,
    required this.im,
    required this.peerId,
    required this.peerName,
    required this.peerAvatar,
    this.voiceMessageEnabled = true,
    this.screenshotNoticeEnabled = false,
  });
  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> with WidgetsBindingObserver {
  final api = const ApiService();
  final input = TextEditingController();
  final inputFocus = FocusNode();
  final scroll = ScrollController();
  final recorder = AudioRecorder();
  final imagePicker = ImagePicker();
  List<UnifiedMessage> messages = [];
  int historyPage = 1;
  bool hasMoreHistory = true;
  bool loadingHistory = false;
  bool isFriend = true;
  bool friendRequestPending = false;
  int nonFriendTextSent = 0;
  bool loading = true;
  ImOnlineStatus? peerOnline;
  DateTime? realtimePresenceAt;
  bool sendingAttachment = false;
  bool readyToShowMessages = false;
  bool showEmojiPanel = false;
  bool voiceInputMode = false;
  bool recordingVoice = false;
  bool sendingVoice = false;
  bool stickToBottomDuringKeyboard = false;
  bool peerTyping = false;
  bool muteNotifications = false;
  bool pinnedChat = false;
  double chatFontSize = ChatDisplayPreferences.defaultChatFontSize;
  bool suppressHistoryDuringProgrammaticScroll = false;
  int keyboardSettleGeneration = 0;
  int bottomSettleGeneration = 0;
  DateTime historyLoadBlockedUntil = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime lastTypingSentAt = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime lastReadReceiptSentAt = DateTime.fromMillisecondsSinceEpoch(0);
  final Map<String, String> messageSendStates = {};
  final Map<String, FailedMessageDraft> failedDrafts = {};
  Set<String> deletedMessageKeys = {};
  StreamSubscription? sub;
  StreamSubscription? presenceSub;
  StreamSubscription? typingSub;
  StreamSubscription? readReceiptSub;
  StreamSubscription? connectionSub;
  StreamSubscription? screenshotSub;
  Timer? typingHideTimer;
  Timer? onlineTimer;
  Timer? voiceTimer;
  DateTime? voiceStartedAt;
  DateTime lastScreenshotNoticeAt = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(loadConversationPreferences());
    unawaited(loadChatDisplayPreferences());
    load();
    checkFriend();
    unawaited(ScreenshotMonitor.prepare());
    screenshotSub = ScreenshotMonitor.events.listen((_) {
      unawaited(_sendScreenshotNotice());
    });
    scroll.addListener(onScroll);
    input.addListener(_handleInputChanged);
    inputFocus.addListener(() {
      if (inputFocus.hasFocus) {
        _handleInputFocus();
      } else {
        unawaited(_sendTypingStopped());
      }
    });
    sub = widget.im.messages.listen((m) {
      if (m.fromUserId == widget.peerId || m.toUserId == widget.peerId) {
        if (_isHiddenCallSignal(m)) return;
        if (_isMessageDeleted(m)) return;
        if (m.msgType == 'recall') {
          if (_applyRecallMessage(m)) _bottom();
          return;
        }
        if (m.msgType == 'transfer_receipt') {
          _applyTransferReceipt(m);
          _bottom();
        }
        setState(() {
          if (!_hasMessage(m)) messages.add(m);
          if (m.fromUserId == widget.peerId) {
            peerOnline = const ImOnlineStatus(online: true, device: '');
          }
        });
        if (m.fromUserId == widget.peerId) unawaited(_sendReadReceipt());
        _bottom();
      }
    });
    presenceSub = widget.im.presences.listen((p) {
      if (p.userId == widget.peerId) {
        setState(() {
          realtimePresenceAt = DateTime.now();
          peerOnline = ImOnlineStatus(online: p.online, device: p.device);
        });
      }
    });
    connectionSub = widget.im.connectionChanges.listen((_) {
      if (widget.im.connected) {
        unawaited(refreshPeerOnline());
        unawaited(_sendReadReceipt());
      }
    });
    typingSub = widget.im.typingEvents.listen((event) {
      if (event.fromUserId != widget.peerId ||
          event.toUserId != widget.session.id) {
        return;
      }
      _showPeerTyping(event.active);
    });
    readReceiptSub = widget.im.readReceipts.listen((receipt) {
      if (receipt.fromUserId != widget.peerId ||
          receipt.toUserId != widget.session.id) {
        return;
      }
      _applyReadReceipt(receipt);
    });
    onlineTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (mounted && widget.im.connected) unawaited(refreshPeerOnline());
    });
    refreshPeerOnline();
  }

  Future<void> loadChatDisplayPreferences() async {
    final value = await const ChatDisplayPreferences().loadChatFontSize();
    if (!mounted) return;
    setState(() => chatFontSize = value);
  }

  bool _isMobileDevice(String device) {
    final d = device.trim().toLowerCase();
    return d.contains('android') ||
        d.contains('ios') ||
        d.contains('iphone') ||
        d.contains('ipad') ||
        d.contains('mobile') ||
        d.contains('phone') ||
        d == '2' ||
        d == '4';
  }

  String get _conversationKey => ConversationPreferences.peerKey(widget.peerId);
  String get _failedConversationKey =>
      'peer:${widget.session.id}:${widget.peerId}';
  String get _deletedConversationKey =>
      'peer:${widget.session.id}:${widget.peerId}';

  Future<void> loadConversationPreferences() async {
    try {
      final results = await Future.wait<Set<String>>([
        ConversationPreferences.loadMuted(widget.session.id),
        ConversationPreferences.loadPinned(widget.session.id),
      ]);
      if (!mounted) return;
      setState(() {
        muteNotifications = results[0].contains(_conversationKey);
        pinnedChat = results[1].contains(_conversationKey);
      });
    } catch (_) {}
  }

  Future<void> setConversationMuted(bool value) async {
    setState(() => muteNotifications = value);
    await ConversationPreferences.setMuted(
      widget.session.id,
      _conversationKey,
      value,
    );
  }

  Future<void> setConversationPinned(bool value) async {
    setState(() => pinnedChat = value);
    await ConversationPreferences.setPinned(
      widget.session.id,
      _conversationKey,
      value,
    );
  }

  Future<void> refreshPeerOnline() async {
    try {
      final status = await api.getImOnlineStatus(
        token: widget.session.token,
        userId: widget.peerId,
      );
      if (mounted) {
        final hasFreshRealtime =
            realtimePresenceAt != null &&
            DateTime.now().difference(realtimePresenceAt!) <
                const Duration(seconds: 45);
        final apiIsMobile = status.online && _isMobileDevice(status.device);
        final currentIsMobile =
            peerOnline != null &&
            peerOnline!.online &&
            _isMobileDevice(peerOnline!.device);
        if (!hasFreshRealtime || apiIsMobile || !currentIsMobile) {
          setState(() => peerOnline = status);
        }
      }
    } catch (_) {
      if (mounted)
        setState(() => peerOnline = const ImOnlineStatus(online: false));
    }
  }

  Future<void> checkFriend() async {
    try {
      final value = await api.isFriend(widget.session.token, widget.peerId);
      var pending = false;
      if (!value) {
        try {
          pending = await api.hasPendingOutgoingFriendRequest(
            widget.session.token,
            widget.peerId,
          );
        } catch (_) {
          final cached =
              await ConversationPreferences.loadPendingFriendRequests(
                widget.session.id,
              );
          pending = cached.contains(widget.peerId);
        }
      }
      if (mounted) {
        setState(() {
          isFriend = value;
          friendRequestPending = value ? false : pending;
        });
      }
    } catch (_) {
      final cached = await ConversationPreferences.loadPendingFriendRequests(
        widget.session.id,
      );
      if (mounted) {
        setState(() {
          isFriend = false;
          friendRequestPending = cached.contains(widget.peerId);
        });
      }
    }
  }

  bool _isHiddenCallSignal(UnifiedMessage message) {
    return message.msgType == 'call';
  }

  bool _isHiddenChatEvent(UnifiedMessage message) {
    return _isHiddenCallSignal(message);
  }

  String _messageKey(UnifiedMessage message) {
    final raw = message.raw;
    final direct =
        '${raw['client_msg_no'] ?? raw['message_id'] ?? raw['id'] ?? message.messageId}'
            .trim();
    if (direct.isNotEmpty && direct != '0') return direct;
    return _semanticMessageKey(message);
  }

  String _semanticMessageKey(UnifiedMessage message) {
    final seconds = message.createTime.millisecondsSinceEpoch ~/ 1000;
    final contentText = jsonEncode(message.content);
    return '${message.fromUserId}_${message.toUserId}_${message.msgType}_${seconds}_$contentText';
  }

  List<UnifiedMessage> _dedupeMessages(List<UnifiedMessage> source) {
    final seen = <String>{};
    final result = <UnifiedMessage>[];
    for (final message in source) {
      final keys = _messageKeys(message);
      if (keys.any(seen.contains)) continue;
      seen.addAll(keys);
      result.add(message);
    }
    return result;
  }

  bool _hasMessage(UnifiedMessage message) {
    final keys = _messageKeys(message);
    return messages.any((m) => _messageKeys(m).any(keys.contains));
  }

  int _recallTargetMessageId(UnifiedMessage message) {
    final content = message.content;
    return int.tryParse(
          '${content['message_id'] ?? message.raw['message_id'] ?? 0}',
        ) ??
        0;
  }

  UnifiedMessage _recalledMessage(UnifiedMessage source, {String? text}) {
    final messageId = source.messageId;
    final content = {
      'message_id': messageId,
      'client_msg_no': source.raw['client_msg_no'] ?? '',
      'text': text ?? (source.isMe ? '你撤回了一条消息' : '对方撤回了一条消息'),
    };
    return source.copyWith(
      msgType: 'recall',
      content: content,
      raw: {
        ...source.raw,
        'msg_type': 'recall',
        'content': content,
        'is_recalled': 1,
      },
    );
  }

  bool _applyRecallMessage(UnifiedMessage recall) {
    final targetId = _recallTargetMessageId(recall);
    var changed = false;
    setState(() {
      for (var i = 0; i < messages.length; i++) {
        final message = messages[i];
        final matchedId = targetId > 0 && message.messageId == targetId;
        final matchedClientNo =
            '${message.raw['client_msg_no'] ?? ''}'.isNotEmpty &&
            '${message.raw['client_msg_no'] ?? ''}' ==
                '${recall.content['client_msg_no'] ?? recall.raw['client_msg_no'] ?? ''}';
        if (matchedId || matchedClientNo) {
          messages[i] = _recalledMessage(
            message,
            text: '${recall.content['text'] ?? '消息已撤回'}',
          );
          changed = true;
          break;
        }
      }
    });
    return changed;
  }

  bool _applyTransferReceipt(UnifiedMessage receipt) {
    final transferId =
        int.tryParse('${receipt.content['transfer_id'] ?? 0}') ?? 0;
    final targetId = int.tryParse('${receipt.content['message_id'] ?? 0}') ?? 0;
    final status = '${receipt.content['status'] ?? ''}'.trim();
    if (transferId <= 0 && targetId <= 0) return false;
    var changed = false;
    setState(() {
      for (var i = 0; i < messages.length; i++) {
        final item = messages[i];
        if (item.msgType != 'transfer') continue;
        final itemTransferId =
            int.tryParse('${item.content['transfer_id'] ?? 0}') ?? 0;
        final itemMessageId = item.messageId > 0
            ? item.messageId
            : (int.tryParse('${item.raw['message_id'] ?? 0}') ?? 0);
        final matchedTransfer =
            transferId > 0 &&
            itemTransferId > 0 &&
            transferId == itemTransferId;
        final matchedMessage = targetId > 0 && itemMessageId == targetId;
        if (matchedTransfer || matchedMessage) {
          messages[i] = _messageWithTransferData(item, {
            if (transferId > 0) 'transfer_id': transferId,
            if (status.isNotEmpty) 'status': status,
            if (receipt.content['amount'] != null)
              'amount': receipt.content['amount'],
          });
          changed = true;
          break;
        }
      }
    });
    return changed;
  }

  Set<String> _messageKeys(UnifiedMessage message) {
    final raw = message.raw;
    final keys = <String>{};
    for (final value in [
      raw['client_msg_no'],
      raw['message_id'],
      raw['id'],
      message.messageId,
    ]) {
      final key = '$value'.trim();
      if (key.isNotEmpty && key != '0' && key != 'null') keys.add(key);
    }
    keys.add(_semanticMessageKey(message));
    return keys;
  }

  bool _isMessageDeleted(UnifiedMessage message) =>
      _messageKeys(message).any(deletedMessageKeys.contains);

  List<UnifiedMessage> _withoutDeletedMessages(
    Iterable<UnifiedMessage> source,
  ) => source.where((message) => !_isMessageDeleted(message)).toList();

  Future<void> _loadDeletedMessageKeys() async {
    deletedMessageKeys = await DeletedMessageStore.load(
      widget.session.id,
      _deletedConversationKey,
    );
  }

  UnifiedMessage _withServerMessageId(UnifiedMessage message, int messageId) {
    if (messageId <= 0 || message.messageId == messageId) return message;
    return message.copyWith(
      messageId: messageId,
      raw: {...message.raw, 'message_id': messageId},
    );
  }

  Future<void> _sendControlPayload(String type, Map<String, dynamic> content) {
    return widget.im.sendDirect(
      channelId: ImService.uidForUser(widget.peerId),
      payload: buildPayload(type, content),
    );
  }

  void _handleInputChanged() {
    if (!mounted || input.text.trim().isEmpty || !inputFocus.hasFocus) return;
    final now = DateTime.now();
    if (now.difference(lastTypingSentAt) < const Duration(seconds: 2)) return;
    lastTypingSentAt = now;
    unawaited(
      _sendControlPayload('typing', {
        'event': 'typing',
        'active': true,
        'time': now.toIso8601String(),
      }).catchError((_) {}),
    );
  }

  Future<void> _sendTypingStopped() async {
    final now = DateTime.now();
    await _sendControlPayload('typing', {
      'event': 'stop',
      'active': false,
      'time': now.toIso8601String(),
    }).catchError((_) {});
  }

  void _showPeerTyping(bool active) {
    typingHideTimer?.cancel();
    if (!mounted) return;
    setState(() => peerTyping = active);
    if (!active) return;
    typingHideTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => peerTyping = false);
    });
    _bottom(delay: const Duration(milliseconds: 40));
  }

  Future<void> _sendReadReceipt() async {
    final now = DateTime.now();
    if (now.difference(lastReadReceiptSentAt) <
        const Duration(milliseconds: 800)) {
      return;
    }
    final received = messages.where((message) => !message.isMe).toList();
    if (received.isEmpty) return;
    lastReadReceiptSentAt = now;
    final messageIds = received
        .map((message) => message.messageId)
        .where((id) => id > 0)
        .toSet()
        .toList();
    final keys = <String>{
      for (final message in received) ..._messageKeys(message),
    };
    final persist = api
        .markPeerMessagesRead(
          token: widget.session.token,
          peerId: widget.peerId,
          messageIds: messageIds,
          lastReadAt: now,
        )
        .catchError((_) {});
    final notify = _sendControlPayload('read_receipt', {
      'reader_user_id': widget.session.id,
      'peer_id': widget.peerId,
      'message_ids': messageIds,
      'message_keys': keys.toList(),
      'last_read_at': now.toIso8601String(),
    }).catchError((_) {});
    await Future.wait([persist, notify]);
  }

  void _applyReadReceipt(ReadReceipt receipt) {
    final keys = receipt.messageKeys;
    final ids = receipt.messageIds;
    final readAt = receipt.readAt;
    setState(() {
      for (final message in messages.where((message) => message.isMe)) {
        final matchedId =
            message.messageId > 0 && ids.contains(message.messageId);
        final matchedKey =
            keys.isNotEmpty && _messageKeys(message).any(keys.contains);
        final matchedTime =
            ids.isEmpty &&
            keys.isEmpty &&
            readAt != null &&
            !message.createTime.isAfter(readAt);
        if (matchedId || matchedKey || matchedTime) {
          messageSendStates[_messageKey(message)] = 'read';
        }
      }
    });
  }

  bool _syncReadStatesFromMessages(Iterable<UnifiedMessage> source) {
    var changed = false;
    for (final message in source) {
      if (message.isMe && message.read) {
        final key = _messageKey(message);
        if (messageSendStates[key] != 'read') {
          messageSendStates[key] = 'read';
          changed = true;
        }
      }
    }
    return changed;
  }

  List<UnifiedMessage> _mergeTimelineMessages(
    List<UnifiedMessage> current,
    List<UnifiedMessage> incoming,
  ) {
    final merged = _dedupeMessages([...incoming, ...current]);
    merged.sort((a, b) {
      final time = a.createTime.compareTo(b.createTime);
      if (time != 0) return time;
      return a.messageId.compareTo(b.messageId);
    });
    return merged;
  }

  String _messageVersion(UnifiedMessage message) => jsonEncode({
    'id': message.messageId,
    'type': message.msgType,
    'content': message.content,
    'read': message.read,
    'read_at': message.readAt?.toIso8601String(),
    'recalled': message.raw['is_recalled'],
  });

  bool _sameMessageTimeline(List<UnifiedMessage> a, List<UnifiedMessage> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!_messageKeys(a[i]).any(_messageKeys(b[i]).contains)) return false;
      if (_messageVersion(a[i]) != _messageVersion(b[i])) return false;
    }
    return true;
  }

  Future<List<UnifiedMessage>> _loadFailedMessages() async {
    final drafts = await FailedMessageStore.load(
      widget.session.id,
      _failedConversationKey,
    );
    failedDrafts
      ..clear()
      ..addEntries(drafts.map((draft) => MapEntry(draft.key, draft)));
    for (final draft in drafts) {
      messageSendStates[draft.key] = 'failed';
    }
    return drafts
        .map(
          (draft) =>
              UnifiedMessage.fromPayload(draft.payload, widget.session.id),
        )
        .where((message) => !_isMessageDeleted(message))
        .toList();
  }

  List<UnifiedMessage> _pendingFailedMessages(
    List<UnifiedMessage> serverMessages,
    List<UnifiedMessage> failedMessages,
  ) {
    final serverKeys = <String>{
      for (final message in serverMessages) ..._messageKeys(message),
    };
    final pending = <UnifiedMessage>[];
    for (final message in failedMessages) {
      final key = _messageKey(message);
      if (_isMessageDeleted(message) ||
          _messageKeys(message).any(serverKeys.contains)) {
        failedDrafts.remove(key);
        messageSendStates.remove(key);
        unawaited(_removeFailedDraft(key));
      } else {
        pending.add(message);
      }
    }
    return pending;
  }

  Future<void> _saveFailedDraft(FailedMessageDraft draft) async {
    failedDrafts[draft.key] = draft;
    messageSendStates[draft.key] = 'failed';
    await FailedMessageStore.upsert(
      widget.session.id,
      _failedConversationKey,
      draft,
    );
  }

  Future<void> _removeFailedDraft(String key) async {
    failedDrafts.remove(key);
    await FailedMessageStore.remove(
      widget.session.id,
      _failedConversationKey,
      key,
    );
  }

  Future<void> load({bool silent = false}) async {
    final firstLoad = messages.isEmpty && !silent;
    final shouldStickAfterLoad = _isNearBottom();
    if (firstLoad) {
      setState(() {
        loading = true;
        readyToShowMessages = false;
      });
    }
    try {
      await _loadDeletedMessageKeys();
      final r = await api.getChatLog(
        token: widget.session.token,
        receiverId: widget.peerId,
        myId: widget.session.id,
        page: 1,
      );
      final visible = _withoutDeletedMessages(
        r.where((m) => !_isHiddenChatEvent(m)),
      );
      final failed = _pendingFailedMessages(
        visible,
        await _loadFailedMessages(),
      );
      final visibleWithFailed = _dedupeMessages([...visible, ...failed]);
      if (mounted) {
        final nextMessages = messages.isEmpty
            ? visibleWithFailed
            : _mergeTimelineMessages(messages, visibleWithFailed);
        final listChanged = !_sameMessageTimeline(messages, nextMessages);
        final stateChanged =
            listChanged ||
            loading ||
            !readyToShowMessages ||
            (!silent && historyPage != 1) ||
            (!silent && hasMoreHistory != (r.length >= 30));
        if (stateChanged) {
          setState(() {
            messages = nextMessages;
            if (!silent) {
              historyPage = 1;
              hasMoreHistory = r.length >= 30;
            }
            _syncReadStatesFromMessages(messages);
            loading = false;
            readyToShowMessages = true;
          });
        } else if (_syncReadStatesFromMessages(nextMessages)) {
          setState(() {});
        }
        unawaited(_sendReadReceipt());
        if (!firstLoad && listChanged && shouldStickAfterLoad) {
          _jumpToBottomAfterLayout();
        }
      }
    } catch (e) {
      if (mounted && !silent) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('聊天内容暂时无法同步')));
      }
    } finally {
      if (mounted) {
        if (firstLoad && loading) {
          setState(() {
            loading = false;
            readyToShowMessages = true;
          });
        }
      }
    }
  }

  void onScroll() {
    if (!scroll.hasClients ||
        loadingHistory ||
        !hasMoreHistory ||
        loading ||
        !readyToShowMessages ||
        _historyLoadBlocked ||
        suppressHistoryDuringProgrammaticScroll)
      return;
    if (!scroll.position.isScrollingNotifier.value) return;
    final distanceToHistory =
        scroll.position.maxScrollExtent - scroll.position.pixels;
    if (distanceToHistory <= 48) unawaited(loadOlderHistory());
  }

  Future<void> loadOlderHistory() async {
    if (loadingHistory || !hasMoreHistory) return;
    bottomSettleGeneration++;
    _blockHistoryLoad(const Duration(milliseconds: 700));
    setState(() => loadingHistory = true);
    var historyChanged = false;
    try {
      final nextPage = historyPage + 1;
      final older = await api.getChatLog(
        token: widget.session.token,
        receiverId: widget.peerId,
        myId: widget.session.id,
        page: nextPage,
      );
      if (mounted) {
        final visibleOlder = _withoutDeletedMessages(
          older.where((m) => !_isHiddenChatEvent(m)),
        );
        final merged = _dedupeMessages([...visibleOlder, ...messages]);
        final added = merged.length > messages.length;
        setState(() {
          messages = merged;
          if (added) historyPage = nextPage;
          hasMoreHistory = added && older.length >= 30;
          _syncReadStatesFromMessages(messages);
        });
        historyChanged = added;
      }
    } catch (_) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('历史消息暂时加载失败')));
    } finally {
      if (mounted) setState(() => loadingHistory = false);
      if (mounted && historyChanged) _showLoadedHistoryStart();
    }
  }

  void _showLoadedHistoryStart() {
    final generation = ++bottomSettleGeneration;
    suppressHistoryDuringProgrammaticScroll = true;
    _blockHistoryLoad(const Duration(milliseconds: 700));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          !scroll.hasClients ||
          generation != bottomSettleGeneration) {
        return;
      }
      Future<void>.delayed(const Duration(milliseconds: 180), () {
        if (mounted && generation == bottomSettleGeneration) {
          suppressHistoryDuringProgrammaticScroll = false;
        }
      });
    });
  }

  Future<void> clearPeerChatHistory() async {
    try {
      final msg = await api.clearPeerChatHistory(
        token: widget.session.token,
        peerId: widget.peerId,
      );
      await DeletedMessageStore.clear(
        widget.session.id,
        _deletedConversationKey,
      );
      if (!mounted) return;
      setState(() {
        messages = [];
        deletedMessageKeys = {};
        historyPage = 1;
        hasMoreHistory = false;
        readyToShowMessages = true;
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('聊天记录清空失败：$e')));
    }
  }

  Future<UnifiedMessage?> sendPayload(
    Map<String, dynamic> payload, {
    required String fallbackContent,
    required int messageType,
    bool optimistic = true,
    FailedMessageDraft? retryDraft,
  }) async {
    final draft =
        retryDraft ??
        FailedMessageDraft(
          payload: Map<String, dynamic>.from(payload),
          fallbackContent: fallbackContent,
          messageType: messageType,
        );
    final local = UnifiedMessage.fromPayload(draft.payload, widget.session.id);
    final key = _messageKey(local);
    if (optimistic) {
      setState(() {
        messageSendStates[key] = 'pending';
        deletedMessageKeys.removeAll(_messageKeys(local));
        if (!_hasMessage(local)) messages.add(local);
      });
      _bottom();
    }
    try {
      final sentMessageId = await api.sendMessage(
        token: widget.session.token,
        receiverId: widget.peerId,
        content: draft.fallbackContent,
        messageType: draft.messageType,
        payload: draft.payload,
      );
      UnifiedMessage delivered = _withServerMessageId(local, sentMessageId);
      if (mounted) {
        setState(() {
          delivered = _withServerMessageId(local, sentMessageId);
          if (optimistic && sentMessageId > 0) {
            final index = messages.indexWhere(
              (message) => _messageKeys(message).contains(key),
            );
            if (index >= 0) {
              delivered = _withServerMessageId(messages[index], sentMessageId);
              messages[index] = delivered;
            }
          }
          if (messageSendStates[key] != 'read') {
            messageSendStates[key] = 'success';
          }
          failedDrafts.remove(key);
          if (!optimistic &&
              !_hasMessage(delivered) &&
              !_isMessageDeleted(delivered)) {
            messages.add(delivered);
          }
        });
        unawaited(_removeFailedDraft(key));
        if (!optimistic) _bottom();
      }
      return delivered;
    } catch (e) {
      if (mounted) {
        setState(() {
          messageSendStates[key] = 'failed';
          if (!_hasMessage(local) && !_isMessageDeleted(local)) {
            messages.add(local);
          }
        });
        unawaited(_saveFailedDraft(draft));
        if (!optimistic) _bottom();
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('消息暂时没有发送成功：$e')));
      }
      return null;
    }
  }

  String? normalizeTransferAmount(String raw) {
    var value = raw
        .replaceAll('，', '.')
        .replaceAll(',', '.')
        .replaceAll('。', '.')
        .trim();
    value = value.replaceAll(RegExp(r'\s+'), '');
    if (value.isEmpty) return null;
    if (!RegExp(r'^\d+(\.\d{1,2})?$').hasMatch(value)) return null;
    final parsed = double.tryParse(value);
    if (parsed == null || parsed <= 0) return null;
    return parsed.toStringAsFixed(2);
  }

  UnifiedMessage _messageWithTransferData(
    UnifiedMessage source,
    Map<String, dynamic> transfer,
  ) {
    if (transfer.isEmpty) return source;
    final content = Map<String, dynamic>.from(source.content)..addAll(transfer);
    final rawContent = source.raw['content'];
    return source.copyWith(
      content: content,
      raw: {
        ...source.raw,
        if (transfer['message_id'] != null)
          'message_id': transfer['message_id'],
        'content': rawContent is Map
            ? {...Map<String, dynamic>.from(rawContent), ...content}
            : content,
      },
    );
  }

  UnifiedMessage _messageWithRedPacketData(
    UnifiedMessage source,
    Map<String, dynamic> redPacket,
  ) {
    if (redPacket.isEmpty) return source;
    final content = Map<String, dynamic>.from(source.content)
      ..addAll(redPacket);
    final rawContent = source.raw['content'];
    return source.copyWith(
      content: content,
      raw: {
        ...source.raw,
        if (redPacket['message_id'] != null)
          'message_id': redPacket['message_id'],
        'content': rawContent is Map
            ? {...Map<String, dynamic>.from(rawContent), ...content}
            : content,
      },
    );
  }

  Future<UnifiedMessage?> sendRedPacketPayload(
    Map<String, dynamic> payload, {
    required String amount,
    required String greeting,
    required String fallbackContent,
  }) async {
    final draft = FailedMessageDraft(
      payload: Map<String, dynamic>.from(payload),
      fallbackContent: fallbackContent,
      messageType: 0,
    );
    final local = UnifiedMessage.fromPayload(draft.payload, widget.session.id);
    final key = _messageKey(local);
    setState(() {
      messageSendStates[key] = 'pending';
      deletedMessageKeys.removeAll(_messageKeys(local));
      if (!_hasMessage(local)) messages.add(local);
    });
    _bottom();
    try {
      final data = await api.sendRedPacket(
        token: widget.session.token,
        receiverId: widget.peerId,
        amount: amount,
        greeting: greeting,
        clientMsgNo: '${payload['client_msg_no'] ?? ''}',
        payload: payload,
      );
      final sentMessageId = int.tryParse('${data['message_id'] ?? 0}') ?? 0;
      final serverPayload = data['payload'] is Map
          ? Map<String, dynamic>.from(data['payload'] as Map)
          : <String, dynamic>{};
      final packetData = data['red_packet'] is Map
          ? Map<String, dynamic>.from(data['red_packet'] as Map)
          : <String, dynamic>{};
      var delivered = serverPayload.isNotEmpty
          ? UnifiedMessage.fromPayload(serverPayload, widget.session.id)
          : _withServerMessageId(local, sentMessageId);
      delivered = _messageWithRedPacketData(delivered, packetData);
      if (mounted) {
        setState(() {
          messageSendStates[key] = 'success';
          messageSendStates[_messageKey(delivered)] = 'success';
          failedDrafts.remove(key);
          final deliveredKeys = _messageKeys(delivered);
          final index = messages.indexWhere(
            (message) =>
                _messageKeys(message).contains(key) ||
                _messageKeys(message).any(deliveredKeys.contains),
          );
          if (index >= 0) {
            messages[index] = delivered;
          } else if (!_isMessageDeleted(delivered)) {
            messages.add(delivered);
          }
        });
        unawaited(_removeFailedDraft(key));
        _bottom();
      }
      return delivered;
    } catch (e) {
      if (mounted) {
        setState(() {
          messageSendStates[key] = 'failed';
          if (!_hasMessage(local) && !_isMessageDeleted(local)) {
            messages.add(local);
          }
        });
        unawaited(_saveFailedDraft(draft));
        _bottom();
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('红包发送失败：$e')));
      }
      return null;
    }
  }

  Future<UnifiedMessage?> sendTransferPayload(
    Map<String, dynamic> payload, {
    required String fallbackContent,
  }) async {
    final draft = FailedMessageDraft(
      payload: Map<String, dynamic>.from(payload),
      fallbackContent: fallbackContent,
      messageType: 2,
    );
    final local = UnifiedMessage.fromPayload(draft.payload, widget.session.id);
    final key = _messageKey(local);
    try {
      final data = await api.sendMessageResult(
        token: widget.session.token,
        receiverId: widget.peerId,
        content: draft.fallbackContent,
        messageType: draft.messageType,
        payload: draft.payload,
      );
      final sentMessageId = int.tryParse('${data['message_id'] ?? 0}') ?? 0;
      final transferData = data['transfer'] is Map
          ? Map<String, dynamic>.from(data['transfer'] as Map)
          : <String, dynamic>{};
      var delivered = _withServerMessageId(local, sentMessageId);
      delivered = _messageWithTransferData(delivered, transferData);
      if (mounted) {
        setState(() {
          messageSendStates[key] = 'success';
          messageSendStates[_messageKey(delivered)] = 'success';
          failedDrafts.remove(key);
          final deliveredKeys = _messageKeys(delivered);
          final index = messages.indexWhere(
            (message) =>
                _messageKeys(message).contains(key) ||
                _messageKeys(message).any(deliveredKeys.contains),
          );
          if (index >= 0) {
            messages[index] = delivered;
          } else if (!_isMessageDeleted(delivered)) {
            messages.add(delivered);
          }
        });
        unawaited(_removeFailedDraft(key));
        _bottom();
      }
      return delivered;
    } catch (e) {
      if (mounted) {
        setState(() {
          messageSendStates[key] = 'failed';
          if (!_hasMessage(local) && !_isMessageDeleted(local)) {
            messages.add(local);
          }
        });
        unawaited(_saveFailedDraft(draft));
        _bottom();
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('转账发送失败：$e')));
      }
      return null;
    }
  }

  Future<void> updateTransferStatus(
    UnifiedMessage message, {
    required bool accept,
  }) async {
    final transferId =
        int.tryParse('${message.content['transfer_id'] ?? 0}') ?? 0;
    final messageId =
        int.tryParse(
          '${message.content['message_id'] ?? message.raw['message_id'] ?? message.messageId}',
        ) ??
        0;
    final clientMsgNo =
        '${message.content['client_msg_no'] ?? message.raw['client_msg_no'] ?? ''}'
            .trim();
    try {
      final data = accept
          ? await api.acceptImTransfer(
              token: widget.session.token,
              transferId: transferId,
              messageId: messageId,
              clientMsgNo: clientMsgNo,
            )
          : await api.returnImTransfer(
              token: widget.session.token,
              transferId: transferId,
              messageId: messageId,
              clientMsgNo: clientMsgNo,
            );
      if (!mounted) return;
      final targetKeys = _messageKeys(message);
      setState(() {
        for (var i = 0; i < messages.length; i++) {
          if (_messageKeys(messages[i]).any(targetKeys.contains)) {
            messages[i] = _messageWithTransferData(messages[i], data);
            break;
          }
        }
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(accept ? '已确认收款' : '已退回转账')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(accept ? '收款失败：$e' : '退回失败：$e')));
    }
  }

  Future<void> retryFailedMessage(UnifiedMessage message) async {
    final key = _messageKey(message);
    final draft = failedDrafts[key];
    if (draft == null) return;
    if ('${draft.payload['msg_type']}' == 'red_packet') {
      final content = draft.payload['content'] is Map
          ? Map<String, dynamic>.from(draft.payload['content'] as Map)
          : <String, dynamic>{};
      await sendRedPacketPayload(
        draft.payload,
        amount: '${content['amount'] ?? content['total_amount'] ?? ''}',
        greeting: redPacketGreeting(content),
        fallbackContent: draft.fallbackContent,
      );
      return;
    }
    if (draft.messageType == 2 ||
        '${draft.payload['msg_type']}' == 'transfer') {
      await sendTransferPayload(
        draft.payload,
        fallbackContent: draft.fallbackContent,
      );
      return;
    }
    await sendPayload(
      draft.payload,
      fallbackContent: draft.fallbackContent,
      messageType: draft.messageType,
      retryDraft: draft,
    );
  }

  Future<void> deleteMessage(UnifiedMessage message) async {
    final keys = _messageKeys(message);
    final key = _messageKey(message);
    setState(() {
      deletedMessageKeys.addAll(keys);
      messages.removeWhere((item) => _messageKeys(item).any(keys.contains));
      messageSendStates.remove(key);
      failedDrafts.remove(key);
    });
    await Future.wait([
      DeletedMessageStore.add(widget.session.id, _deletedConversationKey, keys),
      FailedMessageStore.remove(widget.session.id, _failedConversationKey, key),
    ]);
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('消息已删除')));
    }
  }

  Map<String, dynamic> buildPayload(
    String type,
    Map<String, dynamic> content,
  ) => {
    'message_id': 0,
    'client_msg_no':
        '${widget.session.id}_${widget.peerId}_${DateTime.now().microsecondsSinceEpoch}_$type',
    'from_user_id': widget.session.id,
    'to_user_id': widget.peerId,
    'from_uid': ImService.uidForUser(widget.session.id),
    'to_uid': ImService.uidForUser(widget.peerId),
    'msg_type': type,
    'content': content,
    'create_time': DateTime.now().toIso8601String(),
  };

  Future<void> send() async {
    final text = input.text.trim();
    if (text.isEmpty) return;
    if (!isFriend && nonFriendTextSent >= 3) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('还不是好友，只能先发送 3 条文字消息，请先添加好友')),
      );
      return;
    }
    input.clear();
    unawaited(_sendTypingStopped());
    await sendPayload(
      buildPayload('text', {'text': text}),
      fallbackContent: text,
      messageType: 0,
    );
    if (!isFriend && mounted) setState(() => nonFriendTextSent += 1);
  }

  Future<void> sendEmoji(String emoji) async {
    if (!isFriend && nonFriendTextSent >= 3) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('还不是好友，只能先发送 3 条消息，请先添加好友')));
      return;
    }
    await sendPayload(
      buildPayload('emoji', {'emoji': emoji, 'text': emoji}),
      fallbackContent: emoji,
      messageType: 0,
    );
    if (!isFriend && mounted) setState(() => nonFriendTextSent += 1);
  }

  Future<void> _sendScreenshotNotice() async {
    if (!widget.screenshotNoticeEnabled || !isFriend) return;
    final now = DateTime.now();
    if (now.difference(lastScreenshotNoticeAt) < const Duration(seconds: 3)) {
      return;
    }
    lastScreenshotNoticeAt = now;
    final nickname = (widget.session.nickname ?? '').trim().isEmpty
        ? '我'
        : widget.session.nickname!.trim();
    final text = '$nickname 截屏了';
    final payload = buildPayload('screenshot', {
      'text': text,
      'screenshot': true,
      'nickname': nickname,
    });
    final local = UnifiedMessage.fromPayload(payload, widget.session.id);
    if (mounted && !_hasMessage(local)) {
      setState(() => messages.add(local));
      _bottom();
    }
    try {
      await api.sendMessage(
        token: widget.session.token,
        receiverId: widget.peerId,
        content: text,
        messageType: 0,
        payload: payload,
      );
    } catch (_) {}
  }

  String _pickUrl(Map<String, dynamic> data) {
    for (final key in const [
      'url',
      'path',
      'file_url',
      'video_url',
      'video_path',
      'file_path',
      'src',
      'image',
      'image_path',
      'oss_path',
    ]) {
      final value = data[key];
      if (value != null && '$value'.trim().isNotEmpty && '$value' != 'null')
        return media_url.resolveMediaUrl(value);
    }
    return '';
  }

  bool get _cameraCaptureSupported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  Future<void> sendAttachment({required String mediaType}) async {
    if (!isFriend) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('添加好友后才能发送图片、视频和文件')));
      return;
    }
    if (sendingAttachment) return;
    final result = await FilePicker.platform.pickFiles(
      type: mediaType == 'image'
          ? FileType.custom
          : mediaType == 'video'
          ? FileType.video
          : FileType.any,
      allowedExtensions: mediaType == 'image'
          ? const ['jpg', 'jpeg', 'png', 'webp', 'gif', 'heic', 'heif']
          : null,
      allowMultiple: false,
      withData: true,
    );
    final file = result == null || result.files.isEmpty
        ? null
        : result.files.first;
    if (file == null) return;
    final bytes = file.bytes;
    if (bytes == null) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('当前平台暂时无法读取这个文件')));
      return;
    }
    await _sendAttachmentBytes(
      mediaType: mediaType,
      bytes: bytes,
      filename: file.name,
      size: file.size,
    );
  }

  Future<void> sendGifSticker(GifSticker sticker) async {
    if (!isFriend) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('添加好友后才能发送 GIF 动图')));
      return;
    }
    if (sendingAttachment) return;
    try {
      final data = await rootBundle.load(sticker.asset);
      await _sendAttachmentBytes(
        mediaType: 'image',
        bytes: data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        filename: sticker.filename,
        size: data.lengthInBytes,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('GIF 发送失败：$e')));
    }
  }

  Future<void> captureAttachment() async {
    if (!isFriend) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('添加好友后才能发送图片、视频和文件')));
      return;
    }
    if (sendingAttachment) return;
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => CaptureActionSheet(
        onPhoto: () => Navigator.pop(context, 'image'),
        onVideo: () => Navigator.pop(context, 'video'),
      ),
    );
    if (action == null || !mounted) return;
    if (!_cameraCaptureSupported) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('当前平台暂不支持直接拍摄，请使用图片或文件入口选择媒体')),
      );
      return;
    }
    try {
      final picked = action == 'image'
          ? await imagePicker.pickImage(
              source: ImageSource.camera,
              imageQuality: 88,
            )
          : await imagePicker.pickVideo(
              source: ImageSource.camera,
              maxDuration: const Duration(minutes: 3),
            );
      if (picked == null) return;
      final bytes = await picked.readAsBytes();
      if (bytes.isEmpty) throw ApiException('拍摄文件为空');
      final filename = _captureFilename(picked, action);
      await _sendAttachmentBytes(
        mediaType: action,
        bytes: bytes,
        filename: filename,
        size: bytes.length,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(action == 'image' ? '拍照发送失败：$e' : '视频发送失败：$e')),
      );
    }
  }

  String _captureFilename(XFile file, String mediaType) {
    final raw = file.name.trim();
    if (raw.isNotEmpty && raw != 'null') return raw;
    final ext = mediaType == 'image' ? 'jpg' : 'mp4';
    return '${mediaType}_${widget.session.id}_${DateTime.now().millisecondsSinceEpoch}.$ext';
  }

  Future<void> _sendAttachmentBytes({
    required String mediaType,
    required List<int> bytes,
    required String filename,
    required int size,
  }) async {
    if (sendingAttachment) return;
    setState(() => sendingAttachment = true);
    try {
      final uploaded = await api.uploadChatFile(
        token: widget.session.token,
        bytes: bytes,
        filename: filename,
      );
      final url = _pickUrl(uploaded);
      if (url.isEmpty) throw ApiException('上传后没有返回文件地址');
      final type = mediaType;
      final isGif = type == 'image' && filename.toLowerCase().endsWith('.gif');
      final caption = input.text.trim();
      final payload = buildPayload(type, {
        'url': url,
        'file_url': url,
        if (type == 'image') 'image_path': url,
        if (isGif) ...{'media_format': 'gif', 'animated': true},
        if (type == 'video') ...{
          'video_url': url,
          'video_path': url,
          'file_path': url,
        },
        'name': filename,
        'file_name': filename,
        'size': size,
        if (caption.isNotEmpty && (type == 'image' || type == 'video'))
          'text': caption,
      });
      input.clear();
      unawaited(_sendTypingStopped());
      await sendPayload(
        payload,
        fallbackContent: isGif
            ? '[GIF]'
            : type == 'image'
            ? '[图片]'
            : type == 'video'
            ? '[视频] $filename'
            : '[文件] $filename',
        messageType: type == 'image'
            ? 1
            : type == 'video'
            ? 4
            : 3,
      );
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              mediaType == 'image'
                  ? '图片发送失败：$e'
                  : mediaType == 'video'
                  ? '视频发送失败：$e'
                  : '文件发送失败：$e',
            ),
          ),
        );
    } finally {
      if (mounted) setState(() => sendingAttachment = false);
    }
  }

  Future<void> toggleVoiceRecording() async {
    if (!widget.voiceMessageEnabled) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('语音消息已被后台关闭')));
      return;
    }
    if (recordingVoice) {
      await _finishVoiceRecording(send: true);
      return;
    }
    await _startVoiceRecording();
  }

  Future<void> _startVoiceRecording() async {
    if (!isFriend) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('添加好友后才能发送语音')));
      return;
    }
    if (sendingAttachment || sendingVoice || recordingVoice) return;
    try {
      final allowed = await recorder.hasPermission();
      if (!allowed) {
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('请先允许麦克风权限')));
        return;
      }
      if (!mounted) return;
      FocusScope.of(context).unfocus();
      final path = await voiceRecordPath(
        'voice_${widget.session.id}_${widget.peerId}_${DateTime.now().millisecondsSinceEpoch}.m4a',
      );
      await recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 64000,
          sampleRate: 16000,
        ),
        path: path,
      );
      if (!mounted) return;
      setState(() {
        recordingVoice = true;
        voiceStartedAt = DateTime.now();
      });
      voiceTimer?.cancel();
      voiceTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('录音启动失败：$e')));
    }
  }

  Future<void> _finishVoiceRecording({required bool send}) async {
    voiceTimer?.cancel();
    final startedAt = voiceStartedAt;
    String? path;
    try {
      path = await recorder.stop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('录音结束失败：$e')));
      }
    }
    if (!mounted) return;
    final duration = startedAt == null
        ? 0
        : DateTime.now().difference(startedAt).inSeconds;
    setState(() {
      recordingVoice = false;
      voiceStartedAt = null;
    });
    if (!send || path == null || path.isEmpty) return;
    if (duration < 1) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('说话时间太短')));
      return;
    }
    await sendVoiceFile(path: path, duration: duration);
  }

  Future<void> sendVoiceFile({
    required String path,
    required int duration,
  }) async {
    if (sendingVoice) return;
    setState(() => sendingVoice = true);
    try {
      final bytes = await readVoiceRecordBytes(path);
      if (bytes.isEmpty) throw ApiException('录音文件为空');
      final filename =
          'voice_${widget.session.id}_${widget.peerId}_${DateTime.now().millisecondsSinceEpoch}.m4a';
      final uploaded = await api.uploadChatFile(
        token: widget.session.token,
        bytes: bytes,
        filename: filename,
      );
      final url = _pickUrl(uploaded);
      if (url.isEmpty) throw ApiException('上传后没有返回语音地址');
      final payload = buildPayload('voice', {
        'url': url,
        'file_url': url,
        'name': filename,
        'duration': duration,
        'size': bytes.length,
        'mime': 'audio/mp4',
      });
      await sendPayload(
        payload,
        fallbackContent: '[语音] ${formatVoiceDuration(duration)}',
        messageType: 5,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('语音发送失败：$e')));
    } finally {
      if (mounted) setState(() => sendingVoice = false);
    }
  }

  Future<void> sendTransfer() async {
    if (!isFriend) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('添加好友后才能使用转账')));
      return;
    }
    final amountController = TextEditingController();
    final noteController = TextEditingController();
    final result = await showDialog<Map<String, String>>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: .30),
      builder: (_) => Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 24),
        backgroundColor: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(30),
            boxShadow: [BlinStyle.softShadow(.20)],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: BlinStyle.primary,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: const Row(
                  children: [
                    Icon(
                      Icons.account_balance_wallet_rounded,
                      color: Colors.white,
                    ),
                    SizedBox(width: 10),
                    Text(
                      '发起转账',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: amountController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9\.,]')),
                ],
                decoration: const InputDecoration(
                  labelText: '转账金额',
                  prefixText: '¥ ',
                ),
                autofocus: true,
              ),
              const SizedBox(height: 10),
              TextField(
                controller: noteController,
                decoration: const InputDecoration(labelText: '备注，可选'),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('取消'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton(
                      onPressed: () => Navigator.pop(context, {
                        'amount': amountController.text.trim(),
                        'note': noteController.text.trim(),
                      }),
                      child: const Text('发送'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    amountController.dispose();
    noteController.dispose();
    final normalizedAmount = normalizeTransferAmount(result?['amount'] ?? '');
    if ((result?['amount'] ?? '').trim().isEmpty) return;
    if (normalizedAmount == null) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('转账金额必须为数字，最多保留两位小数')));
      }
      return;
    }
    final amountValue = double.parse(normalizedAmount);
    try {
      final profile = await api.getUserOtherInformation(widget.session.token);
      final coinText = profile.coins.replaceAll(',', '').trim();
      final coins = double.tryParse(coinText) ?? 0;
      if (coins < amountValue) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('金币余额不足')));
        }
        return;
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('余额校验失败，请稍后再试')));
      }
      return;
    }
    await sendTransferPayload(
      buildPayload('transfer', {
        'amount': normalizedAmount,
        'note': result?['note'] ?? '',
        'status': 'pending',
        'payment': 0,
      }),
      fallbackContent: '[转账] ¥$normalizedAmount',
    );
  }

  Future<void> sendRedPacket() async {
    if (!isFriend) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('添加好友后才能发红包')));
      return;
    }
    final draft = await showRedPacketDraftSheet(context, group: false);
    if (draft == null) return;
    try {
      final profile = await api.getUserOtherInformation(widget.session.token);
      final coinText = profile.coins.replaceAll(',', '').trim();
      final coins = double.tryParse(coinText) ?? 0;
      if (coins < double.parse(draft.amount)) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('金币余额不足')));
        }
        return;
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('余额校验失败，请稍后再试')));
      }
      return;
    }
    await sendRedPacketPayload(
      buildPayload('red_packet', {
        'amount': draft.amount,
        'total_amount': draft.amount,
        'greeting': draft.greeting,
        'scope': 'single',
        'count': 1,
        'total_count': 1,
        'packet_type': 'normal',
        'status': 'pending',
        'money_type': 0,
      }),
      amount: draft.amount,
      greeting: draft.greeting,
      fallbackContent: '[红包] ${draft.greeting}',
    );
  }

  Future<void> openRedPacket(UnifiedMessage message) async {
    await showRedPacketOpenDialog(
      context,
      message: message,
      onOpen: () => api.claimRedPacket(
        token: widget.session.token,
        redPacketId: redPacketIdFromMessage(message),
        messageId: message.messageId,
        clientMsgNo:
            '${message.content['client_msg_no'] ?? message.raw['client_msg_no'] ?? ''}',
      ),
      onLoadDetail: () => api.getRedPacketDetail(
        token: widget.session.token,
        redPacketId: redPacketIdFromMessage(message),
        messageId: message.messageId,
        clientMsgNo:
            '${message.content['client_msg_no'] ?? message.raw['client_msg_no'] ?? ''}',
      ),
      onUpdate: (data) {
        final packet = data['red_packet'] is Map
            ? Map<String, dynamic>.from(data['red_packet'] as Map)
            : <String, dynamic>{};
        if (packet.isEmpty || !mounted) return;
        final targetKeys = _messageKeys(message);
        setState(() {
          for (var i = 0; i < messages.length; i++) {
            if (_messageKeys(messages[i]).any(targetKeys.contains)) {
              messages[i] = _messageWithRedPacketData(messages[i], packet);
              break;
            }
          }
        });
      },
    );
  }

  String _messagePlainText(UnifiedMessage message) {
    if (message.msgType == 'text') {
      return '${message.content['text'] ?? message.preview}';
    }
    if (message.msgType == 'emoji') {
      return '${message.content['emoji'] ?? message.content['text'] ?? ''}';
    }
    if (message.msgType == 'transfer') {
      return '[转账] ¥${message.content['amount'] ?? ''}';
    }
    if (message.msgType == 'red_packet') {
      return '[红包] ${redPacketGreeting(message.content)}';
    }
    if (message.msgType == 'call_record' ||
        message.msgType == 'voice' ||
        message.msgType == 'file' ||
        message.msgType == 'image' ||
        message.msgType == 'video') {
      return message.preview;
    }
    return '${message.content['text'] ?? message.preview}';
  }

  bool _canCopyMessage(UnifiedMessage message) {
    return ![
      'image',
      'video',
      'voice',
      'file',
      'red_packet',
      'recall',
    ].contains(message.msgType);
  }

  Map<String, dynamic> _forwardPayload(UnifiedMessage message, int receiverId) {
    final content = Map<String, dynamic>.from(message.content);
    return {
      ...buildPayload(message.msgType, content),
      'to_user_id': receiverId,
      'to_uid': ImService.uidForUser(receiverId),
      'client_msg_no':
          '${widget.session.id}_${receiverId}_${DateTime.now().microsecondsSinceEpoch}_forward',
    };
  }

  String _messageFileUrl(UnifiedMessage message) => firstMediaUrl([
    message.content['url'],
    message.content['file_url'],
    message.content['video_url'],
    message.content['video_path'],
    message.content['file_path'],
    message.content['path'],
    message.content['src'],
    message.content['image_path'],
  ]);

  String _messageFilename(UnifiedMessage message) {
    final raw =
        '${message.content['name'] ?? message.content['file_name'] ?? ''}'
            .trim();
    if (raw.isNotEmpty) return raw;
    final url = _messageFileUrl(message);
    final fallbackImageName = _isGifMessage(message)
        ? 'image.gif'
        : 'image.jpg';
    if (url.isEmpty) {
      return message.msgType == 'image' ? fallbackImageName : 'download';
    }
    final path = Uri.tryParse(url)?.path ?? url;
    final parts = path.split('/').where((e) => e.isNotEmpty).toList();
    final name = parts.isEmpty ? '' : parts.last;
    if (name.trim().isEmpty) {
      return message.msgType == 'image' ? fallbackImageName : 'download';
    }
    return name;
  }

  bool _isGifMessage(UnifiedMessage message) {
    return isGifImagePayload(message.content, _messageFileUrl(message));
  }

  int _messageFileSize(UnifiedMessage message) =>
      int.tryParse('${message.content['size'] ?? 0}') ?? 0;

  Future<void> downloadMessageFile(UnifiedMessage message) async {
    final url = _messageFileUrl(message);
    if (url.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('没有可下载的文件地址')));
      return;
    }
    try {
      final path = await downloadRemoteFile(
        url: url,
        filename: _messageFilename(message),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('已保存：$path')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('下载失败：$e')));
    }
  }

  Future<void> openImagePreview(UnifiedMessage message) async {
    final url = _messageFileUrl(message);
    if (url.isEmpty) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => ImagePreviewScreen(
          url: url,
          onDownload: () => downloadMessageFile(message),
          onForward: () => forwardMessage(message),
        ),
      ),
    );
  }

  Future<void> openFilePreview(UnifiedMessage message) async {
    final url = _messageFileUrl(message);
    if (url.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('没有可打开的文件地址')));
      return;
    }
    await Navigator.push(
      context,
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => FilePreviewScreen(
          filename: _messageFilename(message),
          sizeBytes: _messageFileSize(message),
          onDownload: () => downloadMessageFile(message),
          onForward: () => forwardMessage(message),
        ),
      ),
    );
  }

  Future<void> openVideoPreview(UnifiedMessage message) async {
    final url = _messageFileUrl(message);
    if (url.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('没有可播放的视频地址')));
      return;
    }
    await Navigator.push(
      context,
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => VideoPreviewScreen(
          url: url,
          title: _messageFilename(message),
          onDownload: () => downloadMessageFile(message),
          onForward: () => forwardMessage(message),
        ),
      ),
    );
  }

  Future<void> openLink(Uri uri) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => EmbeddedBrowserScreen(url: uri, title: uri.host),
      ),
    );
  }

  Future<void> showMessageActions(UnifiedMessage message) async {
    if (message.msgType == 'recall') return;
    final isFailed = messageSendStates[_messageKey(message)] == 'failed';
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      backgroundColor: BlinStyle.surface(context),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isFailed)
              NativeListRow(
                leading: const NativeIconBox(
                  icon: Icons.refresh_rounded,
                  color: BlinStyle.danger,
                  size: 40,
                ),
                title: '重新发送',
                subtitle: '再次发送这条失败消息',
                minHeight: 58,
                onTap: () => Navigator.pop(sheetContext, 'retry'),
              ),
            if (_canCopyMessage(message))
              NativeListRow(
                leading: const NativeIconBox(
                  icon: Icons.copy_rounded,
                  color: BlinStyle.primary,
                  size: 40,
                ),
                title: '复制',
                minHeight: 58,
                onTap: () => Navigator.pop(sheetContext, 'copy'),
              ),
            if (message.msgType != 'red_packet')
              NativeListRow(
                leading: const NativeIconBox(
                  icon: Icons.forward_rounded,
                  color: BlinStyle.primary,
                  size: 40,
                ),
                title: '转发',
                minHeight: 58,
                onTap: () => Navigator.pop(sheetContext, 'forward'),
              ),
            if (message.isMe && message.messageId > 0)
              NativeListRow(
                leading: const NativeIconBox(
                  icon: Icons.undo_rounded,
                  color: Color(0xFFE05A47),
                  size: 40,
                ),
                title: '撤回',
                minHeight: 58,
                onTap: () => Navigator.pop(sheetContext, 'recall'),
              ),
            NativeListRow(
              leading: const NativeIconBox(
                icon: Icons.delete_outline_rounded,
                color: BlinStyle.danger,
                size: 40,
              ),
              title: '删除消息',
              subtitle: '仅从本机删除这条消息',
              minHeight: 58,
              onTap: () => Navigator.pop(sheetContext, 'delete'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || action == null) return;
    if (action == 'retry') {
      await retryFailedMessage(message);
    } else if (action == 'copy') {
      await Clipboard.setData(ClipboardData(text: _messagePlainText(message)));
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('已复制')));
      }
    } else if (action == 'forward') {
      await forwardMessage(message);
    } else if (action == 'recall') {
      await recallMessage(message);
    } else if (action == 'delete') {
      await deleteMessage(message);
    }
  }

  Future<void> forwardMessage(UnifiedMessage message) async {
    try {
      final friends = await api.getFriends(widget.session.token);
      if (!mounted) return;
      final target = await showModalBottomSheet<UserSearchResult>(
        context: context,
        showDragHandle: true,
        backgroundColor: BlinStyle.surface(context),
        builder: (sheetContext) => SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 4, 16, 10),
                child: Text(
                  '选择转发对象',
                  style: TextStyle(
                    color: BlinStyle.ink,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              for (final friend in friends)
                NativeListRow(
                  leading: AppAvatar(
                    imageUrl: friend.avatar,
                    name: friend.nickname,
                    size: 40,
                  ),
                  title: friend.nickname,
                  subtitle: '@${friend.username}',
                  minHeight: 62,
                  onTap: () => Navigator.pop(sheetContext, friend),
                ),
            ],
          ),
        ),
      );
      if (target == null) return;
      final payload = _forwardPayload(message, target.id);
      await api.sendMessage(
        token: widget.session.token,
        receiverId: target.id,
        content: _messagePlainText(message),
        messageType: _legacyMessageType(message.msgType),
        payload: payload,
      );
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('已转发给 ${target.nickname}')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('转发失败：$e')));
      }
    }
  }

  Future<void> recallMessage(UnifiedMessage message) async {
    try {
      final msg = await api.recallMessage(
        token: widget.session.token,
        messageId: message.messageId,
      );
      if (!mounted) return;
      setState(() {
        final index = messages.indexWhere(
          (item) => item.messageId == message.messageId,
        );
        if (index >= 0) messages[index] = _recalledMessage(messages[index]);
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('撤回失败：$e')));
      }
    }
  }

  int _legacyMessageType(String msgType) {
    if (msgType == 'image') return 1;
    if (msgType == 'transfer') return 2;
    if (msgType == 'file') return 3;
    if (msgType == 'video') return 4;
    if (msgType == 'voice') return 5;
    return 0;
  }

  Future<void> startCall(bool video) async {
    if (!isFriend) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('添加好友后才能发起通话')));
      return;
    }
    try {
      await widget.im.ensureConnected().timeout(const Duration(seconds: 10));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('正在连接消息服务，请稍后再拨打')));
      return;
    }
    await Navigator.push(
      context,
      callScreenRoute(
        CallScreen(
          session: widget.session,
          im: widget.im,
          peerId: widget.peerId,
          peerName: widget.peerName,
          peerAvatar: widget.peerAvatar,
          video: video,
        ),
      ),
    );
    if (mounted) unawaited(load(silent: true));
  }

  Future<void> addCurrentFriend() async {
    try {
      final msg = await api.addFriend(
        widget.session.token,
        widget.peerId,
        message: '你好，我想添加你为好友',
      );
      await ConversationPreferences.setPendingFriendRequest(
        widget.session.id,
        widget.peerId,
        true,
      );
      if (mounted) {
        setState(() => friendRequestPending = true);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(msg)));
      }
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> deleteCurrentFriend() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('删除好友'),
        content: Text('确定要删除 ${widget.peerName} 吗？删除后需要重新添加好友才能发送附件和发起通话。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final msg = await api.deleteFriend(widget.session.token, widget.peerId);
      await ConversationPreferences.setPendingFriendRequest(
        widget.session.id,
        widget.peerId,
        false,
      );
      if (mounted) {
        setState(() {
          isFriend = false;
          friendRequestPending = false;
          messages = [];
          historyPage = 1;
          hasMoreHistory = false;
          readyToShowMessages = true;
        });
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(msg)));
        Navigator.pop(context, {'deletedUserId': widget.peerId});
      }
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  void addEmoji(String emoji) {
    final start = input.selection.start < 0
        ? input.text.length
        : input.selection.start;
    final end = input.selection.end < 0
        ? input.text.length
        : input.selection.end;
    input.text = input.text.replaceRange(start, end, emoji);
    final offset = start + emoji.length;
    input.selection = TextSelection.collapsed(offset: offset);
  }

  void toggleEmojiPanel() {
    final shouldStickToBottom = !showEmojiPanel && _isNearBottom(distance: 220);
    FocusScope.of(context).unfocus();
    setState(() {
      showEmojiPanel = !showEmojiPanel;
      if (showEmojiPanel) voiceInputMode = false;
    });
    if (shouldStickToBottom) _settleToBottomAfterLayout();
  }

  void toggleVoiceInputMode() {
    if (!widget.voiceMessageEnabled) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('语音消息已被后台关闭')));
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      voiceInputMode = !voiceInputMode;
      if (voiceInputMode) showEmojiPanel = false;
    });
    _settleToBottomAfterLayout();
  }

  Future<void> locateMessage(UnifiedMessage target) async {
    if (_isMessageDeleted(target)) return;
    final targetKeys = _messageKeys(target);
    final exists = messages.any(
      (m) => _messageKeys(m).any(targetKeys.contains),
    );
    if (!exists) {
      setState(() {
        messages = _mergeTimelineMessages(messages, [target]);
        _syncReadStatesFromMessages(messages);
      });
    }
    await _waitForLayoutFrame();
    if (!mounted || !scroll.hasClients) return;
    final timeline = _timelineItems();
    final timelineIndex = timeline.indexWhere((item) {
      if (item is! _PeerTimelineMessage) return false;
      return _messageKeys(item.message).any(targetKeys.contains);
    });
    if (timelineIndex < 0) return;
    final showHistorySlot =
        messages.isNotEmpty && (hasMoreHistory || loadingHistory);
    final totalItems =
        timeline.length + (showHistorySlot ? 1 : 0) + (peerTyping ? 1 : 0);
    final visualIndex = timelineIndex + (showHistorySlot ? 1 : 0);
    final reversedIndex = totalItems - 1 - visualIndex;
    final targetOffset = (reversedIndex * 82.0).clamp(
      0.0,
      scroll.position.maxScrollExtent,
    );
    suppressHistoryDuringProgrammaticScroll = true;
    _blockHistoryLoad(const Duration(milliseconds: 900));
    await scroll.animateTo(
      targetOffset,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
    Future<void>.delayed(const Duration(milliseconds: 220), () {
      if (mounted) suppressHistoryDuringProgrammaticScroll = false;
    });
  }

  void _bottom({Duration delay = const Duration(milliseconds: 80)}) {
    final generation = ++bottomSettleGeneration;
    Future.delayed(delay, () {
      if (!mounted || generation != bottomSettleGeneration) return;
      _stickToBottom();
      unawaited(_settleToBottomAfterLayout());
    });
  }

  bool get _historyLoadBlocked =>
      DateTime.now().isBefore(historyLoadBlockedUntil);

  void _blockHistoryLoad([
    Duration duration = const Duration(milliseconds: 900),
  ]) {
    historyLoadBlockedUntil = DateTime.now().add(duration);
  }

  void _handleInputFocus() {
    _blockHistoryLoad();
    stickToBottomDuringKeyboard = _isNearBottom(distance: 220);
    if (stickToBottomDuringKeyboard) {
      _settleKeyboardBottom();
    }
  }

  bool _isNearBottom({double distance = 120}) {
    if (!scroll.hasClients) return true;
    return scroll.position.pixels <= distance;
  }

  Future<void> _waitForLayoutFrame() {
    final completer = Completer<void>();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!completer.isCompleted) completer.complete();
    });
    return completer.future;
  }

  void _jumpToBottomAfterLayout() {
    unawaited(_settleToBottomAfterLayout(animated: false));
  }

  Future<void> _settleToBottomAfterLayout({bool animated = false}) async {
    final generation = ++bottomSettleGeneration;
    suppressHistoryDuringProgrammaticScroll = true;
    _blockHistoryLoad(const Duration(milliseconds: 700));
    for (var i = 0; i < 4; i++) {
      await _waitForLayoutFrame();
      if (!mounted || generation != bottomSettleGeneration) return;
      _stickToBottom(animated: animated && i == 3);
      await Future<void>.delayed(const Duration(milliseconds: 24));
    }
    Future<void>.delayed(const Duration(milliseconds: 180), () {
      if (mounted && generation == bottomSettleGeneration) {
        suppressHistoryDuringProgrammaticScroll = false;
      }
    });
  }

  void _settleKeyboardBottom() {
    final generation = ++keyboardSettleGeneration;
    void schedule(Duration delay) {
      Future.delayed(delay, () {
        if (!mounted || generation != keyboardSettleGeneration) return;
        _jumpToBottomAfterLayout();
      });
    }

    schedule(Duration.zero);
    schedule(const Duration(milliseconds: 80));
    schedule(const Duration(milliseconds: 180));
    schedule(const Duration(milliseconds: 320));
  }

  void _stickToBottom({bool animated = true}) {
    if (!scroll.hasClients) return;
    const target = 0.0;
    if (animated) {
      scroll.animateTo(
        target,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
      );
    } else {
      scroll.jumpTo(target);
    }
  }

  List<_PeerTimelineItem> _timelineItems() {
    final items = <_PeerTimelineItem>[];
    String? lastDate;
    for (final message in messages) {
      if (_isHiddenChatEvent(message)) continue;
      final date = _dateLabel(message.createTime);
      if (date != lastDate) {
        items.add(_PeerTimelineDate(date));
        lastDate = date;
      }
      items.add(_PeerTimelineMessage(message));
    }
    return items;
  }

  String _dateLabel(DateTime time) {
    final now = DateTime.now();
    if (now.year == time.year &&
        now.month == time.month &&
        now.day == time.day) {
      return '今天';
    }
    final yesterday = now.subtract(const Duration(days: 1));
    if (yesterday.year == time.year &&
        yesterday.month == time.month &&
        yesterday.day == time.day) {
      return '昨天';
    }
    if (now.year == time.year) {
      return '${time.month.toString().padLeft(2, '0')}-${time.day.toString().padLeft(2, '0')}';
    }
    return '${time.year}-${time.month.toString().padLeft(2, '0')}-${time.day.toString().padLeft(2, '0')}';
  }

  @override
  void didChangeMetrics() {
    super.didChangeMetrics();
    _blockHistoryLoad();
    if (inputFocus.hasFocus) {
      if (stickToBottomDuringKeyboard || _isNearBottom(distance: 220)) {
        stickToBottomDuringKeyboard = true;
        _settleKeyboardBottom();
      }
    } else {
      stickToBottomDuringKeyboard = false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(load(silent: true));
      unawaited(refreshPeerOnline());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_sendTypingStopped());
    onlineTimer?.cancel();
    connectionSub?.cancel();
    presenceSub?.cancel();
    typingSub?.cancel();
    readReceiptSub?.cancel();
    sub?.cancel();
    screenshotSub?.cancel();
    typingHideTimer?.cancel();
    voiceTimer?.cancel();
    unawaited(recorder.dispose());
    input.dispose();
    inputFocus.dispose();
    scroll.dispose();
    super.dispose();
  }

  Future<void> openPeerInfo() async {
    final action = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) => _PeerChatInfoScreen(
          session: widget.session,
          peerId: widget.peerId,
          name: widget.peerName,
          avatar: widget.peerAvatar,
          online: peerOnline,
          isFriend: isFriend,
          muteNotifications: muteNotifications,
          pinnedChat: pinnedChat,
          onSearchHistory: openPeerHistorySearch,
          onMuteChanged: (value) => unawaited(setConversationMuted(value)),
          onPinChanged: (value) => unawaited(setConversationPinned(value)),
          onClearHistory: clearPeerChatHistory,
        ),
      ),
    );
    unawaited(loadConversationPreferences());
    if (!mounted || action == null) return;
    if (action == 'message') {
      return;
    } else if (action == 'add_friend') {
      await addCurrentFriend();
    } else if (action == 'voice_call') {
      await startCall(false);
    } else if (action == 'video_call') {
      await startCall(true);
    } else if (action == 'delete_friend') {
      await deleteCurrentFriend();
    }
  }

  Future<void> openPeerHistorySearch() async {
    final selected = await Navigator.push<UnifiedMessage>(
      context,
      MaterialPageRoute(
        builder: (_) => ChatHistorySearchScreen(
          title: widget.peerName,
          subtitle: '查找与 ${widget.peerName} 的聊天记录',
          loadMessages: (keyword) async {
            final all = <UnifiedMessage>[];
            for (var page = 1; page <= 8; page++) {
              final list = await api.getChatLog(
                token: widget.session.token,
                receiverId: widget.peerId,
                myId: widget.session.id,
                page: page,
                limit: 50,
              );
              if (list.isEmpty) break;
              all.addAll(
                list.where(
                  (m) => !_isHiddenChatEvent(m) && !_isMessageDeleted(m),
                ),
              );
              if (list.length < 50) break;
            }
            return all;
          },
        ),
      ),
    );
    if (selected != null) await locateMessage(selected);
  }

  @override
  Widget build(BuildContext context) {
    final timeline = _timelineItems();
    final showHistorySlot =
        messages.isNotEmpty && (hasMoreHistory || loadingHistory);
    return Scaffold(
      resizeToAvoidBottomInset: true,
      backgroundColor: BlinStyle.bg,
      body: PageBackdrop(
        child: Column(
          children: [
            _ChatHeader(
              name: widget.peerName,
              avatar: widget.peerAvatar,
              online: peerOnline,
              isFriend: isFriend,
              friendRequestPending: friendRequestPending,
              onAddFriend: addCurrentFriend,
              onOpenInfo: () => unawaited(openPeerInfo()),
              onVoiceCall: () => unawaited(startCall(false)),
              onVideoCall: () => unawaited(startCall(true)),
            ),
            Expanded(
              child: ListView.builder(
                controller: scroll,
                reverse: true,
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: const EdgeInsets.fromLTRB(
                  BlinStyle.pagePadding,
                  12,
                  BlinStyle.pagePadding,
                  18,
                ),
                itemCount:
                    timeline.length +
                    (showHistorySlot ? 1 : 0) +
                    (peerTyping ? 1 : 0),
                itemBuilder: (_, i) {
                  final totalItems =
                      timeline.length +
                      (showHistorySlot ? 1 : 0) +
                      (peerTyping ? 1 : 0);
                  final visualIndex = totalItems - 1 - i;
                  if (showHistorySlot) {
                    if (peerTyping && visualIndex == timeline.length + 1) {
                      return const _TypingBubble();
                    }
                    if (visualIndex != 0) {
                      final item = timeline[visualIndex - 1];
                      if (item is _PeerTimelineDate) {
                        return _PeerDatePill(text: item.text);
                      }
                      final message = (item as _PeerTimelineMessage).message;
                      return _Bubble(
                        m: message,
                        textFontSize: chatFontSize,
                        sendState: messageSendStates[_messageKey(message)],
                        onRetry: () => unawaited(retryFailedMessage(message)),
                        onPreviewImage: () => openImagePreview(message),
                        onPreviewVideo: () => openVideoPreview(message),
                        onPreviewFile: () => openFilePreview(message),
                        onCallRecordTap: (video) => startCall(video),
                        onOpenLink: openLink,
                        onAction: showMessageActions,
                        onTransferAction: (message, accept) =>
                            updateTransferStatus(message, accept: accept),
                      );
                    }
                    return _PeerHistoryLoadHint(loading: loadingHistory);
                  }
                  if (peerTyping && visualIndex == timeline.length) {
                    return const _TypingBubble();
                  }
                  final item = timeline[visualIndex];
                  if (item is _PeerTimelineDate) {
                    return _PeerDatePill(text: item.text);
                  }
                  final message = (item as _PeerTimelineMessage).message;
                  return _Bubble(
                    m: message,
                    textFontSize: chatFontSize,
                    sendState: messageSendStates[_messageKey(message)],
                    onRetry: () => unawaited(retryFailedMessage(message)),
                    onPreviewImage: () => openImagePreview(message),
                    onPreviewVideo: () => openVideoPreview(message),
                    onPreviewFile: () => openFilePreview(message),
                    onCallRecordTap: (video) => startCall(video),
                    onOpenLink: openLink,
                    onAction: showMessageActions,
                    onTransferAction: (message, accept) =>
                        updateTransferStatus(message, accept: accept),
                    onRedPacket: (message) => unawaited(openRedPacket(message)),
                  );
                },
              ),
            ),
            _Composer(
              controller: input,
              focusNode: inputFocus,
              sendingAttachment: sendingAttachment,
              voiceEnabled: widget.voiceMessageEnabled,
              sendingVoice: sendingVoice,
              recordingVoice: recordingVoice,
              voiceDurationSeconds: voiceRecordingSeconds(voiceStartedAt),
              showEmojiPanel: showEmojiPanel,
              voiceInputMode: voiceInputMode,
              onSend: send,
              onEmoji: toggleEmojiPanel,
              onEmojiSelected: addEmoji,
              onGifSelected: (sticker) => unawaited(sendGifSticker(sticker)),
              onImage: () => unawaited(sendAttachment(mediaType: 'image')),
              onVideo: () => unawaited(sendAttachment(mediaType: 'video')),
              onCapture: () => unawaited(captureAttachment()),
              onFile: () => unawaited(sendAttachment(mediaType: 'file')),
              onTransfer: () => unawaited(sendTransfer()),
              onRedPacket: () => unawaited(sendRedPacket()),
              onVoice: toggleVoiceInputMode,
              onVoicePressStart: () => unawaited(_startVoiceRecording()),
              onVoicePressEnd: () =>
                  unawaited(_finishVoiceRecording(send: true)),
              onVoicePressCancel: () =>
                  unawaited(_finishVoiceRecording(send: false)),
            ),
          ],
        ),
      ),
    );
  }
}

int voiceRecordingSeconds(DateTime? startedAt) {
  if (startedAt == null) return 0;
  return DateTime.now().difference(startedAt).inSeconds;
}

Future<String> voiceRecordPath(String filename) async {
  if (kIsWeb) return filename;
  final dir = await getTemporaryDirectory();
  return '${dir.path}/$filename';
}

Future<List<int>> readVoiceRecordBytes(String path) async {
  final normalizedPath = !kIsWeb && path.startsWith('file://')
      ? Uri.parse(path).toFilePath()
      : path;
  final file = XFile(normalizedPath);
  final length = await file.length();
  if (length <= 0) throw ApiException('录音文件为空');
  return file.readAsBytes();
}

String formatVoiceDuration(int seconds) {
  final safe = seconds < 1 ? 1 : seconds;
  if (safe < 60) return '$safe"';
  final minutes = safe ~/ 60;
  final rest = safe % 60;
  return '$minutes:${rest.toString().padLeft(2, '0')}';
}

class _PeerChatInfoScreen extends StatefulWidget {
  final UserSession session;
  final int peerId;
  final String name;
  final String avatar;
  final ImOnlineStatus? online;
  final bool isFriend;
  final bool muteNotifications;
  final bool pinnedChat;
  final VoidCallback onSearchHistory;
  final ValueChanged<bool> onMuteChanged;
  final ValueChanged<bool> onPinChanged;
  final VoidCallback onClearHistory;

  const _PeerChatInfoScreen({
    required this.session,
    required this.peerId,
    required this.name,
    required this.avatar,
    required this.online,
    required this.isFriend,
    required this.muteNotifications,
    required this.pinnedChat,
    required this.onSearchHistory,
    required this.onMuteChanged,
    required this.onPinChanged,
    required this.onClearHistory,
  });

  @override
  State<_PeerChatInfoScreen> createState() => _PeerChatInfoScreenState();
}

class _PeerChatInfoScreenState extends State<_PeerChatInfoScreen> {
  late bool muteNotifications = widget.muteNotifications;
  late bool pinnedChat = widget.pinnedChat;

  void _toast(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> openProfile() async {
    final action = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) => _PeerProfileScreen(
          session: widget.session,
          peerId: widget.peerId,
          fallbackName: widget.name,
          fallbackAvatar: widget.avatar,
          online: widget.online,
          isFriend: widget.isFriend,
        ),
      ),
    );
    if (!mounted || action == null) return;
    Navigator.pop(context, action);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: PageBackdrop(
      child: Column(
        children: [
          AppTopBar(
            title: '聊天信息',
            subtitle: widget.name,
            leading: IconButton(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.arrow_back_rounded),
            ),
          ),
          Expanded(
            child: ModuleContent(
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  SoftCard(
                    child: InfoLine(
                      avatar: GestureDetector(
                        onTap: openProfile,
                        child: AppAvatar(
                          imageUrl: widget.avatar,
                          name: widget.name,
                          size: 62,
                          showOnline: widget.online != null,
                          online: widget.online?.online == true,
                        ),
                      ),
                      title: widget.name,
                      subtitle: widget.isFriend ? '点击头像查看个人主页' : '还不是好友',
                      trailing: widget.isFriend
                          ? const Icon(
                              Icons.chevron_right_rounded,
                              color: BlinStyle.subtle,
                            )
                          : FilledButton.icon(
                              onPressed: () =>
                                  Navigator.pop(context, 'add_friend'),
                              icon: const Icon(Icons.person_add_alt_1_rounded),
                              label: const Text('添加'),
                            ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _InfoSection(
                    children: [
                      _InfoRow(
                        icon: Icons.manage_search_rounded,
                        title: '查找聊天记录',
                        onTap: widget.onSearchHistory,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _InfoSection(
                    children: [
                      _InfoSwitchRow(
                        icon: Icons.notifications_off_outlined,
                        title: '消息免打扰',
                        value: muteNotifications,
                        onChanged: (v) {
                          setState(() => muteNotifications = v);
                          widget.onMuteChanged(v);
                        },
                      ),
                      _InfoSwitchRow(
                        icon: Icons.push_pin_outlined,
                        title: '置顶聊天',
                        value: pinnedChat,
                        onChanged: (v) {
                          setState(() => pinnedChat = v);
                          widget.onPinChanged(v);
                        },
                      ),
                      _InfoRow(
                        icon: Icons.wallpaper_outlined,
                        title: '聊天背景',
                        trailing: '默认背景',
                        onTap: () => _toast('聊天背景设置入口已预留'),
                      ),
                      _InfoRow(
                        icon: Icons.report_gmailerrorred_outlined,
                        title: '投诉',
                        onTap: () => _toast('投诉入口已预留'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _InfoSection(
                    children: [
                      _InfoRow(
                        icon: Icons.delete_outline_rounded,
                        title: '清空聊天记录',
                        danger: true,
                        onTap: () async {
                          final ok = await showDialog<bool>(
                            context: context,
                            builder: (_) => AlertDialog(
                              title: const Text('清空聊天记录'),
                              content: const Text(
                                '确定要清空当前聊天记录吗？清空范围会按后台应用配置生效，会话入口会继续保留。',
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () =>
                                      Navigator.pop(context, false),
                                  child: const Text('取消'),
                                ),
                                FilledButton(
                                  onPressed: () => Navigator.pop(context, true),
                                  child: const Text('清空'),
                                ),
                              ],
                            ),
                          );
                          if (ok == true) widget.onClearHistory();
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class _PeerProfileScreen extends StatefulWidget {
  final UserSession session;
  final int peerId;
  final String fallbackName;
  final String fallbackAvatar;
  final ImOnlineStatus? online;
  final bool isFriend;

  const _PeerProfileScreen({
    required this.session,
    required this.peerId,
    required this.fallbackName,
    required this.fallbackAvatar,
    required this.online,
    required this.isFriend,
  });

  @override
  State<_PeerProfileScreen> createState() => _PeerProfileScreenState();
}

class _PeerProfileScreenState extends State<_PeerProfileScreen> {
  final api = const ApiService();
  UserPublicProfile? profile;
  AppUserInfoConfig userInfoConfig = const AppUserInfoConfig(
    showUserId: false,
    usernameChangeEnabled: true,
    usernameChangeIntervalDays: 30,
  );
  bool loading = true;
  String? error;

  @override
  void initState() {
    super.initState();
    unawaited(load());
  }

  Future<void> load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final result = await Future.wait<Object>([
        api.getUserInformation(
          token: widget.session.token,
          userId: widget.peerId,
        ),
        api.getUserInfoConfig(),
      ]);
      if (!mounted) return;
      setState(() {
        profile = result[0] as UserPublicProfile;
        userInfoConfig = result[1] as AppUserInfoConfig;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  String get displayName {
    final value = profile?.nickname.trim() ?? '';
    return value.isNotEmpty ? value : widget.fallbackName;
  }

  String get avatar {
    final value = profile?.avatar.trim() ?? '';
    return value.isNotEmpty ? value : widget.fallbackAvatar;
  }

  String get username {
    final value = profile?.username.trim() ?? '';
    return value.isNotEmpty ? '@$value' : '';
  }

  @override
  Widget build(BuildContext context) {
    final p = profile;
    final signature = p?.signature.trim() ?? '';
    final sexName = p?.sexName.trim() ?? '';
    final createTime = p?.createTime.trim() ?? '';
    final level = p?.level.trim() ?? '';
    return Scaffold(
      body: PageBackdrop(
        child: Column(
          children: [
            AppTopBar(
              title: '个人主页',
              subtitle: displayName,
              leading: IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.arrow_back_rounded),
              ),
            ),
            Expanded(
              child: ModuleContent(
                child: ListView(
                  padding: EdgeInsets.zero,
                  children: [
                    SoftCard(
                      child: InfoLine(
                        avatar: _ProfileAvatar(
                          avatar: avatar,
                          name: displayName,
                        ),
                        title: displayName,
                        subtitle: [
                          if (username.isNotEmpty) username,
                          if (userInfoConfig.showUserId) 'ID ${widget.peerId}',
                        ].join(' · '),
                        meta: signature.isNotEmpty ? signature : null,
                      ),
                    ),
                    if (loading)
                      const Padding(
                        padding: EdgeInsets.only(top: 10),
                        child: LinearProgressIndicator(minHeight: 2),
                      )
                    else if (error != null)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(4, 12, 4, 0),
                        child: Text(
                          '资料暂时无法更新，已显示本地信息',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    const SizedBox(height: 12),
                    if (signature.isNotEmpty ||
                        sexName.isNotEmpty ||
                        createTime.isNotEmpty ||
                        level.isNotEmpty)
                      _InfoSection(
                        children: [
                          if (signature.isNotEmpty)
                            _InfoRow(
                              icon: Icons.edit_note_rounded,
                              title: '个性签名',
                              trailing: signature,
                            ),
                          if (sexName.isNotEmpty)
                            _InfoRow(
                              icon: Icons.person_outline_rounded,
                              title: '性别',
                              trailing: sexName,
                            ),
                          if (level.isNotEmpty)
                            _InfoRow(
                              icon: Icons.workspace_premium_outlined,
                              title: '等级',
                              trailing: level,
                            ),
                          if (createTime.isNotEmpty)
                            _InfoRow(
                              icon: Icons.event_available_outlined,
                              title: '加入时间',
                              trailing: createTime,
                            ),
                        ],
                      ),
                    const SizedBox(height: 12),
                    _InfoSection(
                      children: [
                        _InfoRow(
                          icon: Icons.chat_bubble_outline_rounded,
                          title: '发消息',
                          onTap: () => Navigator.pop(context, 'message'),
                        ),
                        if (widget.isFriend) ...[
                          _InfoRow(
                            icon: Icons.call_outlined,
                            title: '语音通话',
                            onTap: () => Navigator.pop(context, 'voice_call'),
                          ),
                          _InfoRow(
                            icon: Icons.videocam_outlined,
                            title: '视频通话',
                            onTap: () => Navigator.pop(context, 'video_call'),
                          ),
                        ] else
                          _InfoRow(
                            icon: Icons.person_add_alt_1_outlined,
                            title: '添加到通讯录',
                            onTap: () => Navigator.pop(context, 'add_friend'),
                          ),
                      ],
                    ),
                    if (widget.isFriend) ...[
                      const SizedBox(height: 12),
                      _InfoSection(
                        children: [
                          _InfoRow(
                            icon: Icons.person_remove_outlined,
                            title: '删除好友',
                            danger: true,
                            onTap: () =>
                                Navigator.pop(context, 'delete_friend'),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProfileAvatar extends StatelessWidget {
  final String avatar;
  final String name;
  const _ProfileAvatar({required this.avatar, required this.name});

  @override
  Widget build(BuildContext context) =>
      AppAvatar(imageUrl: avatar, name: name, size: 72);
}

class _InfoSection extends StatelessWidget {
  final List<Widget> children;
  const _InfoSection({required this.children});

  @override
  Widget build(BuildContext context) => SoftCard(
    padding: EdgeInsets.zero,
    child: Column(
      children: [
        for (var i = 0; i < children.length; i++) ...[
          children[i],
          if (i != children.length - 1)
            Divider(
              height: 1,
              thickness: 1,
              indent: 68,
              color: BlinStyle.hairline(context, .55).color,
            ),
        ],
      ],
    ),
  );
}

class _InfoRow extends StatelessWidget {
  final IconData? icon;
  final String title;
  final String? trailing;
  final VoidCallback? onTap;
  final bool danger;
  const _InfoRow({
    this.icon,
    required this.title,
    this.trailing,
    this.onTap,
    this.danger = false,
  });

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: Container(
      constraints: const BoxConstraints(minHeight: 60),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          if (icon != null) ...[
            NativeIconBox(
              icon: icon!,
              color: danger ? BlinStyle.danger : BlinStyle.primary,
              size: 36,
            ),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                color: danger
                    ? BlinStyle.danger
                    : BlinStyle.textPrimary(context),
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          if (trailing != null)
            Text(
              trailing!,
              style: const TextStyle(color: BlinStyle.subtle, fontSize: 13),
            ),
          const SizedBox(width: 8),
          const Icon(
            Icons.chevron_right_rounded,
            color: BlinStyle.subtle,
            size: 22,
          ),
        ],
      ),
    ),
  );
}

class _InfoSwitchRow extends StatelessWidget {
  final IconData? icon;
  final String title;
  final bool value;
  final ValueChanged<bool> onChanged;
  const _InfoSwitchRow({
    this.icon,
    required this.title,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(minHeight: 60),
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
    child: Row(
      children: [
        if (icon != null) ...[
          NativeIconBox(icon: icon!, color: BlinStyle.primary, size: 36),
          const SizedBox(width: 12),
        ],
        Expanded(
          child: Text(
            title,
            style: const TextStyle(
              color: BlinStyle.ink,
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        Switch(
          value: value,
          onChanged: onChanged,
          activeThumbColor: Colors.white,
          activeTrackColor: BlinStyle.primary,
        ),
      ],
    ),
  );
}

sealed class _PeerTimelineItem {
  const _PeerTimelineItem();
}

class _PeerTimelineDate extends _PeerTimelineItem {
  final String text;
  const _PeerTimelineDate(this.text);
}

class _PeerTimelineMessage extends _PeerTimelineItem {
  final UnifiedMessage message;
  const _PeerTimelineMessage(this.message);
}

class _PeerDatePill extends StatelessWidget {
  final String text;
  const _PeerDatePill({required this.text});

  @override
  Widget build(BuildContext context) => Center(
    child: Container(
      margin: const EdgeInsets.symmetric(vertical: 9),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: BlinStyle.iconSurface(context),
        borderRadius: BorderRadius.circular(BlinStyle.buttonRadius),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: BlinStyle.subtle,
          fontSize: 12,
          fontWeight: FontWeight.w400,
        ),
      ),
    ),
  );
}

class _PeerHistoryLoadHint extends StatelessWidget {
  final bool loading;
  const _PeerHistoryLoadHint({required this.loading});

  @override
  Widget build(BuildContext context) => SizedBox(
    height: loading ? 32 : 0,
    child: Center(
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 120),
        child: loading
            ? const SizedBox(
                key: ValueKey('loading'),
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const SizedBox.shrink(key: ValueKey('idle')),
      ),
    ),
  );
}

class _ChatHeader extends StatelessWidget {
  final String name;
  final String avatar;
  final ImOnlineStatus? online;
  final bool isFriend;
  final bool friendRequestPending;
  final VoidCallback onAddFriend;
  final VoidCallback onOpenInfo;
  final VoidCallback onVoiceCall;
  final VoidCallback onVideoCall;
  const _ChatHeader({
    required this.name,
    required this.avatar,
    required this.online,
    required this.isFriend,
    required this.friendRequestPending,
    required this.onAddFriend,
    required this.onOpenInfo,
    required this.onVoiceCall,
    required this.onVideoCall,
  });

  Future<void> _showMore(BuildContext context) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: .22),
      showDragHandle: false,
      builder: (sheetContext) => CallActionSheet(
        title: '选择通话方式',
        subtitle: '和 $name 发起实时通话',
        voiceTitle: '语音通话',
        voiceSubtitle: '低流量，适合快速沟通',
        videoTitle: '视频通话',
        videoSubtitle: '实时画面，适合面对面沟通',
        onVoice: () => Navigator.pop(sheetContext, 'voice'),
        onVideo: () => Navigator.pop(sheetContext, 'video'),
      ),
    );
    if (!context.mounted || action == null) return;
    if (action == 'voice') {
      onVoiceCall();
    } else if (action == 'video') {
      onVideoCall();
    }
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    bottom: false,
    child: Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
      decoration: BoxDecoration(
        color: BlinStyle.page(context),
        border: Border(
          bottom: BorderSide(color: BlinStyle.hairline(context, .55).color),
        ),
      ),
      child: Row(
        children: [
          ShellAction(
            icon: Icons.arrow_back_rounded,
            onTap: () => Navigator.pop(context),
            tooltip: '返回',
          ),
          const SizedBox(width: 10),
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onOpenInfo,
              child: Row(
                children: [
                  AppAvatar(
                    imageUrl: avatar,
                    name: name,
                    size: 42,
                    online: online?.online == true,
                    showOnline: online != null,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        if (online?.online == true) ...[
                          const SizedBox(height: 3),
                          Text(
                            '在线',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (!isFriend)
            TextButton(
              onPressed: friendRequestPending ? null : onAddFriend,
              child: Text(friendRequestPending ? '待同意' : '加好友'),
            )
          else
            ShellAction(
              icon: Icons.more_horiz_rounded,
              onTap: () => unawaited(_showMore(context)),
              tooltip: '通话',
            ),
        ],
      ),
    ),
  );
}

class _Bubble extends StatelessWidget {
  final UnifiedMessage m;
  final double textFontSize;
  final String? sendState;
  final VoidCallback? onPreviewImage;
  final VoidCallback? onPreviewVideo;
  final VoidCallback? onPreviewFile;
  final VoidCallback? onRetry;
  final ValueChanged<bool>? onCallRecordTap;
  final ValueChanged<Uri>? onOpenLink;
  final ValueChanged<UnifiedMessage>? onAction;
  final Future<void> Function(UnifiedMessage message, bool accept)?
  onTransferAction;
  final ValueChanged<UnifiedMessage>? onRedPacket;
  const _Bubble({
    required this.m,
    required this.textFontSize,
    this.sendState,
    this.onPreviewImage,
    this.onPreviewVideo,
    this.onPreviewFile,
    this.onRetry,
    this.onCallRecordTap,
    this.onOpenLink,
    this.onAction,
    this.onTransferAction,
    this.onRedPacket,
  });
  @override
  Widget build(BuildContext context) {
    if (m.msgType == 'recall') {
      return _RecallPill(text: '${m.content['text'] ?? '消息已撤回'}');
    }
    if (m.msgType == 'transfer_receipt') {
      final text = '${m.content['text'] ?? m.preview}'.trim();
      return _RecallPill(text: text.isEmpty ? '转账状态已更新' : text);
    }
    if (m.msgType == 'screenshot') {
      return _RecallPill(text: '${m.content['text'] ?? m.preview}');
    }
    final me = m.isMe;
    final isImage = m.msgType == 'image';
    final isVideo = m.msgType == 'video';
    final isRedPacket = m.msgType == 'red_packet';
    final isTransfer = m.msgType == 'transfer';
    final isMedia = isImage || isVideo;
    final bubble = Container(
      constraints: BoxConstraints(
        maxWidth:
            MediaQuery.sizeOf(context).width *
            ((isRedPacket || isTransfer) ? .78 : (isMedia ? .70 : .70)),
      ),
      margin: EdgeInsets.fromLTRB(me ? 56 : 2, 4, me ? 2 : 56, 4),
      padding: isMedia || isRedPacket || isTransfer
          ? EdgeInsets.zero
          : const EdgeInsets.fromLTRB(14, 10, 14, 10),
      decoration: isMedia || isRedPacket || isTransfer
          ? null
          : BoxDecoration(
              color: me
                  ? BlinStyle.primary.withValues(alpha: .11)
                  : BlinStyle.surface(context),
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(18),
                topRight: const Radius.circular(18),
                bottomLeft: Radius.circular(me ? 18 : 4),
                bottomRight: Radius.circular(me ? 4 : 18),
              ),
              border: Border.all(
                color: me
                    ? BlinStyle.primary.withValues(alpha: .18)
                    : BlinStyle.hairline(context, .62).color,
              ),
            ),
      child: _content(context, me),
    );
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: sendState == 'failed'
          ? onRetry
          : isImage
          ? onPreviewImage
          : isVideo
          ? onPreviewVideo
          : isRedPacket
          ? () => onRedPacket?.call(m)
          : null,
      onLongPress: onAction == null ? null : () => onAction!(m),
      child: Align(
        alignment: me ? Alignment.centerRight : Alignment.centerLeft,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: me
              ? [
                  bubble,
                  Padding(
                    padding: const EdgeInsets.only(right: 8, bottom: 8),
                    child: _SendStateIcon(state: sendState ?? 'success'),
                  ),
                ]
              : [bubble],
        ),
      ),
    );
  }

  Widget _content(BuildContext context, bool me) {
    const color = BlinStyle.ink;
    final fontSize = ChatDisplayPreferences.normalizeChatFontSize(textFontSize);
    if (m.msgType == 'image') {
      final text = '${m.content['text'] ?? ''}';
      final url = firstMediaUrl([
        m.content['url'],
        m.content['file_url'],
        m.content['image_path'],
        m.content['file_path'],
        m.content['path'],
        m.content['src'],
      ]);
      final isGif = isGifImagePayload(m.content, url);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (url.isNotEmpty) _ChatImagePreview(url: url, isGif: isGif),
          if (text.isNotEmpty && text != '[图片]' && text != '[GIF]') ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.fromLTRB(12, 9, 12, 9),
              decoration: BoxDecoration(
                color: me
                    ? BlinStyle.primary.withValues(alpha: .10)
                    : BlinStyle.surface(context),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: BlinStyle.hairline(context, .58).color,
                ),
              ),
              child: _MaybeLinkText(
                text: text,
                style: TextStyle(
                  color: color,
                  fontSize: fontSize,
                  height: 1.35,
                  fontWeight: FontWeight.w400,
                ),
                onOpenLink: onOpenLink,
              ),
            ),
          ],
        ],
      );
    }
    if (m.msgType == 'video') {
      final rawName = '${m.content['name'] ?? '视频'}';
      final name = rawName.startsWith('[视频]')
          ? rawName.replaceFirst('[视频]', '').trim()
          : rawName;
      final url = firstMediaUrl([
        m.content['url'],
        m.content['file_url'],
        m.content['video_url'],
        m.content['video_path'],
        m.content['file_path'],
      ]);
      final videoText = '${m.content['text'] ?? ''}';
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: url.isEmpty ? null : onPreviewVideo,
            borderRadius: BorderRadius.circular(16),
            child: _VideoCover(url: url),
          ),
          const SizedBox.shrink(),
          if (videoText.isNotEmpty &&
              videoText != '[视频]' &&
              videoText != '[视频] $name')
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Container(
                padding: const EdgeInsets.fromLTRB(12, 9, 12, 9),
                decoration: BoxDecoration(
                  color: me
                      ? BlinStyle.primary.withValues(alpha: .10)
                      : BlinStyle.surface(context),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: BlinStyle.hairline(context, .58).color,
                  ),
                ),
                child: _MaybeLinkText(
                  text: videoText,
                  style: TextStyle(
                    color: color.withValues(alpha: .86),
                    fontSize: fontSize,
                    height: 1.35,
                    fontWeight: FontWeight.w400,
                  ),
                  onOpenLink: onOpenLink,
                ),
              ),
            ),
        ],
      );
    }
    if (m.msgType == 'emoji') {
      final emojiText =
          '${m.content['emoji'] ?? m.content['text'] ?? m.preview}';
      final large =
          emojiText.runes.length <= 8 && emojiText.trim().length <= 16;
      final largeEmojiSize = (fontSize * 2.4).clamp(30.0, 42.0).toDouble();
      return _MaybeLinkText(
        text: emojiText,
        style: TextStyle(
          color: color,
          fontSize: large ? largeEmojiSize : fontSize,
          height: large ? 1.1 : 1.35,
          fontWeight: FontWeight.w400,
        ),
        onOpenLink: onOpenLink,
      );
    }
    if (m.msgType == 'file') {
      final name = '${m.content['name'] ?? m.content['file_name'] ?? '文件'}';
      final size = int.tryParse('${m.content['size'] ?? 0}') ?? 0;
      final sizeText = size > 0
          ? ' · ${(size / 1024).toStringAsFixed(size > 1024 * 1024 ? 1 : 0)}${size > 1024 * 1024 ? 'MB' : 'KB'}'
          : '';
      return InkWell(
        onTap: onPreviewFile,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: (me ? Colors.white : BlinStyle.primary).withValues(
                    alpha: me ? .18 : .12,
                  ),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Icon(
                  Icons.insert_drive_file_outlined,
                  color: color,
                  size: 22,
                ),
              ),
              const SizedBox(width: 10),
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: color,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    if (sizeText.isNotEmpty)
                      Text(
                        sizeText.substring(3),
                        style: TextStyle(
                          color: color.withValues(alpha: .72),
                          fontSize: 12,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }
    if (m.msgType == 'voice') {
      return VoiceMessageBubble(message: m, me: me);
    }
    if (m.msgType == 'transfer') {
      return TransferCard(
        message: m,
        me: me,
        onAccept: onTransferAction == null
            ? null
            : () => onTransferAction!(m, true),
        onReturn: onTransferAction == null
            ? null
            : () => onTransferAction!(m, false),
      );
    }
    if (m.msgType == 'red_packet') {
      return RedPacketCard(
        message: m,
        me: me,
        onTap: () => onRedPacket?.call(m),
      );
    }
    if (m.msgType == 'call_record') {
      final video = '${m.content['media']}'.contains('video');
      return _CallRecordLine(
        message: m,
        me: me,
        onTap: onCallRecordTap == null ? null : () => onCallRecordTap!(video),
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Flexible(
          child: _MaybeLinkText(
            text: '${m.content['text'] ?? m.preview}',
            style: TextStyle(
              color: color,
              height: 1.35,
              fontSize: fontSize,
              fontWeight: FontWeight.w400,
            ),
            onOpenLink: onOpenLink,
          ),
        ),
        const SizedBox(width: 12),
      ],
    );
  }
}

class _MaybeLinkText extends StatelessWidget {
  final String text;
  final TextStyle style;
  final ValueChanged<Uri>? onOpenLink;

  const _MaybeLinkText({
    required this.text,
    required this.style,
    required this.onOpenLink,
  });

  @override
  Widget build(BuildContext context) {
    if (onOpenLink == null) return Text(text, style: style);
    return LinkText(text: text, style: style, onOpenLink: onOpenLink!);
  }
}

class _RecallPill extends StatelessWidget {
  final String text;
  const _RecallPill({required this.text});

  @override
  Widget build(BuildContext context) => Center(
    child: Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: BlinStyle.iconSurface(context),
        borderRadius: BorderRadius.circular(BlinStyle.buttonRadius),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: BlinStyle.subtle,
          fontSize: 12,
          fontWeight: FontWeight.w400,
        ),
      ),
    ),
  );
}

class VoiceMessageBubble extends StatefulWidget {
  final UnifiedMessage message;
  final bool me;

  const VoiceMessageBubble({
    super.key,
    required this.message,
    required this.me,
  });

  @override
  State<VoiceMessageBubble> createState() => _VoiceMessageBubbleState();
}

class _VoiceMessageBubbleState extends State<VoiceMessageBubble> {
  final player = AudioPlayer();
  bool playing = false;

  @override
  void initState() {
    super.initState();
    player.onPlayerComplete.listen((_) {
      if (mounted) setState(() => playing = false);
    });
    player.onPlayerStateChanged.listen((state) {
      if (mounted) setState(() => playing = state == PlayerState.playing);
    });
  }

  @override
  void dispose() {
    player.dispose();
    super.dispose();
  }

  String get url =>
      '${widget.message.content['url'] ?? widget.message.content['file_url'] ?? widget.message.content['path'] ?? ''}';

  int get duration =>
      int.tryParse('${widget.message.content['duration'] ?? 1}') ?? 1;

  Future<void> toggle() async {
    if (url.isEmpty) return;
    if (playing) {
      await player.stop();
      if (mounted) setState(() => playing = false);
      return;
    }
    await player.stop();
    await player.play(UrlSource(url));
  }

  @override
  Widget build(BuildContext context) {
    final width = (88 + duration.clamp(1, 60) * 2.2).clamp(96.0, 220.0);
    final icon = playing ? Icons.stop_rounded : Icons.play_arrow_rounded;
    return InkWell(
      onTap: toggle,
      borderRadius: BorderRadius.circular(18),
      child: SizedBox(
        width: width,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: BlinStyle.ink, size: 24),
            const SizedBox(width: 8),
            Expanded(
              child: Row(
                mainAxisAlignment: widget.me
                    ? MainAxisAlignment.end
                    : MainAxisAlignment.start,
                children: [
                  for (var i = 0; i < 3; i++)
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 160),
                      width: 3,
                      height: playing ? 10.0 + (i * 4) : 8,
                      margin: const EdgeInsets.only(right: 3),
                      decoration: BoxDecoration(
                        color: BlinStyle.ink.withValues(
                          alpha: playing ? .84 : .52,
                        ),
                        borderRadius: BorderRadius.circular(99),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              formatVoiceDuration(duration),
              style: const TextStyle(
                color: BlinStyle.muted,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChatImagePreview extends StatelessWidget {
  final String url;
  final bool isGif;
  const _ChatImagePreview({required this.url, this.isGif = false});

  @override
  Widget build(BuildContext context) {
    final size = isGif ? 156.0 : 176.0;
    return Container(
      width: size,
      height: isGif ? 156 : 164,
      decoration: BoxDecoration(
        color: BlinStyle.softFill,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: BlinStyle.hairline(context, .55).color),
        boxShadow: [BlinStyle.softShadow(.05)],
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: isGif ? const EdgeInsets.all(6) : EdgeInsets.zero,
        child: Image.network(
          url,
          fit: isGif ? BoxFit.contain : BoxFit.cover,
          gaplessPlayback: true,
          filterQuality: FilterQuality.medium,
          webHtmlElementStrategy: WebHtmlElementStrategy.fallback,
          frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
            if (wasSynchronouslyLoaded || frame != null) return child;
            return const Center(
              child: CircularProgressIndicator(strokeWidth: 2),
            );
          },
          errorBuilder: (context, error, stackTrace) =>
              const Icon(Icons.broken_image_outlined),
        ),
      ),
    );
  }
}

class ImagePreviewScreen extends StatelessWidget {
  final String url;
  final Future<void> Function()? onDownload;
  final Future<void> Function()? onForward;

  const ImagePreviewScreen({
    super.key,
    required this.url,
    this.onDownload,
    this.onForward,
  });

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.black,
    body: Stack(
      children: [
        Positioned.fill(
          child: InteractiveViewer(
            minScale: .75,
            maxScale: 4.5,
            child: Center(
              child: Image.network(
                url,
                fit: BoxFit.contain,
                webHtmlElementStrategy: WebHtmlElementStrategy.fallback,
                frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
                  if (wasSynchronouslyLoaded || frame != null) return child;
                  return const SizedBox(
                    width: 36,
                    height: 36,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  );
                },
                errorBuilder: (_, __, ___) => const Icon(
                  Icons.broken_image_outlined,
                  color: Colors.white70,
                  size: 46,
                ),
              ),
            ),
          ),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 6, 10, 16),
            child: Column(
              children: [
                Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(
                        Icons.close_rounded,
                        color: Colors.white,
                      ),
                    ),
                    const Spacer(),
                  ],
                ),
                const Spacer(),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _PreviewActionButton(
                      icon: Icons.download_rounded,
                      label: '下载',
                      onTap: onDownload,
                    ),
                    const SizedBox(width: 16),
                    _PreviewActionButton(
                      icon: Icons.forward_rounded,
                      label: '转发',
                      onTap: onForward,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}

class FilePreviewScreen extends StatelessWidget {
  final String filename;
  final int sizeBytes;
  final Future<void> Function()? onDownload;
  final Future<void> Function()? onForward;

  const FilePreviewScreen({
    super.key,
    required this.filename,
    required this.sizeBytes,
    this.onDownload,
    this.onForward,
  });

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: BlinStyle.bg,
    body: PageBackdrop(
      child: Column(
        children: [
          AppTopBar(
            title: '文件详情',
            subtitle: filename,
            leading: IconButton(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.arrow_back_rounded),
            ),
          ),
          Expanded(
            child: ModuleContent(
              child: Center(
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: BlinStyle.surface(context),
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [BlinStyle.softShadow(.08)],
                    border: Border.all(
                      color: BlinStyle.hairline(context).color,
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const NativeIconBox(
                            icon: Icons.insert_drive_file_outlined,
                            color: BlinStyle.primary,
                            size: 54,
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  filename,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: BlinStyle.ink,
                                    fontSize: 18,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  _formatFileSize(sizeBytes),
                                  style: const TextStyle(
                                    color: BlinStyle.muted,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w400,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 22),
                      Row(
                        children: [
                          Expanded(
                            child: FilledButton.icon(
                              onPressed: onDownload == null
                                  ? null
                                  : () => onDownload!(),
                              icon: const Icon(Icons.download_rounded),
                              label: const Text('下载'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: onForward == null
                                  ? null
                                  : () => onForward!(),
                              icon: const Icon(Icons.forward_rounded),
                              label: const Text('转发'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );

  static String _formatFileSize(int size) {
    if (size <= 0) return '未知大小';
    if (size >= 1024 * 1024) {
      return '${(size / 1024 / 1024).toStringAsFixed(1)} MB';
    }
    if (size >= 1024) return '${(size / 1024).toStringAsFixed(0)} KB';
    return '$size B';
  }
}

class VideoPreviewScreen extends StatefulWidget {
  final String url;
  final String title;
  final Future<void> Function()? onDownload;
  final Future<void> Function()? onForward;

  const VideoPreviewScreen({
    super.key,
    required this.url,
    this.title = '视频',
    this.onDownload,
    this.onForward,
  });

  @override
  State<VideoPreviewScreen> createState() => _VideoPreviewScreenState();
}

class _VideoPreviewScreenState extends State<VideoPreviewScreen> {
  late final VideoPlayerController controller;
  bool ready = false;
  String? error;

  @override
  void initState() {
    super.initState();
    controller = VideoPlayerController.networkUrl(Uri.parse(widget.url));
    controller
        .initialize()
        .then((_) {
          if (!mounted) return;
          setState(() => ready = true);
          controller.play();
        })
        .catchError((e) {
          if (mounted) setState(() => error = '$e');
        });
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.black,
    body: Stack(
      children: [
        Positioned.fill(child: _buildVideoBody()),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 6, 10, 16),
            child: Column(
              children: [
                Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(
                        Icons.close_rounded,
                        color: Colors.white,
                      ),
                    ),
                    Expanded(
                      child: Text(
                        widget.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 48),
                  ],
                ),
                const Spacer(),
                _buildControls(),
              ],
            ),
          ),
        ),
      ],
    ),
  );

  Widget _buildVideoBody() {
    if (error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            '视频加载失败：$error',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white70, fontSize: 14),
          ),
        ),
      );
    }
    if (!ready) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
      );
    }
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _togglePlay,
      child: Center(
        child: AspectRatio(
          aspectRatio: controller.value.aspectRatio > 0
              ? controller.value.aspectRatio
              : 16 / 9,
          child: VideoPlayer(controller),
        ),
      ),
    );
  }

  Widget _buildControls() {
    if (!ready || error != null) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _PreviewActionButton(
            icon: Icons.download_rounded,
            label: '下载',
            onTap: widget.onDownload,
          ),
          const SizedBox(width: 16),
          _PreviewActionButton(
            icon: Icons.forward_rounded,
            label: '转发',
            onTap: widget.onForward,
          ),
        ],
      );
    }
    return ValueListenableBuilder<VideoPlayerValue>(
      valueListenable: controller,
      builder: (context, value, _) {
        final total = value.duration;
        final current = value.position > total ? total : value.position;
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                IconButton(
                  onPressed: _togglePlay,
                  icon: Icon(
                    value.isPlaying
                        ? Icons.pause_rounded
                        : Icons.play_arrow_rounded,
                    color: Colors.white,
                    size: 30,
                  ),
                ),
                Text(
                  '${_formatVideoDuration(current)} / ${_formatVideoDuration(total)}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
            VideoProgressIndicator(
              controller,
              allowScrubbing: true,
              padding: const EdgeInsets.fromLTRB(12, 2, 12, 18),
              colors: VideoProgressColors(
                playedColor: BlinStyle.primary,
                bufferedColor: Colors.white.withValues(alpha: .32),
                backgroundColor: Colors.white.withValues(alpha: .18),
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _PreviewActionButton(
                  icon: Icons.download_rounded,
                  label: '下载',
                  onTap: widget.onDownload,
                ),
                const SizedBox(width: 16),
                _PreviewActionButton(
                  icon: Icons.forward_rounded,
                  label: '转发',
                  onTap: widget.onForward,
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  void _togglePlay() {
    if (!ready) return;
    setState(() {
      controller.value.isPlaying ? controller.pause() : controller.play();
    });
  }

  static String _formatVideoDuration(Duration value) {
    final totalSeconds = value.inSeconds;
    final hours = totalSeconds ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;
    final seconds = totalSeconds % 60;
    if (hours > 0) {
      return '$hours:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }
}

class _PreviewActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Future<void> Function()? onTap;

  const _PreviewActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap == null ? null : () => onTap!(),
    borderRadius: BorderRadius.circular(18),
    child: Container(
      width: 74,
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: .18)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 24),
          const SizedBox(height: 5),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    ),
  );
}

class _CallRecordLine extends StatelessWidget {
  final UnifiedMessage message;
  final bool me;
  final VoidCallback? onTap;
  const _CallRecordLine({required this.message, required this.me, this.onTap});

  @override
  Widget build(BuildContext context) {
    final content = message.content;
    final media = '${content['media']}'.contains('video') ? '视频' : '语音';
    final status = '${content['status']}';
    final callerId = int.tryParse('${content['caller_user_id'] ?? 0}') ?? 0;
    final myUserId = message.isMe ? message.fromUserId : message.toUserId;
    final iAmCaller = callerId > 0 ? callerId == myUserId : me;
    final outgoing = iAmCaller;
    final title = outgoing ? '你拨打的$media通话' : '对方拨打的$media通话';
    final desc = _callRecordDescription(status, content['duration']);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              media == '视频' ? Icons.videocam_outlined : Icons.call_outlined,
              size: 18,
              color: BlinStyle.primary,
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                '$title · $desc',
                style: const TextStyle(
                  color: BlinStyle.ink,
                  fontSize: 14,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ),
            if (onTap != null) ...[
              const SizedBox(width: 8),
              const Icon(
                Icons.refresh_rounded,
                color: BlinStyle.subtle,
                size: 16,
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _callRecordDescription(String status, Object? duration) {
    if (status == 'finished') return _durationText(duration);
    if (status == 'busy') return '对方忙线';
    if (status == 'missed') return '未接听';
    if (status == 'rejected') return '已拒绝';
    if (status == 'failed') return '连接失败';
    return '已取消';
  }

  String _durationText(Object? value) {
    final total = int.tryParse('$value') ?? 0;
    if (total <= 0) return '0秒';
    final minutes = total ~/ 60;
    final seconds = total % 60;
    if (minutes <= 0) return '$seconds秒';
    return '$minutes分${seconds.toString().padLeft(2, '0')}秒';
  }
}

class _SendStateIcon extends StatelessWidget {
  final String state;
  const _SendStateIcon({required this.state});

  @override
  Widget build(BuildContext context) {
    if (state == 'pending') {
      return const SizedBox(
        width: 12,
        height: 12,
        child: CircularProgressIndicator(
          strokeWidth: 1.6,
          color: BlinStyle.subtle,
        ),
      );
    }
    if (state == 'failed') {
      return const Icon(
        Icons.error_outline_rounded,
        color: BlinStyle.danger,
        size: 15,
      );
    }
    if (state == 'read') {
      return const Icon(
        Icons.done_all_rounded,
        color: BlinStyle.primary,
        size: 15,
      );
    }
    return const Icon(Icons.check_rounded, color: BlinStyle.subtle, size: 14);
  }
}

class _TypingBubble extends StatelessWidget {
  const _TypingBubble();

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.centerLeft,
    child: Container(
      margin: const EdgeInsets.fromLTRB(4, 4, 54, 4),
      padding: const EdgeInsets.fromLTRB(12, 9, 13, 9),
      decoration: BoxDecoration(
        color: BlinStyle.surface(context),
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(18),
          topRight: Radius.circular(18),
          bottomLeft: Radius.circular(4),
          bottomRight: Radius.circular(18),
        ),
        border: Border.all(color: BlinStyle.hairline(context, .62).color),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const _TypingDots(),
          const SizedBox(width: 8),
          Text(
            '正在输入中',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: BlinStyle.muted,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    ),
  );
}

class _TypingDots extends StatefulWidget {
  const _TypingDots();

  @override
  State<_TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<_TypingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController controller;

  @override
  void initState() {
    super.initState();
    controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat();
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (_, child) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [for (var i = 0; i < 3; i++) _dot(i)],
    ),
  );

  Widget _dot(int index) {
    final phase = (controller.value + index * .22) % 1.0;
    final lift = phase < .5 ? phase * 2 : (1 - phase) * 2;
    return Transform.translate(
      offset: Offset(0, -3 * lift),
      child: Container(
        width: 5,
        height: 5,
        margin: EdgeInsets.only(right: index == 2 ? 0 : 4),
        decoration: BoxDecoration(
          color: BlinStyle.subtle.withValues(alpha: .55 + .35 * lift),
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}

class _VideoCover extends StatefulWidget {
  final String url;
  const _VideoCover({required this.url});

  @override
  State<_VideoCover> createState() => _VideoCoverState();
}

class _VideoCoverState extends State<_VideoCover> {
  VideoPlayerController? controller;
  bool ready = false;

  @override
  void initState() {
    super.initState();
    if (widget.url.isEmpty) return;
    final c = VideoPlayerController.networkUrl(Uri.parse(widget.url));
    controller = c;
    c
        .initialize()
        .then((_) {
          if (!mounted) return;
          c.pause();
          c.seekTo(Duration.zero);
          setState(() => ready = true);
        })
        .catchError((_) {});
  }

  @override
  void dispose() {
    controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Container(
    width: 236,
    height: 134,
    decoration: BoxDecoration(
      color: Colors.black.withValues(alpha: .10),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: BlinStyle.hairline(context, .55).color),
      boxShadow: [BlinStyle.softShadow(.05)],
    ),
    clipBehavior: Clip.antiAlias,
    child: Stack(
      alignment: Alignment.center,
      children: [
        Positioned.fill(
          child: ready && controller != null
              ? VideoPlayer(controller!)
              : Container(color: Colors.black.withValues(alpha: .16)),
        ),
        Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: .42),
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.play_arrow_rounded,
            color: Colors.white,
            size: 34,
          ),
        ),
      ],
    ),
  );
}

class _Composer extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool sendingAttachment;
  final bool voiceEnabled;
  final bool sendingVoice;
  final bool recordingVoice;
  final int voiceDurationSeconds;
  final bool showEmojiPanel;
  final bool voiceInputMode;
  final VoidCallback onSend;
  final VoidCallback onEmoji;
  final ValueChanged<String> onEmojiSelected;
  final ValueChanged<GifSticker> onGifSelected;
  final VoidCallback onImage;
  final VoidCallback onVideo;
  final VoidCallback onCapture;
  final VoidCallback onFile;
  final VoidCallback onTransfer;
  final VoidCallback onRedPacket;
  final VoidCallback onVoice;
  final VoidCallback onVoicePressStart;
  final VoidCallback onVoicePressEnd;
  final VoidCallback onVoicePressCancel;
  const _Composer({
    required this.controller,
    required this.focusNode,
    required this.sendingAttachment,
    required this.voiceEnabled,
    required this.sendingVoice,
    required this.recordingVoice,
    required this.voiceDurationSeconds,
    required this.showEmojiPanel,
    required this.voiceInputMode,
    required this.onSend,
    required this.onEmoji,
    required this.onEmojiSelected,
    required this.onGifSelected,
    required this.onImage,
    required this.onVideo,
    required this.onCapture,
    required this.onFile,
    required this.onTransfer,
    required this.onRedPacket,
    required this.onVoice,
    required this.onVoicePressStart,
    required this.onVoicePressEnd,
    required this.onVoicePressCancel,
  });

  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    child: Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
      decoration: BoxDecoration(
        color: BlinStyle.surface(context),
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [BlinStyle.cardShadow],
        border: Border.all(color: BlinStyle.hairline(context, .58).color),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (recordingVoice) VoiceRecordingBar(seconds: voiceDurationSeconds),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (voiceEnabled) ...[
                _InputModeButton(
                  icon: voiceInputMode
                      ? Icons.keyboard_alt_outlined
                      : Icons.keyboard_voice_outlined,
                  active: voiceInputMode,
                  onTap: sendingAttachment || sendingVoice ? null : onVoice,
                ),
                const SizedBox(width: 6),
              ],
              Expanded(
                child: voiceInputMode
                    ? _VoiceHoldButton(
                        recording: recordingVoice,
                        sending: sendingVoice,
                        onStart: onVoicePressStart,
                        onEnd: onVoicePressEnd,
                        onCancel: onVoicePressCancel,
                      )
                    : ConstrainedBox(
                        constraints: const BoxConstraints(minHeight: 44),
                        child: TextField(
                          controller: controller,
                          focusNode: focusNode,
                          minLines: 1,
                          maxLines: 4,
                          onSubmitted: (_) => onSend(),
                          decoration: const InputDecoration(
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            filled: false,
                            hintText: '输入消息',
                            hintStyle: TextStyle(color: BlinStyle.subtle),
                            isCollapsed: true,
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: 4,
                              vertical: 12,
                            ),
                          ),
                          style: TextStyle(
                            fontSize: 14,
                            color: BlinStyle.textPrimary(context),
                          ),
                        ),
                      ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 40,
                height: 40,
                child: TsddAssetIconButton(
                  asset: 'assets/tsdd/chat/icon_chat_send.png',
                  onTap: onSend,
                  tooltip: '发送',
                  size: 35,
                  iconSize: 25,
                ),
              ),
            ],
          ),
          const SizedBox(height: 7),
          SizedBox(
            height: 54,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                _ComposerTool(
                  icon: Icons.mood_outlined,
                  label: '表情',
                  onTap: onEmoji,
                ),
                _ComposerTool(
                  icon: Icons.photo_outlined,
                  label: '图片',
                  onTap: sendingAttachment ? null : onImage,
                ),
                _ComposerTool(
                  icon: Icons.video_library_outlined,
                  label: '视频',
                  onTap: sendingAttachment ? null : onVideo,
                ),
                _ComposerTool(
                  icon: Icons.photo_camera_outlined,
                  label: '拍摄',
                  onTap: sendingAttachment ? null : onCapture,
                ),
                _ComposerTool(
                  icon: Icons.attach_file_rounded,
                  label: '文件',
                  onTap: sendingAttachment ? null : onFile,
                ),
                _ComposerTool(
                  icon: Icons.account_balance_wallet_outlined,
                  label: '转账',
                  onTap: onTransfer,
                ),
                _ComposerTool(
                  icon: Icons.redeem_outlined,
                  label: '红包',
                  onTap: onRedPacket,
                ),
              ],
            ),
          ),
          if (showEmojiPanel)
            ChatExpressionPanel(
              onEmoji: onEmojiSelected,
              onGif: onGifSelected,
              gifEnabled: !sendingAttachment,
            ),
        ],
      ),
    ),
  );
}

class CaptureActionSheet extends StatelessWidget {
  final VoidCallback onPhoto;
  final VoidCallback onVideo;

  const CaptureActionSheet({
    super.key,
    required this.onPhoto,
    required this.onVideo,
  });

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(12, 0, 12, bottom > 0 ? 8 : 12),
        child: SoftCard(
          radius: 24,
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 38,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 14),
                  decoration: BoxDecoration(
                    color: BlinStyle.line,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              Text('拍摄发送', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 4),
              Text(
                '选择拍照或录制视频后直接发送',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: _CaptureSheetAction(
                      icon: Icons.photo_camera_outlined,
                      title: '拍照',
                      subtitle: '发送照片',
                      onTap: onPhoto,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _CaptureSheetAction(
                      icon: Icons.videocam_outlined,
                      title: '录视频',
                      subtitle: '最长 3 分钟',
                      onTap: onVideo,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class CallActionSheet extends StatelessWidget {
  final String title;
  final String subtitle;
  final String voiceTitle;
  final String voiceSubtitle;
  final String videoTitle;
  final String videoSubtitle;
  final VoidCallback onVoice;
  final VoidCallback onVideo;

  const CallActionSheet({
    super.key,
    required this.title,
    required this.subtitle,
    required this.voiceTitle,
    required this.voiceSubtitle,
    required this.videoTitle,
    required this.videoSubtitle,
    required this.onVoice,
    required this.onVideo,
  });

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(12, 0, 12, bottom > 0 ? 8 : 12),
        child: Align(
          alignment: Alignment.bottomCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: SoftCard(
              radius: 24,
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 38,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 14),
                      decoration: BoxDecoration(
                        color: BlinStyle.line,
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: BlinStyle.primary.withValues(alpha: .10),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Icon(
                          Icons.wifi_calling_3_outlined,
                          color: BlinStyle.primary,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              subtitle,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: '关闭',
                        visualDensity: VisualDensity.compact,
                        onPressed: () => Navigator.pop(context),
                        icon: Icon(
                          Icons.close_rounded,
                          color: BlinStyle.textSecondary(context),
                          size: 20,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final compact = constraints.maxWidth < 380;
                      final voice = _CallSheetAction(
                        icon: Icons.call_outlined,
                        color: BlinStyle.success,
                        title: voiceTitle,
                        subtitle: voiceSubtitle,
                        onTap: onVoice,
                      );
                      final video = _CallSheetAction(
                        icon: Icons.videocam_outlined,
                        color: BlinStyle.primary,
                        title: videoTitle,
                        subtitle: videoSubtitle,
                        onTap: onVideo,
                      );
                      if (compact) {
                        return Column(
                          children: [voice, const SizedBox(height: 10), video],
                        );
                      }
                      return Row(
                        children: [
                          Expanded(child: voice),
                          const SizedBox(width: 10),
                          Expanded(child: video),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: BlinStyle.iconSurface(context),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.notifications_active_outlined,
                          color: BlinStyle.textSecondary(context),
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '通话邀请会发送到当前会话，对方接听后进入通话。',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: BlinStyle.textSecondary(context),
                              fontSize: 12,
                              height: 1.35,
                              fontWeight: FontWeight.w400,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CallSheetAction extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _CallSheetAction({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.transparent,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Ink(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: color.withValues(alpha: .08),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: color.withValues(alpha: .16)),
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 90),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              NativeIconBox(icon: icon, color: color, size: 44),
              const SizedBox(height: 14),
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: BlinStyle.textPrimary(context),
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: BlinStyle.textSecondary(context),
                  fontSize: 12,
                  height: 1.35,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _CaptureSheetAction extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _CaptureSheetAction({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.transparent,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: BlinStyle.iconSurface(context),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: BlinStyle.hairline(context, .62).color),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            NativeIconBox(icon: icon, color: BlinStyle.primary, size: 42),
            const SizedBox(height: 12),
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    ),
  );
}

class ChatHistorySearchScreen extends StatefulWidget {
  final String title;
  final String subtitle;
  final Future<List<UnifiedMessage>> Function(String keyword) loadMessages;

  const ChatHistorySearchScreen({
    super.key,
    required this.title,
    required this.subtitle,
    required this.loadMessages,
  });

  @override
  State<ChatHistorySearchScreen> createState() =>
      _ChatHistorySearchScreenState();
}

class _ChatHistorySearchScreenState extends State<ChatHistorySearchScreen> {
  final controller = TextEditingController();
  List<UnifiedMessage> results = [];
  bool loading = false;
  String searchedKeyword = '';

  @override
  void initState() {
    super.initState();
    controller.addListener(() {
      if (controller.text.trim().isEmpty && results.isNotEmpty) {
        setState(() {
          results = [];
          searchedKeyword = '';
        });
      }
    });
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  Future<void> search() async {
    final keyword = controller.text.trim();
    if (keyword.isEmpty || loading) return;
    FocusScope.of(context).unfocus();
    setState(() {
      loading = true;
      searchedKeyword = keyword;
    });
    try {
      final list = await widget.loadMessages(keyword);
      final matched = list.where((message) {
        final haystack = [
          message.preview,
          message.msgType,
          jsonEncode(message.content),
        ].join(' ').toLowerCase();
        return haystack.contains(keyword.toLowerCase());
      }).toList()..sort((a, b) => b.createTime.compareTo(a.createTime));
      if (mounted) setState(() => results = matched);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('搜索失败：$e')));
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: PageBackdrop(
      child: Column(
        children: [
          AppTopBar(
            title: '查找聊天记录',
            subtitle: widget.title,
            leading: IconButton(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.arrow_back_rounded),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
            child: TextField(
              controller: controller,
              autofocus: true,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => unawaited(search()),
              decoration: InputDecoration(
                hintText: widget.subtitle,
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: loading
                    ? const Padding(
                        padding: EdgeInsets.all(14),
                        child: SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : IconButton(
                        onPressed: search,
                        icon: const Icon(Icons.arrow_forward_rounded),
                      ),
              ),
            ),
          ),
          Expanded(
            child: results.isEmpty
                ? Center(
                    child: Text(
                      searchedKeyword.isEmpty ? '输入关键词搜索聊天记录' : '没有找到相关消息',
                      style: const TextStyle(
                        color: BlinStyle.muted,
                        fontSize: 14,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  )
                : ListView.separated(
                    padding: EdgeInsets.zero,
                    itemCount: results.length,
                    separatorBuilder: (_, __) =>
                        const Divider(height: 1, indent: 76),
                    itemBuilder: (_, index) =>
                        _HistoryResultTile(message: results[index]),
                  ),
          ),
        ],
      ),
    ),
  );
}

class _HistoryResultTile extends StatelessWidget {
  final UnifiedMessage message;
  const _HistoryResultTile({required this.message});

  @override
  Widget build(BuildContext context) {
    final title = message.isMe ? '我' : _senderTitle(message);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => Navigator.pop(context, message),
        child: NativeListRow(
          leading: NativeIconBox(
            icon: _icon,
            color: message.isMe ? BlinStyle.primary : BlinStyle.green,
            size: 42,
          ),
          title: title,
          subtitle: message.preview.isEmpty ? '消息内容为空' : message.preview,
          trailing: Text(
            _dateText(message.createTime),
            style: const TextStyle(
              color: BlinStyle.subtle,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
          minHeight: 70,
        ),
      ),
    );
  }

  IconData get _icon {
    if (message.msgType == 'image') return Icons.image_outlined;
    if (message.msgType == 'voice') return Icons.keyboard_voice_outlined;
    if (message.msgType == 'video') return Icons.videocam_outlined;
    if (message.msgType == 'file') return Icons.insert_drive_file_outlined;
    if (message.msgType.contains('call')) return Icons.call_outlined;
    return Icons.chat_bubble_outline_rounded;
  }

  String _senderTitle(UnifiedMessage message) {
    final raw = message.raw;
    final content = message.content;
    for (final value in [
      raw['nickname'],
      raw['from_nickname'],
      raw['sender_name'],
      content['nickname'],
    ]) {
      final text = '${value ?? ''}'.trim();
      if (text.isNotEmpty && text != 'null') return text;
    }
    return '对方';
  }

  String _dateText(DateTime time) {
    final y = time.year.toString().padLeft(4, '0');
    final m = time.month.toString().padLeft(2, '0');
    final d = time.day.toString().padLeft(2, '0');
    final h = time.hour.toString().padLeft(2, '0');
    final min = time.minute.toString().padLeft(2, '0');
    return '$y-$m-$d $h:$min';
  }
}

class VoiceRecordingBar extends StatelessWidget {
  final int seconds;

  const VoiceRecordingBar({super.key, required this.seconds});

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    margin: const EdgeInsets.only(bottom: 8),
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
    decoration: BoxDecoration(
      color: BlinStyle.primary.withValues(alpha: .10),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: BlinStyle.primary.withValues(alpha: .20)),
    ),
    child: Row(
      children: [
        const Icon(Icons.mic_rounded, color: BlinStyle.primary, size: 18),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            '正在录音 ${formatVoiceDuration(seconds)}',
            style: const TextStyle(
              color: BlinStyle.ink,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const Text(
          '再次点击发送',
          style: TextStyle(
            color: BlinStyle.muted,
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    ),
  );
}

class _ComposerTool extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  const _ComposerTool({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(right: 8),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: SizedBox(
        width: 54,
        height: 54,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: BlinStyle.iconSurface(context),
                borderRadius: BorderRadius.circular(13),
              ),
              child: Icon(
                icon,
                color: BlinStyle.textPrimary(context),
                size: 20,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              label,
              style: const TextStyle(
                color: BlinStyle.muted,
                fontSize: 11,
                fontWeight: FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _InputModeButton extends StatelessWidget {
  final IconData icon;
  final bool active;
  final VoidCallback? onTap;

  const _InputModeButton({
    required this.icon,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => Tooltip(
    message: active ? '切换输入' : '语音输入',
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        width: 35,
        height: 35,
        decoration: BoxDecoration(
          color: active
              ? BlinStyle.primary.withValues(alpha: .10)
              : Colors.transparent,
          shape: BoxShape.circle,
        ),
        child: Icon(
          icon,
          size: 22,
          color: active ? BlinStyle.primary : BlinStyle.textPrimary(context),
        ),
      ),
    ),
  );
}

class _VoiceHoldButton extends StatelessWidget {
  final bool recording;
  final bool sending;
  final VoidCallback onStart;
  final VoidCallback onEnd;
  final VoidCallback onCancel;

  const _VoiceHoldButton({
    required this.recording,
    required this.sending,
    required this.onStart,
    required this.onEnd,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final label = recording
        ? '松开 结束'
        : sending
        ? '准备中...'
        : '按住 说话';
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onLongPressStart: (_) => onStart(),
      onLongPressEnd: (_) => onEnd(),
      onLongPressCancel: onCancel,
      child: Container(
        height: 40,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: BlinStyle.iconSurface(context),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: recording
                ? BlinStyle.primary
                : BlinStyle.textPrimary(context),
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

String firstMediaUrl(Iterable<Object?> values) {
  return media_url.firstMediaUrl(values);
}

bool isGifImagePayload(Map<String, dynamic> content, String url) {
  final format = '${content['media_format'] ?? content['format'] ?? ''}'
      .toLowerCase();
  if (format == 'gif') return true;
  final animated = '${content['animated'] ?? content['is_gif'] ?? ''}'
      .toLowerCase();
  if (animated == 'true' || animated == '1') return true;
  return _looksLikeGifPath(
        '${content['name'] ?? content['file_name'] ?? ''}',
      ) ||
      _looksLikeGifPath(url) ||
      _looksLikeGifPath(
        '${content['url'] ?? content['file_url'] ?? content['image_path'] ?? content['file_path'] ?? content['path'] ?? content['src'] ?? ''}',
      );
}

bool _looksLikeGifPath(String value) {
  final clean = value.split('?').first.split('#').first.toLowerCase();
  return clean.endsWith('.gif');
}

// More actions are now shown in the horizontal composer toolbar.
