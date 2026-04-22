import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:record/record.dart';
import 'package:http/http.dart' as http;
import '../main.dart';
import '../models/message.dart';
import '../services/call_service.dart';
import '../services/chat_service.dart';
import '../services/notification_service.dart';
import '../widgets/message_bubble.dart';
import '../widgets/sticker_picker.dart';
import 'call_screen.dart';
import 'auth_screen.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _chatService = ChatService();
  CallService? _incomingCallService;
  final _notificationService = const NotificationService();
  final _textCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  final _imagePicker = ImagePicker();
  final _audioRecorder = AudioRecorder();

  List<Message> _messages = [];
  Profile? _partner;
  bool _loading = true;
  bool _sending = false;
  bool _isRecording = false;
  bool _registeringNotifications = false;
  bool _showingIncomingCall = false;
  Map<String, dynamic>? _partnerPresence;
  PushPermissionStatus? _pushStatus;
  Message? _replyingTo;

  String get _myId => supabase.auth.currentUser!.id;

  @override
  void initState() {
    super.initState();
    _textCtrl.addListener(() => setState(() {})); // rebuild for voice/send toggle
    _init();
  }

  Future<void> _init() async {
    final msgs = await _chatService.fetchMessages();
    final partner = await _chatService.fetchPartnerProfile();
    setState(() {
      _messages = msgs;
      _partner = partner;
      _loading = false;
    });

    _chatService.initPresence((presence) {
      if (mounted) setState(() => _partnerPresence = presence);
    });

    _chatService.subscribe((event) {
      if (event is Message) {
        _handleIncomingMessage(event);
      } else if (event is Map && event['type'] == 'nudge') {
        _handleNudge(event);
      } else {
        // Reaction update — re-fetch messages
        _updateReactions();
      }
    });

    await _chatService.markAsRead();
    await _initNotifications();
    _startIncomingCallListener();
    _scrollToBottom();
  }

  void _startIncomingCallListener() {
    _incomingCallService?.dispose();
    final service = CallService();
    _incomingCallService = service;
    service.listenForIncomingCalls(_handleIncomingCallOffer);
  }

  Future<void> _handleIncomingCallOffer(IncomingCallOffer offer) async {
    if (!mounted || _showingIncomingCall) {
      return;
    }

    _showingIncomingCall = true;
    final accepted = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      isDismissible: false,
      enableDrag: false,
      builder: (context) => _IncomingCallSheet(
        callerName: offer.callerName,
        videoCall: offer.videoCall,
      ),
    );
    _showingIncomingCall = false;

    final service = _incomingCallService;
    if (service == null) {
      return;
    }

    if (accepted == true) {
      _incomingCallService = null;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => CallScreen(
            videoCall: offer.videoCall,
            callService: service,
            incomingCall: offer,
          ),
        ),
      );
      if (mounted) {
        _startIncomingCallListener();
      }
      return;
    }

    await service.rejectCall(callerId: offer.callerId);
  }

  void _handleNudge(Map event) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('👋 You received a nudge!'),
        backgroundColor: Color(0xFF007AFF),
        duration: Duration(seconds: 2),
      ),
    );
  }

  Future<void> _initNotifications() async {
    final status = await _notificationService.getStatus();
    if (!mounted) {
      return;
    }

    setState(() => _pushStatus = status);

    if (status.granted && _notificationService.isConfigured) {
      await _notificationService.syncPushSubscription();
    }
  }

  Future<void> _enableNotifications() async {
    if (_registeringNotifications) {
      return;
    }

    setState(() => _registeringNotifications = true);
    final enabled = await _notificationService.requestPermissionAndSync();
    final status = await _notificationService.getStatus();

    if (!mounted) {
      return;
    }

    setState(() {
      _pushStatus = status;
      _registeringNotifications = false;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          enabled
              ? 'Notifications enabled for this device'
              : 'Notifications were not enabled',
        ),
      ),
    );
  }

  Future<void> _updateReactions() async {
    final msgs = await _chatService.fetchMessages();
    if (mounted) {
      setState(() => _messages = _mergeWithPending(msgs));
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _sendText() async {
    final text = _textCtrl.text.trim();
    if (text.isEmpty || _sending) return;
    final replyId = _replyingTo?.id;
    final draft = _chatService.createOptimisticMessage(
      content: text,
      replyToId: replyId,
    );
    _textCtrl.clear();
    setState(() {
      _sending = true;
      _replyingTo = null;
      _messages = _chatService.mergeMessages(_messages, [draft]);
    });
    _scrollToBottom();
    _chatService.updatePresenceStatus('online');
    try {
      final sent = await _chatService.sendMessage(text, replyToId: replyId);
      if (mounted) {
        setState(() => _replaceMessage(draft.id, sent));
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _replaceMessage(
            draft.id,
            draft.copyWith(deliveryStatus: MessageDeliveryStatus.failed),
          );
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Message failed to send')),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _pickAndSendImage() async {
    final picked = await _imagePicker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 70,
      maxWidth: 1000,
    );
    if (picked == null) return;
    final bytes = await picked.readAsBytes();
    final replyId = _replyingTo?.id;
    final draft = _chatService.createOptimisticMessage(
      mediaType: 'image',
      replyToId: replyId,
    );
    if (mounted) {
      setState(() {
        _replyingTo = null;
        _messages = _chatService.mergeMessages(_messages, [draft]);
      });
      _scrollToBottom();
    }
    try {
      final sent = await _chatService.sendMedia(
        bytes,
        'image',
        replyToId: replyId,
      );
      if (mounted) {
        setState(() => _replaceMessage(draft.id, sent));
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _replaceMessage(
            draft.id,
            draft.copyWith(deliveryStatus: MessageDeliveryStatus.failed),
          );
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Image failed to send')),
        );
      }
    }
  }

  Future<void> _toggleRecording() async {
    if (_isRecording) {
      final path = await _audioRecorder.stop();
      setState(() => _isRecording = false);
      if (path != null) {
        await _sendVoiceRecording(path);
      }
    } else {
      if (await _audioRecorder.hasPermission()) {
        await _audioRecorder.start(
          const RecordConfig(encoder: AudioEncoder.opus, bitRate: 128000),
          path: '',
        );
        setState(() => _isRecording = true);
      }
    }
  }

  Future<void> _sendVoiceRecording(String url) async {
    try {
      final res = await http.get(Uri.parse(url));
      final bytes = res.bodyBytes;
      final replyId = _replyingTo?.id;
      final draft = _chatService.createOptimisticMessage(
        mediaType: 'voice',
        replyToId: replyId,
      );
      if (mounted) {
        setState(() {
          _replyingTo = null;
          _messages = _chatService.mergeMessages(_messages, [draft]);
        });
        _scrollToBottom();
      }
      final sent =
          await _chatService.sendMedia(bytes, 'voice', replyToId: replyId);
      if (mounted) setState(() => _replaceMessage(draft.id, sent));
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Voice failed to send')),
        );
      }
    }
  }

  Future<void> _sendSticker(String url) async {
    final replyId = _replyingTo?.id;
    final draft = _chatService.createOptimisticMessage(
      mediaUrl: url,
      mediaType: 'sticker',
      replyToId: replyId,
    );
    if (mounted) {
      setState(() {
        _replyingTo = null;
        _messages = _chatService.mergeMessages(_messages, [draft]);
      });
      Navigator.pop(context);
      _scrollToBottom();
    }
    try {
      final sent = await _chatService.sendSticker(url, replyToId: replyId);
      if (mounted) {
        setState(() => _replaceMessage(draft.id, sent));
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _replaceMessage(
            draft.id,
            draft.copyWith(deliveryStatus: MessageDeliveryStatus.failed),
          );
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Sticker failed to send')),
        );
      }
    }
  }

  void _handleIncomingMessage(Message event) {
    if (!mounted) {
      return;
    }

    setState(() {
      final pendingMatchIndex = _messages.indexWhere(
        (message) =>
            message.isPending &&
            message.senderId == event.senderId &&
            message.content == event.content &&
            message.mediaUrl == event.mediaUrl &&
            message.mediaType == event.mediaType &&
            message.replyToId == event.replyToId &&
            message.createdAt
                    .difference(event.createdAt)
                    .inSeconds
                    .abs() <=
                10,
      );

      if (pendingMatchIndex != -1) {
        _messages[pendingMatchIndex] = event;
        _messages = _chatService.mergeMessages(_messages, const []);
      } else if (_messages.indexWhere((message) => message.id == event.id) ==
          -1) {
        _messages = _chatService.mergeMessages(_messages, [event]);
      }
    });

    _scrollToBottom();
    if (event.senderId != _myId) {
      _chatService.markAsRead();
    }
  }

  List<Message> _mergeWithPending(List<Message> fetchedMessages) {
    final pending = _messages
        .where((message) => message.isPending || message.isFailed)
        .toList();
    return _chatService.mergeMessages(fetchedMessages, pending);
  }

  void _replaceMessage(String oldId, Message replacement) {
    final index = _messages.indexWhere((message) => message.id == oldId);
    if (index == -1) {
      _messages = _chatService.mergeMessages(_messages, [replacement]);
      return;
    }
    _messages[index] = replacement;
    _messages = _chatService.mergeMessages(_messages, const []);
  }

  @override
  void dispose() {
    _incomingCallService?.dispose();
    _chatService.dispose();
    _textCtrl.dispose();
    _scrollCtrl.dispose();
    _audioRecorder.dispose();
    super.dispose();
  }

  // ══════════════════════════════════════════════════
  // ═══  iMessage UI  ═══════════════════════════════
  // ══════════════════════════════════════════════════

  bool _isSameSender(int i, int j) {
    if (j < 0 || j >= _messages.length) return false;
    return (_messages[i].senderId == _myId) ==
        (_messages[j].senderId == _myId);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            if (_shouldShowNotificationPrompt) _buildNotificationPrompt(),
            Expanded(child: _buildMessageList()),
            if (_partnerPresence?['status'] == 'typing')
              const _TypingIndicator(),
            _buildInputBar(),
          ],
        ),
      ),
    );
  }

  // ── iOS-style top bar ──
  Widget _buildHeader() {
    final partnerName = _partner?.name ?? '...';
    final online = _partnerPresence?['status'] == 'online';
    final typing = _partnerPresence?['status'] == 'typing';
    final lastSeen = _partner?.lastSeen;

    return Container(
      padding: const EdgeInsets.fromLTRB(4, 6, 4, 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.97),
        border: Border(
          bottom: BorderSide(color: Colors.grey[300]!, width: 0.5),
        ),
      ),
      child: Row(
        children: [
          // Nudge button
          IconButton(
            icon: const Icon(Icons.waving_hand_outlined,
                color: Color(0xFF007AFF), size: 22),
            onPressed: () async {
              if (_partner != null) {
                await _chatService.sendNudge(_partner!.id);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Nudge sent!')),
                  );
                }
              }
            },
          ),
          // Avatar
          _buildAvatar(partnerName, online),
          const SizedBox(width: 10),
          // Name + status
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  partnerName,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    color: Colors.black,
                  ),
                ),
                Text(
                  typing
                      ? 'typing...'
                      : online
                          ? 'online'
                          : lastSeen != null
                              ? 'seen ${timeago.format(lastSeen)}'
                              : 'offline',
                  style: TextStyle(
                    fontSize: 12,
                    color: typing || online
                        ? const Color(0xFF34C759)
                        : Colors.grey[500],
                  ),
                ),
              ],
            ),
          ),
          // Call buttons
          IconButton(
            icon: const Icon(Icons.phone_outlined,
                color: Color(0xFF007AFF), size: 22),
            onPressed: () => _startCall(false),
          ),
          IconButton(
            icon: const Icon(Icons.videocam_outlined,
                color: Color(0xFF007AFF), size: 22),
            onPressed: () => _startCall(true),
          ),
          IconButton(
            icon: Icon(Icons.logout, color: Colors.grey[400], size: 20),
            onPressed: () async {
              await _notificationService.unregisterCurrentDevice();
              await _chatService.updatePresenceStatus('offline');
              await supabase.auth.signOut();
              // Navigation handled by main.dart StreamBuilder
            },
          ),
        ],
      ),
    );
  }

  bool get _shouldShowNotificationPrompt {
    if (!_notificationService.isConfigured) {
      return false;
    }
    final status = _pushStatus;
    return status != null && status.supported && !status.granted;
  }

  Widget _buildNotificationPrompt() {
    final status = _pushStatus;
    if (status == null) {
      return const SizedBox.shrink();
    }

    final title = status.canPrompt
        ? 'Enable notifications'
        : 'Notifications are blocked';
    final description = status.canPrompt
        ? 'Turn on push alerts so new messages can reach this device when the app is closed.'
        : 'Open your browser or iPhone PWA settings and allow notifications for HillsMeetSea.';

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey[200]!),
        ),
        child: Row(
          children: [
            Icon(Icons.notifications_active_outlined,
                color: Colors.grey[700]),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: Colors.black,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    description,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[600],
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
            if (status.canPrompt)
              TextButton(
                onPressed:
                    _registeringNotifications ? null : _enableNotifications,
                child: _registeringNotifications
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Enable',
                        style: TextStyle(color: Color(0xFF007AFF))),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildAvatar(String name, bool online) {
    return Stack(
      children: [
        CircleAvatar(
          radius: 20,
          backgroundColor: Colors.grey[300],
          child: Text(
            name.isNotEmpty ? name[0].toUpperCase() : '?',
            style: const TextStyle(
              fontSize: 16,
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        if (online)
          Positioned(
            bottom: 0,
            right: 0,
            child: Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF34C759),
                border: Border.all(color: Colors.white, width: 2),
              ),
            ),
          ),
      ],
    );
  }

  void _startCall(bool video) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => CallScreen(videoCall: video)),
    );
  }

  // ── Message list with grouping logic ──
  Widget _buildMessageList() {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFF007AFF)),
      );
    }
    if (_messages.isEmpty) {
      return Center(
        child: Text(
          'Say something ✨',
          style: TextStyle(fontSize: 18, color: Colors.grey[400]),
        ),
      );
    }
    return ListView.builder(
      controller: _scrollCtrl,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      itemCount: _messages.length,
      itemBuilder: (context, i) {
        final msg = _messages[i];
        final replyTo = msg.replyToId != null
            ? _messages
                .cast<Message?>()
                .firstWhere((m) => m!.id == msg.replyToId, orElse: () => null)
            : null;
        final isMine = msg.senderId == _myId;
        final showDate = i == 0 ||
            _messages[i].createdAt.day != _messages[i - 1].createdAt.day;

        final isTop = !_isSameSender(i, i - 1);
        final isBottom = !_isSameSender(i, i + 1);

        return Slidable(
          key: ValueKey(msg.id),
          endActionPane: ActionPane(
            motion: const ScrollMotion(),
            extentRatio: 0.15,
            children: [
              SlidableAction(
                onPressed: (_) => setState(() => _replyingTo = msg),
                backgroundColor: Colors.transparent,
                foregroundColor: const Color(0xFF007AFF),
                icon: Icons.reply,
                label: 'Reply',
              ),
            ],
          ),
          child: Column(
            children: [
              if (showDate) _DateDivider(date: msg.createdAt),
              MessageBubble(
                message: msg,
                isMine: isMine,
                isTop: isTop,
                isBottom: isBottom,
                replyToMessage: replyTo,
                onReply: (m) => setState(() => _replyingTo = m),
                onReact: (m, e) => _chatService.addReaction(m.id, e),
              ),
            ],
          ),
        );
      },
    );
  }

  // ── iMessage input bar ──
  Widget _buildInputBar() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_replyingTo != null) _buildReplyPreview(),
        Container(
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
          color: Colors.white,
          child: Row(
            children: [
              // Sticker + Image buttons
              IconButton(
                icon:
                    Icon(Icons.add_circle, color: Colors.grey[400], size: 28),
                onPressed: _showStickers,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
              const SizedBox(width: 4),
              IconButton(
                icon: Icon(Icons.camera_alt_outlined,
                    color: Colors.grey[400], size: 24),
                onPressed: _pickAndSendImage,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
              const SizedBox(width: 8),
              // Text input pill
              Expanded(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.grey[200],
                    borderRadius: BorderRadius.circular(22),
                  ),
                  child: TextField(
                    controller: _textCtrl,
                    onChanged: (v) {
                      _chatService.updatePresenceStatus(
                          v.isEmpty ? 'online' : 'typing');
                    },
                    style: const TextStyle(
                        color: Colors.black, fontSize: 16),
                    decoration: const InputDecoration(
                      hintText: 'iMessage',
                      hintStyle:
                          TextStyle(color: Colors.grey, fontSize: 16),
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.symmetric(vertical: 8),
                    ),
                    onSubmitted: (_) => _sendText(),
                    maxLines: null,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _buildSendButton(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildReplyPreview() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.grey[100],
          borderRadius: BorderRadius.circular(12),
          border: Border(
            left: BorderSide(
              color: const Color(0xFF007AFF),
              width: 3,
            ),
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _replyingTo!.senderId == _myId
                        ? 'You'
                        : _partner?.name ?? 'Partner',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF007AFF),
                    ),
                  ),
                  Text(
                    _replyingTo!.content ??
                        (_replyingTo!.mediaType ?? 'Media'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
                ],
              ),
            ),
            IconButton(
              icon: Icon(Icons.close, size: 16, color: Colors.grey[400]),
              onPressed: () => setState(() => _replyingTo = null),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSendButton() {
    final hasText = _textCtrl.text.trim().isNotEmpty;
    if (hasText || _sending) {
      return GestureDetector(
        onTap: _sendText,
        child: CircleAvatar(
          radius: 16,
          backgroundColor: const Color(0xFF007AFF),
          child: _sending
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.arrow_upward,
                  size: 18, color: Colors.white),
        ),
      );
    }
    // Mic button
    return GestureDetector(
      onTap: _toggleRecording,
      child: Icon(
        _isRecording ? Icons.stop_circle : Icons.mic,
        color: _isRecording ? Colors.red : Colors.grey[400],
        size: 28,
      ),
    );
  }

  void _showStickers() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => SizedBox(
        height: MediaQuery.of(context).size.height * 0.45,
        child: Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: StickerPicker(onStickerSelected: _sendSticker),
        ),
      ),
    );
  }
}

