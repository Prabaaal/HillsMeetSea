import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/call_service.dart';
import '../widgets/glass_container.dart';

class CallScreen extends StatefulWidget {
  final bool videoCall;
  final CallService? callService;
  final IncomingCallOffer? incomingCall;

  const CallScreen({
    super.key,
    required this.videoCall,
    this.callService,
    this.incomingCall,
  });

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  late final CallService _callService;
  final _localRenderer = RTCVideoRenderer();
  final _remoteRenderer = RTCVideoRenderer();

  late CallState _state;
  bool _muted = false;
  bool _cameraOff = false;
  Duration _callDuration = Duration.zero;
  late final Stopwatch _stopwatch;

  @override
  void initState() {
    super.initState();
    _callService = widget.callService ?? CallService();
    _state = widget.incomingCall != null ? CallState.connecting : CallState.calling;
    _stopwatch = Stopwatch();
    _initRenderers();
    if (widget.incomingCall != null) {
      _answerIncomingCall();
    } else {
      _startCall();
    }

    _callService.callState.listen((state) {
      if (mounted) {
        setState(() => _state = state);
        if (state == CallState.connected && !_stopwatch.isRunning) {
          _stopwatch.start();
          _startTimer();
        }
        if (state == CallState.idle) {
          Navigator.of(context).pop();
        }
      }
    });

    _callService.remoteStream.listen((stream) {
      _remoteRenderer.srcObject = stream;
    });
  }

  Future<void> _initRenderers() async {
    await _localRenderer.initialize();
    await _remoteRenderer.initialize();
  }

  Future<void> _startCall() async {
    final localStream = await _callService.startCall(
      videoCall: widget.videoCall,
    );
    _localRenderer.srcObject = localStream;
  }

  Future<void> _answerIncomingCall() async {
    final incomingCall = widget.incomingCall!;
    final localStream = await _callService.answerCall(
      callerId: incomingCall.callerId,
      offerData: incomingCall.offerData,
      videoCall: incomingCall.videoCall,
    );
    _localRenderer.srcObject = localStream;
  }

  void _startTimer() {
    Future.doWhile(() async {
      await Future.delayed(const Duration(seconds: 1));
      if (!mounted || _state != CallState.connected) return false;
      setState(() {
        _callDuration = _stopwatch.elapsed;
      });
      return true;
    });
  }

  String _formatDuration(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  void dispose() {
    _callService.dispose();
    _localRenderer.dispose();
    _remoteRenderer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF0D0021), Color(0xFF1A0840), Color(0xFF0D1A3A)],
          ),
        ),
        child: Stack(
          children: [
            // Background orbs
            Positioned(top: -120, left: -60,
              child: _buildOrb(const Color(0x40B57BFF), 350)),
            Positioned(bottom: -80, right: -60,
              child: _buildOrb(const Color(0x3063B3FF), 300)),

            // Remote video (full screen) or placeholder
            if (widget.videoCall)
              Positioned.fill(
                child: RTCVideoView(
                  _remoteRenderer,
                  objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                ),
              )
            else
              _buildAudioCallBg(),

            // Local video (picture-in-picture)
            if (widget.videoCall)
              Positioned(
                top: 60,
                right: 20,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: SizedBox(
                    width: 110,
                    height: 160,
                    child: RTCVideoView(
                      _localRenderer,
                      mirror: true,
                      objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                    ),
                  ),
                ),
              ),

            // UI overlay
            SafeArea(
              child: Column(
                children: [
                  const SizedBox(height: 20),
                  _buildCallInfo(),
                  const Spacer(),
                  _buildControls(),
                  const SizedBox(height: 40),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAudioCallBg() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 110,
            height: 110,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(
                colors: [Color(0xFFB57BFF), Color(0xFF7BB8FF)],
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFB57BFF).withOpacity(0.4),
                  blurRadius: 40,
                  spreadRadius: 10,
                ),
              ],
            ),
            alignment: Alignment.center,
            child: Text(
              '♡',
              style: GoogleFonts.playfairDisplay(
                fontSize: 44,
                color: const Color(0xFF1A0040),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCallInfo() {
    return GlassContainer(
      borderRadius: BorderRadius.circular(20),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
      child: Column(
        children: [
          Text(
            _state == CallState.calling
                ? 'calling...'
                : _state == CallState.ringing
                    ? 'ringing...'
                    : _state == CallState.connecting
                        ? 'connecting...'
                : _state == CallState.connected
                    ? _formatDuration(_callDuration)
                    : 'waiting...',
            style: GoogleFonts.dmSans(
              fontSize: 13,
              color: Colors.white54,
              letterSpacing: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildControls() {
    return GlassContainer(
      borderRadius: BorderRadius.circular(40),
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ControlBtn(
            icon: _muted ? Icons.mic_off : Icons.mic,
            active: _muted,
            onTap: () {
              setState(() => _muted = !_muted);
              _callService.toggleMute(_muted);
            },
          ),
          if (widget.videoCall) ...[
            const SizedBox(width: 16),
            _ControlBtn(
              icon: _cameraOff ? Icons.videocam_off : Icons.videocam,
              active: _cameraOff,
              onTap: () {
                setState(() => _cameraOff = !_cameraOff);
                _callService.toggleCamera(_cameraOff);
              },
            ),
          ],
          const SizedBox(width: 16),
          // Hang up
          GestureDetector(
            onTap: () async {
              await _callService.hangUp();
              if (mounted) Navigator.of(context).pop();
            },
            child: Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFFFF4A6A),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFFF4A6A).withOpacity(0.4),
                    blurRadius: 20,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: const Icon(Icons.call_end, color: Colors.white, size: 26),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOrb(Color color, double size) {
    return Container(
      width: size, height: size,
      decoration: BoxDecoration(shape: BoxShape.circle, color: color),
    );
  }
}

class _ControlBtn extends StatelessWidget {
  final IconData icon;
  final bool active;
  final VoidCallback onTap;

  const _ControlBtn({
    required this.icon,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 54,
        height: 54,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: active
              ? Colors.white.withOpacity(0.25)
              : Colors.white.withOpacity(0.1),
          border: Border.all(color: Colors.white.withOpacity(0.2)),
        ),
        child: Icon(icon, color: Colors.white, size: 22),
      ),
    );
  }
}
