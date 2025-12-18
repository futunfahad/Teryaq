import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'dart:convert';
import 'package:intl/intl.dart';

import 'package:teryagapptry/constants/app_colors.dart';
import 'package:teryagapptry/widgets/custom_top_bar.dart';
import 'package:teryagapptry/widgets/custom_popup.dart';
import 'package:teryagapptry/features/patient/patient_screens/patient_home.dart';
import 'package:teryagapptry/services/patient_service.dart';

String _prettyDate(dynamic raw) {
  if (raw == null) return "—";

  final s = raw.toString().trim();
  if (s.isEmpty || s == "null" || s == "-") return "—";

  // Handles:
  // "2026-01-28 19:29:19.317725"
  // "2026-01-28T19:29:19.317725"
  // "2026-01-28"
  try {
    final normalized = s.contains('T') ? s : s.replaceFirst(' ', 'T');
    DateTime dt = DateTime.parse(normalized);

    // Optional: if your backend timestamps are UTC and you want local:
    // dt = dt.toLocal();

    return DateFormat('dd MMM yyyy').format(dt); // e.g. "28 Jan 2026"
    // If you want time too:
    // return DateFormat('dd MMM yyyy, hh:mm a').format(dt);
  } catch (_) {
    // If backend already sends something like "28 Jan 2026"
    return s;
  }
}

class PatientOrderReview extends StatefulWidget {
  final String prescriptionId;

  const PatientOrderReview({super.key, required this.prescriptionId});

  @override
  State<PatientOrderReview> createState() => _PatientOrderReviewState();
}

class _PatientOrderReviewState extends State<PatientOrderReview> {
  String? _lockedMethod; // "pickup" | "delivery"
  String? _lockedTimeOfDay; // "morning" | "evening"

  bool _isLoading = true;
  String? _errorMessage;

  Map<String, dynamic>? _prescriptionReview;
  Map<String, dynamic>? _locationReview;

  @override
  void initState() {
    super.initState();
    _loadOrderReview();
  }

  // ============================================================
  // LOAD ORDER REVIEW DATA
  // ============================================================
  Future<void> _loadOrderReview() async {
    try {
      final data = await PatientService.fetchOrderReview(
        prescriptionId: widget.prescriptionId,
      );

      final prescription = Map<String, dynamic>.from(
        data["prescription"] ?? {},
      );
      final location = Map<String, dynamic>.from(data["location"] ?? {});
      final ml = data["ml"] as Map<String, dynamic>?;

      final String deliveryType = (ml?["delivery_type"] ?? "delivery")
          .toString()
          .toLowerCase();

      // Suggested choice from ML (still user must confirm)
      location["holdtheseggest"] = deliveryType;

      setState(() {
        _prescriptionReview = prescription;
        _locationReview = location;
        _isLoading = false;
        _errorMessage = null;
        debugPrint("ORDER REVIEW JSON:");
        debugPrint(
          const JsonEncoder.withIndent("  ").convert(_prescriptionReview),
        );
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = e.toString();
      });
    }
  }

