import 'package:dart_sip_ua_example/src/theme_provider.dart';
import 'package:dart_sip_ua_example/src/user_state/sip_user_cubit.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:logger/logger.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sip_ua/sip_ua.dart';
import 'package:dart_sip_ua_example/src/services/call_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../main.dart';
import 'services/service_providers.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import 'widgets/action_button.dart';

class DialPadWidget extends ConsumerStatefulWidget {
  const DialPadWidget({Key? key}) : super(key: key);

  @override
  ConsumerState<DialPadWidget> createState() => _MyDialPadWidget();
}

class _MyDialPadWidget extends ConsumerState<DialPadWidget>
    implements SipUaHelperListener {
  String? _dest;
  late SipUserCubit currentUserCubit;
  late SIPUAHelper helper;
  TextEditingController? _textController;
  late SharedPreferences _preferences;

  final Logger _logger = Logger();

  String? receivedMsg;
  late CallService callService;
  String? _fcmToken;

  @override
  void initState() {
    super.initState();
    receivedMsg = "";
    _fetchFcmToken();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    helper = ref.read(sipUAHelperProvider);
    _bindEventListeners();
    _loadSettings();
    callService = CallService(helper);
  }

  void _bindEventListeners() {
    helper.addSipUaHelperListener(this);
  }

  @override
  void dispose() {
    helper.removeSipUaHelperListener(this);
    _textController?.dispose();
    super.dispose();
  }

  void _loadSettings() async {
    _preferences = await SharedPreferences.getInstance();
    _dest = _preferences.getString('dest') ?? 'sip:hello_jssip@tryit.jssip.net';
    _textController = TextEditingController(text: _dest);
    _textController!.text = _dest!;

    setState(() {});
  }

  void reRegisterWithCurrentUser() async {
    if (currentUserCubit.state == null) return;
    if (helper.registered) {
      helper.unregister();
    }
    _logger.i("Re-registering");
    currentUserCubit.register(currentUserCubit.state!);
  }

  @override
  void registrationStateChanged(RegistrationState state) {
    setState(() {
      _logger.i("Registration state: ${state.state?.name}");
    });
  }

  @override
  void transportStateChanged(TransportState state) {
    _logger.i("Transport state: ${state.state}");
  }

  @override
  void callStateChanged(Call call, CallState callState) {
    if (callState.state == CallStateEnum.CALL_INITIATION && call.direction == 'incoming') {
      // Auto-answer integration
      callService.handleIncomingSipCall(call);
    }
    switch (callState.state) {
      case CallStateEnum.CALL_INITIATION:
        Navigator.pushNamed(context, '/callscreen', arguments: call);
        break;
      case CallStateEnum.FAILED:
      case CallStateEnum.ENDED:
        if (call.direction == 'incoming') {
          reRegisterWithCurrentUser();
        }
        break;
      default:
        break;
    }
  }

  @override
  void onNewMessage(SIPMessageRequest msg) {
    String? msgBody = msg.request.body as String?;
    setState(() {
      receivedMsg = msgBody;
    });
  }

  @override
  void onNewNotify(Notify ntf) {
    _logger.d("New notify: ${ntf.request?.method}");
  }

  @override
  void onNewReinvite(ReInvite event) {
    _logger.d("New reinvite");
  }

  Future<Widget?> _handleCall(BuildContext context,
      [bool voiceOnly = false]) async {
    final dest = _textController?.text;
    if (defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS) {
      await Permission.microphone.request();
      await Permission.camera.request();
    }
    if (dest == null || dest.isEmpty) {
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext context) {
          return AlertDialog(
            title: Text('Target is empty.'),
            content: Text('Please enter a SIP URI or username!'),
            actions: <Widget>[
              TextButton(
                child: Text('Ok'),
                onPressed: () {
                  Navigator.of(context).pop();
                },
              ),
            ],
          );
        },
      );
      return null;
    }

    var mediaConstraints = <String, dynamic>{
      'audio': true,
      'video': {
        'mandatory': <String, dynamic>{
          'minWidth': '640',
          'minHeight': '480',
          'minFrameRate': '30',
        },
        'facingMode': 'user',
      }
    };

    MediaStream mediaStream;

    if (kIsWeb && !voiceOnly) {
      mediaStream =
          await navigator.mediaDevices.getDisplayMedia(mediaConstraints);
      mediaConstraints['video'] = false;
      MediaStream userStream =
          await navigator.mediaDevices.getUserMedia(mediaConstraints);
      final audioTracks = userStream.getAudioTracks();
      if (audioTracks.isNotEmpty) {
        mediaStream.addTrack(audioTracks.first, addToNative: true);
      }
    } else {
      if (voiceOnly) {
        mediaConstraints['video'] = !voiceOnly;
      }
      mediaStream = await navigator.mediaDevices.getUserMedia(mediaConstraints);
    }

    helper.call(dest, voiceOnly: voiceOnly, mediaStream: mediaStream);
    _preferences.setString('dest', dest);
    return null;
  }

  void _handleBackSpace([bool deleteAll = false]) {
    var text = _textController!.text;
    if (text.isNotEmpty) {
      setState(() {
        text = deleteAll ? '' : text.substring(0, text.length - 1);
        _textController!.text = text;
      });
    }
  }

  void _handleNum(String number) {
    setState(() {
      _textController!.text += number;
    });
  }

  List<Widget> _buildNumPad() {
    final labels = [
      [
        {'1': ''},
        {'2': 'abc'},
        {'3': 'def'}
      ],
      [
        {'4': 'ghi'},
        {'5': 'jkl'},
        {'6': 'mno'}
      ],
      [
        {'7': 'pqrs'},
        {'8': 'tuv'},
        {'9': 'wxyz'}
      ],
      [
        {'*': ''},
        {'0': '+'},
        {'#': ''}
      ],
    ];

    return labels
        .map((row) => Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: row
                    .map((label) => ActionButton(
                          title: label.keys.first,
                          subTitle: label.values.first,
                          onPressed: () => _handleNum(label.keys.first),
                          number: true,
                        ))
                    .toList())))
        .toList();
  }

  List<Widget> _buildDialPad() {
    Color? textFieldColor =
        Theme.of(context).textTheme.bodyMedium?.color?.withValues(alpha: 0.5);
    Color? textFieldFill =
        Theme.of(context).buttonTheme.colorScheme?.surfaceContainerLowest;
    return [
      Align(
        alignment: AlignmentDirectional.centerStart,
        child: Text('Destination URL'),
      ),
      const SizedBox(height: 8),
      TextField(
        keyboardType: TextInputType.text,
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 18, color: textFieldColor),
        maxLines: 2,
        decoration: InputDecoration(
          filled: true,
          fillColor: textFieldFill,
          border: OutlineInputBorder(
            borderSide: BorderSide(color: Colors.blue.withValues(alpha: 0.5)),
            borderRadius: BorderRadius.circular(5),
          ),
          enabledBorder: OutlineInputBorder(
            borderSide: BorderSide(color: Colors.blue.withValues(alpha: 0.5)),
            borderRadius: BorderRadius.circular(5),
          ),
          focusedBorder: OutlineInputBorder(
            borderSide: BorderSide(color: Colors.blue.withValues(alpha: 0.5)),
            borderRadius: BorderRadius.circular(5),
          ),
        ),
        controller: _textController,
      ),
      SizedBox(height: 20),
      Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisAlignment: MainAxisAlignment.center,
        children: _buildNumPad(),
      ),
      Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: <Widget>[
            ActionButton(
              icon: Icons.videocam,
              onPressed: () => _handleCall(context),
            ),
            ActionButton(
              icon: Icons.dialer_sip,
              fillColor: Colors.green,
              onPressed: () => _handleCall(context, true),
            ),
            ActionButton(
              icon: Icons.keyboard_arrow_left,
              onPressed: () => _handleBackSpace(),
              onLongPress: () => _handleBackSpace(true),
            ),
          ],
        ),
      ),
    ];
  }

  void _fetchFcmToken() async {
    try {
      String? token = await FirebaseMessaging.instance.getToken();
      setState(() {
        _fcmToken = token;
      });
      if (token != null) {
        print('FCM Token: ' + token);
      }
    } catch (e) {
      print('Error fetching FCM token: ' + e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    Color? textColor = Theme.of(context).textTheme.bodyMedium?.color;
    Color? iconColor = Theme.of(context).iconTheme.color;
    bool isDarkTheme = Theme.of(context).brightness == Brightness.dark;
    currentUserCubit = ref.watch(sipUserCubitProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text("Dart SIP UA Demo"),
        actions: <Widget>[
          PopupMenuButton<String>(
              onSelected: (String value) {
                switch (value) {
                  case 'account':
                    Navigator.pushNamed(context, '/register');
                    break;
                  case 'about':
                    Navigator.pushNamed(context, '/about');
                    break;
                  case 'theme':
                    ref.read(themeProvider).setDarkmode();
                    break;
                  default:
                    break;
                }
              },
              icon: Icon(Icons.menu),
              itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
                    PopupMenuItem(
                      child: Row(
                        children: <Widget>[
                          Icon(
                            Icons.account_circle,
                            color: iconColor,
                          ),
                          SizedBox(width: 12),
                          Text('Account'),
                        ],
                      ),
                      value: 'account',
                    ),
                    PopupMenuItem(
                      child: Row(
                        children: <Widget>[
                          Icon(
                            Icons.info,
                            color: iconColor,
                          ),
                          SizedBox(width: 12),
                          Text('About'),
                        ],
                      ),
                      value: 'about',
                    ),
                    PopupMenuItem(
                      child: Row(
                        children: <Widget>[
                          Icon(
                            Icons.info,
                            color: iconColor,
                          ),
                          SizedBox(width: 12),
                          Text(isDarkTheme ? 'Light Mode' : 'Dark Mode'),
                        ],
                      ),
                      value: 'theme',
                    )
                  ]),
        ],
      ),
      body: ListView(
        padding: EdgeInsets.symmetric(horizontal: 12),
        children: <Widget>[
          SizedBox(height: 8),
          if (_fcmToken != null)
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: SelectableText(
                'FCM Token:\n$_fcmToken',
                style: TextStyle(fontSize: 12, color: Colors.blueGrey),
              ),
            ),
          Center(
            child: Text(
              'Register Status: ${helper.registerState.state?.name ?? ''}',
              style: TextStyle(fontSize: 18, color: textColor),
            ),
          ),
          SizedBox(height: 8),
          Center(
            child: Text(
              'Received Message: $receivedMsg',
              style: TextStyle(fontSize: 16, color: textColor),
            ),
          ),
          SizedBox(height: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            mainAxisAlignment: MainAxisAlignment.center,
            children: _buildDialPad(),
          ),
        ],
      ),
    );
  }
}
