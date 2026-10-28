class CheckinResult {
  const CheckinResult({required this.checkinId, required this.message});

  final int checkinId;
  final String message;

  factory CheckinResult.fromJson(Map<String, dynamic> json) {
    if (json.length != 2 ||
        !json.containsKey('checkin_id') ||
        !json.containsKey('message')) {
      throw const FormatException('Unexpected check-in response.');
    }

    final checkinId = json['checkin_id'];
    final message = json['message'];
    if (checkinId is! int ||
        checkinId <= 0 ||
        message is! String ||
        message.trim().isEmpty) {
      throw const FormatException('Invalid check-in response.');
    }

    return CheckinResult(checkinId: checkinId, message: message);
  }
}
