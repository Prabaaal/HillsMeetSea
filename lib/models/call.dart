/// Lifecycle states for a WebRTC call session.
enum CallState { idle, calling, ringing, connecting, connected }

/// Data carried by an incoming call offer signal.
class IncomingCallOffer {
  final String signalId;
  final String callerId;
  final String callerName;
  final bool videoCall;
  final Map<String, dynamic> offerData;

  const IncomingCallOffer({
    required this.signalId,
    required this.callerId,
    required this.callerName,
    required this.videoCall,
    required this.offerData,
  });
}
