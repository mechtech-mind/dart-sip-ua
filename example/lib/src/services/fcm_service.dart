import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:flutter_callkit_incoming/entities/call_kit_params.dart';
import 'package:flutter_callkit_incoming/entities/notification_params.dart';
import 'package:flutter_callkit_incoming/entities/android_params.dart';
import 'package:flutter_callkit_incoming/entities/ios_params.dart';
import '../utils/logger.dart';

class FCMService {
  final FirebaseMessaging _messaging = FirebaseMessaging.instance;

  Future<void> initialize() async {
    AppLogger.i('Initializing FCM Service');
    
    // Request permission for notifications
    NotificationSettings settings = await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
      criticalAlert: true, // Enable critical alerts for calls
    );
    
    AppLogger.d('FCM Permission status: ${settings.authorizationStatus}');

    // Get FCM token
    String? token = await _messaging.getToken();
    AppLogger.i('FCM Token: $token');

    // Configure FCM settings for high priority messages
    await _messaging.setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    );

    // Handle incoming messages when app is in foreground
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      AppLogger.d('Received foreground message: ${message.data}');
      handleIncomingMessage(message);
    });

    // Handle message when app is opened from terminated state
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      AppLogger.d('App opened from terminated state: ${message.data}');
      handleIncomingMessage(message);
    });

    // Handle initial message when app is opened from terminated state
    RemoteMessage? initialMessage = await _messaging.getInitialMessage();
    if (initialMessage != null) {
      AppLogger.d('App opened from terminated state with initial message: ${initialMessage.data}');
      handleIncomingMessage(initialMessage);
    }
  }

  void handleIncomingMessage(RemoteMessage message) {
    try {
      AppLogger.i('Handling incoming message');
      
      if (message.data['type'] == 'incoming_call') {
        AppLogger.d('Processing incoming call notification');
        
        final callData = message.data;
        final callId = callData['call_id'] ?? DateTime.now().millisecondsSinceEpoch.toString();
        
        final params = CallKitParams(
          id: callId,
          nameCaller: callData['caller_name'] ?? 'Unknown',
          appName: 'SIP Call',
          avatar: 'https://i.pravatar.cc/100',
          handle: callData['caller_number'] ?? 'Unknown',
          type: 0,
          duration: 30000,
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
          extra: <String, dynamic>{'userId': callData['user_id'] ?? 'unknown'},
          headers: <String, dynamic>{
            'apiKey': callData['api_key'] ?? '',
            'platform': 'flutter'
          },
          android: AndroidParams(
            isCustomNotification: true,
            isShowLogo: false,
            ringtonePath: 'system_ringtone_default',
            backgroundColor: '#0955fa',
            backgroundUrl: 'https://i.pravatar.cc/500',
            actionColor: '#4CAF50',
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

        FlutterCallkitIncoming.showCallkitIncoming(params);
        AppLogger.i('CallKit notification shown successfully');
      } else {
        AppLogger.w('Unknown message type: ${message.data['type']}');
      }
    } catch (e, stackTrace) {
      AppLogger.e('Error handling incoming message', e, stackTrace);
    }
  }

  Future<void> subscribeToTopic(String topic) async {
    AppLogger.i('Subscribing to topic: $topic');
    await _messaging.subscribeToTopic(topic);
  }

  Future<void> unsubscribeFromTopic(String topic) async {
    AppLogger.i('Unsubscribing from topic: $topic');
    await _messaging.unsubscribeFromTopic(topic);
  }
} 