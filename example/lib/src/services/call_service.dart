import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:flutter_callkit_incoming/entities/call_kit_params.dart';
import 'package:flutter_callkit_incoming/entities/notification_params.dart';
import 'package:flutter_callkit_incoming/entities/android_params.dart';
import 'package:flutter_callkit_incoming/entities/ios_params.dart';
import 'package:logger/logger.dart';
import 'package:sip_ua/sip_ua.dart';
import 'package:uuid/uuid.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';

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

  // --- Auto-answer state ---
  bool _shouldAutoAnswer = false;
  String? _expectedSipUri;
  Timer? _autoAnswerTimer;

  CallService(this._sipHelper) {
    _setupCallKitListeners();
    _setupFCMListeners();
  }

  void _setupCallKitListeners() {
    FlutterCallkitIncoming.onEvent.listen((event) {
      

      String? eventType;
      dynamic params;
      if (event is Map) {
        final mapEvent = event as Map;
        eventType = mapEvent['event'];
        params = mapEvent['body'] ?? mapEvent['params'] ?? mapEvent;
      } else {
        // For CallEvent object
        try {
          eventType = (event as dynamic).event?.toString();
          params = (event as dynamic).body;
        } catch (e) {
          _logger.w('Unknown CallKit event structure: $event');
        }
      }
      _logger.i('[CallKit] Received event: $eventType, params: $params');
      if (eventType == 'ACTION_CALL_ACCEPT' || eventType == 'Event.actionCallAccept') {
        _handleCallAccept(params);
      } else if (eventType == 'ACTION_CALL_DECLINE' || eventType == 'Event.actionCallDecline') {
        _handleCallDecline(params);
      } else if (eventType == 'ACTION_CALL_ENDED' || eventType == 'Event.actionCallEnded') {
        _handleCallEnded(params);
      } else if (eventType == 'ACTION_CALL_TIMEOUT' || eventType == 'Event.actionCallTimeout') {
        _handleCallTimeout(params);
      } else if (eventType == 'ACTION_CALL_CALLBACK' || eventType == 'Event.actionCallCallback') {
        _handleCallCallback(params);
      } else if (eventType == 'ACTION_CALL_TOGGLE_HOLD' || eventType == 'Event.actionCallToggleHold') {
        _handleCallToggleHold(params);
      } else if (eventType == 'ACTION_CALL_TOGGLE_MUTE' || eventType == 'Event.actionCallToggleMute') {
        _handleCallToggleMute(params);
      } else if (eventType == 'ACTION_CALL_TOGGLE_DMTF' || eventType == 'Event.actionCallToggleDMTF') {
        _handleCallToggleDMTF(params);
      } else if (eventType == 'ACTION_CALL_TOGGLE_GROUP' || eventType == 'Event.actionCallToggleGroup') {
        _handleCallToggleGroup(params);
      } else if (eventType == 'ACTION_CALL_TOGGLE_AUDIO_SESSION' || eventType == 'Event.actionCallToggleAudioSession') {
        _handleCallToggleAudioSession(params);
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
    String? sipUri,
  }) async {
    _logger.i('[CallKit] showIncomingCall called with SIP call id: $callId, callerName: $callerName, callerNumber: $callerNumber, sipUri: $sipUri');
    _logger.i('[CallKit] Showing incoming call for SIP call id: $callId');
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
        extra: <String, dynamic>{
          'sip_call_id': callId,
          if (sipUri != null) 'sip_uri': sipUri,
        },
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
      _logger.i('[CallKit] showCallkitIncoming completed for SIP call id: $callId');
    } catch (e, s) {
      _logger.e('Error showing incoming call UI: $e\n$s');
    }
  }

  Future<void> answerCallWithMedia(Call call, SIPUAHelper helper) async {
    final remoteHasVideo = call.remote_has_video;
    final mediaConstraints = <String, dynamic>{
      'audio': true,
      'video': remoteHasVideo
          ? {
              'mandatory': <String, dynamic>{
                'minWidth': '640',
                'minHeight': '480',
                'minFrameRate': '30',
              },
              'facingMode': 'user',
              'optional': <dynamic>[],
            }
          : false
    };

    MediaStream mediaStream;
    try {
      if (kIsWeb && remoteHasVideo) {
        mediaStream = await navigator.mediaDevices.getDisplayMedia(mediaConstraints);
        MediaStream userStream = await navigator.mediaDevices.getUserMedia(mediaConstraints);
        mediaStream.addTrack(userStream.getAudioTracks()[0], addToNative: true);
      } else {
        if (!remoteHasVideo) {
          mediaConstraints['video'] = false;
        }
        mediaStream = await navigator.mediaDevices.getUserMedia(mediaConstraints);
      }
      _logger.d('Successfully obtained media stream for answering call');
    } catch (e) {
      _logger.e('Error getting media stream for answering call: $e');
      return;
    }

    try {
      call.answer(helper.buildCallOptions(!remoteHasVideo), mediaStream: mediaStream);
      _logger.d('Call answered with media stream');
    } catch (e) {
      _logger.e('Error calling answer() with media stream: $e');
    }
  }

  void _handleCallAccept(dynamic params) async {
    print('params: $params');
    // Extract the SIP URI (e.g., "sip:8234@94.130.104.22") from params
    String? sipUri = params?['extra']?['sip_uri'] ?? params?['sip_uri'];
    _logger.i('[AutoAnswer] _handleCallAccept called with params: $params');
    _logger.i('[AutoAnswer] Extracted sipUri: $sipUri');
    if (sipUri == null) {
      _logger.e('No SIP URI found in CallKit accept params');
      return;
    }
    print('sipUri: $sipUri');
    // Set shouldAutoAnswer flag in SharedPreferences
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('shouldAutoAnswer', true);
    await prefs.setString('expectedSipUri', sipUri);
    _shouldAutoAnswer = true;
    _expectedSipUri = sipUri;
    _logger.i('[AutoAnswer] Set _shouldAutoAnswer: $_shouldAutoAnswer, _expectedSipUri: $_expectedSipUri');

    // Start a timeout to clear auto-answer state
    _autoAnswerTimer?.cancel();
    _logger.i('[AutoAnswer] Starting auto-answer timer for 40 seconds');
    _autoAnswerTimer = Timer(Duration(seconds: 40), () async {
      _logger.w('[AutoAnswer] Auto-answer timer fired. Current state: _shouldAutoAnswer=$_shouldAutoAnswer, _expectedSipUri=$_expectedSipUri');
      _shouldAutoAnswer = false;
      _expectedSipUri = null;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('shouldAutoAnswer', false);
      await prefs.remove('expectedSipUri');
      _logger.w('Auto-answer window expired');
    });

    _logger.i('Set to auto-answer next call from $_expectedSipUri');
  }

  void _handleCallDecline(dynamic params) {
    _logger.i('Call declined: ${params?['id']}');
    // Decline the SIP call
    final call = _sipHelper.findCall(params?['id']);
    if (call != null) {
      _logger.d('Found call, checking current state: ${call.state}');
      call.hangup();
    } else {
      _logger.e('Call not found for id: ${params?['id']}');
    }
  }

  void _handleCallEnded(dynamic params) {
    _logger.i('Call ended: ${params?['id']}');
    // End the SIP call
    final call = _sipHelper.findCall(params?['id']);
    if (call != null) {
      _logger.d('Found call, checking current state: ${call.state}');
      call.hangup();
    } else {
      _logger.e('Call not found for id: ${params?['id']}');
    }
    _resetAutoAnswer();
  }

  void _handleCallTimeout(dynamic params) {
    _logger.i('Call timeout: ${params?['id']}');
    // Handle call timeout
    _resetAutoAnswer();
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

  /// Call this from your SIPUAHelperListener when a new incoming call arrives
  Future<void> handleIncomingSipCall(Call call) async {
    _logger.i('[AutoAnswer] handleIncomingSipCall called');
    _logger.i('[AutoAnswer] _shouldAutoAnswer: $_shouldAutoAnswer, _expectedSipUri: $_expectedSipUri');
    _logger.i('[AutoAnswer] call.remote_identity: ${call.remote_identity}');
    // Check SharedPreferences for shouldAutoAnswer flag
    final prefs = await SharedPreferences.getInstance();
    final shouldAutoAnswerPref = prefs.getBool('shouldAutoAnswer') ?? false;
    final expectedSipUriPref = prefs.getString('expectedSipUri');
    if ((_shouldAutoAnswer && _expectedSipUri != null) || (shouldAutoAnswerPref && expectedSipUriPref != null)) {
      final incomingUser = call.remote_identity?.split('@').first;
      final expectedUser = (_expectedSipUri ?? expectedSipUriPref)?.split('@').first;
      _logger.i('[AutoAnswer] incomingUser: $incomingUser, expectedUser: $expectedUser');
      if (incomingUser == expectedUser) {
        _logger.i('[AutoAnswer] Match found. Auto-answering call for user $expectedUser');
        await answerCallWithMedia(call, _sipHelper);
        _resetAutoAnswer();
        await prefs.setBool('shouldAutoAnswer', false);
        await prefs.remove('expectedSipUri');
        _logger.i('[AutoAnswer] Auto-answer performed and state reset.');
        return;
      } else {
        _logger.w('[AutoAnswer] Incoming call user $incomingUser does not match expected $expectedUser. Ignoring for auto-answer.');
      }
    } else {
      _logger.i('[AutoAnswer] Auto-answer not enabled or expected SIP URI is null. Skipping auto-answer.');
    }
    _logger.i('[AutoAnswer] Exiting handleIncomingSipCall without auto-answer.');
  }

  /// Call this on call end, timeout, or for safety
  void _resetAutoAnswer() {
    _shouldAutoAnswer = false;
    _expectedSipUri = null;
    _autoAnswerTimer?.cancel();
  }

  void resetAutoAnswer() => _resetAutoAnswer();
} 