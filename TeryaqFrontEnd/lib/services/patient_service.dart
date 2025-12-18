// lib/services/patient_service.dart
//
// PatientService
// - Firebase login (patient email convention) + token persistence
// - Patient API calls (home, orders, track, dashboard-map, prescriptions, reports)
// - Notifications
// - Cancel Order (robust: tries multiple endpoint shapes)
// - Order Events (robust: tries multiple endpoint shapes, and can parse events from order/report payloads)
// - OTP helpers:
//     A) fetchOtpIfApproaching(orderId)  -> ONLY if driver is near OR “approaching” notification exists
//     B) fetchOtpForOrder(orderId)       -> ALWAYS fetch OTP from report (unconditional)  ✅ ADDED
//
// Notes:
// - This file is designed to be resilient if backend route paths differ slightly.
// - If you have a single fixed path, you can remove the extra candidates safely.
//

import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// ===================================================================
/// Map / Tile Config
/// ===================================================================
class MapConfig {
  // Use Gateway (example: 8088) not TileServer direct (8081)
  static const String gatewayBaseUrl = "http://192.168.8.113:8088";

  // Always go through /tiles
  static const String tilesTemplate =
      "$gatewayBaseUrl/tiles/styles/basic-preview/{z}/{x}/{y}.png";
}

/// ===================================================================
/// Patient Service
/// ===================================================================
class PatientService {
  static const String apiBaseUrl = "http://192.168.8.113:8000";
  static final FirebaseAuth _auth = FirebaseAuth.instance;

  static String? _authToken;
  static String? currentPatientNationalId;
  static String? currentPatientId;

  static const String _kPatientTokenKey = "patient_token";
  static const String _kPatientNationalIdKey = "patient_national_id";
  static const String _kLegacyNationalIdKey = "national_id";
  static const String _kPatientIdKey = "patient_id";

  // ----------------------------------------------------------
  // Helpers
  // ----------------------------------------------------------

  static String _patientEmailFromNationalId(String nationalId) {
    return "$nationalId@patient.teryag.com";
  }

  static String? _extractNationalIdFromEmail(String? email) {
    if (email == null) return null;
    final parts = email.split("@");
    if (parts.isEmpty) return null;
    final id = parts.first.trim();
    if (!RegExp(r'^\d{10}$').hasMatch(id)) return null;
    return id;
  }

  static String? _readNationalId(SharedPreferences prefs) {
    return prefs.getString(_kPatientNationalIdKey) ??
        prefs.getString(_kLegacyNationalIdKey);
  }

  static Map<String, String> _headers(String token) {
    return <String, String>{
      "Authorization": "Bearer $token",
      "Content-Type": "application/json",
    };
  }

  static String _enc(String v) => Uri.encodeComponent(v);

  // ==========================================================
  // ✅ UUID detection + code→UUID resolver
  // ==========================================================
  static bool _looksLikeUuid(String s) {
    final v = s.trim();
    if (v.isEmpty) return false;
    return RegExp(
      r'^[0-9a-fA-F]{8}-'
      r'[0-9a-fA-F]{4}-'
      r'[0-9a-fA-F]{4}-'
      r'[0-9a-fA-F]{4}-'
      r'[0-9a-fA-F]{12}$',
    ).hasMatch(v);
  }

  /// If input is UUID, return it.
  /// Otherwise try to resolve by matching order code in fetchOrders().
  /// If not found, returns original input.
  static Future<String> _resolveOrderUuid(String anyOrderIdOrCode) async {
    final raw = anyOrderIdOrCode.trim();
    if (raw.isEmpty) return raw;

    if (_looksLikeUuid(raw)) return raw;

    try {
      final orders = await fetchOrders();
      for (final o in orders) {
        final code = (o["code"] ?? o["order_code"] ?? o["orderCode"] ?? "")
            .toString()
            .trim();
        if (code.isNotEmpty && code == raw) {
          final id = (o["order_id"] ?? o["orderId"] ?? o["uuid"] ?? "")
              .toString()
              .trim();
          if (id.isNotEmpty) return id;
        }
      }
    } catch (_) {
      // ignore and fallback
    }

    return raw;
  }

  // ==========================================================
  // ✅ _getToken() handles nullable getIdToken() result
  // ==========================================================
  static Future<String> _getToken({bool forceRefresh = false}) async {
    final prefs = await SharedPreferences.getInstance();

    final saved = prefs.getString(_kPatientTokenKey);
    if (saved != null && saved.isNotEmpty && !forceRefresh) {
      _authToken = saved;
      return saved;
    }

    final user = _auth.currentUser;
    if (user != null) {
      final String? fresh = await user.getIdToken(forceRefresh);

      if (fresh != null && fresh.isNotEmpty) {
        _authToken = fresh;
        await prefs.setString(_kPatientTokenKey, fresh);

        final current = _readNationalId(prefs);
        if (current == null) {
          final derived = _extractNationalIdFromEmail(user.email);
          if (derived != null) {
            currentPatientNationalId = derived;
            await prefs.setString(_kPatientNationalIdKey, derived);
            await prefs.setString(_kLegacyNationalIdKey, derived);
          }
        }

        return fresh;
      }
    }

    throw Exception("Patient not logged in.");
  }

