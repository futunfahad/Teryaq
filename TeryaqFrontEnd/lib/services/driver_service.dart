import 'dart:convert';
import 'package:flutter/foundation.dart'; // debugPrint
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// ===============================================================
///   DRIVER SERVICE  (FULL + CLEAN + TOKEN-SAFE)
/// ===============================================================
class DriverService {
  // ✅ API (FastAPI)
  static const String apiBaseUrl = "http://192.168.8.113:8000";

  // ✅ VRP Backend (optional)
  static const String vrpBaseUrl = "http://192.168.8.113:8070";

  // ===============================================================
  // Helper: create email from national id
  // ===============================================================
  static String _driverEmailFromNationalId(String nationalId) {
    return "$nationalId@driver.teryag.com";
  }

  // ===============================================================
  // LOGIN → Firebase + ID token + national_id (stores token in prefs)
  // ===============================================================
  static Future<void> loginDriver({
    required String nationalId,
    required String password,
  }) async {
    try {
      final String email = _driverEmailFromNationalId(nationalId);

      final cred = await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      // getIdToken() returns String? → must handle null
      final String? token = await cred.user?.getIdToken(true);
      if (token == null || token.isEmpty) {
        throw Exception("Failed to obtain Firebase ID token (null/empty)");
      }

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString("id_token", token);
      await prefs.setString("driver_national_id", nationalId);

      debugPrint("DriverService.loginDriver → token saved to prefs");
    } on FirebaseAuthException {
      rethrow;
    }
  }

