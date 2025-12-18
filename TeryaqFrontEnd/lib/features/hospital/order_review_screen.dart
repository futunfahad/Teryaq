import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:easy_localization/easy_localization.dart';

import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' as latLng;

import '../../constants/app_colors.dart';
import '../../widgets/custom_top_bar.dart';
import '../../widgets/custom_popup.dart';

// Hospital backend service + config
import 'package:teryagapptry/services/hospital_service.dart';

class OrderReviewScreen extends StatefulWidget {
  /// Backend order_id used to fetch order details
  final String orderId;

  const OrderReviewScreen({super.key, required this.orderId});

  @override
  State<OrderReviewScreen> createState() => _OrderReviewScreenState();
}

class _OrderReviewScreenState extends State<OrderReviewScreen> {
  // =========================================================
  // 🔥 Backend-driven state (safe defaults)
  // =========================================================

  double locationLat = 24.774265; // Fallback: Riyadh
  double locationLng = 46.738586;

  /// Order status: pending | progress | completed | rejected
  String orderStatus = "pending";

  Map<String, String> patient = {
    "name": "—",
    "gender": "—",
    "nationalId": "—",
    "dob": "—",
    "phone": "—",
  };

  Map<String, String> prescription = {
    "medicationName": "—",
    "doctor": "—",
    "hospital": "—",
    "instructions": "—",
    "validUntil": "—",
    "refillLimit": "—",
    "prescriptionID": "—",
  };

  Map<String, String> location = {"city": "—", "description": "—"};

  // User choices (from backend or patient preferences)
  String deliveryType = "delivery"; // delivery | pickup
  String deliveryTime = "evening"; // morning | evening
  String systemRecommendation = "delivery"; // delivery | pickup

  bool _isLoading = true;
  String? _errorMessage;
  bool _isUpdatingStatus = false;

  late final HospitalService _hospitalService;

  /// Tile URL template used by FlutterMap
  final String _tilesUrlTemplate = HospitalConfig.tilesTemplate;

  String get systemRecommendationLabel {
    return systemRecommendation == "delivery"
        ? "delivery_label".tr()
        : "pickup_label".tr();
  }

  @override
  void initState() {
    super.initState();

    // Use global hospital backend base URL from HospitalConfig
    _hospitalService = HospitalService(baseUrl: HospitalConfig.apiBaseUrl);

    _fetchOrderReview();
  }

  // =========================================================
  // 🔗 Fetch order details from backend
  // =========================================================
  Future<void> _fetchOrderReview() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final Map<String, dynamic> raw = await _hospitalService.getOrderReview(
        orderId: widget.orderId,
      );