  // ----------------------------------------------------------
  // Auth
  // ----------------------------------------------------------

  static Future<void> loginPatient({
    required String nationalId,
    required String password,
  }) async {
    try {
      final email = _patientEmailFromNationalId(nationalId);

      final cred = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      final String? token = await cred.user?.getIdToken();
      if (token == null || token.isEmpty) {
        throw Exception("Failed to retrieve Firebase token for patient.");
      }

      _authToken = token;
      currentPatientNationalId = nationalId;

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kPatientTokenKey, token);
      await prefs.setString(_kPatientNationalIdKey, nationalId);
      await prefs.setString(_kLegacyNationalIdKey, nationalId);

      await fetchPatientIdByNationalId(nationalId);
    } on FirebaseAuthException catch (e) {
      debugPrint("Firebase Patient Login Failed → $e");
      rethrow;
    }
  }

  static Future<void> fetchPatientIdByNationalId(String nationalId) async {
    final url = Uri.parse(
      "$apiBaseUrl/patient/auth/lookup",
    ).replace(queryParameters: {"national_id": nationalId});

    final prefs = await SharedPreferences.getInstance();
    final token = _authToken ?? prefs.getString(_kPatientTokenKey);

    final response = await http.get(
      url,
      headers: {
        if (token != null && token.isNotEmpty) "Authorization": "Bearer $token",
        "Content-Type": "application/json",
      },
    );

    if (response.statusCode != 200) {
      debugPrint("Failed to fetch patient_id: ${response.body}");
      throw Exception("Patient lookup failed.");
    }

    final data = jsonDecode(response.body);
    currentPatientId = data["patient_id"]?.toString();
    await prefs.setString(_kPatientIdKey, currentPatientId ?? "");
  }

  // ----------------------------------------------------------
  // Patient Profile / Home
  // ----------------------------------------------------------

  static Future<Map<String, dynamic>?> fetchCurrentPatient() async {
    final prefs = await SharedPreferences.getInstance();
    final nationalId = _readNationalId(prefs);
    if (nationalId == null) return null;

    final token = await _getToken();
    final url = Uri.parse("$apiBaseUrl/patient/$nationalId");

    final response = await http.get(url, headers: _headers(token));
    if (response.statusCode == 200) {
      return Map<String, dynamic>.from(jsonDecode(response.body));
    }
    return null;
  }

  static Future<String?> fetchPatientName() async {
    final data = await fetchCurrentPatient();
    return data?["name"]?.toString();
  }

  static Future<Map<String, dynamic>?> fetchHomeSummary() async {
    final prefs = await SharedPreferences.getInstance();
    final nationalId = _readNationalId(prefs);
    if (nationalId == null) return null;

    final token = await _getToken();
    final url = Uri.parse("$apiBaseUrl/patient/home/$nationalId");

    final response = await http.get(url, headers: _headers(token));
    if (response.statusCode == 200) {
      return Map<String, dynamic>.from(jsonDecode(response.body));
    }
    return null;
  }

  // ----------------------------------------------------------
  // Dashboard Map
  // ----------------------------------------------------------

  static Future<Map<String, dynamic>> fetchDashboardMap({
    String? orderId,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final nationalId = _readNationalId(prefs);
    if (nationalId == null) {
      throw Exception("Patient national_id not found in SharedPreferences.");
    }

    final token = await _getToken();

    final oidRaw = (orderId ?? "").trim();
    String resolved = oidRaw;
    if (oidRaw.isNotEmpty) {
      resolved = await _resolveOrderUuid(oidRaw);
    }

    final qp = <String, String>{};
    if (resolved.isNotEmpty && _looksLikeUuid(resolved)) {
      qp["order_id"] = resolved;
    }

    final url = Uri.parse(
      "$apiBaseUrl/patient/$nationalId/dashboard-map",
    ).replace(queryParameters: qp.isEmpty ? null : qp);

    final response = await http.get(url, headers: _headers(token));

    if (response.statusCode != 200) {
      debugPrint(
        "Failed to fetch dashboard map: ${response.statusCode} ${response.body}",
      );
      throw Exception("Failed to fetch dashboard map");
    }

    return Map<String, dynamic>.from(jsonDecode(response.body));
  }

  // ----------------------------------------------------------
  // Notifications
  // ----------------------------------------------------------

  static Future<List<Map<String, dynamic>>> fetchNotifications() async {
    final prefs = await SharedPreferences.getInstance();
    final nationalId = _readNationalId(prefs);
    if (nationalId == null) {
      throw Exception("Patient national_id not found in SharedPreferences.");
    }

    final token = await _getToken();
    final url = Uri.parse("$apiBaseUrl/patient/$nationalId/notifications");

    final response = await http.get(url, headers: _headers(token));
    if (response.statusCode != 200) {
      debugPrint(
        "Failed to fetch notifications: ${response.statusCode} ${response.body}",
      );
      throw Exception("Failed to fetch notifications");
    }

    final List<dynamic> data = jsonDecode(response.body);

    return data.map<Map<String, dynamic>>((e) {
      final m = Map<String, dynamic>.from(e as Map);

      final id = m["order_id"] ?? m["orderId"] ?? m["order_uuid"] ?? m["uuid"];
      if (id != null) {
        m["order_id"] = id.toString();
        m["orderId"] = id.toString();
      }

      final created =
          m["created_at"] ?? m["createdAt"] ?? m["time"] ?? m["timestamp"];
      if (created != null) {
        m["created_at"] = created.toString();
      }

      m["status"] = (m["status"] ?? m["status_key"] ?? "").toString();

      m["title"] = (m["title"] ?? m["name"] ?? "Medication").toString();
      m["description"] = (m["description"] ?? m["message"] ?? "").toString();
      m["level"] = (m["level"] ?? m["severity"] ?? "warning").toString();

      return m;
    }).toList();
  }

  // ----------------------------------------------------------
  // Orders
  // ----------------------------------------------------------

  static Future<List<Map<String, dynamic>>> fetchOrders() async {
    final prefs = await SharedPreferences.getInstance();
    final nationalId = _readNationalId(prefs);
    if (nationalId == null) {
      throw Exception("Patient national_id not found in SharedPreferences.");
    }

    final token = await _getToken();
    final url = Uri.parse("$apiBaseUrl/patient/$nationalId/orders");

    debugPrint("PatientService.fetchOrders → nationalId=$nationalId url=$url");

    final response = await http.get(url, headers: _headers(token));
    if (response.statusCode != 200) {
      debugPrint(
        "Failed to fetch orders: ${response.statusCode} ${response.body}",
      );
      throw Exception("Failed to fetch orders");
    }

    final List<dynamic> data = jsonDecode(response.body);

    return data.map<Map<String, dynamic>>((e) {
      final m = Map<String, dynamic>.from(e as Map);

      final id =
          m["order_id"] ??
          m["orderId"] ??
          m["id"] ??
          m["order_uuid"] ??
          m["uuid"];
      if (id != null) {
        m["order_id"] = id.toString();
        m["orderId"] = id.toString();
      }

      final created =
          m["created_at"] ?? m["placed_at"] ?? m["createdAt"] ?? m["placedAt"];
      if (created != null) {
        m["created_at"] = created.toString();
      }

      final delivered = m["delivered_at"] ?? m["deliveredAt"];
      if (delivered != null) {
        m["delivered_at"] = delivered.toString();
      }

      m["medication_name"] =
          m["medication_name"] ?? m["medicine"] ?? m["medication"] ?? "";

      m["priority_level"] = m["priority_level"] ?? m["priority"] ?? "";

      m["status"] = (m["status"] ?? m["status_key"] ?? "").toString();

      return m;
    }).toList();
  }

  // ----------------------------------------------------------
  // Cancel Order (Event-based)
  // ----------------------------------------------------------

  static Future<void> cancelOrder({required String orderId}) async {
    final raw = orderId.trim();
    if (raw.isEmpty) throw Exception("orderId is empty");

    final oid = await _resolveOrderUuid(raw);
    if (!_looksLikeUuid(oid)) {
      throw Exception(
        "cancelOrder requires UUID. Could not resolve from: $raw",
      );
    }

    final prefs = await SharedPreferences.getInstance();
    final nationalId = _readNationalId(prefs);
    if (nationalId == null) {
      throw Exception("Patient national_id not found in SharedPreferences.");
    }

    final token = await _getToken();

    final candidates = <Future<http.Response>>[
      http.post(
        Uri.parse("$apiBaseUrl/patient/$nationalId/orders/${_enc(oid)}/cancel"),
        headers: _headers(token),
      ),
      http.post(
        Uri.parse("$apiBaseUrl/patient/$nationalId/orders/cancel"),
        headers: _headers(token),
        body: jsonEncode({"order_id": oid}),
      ),
      http.put(
        Uri.parse("$apiBaseUrl/patient/$nationalId/orders/${_enc(oid)}/cancel"),
        headers: _headers(token),
      ),
      http.delete(
        Uri.parse("$apiBaseUrl/patient/$nationalId/orders/${_enc(oid)}"),
        headers: _headers(token),
      ),
    ];

    http.Response? last;
    for (final req in candidates) {
      final res = await req;
      last = res;

      if (res.statusCode == 200 ||
          res.statusCode == 201 ||
          res.statusCode == 204) {
        return;
      }
    }

    debugPrint(
      "Failed to cancel order. Last=${last?.statusCode} body=${last?.body}",
    );
    throw Exception("Failed to cancel order");
  }

  // ----------------------------------------------------------
  // Order Details + Events
  // ----------------------------------------------------------

  static Future<Map<String, dynamic>> fetchOrderDetails({
    required String orderId,
  }) async {
    final raw = orderId.trim();
    if (raw.isEmpty) throw Exception("orderId is empty");

    final oid = await _resolveOrderUuid(raw);
    if (!_looksLikeUuid(oid)) {
      throw Exception(
        "fetchOrderDetails requires UUID. Could not resolve from: $raw",
      );
    }

    final prefs = await SharedPreferences.getInstance();
    final nationalId = _readNationalId(prefs);
    if (nationalId == null) {
      throw Exception("Patient national_id not found in SharedPreferences.");
    }

    final token = await _getToken();

    final candidates = <Uri>[
      Uri.parse("$apiBaseUrl/patient/$nationalId/orders/${_enc(oid)}"),
      Uri.parse("$apiBaseUrl/patient/$nationalId/order/${_enc(oid)}"),
      Uri.parse("$apiBaseUrl/patient/orders/${_enc(oid)}"),
    ];

    http.Response? lastRes;
    for (final url in candidates) {
      final res = await http.get(url, headers: _headers(token));
      lastRes = res;

      if (res.statusCode != 200) continue;

      final decoded = jsonDecode(res.body);
      if (decoded is Map) {
        return Map<String, dynamic>.from(decoded);
      }
    }

    throw Exception(
      "Failed to fetch order details. Last status=${lastRes?.statusCode} body=${lastRes?.body}",
    );
  }

  static Future<List<Map<String, dynamic>>> fetchOrderEvents({
    required String orderId,
  }) async {
    final raw = orderId.trim();
    if (raw.isEmpty) throw Exception("orderId is empty");

    final oid = await _resolveOrderUuid(raw);
    if (!_looksLikeUuid(oid)) {
      return <Map<String, dynamic>>[];
    }

    final prefs = await SharedPreferences.getInstance();
    final nationalId = _readNationalId(prefs);
    if (nationalId == null) {
      throw Exception("Patient national_id not found in SharedPreferences.");
    }

    final token = await _getToken();

    final candidates = <Uri>[
      Uri.parse("$apiBaseUrl/patient/$nationalId/orders/${_enc(oid)}/events"),
      Uri.parse("$apiBaseUrl/patient/$nationalId/order/${_enc(oid)}/events"),
      Uri.parse("$apiBaseUrl/patient/orders/${_enc(oid)}/events"),
    ];

    for (final url in candidates) {
      final res = await http.get(url, headers: _headers(token));
      if (res.statusCode != 200) continue;

      final decoded = jsonDecode(res.body);
      final extracted = _extractEventsFromAny(decoded);
      if (extracted.isNotEmpty) return extracted;
    }

    try {
      final details = await fetchOrderDetails(orderId: oid);
      final extracted = _extractEventsFromAny(details);
      if (extracted.isNotEmpty) return extracted;
    } catch (_) {}

    try {
      final report = await fetchOrderReport(orderId: oid);
      final extracted = _extractEventsFromAny(report);
      if (extracted.isNotEmpty) return extracted;
    } catch (_) {}

    return <Map<String, dynamic>>[];
  }

  static List<Map<String, dynamic>> _extractEventsFromAny(dynamic decoded) {
    List<dynamic>? list;

    if (decoded is List) {
      list = decoded;
    } else if (decoded is Map) {
      list =
          (decoded["events"] as List?) ??
          (decoded["timeline"] as List?) ??
          (decoded["delivery_events"] as List?) ??
          (decoded["deliveryEvents"] as List?);

      if (list == null && decoded["order"] is Map) {
        final o = decoded["order"] as Map;
        list =
            (o["events"] as List?) ??
            (o["timeline"] as List?) ??
            (o["delivery_events"] as List?) ??
            (o["deliveryEvents"] as List?);
      }
    }

    if (list == null) return <Map<String, dynamic>>[];

    return list.map<Map<String, dynamic>>((e) {
      if (e is Map) {
        final m = Map<String, dynamic>.from(e);

        m["type"] = (m["type"] ?? m["event_type"] ?? m["status"] ?? "")
            .toString();
        m["title"] = (m["title"] ?? m["name"] ?? m["type"] ?? "Event")
            .toString();
        m["description"] =
            (m["description"] ?? m["message"] ?? m["details"] ?? "").toString();
        m["created_at"] =
            (m["created_at"] ?? m["createdAt"] ?? m["time"] ?? m["timestamp"])
                ?.toString();

        return m;
      }

      return <String, dynamic>{
        "type": "event",
        "title": "Event",
        "description": e.toString(),
      };
    }).toList();
  }

  // ----------------------------------------------------------
  // Track Order
  // ----------------------------------------------------------

  static Future<Map<String, dynamic>> fetchTrackOrder({String? orderId}) async {
    final prefs = await SharedPreferences.getInstance();
    final nationalId = _readNationalId(prefs);
    if (nationalId == null) {
      throw Exception("Patient national_id not found in SharedPreferences.");
    }

    final token = await _getToken();
    final String rawRequested = (orderId ?? "").trim();

    String requestedUuid = rawRequested;
    if (rawRequested.isNotEmpty) {
      requestedUuid = await _resolveOrderUuid(rawRequested);
    }

    final List<Uri> candidates = [];

    if (requestedUuid.isNotEmpty && _looksLikeUuid(requestedUuid)) {
      candidates.add(
        Uri.parse(
          "$apiBaseUrl/patient/$nationalId/track",
        ).replace(queryParameters: {"order_id": requestedUuid}),
      );
      candidates.add(
        Uri.parse(
          "$apiBaseUrl/patient/$nationalId/track/${_enc(requestedUuid)}",
        ),
      );
      candidates.add(
        Uri.parse("$apiBaseUrl/patient/orders/${_enc(requestedUuid)}/track"),
      );
    }

    candidates.add(Uri.parse("$apiBaseUrl/patient/$nationalId/track"));

    http.Response? lastRes;

    for (final url in candidates) {
      debugPrint("PatientService.fetchTrackOrder trying URL=$url");

      final res = await http.get(url, headers: _headers(token));
      lastRes = res;

      debugPrint(
        "PatientService.fetchTrackOrder → ${res.statusCode} ${res.body}",
      );

      if (res.statusCode != 200) continue;

      final decoded = jsonDecode(res.body);
      final order = _canonicalizeTrackPayload(decoded);

      if (requestedUuid.isNotEmpty && _looksLikeUuid(requestedUuid)) {
        final returnedId = (order["order_id"] ?? order["orderId"] ?? "")
            .toString();

        if (returnedId.isNotEmpty && returnedId != requestedUuid) {
          throw Exception(
            "Track mismatch: requested order_id=$requestedUuid but backend returned order_id=$returnedId. "
            "Backend track endpoint is not filtering by order_id.",
          );
        }

        order["order_id"] = requestedUuid;
        order["orderId"] = requestedUuid;
      }

      return order;
    }

    throw Exception(
      "Failed to fetch track order. Last status=${lastRes?.statusCode} body=${lastRes?.body}",
    );
  }

  static Map<String, dynamic> _canonicalizeTrackPayload(dynamic decoded) {
    Map<String, dynamic> order;

    if (decoded is List) {
      if (decoded.isEmpty) return <String, dynamic>{};
      final first = decoded.first;
      if (first is Map) {
        order = Map<String, dynamic>.from(first as Map);
      } else {
        return <String, dynamic>{};
      }
    } else if (decoded is Map) {
      if (decoded["order"] is Map) {
        order = Map<String, dynamic>.from(decoded["order"] as Map);
      } else if (decoded["active_order"] is Map) {
        order = Map<String, dynamic>.from(decoded["active_order"] as Map);
      } else if (decoded["track"] is Map) {
        order = Map<String, dynamic>.from(decoded["track"] as Map);
      } else {
        order = Map<String, dynamic>.from(decoded as Map);
      }
    } else {
      return <String, dynamic>{};
    }

    final rawStatus =
        order["status"] ??
        order["status_key"] ??
        order["order_status"] ??
        order["state"] ??
        order["statusKey"];
    if (rawStatus != null) {
      order["status"] = rawStatus.toString();
    }

    final rawOrderId =
        order["order_id"] ??
        order["orderId"] ??
        order["id"] ??
        order["order_uuid"] ??
        order["uuid"];
    if (rawOrderId != null) {
      order["order_id"] = rawOrderId.toString();
      order["orderId"] = rawOrderId.toString();
    }

    final driverObj = order["driver"];
    order["driverName"] =
        order["driverName"] ??
        order["driver_name"] ??
        (driverObj is Map ? driverObj["name"] : null) ??
        "-";
    order["driverPhone"] =
        order["driverPhone"] ??
        order["driver_phone"] ??
        (driverObj is Map ? driverObj["phone"] : null) ??
        "-";

    order["createdAt"] = order["createdAt"] ?? order["created_at"];
    order["deliveredAt"] = order["deliveredAt"] ?? order["delivered_at"];

    return order;
  }

  // ----------------------------------------------------------
  // Prescriptions / Order Review / Create Order
  // ----------------------------------------------------------

  static Future<List<Map<String, dynamic>>> fetchPrescriptions() async {
    final prefs = await SharedPreferences.getInstance();
    final nationalId = _readNationalId(prefs);
    if (nationalId == null) {
      throw Exception("Patient national_id not found in SharedPreferences.");
    }

    final token = await _getToken();
    final url = Uri.parse("$apiBaseUrl/patient/$nationalId/prescriptions");

    final response = await http.get(url, headers: _headers(token));

    if (response.statusCode == 404) {
      return <Map<String, dynamic>>[];
    }

    if (response.statusCode != 200) {
      debugPrint(
        "Failed to fetch prescriptions: ${response.statusCode} ${response.body}",
      );
      throw Exception("Failed to fetch prescriptions");
    }

    final List<dynamic> data = jsonDecode(response.body);
    return data
        .map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }

  static Future<Map<String, dynamic>> fetchOrderReview({
    required String prescriptionId,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final nationalId = _readNationalId(prefs);
    if (nationalId == null) {
      throw Exception("Patient national_id not found in SharedPreferences.");
    }

    final token = await _getToken();
    final url = Uri.parse(
      "$apiBaseUrl/patient/$nationalId/order-review/${_enc(prescriptionId)}",
    );

    final response = await http.get(url, headers: _headers(token));
    if (response.statusCode != 200) {
      debugPrint(
        "Failed to fetch order review: ${response.statusCode} ${response.body}",
      );
      throw Exception("Failed to fetch order review");
    }

    return Map<String, dynamic>.from(jsonDecode(response.body));
  }

  static Future<void> createOrderFromPrescription({
    required String prescriptionId,
    required String orderType,
    String? timeOfDay, // "morning" | "evening"
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final nationalId = _readNationalId(prefs);
    if (nationalId == null) {
      throw Exception("Patient national_id not found in SharedPreferences.");
    }

    final token = await _getToken();
    final url = Uri.parse("$apiBaseUrl/patient/$nationalId/orders");

    // Base payload
    final base = <String, dynamic>{
      "prescription_id": prescriptionId,
      "order_type": orderType,
      "priority_level": "Normal",
    };

    // If no time selected, keep old behavior.
    if (timeOfDay == null || timeOfDay.trim().isEmpty) {
      final response = await http.post(
        url,
        headers: _headers(token),
        body: jsonEncode(base),
      );

      if (response.statusCode != 201 && response.statusCode != 200) {
        debugPrint(
          "Failed to create order: ${response.statusCode} ${response.body}",
        );
        throw Exception("Failed to create order");
      }
      return;
    }

    final t = timeOfDay.trim().toLowerCase(); // morning/evening

    // ✅ Robust: try multiple key names (depending on your DB / backend request schema)
    final payloadCandidates = <Map<String, dynamic>>[
      {...base, "time_of_day": t},
      {...base, "delivery_time": t},
      {...base, "time_slot": t},
      {...base, "slot": t},
      {...base, "period": t},
      {...base, "shift": t},
    ];

    http.Response? last;
    for (final payload in payloadCandidates) {
      final res = await http.post(
        url,
        headers: _headers(token),
        body: jsonEncode(payload),
      );
      last = res;

      if (res.statusCode == 201 || res.statusCode == 200) return;
    }

    debugPrint(
      "Failed to create order with time-of-day. "
      "Last=${last?.statusCode} body=${last?.body}",
    );
    throw Exception("Failed to create order");
  }

  // ----------------------------------------------------------
  // Address Update
  // ----------------------------------------------------------

  static Future<void> updatePatientAddress({
    required String address,
    String? label,
    double? lat,
    double? lon,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final nationalId = _readNationalId(prefs);
    if (nationalId == null) {
      throw Exception("Patient national_id not found in SharedPreferences.");
    }

    final token = await _getToken();
    final url = Uri.parse("$apiBaseUrl/patient/$nationalId/address");

    final body = jsonEncode({
      "address": address,
      if (label != null) "label": label,
      if (lat != null) "lat": lat,
      if (lon != null) "lon": lon,
    });

    final response = await http.put(url, headers: _headers(token), body: body);

    if (response.statusCode != 200 && response.statusCode != 204) {
      debugPrint(
        "Failed to update address: ${response.statusCode} ${response.body}",
      );
      throw Exception("Failed to update address");
    }
  }

  // ----------------------------------------------------------
  // Reports
  // ----------------------------------------------------------

  static Future<Map<String, dynamic>> fetchDeliveryReport({
    required String orderId,
  }) async {
    final raw = orderId.trim();
    if (raw.isEmpty) throw Exception("orderId is empty");

    final oid = await _resolveOrderUuid(raw);
    if (!_looksLikeUuid(oid)) {
      throw Exception(
        "fetchDeliveryReport requires UUID. Could not resolve from: $raw",
      );
    }

    final prefs = await SharedPreferences.getInstance();
    final nationalId = _readNationalId(prefs);
    if (nationalId == null) {
      throw Exception("Patient national_id not found in SharedPreferences.");
    }

    final token = await _getToken();
    final url = Uri.parse(
      "$apiBaseUrl/patient/$nationalId/reports/${_enc(oid)}",
    );

    final response = await http.get(url, headers: _headers(token));
    if (response.statusCode != 200) {
      debugPrint(
        "Failed to fetch delivery report: ${response.statusCode} ${response.body}",
      );
      throw Exception("Failed to fetch delivery report");
    }

    return Map<String, dynamic>.from(jsonDecode(response.body));
  }

  static Future<Map<String, dynamic>> fetchOrderReport({
    required String orderId,
  }) async {
    return fetchDeliveryReport(orderId: orderId);
  }

  // ----------------------------------------------------------
  // OTP Helpers
  // ----------------------------------------------------------

  /// ✅ ADDED: Always fetch OTP for an order (unconditional).
  /// Use this if you want OTP to show without proximity logic.
  static Future<String?> fetchOtpForOrder({required String orderId}) async {
    final raw = orderId.trim();
    if (raw.isEmpty) return null;

    final oid = await _resolveOrderUuid(raw);
    if (!_looksLikeUuid(oid)) return null;

    final report = await fetchOrderReport(orderId: oid);
    return _extractOtpFromReport(report);
  }

  /// Proximity-based OTP: returns OTP only if driver is near OR notification says approaching.
  static Future<Map<String, dynamic>> checkDriverApproach({
    required String orderId,
    double thresholdMeters = 500.0,
  }) async {
    final oid = await _resolveOrderUuid(orderId);
    final dash = await fetchDashboardMap(orderId: oid);

    final patient = _extractLatLon(
      dash,
      primaryKeys: const [
        ["patient_lat", "patient_lon"],
        ["patientLat", "patientLon"],
      ],
      nestedKeys: const [
        ["patient", "lat", "lon"],
        ["patient", "latitude", "longitude"],
        ["patient", "location", "lat", "lon"],
        ["patient", "location", "latitude", "longitude"],
      ],
    );

    final driver = _extractLatLon(
      dash,
      primaryKeys: const [
        ["driver_lat", "driver_lon"],
        ["driverLat", "driverLon"],
      ],
      nestedKeys: const [
        ["driver", "lat", "lon"],
        ["driver", "latitude", "longitude"],
        ["driver", "location", "lat", "lon"],
        ["driver", "location", "latitude", "longitude"],
      ],
    );

    double? distanceMeters;
    if (patient != null && driver != null) {
      distanceMeters = _haversineMeters(
        patient["lat"]!,
        patient["lon"]!,
        driver["lat"]!,
        driver["lon"]!,
      );
    }

    final approachingByDistance =
        (distanceMeters != null && distanceMeters <= thresholdMeters);

    final approachingByNotification = _hasApproachingNotification(dash);

    return <String, dynamic>{
      "dashboard": dash,
      "distance_meters": distanceMeters,
      "threshold_meters": thresholdMeters,
      "approaching": approachingByDistance || approachingByNotification,
      "approaching_by_distance": approachingByDistance,
      "approaching_by_notification": approachingByNotification,
    };
  }

  static Future<String?> fetchOtpIfApproaching({
    required String orderId,
    double thresholdMeters = 500.0,
  }) async {
    final oid = await _resolveOrderUuid(orderId);

    final check = await checkDriverApproach(
      orderId: oid,
      thresholdMeters: thresholdMeters,
    );

    final approaching = (check["approaching"] == true);
    if (!approaching) return null;

    final report = await fetchOrderReport(orderId: oid);
    return _extractOtpFromReport(report);
  }

  static String? _extractOtpFromReport(Map<String, dynamic> report) {
    // try many key shapes
    final direct =
        report["otp"] ??
        report["otp_code"] ??
        report["otpCode"] ??
        report["otp_display"] ??
        report["otpDisplay"] ??
        report["otp_formatted"] ??
        report["otpFormatted"] ??
        report["code"];
    if (direct != null) {
      final s = direct.toString().trim();
      if (s.isNotEmpty) return s;
    }

    final order = report["order"];
    if (order is Map) {
      final o =
          order["otp"] ??
          order["otp_code"] ??
          order["otpCode"] ??
          order["otp_display"] ??
          order["otpDisplay"] ??
          order["otp_formatted"] ??
          order["otpFormatted"];
      if (o != null) {
        final s = o.toString().trim();
        if (s.isNotEmpty) return s;
      }
    }

    final details = report["deliveryDetails"] ?? report["delivery_details"];
    if (details is List) {
      for (final row in details) {
        if (row is Map) {
          final v =
              row["otp"] ??
              row["otp_code"] ??
              row["otpCode"] ??
              row["otp_display"] ??
              row["otpDisplay"] ??
              row["otp_formatted"] ??
              row["otpFormatted"];
          if (v != null) {
            final s = v.toString().trim();
            if (s.isNotEmpty) return s;
          }
        }
      }
    }

    return null;
  }

  static bool _hasApproachingNotification(Map<String, dynamic> dash) {
    final noti = dash["notifications"];
    if (noti is List) {
      for (final n in noti) {
        if (n is Map) {
          final msg = (n["message"] ?? n["title"] ?? "")
              .toString()
              .toLowerCase();
          if (msg.contains("approach") ||
              msg.contains("arriv") ||
              msg.contains("near") ||
              msg.contains("close") ||
              msg.contains("اقترب") ||
              msg.contains("قريب") ||
              msg.contains("وصل") ||
              msg.contains("بالقرب")) {
            return true;
          }
        } else {
          final msg = n.toString().toLowerCase();
          if (msg.contains("approach") ||
              msg.contains("arriv") ||
              msg.contains("near") ||
              msg.contains("close") ||
              msg.contains("اقترب") ||
              msg.contains("قريب") ||
              msg.contains("وصل") ||
              msg.contains("بالقرب")) {
            return true;
          }
        }
      }
    }
    return false;
  }

  static Map<String, double>? _extractLatLon(
    Map<String, dynamic> root, {
    required List<List<String>> primaryKeys,
    required List<List<String>> nestedKeys,
  }) {
    for (final pair in primaryKeys) {
      if (pair.length != 2) continue;
      final a = root[pair[0]];
      final b = root[pair[1]];
      final lat = _toDouble(a);
      final lon = _toDouble(b);
      if (lat != null && lon != null) return {"lat": lat, "lon": lon};
    }

    for (final path in nestedKeys) {
      final extracted = _readNestedLatLon(root, path);
      if (extracted != null) return extracted;
    }

    return null;
  }

  static Map<String, double>? _readNestedLatLon(
    Map<String, dynamic> root,
    List<String> path,
  ) {
    if (path.length == 3) {
      final obj = root[path[0]];
      if (obj is Map) {
        final lat = _toDouble(obj[path[1]]);
        final lon = _toDouble(obj[path[2]]);
        if (lat != null && lon != null) return {"lat": lat, "lon": lon};
      }
    } else if (path.length == 4) {
      final obj = root[path[0]];
      if (obj is Map) {
        final obj2 = obj[path[1]];
        if (obj2 is Map) {
          final lat = _toDouble(obj2[path[2]]);
          final lon = _toDouble(obj2[path[3]]);
          if (lat != null && lon != null) return {"lat": lat, "lon": lon};
        }
      }
    }
    return null;
  }

  static double? _toDouble(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    final s = v.toString().trim();
    return double.tryParse(s);
  }

  static double _haversineMeters(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    const r = 6371000.0;
    final dLat = _degToRad(lat2 - lat1);
    final dLon = _degToRad(lon2 - lon1);

    final a =
        math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_degToRad(lat1)) *
            math.cos(_degToRad(lat2)) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);

    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return r * c;
  }

  static double _degToRad(double deg) => deg * (math.pi / 180.0);

  // ----------------------------------------------------------
  // Stored National ID
  // ----------------------------------------------------------

  static Future<String?> getStoredNationalId() async {
    if (currentPatientNationalId != null) return currentPatientNationalId;

    final prefs = await SharedPreferences.getInstance();
    final stored = _readNationalId(prefs);
    if (stored != null) {
      currentPatientNationalId = stored;
      return stored;
    }

    final derived = _extractNationalIdFromEmail(_auth.currentUser?.email);
    if (derived != null) {
      currentPatientNationalId = derived;
      await prefs.setString(_kPatientNationalIdKey, derived);
      await prefs.setString(_kLegacyNationalIdKey, derived);
      return derived;
    }

    return null;
  }
}
