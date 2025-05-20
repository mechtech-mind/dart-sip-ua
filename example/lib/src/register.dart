import 'package:dart_sip_ua_example/src/user_state/sip_user.dart';
import 'package:dart_sip_ua_example/src/user_state/sip_user_cubit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sip_ua/sip_ua.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:logger/logger.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:flutter_callkit_incoming/entities/call_kit_params.dart';
import 'package:flutter_callkit_incoming/entities/notification_params.dart';
import 'package:flutter_callkit_incoming/entities/android_params.dart';
import 'package:flutter_callkit_incoming/entities/ios_params.dart';
import 'package:uuid/uuid.dart';
import 'package:dart_sip_ua_example/src/services/call_service.dart';
import '../../main.dart';

class RegisterWidget extends ConsumerStatefulWidget {
  const RegisterWidget({Key? key}) : super(key: key);

  @override
  ConsumerState<RegisterWidget> createState() => _MyRegisterWidget();
}

class _MyRegisterWidget extends ConsumerState<RegisterWidget>
    implements SipUaHelperListener {
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

  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _portController = TextEditingController();
  final TextEditingController _wsUriController = TextEditingController();
  final TextEditingController _sipUriController = TextEditingController();
  final TextEditingController _displayNameController = TextEditingController();
  final TextEditingController _authorizationUserController =
      TextEditingController();
  final Map<String, String> _wsExtraHeaders = {
    // 'Origin': ' https://tryit.jssip.net',
    // 'Host': 'tryit.jssip.net:10443'
  };
  late SharedPreferences _preferences;
  late RegistrationState _registerState;

  TransportType _selectedTransport = TransportType.TCP;

  late SipUserCubit currentUser;
  late SIPUAHelper helper;

  final _uuid = Uuid();
  String? _currentUuid;

  late CallService callService;

  @override
  void initState() {
    super.initState();
    _currentUuid = _uuid.v4();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    helper = ref.read(sipUAHelperProvider);
    _registerState = helper.registerState;
    helper.addSipUaHelperListener(this);
    _loadSettings();
    if (kIsWeb) {
      _selectedTransport = TransportType.WS;
    }
    callService = CallService(helper);
  }

  @override
  void dispose() {
    helper.removeSipUaHelperListener(this);
    _passwordController.dispose();
    _wsUriController.dispose();
    _sipUriController.dispose();
    _displayNameController.dispose();
    _authorizationUserController.dispose();
    super.dispose();
  }

  @override
  void deactivate() {
    super.deactivate();
    helper.removeSipUaHelperListener(this);
    _saveSettings();
  }

  void _loadSettings() async {
    _preferences = await SharedPreferences.getInstance();
    setState(() {
      _portController.text = '5060';
      _wsUriController.text =
          _preferences.getString('ws_uri') ?? 'ws://94.130.104.22:8088/anatel/ws';
      _sipUriController.text =
          _preferences.getString('sip_uri') ?? 'sip:3488@94.130.104.22';
      _displayNameController.text =
          _preferences.getString('display_name') ?? 'Flutter SIP UA';
      _passwordController.text = _preferences.getString('password') ?? 'Awzvzhrd';
      _authorizationUserController.text =
          _preferences.getString('auth_user') ?? '3488';
    });
  }

  void _saveSettings() {
    _logger.i('Saving settings with current values:');
    _logger.d('WS URI: ${_wsUriController.text}');
    _logger.d('SIP URI: ${_sipUriController.text}');
    _logger.d('Auth User: ${_authorizationUserController.text}');
    _logger.d('Password: ${_passwordController.text}');
    
    _preferences.setString('port', _portController.text);
    _preferences.setString('ws_uri', _wsUriController.text);
    _preferences.setString('sip_uri', _sipUriController.text);
    _preferences.setString('display_name', _displayNameController.text);
    _preferences.setString('password', _passwordController.text);
    _preferences.setString('auth_user', _authorizationUserController.text);
  }

  @override
  void registrationStateChanged(RegistrationState state) {
    _logger.i('Registration state changed: ${state.state?.name}');
    setState(() {
      _registerState = state;
    });
  }

  void _alert(BuildContext context, String alertFieldName) {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
            title: Text('$alertFieldName is empty'),
            content: Text('Please enter $alertFieldName!'),
            actions: <Widget>[
              TextButton(
                child: Text('Ok'),
                onPressed: () {
                  Navigator.of(context).pop();
                },
              ),
            ]);
      },
    );
  }

  void _register(BuildContext context) {
    if (_wsUriController.text == '') {
      _logger.w('WebSocket URL is empty');
      _alert(context, "WebSocket URL");
      return;
    } else if (_sipUriController.text == '') {
      _logger.w('SIP URI is empty');
      _alert(context, "SIP URI");
      return;
    }

    _logger.i('Registering with current values:');
    _logger.d('WS URL: ${_wsUriController.text}');
    _logger.d('SIP URI: ${_sipUriController.text}');
    _logger.d('Transport: $_selectedTransport');
    _logger.d('Auth User: ${_authorizationUserController.text}');
    _logger.d('Display Name: ${_displayNameController.text}');

    _saveSettings();

    try {
      _logger.i('Attempting to register with SIP server...');
      currentUser.register(SipUser(
        wsUrl: _wsUriController.text,
        selectedTransport: _selectedTransport,
        wsExtraHeaders: _wsExtraHeaders,
        sipUri: _sipUriController.text,
        port: _portController.text,
        displayName: _displayNameController.text,
        password: _passwordController.text,
        authUser: _authorizationUserController.text,
      ));
      _logger.i('Registration request sent successfully');
    } catch (e) {
      _logger.e('Error during registration: $e');
      _alert(context, "Registration failed: $e");
    }
  }

  @override
  void callStateChanged(Call call, CallState state) {
    _logger.d('Call state changed: $state');
    _logger.d('Call direction: ${call.direction}');
    _logger.d('Call state: ${state.state}');
    
    if (state.state == CallStateEnum.CALL_INITIATION && call.direction == 'incoming') {
      // Auto-answer integration
      callService.handleIncomingSipCall(call);
      _logger.i('Incoming call detected, showing CallKit notification...');
      showIncomingCall();
    } else {
      _logger.d('Not showing CallKit notification - state: ${state.state}, direction: ${call.direction}');
    }
  }

  @override
  void transportStateChanged(TransportState state) {
    _logger.i('Transport state changed: $state');
  }

  @override
  void onNewMessage(SIPMessageRequest msg) {
    _logger.d('New message received: ${msg.request?.method}');
  }

  @override
  void onNewNotify(Notify ntf) {
    _logger.d('New notify received: ${ntf.request?.method}');
  }

  @override
  void onNewReinvite(ReInvite event) {
    _logger.d('New reinvite received');
  }

  Future<void> showIncomingCall() async {
    final _uuid = Uuid();
    final _currentUuid = _uuid.v4();
    _logger.i('showIncomingCall called, uuid: $_currentUuid');
    try {
      _logger.d('Requesting notification permission for CallKit...');
      await FlutterCallkitIncoming.requestNotificationPermission({
        "rationaleMessagePermission": "Notification permission is required, to show notification.",
        "postNotificationMessageRequired": "Notification permission is required, Please allow notification permission from setting."
      });
      _logger.d('Notification permission requested. Building CallKitParams...');

      final callKitParams = CallKitParams(
        id: _currentUuid,
        nameCaller: 'Hien Nguyen',
        appName: 'Callkit',
        avatar: 'https://i.pravatar.cc/100',
        handle: '0123456789',
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
        extra: <String, dynamic>{'userId': '1a2b3c4d'},
        headers: <String, dynamic>{'apiKey': 'Abc@123!', 'platform': 'flutter'},
        android: AndroidParams(
          isCustomNotification: true,
          isShowLogo: false,
          logoUrl: 'https://i.pravatar.cc/100',
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
      _logger.d('CallKitParams built. Showing CallKit incoming notification...');
      await FlutterCallkitIncoming.showCallkitIncoming(callKitParams);
      _logger.i('CallKit incoming notification shown successfully.');
    } catch (e, s) {
      _logger.e('Error in showIncomingCall: $e', error: e, stackTrace: s);
    }
  }

  @override
  Widget build(BuildContext context) {
    Color? textColor = Theme.of(context).textTheme.bodyMedium?.color;
    Color? textFieldFill =
        Theme.of(context).buttonTheme.colorScheme?.surfaceContainerLowest;
    currentUser = ref.watch(sipUserCubitProvider);

    OutlineInputBorder border = OutlineInputBorder(
      borderSide: BorderSide.none,
      borderRadius: BorderRadius.circular(5),
    );
    Color? textLabelColor =
        Theme.of(context).textTheme.bodyMedium?.color?.withValues(alpha: 0.5);
    return Scaffold(
      appBar: AppBar(
        title: Text("SIP Account"),
      ),
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 40,
                    child: ElevatedButton(
                      child: Text('Register'),
                      onPressed: () => _register(context),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 20),
        children: <Widget>[
          Center(
            child: Text(
              'Register Status: ${_registerState.state?.name ?? ''}',
              style: TextStyle(fontSize: 18, color: textColor),
            ),
          ),
          SizedBox(height: 15),
          if (_selectedTransport == TransportType.WS) ...[
            Text('WebSocket', style: TextStyle(color: textLabelColor)),
            SizedBox(height: 5),
            TextFormField(
              controller: _wsUriController,
              keyboardType: TextInputType.text,
              autocorrect: false,
              textAlign: TextAlign.center,
            ),
          ],
          if (_selectedTransport == TransportType.TCP) ...[
            Text('Port', style: TextStyle(color: textLabelColor)),
            SizedBox(height: 5),
            TextFormField(
              controller: _portController,
              keyboardType: TextInputType.text,
              textAlign: TextAlign.center,
              decoration: InputDecoration(
                filled: true,
                fillColor: textFieldFill,
                border: border,
                enabledBorder: border,
                focusedBorder: border,
              ),
            ),
          ],
          SizedBox(height: 15),
          Text('SIP URI', style: TextStyle(color: textLabelColor)),
          SizedBox(height: 5),
          TextFormField(
            controller: _sipUriController,
            keyboardType: TextInputType.text,
            autocorrect: false,
            textAlign: TextAlign.center,
            decoration: InputDecoration(
              filled: true,
              fillColor: textFieldFill,
              border: border,
              enabledBorder: border,
              focusedBorder: border,
            ),
          ),
          SizedBox(height: 15),
          Text('Authorization User', style: TextStyle(color: textLabelColor)),
          SizedBox(height: 5),
          TextFormField(
            controller: _authorizationUserController,
            keyboardType: TextInputType.text,
            autocorrect: false,
            textAlign: TextAlign.center,
            decoration: InputDecoration(
              filled: true,
              fillColor: textFieldFill,
              border: border,
              enabledBorder: border,
              focusedBorder: border,
              hintText:
                  _authorizationUserController.text.isEmpty ? '[Empty]' : null,
            ),
          ),
          SizedBox(height: 15),
          Text('Password', style: TextStyle(color: textLabelColor)),
          SizedBox(height: 5),
          TextFormField(
            controller: _passwordController,
            keyboardType: TextInputType.text,
            autocorrect: false,
            textAlign: TextAlign.center,
            decoration: InputDecoration(
              filled: true,
              fillColor: textFieldFill,
              border: border,
              enabledBorder: border,
              focusedBorder: border,
              hintText: _passwordController.text.isEmpty ? '[Empty]' : null,
            ),
          ),
          SizedBox(height: 15),
          Text('Display Name', style: TextStyle(color: textLabelColor)),
          SizedBox(height: 5),
          TextFormField(
            controller: _displayNameController,
            keyboardType: TextInputType.text,
            textAlign: TextAlign.center,
            decoration: InputDecoration(
              filled: true,
              fillColor: textFieldFill,
              border: border,
              enabledBorder: border,
              focusedBorder: border,
              hintText: _displayNameController.text.isEmpty ? '[Empty]' : null,
            ),
          ),
          const SizedBox(height: 20),
          if (!kIsWeb) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                RadioMenuButton<TransportType>(
                    value: TransportType.TCP,
                    groupValue: _selectedTransport,
                    onChanged: ((value) => setState(() {
                          _selectedTransport = value!;
                        })),
                    child: Text("TCP")),
                RadioMenuButton<TransportType>(
                    value: TransportType.WS,
                    groupValue: _selectedTransport,
                    onChanged: ((value) => setState(() {
                          _selectedTransport = value!;
                        })),
                    child: Text("WS")),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
