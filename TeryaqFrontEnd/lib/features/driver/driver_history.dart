// 📦 Required packages
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:easy_localization/easy_localization.dart';

import 'package:teryagapptry/constants/app_colors.dart';
import 'package:teryagapptry/widgets/custom_top_bar.dart';
import 'package:teryagapptry/widgets/custom_bottom_nav_driver.dart';
import 'package:teryagapptry/widgets/show_teryaq_menu.dart';

import 'package:teryagapptry/features/driver/driver_home.dart';
import 'package:teryagapptry/services/driver_service.dart';

class DriverHistory extends StatefulWidget {
  const DriverHistory({super.key});

  @override
  State<DriverHistory> createState() => _DriverHistoryState();
}

class _DriverHistoryState extends State<DriverHistory> {
  bool loading = true;
  List<Map<String, dynamic>> historyData = [];

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  /// ===========================================================
  /// LOAD HISTORY
  /// ===========================================================
  Future<void> _loadHistory() async {
    setState(() => loading = true);

    try {
      final raw = await DriverService.getOrdersHistory();
      debugPrint("DriverHistory → raw = $raw");

      List list = [];
      list = raw;

      setState(() {
        historyData = list
            .whereType<Map>()
            .map<Map<String, dynamic>>(
              (e) => Map<String, dynamic>.from(e as Map),
            )
            .toList();
        loading = false;
      });
    } catch (e) {
      debugPrint("Error loading history: $e");
      setState(() {
        historyData = [];
        loading = false;
      });
    }
  }

