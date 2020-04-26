import 'dart:async';
import 'dart:convert';

import 'dart:developer' as developer;
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/webrtc.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:webrtc_chat_mobile/data_message.dart';
import 'package:webrtc_chat_mobile/room.dart';
import 'package:barcode_scan/barcode_scan.dart';
import 'package:sensors/sensors.dart';
import 'package:stream_transform/stream_transform.dart';

void main() => runApp(MyApp());

class MyApp extends StatelessWidget {
  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Demo',
      theme: ThemeData(
          // This is the theme of your application.
          //
          // Try running your application with "flutter run". You'll see the
          // application has a blue toolbar. Then, without quitting the app, try
          // changing the primarySwatch below to Colors.green and then invoke
          // "hot reload" (press "r" in the console where you ran "flutter run",
          // or simply save your changes to "hot reload" in a Flutter IDE).
          // Notice that the counter didn't reset back to zero; the application
          // is not restarted.
          primarySwatch: Colors.blue,
          buttonTheme: ButtonThemeData(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
            textTheme: ButtonTextTheme.primary,
          )),
      home: MyHomePage(title: 'Flutter WebRTC App'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  MyHomePage({Key key, this.title}) : super(key: key);

  // This widget is the home page of your application. It is stateful, meaning
  // that it has a State object (defined below) that contains fields that affect
  // how it looks.

  // This class is the configuration for the state. It holds the values (in this
  // case the title) provided by the parent (in this case the App widget) and
  // used by the build method of the State. Fields in a Widget subclass are
  // always marked "final".

  final String title;

  @override
  _MyHomePageState createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  String _peerId = '';
  dynamic _room;
  RTCDataChannel _chatChannel;
  RTCPeerConnection _peerConnection;
  bool _isConnecting = false;

  List<String> _messages = [];
  final _newMessageFieldController = TextEditingController();

  List<StreamSubscription<dynamic>> _streamSubscriptions =
      <StreamSubscription<dynamic>>[];

  Map<String, dynamic> _rtcConfig = {
    "iceServers": [
      {"url": "stun:stun.l.google.com:19302"},
    ]
  };

  final Map<String, dynamic> _rtcConstraints = {
    'mandatory': {
      'OfferToReceiveAudio': false,
      'OfferToReceiveVideo': false,
    },
    'optional': [],
  };

  void _scanQRCode() async {
    var result = await BarcodeScanner.scan();

    if (result.type == ResultType.Barcode &&
        result.format == BarcodeFormat.qr) {
      _setPeerId(result.rawContent);
      _joinRoom();
    }
  }

  void _joinRoom() async {
    setState(() {
      _isConnecting = true;
    });
    var roomDoc = Firestore.instance.collection('rooms').document(_peerId);
    var roomSnapshot = await roomDoc.get();
    if (roomSnapshot.exists) {
      var room = Room.fromJson(roomSnapshot.data);
      var pc = await _createNewRTCConnection();
      setState(() {
        _peerConnection = pc;
        _messages = [];
      });

      var _dataChannelDict = new RTCDataChannelInit();
      _dataChannelDict.id = room.dataChannelId;
      _dataChannelDict.negotiated = true;
      _dataChannelDict.protocol = 'sctp';
      _chatChannel = await _peerConnection.createDataChannel(
          'chat-channel', _dataChannelDict);
      _onDataChannel(_chatChannel);

      roomDoc
          .snapshots()
          .listen((payload) => _room = payload.exists ? payload : null);

      // Listening for remote ICE candidates below
      roomDoc.collection('callerCandidates').snapshots().listen((data) async {
        data.documentChanges.forEach((change) async {
          if (change.type == DocumentChangeType.added) {
            var data = change.document.data;
            var candidate = new RTCIceCandidate(
                data['candidate'], data['sdpMid'], data['sdpMLineIndex']);
            await _peerConnection.addCandidate(candidate);
          }
        });
      });
      // Code for collecting ICE candidates above

      // Code for collecting ICE candidates below
      var calleeCandidatesCollection = roomDoc.collection('calleeCandidates');
      _peerConnection.onIceCandidate = (RTCIceCandidate candidate) {
        calleeCandidatesCollection.add(candidate.toMap());
      };

      // Code for creating SDP answer below
      await _peerConnection.setRemoteDescription(room.offer);
      var answer = await _peerConnection.createAnswer(_rtcConstraints);
      await _peerConnection.setLocalDescription(answer);

      await roomDoc.updateData({
        'answer': {
          'type': answer.type,
          'sdp': answer.sdp,
        },
      });
      // Code for creating SDP answer above
    } else {
      _closeRTCConnection();

      return showDialog<void>(
        context: context,
        barrierDismissible: false, // user must tap button!
        builder: (BuildContext context) {
          return AlertDialog(
            title: Text('Not found'),
            content: SingleChildScrollView(
              child: ListBody(
                children: <Widget>[
                  Text('There is no Room with ID: $_peerId :('),
                ],
              ),
            ),
            actions: <Widget>[
              FlatButton(
                child: Text('Ok'),
                onPressed: () {
                  Navigator.of(context).pop();
                },
              ),
            ],
          );
        },
      );
    }

    developer.log('_connectToPeer');
  }

  void _setPeerId(String id) {
    setState(() {
      _peerId = id;
    });
  }

  void _sendNewMessage(String text) {
    setState(() {
      _messages.add(text);
      _chatChannel.send(RTCDataChannelMessage(text));
      _newMessageFieldController.clear();
    });
  }

  bool get isChatConnected {
    return _room != null &&
        _chatChannel != null &&
        _chatChannel.state == RTCDataChannelState.RTCDataChannelOpen;
  }

  bool get isChatConnecting {
    return _isConnecting;
  }

  /// Send some sample messages and handle incoming messages.
  _onDataChannel(RTCDataChannel channel) {
    setState(() => _chatChannel = channel);

    channel.onMessage = (message) {
      if (message.type == MessageType.text) {
        setState(() {
          _messages.add(message.text);
        });
        print(message.text);
      } else {
        // do something with message.binary
      }
    };

    channel.onDataChannelState = (state) {
      switch (state) {
        case RTCDataChannelState.RTCDataChannelOpen:
          print('onDataChannelState: Open');
          setState(() {
            final messageText = 'Hi! I just connected';
            channel.send(RTCDataChannelMessage(messageText));
            _isConnecting = false;
          });
          break;

        case RTCDataChannelState.RTCDataChannelClosed:
          print('onDataChannelState: Closed');
          _closeRTCConnection();
          break;
        default:
      }
    };
  }

  _closeRTCConnection() async {
    if (_peerConnection != null) {
      if (_chatChannel != null) {
        await _chatChannel.close();
      }
      await _peerConnection.close();
      setState(() {
        _chatChannel = null;
        _peerConnection = null;
        _isConnecting = false;
      });
    }
  }

  // Platform messages are asynchronous, so we initialize in an async method.
  _createNewRTCConnection() async {
    final Map<String, dynamic> _config = {
      "mandatory": {},
      "optional": [
        {"DtlsSrtpKeyAgreement": true},
      ],
    };

    _closeRTCConnection();

    try {
      var pc = await createPeerConnection(_rtcConfig, _config);
      print('createPeerConnection');

      pc.onSignalingState = (state) => print(state);
      pc.onIceGatheringState = (state) {
        print(state);
        switch (state) {
          case RTCIceGatheringState.RTCIceGatheringStateComplete:
            break;
          default:
        }
      };

      pc.onRenegotiationNeeded = () => print('onRenegotiationNeeded');
      pc.onIceConnectionState = (state) {
        print(state);
        switch (state) {
          case RTCIceConnectionState.RTCIceConnectionStateDisconnected:
          case RTCIceConnectionState.RTCIceConnectionStateFailed:
            _closeRTCConnection();
            break;
          case RTCIceConnectionState.RTCIceConnectionStateConnected:
            break;
          default:
        }
      };

      return pc;
    } catch (e) {
      print(e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    // This method is rerun every time setState is called, for instance as done
    // by the _incrementCounter method above.
    //
    // The Flutter framework has been optimized to make rerunning build methods
    // fast, so that you can just rebuild anything that needs updating rather
    // than having to individually change instances of widgets.
    return Scaffold(
      appBar: AppBar(
        // Here we take the value from the MyHomePage object that was created by
        // the App.build method, and use it to set our appbar title.
        title: Text(widget.title),
      ),
      body: Center(
        // Center is a layout widget. It takes a single child and positions it
        // in the middle of the parent.
        child: Container(
          padding: EdgeInsets.all(20),
          child: Column(
            // Column is also a layout widget. It takes a list of children and
            // arranges them vertically. By default, it sizes itself to fit its
            // children horizontally, and tries to be as tall as its parent.
            //
            // Invoke "debug painting" (press "p" in the console, choose the
            // "Toggle Debug Paint" action from the Flutter Inspector in Android
            // Studio, or the "Toggle Debug Paint" command in Visual Studio Code)
            // to see the wireframe for each widget.
            //
            // Column has various properties to control how it sizes itself and
            // how it positions its children. Here we use mainAxisAlignment to
            // center the children vertically; the main axis here is the vertical
            // axis because Columns are vertical (the cross axis would be
            // horizontal).
            mainAxisAlignment: MainAxisAlignment.start,
            children: <Widget>[
              if (!isChatConnected)
                Column(
                  children: <Widget>[
                    TextField(
                        onChanged: _setPeerId,
                        decoration:
                            InputDecoration(hintText: 'Enter a Peer ID')),
                    Container(
                        margin: EdgeInsets.only(top: 10),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: <Widget>[
                            RaisedButton(
                              onPressed: _peerId != '' &&
                                      !isChatConnecting &&
                                      !isChatConnected
                                  ? _joinRoom
                                  : null,
                              child: Text('Connect',
                                  style: TextStyle(fontSize: 14)),
                            ),
                            SizedBox(width: 20),
                            RaisedButton(
                              onPressed: !isChatConnecting && !isChatConnected
                                  ? _scanQRCode
                                  : null,
                              child: Text('Scan QR code',
                                  style: TextStyle(fontSize: 14)),
                            ),
                          ],
                        )),
                  ],
                ),
              if (isChatConnected)
                Column(
                  children: <Widget>[
                    Text(
                      'You\'re in Chat: $_peerId',
                      style: TextStyle(fontSize: 18),
                    ),
                    TextField(
                        onSubmitted: _sendNewMessage,
                        controller: _newMessageFieldController,
                        decoration:
                            InputDecoration(hintText: 'Write a message...')),
                    ListView.builder(
                        shrinkWrap: true,
                        padding: const EdgeInsets.all(8),
                        itemCount: _messages.length,
                        itemBuilder: (BuildContext context, int index) {
                          return Container(
                            height: 50,
                            child: Center(child: Text('${_messages[index]}')),
                          );
                        })
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    super.dispose();
    for (StreamSubscription<dynamic> subscription in _streamSubscriptions) {
      subscription.cancel();
    }
  }

  @override
  void initState() {
    super.initState();
    _streamSubscriptions.add(userAccelerometerEvents
        // .transform(StreamTransformer.fromBind(
        //     (s) => s.throttle(const Duration(milliseconds: 50))))
        .listen((UserAccelerometerEvent event) {
      if (isChatConnected) {
        var moveEvent = DataMessage(
            'remote_move', {'x': event.x, 'y': event.y, 'z': event.z});
        print(jsonEncode(moveEvent));
        _chatChannel.send(RTCDataChannelMessage(jsonEncode(moveEvent)));
      }
    }));
    // _streamSubscriptions.add(gyroscopeEvents.listen((GyroscopeEvent event) {
    //   setState(() {
    //     _gyroscopeValues = <double>[event.x, event.y, event.z];
    //   });
    // }));
    // _streamSubscriptions
    //     .add(userAccelerometerEvents.listen((UserAccelerometerEvent event) {
    //   setState(() {
    //     _userAccelerometerValues = <double>[event.x, event.y, event.z];
    //   });
    // }));
  }
}
