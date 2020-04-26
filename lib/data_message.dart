class DataMessage {
  final String type;
  final Map<String, dynamic> payload;

  DataMessage(this.type, this.payload);

  Map<String, dynamic> toJson() => {
        'type': type,
        'payload': payload,
      };
}