      setState(() {
        _applyBackendData(raw);
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = e.toString();
      });
    }
  }

  // =========================================================
  // 🧠 Normalize & map backend JSON into the UI fields
  // =========================================================
  void _applyBackendData(Map<String, dynamic> rawJson) {
    // Handle different root shapes: { "order": {...} }, { "data": {...} }, or flat JSON
    final Map<String, dynamic> json;
    if (rawJson['order'] is Map<String, dynamic>) {
      json = Map<String, dynamic>.from(rawJson['order']);
    } else if (rawJson['data'] is Map<String, dynamic>) {
      json = Map<String, dynamic>.from(rawJson['data']);
    } else {
      json = rawJson;
    }

    // -------------------------
    // 🔹 Patient object / flat
    // -------------------------
    Map<String, dynamic> p = {};
    if (json['patient'] is Map<String, dynamic>) {
      p = Map<String, dynamic>.from(json['patient']);
    } else if (json['patient_info'] is Map<String, dynamic>) {
      p = Map<String, dynamic>.from(json['patient_info']);
    } else {
      // Fallback: flat fields from order/detail/report responses
      p = {
        'name': json['patient_name'],
        'gender': json['patient_gender'],
        'national_id': json['patient_national_id'] ?? json['national_id'],
        'dob':
            json['patient_birth_date'] ??
            json['birth_date'] ??
            json['patient_dob'],
        'phone_number':
            json['patient_phone_number'] ??
            json['phone_number'] ??
            json['patient_phone'],
      }..removeWhere((key, value) => value == null);
    }

    // -------------------------
    // 🔹 Prescription object / flat
    // -------------------------
    Map<String, dynamic> rx = {};
    if (json['prescription'] is Map<String, dynamic>) {
      rx = Map<String, dynamic>.from(json['prescription']);
    } else if (json['prescription_info'] is Map<String, dynamic>) {
      rx = Map<String, dynamic>.from(json['prescription_info']);
    } else {
      rx = {
        'medication_name':
            json['medication_name'] ??
            json['medicine_name'] ??
            json['med_name'],
        'doctor':
            json['prescribing_doctor'] ?? json['doctor'] ?? json['doctor_name'],
        'hospital': json['hospital_name'] ?? json['hospital'],
        'instructions': json['instructions'],
        'valid_until':
            json['valid_until'] ??
            json['expiration_date'] ??
            json['expiry_date'] ??
            json['end_date'],
        'refill_limit': json['refill_limit'] ?? json['reorder_threshold'],
        'prescription_id': json['prescription_id'] ?? json['prescription_code'],
      }..removeWhere((key, value) => value == null);
    }

    // -------------------------
    // 🔹 Location object / flat
    // -------------------------
    Map<String, dynamic> loc = {};
    if (json['location'] is Map<String, dynamic>) {
      loc = Map<String, dynamic>.from(json['location']);
    } else if (json['address'] is Map<String, dynamic>) {
      loc = Map<String, dynamic>.from(json['address']);
    } else {
      loc = {
        'city': json['location_city'] ?? json['city'] ?? json['region'],
        'description': json['location_description'] ?? json['address'],
        'lat': json['location_lat'] ?? json['lat'],
        'lng': json['location_lon'] ?? json['location_lng'] ?? json['lng'],
      }..removeWhere((key, value) => value == null);
    }

    // -------------------------
    // 🔹 Location coordinates (with Riyadh fallback)
    // -------------------------
    const double riyadhLat = 24.774265;
    const double riyadhLng = 46.738586;

    final dynamic latRaw =
        json['location_lat'] ?? loc['lat'] ?? loc['latitude'] ?? json['lat'];
    final dynamic lngRaw =
        json['location_lon'] ??
        json['location_lng'] ??
        loc['lng'] ??
        loc['longitude'] ??
        json['lon'];

    double toDouble(dynamic v, double fallback) {
      if (v == null) return fallback;
      if (v is double) return v;
      if (v is int) return v.toDouble();
      if (v is String) {
        return double.tryParse(v) ?? fallback;
      }
      return fallback;
    }

    // ✅ لو ما جا شيء من الـ backend نستخدم دائماً إحداثيات الرياض
    locationLat = toDouble(latRaw, riyadhLat);
    locationLng = toDouble(lngRaw, riyadhLng);

    // -------------------------
    // 🔹 Order status & preferences
    // -------------------------
    // -------------------------
    // 🔹 Order status & preferences
    // -------------------------
    String rawStatus = (json['status'] ?? json['order_status'] ?? orderStatus)
        .toString();
    rawStatus = rawStatus.toLowerCase();

    // Treat "created"/"new" as "pending"
    if (rawStatus == 'created' || rawStatus == 'new') {
      rawStatus = 'pending';
    }

    orderStatus = rawStatus;

    // 🔹 Patient-selected DELIVERY TYPE (delivery | pickup)
    //  - order_type          → from Order.order_type (DB)
    //  - delivery_type       → if backend exposes it by that name
    //  - preferred_delivery_type / preferred_deliveryType → if added later
    //  - p['preferred_delivery_type'] → if patient object carries it
    deliveryType =
        (json['delivery_type'] ??
                json['order_type'] ??
                json['preferred_delivery_type'] ??
                json['preferredDeliveryType'] ??
                p['preferred_delivery_type'] ??
                json['deliveryType'] ??
                deliveryType)
            .toString()
            .toLowerCase();

    // 🔹 Patient-selected DELIVERY TIME (morning | evening)
    //  - preferred_delivery_time → recommended name
    //  - delivery_time           → alternative
    deliveryTime =
        (json['preferred_delivery_time'] ??
                json['delivery_time'] ??
                json['preferredDeliveryTime'] ??
                json['deliveryTime'] ??
                deliveryTime)
            .toString()
            .toLowerCase();

    // 🔹 System recommendation (ML decision)
    //  - system_recommendation   → API field
    //  - ml_delivery_type        → from Order.ml_delivery_type
    systemRecommendation =
        (json['system_recommendation'] ??
                json['ml_delivery_type'] ??
                systemRecommendation)
            .toString()
            .toLowerCase();

    // -------------------------
    // 🔹 Patient (final mapping)
    // -------------------------
    patient = {
      "name": (p['name'] ?? p['patient_name'] ?? json['patient_name'] ?? '—')
          .toString(),
      "gender": (p['gender'] ?? json['patient_gender'] ?? '—').toString(),
      "nationalId":
          (p['national_id'] ??
                  p['patient_national_id'] ??
                  json['patient_national_id'] ??
                  json['national_id'] ??
                  '—')
              .toString(),
      "dob":
          (p['dob'] ??
                  p['date_of_birth'] ??
                  p['birth_date'] ??
                  json['patient_birth_date'] ??
                  json['birth_date'] ??
                  '—')
              .toString(),
      "phone":
          (p['phone'] ??
                  p['phone_number'] ??
                  p['mobile'] ??
                  json['patient_phone'] ??
                  json['patient_phone_number'] ??
                  json['phone_number'] ??
                  '—')
              .toString(),
    };

    // -------------------------
    // 🔹 Prescription (final mapping)
    // -------------------------
    prescription = {
      "medicationName":
          (rx['medication_name'] ??
                  rx['medicine_name'] ??
                  json['medication_name'] ??
                  json['medicine_name'] ??
                  '—')
              .toString(),
      "doctor":
          (rx['doctor'] ??
                  rx['prescribing_doctor'] ??
                  json['prescribing_doctor'] ??
                  json['doctor'] ??
                  '—')
              .toString(),
      "hospital":
          (rx['hospital'] ??
                  rx['hospital_name'] ??
                  json['hospital_name'] ??
                  json['hospital'] ??
                  '—')
              .toString(),
      "instructions":
          (rx['instructions'] ??
                  rx['usage_instructions'] ??
                  json['instructions'] ??
                  '—')
              .toString(),
      "validUntil":
          (rx['valid_until'] ??
                  rx['validTo'] ??
                  rx['expiry_date'] ??
                  rx['expiration_date'] ??
                  json['valid_until'] ??
                  json['expiration_date'] ??
                  json['expiry_date'] ??
                  json['end_date'] ??
                  '—')
              .toString(),
      "refillLimit":
          (rx['refill_limit'] ??
                  rx['reorder_threshold'] ??
                  json['refill_limit'] ??
                  json['reorder_threshold'] ??
                  '—')
              .toString(),
      "prescriptionID":
          (rx['prescription_id'] ??
                  rx['prescription_code'] ??
                  json['prescription_id'] ??
                  json['prescription_code'] ??
                  '—')
              .toString(),
    };

    // -------------------------
    // 🔹 Location text (city + description) مع تطبيع Unknown → Riyadh
    // -------------------------
    String normalizeCity(dynamic v) {
      final s = (v ?? '').toString().trim();
      if (s.isEmpty || s.toLowerCase() == 'unknown') {
        return 'Riyadh'; // ✅ ديفولت المدينة
      }
      return s;
    }

    location = {
      "city": normalizeCity(
        loc['city'] ?? loc['region'] ?? json['location_city'] ?? json['city'],
      ),
      "description":
          (loc['description'] ??
                  loc['address'] ??
                  json['location_description'] ??
                  json['address'] ??
                  '—')
              .toString(),
    };
  }

  // =========================================================
  // 🔗 Update order status (ACCEPT / DENY)
  // =========================================================
  Future<void> _updateOrderStatus(String newStatus) async {
    if (_isUpdatingStatus) return;

    setState(() => _isUpdatingStatus = true);

    try {
      await _hospitalService.updateOrderStatus(
        orderId: widget.orderId,
        newStatus: newStatus,
      );

      setState(() {
        orderStatus = newStatus;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("failed_to_update_status".tr())));
      }
    } finally {
      if (mounted) {
        setState(() => _isUpdatingStatus = false);
      }
    }
  }

  // =========================================================
  // MAP BOTTOM SHEET (FlutterMap + TileServer)
  // =========================================================
  void _openLocationMap(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      enableDrag: false,
      isDismissible: true,
      builder: (context) {
        return Container(
          height: MediaQuery.of(context).size.height * 0.95,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(22.r)),
          ),
          child: Column(
            children: [
              // Header
              Container(
                padding: EdgeInsets.symmetric(horizontal: 20.w, vertical: 16.h),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(
                    top: Radius.circular(22.r),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.07),
                      blurRadius: 6,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      "view_location".tr(),
                      style: TextStyle(
                        fontFamily: "Poppins",
                        fontSize: 18.sp,
                        fontWeight: FontWeight.w700,
                        color: AppColors.bodyText,
                      ),
                    ),
                    GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: Icon(
                        Icons.close,
                        size: 26.sp,
                        color: const Color(0xFF8D8D8D),
                      ),
                    ),
                  ],
                ),
              ),

              // 🌍 FlutterMap with TileServer
              Expanded(
                child: FlutterMap(
                  options: MapOptions(
                    initialCenter: latLng.LatLng(locationLat, locationLng),
                    initialZoom: 15,
                    interactionOptions: const InteractionOptions(
                      flags: InteractiveFlag.all,
                    ),
                  ),
                  children: [
                    // 🧱 Tile layer from your gateway / TileServer
                    TileLayer(
                      urlTemplate: _tilesUrlTemplate,
                      userAgentPackageName: 'com.teryag.hospital',
                    ),

                    // 📍 Marker at patient location
                    MarkerLayer(
                      markers: [
                        Marker(
                          point: latLng.LatLng(locationLat, locationLng),
                          width: 40.w,
                          height: 40.h,
                          alignment: Alignment.center,
                          child: const Icon(
                            Icons.location_on,
                            size: 34,
                            color: Colors.red,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // =========================================================
  // BUILD
  // =========================================================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: CustomTopBar(title: "order_review".tr(), showBackButton: true),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return Center(
        child: Padding(
          padding: EdgeInsets.only(top: 40.h),
          child: const CircularProgressIndicator(),
        ),
      );
    }

    if (_errorMessage != null) {
      return Padding(
        padding: EdgeInsets.symmetric(horizontal: 25.w),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              "failed_to_load_order".tr(),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 16.sp,
                fontWeight: FontWeight.w600,
                color: Colors.red,
              ),
            ),
            SizedBox(height: 10.h),
            Text(
              _errorMessage!,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 12.sp,
                color: Colors.grey[700],
              ),
            ),
            SizedBox(height: 16.h),
            TextButton(
              onPressed: _fetchOrderReview,
              child: Text(
                "retry".tr(),
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 14.sp,
                  color: AppColors.buttonBlue,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      padding: EdgeInsets.symmetric(horizontal: 25.w),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(height: 30.h),
          _patientInfoCard(),
          SizedBox(height: 20.h),
          _prescriptionCard(),
          SizedBox(height: 20.h),
          _locationCard(context),
          SizedBox(height: 40.h),
          _acceptDenySection(context),
          SizedBox(height: 40.h),
        ],
      ),
    );
  }

  // =========================================================
  // CARD WRAPPER
  // =========================================================
  Widget _card({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(horizontal: 24.w, vertical: 17.h),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15.r),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1C0E5D7C),
            blurRadius: 11,
            spreadRadius: 1,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: child,
    );
  }

  Widget _title(String t) {
    return Text(
      t,
      style: TextStyle(
        fontFamily: "Poppins",
        fontSize: 18.sp,
        fontWeight: FontWeight.w700,
        color: AppColors.bodyText,
      ),
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: EdgeInsets.only(top: 6.h, bottom: 6.h),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140.w,
            child: Text(
              label,
              style: TextStyle(
                fontFamily: "Poppins",
                fontSize: 13.sp,
                fontWeight: FontWeight.w600,
                color: AppColors.bodyText,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontFamily: "Poppins",
                fontSize: 13.sp,
                fontWeight: FontWeight.w500,
                color: const Color(0xFF525252),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // =========================================================
  // PATIENT INFO CARD
  // =========================================================
  Widget _patientInfoCard() {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _title("patient_information".tr()),
          SizedBox(height: 10.h),
          _row("patient_name_label".tr(), patient["name"] ?? "—"),
          _row("gender_label".tr(), patient["gender"] ?? "—"),
          _row("national_id_label".tr(), patient["nationalId"] ?? "—"),
          _row("date_of_birth_label".tr(), patient["dob"] ?? "—"),
          _row("phone_number_label".tr(), patient["phone"] ?? "—"),
        ],
      ),
    );
  }

  // =========================================================
  // PRESCRIPTION CARD
  // =========================================================
  Widget _prescriptionCard() {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _title("prescription_section".tr()),
          SizedBox(height: 12.h),
          Row(
            children: [
              Container(
                width: 64.w,
                height: 64.h,
                decoration: BoxDecoration(
                  color: const Color(0xFFE4EEF2),
                  borderRadius: BorderRadius.circular(12.r),
                ),
                child: Icon(
                  Icons.medical_services,
                  size: 32.sp,
                  color: AppColors.bodyText,
                ),
              ),
              SizedBox(width: 12.w),
              Expanded(
                child: Text(
                  prescription["medicationName"] ?? "—",
                  style: TextStyle(
                    fontFamily: "Poppins",
                    fontSize: 16.sp,
                    fontWeight: FontWeight.w700,
                    color: AppColors.buttonRed,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: 14.h),
          const Divider(color: Color(0xFFE6E6E6)),
          SizedBox(height: 14.h),
          _row("prescribing_doctor_label".tr(), prescription["doctor"] ?? "—"),
          _row("hospital_label".tr(), prescription["hospital"] ?? "—"),
          _row("instructions_label".tr(), prescription["instructions"] ?? "—"),
          _row("valid_until_label".tr(), prescription["validUntil"] ?? "—"),
          _row("refill_limit_label".tr(), prescription["refillLimit"] ?? "—"),
          _row(
            "prescription_id_label".tr(),
            prescription["prescriptionID"] ?? "—",
          ),
        ],
      ),
    );
  }

  // =========================================================
  // LOCATION CARD (includes delivery & time buttons)
  // =========================================================
  Widget _locationCard(BuildContext context) {
    final deliveryLabel = deliveryType == "delivery"
        ? "delivery_label".tr()
        : "pickup_label".tr();
    final timeLabel = deliveryTime == "morning"
        ? "morning_label".tr()
        : "evening_label".tr();

    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Location header
          Row(
            children: [
              Icon(
                Icons.location_on_outlined,
                size: 22.sp,
                color: AppColors.bodyText,
              ),
              SizedBox(width: 8.w),
              Text(
                location["city"] ?? "—",
                style: TextStyle(
                  fontFamily: "Poppins",
                  fontSize: 16.sp,
                  fontWeight: FontWeight.w700,
                  color: AppColors.bodyText,
                ),
              ),
            ],
          ),

          SizedBox(height: 6.h),

          Padding(
            padding: EdgeInsets.only(left: 25.w, right: 25.w),
            child: Text(
              location["description"] ?? "—",
              style: TextStyle(
                fontFamily: "Poppins",
                fontSize: 14.sp,
                color: AppColors.bodyText,
              ),
            ),
          ),

          SizedBox(height: 16.h),

          // View location button (opens map bottom sheet)
          SizedBox(
            width: double.infinity,
            height: 44.h,
            child: ElevatedButton(
              onPressed: () => _openLocationMap(context),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.buttonBlue,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12.r),
                ),
              ),
              child: Text(
                "view_location".tr(),
                style: TextStyle(
                  fontFamily: "Poppins",
                  fontSize: 14.sp,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
            ),
          ),
          SizedBox(height: 25.h),

          // System recommendation (text under the button)
          Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: "based_on_location_suggested".tr(),
                  style: TextStyle(
                    fontFamily: "Poppins",
                    fontSize: 15.sp,
                    fontWeight: FontWeight.w400,
                    color: AppColors.alertRed,
                  ),
                ),
                TextSpan(
                  text: systemRecommendationLabel,
                  style: TextStyle(
                    fontFamily: "Poppins",
                    fontSize: 15.sp,
                    fontWeight: FontWeight.bold,
                    color: AppColors.alertRed,
                  ),
                ),
                TextSpan(
                  text: " ${"patient_chose".tr()} $deliveryLabel, $timeLabel",
                  style: TextStyle(
                    fontFamily: "Poppins",
                    fontSize: 15.sp,
                    fontWeight: FontWeight.w400,
                    color: AppColors.alertRed,
                  ),
                ),
              ],
            ),
          ),

          SizedBox(height: 20.h),

          // Delivery type (patient selection, read-only)
          Text(
            "preferred_delivery_type_hospital".tr(),
            style: TextStyle(
              fontFamily: "Poppins",
              fontSize: 15.sp,
              fontWeight: FontWeight.w600,
              color: AppColors.bodyText,
            ),
          ),
          SizedBox(height: 12.h),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _choiceButton(
                "delivery_label".tr(),
                deliveryType == "delivery",
                // no onTap → view-only
              ),
              SizedBox(width: 12.w),
              _choiceButton(
                "pickup_label".tr(),
                deliveryType == "pickup",
                // no onTap
              ),
            ],
          ),

          SizedBox(height: 25.h),

          // Delivery time (patient selection, read-only)
          Text(
            "preferred_delivery_time_hospital".tr(),
            style: TextStyle(
              fontFamily: "Poppins",
              fontSize: 15.sp,
              fontWeight: FontWeight.w600,
              color: AppColors.bodyText,
            ),
          ),

          SizedBox(height: 12.h),

          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _choiceButton(
                "morning_label".tr(),
                deliveryTime == "morning",
                // no onTap
              ),
              SizedBox(width: 12.w),
              _choiceButton(
                "evening_label".tr(),
                deliveryTime == "evening",
                // no onTap
              ),
            ],
          ),
        ],
      ),
    );
  }

  // =========================================================
  // CHOICE BUTTON (delivery / pickup / morning / evening)
  // =========================================================
  Widget _choiceButton(String label, bool active, {VoidCallback? onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 120.w,
        height: 40.h,
        decoration: BoxDecoration(
          color: active ? AppColors.buttonRed : const Color(0xFFE6E6E6),
          borderRadius: BorderRadius.circular(12.r),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            fontFamily: "Poppins",
            fontSize: 14.sp,
            fontWeight: FontWeight.w600,
            color: active ? Colors.white : AppColors.bodyText,
          ),
        ),
      ),
    );
  }

  // =========================================================
  // ACCEPT / DENY SECTION (using custom popup)
  // =========================================================
  Widget _acceptDenySection(BuildContext context) {
    final bool isPending = orderStatus == "pending";
    final bool isAccepted =
        orderStatus == "progress" || orderStatus == "completed";
    final bool isRejected = orderStatus == "rejected";

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          "accept_or_deny_question".tr(),
          style: TextStyle(
            fontFamily: "Poppins",
            fontSize: 13.sp,
            fontWeight: FontWeight.w600,
            color: AppColors.bodyText,
          ),
        ),
        SizedBox(height: 16.h),

        if (_isUpdatingStatus)
          Center(
            child: Padding(
              padding: EdgeInsets.only(bottom: 12.h),
              child: const CircularProgressIndicator(strokeWidth: 2),
            ),
          ),

        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // ACCEPT
            GestureDetector(
              onTap: isPending && !_isUpdatingStatus
                  ? () {
                      showCustomPopup(
                        context: context,
                        titleText: "confirm_accept".tr(),
                        subtitleText: "",
                        cancelText: "no".tr(),
                        confirmText: "yes".tr(),
                        onConfirm: () => _updateOrderStatus("progress"),
                      );
                    }
                  : null,
              child: _decisionButton(
                label: "accept".tr(),
                active: isPending || isAccepted,
                color: Colors.green,
              ),
            ),

            SizedBox(width: 14.w),

            // DENY
            GestureDetector(
              onTap: isPending && !_isUpdatingStatus
                  ? () {
                      showCustomPopup(
                        context: context,
                        titleText: "confirm_deny".tr(),
                        subtitleText: "",
                        cancelText: "no".tr(),
                        confirmText: "yes".tr(),
                        onConfirm: () => _updateOrderStatus("rejected"),
                      );
                    }
                  : null,
              child: _decisionButton(
                label: "deny".tr(),
                active: isPending || isRejected,
                color: AppColors.alertRed,
              ),
            ),
          ],
        ),
      ],
    );
  }

  // =========================================================
  // DECISION BUTTON
  // =========================================================
  Widget _decisionButton({
    required String label,
    required bool active,
    required Color color,
  }) {
    return Container(
      width: 120.w,
      height: 40.h,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12.r),
        border: Border.all(color: active ? color : Colors.grey, width: 1.5),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontFamily: "Poppins",
          fontSize: 14.sp,
          fontWeight: FontWeight.w700,
          color: active ? color : Colors.grey,
        ),
      ),
    );
  }
}
