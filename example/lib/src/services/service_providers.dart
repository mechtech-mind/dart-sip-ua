import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sip_ua/sip_ua.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'fcm_service.dart';
import 'call_service.dart';

// Firebase initialization provider
final firebaseInitProvider = FutureProvider<FirebaseApp>((ref) async {
  if (kIsWeb) return Future.value(null);
  return await Firebase.initializeApp();
});

// FCM Service Provider - depends on Firebase initialization
final fcmServiceProvider = Provider<FCMService>((ref) {
  if (!kIsWeb) {
    // Ensure Firebase is initialized before creating FCM service
    final firebase = ref.watch(firebaseInitProvider);
    if (firebase is AsyncData) {
      return FCMService();
    }
    throw Exception('Firebase must be initialized before FCM service can be created');
  }
  return FCMService(); // For web, return empty service
});

// SIPUAHelper Provider
final sipUAHelperProvider = Provider<SIPUAHelper>((ref) => SIPUAHelper());

// CallService Provider
final callServiceProvider = Provider<CallService>((ref) {
  final sipHelper = ref.watch(sipUAHelperProvider);
  return CallService(sipHelper);
});

// Combined Service Provider for easy access to all services
final combinedServicesProvider = FutureProvider<CombinedServices>((ref) async {
  if (!kIsWeb) {
    // Wait for Firebase to initialize
    await ref.watch(firebaseInitProvider.future);
  }
  
  return CombinedServices(
    fcmService: ref.watch(fcmServiceProvider),
    callService: ref.watch(callServiceProvider),
    sipHelper: ref.watch(sipUAHelperProvider),
  );
});

// Class to hold all services for easy access
class CombinedServices {
  final FCMService fcmService;
  final CallService callService;
  final SIPUAHelper sipHelper;

  CombinedServices({
    required this.fcmService,
    required this.callService,
    required this.sipHelper,
  });
} 