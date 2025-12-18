// lib/services/hospital_service.dart

import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart';

/// ======================================================
/// 🌐 Global Hospital Backend Configuration
///    Central place for API base URL and TileServer URL
/// ======================================================
class HospitalConfig {
  /// Base backend URL for all hospital API calls.
  static const String apiBaseUrl = "http://192.168.8.113:8000";

  /// Tile server base URL (OpenStreetMap tiles through your gateway).
  static const String tilesBaseUrl = "http://192.168.8.113:8088";

  /// Template used by FlutterMap TileLayer.
  ///   {tilesBaseUrl}/styles/basic-preview/{z}/{x}/{y}.png
  static const String tilesTemplate =
      "$tilesBaseUrl/tiles/styles/basic-preview/{z}/{x}/{y}.png";
}

class HospitalService {
  /// Default backend URL for the hospital API.
  /// We forward it to HospitalConfig.apiBaseUrl so it’s controlled from one place.
  static const String _defaultBaseUrl = HospitalConfig.apiBaseUrl;

  /// Public default base URL to be reused by UI screens.
  /// Example usage in UI:
  ///   final api = HospitalService();
  ///   or HospitalService(baseUrl: HospitalService.baseUrl);
  static const String baseUrl = _defaultBaseUrl;

  /// Base URL used by this instance.
  /// If not provided in the constructor, [baseUrl] is used.
  final String _baseUrl;
  final http.Client _client;

  // ---------- 🔐 AUTH STATICS ----------
  static final FirebaseAuth _auth = FirebaseAuth.instance;

  /// Last Firebase ID token after hospital login
  static String? _authToken;

  /// National ID of the current hospital (from login)
  static String? currentHospitalNationalId;

  /// hospital_id of the current hospital (from backend lookup)
  static String? currentHospitalId;

  /// Hospital name of the current hospital (from backend lookup)
  static String? currentHospitalName;

  HospitalService({String? baseUrl, http.Client? client})
    : _baseUrl = baseUrl ?? HospitalService.baseUrl,
      _client = client ?? http.Client();

  // =========================================================
  // ✅ ORDER STATUS NORMALIZATION (7 STATUSES)
  // =========================================================
  // You said your 7 statuses are:
  // Pending, Rejected, Accepted, On Delivery, Delivered, On_route, Delivery failed
  //
  // Canonical API/DB style we will use:
  // pending, rejected, accepted, on_delivery, delivered, on_route, delivery_failed
  //
  // This keeps UI labels flexible, but always sends backend what it expects.

  static String normalizeOrderStatusForApi(String status) {
    final s = status.trim();
    if (s.isEmpty) return "All";
    if (s.toLowerCase() == "all") return "All";

    final lower = s.toLowerCase().trim();

    // UI label variants -> canonical
    if (lower == "pending") return "pending";
    if (lower == "rejected") return "rejected";
    if (lower == "accepted") return "accepted";

    if (lower == "on delivery" ||
        lower == "on_delivery" ||
        lower == "ondelivery") {
      return "on_delivery";
    }

    if (lower == "on route" ||
        lower == "on_route" ||
        lower == "onroute" ||
        lower == "on_route ") {
      return "on_route";
    }

    if (lower == "delivered") return "delivered";

    if (lower == "delivery failed" ||
        lower == "delivery_failed" ||
        lower == "deliveryfailed") {
      return "delivery_failed";
    }

    // legacy backend values you had before
    if (lower == "progress") return "accepted";

    // fallback: convert spaces/hyphens to underscore
    return lower.replaceAll("-", "_").replaceAll(" ", "_");
  }

  static String normalizeOrderStatusForUi(String apiStatus) {
    final s = apiStatus.trim();
    if (s.isEmpty) return "";
    final lower = s.toLowerCase();

    // legacy
    if (lower == "progress") return "Accepted";

    // canonical
    if (lower == "pending") return "Pending";
    if (lower == "rejected") return "Rejected";
    if (lower == "accepted") return "Accepted";
    if (lower == "on_delivery") return "On Delivery";
    if (lower == "on_route") return "On Route";
    if (lower == "delivered") return "Delivered";
    if (lower == "delivery_failed") return "Delivery Failed";

    // fallback: Title-ish
    if (lower.contains("_")) {
      final parts = lower.split("_").where((p) => p.isNotEmpty).toList();
      return parts.map((p) => p[0].toUpperCase() + p.substring(1)).join(" ");
    }
    return lower[0].toUpperCase() + lower.substring(1);
  }

  // =========================================================
  // 🔐 AUTH: HOSPITAL LOGIN (Firebase)
  // =========================================================

  static Future<void> loginHospital({
    required String nationalId,
    required String password,
  }) async {
    final email = '$nationalId@hospital.teryag.com';

    final cred = await _auth.signInWithEmailAndPassword(
      email: email,
      password: password,
    );
    final token = await cred.user!.getIdToken();
    _authToken = token;
    currentHospitalNationalId = nationalId;
  }

  // =========================================================
  // 🔐 AUTH: LOOKUP hospital_id FROM national_id
  // =========================================================

  Future<String> fetchHospitalIdByNationalId(String nationalId) async {
    final uri = Uri.parse(
      '$_baseUrl/hospital/auth/lookup',
    ).replace(queryParameters: {'national_id': nationalId});

    final res = await _client.get(uri, headers: _headers());
    _throwIfNotOk(res);

    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final hospitalId = data['hospital_id'] as String;

    HospitalService.currentHospitalId = hospitalId;
    HospitalService.currentHospitalName =
        (data['name'] as String?) ?? 'Hospital';

    return hospitalId;
  }

  //reporttttttttttttttttttttttttttt

  /// ✅ FIX (NO DELETION): uses auth header + instance base url
  Future<void> generateOrderReportPdf({required String orderId}) async {
    final uri = Uri.parse(
      '$_baseUrl/hospital/orders/$orderId/report/generate-pdf',
    );

    final res = await _client.post(uri, headers: _headers());
    if (res.statusCode != 200) {
      throw Exception("Generate PDF failed: ${res.body}");
    }
  }

  // =========================================================
  // 🔧 Helper Headers
  // =========================================================

  Map<String, String> _headers({bool json = false}) {
    final headers = <String, String>{};
    if (json) {
      headers['Content-Type'] = 'application/json';
    }
    if (_authToken != null) {
      headers['Authorization'] = 'Bearer $_authToken';
    }
    return headers;
  }