  /// ===========================================================
  /// UI
  /// ===========================================================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: CustomTopBar(
        title: tr("order_history"),
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
        currentIndex: 2,
        onTap: (_) {},
      ),

      body: loading
          ? const Center(child: CircularProgressIndicator())
          : historyData.isEmpty
          ? Center(
              child: Text(
                tr("no_orders_history"),
                style: TextStyle(
                  fontSize: 16.sp,
                  fontWeight: FontWeight.w600,
                  color: AppColors.bodyText,
                ),
              ),
            )
          : ListView.builder(
              padding: EdgeInsets.all(20.w),
              itemCount: historyData.length,
              itemBuilder: (context, index) {
                final packet = historyData[index];

                // 1) { order: {...}, patient: {...}, hospital: {...} }
                // 2) { order_id, status, patient_name, hospital_name, ... }
                Map<String, dynamic> order;
                Map<String, dynamic> patient = {};
                Map<String, dynamic> hospital = {};

                if (packet["order"] is Map) {
                  order = Map<String, dynamic>.from(packet["order"]);
                  if (packet["patient"] is Map) {
                    patient = Map<String, dynamic>.from(packet["patient"]);
                  }
                  if (packet["hospital"] is Map) {
                    hospital = Map<String, dynamic>.from(packet["hospital"]);
                  }
                } else {
                  order = Map<String, dynamic>.from(packet);
                  patient = {
                    "name": packet["patient_name"],
                    "phone_number": packet["patient_phone"],
                  };
                  hospital = {
                    "name": packet["hospital_name"],
                    "phone_number": packet["hospital_phone"],
                  };
                }

                final bool delivered =
                    (order["status"] ?? "").toString().toLowerCase() ==
                    "delivered";

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    /// Title row (Order #)
                    Row(
                      children: [
                        Icon(
                          Icons.local_shipping,
                          color: AppColors.buttonRed,
                          size: 34.sp,
                        ),
                        SizedBox(width: 8.w),
                        Text(
                          "${tr("order")} ${index + 1}",
                          style: TextStyle(
                            fontSize: 25.sp,
                            fontWeight: FontWeight.w600,
                            color: AppColors.buttonRed,
                          ),
                        ),
                      ],
                    ),

                    SizedBox(height: 12.h),

                    _buildDeliveryCard(order, delivered),
                    SizedBox(height: 12.h),

                    _buildPatientCard(patient, hospital),
                    SizedBox(height: 24.h),
                  ],
                );
              },
            ),
    );
  }

  String _formatDate(dynamic value) {
    if (value == null) return "-";

    try {
      final dt = DateTime.parse(value.toString());
      return "${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}";
    } catch (_) {
      return value.toString().split(" ").first; // fallback
    }
  }

  /// ===========================================================
  /// 🔵 Delivery Card UI
  /// ===========================================================
  Widget _buildDeliveryCard(Map<String, dynamic> order, bool delivered) {
    final color = delivered
        ? AppColors.statusDelivered
        : AppColors.statusRejected;
    final light = delivered
        ? AppColors.statusDeliveredLight
        : AppColors.statusRejectedLight;
    final icon = delivered ? Icons.check_circle : Icons.cancel;

    return Container(
      width: double.infinity, // ⬅ FULL WIDTH
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
      child: Row(
        children: [
          // STATUS ICON
          Container(
            width: 56.w,
            height: 56.h,
            decoration: BoxDecoration(
              color: light,
              borderRadius: BorderRadius.circular(12.r),
            ),
            child: Icon(icon, color: color, size: 30.sp),
          ),
          SizedBox(width: 12.w),

          // TEXT DETAILS
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // STATUS LABEL
                Text(
                  delivered ? tr("delivered") : tr("failed"),
                  style: TextStyle(
                    fontSize: 17.sp,
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
                SizedBox(height: 2.h),

                // ORDER ID — prevent overflow
                Text(
                  (order["order_id"] ?? "").toString(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10.sp,
                    color: AppColors.bodyText,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                SizedBox(height: 12.h),

                // PLACED & DELIVERED ROW
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Labels
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          tr("placed_at"),
                          style: TextStyle(
                            color: AppColors.bodyText,
                            fontSize: 12.sp,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        SizedBox(height: 3.h),
                        Text(
                          tr("delivered_at"),
                          style: TextStyle(
                            color: AppColors.bodyText,
                            fontSize: 12.sp,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),

                    // Values — prevent overflow
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        SizedBox(
                          width: 140.w,
                          child: Text(
                            _formatDate(order["created_at"]),
                            maxLines: 2,
                            overflow: TextOverflow.visible,
                            softWrap: true,
                            style: TextStyle(fontSize: 12.sp),
                          ),
                        ),

                        SizedBox(height: 3.h),
                        SizedBox(
                          width: 140.w, // gives room for 2-line wrap
                          child: Text(
                            _formatDate(order["delivered_at"]),
                            maxLines: 2, // ⬅ allow wrapping
                            overflow: TextOverflow.visible,
                            softWrap: true, // ⬅ ensure wrapping
                            style: TextStyle(fontSize: 12.sp),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// ===========================================================
  /// 🔵 Patient + Hospital Card
  /// ===========================================================
  Widget _buildPatientCard(
    Map<String, dynamic> patient,
    Map<String, dynamic> hospital,
  ) {
    final String patientName = (patient["name"] ?? "Unknown Patient")
        .toString();
    final String patientPhone = (patient["phone_number"] ?? "N/A").toString();
    final String hospitalName = (hospital["name"] ?? "").toString();
    final String hospitalPhone = (hospital["phone_number"] ?? "").toString();

    return Container(
      width: double.infinity,

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
            tr("patient"),
            style: TextStyle(
              fontSize: 18.sp,
              fontWeight: FontWeight.w600,
              color: AppColors.bodyText,
            ),
          ),
          SizedBox(height: 12.h),

          _row(tr("patient"), patientName),
          _row(tr("phone_number_p"), patientPhone),
          _row(tr("hospital"), hospitalName),
          _row(tr("phone_number_h"), hospitalPhone),
        ],
      ),
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: EdgeInsets.only(left: 8.w, bottom: 8.h),
      child: Row(
        children: [
          Text(
            "$label: ",
            style: TextStyle(
              fontSize: 14.sp,
              fontWeight: FontWeight.w500,
              color: AppColors.bodyText,
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 14.sp,
                fontWeight: FontWeight.w500,
                color: AppColors.detailText,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