  // ============================================================
  // PLACE ORDER
  // ============================================================
  Future<void> _placeOrder() async {
    final p = _prescriptionReview;
    if (p == null) return;

    if (_lockedMethod == null || _lockedTimeOfDay == null) return;

    final String prescriptionId =
        (p["prescription_id"] ?? p["prescriptionId"] ?? "").toString();

    try {
      await PatientService.createOrderFromPrescription(
        prescriptionId: prescriptionId,
        orderType: _lockedMethod!, // pickup/delivery
        timeOfDay: _lockedTimeOfDay!, // morning/evening
      );

      if (!mounted) return;

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const PatientHome(initialIndex: 2)),
      );
    } catch (e) {
      if (!mounted) return;

      showCustomPopup(
        context: context,
        titleText: "Error",
        subtitleText: e.toString(),
        cancelText: "OK",
        confirmText: "Close",
        onConfirm: () {},
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool canPlaceOrder =
        _lockedMethod != null && _lockedTimeOfDay != null;

    return Scaffold(
      backgroundColor: AppColors.appBackground,
      appBar: PreferredSize(
        preferredSize: Size.fromHeight(90.h),
        child: CustomTopBar(
          title: "order_review".tr(),
          showBackButton: true,
          onBackTap: () => Navigator.pop(context),
        ),
      ),
      body: Column(
        children: [
          Expanded(child: _buildBodyContent()),

          // ====================================================
          // BOTTOM BUTTON
          // ====================================================
          Container(
            width: double.infinity,
            padding: EdgeInsets.fromLTRB(25.w, 10.h, 25.w, 60.h),
            decoration: BoxDecoration(
              color: AppColors.cardBackground,
              boxShadow: AppColors.universalShadow,
            ),
            child: SizedBox(
              width: double.infinity,
              height: 40.h,
              child: TextButton(
                onPressed: canPlaceOrder ? _placeOrder : null,
                style: TextButton.styleFrom(
                  backgroundColor: canPlaceOrder
                      ? AppColors.bodyText
                      : AppColors.grayDisabled,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(25.r),
                  ),
                ),
                child: Text(
                  "place_an_order".tr(),
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 14.sp,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // MAIN BODY STATES
  // ============================================================
  Widget _buildBodyContent() {
    if (_isLoading) {
      return Center(
        child: SizedBox(
          width: 30.w,
          height: 30.w,
          child: const CircularProgressIndicator(),
        ),
      );
    }

    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: EdgeInsets.all(24.w),
          child: Text(
            _errorMessage!,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 14.sp,
              fontWeight: FontWeight.w500,
              color: AppColors.buttonRed,
            ),
          ),
        ),
      );
    }

    if (_prescriptionReview == null || _locationReview == null) {
      return Center(
        child: Text(
          "No data available",
          style: TextStyle(
            fontFamily: 'Poppins',
            fontSize: 14.sp,
            fontWeight: FontWeight.w500,
            color: AppColors.detailText,
          ),
        ),
      );
    }

    return SingleChildScrollView(
      physics: const ClampingScrollPhysics(),
      child: Padding(
        padding: EdgeInsets.only(top: 25.h, left: 25.w, right: 25.w),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildPrescriptionCard(),
            SizedBox(height: 18.h),
            _buildLocationCard(), // ✅ contains BOTH (pickup/delivery) + (morning/evening)
            SizedBox(height: 40.h),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // PRESCRIPTION CARD
  // ============================================================
  Widget _buildPrescriptionCard() {
    final p = _prescriptionReview;
    if (p == null) return const SizedBox.shrink();

    final String medName = (p["medicine"] ?? "").toString();
    final String doctor = (p["doctor"] ?? "").toString();
    final String hospital = (p["hospital"] ?? "").toString();
    final String instruction = (p["instruction"] ?? "").toString();
    final String validUntilRaw =
        (p["valid_until"] ??
                p["expiration_date"] ??
                p["validUntil"] ??
                p["expiry_date"] ??
                p["end_date"])
            ?.toString() ??
        "";

    final String validUntil = _prettyDate(validUntilRaw);

    final String refillLimit =
        (p["refill_limit"] ?? p["reorder_threshold"] ?? p["refillLimit"] ?? "—")
            .toString();

    final String prescriptionId =
        (p["prescription_id"] ?? p["prescriptionId"] ?? "").toString().padLeft(
          10,
          '0',
        );

    return Container(
      width: double.infinity,
      margin: EdgeInsets.only(bottom: 12.h),
      padding: EdgeInsets.fromLTRB(15.w, 15.h, 19.w, 7.h),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(12.r),
        boxShadow: AppColors.universalShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "prescription".tr(),
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 18.sp,
              fontWeight: FontWeight.w700,
              color: AppColors.headingText,
            ),
          ),
          SizedBox(height: 12.h),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 55.h,
                height: 55.h,
                decoration: BoxDecoration(
                  color: const Color(0xFFE2F2FF),
                  borderRadius: BorderRadius.circular(10.r),
                ),
                child: Center(
                  child: Icon(
                    Icons.vaccines,
                    size: 30.sp,
                    color: AppColors.cardBlue,
                  ),
                ),
              ),
              SizedBox(width: 10.w),
              Expanded(
                child: Text(
                  medName,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 15.sp,
                    fontWeight: FontWeight.w800,
                    color: AppColors.buttonRed,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: 18.h),
          _infoRow("${"prescribing_doctor".tr()}: ", doctor),
          SizedBox(height: 6.h),
          _infoRow("${"hospital".tr()}: ", hospital),
          SizedBox(height: 6.h),
          _infoRow("${"instruction".tr()}: ", instruction),
          SizedBox(height: 6.h),
          _infoRow("${"valid_until".tr()}: ", validUntil),
          SizedBox(height: 6.h),
          _infoRow("${"refill_limit".tr()}: ", refillLimit),
          SizedBox(height: 6.h),
          _infoRow("${"prescription_id".tr()}: ", prescriptionId),
        ],
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 2,
          child: Text(
            label,
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 12.sp,
              fontWeight: FontWeight.w700,
              color: AppColors.bodyText,
            ),
          ),
        ),
        SizedBox(width: 6.w),
        Expanded(
          flex: 3,
          child: Text(
            value,
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 12.sp,
              fontWeight: FontWeight.w500,
              color: AppColors.detailText,
            ),
          ),
        ),
      ],
    );
  }

  // ============================================================
  // LOCATION CARD (Pickup/Delivery + Morning/Evening) — ONE CARD
  // ============================================================
  Widget _buildLocationCard() {
    final loc = _locationReview;
    if (loc == null) return const SizedBox.shrink();

    final String label = (loc["label"] ?? "").toString();
    final String address = (loc["address"] ?? "").toString();
    final String suggestKey = (loc["holdtheseggest"] ?? "pickup")
        .toString()
        .toLowerCase();

    final bool isPickup = suggestKey == "pickup";
    final String suggestedWord = isPickup ? "Pick Up" : "Delivery";

    return Container(
      width: double.infinity,
      margin: EdgeInsets.only(bottom: 12.h),
      padding: EdgeInsets.fromLTRB(15.w, 15.h, 19.w, 18.h),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(12.r),
        boxShadow: AppColors.universalShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "location_information".tr(),
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 18.sp,
              fontWeight: FontWeight.w700,
              color: AppColors.headingText,
            ),
          ),
          SizedBox(height: 12.h),

          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.location_on_outlined,
                size: 22.sp,
                color: AppColors.bodyText,
              ),
              SizedBox(width: 8.w),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 16.sp,
                        fontWeight: FontWeight.w700,
                        color: AppColors.bodyText,
                      ),
                    ),
                    SizedBox(height: 4.h),
                    Text(
                      address,
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 12.sp,
                        fontWeight: FontWeight.w500,
                        color: AppColors.bodyText,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          SizedBox(height: 16.h),
          Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: "Based on your location we suggest to ",
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 13.sp,
                    fontWeight: FontWeight.w600,
                    color: AppColors.buttonRed,
                  ),
                ),
                TextSpan(
                  text: suggestedWord,
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 12.sp,
                    fontWeight: FontWeight.w800,
                    color: AppColors.buttonRed,
                  ),
                ),
                TextSpan(
                  text: " your medicine.",
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 13.sp,
                    fontWeight: FontWeight.w600,
                    color: AppColors.buttonRed,
                  ),
                ),
              ],
            ),
          ),

          SizedBox(height: 14.h),

          // -------------------------------
          // 1) Pickup / Delivery
          // -------------------------------
          Text(
            "Order method:",
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 13.sp,
              fontWeight: FontWeight.w700,
              color: AppColors.bodyText,
            ),
          ),
          SizedBox(height: 10.h),
          Row(
            children: [
              _methodChoiceButton(keyName: "pickup", label: "Pick Up"),
              SizedBox(width: 12.w),
              _methodChoiceButton(keyName: "delivery", label: "Delivery"),
            ],
          ),

          SizedBox(height: 18.h),

          // -------------------------------
          // 2) Morning / Evening
          // -------------------------------
          Text(
            "Delivery time:",
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 13.sp,
              fontWeight: FontWeight.w700,
              color: AppColors.bodyText,
            ),
          ),
          SizedBox(height: 10.h),
          Row(
            children: [
              _timeChoiceButton(keyName: "morning", label: "Morning"),
              SizedBox(width: 12.w),
              _timeChoiceButton(keyName: "evening", label: "Evening"),
            ],
          ),
        ],
      ),
    );
  }

  // ============================================================
  // BUTTONS (lock after confirm)
  // ============================================================
  Widget _methodChoiceButton({required String keyName, required String label}) {
    final bool locked = _lockedMethod != null;
    final bool isSelected = _lockedMethod == keyName;

    final Color bgColor = (!locked || isSelected)
        ? AppColors.buttonRed
        : AppColors.grayDisabled;

    return Expanded(
      child: SizedBox(
        height: 36.h,
        child: TextButton(
          onPressed: locked ? null : () => _confirmMethod(keyName),
          style: TextButton.styleFrom(
            backgroundColor: bgColor,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(22.r),
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 13.sp,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }

  Widget _timeChoiceButton({required String keyName, required String label}) {
    final bool locked = _lockedTimeOfDay != null;
    final bool isSelected = _lockedTimeOfDay == keyName;

    final Color bgColor = (!locked || isSelected)
        ? AppColors.buttonRed
        : AppColors.grayDisabled;

    return Expanded(
      child: SizedBox(
        height: 36.h,
        child: TextButton(
          onPressed: locked ? null : () => _confirmTimeOfDay(keyName),
          style: TextButton.styleFrom(
            backgroundColor: bgColor,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(22.r),
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 13.sp,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }

  void _confirmMethod(String keyName) {
    showCustomPopup(
      context: context,
      titleText: "Are you sure?",
      subtitleText:
          "You cannot change your choice after confirming this option.",
      cancelText: "Cancel",
      confirmText: "Confirm",
      onConfirm: () => setState(() => _lockedMethod = keyName),
    );
  }

  void _confirmTimeOfDay(String keyName) {
    showCustomPopup(
      context: context,
      titleText: "Are you sure?",
      subtitleText:
          "You cannot change your choice after confirming this option.",
      cancelText: "Cancel",
      confirmText: "Confirm",
      onConfirm: () => setState(() => _lockedTimeOfDay = keyName),
    );
  }
}