// ── Typing indicator (iMessage style) ──
class _TypingIndicator extends StatelessWidget {
  const _TypingIndicator();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 14, bottom: 6),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFFE5E5EA),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _Dot(delay: 0),
                SizedBox(width: 4),
                _Dot(delay: 200),
                SizedBox(width: 4),
                _Dot(delay: 400),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Dot extends StatefulWidget {
  final int delay;
  const _Dot({required this.delay});

  @override
  State<_Dot> createState() => _DotState();
}

class _DotState extends State<_Dot> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    Future.delayed(Duration(milliseconds: widget.delay), () {
      if (mounted) _controller.repeat(reverse: true);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _controller,
      child: CircleAvatar(radius: 4, backgroundColor: Colors.grey[500]),
    );
  }
}

// ── Incoming call sheet ──
class _IncomingCallSheet extends StatelessWidget {
  final String callerName;
  final bool videoCall;

  const _IncomingCallSheet({
    required this.callerName,
    required this.videoCall,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(28),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.15),
                blurRadius: 30,
                spreadRadius: 2,
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircleAvatar(
                radius: 32,
                backgroundColor: Colors.grey[300],
                child: Text(
                  callerName.isNotEmpty ? callerName[0].toUpperCase() : '?',
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                callerName,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: Colors.black,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                videoCall ? 'Incoming video call' : 'Incoming voice call',
                style: TextStyle(fontSize: 13, color: Colors.grey[600]),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _IncomingCallAction(
                    color: Colors.red,
                    icon: Icons.call_end,
                    onTap: () => Navigator.of(context).pop(false),
                  ),
                  const SizedBox(width: 20),
                  _IncomingCallAction(
                    color: const Color(0xFF34C759),
                    icon: videoCall ? Icons.videocam : Icons.call,
                    onTap: () => Navigator.of(context).pop(true),
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

class _IncomingCallAction extends StatelessWidget {
  final Color color;
  final IconData icon;
  final VoidCallback onTap;

  const _IncomingCallAction({
    required this.color,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 64,
        height: 64,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color,
        ),
        child: Icon(icon, color: Colors.white, size: 28),
      ),
    );
  }
}

// ── Date divider ──
class _DateDivider extends StatelessWidget {
  final DateTime date;
  const _DateDivider({required this.date});

  String _format() {
    final now = DateTime.now();
    final diff = now.difference(date).inDays;
    if (diff == 0) return 'Today';
    if (diff == 1) return 'Yesterday';
    return '${date.day}/${date.month}/${date.year}';
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.grey[300],
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            _format(),
            style: TextStyle(fontSize: 11, color: Colors.grey[700]),
          ),
        ),
      ),
    );
  }
}
