import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:provider/provider.dart';
import 'package:flutter/foundation.dart' show kIsWeb, debugDefaultTargetPlatformOverride, TargetPlatform;
import 'package:sip_ua/sip_ua.dart';
import 'package:logger/logger.dart';
import 'src/services/fcm_service.dart';
import 'src/utils/logger.dart';
import 'src/dialpad.dart';
import 'src/register.dart';
import 'src/callscreen.dart';
import 'src/about.dart';
import 'src/theme_provider.dart';
import 'src/user_state/sip_user_cubit.dart';

// Background message handler
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  AppLogger.i('Handling background message: ${message.messageId}');
  try {
    await Firebase.initializeApp();
    AppLogger.d('Firebase initialized in background handler');
    final fcmService = FCMService();
    fcmService.handleIncomingMessage(message);
  } catch (e, stackTrace) {
    AppLogger.e('Error in background handler', e, stackTrace);
  }
}

void main() async {
  AppLogger.i('Starting application initialization');
  
  try {
    // Initialize Flutter bindings first
    AppLogger.d('Initializing Flutter bindings');
    WidgetsFlutterBinding.ensureInitialized();
    
    // Create SIPUAHelper instance
    AppLogger.d('Creating SIPUAHelper instance');
    final sipHelper = SIPUAHelper();
    
    // Set logger to show all levels
    AppLogger.d('Configuring logging levels');
    Logger.level = Level.debug;
    
    // Handle desktop platform
    if (WebRTC.platformIsDesktop) {
      AppLogger.d('Running on desktop platform, setting Fuchsia as target');
      debugDefaultTargetPlatformOverride = TargetPlatform.fuchsia;
    }
    
    AppLogger.i('Running application');
    runApp(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => ThemeProvider()),
          Provider<SIPUAHelper>.value(value: sipHelper),
          Provider<SipUserCubit>(
            create: (context) => SipUserCubit(sipHelper: sipHelper),
          ),
        ],
        child: MyApp(sipHelper: sipHelper),
      ),
    );
  } catch (e, stackTrace) {
    AppLogger.e('Error during app initialization', e, stackTrace);
    rethrow;
  }
}

class MyApp extends StatefulWidget {
  final SIPUAHelper sipHelper;
  
  const MyApp({Key? key, required this.sipHelper}) : super(key: key);

  @override
  _MyAppState createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  late Map<String, PageContentBuilder> routes;
  bool _isInitialized = false;
  String? _initError;

  @override
  void initState() {
    super.initState();
    AppLogger.d('Initializing MyApp state');
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    try {
      AppLogger.d('Setting up routes');
      routes = {
        '/': ([SIPUAHelper? helper, Object? arguments]) => DialPadWidget(widget.sipHelper),
        '/register': ([SIPUAHelper? helper, Object? arguments]) => RegisterWidget(widget.sipHelper),
        '/callscreen': ([SIPUAHelper? helper, Object? arguments]) => CallScreenWidget(widget.sipHelper, arguments as Call?),
        '/about': ([SIPUAHelper? helper, Object? arguments]) => AboutWidget(),
      };

      if (!kIsWeb) {
        AppLogger.d('Initializing Firebase');
        await Firebase.initializeApp();
        AppLogger.d('Firebase initialized successfully');

        AppLogger.d('Setting up FCM');
        final fcmService = FCMService();
        await fcmService.initialize();
        AppLogger.d('FCM Service initialized successfully');

        AppLogger.d('Setting up background message handler');
        FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
      } else {
        AppLogger.i('Running on web platform, skipping Firebase initialization');
      }

      if (mounted) {
        setState(() {
          _isInitialized = true;
        });
      }
    } catch (e, stackTrace) {
      AppLogger.e('Error during app initialization', e, stackTrace);
      if (mounted) {
        setState(() {
          _initError = e.toString();
          _isInitialized = true; // Set to true to show error UI
        });
      }
    }
  }

  Route<dynamic>? _onGenerateRoute(RouteSettings settings) {
    AppLogger.d('Generating route for: ${settings.name}');
    final String? name = settings.name;
    final PageContentBuilder? pageContentBuilder = routes[name!];
    if (pageContentBuilder != null) {
      if (settings.arguments != null) {
        AppLogger.d('Creating route with arguments');
        final Route route = MaterialPageRoute<Widget>(
            builder: (context) => pageContentBuilder(widget.sipHelper, settings.arguments));
        return route;
      } else {
        AppLogger.d('Creating route without arguments');
        final Route route = MaterialPageRoute<Widget>(
            builder: (context) => pageContentBuilder(widget.sipHelper));
        return route;
      }
    }
    AppLogger.w('No route found for: ${settings.name}');
    return null;
  }

  @override
  Widget build(BuildContext context) {
    AppLogger.d('Building MyApp widget');
    return MaterialApp(
      title: 'Dart SIP UA Example',
      theme: Provider.of<ThemeProvider>(context).currentTheme,
      home: _isInitialized 
        ? (_initError != null
            ? Scaffold(
                body: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text('Initialization Error:'),
                      Text(_initError!, style: TextStyle(color: Colors.red)),
                      ElevatedButton(
                        onPressed: _initializeApp,
                        child: Text('Retry'),
                      ),
                    ],
                  ),
                ),
              )
            : DialPadWidget(widget.sipHelper))
        : Scaffold(
            body: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Initializing...'),
                ],
              ),
            ),
          ),
      onGenerateRoute: _onGenerateRoute,
    );
  }
}

typedef PageContentBuilder = Widget Function([SIPUAHelper? helper, Object? arguments]);
