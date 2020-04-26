import 'package:flutter_webrtc/webrtc.dart';

class Room {
  final String id;
  final String creatorId;
  final RTCSessionDescription offer;
  final int dataChannelId;
  // final RTCSessionDescription answer;

  Room(this.id, this.creatorId, this.offer, this.dataChannelId);

  Room.fromJson(Map<String, dynamic> json)
      : id = json['id'],
        creatorId = json['creatorId'],
        offer =
            RTCSessionDescription(json['offer']['sdp'], json['offer']['type']),
        dataChannelId = json['dataChannelId'];
  // answer = json['answer'];

  Map<String, dynamic> toJson() => {
        'id': id,
        'creatorId': creatorId,
        'offer': offer,
        'dataChannelId': dataChannelId,
        // 'answer': answer,
      };
}
