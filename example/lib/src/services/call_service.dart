import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:flutter_callkit_incoming/entities/call_kit_params.dart';
import 'package:flutter_callkit_incoming/entities/notification_params.dart';
import 'package:flutter_callkit_incoming/entities/android_params.dart';
import 'package:flutter_callkit_incoming/entities/ios_params.dart';
import 'package:logger/logger.dart';
import 'package:sip_ua/sip_ua.dart';
import 'package:uuid/uuid.dart';

class CallService {
  final _logger = Logger(
    printer: PrettyPrinter(
      methodCount: 2,
      errorMethodCount: 8,
      lineLength: 120,
      colors: true,
      printEmojis: true,
      printTime: true
    ),
  );

  final SIPUAHelper _sipHelper;
  final _uuid = Uuid();

  CallService(this._sipHelper) {
    _setupCallKitListeners();
    _setupFCMListeners();
  }

  void _setupCallKitListeners() {
    FlutterCallkitIncoming.onEvent.listen((event) {
      if (event is Map) {
        final mapEvent = event as Map;
        final eventType = mapEvent['event'];
        final params = mapEvent['body'] ?? mapEvent['params'] ?? mapEvent;
        _logger.i('CallKit event: $eventType');
        if (eventType == 'ACTION_CALL_ACCEPT') {
          _handleCallAccept(params);
        } else if (eventType == 'ACTION_CALL_DECLINE') {
          _handleCallDecline(params);
        } else if (eventType == 'ACTION_CALL_ENDED') {
          _handleCallEnded(params);
        } else if (eventType == 'ACTION_CALL_TIMEOUT') {
          _handleCallTimeout(params);
        } else if (eventType == 'ACTION_CALL_CALLBACK') {
          _handleCallCallback(params);
        } else if (eventType == 'ACTION_CALL_TOGGLE_HOLD') {
          _handleCallToggleHold(params);
        } else if (eventType == 'ACTION_CALL_TOGGLE_MUTE') {
          _handleCallToggleMute(params);
        } else if (eventType == 'ACTION_CALL_TOGGLE_DMTF') {
          _handleCallToggleDMTF(params);
        } else if (eventType == 'ACTION_CALL_TOGGLE_GROUP') {
          _handleCallToggleGroup(params);
        } else if (eventType == 'ACTION_CALL_TOGGLE_AUDIO_SESSION') {
          _handleCallToggleAudioSession(params);
        }
      } else {
        _logger.w('CallKit event is not a Map: $event');
      }
    });
  }

  void _setupFCMListeners() {
    FirebaseMessaging.onMessage.listen((message) {
      _logger.i('Got FCM message: ${message.data}');
      if (message.data['type'] == 'incoming_call') {
        showIncomingCall(
          callId: message.data['call_id'],
          callerName: message.data['caller_name'],
          callerNumber: message.data['caller_number'],
        );
      }
    });

    FirebaseMessaging.onMessageOpenedApp.listen((message) {
      _logger.i('FCM message opened app: ${message.data}');
      if (message.data['type'] == 'incoming_call') {
        showIncomingCall(
          callId: message.data['call_id'],
          callerName: message.data['caller_name'],
          callerNumber: message.data['caller_number'],
        );
      }
    });
  }

  Future<void> showIncomingCall({
    required String callId,
    required String callerName,
    required String callerNumber,
  }) async {
    _logger.i('Showing incoming call UI for call: $callId');
    try {
      await FlutterCallkitIncoming.requestNotificationPermission({
        "rationaleMessagePermission": "Notification permission is required, to show notification.",
        "postNotificationMessageRequired": "Notification permission is required, Please allow notification permission from setting."
      });

      final params = CallKitParams(
        id: callId,
        nameCaller: callerName,
        appName: 'SIP Call',
        avatar: 'https://i.pravatar.cc/100',
        handle: callerNumber,
        type: 0,
        textAccept: 'Accept',
        textDecline: 'Decline',
        missedCallNotification: NotificationParams(
          showNotification: true,
          isShowCallback: true,
          subtitle: 'Missed call',
          callbackText: 'Call back',
        ),
        callingNotification: NotificationParams(
          showNotification: true,
          isShowCallback: true,
          subtitle: 'Calling...',
          callbackText: 'Hang Up',
        ),
        duration: 30000,
        extra: <String, dynamic>{'call_id': callId},
        headers: <String, dynamic>{'platform': 'flutter'},
        android: AndroidParams(
          isCustomNotification: true,
          isShowLogo: false,
          ringtonePath: 'system_ringtone_default',
          backgroundColor: '#0955fa',
          backgroundUrl: 'https://i.pravatar.cc/500',
          actionColor: '#4CAF50',
          textColor: '#ffffff',
          incomingCallNotificationChannelName: "Incoming Call",
          missedCallNotificationChannelName: "Missed Call",
          isShowCallID: false,
        ),
        ios: IOSParams(
          iconName: 'CallKitLogo',
          handleType: 'generic',
          supportsVideo: true,
          maximumCallGroups: 2,
          maximumCallsPerCallGroup: 1,
          audioSessionMode: 'default',
          audioSessionActive: true,
          audioSessionPreferredSampleRate: 44100.0,
          audioSessionPreferredIOBufferDuration: 0.005,
          supportsDTMF: true,
          supportsHolding: true,
          supportsGrouping: false,
          supportsUngrouping: false,
          ringtonePath: 'system_ringtone_default',
        ),
      );

      await FlutterCallkitIncoming.showCallkitIncoming(params);
      _logger.i('CallKit incoming call UI shown successfully');
    } catch (e, s) {
      _logger.e('Error showing incoming call UI: $e\n$s');
    }
  }

  void _handleCallAccept(dynamic params) {
    _logger.i('Call accepted: ${params?['id']}');
    // Accept the SIP call
    final call = _sipHelper.findCall(params?['id']);
    if (call != null) {
      call.answer({});
    }
  }

  void _handleCallDecline(dynamic params) {
    _logger.i('Call declined: ${params?['id']}');
    // Decline the SIP call
    final call = _sipHelper.findCall(params?['id']);
    if (call != null) {
      call.hangup();
    }
  }

  void _handleCallEnded(dynamic params) {
    _logger.i('Call ended: ${params?['id']}');
    // End the SIP call
    final call = _sipHelper.findCall(params?['id']);
    if (call != null) {
      call.hangup();
    }
  }

  void _handleCallTimeout(dynamic params) {
    _logger.i('Call timeout: ${params?['id']}');
    // Handle call timeout
  }

  void _handleCallCallback(dynamic params) {
    _logger.i('Call callback: ${params?['id']}');
    // Handle call callback
  }

  void _handleCallToggleHold(dynamic params) {
    _logger.i('Call toggle hold: ${params?['id']}');
    // Handle call hold toggle
  }

  void _handleCallToggleMute(dynamic params) {
    _logger.i('Call toggle mute: ${params?['id']}');
    // Handle call mute toggle
  }

  void _handleCallToggleDMTF(dynamic params) {
    _logger.i('Call toggle DMTF: ${params?['id']}');
    // Handle DTMF toggle
  }

  void _handleCallToggleGroup(dynamic params) {
    _logger.i('Call toggle group: ${params?['id']}');
    // Handle group toggle
  }

  void _handleCallToggleAudioSession(dynamic params) {
    _logger.i('Call toggle audio session: ${params?['id']}');
    // Handle audio session toggle
  }
} 