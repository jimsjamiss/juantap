import 'dart:convert';
import 'package:http/http.dart' as http;

class EmailService {
  static Future<bool> sendOtpEmail({
    required String userEmail,
    required String otpCode,
  }) async {
    const serviceId = 'service_2szlwem';
    const templateId = 'template_drzcd7p';
    const userId = '7jNR_ojNzuUqezHRi';

    final url = Uri.parse('https://api.emailjs.com/api/v1.0/email/send');
    final response = await http.post(
      url,
      headers: {
        'origin': 'http://localhost',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'service_id': serviceId,
        'template_id': templateId,
        'user_id': userId,
        'template_params': {
          'user_email': userEmail,
          'otp_code': otpCode,
        }
      }),
    );

    return response.statusCode == 200;
  }
}
