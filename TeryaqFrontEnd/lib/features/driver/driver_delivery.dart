// 📂 lib/features/driver/driver_delivery.dart

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:teryagapptry/constants/app_colors.dart';
import 'package:teryagapptry/widgets/custom_top_bar.dart';
import 'package:teryagapptry/widgets/custom_bottom_nav_driver.dart';
import 'package:teryagapptry/widgets/show_teryaq_menu.dart';
import 'package:teryagapptry/widgets/report_issue_dialog.dart';
import 'package:teryagapptry/widgets/custom_popup.dart';

import 'package:teryagapptry/services/driver_service.dart';
import 'package:teryagapptry/features/driver/driver_otp.dart';
import 'package:teryagapptry/features/driver/driver_dashboard.dart';
import 'package:teryagapptry/features/driver/driver_home.dart';

/// ===============================================================
///  🔴 DRIVER DELIVERY SCREEN
/// ===============================================================

class DriverDelivery extends StatefulWidget {
  final String orderId;

  /// Full HGS sequence for today (optional)
  final List<String> orderSequence;

  /// Index of this order inside the sequence (optional)
  final int currentIndex;

  const DriverDelivery({
    super.key,
    required this.orderId,
    this.orderSequence = const [],
    this.currentIndex = 0,
  });

  @override
  State<DriverDelivery> createState() => _DriverDeliveryState();
}

class _DriverDeliveryState extends State<DriverDelivery> {
  bool loading = true;
  Map<String, dynamic>? orderData;
  bool hasDashboard = false;

  // ===============================================================
  //                🔹 FORMAT MINUTES → "3h 40m"
  // ===============================================================
  String _formatMinutes(int minutes) {
    if (minutes <= 0) return "0m";
    final h = minutes ~/ 60;
    final m = minutes % 60;

    if (h > 0 && m > 0) return "${h}h ${m}m";
    if (h > 0) return "${h}h";
    return "${m}m";
  }

  // ===============================================================
  //     🔹 LOAD LOCAL ETA + STABILITY FROM SHARED PREFERENCES
  //     (same keys as Home: "order_times_<order_id>")
  // ===============================================================
  Future<Map<String, int>> _getLocalOrderTimes(String orderId) async {
    final prefs = await SharedPreferences.getInstance();
    final key = "order_times_$orderId";
    final jsonString = prefs.getString(key);
    if (jsonString == null) return {};

    try {
      final data = jsonDecode(jsonString);
      int? eta;
      int? exc;

      if (data is Map) {
        final etaRaw = data["eta_minutes"];
        if (etaRaw is int) {
          eta = etaRaw;
        } else if (etaRaw is String) {
          eta = int.tryParse(etaRaw);
        }

        final excRaw = data["max_excursion_minutes"];
        if (excRaw is int) {
          exc = excRaw;
        } else if (excRaw is String) {
          exc = int.tryParse(excRaw);
        }
      }

      final Map<String, int> result = {};
      if (eta != null) result["eta_minutes"] = eta;
      if (exc != null) result["max_excursion_minutes"] = exc;
      return result;
    } catch (_) {
      return {};
    }
  }

