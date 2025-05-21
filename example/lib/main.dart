import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart' show kIsWeb, debugDefaultTargetPlatformOverride, TargetPlatform;
import 'package:sip_ua/sip_ua.dart';
import 'package:logger/logger.dart';
import 'src/services/service_providers.dart';
import 'src/utils/logger.dart';
import 'src/dialpad.dart';
import 'src/register.dart';
import 'src/callscreen.dart';
import 'src/about.dart';
import 'src/theme_provider.dart';
import 'src/user_state/sip_user_cubit.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:flutter_callkit_incoming/entities/call_kit_params.dart';
import 'package:flutter_callkit_incoming/entities/notification_params.dart';
import 'package:flutter_callkit_incoming/entities/android_params.dart';
import 'package:flutter_callkit_incoming/entities/ios_params.dart';
import 'dart:math';
import 'package:flutter_riverpod/flutter_riverpod.dart' as riverpod;
import 'src/user_state/sip_user.dart';
import 'src/services/fcm_service.dart';

// Background message handler
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  AppLogger.i('Handling background message: ${message.messageId}');
  try {
    await Firebase.initializeApp();
    if (message.data['type'] == 'incoming_call') {
      final callId = message.data['call_id'] ?? DateTime.now().millisecondsSinceEpoch.toString();
      final params = CallKitParams(
        id: callId,
        nameCaller: message.data['caller_name'] ?? 'Unknown',
        appName: 'SIP Call',
        avatar: 'https://i.pravatar.cc/100',
        handle: message.data['caller_number'] ?? 'Unknown',
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
          if (message.data['sip_uri'] != null) 'sip_uri': message.data['sip_uri'],
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
      AppLogger.i('CallKit incoming call notification shown (background handler).');
    }
  } catch (e, stackTrace) {
    AppLogger.e('Error in background handler', e, stackTrace);
  }
}

// Riverpod providers
final themeProvider = riverpod.ChangeNotifierProvider<ThemeProvider>((ref) => ThemeProvider());

// SIP User Cubit Provider (moved from main.dart)
final sipUserCubitProvider = riverpod.Provider<SipUserCubit>(
  (ref) => SipUserCubit(sipHelper: ref.watch(sipUAHelperProvider)),
);

void main() async {
  final instanceId = Random().nextInt(1000000);
  AppLogger.i('Starting application initialization [InstanceID: $instanceId]');
  try {
    AppLogger.d('Initializing Flutter bindings');
    WidgetsFlutterBinding.ensureInitialized();
    AppLogger.d('Configuring logging levels');
    Logger.level = Level.debug;
    if (WebRTC.platformIsDesktop) {
      AppLogger.d('Running on desktop platform, setting Fuchsia as target');
      debugDefaultTargetPlatformOverride = TargetPlatform.fuchsia;
    }
    // Initialize Firebase before using any Firebase services
    await Firebase.initializeApp();
    // Initialize FCM Service
    final fcmService = FCMService();
    await fcmService.initialize();
    AppLogger.i('Running application');
    runApp(
      riverpod.ProviderScope(
        child: MyApp(),
      ),
    );
  } catch (e, stackTrace) {
    AppLogger.e('Error during app initialization', e, stackTrace);
    rethrow;
  }
}

class MyApp extends riverpod.ConsumerStatefulWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  _MyAppState createState() => _MyAppState();
}

class _MyAppState extends riverpod.ConsumerState<MyApp> {
  late Map<String, PageContentBuilder> routes;
  bool _sipRegisteredOnLaunch = false;

  @override
  void initState() {
    super.initState();
    AppLogger.d('Initializing MyApp state');
    _setupRoutes();
  }

  Future<void> _autoRegisterSIP(riverpod.WidgetRef ref) async {
    if (_sipRegisteredOnLaunch) return;
    _sipRegisteredOnLaunch = true;
    final prefs = await SharedPreferences.getInstance();
    final wsUri = prefs.getString('ws_uri') ?? 'ws://94.130.104.22:8088/anatel/ws';
    final sipUri = prefs.getString('sip_uri') ?? 'sip:3488@94.130.104.22';
    final displayName = prefs.getString('display_name') ?? 'Flutter SIP UA';
    final password = prefs.getString('password') ?? 'Awzvzhrd';
    final authUser = prefs.getString('auth_user') ?? '3488';
    final port = prefs.getString('port') ?? '5060';
    if (wsUri.isNotEmpty && sipUri.isNotEmpty) {
      final sipUserCubit = ref.read(sipUserCubitProvider);
      sipUserCubit.register(SipUser(
        wsUrl: wsUri,
        selectedTransport: TransportType.WS,
        wsExtraHeaders: const {},
        sipUri: sipUri,
        port: port,
        displayName: displayName,
        password: password,
        authUser: authUser,
      ));
      AppLogger.i('Auto SIP registration triggered on app launch');
    }
  }

  void _setupRoutes() {
    routes = {
      '/': ([Object? arguments]) => const DialPadWidget(),
      '/register': ([Object? arguments]) => const RegisterWidget(),
      '/callscreen': ([Object? arguments]) => CallScreenWidget(arguments as Call),
      '/about': ([Object? arguments]) => AboutWidget(),
    };
  }

  Route<dynamic>? _onGenerateRoute(RouteSettings settings) {
    AppLogger.d('Generating route for: ${settings.name}');
    final String? name = settings.name;
    final PageContentBuilder? pageContentBuilder = routes[name!];
    if (pageContentBuilder != null) {
      if (settings.arguments != null) {
        AppLogger.d('Creating route with arguments');
        final Route route = MaterialPageRoute<Widget>(
            builder: (context) => pageContentBuilder(settings.arguments));
        return route;
      } else {
        AppLogger.d('Creating route without arguments');
        final Route route = MaterialPageRoute<Widget>(
            builder: (context) => pageContentBuilder());
        return route;
      }
    }
    AppLogger.w('No route found for: ${settings.name}');
    return null;
  }

  @override
  Widget build(BuildContext context) {
    AppLogger.d('Building MyApp widget');
    final theme = ref.watch(themeProvider);
    final servicesAsync = ref.watch(combinedServicesProvider);

    servicesAsync.whenData((_) {
      _autoRegisterSIP(ref);
    });

    return MaterialApp(
      title: 'Dart SIP UA Example',
      theme: theme.currentTheme,
      routes: {
        '/': (context) => const DialPadWidget(),
        '/dialpad': (context) => const DialPadWidget(),
        '/register': (context) => const RegisterWidget(),
        '/callscreen': (context) {
          final call = ModalRoute.of(context)!.settings.arguments as Call;
          return CallScreenWidget(call);
        },
        '/about': (context) => AboutWidget(),
      },
    );
  }
}

typedef PageContentBuilder = Widget Function([Object? arguments]);
