import 'package:sip_ua/sip_ua.dart';
import 'package:logger/logger.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'dart:async';

/// Singleton SIP handler for all SIP logic and state
class SipHandler implements SipUaHelperListener {
  static final SipHandler instance = SipHandler._internal();
  final Logger _logger = Logger();
  final SIPUAHelper _helper = SIPUAHelper();

  // Listeners
  final List<SipUaHelperListener> _listeners = [];

  // State
  RegistrationState? _registrationState;
  TransportState? _transportState;
  Call? _currentCall;
  CallState? _currentCallState;

  SipHandler._internal() {
    _helper.addSipUaHelperListener(this);
  }

  // --- Public API ---

  SIPUAHelper get helper => _helper;
  RegistrationState? get registrationState => _registrationState;
  TransportState? get transportState => _transportState;
  Call? get currentCall => _currentCall;
  CallState? get currentCallState => _currentCallState;

  void addListener(SipUaHelperListener listener) {
    if (!_listeners.contains(listener)) {
      _listeners.add(listener);
    }
  }

  void removeListener(SipUaHelperListener listener) {
    _listeners.remove(listener);
  }

  void register(UaSettings settings) {
    _logger.i('Registering SIP with settings: $settings');
    _helper.start(settings);
  }

  void unregister() {
    _logger.i('Unregistering SIP');
    _helper.unregister();
  }

  void makeCall(String dest, {bool voiceOnly = false}) async {
    var mediaConstraints = <String, dynamic>{
      'audio': true,
      'video': !voiceOnly
          ? {
              'mandatory': <String, dynamic>{
                'minWidth': '640',
                'minHeight': '480',
                'minFrameRate': '30',
              },
              'facingMode': 'user',
            }
          : false
    };
    MediaStream mediaStream;
    if (kIsWeb && !voiceOnly) {
      mediaStream = await navigator.mediaDevices.getDisplayMedia(mediaConstraints);
      mediaConstraints['video'] = false;
      MediaStream userStream = await navigator.mediaDevices.getUserMedia(mediaConstraints);
      final audioTracks = userStream.getAudioTracks();
      if (audioTracks.isNotEmpty) {
        mediaStream.addTrack(audioTracks.first, addToNative: true);
      }
    } else {
      if (voiceOnly) {
        mediaConstraints['video'] = false;
      }
      mediaStream = await navigator.mediaDevices.getUserMedia(mediaConstraints);
    }
    _helper.call(dest, voiceOnly: voiceOnly, mediaStream: mediaStream);
  }

  void hangup() {
    _logger.i('Hanging up current call');
    _currentCall?.hangup();
  }

  // --- SipUaHelperListener implementation ---

  @override
  void registrationStateChanged(RegistrationState state) {
    _logger.i('Registration state changed: ${state.state?.name}');
    _registrationState = state;
    for (final l in _listeners) {
      l.registrationStateChanged(state);
    }
  }

  @override
  void transportStateChanged(TransportState state) {
    _logger.i('Transport state changed: ${state.state}');
    _transportState = state;
    for (final l in _listeners) {
      l.transportStateChanged(state);
    }
  }

  @override
  void callStateChanged(Call call, CallState state) {
    _logger.i('Call state changed: ${state.state}');
    _currentCall = call;
    _currentCallState = state;
    for (final l in _listeners) {
      l.callStateChanged(call, state);
    }
  }

  @override
  void onNewMessage(SIPMessageRequest msg) {
    for (final l in _listeners) {
      l.onNewMessage(msg);
    }
  }

  @override
  void onNewNotify(Notify ntf) {
    for (final l in _listeners) {
      l.onNewNotify(ntf);
    }
  }

  @override
  void onNewReinvite(ReInvite event) {
    for (final l in _listeners) {
      l.onNewReinvite(event);
    }
  }
}