  // ===============================================================
  // Optional: Logout helper (clears local prefs)
  // ===============================================================
  static Future<void> logoutDriver() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove("id_token");
    await prefs.remove("driver_uuid");
    await prefs.remove("driver_national_id");
    await FirebaseAuth.instance.signOut();
  }

  // ===============================================================
  // Fetch Firebase token (prefer Firebase currentUser; fallback to prefs)
  // - forceRefresh: refresh token if 401/403 happens
  // ===============================================================
  static Future<String> _getToken({bool forceRefresh = false}) async {
    final user = FirebaseAuth.instance.currentUser;
    final prefs = await SharedPreferences.getInstance();

    if (user != null) {
      final String? fresh = await user.getIdToken(forceRefresh);
      if (fresh != null && fresh.isNotEmpty) {
        await prefs.setString("id_token", fresh);
        return fresh;
      }
      // If Firebase exists but token is null, fall back to prefs below
      debugPrint(
        "DriverService._getToken → Firebase token null, fallback to prefs",
      );
    }

    final String? cached = prefs.getString("id_token");
    if (cached == null || cached.isEmpty) {
      throw Exception(
        "Driver not logged in (missing Firebase user + id_token)",
      );
    }
    return cached;
  }

  // ===============================================================
  //  Secured GET call
  // ===============================================================
  static Future<dynamic> _secureGet(String endpoint) async {
    Future<http.Response> doReq(String token) {
      final url = Uri.parse("$apiBaseUrl$endpoint");
      return http.get(
        url,
        headers: {
          "Authorization": "Bearer $token",
          "Accept": "application/json",
          "Content-Type": "application/json",
        },
      );
    }

    String token = await _getToken();
    http.Response resp = await doReq(token);

    debugPrint("DriverService GET $endpoint → ${resp.statusCode}");

    if (resp.statusCode == 401 || resp.statusCode == 403) {
      token = await _getToken(forceRefresh: true);
      resp = await doReq(token);
      debugPrint("DriverService GET (retry) $endpoint → ${resp.statusCode}");
    }

    if (resp.statusCode != 200) {
      debugPrint("DriverService GET $endpoint body → ${resp.body}");
      throw Exception("GET $endpoint failed: ${resp.statusCode} ${resp.body}");
    }

    return jsonDecode(resp.body);
  }

  // ===============================================================
  //  Secured POST call
  // ===============================================================
  static Future<dynamic> _securePost(
    String endpoint,
    Map<String, dynamic> data,
  ) async {
    Future<http.Response> doReq(String token) {
      final url = Uri.parse("$apiBaseUrl$endpoint");
      return http.post(
        url,
        body: jsonEncode(data),
        headers: {
          "Authorization": "Bearer $token",
          "Accept": "application/json",
          "Content-Type": "application/json",
        },
      );
    }

    String token = await _getToken();
    http.Response resp = await doReq(token);

    debugPrint("DriverService POST $endpoint → ${resp.statusCode}");

    if (resp.statusCode == 401 || resp.statusCode == 403) {
      token = await _getToken(forceRefresh: true);
      resp = await doReq(token);
      debugPrint("DriverService POST (retry) $endpoint → ${resp.statusCode}");
    }

    if (resp.statusCode != 200) {
      debugPrint("DriverService POST $endpoint body → ${resp.body}");
      throw Exception("POST $endpoint failed: ${resp.statusCode} ${resp.body}");
    }

    return jsonDecode(resp.body);
  }

  // ===============================================================
  // START DAY → /driver/orders/start-day
  // ===============================================================
  static Future<Map<String, dynamic>> startDay(String firstOrderId) async {
    final data = await _securePost("/driver/orders/start-day", {
      "first_order_id": firstOrderId,
    });
    return Map<String, dynamic>.from(data);
  }

  // ===============================================================
  // REJECT ORDER → /driver/orders/reject
  // ===============================================================
  static Future<bool> rejectOrder({
    required String orderId,
    String? reason,
  }) async {
    try {
      final data = await _securePost("/driver/orders/reject", {
        "order_id": orderId,
        "reason": reason ?? "reported_by_driver",
      });

      debugPrint("DriverService.rejectOrder → $data");

      if (data is Map && data["success"] == true) return true;
      return false;
    } catch (e) {
      debugPrint("DriverService.rejectOrder error: $e");
      return false;
    }
  }

  // ===============================================================
  // MARK DELIVERED → /driver/orders/mark-delivered
  // ===============================================================
  static Future<Map<String, dynamic>> markOrderDelivered(String orderId) async {
    final data = await _securePost("/driver/orders/mark-delivered", {
      "order_id": orderId,
    });
    return Map<String, dynamic>.from(data);
  }

  // ===============================================================
  // VERIFY OTP → /driver/verify-otp
  // ===============================================================
  static Future<Map<String, dynamic>> verifyOtp(
    String orderId,
    String otp,
  ) async {
    final data = await _securePost("/driver/verify-otp", {
      "order_id": orderId,
      "otp": otp,
    });
    return Map<String, dynamic>.from(data);
  }

  // ===============================================================
  // GET /driver/me
  // ===============================================================
  static Future<Map<String, dynamic>> getDriverProfile() async {
    final data = await _secureGet("/driver/me");

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString("driver_uuid", data["driver_id"]?.toString() ?? "");
    await prefs.setString(
      "driver_national_id",
      data["national_id"]?.toString() ?? "",
    );

    return Map<String, dynamic>.from(data);
  }

  // ===============================================================
  // HOME /driver/home
  // ===============================================================
  static Future<Map<String, dynamic>> getDriverHome() async {
    final data = await _secureGet("/driver/home");
    return Map<String, dynamic>.from(data);
  }

  // ===============================================================
  // DASHBOARD /driver/dashboard
  // ===============================================================
  static Future<Map<String, dynamic>> getDashboardStats() async {
    final data = await _secureGet("/driver/dashboard");
    return Map<String, dynamic>.from(data);
  }

  // ===============================================================
  // DELIVERY /driver/delivery
  // ===============================================================
  static Future<Map<String, dynamic>> getDriverDeliveries() async {
    final data = await _secureGet("/driver/delivery");
    return Map<String, dynamic>.from(data);
  }

  // ===============================================================
  // HISTORY /driver/history
  // ===============================================================
  static Future<Map<String, dynamic>> getDriverHistory() async {
    final data = await _secureGet("/driver/history");
    return Map<String, dynamic>.from(data);
  }

  // ===============================================================
  // NOTIFICATIONS (all driver notifications) → /driver/notifications
  // ===============================================================
  static Future<dynamic> getNotifications() async {
    final data = await _secureGet("/driver/notifications");
    return data; // could be {notifications:[...]} or list (your backend returns a map)
  }

  // ===============================================================
  // NOTIFICATIONS FOR ONE ORDER
  // - tries server filter first /driver/notifications?order_id=...
  // - if backend ignores it, we filter locally safely
  // ===============================================================
  static Future<List<Map<String, dynamic>>> getDriverNotificationsForOrder({
    required String orderId,
  }) async {
    try {
      final token = await _getToken();
      final url = Uri.parse(
        "$apiBaseUrl/driver/notifications?order_id=$orderId",
      );

      final resp = await http.get(
        url,
        headers: {
          "Authorization": "Bearer $token",
          "Accept": "application/json",
          "Content-Type": "application/json",
        },
      );

      if (resp.statusCode != 200) {
        final raw = await getNotifications();
        return _filterNotificationsByOrder(raw, orderId);
      }

      final decoded = jsonDecode(resp.body);
      return _filterNotificationsByOrder(decoded, orderId);
    } catch (e) {
      debugPrint("DriverService.getDriverNotificationsForOrder error: $e");
      return [];
    }
  }

  static List<Map<String, dynamic>> _filterNotificationsByOrder(
    dynamic decoded,
    String orderId,
  ) {
    final out = <Map<String, dynamic>>[];

    final list = (decoded is Map && decoded["notifications"] is List)
        ? decoded["notifications"] as List
        : (decoded is List ? decoded : <dynamic>[]);

    for (final it in list) {
      if (it is! Map) continue;
      final m = Map<String, dynamic>.from(it as Map);
      final oid = (m["order_id"] ?? m["orderId"] ?? "").toString();
      if (oid == orderId) out.add(m);
    }
    return out;
  }

  // ===============================================================
  // ORDER DETAILS → /driver/order/{order_id}
  // ===============================================================
  static Future<Map<String, dynamic>> getOrderDetails(String orderId) async {
    final data = await _secureGet("/driver/order/$orderId");
    return Map<String, dynamic>.from(data);
  }

  // ===============================================================
  // Alias used by dashboard “status check”
  // ===============================================================
  static Future<Map<String, dynamic>> getOrderById({
    required String orderId,
  }) async {
    final data = await _secureGet("/driver/order/$orderId");
    return Map<String, dynamic>.from(data);
  }

  // ===============================================================
  // TOP CARD (temp + eta) → /driver/order/{order_id}/dashboard
  // ===============================================================
  static Future<Map<String, dynamic>> getOrderDashboardCard(
    String orderId,
  ) async {
    final data = await _secureGet("/driver/order/$orderId/dashboard");
    return Map<String, dynamic>.from(data);
  }

  // ===============================================================
  // TODAY ORDERS → /driver/orders/today?driver_id=...
  // ===============================================================
  static Future<List<dynamic>> getTodayOrders({String? driverId}) async {
    final prefs = await SharedPreferences.getInstance();
    String savedId = prefs.getString("driver_uuid") ?? "";

    if (savedId.isEmpty) {
      try {
        final profile = await getDriverProfile();
        savedId = profile["driver_id"]?.toString() ?? "";
        await prefs.setString("driver_uuid", savedId);
      } catch (_) {
        return [];
      }
    }

    final id = (driverId ?? savedId).trim();
    if (id.isEmpty) return [];

    final data = await _secureGet("/driver/orders/today?driver_id=$id");

    if (data is List) return data;
    if (data is Map && data["orders"] is List) return data["orders"] as List;
    if (data is Map && data["today"] is List) return data["today"] as List;
    return [];
  }

  // ===============================================================
  // ORDERS HISTORY → /driver/orders/history?driver_id=...
  // ===============================================================
  static Future<List<dynamic>> getOrdersHistory({String? driverId}) async {
    final prefs = await SharedPreferences.getInstance();
    String savedId = prefs.getString("driver_uuid") ?? "";

    if (savedId.isEmpty) {
      try {
        final profile = await getDriverProfile();
        savedId = profile["driver_id"]?.toString() ?? "";
        await prefs.setString("driver_uuid", savedId);
      } catch (_) {
        return [];
      }
    }

    final id = (driverId ?? savedId).trim();
    if (id.isEmpty) return [];

    final data = await _secureGet("/driver/orders/history?driver_id=$id");

    if (data is List) return data;
    if (data is Map && data["history"] is List) return data["history"] as List;
    if (data is Map && data["orders"] is List) return data["orders"] as List;
    return [];
  }

  // ===============================================================
  // TODAY ORDERS MAP → /driver/today-orders-map?driver_id=...
  // ===============================================================
  static Future<List<Map<String, dynamic>>> getTodayOrdersMap({
    String? driverId,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    String savedId = prefs.getString("driver_uuid") ?? "";

    if (savedId.isEmpty) {
      try {
        final profile = await getDriverProfile();
        savedId = profile["driver_id"]?.toString() ?? "";
        await prefs.setString("driver_uuid", savedId);
      } catch (_) {
        return [];
      }
    }

    final id = (driverId ?? savedId).trim();
    if (id.isEmpty) return [];

    final data = await _secureGet("/driver/today-orders-map?driver_id=$id");

    if (data is Map<String, dynamic> && data["orders"] is List) {
      return (data["orders"] as List)
          .whereType<Map>()
          .map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e as Map))
          .toList();
    }

    if (data is List) {
      return data
          .whereType<Map>()
          .map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e as Map))
          .toList();
    }

    return [];
  }

  // ===============================================================
  // CREATE ORDER → /driver/orders/create
  // ===============================================================
  static Future<Map<String, dynamic>> createOrder({
    required String patientId,
    required String hospitalId,
    required String description,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final driverUuid = prefs.getString("driver_uuid") ?? "";

    final data = await _securePost("/driver/orders/create", {
      "patient_id": patientId,
      "hospital_id": hospitalId,
      "driver_id": driverUuid,
      "description": description,
    });

    return Map<String, dynamic>.from(data);
  }
}
