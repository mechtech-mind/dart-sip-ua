import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:sip_ua/sip_ua.dart';
import 'utils/logger.dart';

import 'widgets/action_button.dart';

class CallScreenWidget extends StatefulWidget {
  final SIPUAHelper? _helper;
  final Call? _call;

  CallScreenWidget(this._helper, this._call, {Key? key}) : super(key: key);

  @override
  State<CallScreenWidget> createState() => _MyCallScreenWidget();
}

class _MyCallScreenWidget extends State<CallScreenWidget>
    implements SipUaHelperListener {
  RTCVideoRenderer? _localRenderer = RTCVideoRenderer();
  RTCVideoRenderer? _remoteRenderer = RTCVideoRenderer();
  double? _localVideoHeight;
  double? _localVideoWidth;
  EdgeInsetsGeometry? _localVideoMargin;
  MediaStream? _localStream;
  MediaStream? _remoteStream;

  bool _showNumPad = false;
  final ValueNotifier<String> _timeLabel = ValueNotifier<String>('00:00');
  bool _audioMuted = false;
  bool _videoMuted = false;
  bool _speakerOn = false;
  bool _hold = false;
  bool _mirror = true;
  String? _holdOriginator;
  bool _callConfirmed = false;
  CallStateEnum _state = CallStateEnum.NONE;

  late String _transferTarget;
  late Timer _timer;

  SIPUAHelper? get helper => widget._helper;

  bool get voiceOnly => call!.voiceOnly && !call!.remote_has_video;

  String? get remoteIdentity => call!.remote_identity;

  String? get direction => call!.direction;

  Call? get call => widget._call;

  @override
  initState() {
    super.initState();
    AppLogger.i('Initializing CallScreen');
    _initRenderers();
    helper!.addSipUaHelperListener(this);
    _startTimer();
  }

  @override
  deactivate() {
    super.deactivate();
    AppLogger.i('Deactivating CallScreen');
    helper!.removeSipUaHelperListener(this);
    _disposeRenderers();
  }

  void _startTimer() {
    AppLogger.d('Starting call timer');
    _timer = Timer.periodic(Duration(seconds: 1), (Timer timer) {
      Duration duration = Duration(seconds: timer.tick);
      if (mounted) {
        _timeLabel.value = [duration.inMinutes, duration.inSeconds]
            .map((seg) => seg.remainder(60).toString().padLeft(2, '0'))
            .join(':');
      } else {
        _timer.cancel();
        AppLogger.d('Timer cancelled - widget not mounted');
      }
    });
  }

  void _initRenderers() async {
    AppLogger.d('Initializing video renderers');
    if (_localRenderer != null) {
      await _localRenderer!.initialize();
    }
    if (_remoteRenderer != null) {
      await _remoteRenderer!.initialize();
    }
  }

  void _disposeRenderers() {
    AppLogger.d('Disposing video renderers');
    if (_localRenderer != null) {
      _localRenderer!.dispose();
      _localRenderer = null;
    }
    if (_remoteRenderer != null) {
      _remoteRenderer!.dispose();
      _remoteRenderer = null;
    }
  }

  @override
  void callStateChanged(Call call, CallState callState) {
    AppLogger.d('Call state changed: ${callState.state}');
    
    if (callState.state == CallStateEnum.HOLD ||
        callState.state == CallStateEnum.UNHOLD) {
      _hold = callState.state == CallStateEnum.HOLD;
      _holdOriginator = callState.originator;
      AppLogger.i('Call ${_hold ? 'held' : 'unheld'} by ${_holdOriginator}');
      setState(() {});
      return;
    }

    if (callState.state == CallStateEnum.MUTED) {
      if (callState.audio!) _audioMuted = true;
      if (callState.video!) _videoMuted = true;
      AppLogger.i('Call muted - audio: ${callState.audio}, video: ${callState.video}');
      setState(() {});
      return;
    }

    if (callState.state == CallStateEnum.UNMUTED) {
      if (callState.audio!) _audioMuted = false;
      if (callState.video!) _videoMuted = false;
      AppLogger.i('Call unmuted - audio: ${callState.audio}, video: ${callState.video}');
      setState(() {});
      return;
    }

    if (callState.state != CallStateEnum.STREAM) {
      _state = callState.state;
    }

    switch (callState.state) {
      case CallStateEnum.STREAM:
        AppLogger.d('Handling call stream');
        _handleStreams(callState);
        break;
      case CallStateEnum.ENDED:
      case CallStateEnum.FAILED:
        AppLogger.i('Call ended/failed - returning to dialpad');
        _backToDialPad();
        break;
      case CallStateEnum.UNMUTED:
      case CallStateEnum.MUTED:
      case CallStateEnum.CONNECTING:
      case CallStateEnum.PROGRESS:
      case CallStateEnum.ACCEPTED:
      case CallStateEnum.CONFIRMED:
        AppLogger.i('Call confirmed');
        setState(() => _callConfirmed = true);
        break;
      case CallStateEnum.HOLD:
      case CallStateEnum.UNHOLD:
      case CallStateEnum.NONE:
      case CallStateEnum.CALL_INITIATION:
      case CallStateEnum.REFER:
        break;
    }
  }

  @override
  void transportStateChanged(TransportState state) {}

  @override
  void registrationStateChanged(RegistrationState state) {}

  void _cleanUp() {
    if (_localStream == null) return;
    _localStream?.getTracks().forEach((track) {
      track.stop();
    });
    _localStream!.dispose();
    _localStream = null;
  }

  void _backToDialPad() {
    _timer.cancel();
    Timer(Duration(seconds: 2), () {
      Navigator.of(context).pop();
    });
    _cleanUp();
  }

  void _handleStreams(CallState event) async {
    AppLogger.d('Handling call streams');
    MediaStream? stream = event.stream;
    if (event.originator == 'local') {
      AppLogger.d('Setting up local stream');
      if (_localRenderer != null) {
        _localRenderer!.srcObject = stream;
      }

      if (!kIsWeb &&
          !WebRTC.platformIsDesktop &&
          event.stream?.getAudioTracks().isNotEmpty == true) {
        event.stream?.getAudioTracks().first.enableSpeakerphone(false);
      }
      _localStream = stream;
    }
    if (event.originator == 'remote') {
      AppLogger.d('Setting up remote stream');
      if (_remoteRenderer != null) {
        _remoteRenderer!.srcObject = stream;
      }
      _remoteStream = stream;
    }

    setState(() {
      _resizeLocalVideo();
    });
  }

  void _resizeLocalVideo() {
    _localVideoMargin = _remoteStream != null
        ? EdgeInsets.only(top: 15, right: 15)
        : EdgeInsets.all(0);
    _localVideoWidth = _remoteStream != null
        ? MediaQuery.of(context).size.width / 4
        : MediaQuery.of(context).size.width;
    _localVideoHeight = _remoteStream != null
        ? MediaQuery.of(context).size.height / 4
        : MediaQuery.of(context).size.height;
  }

  void _handleHangup() {
    AppLogger.i('Hanging up call');
    call!.hangup({'status_code': 603});
    _timer.cancel();
  }

  void _handleAccept() async {
    AppLogger.i('Accepting call');
    bool remoteHasVideo = call!.remote_has_video;
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
        AppLogger.d('Getting display media for web');
        mediaStream =
            await navigator.mediaDevices.getDisplayMedia(mediaConstraints);
        MediaStream userStream =
            await navigator.mediaDevices.getUserMedia(mediaConstraints);
        mediaStream.addTrack(userStream.getAudioTracks()[0], addToNative: true);
      } else {
        if (!remoteHasVideo) {
          mediaConstraints['video'] = false;
        }
        AppLogger.d('Getting user media');
        mediaStream = await navigator.mediaDevices.getUserMedia(mediaConstraints);
      }

      call!.answer(helper!.buildCallOptions(!remoteHasVideo),
          mediaStream: mediaStream);
      AppLogger.i('Call accepted successfully');
    } catch (e, stackTrace) {
      AppLogger.e('Error accepting call', e, stackTrace);
    }
  }

  void _switchCamera() {
    AppLogger.d('Switching camera');
    if (_localStream != null) {
      Helper.switchCamera(_localStream!.getVideoTracks()[0]);
      setState(() {
        _mirror = !_mirror;
      });
    }
  }

  void _muteAudio() {
    AppLogger.d('Toggling audio mute');
    if (_audioMuted) {
      call!.unmute(true, false);
    } else {
      call!.mute(true, false);
    }
  }

  void _muteVideo() {
    AppLogger.d('Toggling video mute');
    if (_videoMuted) {
      call!.unmute(false, true);
    } else {
      call!.mute(false, true);
    }
  }

  void _handleHold() {
    AppLogger.d('Toggling call hold');
    if (_hold) {
      call!.unhold();
    } else {
      call!.hold();
    }
  }

  void _handleTransfer() {
    AppLogger.d('Initiating call transfer');
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Enter target to transfer.'),
          content: TextField(
            onChanged: (String text) {
              setState(() {
                _transferTarget = text;
              });
            },
            decoration: InputDecoration(
              hintText: 'URI or Username',
            ),
            textAlign: TextAlign.center,
          ),
          actions: <Widget>[
            TextButton(
              child: Text('Ok'),
              onPressed: () {
                AppLogger.i('Transferring call to: $_transferTarget');
                call!.refer(_transferTarget);
                Navigator.of(context).pop();
              },
            ),
            TextButton(
              child: Text('Cancel'),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
    );
  }

  void _handleDtmf(String tone) {
    AppLogger.d('Sending DTMF tone: $tone');
    call!.sendDTMF(tone);
  }

  void _handleKeyPad() {
    AppLogger.d('Toggling keypad');
    setState(() {
      _showNumPad = !_showNumPad;
    });
  }

  void _handleVideoUpgrade() {
    AppLogger.d('Handling video upgrade');
    if (voiceOnly) {
      setState(() {
        call!.voiceOnly = false;
      });
      helper!.renegotiate(
          call: call!,
          voiceOnly: false,
          done: (IncomingMessage? incomingMessage) {
            AppLogger.d('Video upgrade negotiation completed');
          });
    } else {
      helper!.renegotiate(
          call: call!,
          voiceOnly: true,
          done: (IncomingMessage? incomingMessage) {
            AppLogger.d('Voice only negotiation completed');
          });
    }
  }

  void _toggleSpeaker() {
    AppLogger.d('Toggling speaker');
    if (_localStream != null) {
      _speakerOn = !_speakerOn;
      if (!kIsWeb) {
        _localStream!.getAudioTracks()[0].enableSpeakerphone(_speakerOn);
      }
    }
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
            padding: const EdgeInsets.all(3),
            child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: row
                    .map((label) => ActionButton(
                          title: label.keys.first,
                          subTitle: label.values.first,
                          onPressed: () => _handleDtmf(label.keys.first),
                          number: true,
                        ))
                    .toList())))
        .toList();
  }

  Widget _buildActionButtons() {
    final hangupBtn = ActionButton(
      title: "hangup",
      onPressed: () => _handleHangup(),
      icon: Icons.call_end,
      fillColor: Colors.red,
    );

    final hangupBtnInactive = ActionButton(
      title: "hangup",
      onPressed: () {},
      icon: Icons.call_end,
      fillColor: Colors.grey,
    );

    final basicActions = <Widget>[];
    final advanceActions = <Widget>[];
    final advanceActions2 = <Widget>[];

    switch (_state) {
      case CallStateEnum.NONE:
      case CallStateEnum.CONNECTING:
        if (direction == 'incoming') {
          basicActions.add(ActionButton(
            title: "Accept",
            fillColor: Colors.green,
            icon: Icons.phone,
            onPressed: () => _handleAccept(),
          ));
          basicActions.add(hangupBtn);
        } else {
          basicActions.add(hangupBtn);
        }
        break;
      case CallStateEnum.ACCEPTED:
      case CallStateEnum.CONFIRMED:
        {
          advanceActions.add(ActionButton(
            title: _audioMuted ? 'unmute' : 'mute',
            icon: _audioMuted ? Icons.mic_off : Icons.mic,
            checked: _audioMuted,
            onPressed: () => _muteAudio(),
          ));

          if (voiceOnly) {
            advanceActions.add(ActionButton(
              title: "keypad",
              icon: Icons.dialpad,
              onPressed: () => _handleKeyPad(),
            ));
          } else {
            advanceActions.add(ActionButton(
              title: "switch camera",
              icon: Icons.switch_video,
              onPressed: () => _switchCamera(),
            ));
          }

          if (voiceOnly) {
            advanceActions.add(ActionButton(
              title: _speakerOn ? 'speaker off' : 'speaker on',
              icon: _speakerOn ? Icons.volume_off : Icons.volume_up,
              checked: _speakerOn,
              onPressed: () => _toggleSpeaker(),
            ));
            advanceActions2.add(ActionButton(
              title: 'request video',
              icon: Icons.videocam,
              onPressed: () => _handleVideoUpgrade(),
            ));
          } else {
            advanceActions.add(ActionButton(
              title: _videoMuted ? "camera on" : 'camera off',
              icon: _videoMuted ? Icons.videocam : Icons.videocam_off,
              checked: _videoMuted,
              onPressed: () => _muteVideo(),
            ));
          }

          basicActions.add(ActionButton(
            title: _hold ? 'unhold' : 'hold',
            icon: _hold ? Icons.play_arrow : Icons.pause,
            checked: _hold,
            onPressed: () => _handleHold(),
          ));

          basicActions.add(hangupBtn);

          if (_showNumPad) {
            basicActions.add(ActionButton(
              title: "back",
              icon: Icons.keyboard_arrow_down,
              onPressed: () => _handleKeyPad(),
            ));
          } else {
            basicActions.add(ActionButton(
              title: "transfer",
              icon: Icons.phone_forwarded,
              onPressed: () => _handleTransfer(),
            ));
          }
        }
        break;
      case CallStateEnum.FAILED:
      case CallStateEnum.ENDED:
        basicActions.add(hangupBtnInactive);
        break;
      case CallStateEnum.PROGRESS:
        basicActions.add(hangupBtn);
        break;
      default:
        print('Other state => $_state');
        break;
    }

    final actionWidgets = <Widget>[];

    if (_showNumPad) {
      actionWidgets.addAll(_buildNumPad());
    } else {
      if (advanceActions2.isNotEmpty) {
        actionWidgets.add(
          Padding(
            padding: const EdgeInsets.all(3),
            child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: advanceActions2),
          ),
        );
      }
      if (advanceActions.isNotEmpty) {
        actionWidgets.add(
          Padding(
            padding: const EdgeInsets.all(3),
            child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: advanceActions),
          ),
        );
      }
    }

    actionWidgets.add(
      Padding(
        padding: const EdgeInsets.all(3),
        child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: basicActions),
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisAlignment: MainAxisAlignment.end,
      children: actionWidgets,
    );
  }

  Widget _buildContent() {
    Color? textColor = Theme.of(context).textTheme.bodyMedium?.color;
    final stackWidgets = <Widget>[];

    if (!voiceOnly && _remoteStream != null) {
      stackWidgets.add(
        Center(
          child: RTCVideoView(
            _remoteRenderer!,
            objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
          ),
        ),
      );
    }

    if (!voiceOnly && _localStream != null) {
      stackWidgets.add(
        AnimatedContainer(
          child: RTCVideoView(
            _localRenderer!,
            mirror: _mirror,
            objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
          ),
          height: _localVideoHeight,
          width: _localVideoWidth,
          alignment: Alignment.topRight,
          duration: Duration(milliseconds: 300),
          margin: _localVideoMargin,
        ),
      );
    }
    if (voiceOnly || !_callConfirmed) {
      stackWidgets.addAll(
        [
          Positioned(
            top: MediaQuery.of(context).size.height / 8,
            left: 0,
            right: 0,
            child: Center(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.all(6),
                      child: Text(
                        (voiceOnly ? 'VOICE CALL' : 'VIDEO CALL') +
                            (_hold
                                ? ' PAUSED BY ${_holdOriginator}'
                                : ''),
                        style: TextStyle(fontSize: 24, color: textColor),
                      ),
                    ),
                  ),
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.all(6),
                      child: Text(
                        '$remoteIdentity',
                        style: TextStyle(fontSize: 18, color: textColor),
                      ),
                    ),
                  ),
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.all(6),
                      child: ValueListenableBuilder<String>(
                        valueListenable: _timeLabel,
                        builder: (context, value, child) {
                          return Text(
                            _timeLabel.value,
                            style: TextStyle(fontSize: 14, color: textColor),
                          );
                        },
                      ),
                    ),
                  )
                ],
              ),
            ),
          ),
        ],
      );
    }

    return Stack(
      children: stackWidgets,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: Text('[$direction] ${_state.name}'),
      ),
      body: _buildContent(),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: Container(
        width: 320,
        padding: EdgeInsets.only(bottom: 24.0),
        child: _buildActionButtons(),
      ),
    );
  }

  @override
  void onNewReinvite(ReInvite event) {
    AppLogger.d('Received reinvite request');
    if (event.accept == null) return;
    if (event.reject == null) return;
    if (voiceOnly && (event.hasVideo ?? false)) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext context) {
          return AlertDialog(
            title: Text('Upgrade to video?'),
            content: Text('$remoteIdentity is inviting you to video call'),
            alignment: Alignment.center,
            actionsAlignment: MainAxisAlignment.spaceBetween,
            actions: <Widget>[
              TextButton(
                child: const Text('Cancel'),
                onPressed: () {
                  AppLogger.i('Rejecting video upgrade');
                  event.reject!.call({'status_code': 607});
                  Navigator.of(context).pop();
                },
              ),
              TextButton(
                child: const Text('OK'),
                onPressed: () {
                  AppLogger.i('Accepting video upgrade');
                  event.accept!.call({});
                  setState(() {
                    call!.voiceOnly = false;
                    _resizeLocalVideo();
                  });
                  Navigator.of(context).pop();
                },
              ),
            ],
          );
        },
      );
    }
  }

  @override
  void onNewMessage(SIPMessageRequest msg) {
    AppLogger.d('Received new SIP message');
  }

  @override
  void onNewNotify(Notify ntf) {
    AppLogger.d('Received new SIP notify');
  }
}
