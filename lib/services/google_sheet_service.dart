import 'dart:convert';
import 'package:http/http.dart' as http;

class GoogleSheetService {

  // 🔴 PASTE YOUR WEB APP URL HERE
  static const String url =
      "https://script.google.com/macros/s/AKfycbzDL_qSK74_ZiZkMf-_TWuUopMPbHLTLe9e10Gp4AKU6jPkTG5FBvQ4zg8np7HlaJYR/exec";

  static Future<void> sendAttendance({
    required String email,
    required String date,
    required String time,
    required String status,
    required String location,
  }) async {

    await http.post(
      Uri.parse(url),
      body: jsonEncode({
        "email": email,
        "date": date,
        "time": time,
        "status": status,
        "location": location,
      }),
      headers: {
        "Content-Type": "application/json",
      },
    );
  }
}