  void _throwIfNotOk(http.Response res) {
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception(
        'Request failed (${res.statusCode}): ${res.body.toString()}',
      );
    }
  }

  // =========================================================
  // 🏠 1) HOSPITAL HOME DASHBOARD
  // =========================================================

  Future<HospitalDashboardSummary> getDashboard(String hospitalId) async {
    final uri = Uri.parse(
      '$_baseUrl/hospital/dashboard',
    ).replace(queryParameters: {'hospital_id': hospitalId});

    final res = await _client.get(uri, headers: _headers());
    _throwIfNotOk(res);

    return HospitalDashboardSummary.fromJson(jsonDecode(res.body));
  }

  // =========================================================
  // 👤 2) PATIENTS
  // =========================================================

  Future<List<PatientModel>> getPatients({
    required String hospitalId,
    String status = 'All',
    String? search,
  }) async {
    final qp = <String, String>{
      'hospital_id': hospitalId,
      'status': status,
      if (search != null && search.isNotEmpty) 'search': search,
    };

    final uri = Uri.parse(
      '$_baseUrl/hospital/patients',
    ).replace(queryParameters: qp);

    final res = await _client.get(uri, headers: _headers());
    _throwIfNotOk(res);

    final data = jsonDecode(res.body) as List<dynamic>;
    return data.map((e) => PatientModel.fromJson(e)).toList();
  }

  Future<PatientModel> addPatient({
    required String hospitalId,
    required PatientCreateDto body,
  }) async {
    final uri = Uri.parse(
      '$_baseUrl/hospital/patients',
    ).replace(queryParameters: {'hospital_id': hospitalId});

    final res = await _client.post(
      uri,
      headers: _headers(json: true),
      body: jsonEncode(body.toJson()),
    );
    _throwIfNotOk(res);

    return PatientModel.fromJson(jsonDecode(res.body));
  }

  Future<Map<String, dynamic>?> getPatientByNationalId({
    required String nationalId,
  }) async {
    final uri = Uri.parse(
      '$_baseUrl/hospital/patients/by-national/$nationalId',
    );

    final res = await _client.get(uri, headers: _headers());

    if (res.statusCode == 404) {
      return null;
    }

    _throwIfNotOk(res);
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  Future<PatientModel?> getPatientByNationalIdModel(String nationalId) async {
    final json = await getPatientByNationalId(nationalId: nationalId);
    if (json == null) return null;
    return PatientModel.fromJson(json);
  }

  Future<List<PatientModel>> searchPatientsByIdPrefix({
    required String idPrefix,
    int limit = 10,
  }) async {
    final uri = Uri.parse(
      '$_baseUrl/hospital/patients/search',
    ).replace(queryParameters: {'id_prefix': idPrefix, 'limit': '$limit'});

    final res = await _client.get(uri, headers: _headers());
    _throwIfNotOk(res);

    final data = jsonDecode(res.body) as List<dynamic>;
    return data.map((e) => PatientModel.fromJson(e)).toList();
  }

  /// Patient profile + list of prescriptions (used by PatientProfileScreen)
  Future<PatientProfileModel> getPatientProfile(String patientId) async {
    final uri = Uri.parse('$_baseUrl/hospital/patients/$patientId/profile');

    final res = await _client.get(uri, headers: _headers());
    _throwIfNotOk(res);

    return PatientProfileModel.fromJson(jsonDecode(res.body));
  }

  Future<PatientModel> updatePatientStatus({
    required String patientId,
    required String status,
  }) async {
    final uri = Uri.parse('$_baseUrl/hospital/patients/$patientId/status');

    final res = await _client.patch(
      uri,
      headers: _headers(json: true),
      body: jsonEncode({'status': status}),
    );
    _throwIfNotOk(res);

    return PatientModel.fromJson(jsonDecode(res.body));
  }

  /// If patient already exists (by national ID) returns existing,
  /// otherwise creates a new patient under this hospital.
  Future<PatientModel> createOrAttachPatient({
    required String hospitalId,
    required PatientCreateDto payload,
  }) async {
    final existing = await getPatientByNationalIdModel(payload.nationalId);
    if (existing != null) {
      return existing;
    }
    return addPatient(hospitalId: hospitalId, body: payload);
  }

  // =========================================================
  // 💊 3) MEDICATIONS
  // =========================================================

  // ✅✅✅ FIX (NO DELETION): keep add_prescription.dart happy (expects Map)
  // add_prescription.dart uses: List<Map<String,dynamic>>
  // لذا هذه الدالة ترجع RAW MAPs.
  Future<List<Map<String, dynamic>>> getHospitalMedications({
    required String hospitalId,
    String? query,
  }) async {
    final models = await getHospitalMedicationsModel(
      hospitalId: hospitalId,
      query: query,
    );
    return models.map((m) => m.toJson()).toList();
  }

  // ✅ ADDED (NO DELETION): if any other screen needs the model type directly
  Future<List<MedicationModel>> getHospitalMedicationsModel({
    required String hospitalId,
    String? query,
  }) async {
    // Try with hospital_id first (some backends need it), then fallback without it.
    final qpWith = <String, String>{
      'hospital_id': hospitalId,
      if (query != null && query.isNotEmpty) 'q': query,
    };

    final qpWithout = <String, String>{
      if (query != null && query.isNotEmpty) 'q': query,
    };

    final uriWith = Uri.parse(
      '$_baseUrl/hospital/medications',
    ).replace(queryParameters: qpWith);

    final uriWithout = Uri.parse(
      '$_baseUrl/hospital/medications',
    ).replace(queryParameters: qpWithout.isEmpty ? null : qpWithout);

    http.Response res = await _client.get(uriWith, headers: _headers());

    if (res.statusCode != 200) {
      // fallback attempt
      final res2 = await _client.get(uriWithout, headers: _headers());
      if (res2.statusCode == 200) {
        final data = jsonDecode(res2.body) as List<dynamic>;
        return data
            .map((e) => MedicationModel.fromJson(e as Map<String, dynamic>))
            .toList();
      }
      // if fallback also fails, throw based on original or fallback
      _throwIfNotOk(res2);
    }

    final data = jsonDecode(res.body) as List<dynamic>;
    return data
        .map((e) => MedicationModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<MedicationModel>> getMedications({String? query}) async {
    final uri = Uri.parse('$_baseUrl/hospital/medications').replace(
      queryParameters: {if (query != null && query.isNotEmpty) 'q': query},
    );

    final res = await _client.get(uri, headers: _headers());
    _throwIfNotOk(res);

    final data = jsonDecode(res.body) as List<dynamic>;
    return data.map((e) => MedicationModel.fromJson(e)).toList();
  }

  // =========================================================
  // ✅ ADD-PRESCRIPTION HELPERS (NO DELETION)
  // =========================================================
  // هذه دوال إضافية لتسهيل شاشة AddPrescription:
  // 1) تجيب الأدوية للمودال/الدروبداون (id + name)
  // 2) تجيب المرضى للدروبداون/الأوتوكومبليت لو تحتاج

  /// Returns minimal dropdown-ready items: [{ "id": "...", "name": "..." }, ...]
  Future<List<Map<String, String>>> getMedicationDropdownItems({
    required String hospitalId,
    String? query,
  }) async {
    final meds = await getHospitalMedicationsModel(
      hospitalId: hospitalId,
      query: query,
    );
    return meds.map((m) => {"id": m.medicationId, "name": m.name}).toList();
  }

  /// Returns minimal patient items: [{ "patient_id": "...", "national_id": "...", "name": "..." }, ...]
  Future<List<Map<String, String>>> getPatientDropdownItems({
    required String hospitalId,
    String status = "All",
    String? search,
  }) async {
    final patients = await getPatients(
      hospitalId: hospitalId,
      status: status,
      search: search,
    );
    return patients
        .map(
          (p) => {
            "patient_id": p.patientId,
            "national_id": p.nationalId,
            "name": (p.name ?? ""),
          },
        )
        .toList();
  }

  // =========================================================
  // 📜 4) PRESCRIPTIONS
  // =========================================================

  /// Create prescription using raw payload map (matches backend schemas.PrescriptionCreate).
  /// POST /hospital/prescriptions?hospital_id=currentHospitalId
  Future<Map<String, dynamic>> createPrescription({
    required Map<String, dynamic> payload,
  }) async {
    final hospitalId = HospitalService.currentHospitalId;
    if (hospitalId == null) {
      throw Exception(
        'currentHospitalId is null. Call fetchHospitalIdByNationalId() after login.',
      );
    }

    final uri = Uri.parse(
      '$_baseUrl/hospital/prescriptions',
    ).replace(queryParameters: {'hospital_id': hospitalId});

    final res = await _client.post(
      uri,
      headers: _headers(json: true),
      body: jsonEncode(payload),
    );
    _throwIfNotOk(res);

    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  Future<PrescriptionDetailModel> createPrescriptionModel({
    required String hospitalId,
    required PrescriptionCreateDto body,
  }) async {
    final uri = Uri.parse(
      '$_baseUrl/hospital/prescriptions',
    ).replace(queryParameters: {'hospital_id': hospitalId});

    final res = await _client.post(
      uri,
      headers: _headers(json: true),
      body: jsonEncode(body.toJson()),
    );
    _throwIfNotOk(res);

    return PrescriptionDetailModel.fromJson(jsonDecode(res.body));
  }

  Future<List<PrescriptionCardModel>> getPrescriptions({
    required String hospitalId,
    String status = 'All',
    String? search,
  }) async {
    final qp = <String, String>{
      'hospital_id': hospitalId,
      'status': status,
      if (search != null && search.isNotEmpty) 'search': search,
    };

    final uri = Uri.parse(
      '$_baseUrl/hospital/prescriptions',
    ).replace(queryParameters: qp);

    final res = await _client.get(uri, headers: _headers());
    _throwIfNotOk(res);

    final data = jsonDecode(res.body) as List<dynamic>;
    return data.map((e) => PrescriptionCardModel.fromJson(e)).toList();
  }

  /// Prescription Detail
  /// GET /hospital/prescriptions/{prescription_id}
  Future<PrescriptionDetailModel> getPrescriptionDetail(
    String prescriptionId,
  ) async {
    final uri = Uri.parse('$_baseUrl/hospital/prescriptions/$prescriptionId');

    final res = await _client.get(uri, headers: _headers());
    _throwIfNotOk(res);

    final json = jsonDecode(res.body) as Map<String, dynamic>;
    return PrescriptionDetailModel.fromJson(json);
  }

  /// Raw map
  Future<Map<String, dynamic>> getPrescriptionDetails({
    required String code,
  }) async {
    final uri = Uri.parse('$_baseUrl/hospital/prescriptions/$code');

    final res = await _client.get(uri, headers: _headers());
    _throwIfNotOk(res);

    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  /// PATCH /hospital/prescriptions/{code}/invalidate
  Future<void> invalidatePrescription({required String code}) async {
    final uri = Uri.parse('$_baseUrl/hospital/prescriptions/$code/invalidate');

    final res = await _client.patch(uri, headers: _headers());
    _throwIfNotOk(res);
  }

  /// DELETE /hospital/prescriptions/{prescription_id}
  Future<void> deletePrescription({required String prescriptionId}) async {
    final uri = Uri.parse('$_baseUrl/hospital/prescriptions/$prescriptionId');

    final res = await _client.delete(uri, headers: _headers());
    _throwIfNotOk(res);
  }

  // =========================================================
  // 📦 5) ORDERS
  // =========================================================

  /// POST /hospital/orders?hospital_id=...
  Future<OrderDetailModel> createOrder({
    required String patientNationalId,
    required String prescriptionId,
    String priorityLevel = 'Normal',
    String orderType = 'delivery',
    String? notes,
    int? otp,
  }) async {
    final hospitalId = HospitalService.currentHospitalId;
    if (hospitalId == null) {
      throw Exception(
        'currentHospitalId is null. Call fetchHospitalIdByNationalId() after login.',
      );
    }

    final uri = Uri.parse(
      '$_baseUrl/hospital/orders',
    ).replace(queryParameters: {'hospital_id': hospitalId});

    final payload = <String, dynamic>{
      'patient_national_id': patientNationalId,
      'prescription_id': prescriptionId,
      'priority_level': priorityLevel,
      'order_type': orderType,
      if (notes != null && notes.isNotEmpty) 'notes': notes,
      if (otp != null) 'otp': otp,
    };

    final res = await _client.post(
      uri,
      headers: _headers(json: true),
      body: jsonEncode(payload),
    );
    _throwIfNotOk(res);

    final json = jsonDecode(res.body) as Map<String, dynamic>;
    return OrderDetailModel.fromJson(json);
  }

  Future<List<OrderSummaryModel>> getOrders({
    required String hospitalId,
    String status = 'All',
    String? search,
  }) async {
    final apiStatus = HospitalService.normalizeOrderStatusForApi(status);

    final qp = <String, String>{
      'hospital_id': hospitalId,
      'status': apiStatus,
      if (search != null && search.isNotEmpty) 'search': search,
    };

    final uri = Uri.parse(
      '$_baseUrl/hospital/orders',
    ).replace(queryParameters: qp);

    final res = await _client.get(uri, headers: _headers());
    _throwIfNotOk(res);

    final data = jsonDecode(res.body) as List<dynamic>;
    return data.map((e) => OrderSummaryModel.fromJson(e)).toList();
  }

  Future<OrderDetailModel> getOrderDetail(String orderId) async {
    final uri = Uri.parse('$_baseUrl/hospital/orders/$orderId');

    final res = await _client.get(uri, headers: _headers());
    _throwIfNotOk(res);

    return OrderDetailModel.fromJson(jsonDecode(res.body));
  }

  /// Order review:
  /// - Tries /hospital/orders/{orderId}/review
  /// - Falls back to getOrderDetail + patient lookup
  Future<Map<String, dynamic>> getOrderReview({required String orderId}) async {
    // --------- Try dedicated review endpoint ----------
    final reviewUri = Uri.parse('$_baseUrl/hospital/orders/$orderId/review');

    try {
      final res = await _client.get(reviewUri, headers: _headers());
      if (res.statusCode >= 200 && res.statusCode < 300) {
        return jsonDecode(res.body) as Map<String, dynamic>;
      }
      if (res.statusCode != 404 && res.statusCode != 405) {
        _throwIfNotOk(res);
      }
    } catch (_) {
      // Ignore and fall back
    }

    // --------- Fallback: /hospital/orders/{id} + patient lookup ----------
    final detail = await getOrderDetail(orderId);

    Map<String, dynamic>? patientJson;
    try {
      patientJson = await getPatientByNationalId(
        nationalId: detail.patientNationalId,
      );
    } catch (_) {
      patientJson = null;
    }

    final Map<String, dynamic> orderMap = {
      'order_id': detail.orderId,
      'code': detail.code,
      'status': detail.status,
      'order_status': detail.status,
      'priority_level': detail.priorityLevel,
      'delivery_type': detail.deliveryType,
      'delivery_time': detail.deliveryTime,
      'system_recommendation': detail.systemRecommendation,
      'location_city': detail.locationCity,
      'location_description': detail.locationDescription,
      'location_lat': detail.locationLat,
      'location_lon': detail.locationLon,
      'patient_name': detail.patientName,
      'patient_national_id': detail.patientNationalId,
      'hospital_name': detail.hospitalName,
      'medicine_name': detail.medicineName,

      // 🔹 Prescription info for OrderReviewScreen
      'medication_name': detail.medicineName,
      'prescribing_doctor': detail.prescribingDoctor,
      'instructions': detail.instructions,
      'expiration_date': detail.expirationDate?.toIso8601String(),
      'refill_limit': detail.refillLimit,
      'reorder_threshold': detail.reorderThreshold,
      'prescription_id': detail.prescriptionId,
    };

    if (patientJson != null) {
      orderMap['patient_gender'] = patientJson['gender'];
      orderMap['patient_birth_date'] = patientJson['birth_date'];
      orderMap['patient_phone_number'] = patientJson['phone_number'];
    }

    return {'order': orderMap, if (patientJson != null) 'patient': patientJson};
  }

  /// decision = "accept" | "deny"
  Future<String> decideOrder({
    required String orderId,
    required String decision,
  }) async {
    final uri = Uri.parse('$_baseUrl/hospital/orders/$orderId/decision');

    final res = await _client.post(
      uri,
      headers: _headers(json: true),
      body: jsonEncode({'decision': decision}),
    );
    _throwIfNotOk(res);

    final data = jsonDecode(res.body);
    return data['status'] as String;
  }

  /// OrderReviewScreen:
  ///  - "progress" / "accepted" → "accept"
  ///  - "rejected" / "deny" / "denied" → "deny"
  Future<void> updateOrderStatus({
    required String orderId,
    required String newStatus,
  }) async {
    final normalized = HospitalService.normalizeOrderStatusForApi(newStatus);
    final lower = normalized.toLowerCase();
    String decision;

    if (lower == 'progress' || lower == 'accepted') {
      decision = 'accept';
    } else if (lower == 'rejected' || lower == 'deny' || lower == 'denied') {
      decision = 'deny';
    } else {
      // Fallback: send as-is
      decision = newStatus;
    }

    await decideOrder(orderId: orderId, decision: decision);
  }

  Future<Map<String, dynamic>> getOrderReport({required String orderId}) async {
    final uri = Uri.parse('$_baseUrl/hospital/orders/$orderId/report');

    final res = await _client.get(uri, headers: _headers());
    _throwIfNotOk(res);

    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  Future<OrderReportModel> getOrderReportModel(String orderId) async {
    final json = await getOrderReport(orderId: orderId);
    return OrderReportModel.fromJson(json);
  }

  /// ✅ Use named parameter so it matches calls like:
  ///    downloadOrderReportPdf(orderId: orderId)
  Future<http.Response> downloadOrderReportPdf({
    required String orderId,
  }) async {
    final uri = Uri.parse('$_baseUrl/hospital/orders/$orderId/report/pdf');
    final res = await _client.get(uri, headers: _headers());
    _throwIfNotOk(res);
    return res;
  }

  Future<void> exportOrderReportPdf({required String orderId}) async {
    await downloadOrderReportPdf(orderId: orderId);
  }
}

/// ======================= MODELS ==========================

class HospitalDashboardSummary {
  final String hospitalId;
  final int activePatients;
  final int newPatientsToday;
  final int activePrescriptions;
  final int ordersWaitingApproval;

  HospitalDashboardSummary({
    required this.hospitalId,
    required this.activePatients,
    required this.newPatientsToday,
    required this.activePrescriptions,
    required this.ordersWaitingApproval,
  });

  factory HospitalDashboardSummary.fromJson(Map<String, dynamic> json) {
    int asInt(dynamic v) => v is int ? v : (v is num ? v.toInt() : 0);

    return HospitalDashboardSummary(
      hospitalId: json['hospital_id']?.toString() ?? '',
      activePatients: asInt(json['active_patients']),
      newPatientsToday: asInt(json['new_patients_today']),
      activePrescriptions: asInt(json['active_prescriptions']),
      ordersWaitingApproval: asInt(json['orders_waiting_approval']),
    );
  }
}

// ---------- Patients ----------

class PatientModel {
  final String patientId;
  final String nationalId;
  final String? hospitalId; // nullable
  final String? name;
  final String? address;
  final String? email;
  final String? phoneNumber;
  final String? gender;
  final double? lat;
  final double? lon;
  final String status;
  final DateTime createdAt;

  PatientModel({
    required this.patientId,
    required this.nationalId,
    this.hospitalId,
    this.name,
    this.address,
    this.email,
    this.phoneNumber,
    this.gender,
    this.lat,
    this.lon,
    required this.status,
    required this.createdAt,
  });

  factory PatientModel.fromJson(Map<String, dynamic> json) {
    DateTime parseDate(dynamic v) {
      if (v == null) return DateTime.now();
      try {
        return DateTime.parse(v as String);
      } catch (_) {
        return DateTime.now();
      }
    }

    double? toDouble(dynamic v) {
      if (v == null) return null;
      if (v is num) return v.toDouble();
      if (v is String) {
        return double.tryParse(v);
      }
      return null;
    }

    return PatientModel(
      patientId: json['patient_id']?.toString() ?? '',
      nationalId: json['national_id']?.toString() ?? '',
      hospitalId: json['hospital_id']?.toString(),
      name: json['name'] as String?,
      address: json['address'] as String?,
      email: json['email'] as String?,
      phoneNumber: json['phone_number'] as String?,
      gender: json['gender'] as String?,
      lat: toDouble(json['lat']),
      lon: toDouble(json['lon']),
      status: json['status']?.toString() ?? '',
      createdAt: parseDate(json['created_at']),
    );
  }

  Map<String, dynamic> toJson() => {
    'patient_id': patientId,
    'national_id': nationalId,
    'hospital_id': hospitalId,
    'name': name,
    'address': address,
    'email': email,
    'phone_number': phoneNumber,
    'gender': gender,
    'lat': lat,
    'lon': lon,
    'status': status,
    'created_at': createdAt.toIso8601String(),
  };
}

class PatientCreateDto {
  final String nationalId;
  final String name;
  final String phoneNumber;
  final String? address;
  final String? email;
  final String? gender;

  /// Optional date of birth as String (e.g. "2001-07-14")
  final String? dateOfBirth;

  final double? lat;
  final double? lon;

  PatientCreateDto({
    required this.nationalId,
    required this.name,
    required this.phoneNumber,
    this.address,
    this.email,
    this.gender,
    this.dateOfBirth,
    this.lat,
    this.lon,
  });

  Map<String, dynamic> toJson() => {
    'national_id': nationalId,
    'name': name,
    'phone_number': phoneNumber,
    'address': address,
    'email': email,
    'gender': gender,
    // يرسل للبك إند كمفتاح birth_date
    'birth_date': dateOfBirth,
    'lat': lat,
    'lon': lon,
  };
}

class PatientPrescriptionSummaryModel {
  final String prescriptionId;
  final String medicineName;
  final String status; // "Active" / "Expired" / "Invalid"
  final String? refillLimitText;
  final DateTime? startDate;
  final DateTime? endDate;

  PatientPrescriptionSummaryModel({
    required this.prescriptionId,
    required this.medicineName,
    required this.status,
    this.refillLimitText,
    this.startDate,
    this.endDate,
  });

  factory PatientPrescriptionSummaryModel.fromJson(Map<String, dynamic> json) {
    DateTime? parseDate(dynamic v) {
      if (v == null) return null;
      try {
        return DateTime.parse(v as String);
      } catch (_) {
        return null;
      }
    }

    return PatientPrescriptionSummaryModel(
      prescriptionId: json['prescription_id']?.toString() ?? '',
      medicineName: json['medicine_name']?.toString() ?? '',
      status: json['status']?.toString() ?? '',
      refillLimitText: json['refill_limit_text'] as String?,
      startDate: parseDate(json['start_date']),
      endDate: parseDate(json['end_date']),
    );
  }
}

class PatientProfileModel {
  final String patientId;
  final String nationalId;
  final String name;
  final String? phoneNumber;
  final String? email;
  final String status;
  final String? gender;
  final DateTime? birthDate;
  final List<PatientPrescriptionSummaryModel> prescriptions;

  PatientProfileModel({
    required this.patientId,
    required this.nationalId,
    required this.name,
    this.phoneNumber,
    this.email,
    required this.status,
    this.gender,
    this.birthDate,
    required this.prescriptions,
  });

  factory PatientProfileModel.fromJson(Map<String, dynamic> json) {
    final list = (json['prescriptions'] as List<dynamic>? ?? [])
        .map(
          (e) => PatientPrescriptionSummaryModel.fromJson(
            e as Map<String, dynamic>,
          ),
        )
        .toList();

    DateTime? parseDate(dynamic v) {
      if (v == null) return null;
      try {
        return DateTime.parse(v as String);
      } catch (_) {
        return null;
      }
    }

    return PatientProfileModel(
      patientId: json['patient_id']?.toString() ?? '',
      nationalId: json['national_id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      phoneNumber: json['phone_number'] as String?,
      email: json['email'] as String?,
      status: json['status']?.toString() ?? '',
      gender: json['gender'] as String?,
      birthDate: parseDate(json['birth_date']),
      prescriptions: list,
    );
  }
}

// ---------- Medications ----------

class MedicationModel {
  final String medicationId;
  final String name;
  final String? description;
  final String? informationSource;
  final DateTime? expDate;
  final String? riskLevel;

  MedicationModel({
    required this.medicationId,
    required this.name,
    this.description,
    this.informationSource,
    this.expDate,
    this.riskLevel,
  });

  factory MedicationModel.fromJson(Map<String, dynamic> json) {
    DateTime? parseDate(dynamic v) {
      if (v == null) return null;
      try {
        return DateTime.parse(v as String);
      } catch (_) {
        return null;
      }
    }

    return MedicationModel(
      medicationId: json['medication_id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      description: json['description'] as String?,
      informationSource: json['information_source'] as String?,
      expDate: parseDate(json['exp_date']),
      riskLevel: json['risk_level'] as String?,
    );
  }

  // ✅ ADDED (NO DELETION): so we can convert MedicationModel -> Map for UI screens
  Map<String, dynamic> toJson() => {
    'medication_id': medicationId,
    'name': name,
    'description': description,
    'information_source': informationSource,
    'exp_date': expDate?.toIso8601String(),
    'risk_level': riskLevel,
  };
}

// ---------- Prescriptions ----------

class PrescriptionCreateDto {
  final String patientNationalId;
  final String medicationId;
  final String instructions;
  final String prescribingDoctor;
  final DateTime? expirationDate;
  final int? reorderThreshold;

  PrescriptionCreateDto({
    required this.patientNationalId,
    required this.medicationId,
    required this.instructions,
    required this.prescribingDoctor,
    this.expirationDate,
    this.reorderThreshold,
  });

  Map<String, dynamic> toJson() => {
    'patient_national_id': patientNationalId,
    'medication_id': medicationId,
    'instructions': instructions,
    'prescribing_doctor': prescribingDoctor,
    'expiration_date': expirationDate?.toIso8601String(),
    'reorder_threshold': reorderThreshold,
  };
}

class PrescriptionCardModel {
  final String prescriptionId;
  final String name;
  final String code;
  final String patient;
  final int? refillLimit;
  final DateTime? startDate;
  final DateTime? endDate;
  final String status;

  PrescriptionCardModel({
    required this.prescriptionId,
    required this.name,
    required this.code,
    required this.patient,
    this.refillLimit,
    this.startDate,
    this.endDate,
    required this.status,
  });

  factory PrescriptionCardModel.fromJson(Map<String, dynamic> json) {
    DateTime? parseDate(dynamic v) {
      if (v == null) return null;
      try {
        return DateTime.parse(v as String);
      } catch (_) {
        return null;
      }
    }

    return PrescriptionCardModel(
      prescriptionId: json['prescription_id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      code: json['code']?.toString() ?? '',
      patient: json['patient']?.toString() ?? '',
      refillLimit: json['refill_limit'] as int?,
      startDate: parseDate(json['start_date']),
      endDate: parseDate(json['end_date']),
      status: json['status']?.toString() ?? '',
    );
  }
}

/// Prescription Detail
class PrescriptionDetailModel {
  final String prescriptionId;

  // Patient info
  final String patientName;
  final String patientNationalId;
  final String? patientGender;
  final DateTime? patientBirthDate;
  final String? patientPhoneNumber;

  // Prescription info
  final String medicationName;
  final String prescribingDoctor;
  final String hospitalName;
  final String instructions;
  final DateTime? validUntil;
  final int? refillLimit;
  final String status;

  PrescriptionDetailModel({
    required this.prescriptionId,
    required this.patientName,
    required this.patientNationalId,
    this.patientGender,
    this.patientBirthDate,
    this.patientPhoneNumber,
    required this.medicationName,
    required this.prescribingDoctor,
    required this.hospitalName,
    required this.instructions,
    this.validUntil,
    this.refillLimit,
    required this.status,
  });

  factory PrescriptionDetailModel.fromJson(Map<String, dynamic> json) {
    // Helpers
    String asString(dynamic v) => v == null ? '' : v.toString();

    DateTime? parseDate(dynamic v) {
      if (v == null) return null;
      try {
        return DateTime.parse(v.toString());
      } catch (_) {
        return null;
      }
    }

    int? asInt(dynamic v) {
      if (v == null) return null;
      if (v is int) return v;
      if (v is num) return v.toInt();
      if (v is String) return int.tryParse(v);
      return null;
    }

    final DateTime? startDate = parseDate(json['start_date']);
    final DateTime? endDate = parseDate(json['end_date']);
    final DateTime? validDate =
        parseDate(
          json['valid_until'] ?? json['expiration_date'] ?? json['exp_date'],
        ) ??
        endDate ??
        startDate;

    final gender = asString(json['patient_gender'] ?? json['gender']);
    final phone = asString(
      json['patient_phone_number'] ?? json['phone_number'],
    );

    return PrescriptionDetailModel(
      prescriptionId: asString(
        json['prescription_id'] ?? json['id'] ?? json['code'],
      ),
      patientName: asString(json['patient_name'] ?? json['name']),
      patientNationalId: asString(
        json['patient_national_id'] ?? json['national_id'],
      ),
      patientGender: gender.isEmpty ? null : gender,
      patientBirthDate: parseDate(
        json['patient_birth_date'] ?? json['birth_date'],
      ),
      patientPhoneNumber: phone.isEmpty ? null : phone,
      medicationName: asString(
        json['medication_name'] ?? json['medicine_name'] ?? json['medication'],
      ),
      prescribingDoctor: asString(json['prescribing_doctor'] ?? json['doctor']),
      hospitalName: asString(json['hospital_name'] ?? json['hospital']),
      instructions: asString(
        json['instructions'] ??
            json['dosage_instructions'] ??
            json['notes'] ??
            '',
      ),
      validUntil: validDate,
      refillLimit: asInt(
        json['refill_limit'] ??
            json['reorder_threshold'] ??
            json['refill_limit_text'],
      ),
      status: asString(json['status']),
    );
  }
}

// ---------- Orders ----------

class OrderSummaryModel {
  final String orderId;
  final String code;
  final String medicineName;
  final String patientName;
  final DateTime placedAt;
  final String status;
  final String priorityLevel;
  final bool canGenerateReport;

  OrderSummaryModel({
    required this.orderId,
    required this.code,
    required this.medicineName,
    required this.patientName,
    required this.placedAt,
    required this.status,
    required this.priorityLevel,
    required this.canGenerateReport,
  });

  /// ✅ ADDED (NO DELETION): UI-friendly status label
  String get statusLabel => HospitalService.normalizeOrderStatusForUi(status);

  factory OrderSummaryModel.fromJson(Map<String, dynamic> json) {
    DateTime parseDate(dynamic v) {
      if (v == null) return DateTime.now();
      try {
        return DateTime.parse(v as String);
      } catch (_) {
        return DateTime.now();
      }
    }

    bool parseBool(dynamic v) {
      if (v is bool) return v;
      if (v is num) return v != 0;
      if (v is String) {
        return v.toLowerCase() == 'true' || v == '1';
      }
      return false;
    }

    return OrderSummaryModel(
      orderId: json['order_id']?.toString() ?? '',
      code: json['code']?.toString() ?? '',
      medicineName: json['medicine_name']?.toString() ?? '',
      patientName: json['patient_name']?.toString() ?? '',
      placedAt: parseDate(json['placed_at']),
      status: json['status']?.toString() ?? '',
      priorityLevel: json['priority_level']?.toString() ?? '',
      canGenerateReport: parseBool(json['can_generate_report']),
    );
  }
}

class OrderDetailModel {
  final String orderId;
  final String code;
  final String status;
  final String priorityLevel;
  final DateTime placedAt;
  final DateTime? deliveredAt;
  final String medicineName;
  final String patientName;
  final String patientNationalId;
  final String hospitalName;
  final String? locationCity;
  final String? locationDescription;
  final double? locationLat;
  final double? locationLon;
  final String deliveryType;
  final String deliveryTime;
  final String systemRecommendation;
  final int? otp;

  // 🔹 Prescription-related fields
  final String? prescriptionId;
  final String? instructions;
  final String? prescribingDoctor;
  final DateTime? expirationDate;
  final int? reorderThreshold;
  final int? refillLimit;

  OrderDetailModel({
    required this.orderId,
    required this.code,
    required this.status,
    required this.priorityLevel,
    required this.placedAt,
    this.deliveredAt,
    required this.medicineName,
    required this.patientName,
    required this.patientNationalId,
    required this.hospitalName,
    this.locationCity,
    this.locationDescription,
    this.locationLat,
    this.locationLon,
    required this.deliveryType,
    required this.deliveryTime,
    required this.systemRecommendation,
    this.otp,
    this.prescriptionId,
    this.instructions,
    this.prescribingDoctor,
    this.expirationDate,
    this.reorderThreshold,
    this.refillLimit,
  });

  /// ✅ ADDED (NO DELETION): UI-friendly status label
  String get statusLabel => HospitalService.normalizeOrderStatusForUi(status);

  factory OrderDetailModel.fromJson(Map<String, dynamic> json) {
    DateTime parseDate(dynamic v) {
      if (v == null) return DateTime.now();
      try {
        return DateTime.parse(v as String);
      } catch (_) {
        return DateTime.now();
      }
    }

    DateTime? parseDateNullable(dynamic v) {
      if (v == null) return null;
      try {
        return DateTime.parse(v as String);
      } catch (_) {
        return null;
      }
    }

    double? toDouble(dynamic v) {
      if (v == null) return null;
      if (v is num) return v.toDouble();
      if (v is String) {
        return double.tryParse(v);
      }
      return null;
    }

    String? asStringNullable(dynamic v) {
      if (v == null) return null;
      return v.toString();
    }

    int? asIntNullable(dynamic v) {
      if (v == null) return null;
      if (v is int) return v;
      if (v is num) return v.toInt();
      if (v is String) return int.tryParse(v);
      return null;
    }

    return OrderDetailModel(
      orderId: json['order_id']?.toString() ?? '',
      code: json['code']?.toString() ?? '',
      status: json['status']?.toString() ?? '',
      priorityLevel: json['priority_level']?.toString() ?? '',
      placedAt: parseDate(json['placed_at']),
      deliveredAt: parseDateNullable(json['delivered_at']),
      medicineName: json['medicine_name']?.toString() ?? '',
      patientName: json['patient_name']?.toString() ?? '',
      patientNationalId: json['patient_national_id']?.toString() ?? '',
      hospitalName: json['hospital_name']?.toString() ?? '',
      locationCity: json['location_city'] as String?,
      locationDescription: json['location_description'] as String?,
      locationLat: toDouble(json['location_lat']),
      locationLon: toDouble(json['location_lon']),
      deliveryType: (json['delivery_type'] ?? 'delivery').toString(),
      deliveryTime: (json['delivery_time'] ?? 'morning').toString(),
      systemRecommendation: (json['system_recommendation'] ?? 'delivery')
          .toString(),
      otp: json['otp'] is int
          ? json['otp'] as int?
          : asIntNullable(json['otp']),

      // 🔹 Prescription fields
      prescriptionId: asStringNullable(json['prescription_id']),
      instructions: asStringNullable(json['instructions']),
      prescribingDoctor: asStringNullable(json['prescribing_doctor']),
      expirationDate: parseDateNullable(json['expiration_date']),
      reorderThreshold: asIntNullable(json['reorder_threshold']),
      refillLimit: asIntNullable(json['refill_limit']),
    );
  }
}

// ---------- Report ----------

class DeliveryDetailModel {
  final String status;
  final String description;
  final String duration;
  final String stability;
  final String condition;

  DeliveryDetailModel({
    required this.status,
    required this.description,
    required this.duration,
    required this.stability,
    required this.condition,
  });

  factory DeliveryDetailModel.fromJson(Map<String, dynamic> json) {
    return DeliveryDetailModel(
      status: json['status']?.toString() ?? '',
      description: json['description']?.toString() ?? '',
      duration: json['duration']?.toString() ?? '',
      stability: json['stability']?.toString() ?? '',
      condition: json['condition']?.toString() ?? '',
    );
  }
}

// ===================== ✅ NEW MODELS FOR (B) =====================

class TimelineEventModel {
  final String eventStatus;
  final String eventMessage;
  final String duration;
  final String remainingStability;
  final String condition;
  final double? lat;
  final double? lon;
  final DateTime? eta;
  final DateTime? recordedAt;

  TimelineEventModel({
    required this.eventStatus,
    required this.eventMessage,
    required this.duration,
    required this.remainingStability,
    required this.condition,
    this.lat,
    this.lon,
    this.eta,
    this.recordedAt,
  });

  static DateTime? _parseDateNullable(dynamic v) {
    if (v == null) return null;
    try {
      return DateTime.parse(v.toString());
    } catch (_) {
      return null;
    }
  }

  static double? _toDouble(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString());
  }

  factory TimelineEventModel.fromJson(Map<String, dynamic> json) {
    return TimelineEventModel(
      eventStatus: json['event_status']?.toString() ?? '',
      eventMessage: json['event_message']?.toString() ?? '',
      duration: json['duration']?.toString() ?? '',
      remainingStability: json['remaining_stability']?.toString() ?? '',
      condition: json['condition']?.toString() ?? '',
      lat: _toDouble(json['lat']),
      lon: _toDouble(json['lon']),
      eta: _parseDateNullable(json['eta']),
      recordedAt: _parseDateNullable(json['recorded_at']),
    );
  }
}

class NotificationEventModel {
  final String notificationType;
  final String notificationContent;
  final DateTime? notificationTime;

  NotificationEventModel({
    required this.notificationType,
    required this.notificationContent,
    this.notificationTime,
  });

  static DateTime? _parseDateNullable(dynamic v) {
    if (v == null) return null;
    try {
      return DateTime.parse(v.toString());
    } catch (_) {
      return null;
    }
  }

  factory NotificationEventModel.fromJson(Map<String, dynamic> json) {
    return NotificationEventModel(
      notificationType: json['notification_type']?.toString() ?? '',
      notificationContent: json['notification_content']?.toString() ?? '',
      notificationTime: _parseDateNullable(json['notification_time']),
    );
  }
}

class TemperaturePointModel {
  final String tempValue;
  final double? tempC;
  final DateTime? recordedAt;

  TemperaturePointModel({required this.tempValue, this.tempC, this.recordedAt});

  static DateTime? _parseDateNullable(dynamic v) {
    if (v == null) return null;
    try {
      return DateTime.parse(v.toString());
    } catch (_) {
      return null;
    }
  }

  static double? _toDouble(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString());
  }

  factory TemperaturePointModel.fromJson(Map<String, dynamic> json) {
    return TemperaturePointModel(
      tempValue: json['temp_value']?.toString() ?? '',
      tempC: _toDouble(json['temp_c']),
      recordedAt: _parseDateNullable(json['recorded_at']),
    );
  }
}

class GpsPointModel {
  final double? latitude;
  final double? longitude;
  final DateTime? recordedAt;

  GpsPointModel({this.latitude, this.longitude, this.recordedAt});

  static DateTime? _parseDateNullable(dynamic v) {
    if (v == null) return null;
    try {
      return DateTime.parse(v.toString());
    } catch (_) {
      return null;
    }
  }

  static double? _toDouble(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString());
  }

  factory GpsPointModel.fromJson(Map<String, dynamic> json) {
    return GpsPointModel(
      latitude: _toDouble(json['latitude']),
      longitude: _toDouble(json['longitude']),
      recordedAt: _parseDateNullable(json['recorded_at']),
    );
  }
}

class EtaPointModel {
  final String delayTime;
  final DateTime? recordedAt;

  EtaPointModel({required this.delayTime, this.recordedAt});

  static DateTime? _parseDateNullable(dynamic v) {
    if (v == null) return null;
    try {
      return DateTime.parse(v.toString());
    } catch (_) {
      return null;
    }
  }

  factory EtaPointModel.fromJson(Map<String, dynamic> json) {
    return EtaPointModel(
      delayTime: json['delay_time']?.toString() ?? '',
      recordedAt: _parseDateNullable(json['recorded_at']),
    );
  }
}

class StabilityPointModel {
  final String stabilityTime;
  final DateTime? recordedAt;

  StabilityPointModel({required this.stabilityTime, this.recordedAt});

  static DateTime? _parseDateNullable(dynamic v) {
    if (v == null) return null;
    try {
      return DateTime.parse(v.toString());
    } catch (_) {
      return null;
    }
  }

  factory StabilityPointModel.fromJson(Map<String, dynamic> json) {
    return StabilityPointModel(
      stabilityTime: json['stability_time']?.toString() ?? '',
      recordedAt: _parseDateNullable(json['recorded_at']),
    );
  }
}

class TelemetrySummaryModel {
  final double? tempMin;
  final double? tempMax;
  final double? tempAvg;
  final int temperaturePoints;
  final int gpsPoints;
  final int etaPoints;
  final int stabilityPoints;
  final int timelineEvents;
  final int notifications;

  TelemetrySummaryModel({
    this.tempMin,
    this.tempMax,
    this.tempAvg,
    required this.temperaturePoints,
    required this.gpsPoints,
    required this.etaPoints,
    required this.stabilityPoints,
    required this.timelineEvents,
    required this.notifications,
  });

  static double? _toDouble(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString());
  }

  static int _toInt(dynamic v) {
    if (v == null) return 0;
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString()) ?? 0;
  }

  factory TelemetrySummaryModel.fromJson(Map<String, dynamic> json) {
    return TelemetrySummaryModel(
      tempMin: _toDouble(json['temp_min']),
      tempMax: _toDouble(json['temp_max']),
      tempAvg: _toDouble(json['temp_avg']),
      temperaturePoints: _toInt(json['temperature_points']),
      gpsPoints: _toInt(json['gps_points']),
      etaPoints: _toInt(json['eta_points']),
      stabilityPoints: _toInt(json['stability_points']),
      timelineEvents: _toInt(json['timeline_events']),
      notifications: _toInt(json['notifications']),
    );
  }
}

// ===================== ✅ UPDATED OrderReportModel (NO BREAKING) =====================

class OrderReportModel {
  final String reportId;
  final String type;
  final DateTime generated;
  final String orderId;
  final String orderCode;
  final String? orderType;
  final String orderStatus;
  final DateTime createdAt;
  final DateTime? deliveredAt;
  final String otpCode;
  final bool verified;
  final String priority;
  final String patientName;
  final String? phoneNumber;
  final String hospitalName;
  final String medicationName;
  final String? allowedTemp;
  final String? maxExcursion;
  final String? returnToFridge;
  final List<DeliveryDetailModel> deliveryDetails;

  // ✅ NEW (B) fields
  final List<TimelineEventModel> timelineEvents;
  final List<NotificationEventModel> notifications;
  final List<TemperaturePointModel> temperatureSeries;
  final List<GpsPointModel> gpsSeries;
  final List<EtaPointModel> etaSeries;
  final List<StabilityPointModel> stabilitySeries;
  final TelemetrySummaryModel? telemetrySummary;
  final String? dashboardId;

  OrderReportModel({
    required this.reportId,
    required this.type,
    required this.generated,
    required this.orderId,
    required this.orderCode,
    this.orderType,
    required this.orderStatus,
    required this.createdAt,
    this.deliveredAt,
    required this.otpCode,
    required this.verified,
    required this.priority,
    required this.patientName,
    this.phoneNumber,
    required this.hospitalName,
    required this.medicationName,
    this.allowedTemp,
    this.maxExcursion,
    this.returnToFridge,
    required this.deliveryDetails,

    // ✅ new
    required this.timelineEvents,
    required this.notifications,
    required this.temperatureSeries,
    required this.gpsSeries,
    required this.etaSeries,
    required this.stabilitySeries,
    this.telemetrySummary,
    this.dashboardId,
  });

  factory OrderReportModel.fromJson(Map<String, dynamic> json) {
    DateTime parseDate(dynamic v) {
      if (v == null) return DateTime.now();
      try {
        return DateTime.parse(v as String);
      } catch (_) {
        return DateTime.now();
      }
    }

    DateTime? parseDateNullable(dynamic v) {
      if (v == null) return null;
      try {
        return DateTime.parse(v as String);
      } catch (_) {
        return null;
      }
    }

    bool parseBool(dynamic v) {
      if (v is bool) return v;
      if (v is num) return v != 0;
      if (v is String) {
        return v.toLowerCase() == 'true' || v == '1';
      }
      return false;
    }

    final details = (json['delivery_details'] as List<dynamic>? ?? [])
        .map((e) => DeliveryDetailModel.fromJson(e as Map<String, dynamic>))
        .toList();

    final timeline = (json['timeline_events'] as List<dynamic>? ?? [])
        .map((e) => TimelineEventModel.fromJson(e as Map<String, dynamic>))
        .toList();

    final notifs = (json['notifications'] as List<dynamic>? ?? [])
        .map((e) => NotificationEventModel.fromJson(e as Map<String, dynamic>))
        .toList();

    final temps = (json['temperature_series'] as List<dynamic>? ?? [])
        .map((e) => TemperaturePointModel.fromJson(e as Map<String, dynamic>))
        .toList();

    final gps = (json['gps_series'] as List<dynamic>? ?? [])
        .map((e) => GpsPointModel.fromJson(e as Map<String, dynamic>))
        .toList();

    final eta = (json['eta_series'] as List<dynamic>? ?? [])
        .map((e) => EtaPointModel.fromJson(e as Map<String, dynamic>))
        .toList();

    final stability = (json['stability_series'] as List<dynamic>? ?? [])
        .map((e) => StabilityPointModel.fromJson(e as Map<String, dynamic>))
        .toList();

    TelemetrySummaryModel? summary;
    final summaryJson = json['telemetry_summary'];
    if (summaryJson is Map<String, dynamic>) {
      summary = TelemetrySummaryModel.fromJson(summaryJson);
    }

    return OrderReportModel(
      reportId: json['report_id']?.toString() ?? '',
      type: json['type']?.toString() ?? '',
      generated: parseDate(json['generated']),
      orderId: json['order_id']?.toString() ?? '',
      orderCode: json['order_code']?.toString() ?? '',
      orderType: json['order_type'] as String?,
      orderStatus: json['order_status']?.toString() ?? '',
      createdAt: parseDate(json['created_at']),
      deliveredAt: parseDateNullable(json['delivered_at']),
      otpCode: json['otp_code']?.toString() ?? '',
      verified: parseBool(json['verified']),
      priority: json['priority']?.toString() ?? '',
      patientName: json['patient_name']?.toString() ?? '',
      phoneNumber: json['phone_number'] as String?,
      hospitalName: json['hospital_name']?.toString() ?? '',
      medicationName: json['medication_name']?.toString() ?? '',
      allowedTemp: json['allowed_temp'] as String?,
      maxExcursion: json['max_excursion'] as String?,
      returnToFridge: json['return_to_fridge'] as String?,
      deliveryDetails: details,

      // ✅ new
      timelineEvents: timeline,
      notifications: notifs,
      temperatureSeries: temps,
      gpsSeries: gps,
      etaSeries: eta,
      stabilitySeries: stability,
      telemetrySummary: summary,
      dashboardId: json['dashboard_id']?.toString(),
    );
  }
}
