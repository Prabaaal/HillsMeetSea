import 'dart:convert';
import 'dart:js_interop';

import 'package:flutter/foundation.dart';

import '../main.dart';

@JS('window.HMSPush.isSupported')
external bool _isPushSupported();

@JS('window.HMSPush.permission')
external String _pushPermission();

@JS('window.HMSPush.requestPermission')
external JSPromise<JSAny?> _requestPermission();

@JS('window.HMSPush.ensureSubscription')
external JSPromise<JSAny?> _ensureSubscription(JSString vapidKey);

@JS('window.HMSPush.unsubscribe')
external JSPromise<JSAny?> _unsubscribePush();

class PushPermissionStatus {
  final bool supported;
  final String permission;

  const PushPermissionStatus({
    required this.supported,
    required this.permission,
  });

  bool get canPrompt => supported && permission == 'default';
  bool get denied => permission == 'denied';
  bool get granted => permission == 'granted';
}

class NotificationService {
  const NotificationService();

  bool get isConfigured => pushVapidPublicKey.trim().isNotEmpty;

  Future<PushPermissionStatus> getStatus() async {
    if (!kIsWeb) {
      return const PushPermissionStatus(supported: false, permission: 'unsupported');
    }

    final supported = _isPushSupported();
    if (!supported) {
      return const PushPermissionStatus(supported: false, permission: 'unsupported');
    }

    return PushPermissionStatus(
      supported: true,
      permission: _pushPermission(),
    );
  }

  Future<bool> requestPermissionAndSync() async {
    if (!kIsWeb || !isConfigured) {
      return false;
    }

    final permission = await _requestPermission().toDart;
    final granted = permission != null && (permission as JSString).toDart == 'granted';
    if (!granted) {
      return false;
    }

    return syncPushSubscription();
  }

  Future<bool> syncPushSubscription() async {
    if (!kIsWeb || !isConfigured || supabase.auth.currentUser == null) {
      return false;
    }

    final raw = await _ensureSubscription(pushVapidPublicKey.toJS).toDart;
    if (raw == null) {
      return false;
    }

    final payload = jsonDecode((raw as JSString).toDart);
    if (payload is! Map<String, dynamic>) {
      return false;
    }

    final endpoint = payload['endpoint'];
    if (endpoint is! String || endpoint.isEmpty) {
      return false;
    }

    await supabase.from('push_subscriptions').upsert({
      'user_id': supabase.auth.currentUser!.id,
      'endpoint': endpoint,
      'subscription': payload,
      'updated_at': DateTime.now().toIso8601String(),
    }, onConflict: 'endpoint');

    return true;
  }

  Future<void> unregisterCurrentDevice() async {
    if (!kIsWeb || supabase.auth.currentUser == null) {
      return;
    }

    final endpoint = await _unsubscribePush().toDart;
    if (endpoint == null) {
      return;
    }

    final endpointValue = (endpoint as JSString).toDart;
    if (endpointValue.isEmpty) {
      return;
    }

    await supabase
        .from('push_subscriptions')
        .delete()
        .eq('user_id', supabase.auth.currentUser!.id)
        .eq('endpoint', endpointValue);
  }
}