  // ===============================================================
  //                   🔴 REPORT ISSUE HANDLER
  // ===============================================================
  Future<void> _onReportIssue(String orderId) async {
    // Make sure showReportIssueDialog returns Future<String?>
    final String? reason = await showReportIssueDialog(context);

    if (reason == null || reason.isEmpty) {
      // user cancelled
      return;
    }

    try {
      final ok = await DriverService.rejectOrder(
        orderId: orderId,
        reason: reason,
      );

      if (!mounted) return;

      if (ok) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("order_marked_rejected".tr()),
            backgroundColor: AppColors.alertRed,
          ),
        );

        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const DriverHome()),
          (route) => false,
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("failed_to_reject_order".tr()),
            backgroundColor: AppColors.alertRed,
          ),
        );
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("failed_to_reject_order".tr()),
          backgroundColor: AppColors.alertRed,
        ),
      );
    }
  }

  @override
  void initState() {
    super.initState();
    _loadOrderDetails();
  }

  /// =============================================
  /// Load order details from API + merge local ETA
  /// GET /driver/order/{order_id}
  /// =============================================
  Future<void> _loadOrderDetails() async {
    try {
      final resp = await DriverService.getOrderDetails(widget.orderId);
      debugPrint("DriverDelivery: raw resp = $resp");

      final respMap = Map<String, dynamic>.from(resp as Map);

      final rawOrder = respMap["order"];
      final rawPatient = respMap["patient"];
      final rawHospital = respMap["hospital"];

      if (rawOrder == null || rawOrder is! Map) {
        throw Exception("order field missing in response");
      }

      final order = Map<String, dynamic>.from(rawOrder);

      final Map<String, dynamic>? patient = rawPatient is Map
          ? Map<String, dynamic>.from(rawPatient)
          : null;

      final Map<String, dynamic>? hospital = rawHospital is Map
          ? Map<String, dynamic>.from(rawHospital)
          : null;

      // Flatten as before
      final flattened = <String, dynamic>{
        //  order
        "order_id": order["order_id"],
        "driver_id": order["driver_id"],
        "patient_id": order["patient_id"],
        "hospital_id": order["hospital_id"],
        "dashboard_id": order["dashboard_id"],
        "status": order["status"],
        "description": order["description"],
        "priority_level": order["priority_level"],
        "order_type": order["order_type"],
        "created_at": order["created_at"],
        "delivered_at": order["delivered_at"],
        "OTP": order["OTP"],

        //  patient
        "patient_name": patient?["name"],
        "patient_phone": patient?["phone_number"],
        "patient_address": patient?["address"],

        //  hospital
        "hospital_name": hospital?["name"],
        "hospital_phone": hospital?["phone_number"],
        "hospital_address": hospital?["address"],

        // Old string fields if backend sends them
        "arrival_time": order["arrival_time"],
        "remaining_stability": order["remaining_stability"],

        "is_medication_bad": order["is_medication_bad"],
        "progress": order["progress"],

        // Optional numeric ETA if backend already sends it
        "eta_minutes": order["eta_minutes"],
        "max_excursion_minutes": order["max_excursion_minutes"],
      };

      final orderIdStr = (flattened["order_id"] ?? widget.orderId).toString();

      // 🔥 Merge in local ETA + stability from SharedPreferences (from Home)
      final localTimes = await _getLocalOrderTimes(orderIdStr);
      if (localTimes["eta_minutes"] != null) {
        flattened["eta_minutes"] = localTimes["eta_minutes"];
      }
      if (localTimes["max_excursion_minutes"] != null) {
        flattened["max_excursion_minutes"] =
            localTimes["max_excursion_minutes"];
      }

      debugPrint("DriverDelivery: flattened+local = $flattened");

      if (!mounted) return;
      setState(() {
        orderData = flattened;
        hasDashboard = flattened["dashboard_id"] != null;
        loading = false;
      });
    } catch (e) {
      debugPrint("Error loading order: $e");
      if (!mounted) return;
      setState(() {
        loading = false;
        orderData = null;
        hasDashboard = false;
      });
    }
  }

  // ===============================================================
  //                       🔵 BUILD
  // ===============================================================
  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (orderData == null) {
      return Scaffold(
        backgroundColor: AppColors.appBackground,
        appBar: CustomTopBar(
          title: tr("delivery"),
          showBackButton: true,
          onBackTap: () {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (_) => const DriverHome()),
            );
          },
          onMenuTap: () => showTeryaqMenu(context),
        ),
        bottomNavigationBar: CustomBottomNavDriver(
          currentIndex: 0,
          onTap: (index) {},
        ),
        body: Center(
          child: Text(
            "failed_to_load_order".tr(),
            style: TextStyle(color: AppColors.alertRed, fontSize: 14.sp),
          ),
        ),
      );
    }

    final bool isMedicationBad =
        (orderData!["is_medication_bad"] ?? false) == true;

    return Scaffold(
      backgroundColor: AppColors.appBackground,
      appBar: CustomTopBar(
        title: tr("delivery"),
        showBackButton: true,
        onBackTap: () {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const DriverHome()),
          );
        },
        onMenuTap: () => showTeryaqMenu(context),
      ),
      bottomNavigationBar: CustomBottomNavDriver(
        currentIndex: 0,
        onTap: (index) {
          // handle driver bottom nav if needed
        },
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.symmetric(horizontal: 25.w, vertical: 20.h),
        child: _buildLoadedScreen(isMedicationBad),
      ),
    );
  }

  // ===============================================================
  //                       🔵 MAIN UI
  // ===============================================================
  Widget _buildLoadedScreen(bool isMedicationBad) {
    final orderIdText = (orderData!["order_id"] ?? widget.orderId).toString();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Icon(
              Icons.local_shipping_rounded,
              size: 34.w,
              color: AppColors.buttonRed,
            ),
            SizedBox(width: 8.w),
            Text(
              "order".tr(),
              style: TextStyle(
                fontSize: 25.sp,
                fontWeight: FontWeight.w700,
                color: AppColors.buttonRed,
              ),
            ),
            SizedBox(width: 8.w),
            Flexible(
              child: Text(
                orderIdText,
                style: TextStyle(
                  fontSize: 25.sp,
                  fontWeight: FontWeight.w700,
                  color: AppColors.buttonRed,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),

        SizedBox(height: 20.h),

        _buildDeliveryCard(isMedicationBad),
        SizedBox(height: 16.h),

        _buildPatientCard(isMedicationBad),
        SizedBox(height: 20.h),

        _buildActionButtons(isMedicationBad, orderIdText),

        if (isMedicationBad) ...[SizedBox(height: 20.h), _buildWarningBanner()],
      ],
    );
  }

  // ===============================================================
  //                       🔵 DELIVERY CARD
  // ===============================================================
  Widget _buildDeliveryCard(bool isMedicationBad) {
    final orderId = (orderData!["order_id"] ?? widget.orderId).toString();
    final String? status = orderData?["status"]?.toString().toLowerCase();
    final bool isOnRoute = status == "on_route";

    // 🔹 DATE: ALWAYS TODAY, ONLY DATE
    final now = DateTime.now();
    final deliveryDate =
        "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}";

    // 🔹 ETA: like homepage — from eta_minutes or fallback to arrival_time string
    String etaText;
    final dynamic etaRaw = orderData!["eta_minutes"];

    if (etaRaw is int) {
      etaText = _formatMinutes(etaRaw);
    } else if (etaRaw is String && int.tryParse(etaRaw) != null) {
      etaText = _formatMinutes(int.parse(etaRaw));
    } else {
      etaText = (orderData!["arrival_time"] ?? "-").toString();
    }

    // progress bar
    final progress = (orderData!["progress"] ?? 0.3);
    final double progressValue = progress is num ? progress.toDouble() : 0.3;

    final bool localHasDashboard = hasDashboard;

    return Stack(
      children: [
        Container(
          width: 322.w,
          height: 207.h,
          padding: EdgeInsets.all(12.w),
          decoration: BoxDecoration(
            color: AppColors.backgroundGrey,
            borderRadius: BorderRadius.circular(16.r),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 6,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // HEADER ROW
              Row(
                children: [
                  Container(
                    width: 56.w,
                    height: 56.h,
                    decoration: BoxDecoration(
                      color: AppColors.cardBlueLight,
                      borderRadius: BorderRadius.circular(12.r),
                    ),
                    child: Icon(
                      Icons.directions_car_filled_outlined,
                      color: AppColors.buttonBlue,
                      size: 30.sp,
                    ),
                  ),
                  SizedBox(width: 12.w),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "on_delivery".tr(),
                        style: TextStyle(
                          fontSize: 17.sp,
                          fontWeight: FontWeight.w600,
                          color: AppColors.headingText,
                        ),
                      ),
                      SizedBox(height: 2.h),
                      SizedBox(
                        width: 180.w,
                        child: Text(
                          orderId,
                          style: TextStyle(
                            fontSize: 11.sp,
                            fontWeight: FontWeight.w500,
                            color: AppColors.bodyText,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
              ),

              SizedBox(height: 10.h),

              // 🔹 Progress
              LinearProgressIndicator(
                value: progressValue,
                backgroundColor: Colors.grey[300],
                valueColor: AlwaysStoppedAnimation(AppColors.buttonRed),
              ),

              SizedBox(height: 10.h),

              Text(
                "estimated_delivery_time".tr(),
                style: TextStyle(
                  fontSize: 13.sp,
                  fontWeight: FontWeight.w600,
                  color: AppColors.bodyText,
                ),
              ),

              SizedBox(height: 4.h),

              // 🔹 DATE (left) + ETA (right)
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 25.w, vertical: 5.h),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // DATE ONLY
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.calendar_today_outlined,
                          size: 14.sp,
                          color: AppColors.bodyText,
                        ),
                        SizedBox(width: 4.w),
                        SizedBox(
                          width: 100.w,
                          child: Text(
                            deliveryDate,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            softWrap: false,
                            style: TextStyle(fontSize: 12.sp),
                          ),
                        ),
                      ],
                    ),

                    SizedBox(width: 15.w),

                    // ETA NEXT TO CLOCK
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.access_time,
                          size: 14.sp,
                          color: AppColors.bodyText,
                        ),
                        SizedBox(width: 4.w),
                        SizedBox(
                          width: 90.w,
                          child: Text(
                            etaText.isEmpty ? "-" : etaText,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            softWrap: false,
                            style: TextStyle(fontSize: 12.sp),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const Spacer(),

              Align(
                alignment: Alignment.bottomRight,
                child: GestureDetector(
                  onTap: (!localHasDashboard || !isOnRoute)
                      ? null
                      : () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => DriverDashboardScreen(
                                initialOrderId: orderId,
                              ),
                            ),
                          );
                        },
                  child: Opacity(
                    opacity: (!localHasDashboard || !isOnRoute) ? 0.55 : 1.0,
                    child: Container(
                      width: 64.w,
                      height: 32.h,
                      decoration: BoxDecoration(
                        color: (!localHasDashboard || !isOnRoute)
                            ? Colors.grey
                            : AppColors.buttonRed,
                        borderRadius: BorderRadius.circular(9.r),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        "view".tr(),
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 12.sp,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),

        if (isMedicationBad)
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                color: Colors.grey.withOpacity(0.4),
                borderRadius: BorderRadius.circular(16.r),
              ),
            ),
          ),
      ],
    );
  }

  // ===============================================================
  //                       🔵 PATIENT CARD
  // ===============================================================
  Widget _buildPatientCard(bool isMedicationBad) {
    final patientName = (orderData!["patient_name"] ?? "").toString();
    final patientPhone = (orderData!["patient_phone"] ?? "").toString();

    return Stack(
      children: [
        Container(
          width: 322.w,
          padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 14.h),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16.r),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 6,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "patient".tr(),
                style: TextStyle(
                  fontSize: 18.sp,
                  fontWeight: FontWeight.w600,
                  color: AppColors.bodyText,
                ),
              ),
              SizedBox(height: 12.h),

              Row(
                children: [
                  Text(
                    "patient_name".tr(),
                    style: TextStyle(
                      fontSize: 14.sp,
                      fontWeight: FontWeight.w500,
                      color: AppColors.bodyText,
                    ),
                  ),
                  SizedBox(width: 8.w),
                  Expanded(
                    child: Text(
                      patientName.isEmpty ? "-" : patientName,
                      style: TextStyle(
                        fontSize: 14.sp,
                        color: AppColors.detailText,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),

              SizedBox(height: 8.h),

              Row(
                children: [
                  Text(
                    "phone_number".tr(),
                    style: TextStyle(
                      fontSize: 14.sp,
                      fontWeight: FontWeight.w500,
                      color: AppColors.bodyText,
                    ),
                  ),
                  SizedBox(width: 8.w),
                  Expanded(
                    child: Text(
                      patientPhone.isEmpty ? "-" : patientPhone,
                      style: TextStyle(
                        fontSize: 14.sp,
                        color: AppColors.detailText,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),

        if (isMedicationBad)
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                color: Colors.grey.withOpacity(0.4),
                borderRadius: BorderRadius.circular(16.r),
              ),
            ),
          ),
      ],
    );
  }

  // ===============================================================
  //                       🔵 ACTION BUTTONS
  // ===============================================================
  Widget _buildActionButtons(bool isMedicationBad, String orderId) {
    final String? status = orderData?["status"]?.toString().toLowerCase();
    final bool isOnRoute = status == "on_route";

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        // 🔴 Report issue
        ElevatedButton(
          onPressed: isMedicationBad ? null : () => _onReportIssue(orderId),
          style: ElevatedButton.styleFrom(
            backgroundColor: isMedicationBad
                ? Colors.grey
                : AppColors.buttonRed,
            padding: EdgeInsets.symmetric(horizontal: 18.w, vertical: 10.h),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12.r),
            ),
          ),
          child: Text(
            "report_issue".tr(),
            style: const TextStyle(color: Colors.white),
          ),
        ),

        // 🔵 Mark delivered → OTP
        // 🔵 Mark delivered → OTP (only when ON_ROUTE)
        ElevatedButton(
          onPressed: (!isOnRoute || isMedicationBad)
              ? null // disable button
              : () => showCustomPopup(
                  context: context,
                  titleText: 'complete_delivery'.tr(),
                  subtitleText: 'complete_delivery_subtitle'.tr(),
                  cancelText: 'no_not_sure'.tr(),
                  confirmText: 'yes_sure'.tr(),
                  onCancel: () {},
                  onConfirm: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => OTP(orderId: orderId)),
                  ),
                ),
          style: ElevatedButton.styleFrom(
            backgroundColor: (!isOnRoute || isMedicationBad)
                ? Colors
                      .grey // inactive
                : AppColors.buttonBlue, // active
            padding: EdgeInsets.symmetric(horizontal: 18.w, vertical: 10.h),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12.r),
            ),
          ),
          child: Text(
            "mark_delivered".tr(),
            style: const TextStyle(color: Colors.white),
          ),
        ),
      ],
    );
  }

  // ===============================================================
  //                    🔵 MEDICATION BAD WARNING
  // ===============================================================
  Widget _buildWarningBanner() {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(12.w),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: AppColors.alertRed, width: 1.5),
        borderRadius: BorderRadius.circular(12.r),
      ),
      child: Row(
        children: [
          Icon(
            Icons.sentiment_very_dissatisfied,
            color: AppColors.alertRed,
            size: 24.sp,
          ),
          SizedBox(width: 12.w),
          Expanded(
            child: Text(
              "medication_bad_warning".tr(),
              style: TextStyle(
                fontSize: 13.sp,
                fontWeight: FontWeight.w600,
                color: AppColors.alertRed,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
