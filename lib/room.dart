import 'package:flutter_webrtc/webrtc.dart';

class Room {
  final String id;
  final String creatorId;
  final RTCSessionDescription offer;
  // final RTCSessionDescription answer;

  Room(this.id, this.creatorId, this.offer);

  Room.fromJson(Map<String, dynamic> json)
      : id = json['id'],
        creatorId = json['creatorId'],
        offer =
            RTCSessionDescription(json['offer']['sdp'], json['offer']['type']);
  // answer = json['answer'];

  Map<String, dynamic> toJson() => {
        'id': id,
        'creatorId': creatorId,
        'offer': offer,
        // 'answer': answer,
      };
}
