import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class AuthService {
  static const String baseUrl =
      "http://192.168.8.113:8000/auth"; // should change later

  // 🔹 Register function
  static Future<Map<String, dynamic>> register(
    Map<String, dynamic> userData,
  ) async {
    final url = Uri.parse('$baseUrl/register');
    final response = await http.post(
      url,
      headers: {"Content-Type": "application/json"},
      body: jsonEncode(userData),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final prefs = await SharedPreferences.getInstance();

      // 🟢 Save basic user info
      await prefs.setString('patient_id', data['patient_id']);
      await prefs.setString('national_id', data['national_id']);
      await prefs.setString('hospital_id', data['hospital_id']);
      await prefs.setString('firebase_uid', data['firebase_uid']);

      return data;
    } else {
      // ❗ handle both 'detail' and 'message' for flexibility
      final errorBody = jsonDecode(response.body);
      final errorMsg =
          errorBody['detail'] ?? errorBody['message'] ?? 'Registration failed';
      throw Exception(errorMsg);
    }
  }

  static Future<Map<String, dynamic>> login(
    String nationalId,
    String password,
  ) async {
    final url = Uri.parse('$baseUrl/login');
    final response = await http.post(
      url,
      headers: {"Content-Type": "application/json"},
      body: jsonEncode({"national_id": nationalId, "password": password}),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final prefs = await SharedPreferences.getInstance();

      await prefs.setString('token', data['token']);
      final patient = data['patient'];
      await prefs.setString('patient_id', patient['patient_id']);
      await prefs.setString('patient_name', patient['name']);
      await prefs.setString('national_id', patient['national_id']);
      await prefs.setString('hospital', patient['hospital_id']);
      await prefs.setString('gender', patient['gender'] ?? 'N/A');
      await prefs.setString('address', patient['address'] ?? 'N/A');
      await prefs.setString('phone_number', patient['phone_number'] ?? 'N/A');
      await prefs.setString('email', patient['email'] ?? 'N/A');
      await prefs.setString('city', patient['city'] ?? 'N/A');

      return data;
    } else {
      final errorBody = jsonDecode(response.body);
      throw Exception(
        errorBody['detail'] ?? errorBody['message'] ?? 'Login failed',
      );
    }
  }
}
