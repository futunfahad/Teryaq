// lib/features/hospital/manage_orders.dart

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:intl/intl.dart'; // ✅ FIX: required for DateFormat

import 'package:teryagapptry/features/hospital/hospital_report.dart';
import 'package:teryagapptry/features/hospital/order_review_screen.dart'
    show OrderReviewScreen;
import '../../constants/app_colors.dart';

// Hospital service + models (aliased as hs for clarity)
import 'package:teryagapptry/services/hospital_service.dart' as hs;

/// ===================================================================
///  🩺 MANAGE ORDERS SCREEN (Hospital)
///  - Lists orders from backend
///  - Supports filter (All / Pending / Rejected / Accepted / On Route / On Delivery / Delivered / Delivery Failed)
///  - Supports search by medication name
///  - Can open:
///      • Order review screen
///      • Order report screen (when allowed)
/// ===================================================================
class ManageOrders extends StatefulWidget {
  const ManageOrders({super.key});

  @override
  State<ManageOrders> createState() => _ManageOrdersState();
}

class _ManageOrdersState extends State<ManageOrders> {
  String selectedFilter = "All";
  String searchQuery = "";

  // -------------------------------------------------
  // Backend-driven state
  // -------------------------------------------------
  List<hs.OrderSummaryModel> _orders = [];
  bool _isLoading = true;
  String? _errorMessage;

  // -------------------------------------------------
  // Status + priority localization
  // -------------------------------------------------
  String translateStatus(String s) {
    switch (s.toLowerCase()) {
      case "pending":
        return "pending".tr();
      case "rejected":
        return "rejected".tr();
      case "accepted":
        return "accepted".tr();
      case "on_delivery":
        return "on_delivery".tr();
      case "on_route":
        return "on_route".tr(); // ✅ added / already supported
      case "delivered":
        return "delivered".tr();
      case "delivery_failed":
        return "delivery_failed".tr();
      default:
        return s;
    }
  }

  String translateLevel(String s) {
    switch (s.toLowerCase()) {
      case "normal":
        return "normal".tr();
      case "high":
        return "high".tr();
      default:
        return s;
    }
  }

  // -------------------------------------------------
  // Lifecycle
  // -------------------------------------------------
  @override
  void initState() {
    super.initState();
    _loadOrders();
  }

  // -------------------------------------------------
  // Helper: map filter chip key -> backend status param
  // -------------------------------------------------
  String _backendStatusFromFilter(String filter) {
    if (filter == "All") return "All";

    switch (filter) {
      case "Pending":
        return "pending";
      case "Rejected":
        return "rejected";
      case "Accepted":
        return "accepted";
      case "On Route":
        return "on_route"; // ✅ ADDED
      case "On Delivery":
        return "on_delivery";
      case "Delivered":
        return "delivered";
      case "Delivery Failed":
        return "delivery_failed";
      default:
        return "All";
    }
  }

  // -------------------------------------------------
  // API: Load orders from backend based on current filter + search
  // -------------------------------------------------
  Future<void> _loadOrders() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final hospitalId = hs.HospitalService.currentHospitalId;
      if (hospitalId == null || hospitalId.isEmpty) {
        throw Exception('Hospital ID is not set. Please login first.');
      }

      final api = hs.HospitalService();

      final status = _backendStatusFromFilter(selectedFilter);
      final String? searchParam =
          searchQuery.trim().isEmpty ? null : searchQuery.trim();

      final orders = await api.getOrders(
        hospitalId: hospitalId,
        status: status,
        search: searchParam,
      );

      setState(() {
        _orders = orders;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = e.toString();
      });
    }
  }

  // -------------------------------------------------
  // Helpers: status / priority / icons / date formatting
  // -------------------------------------------------
  Color _statusColor(String status) {
    switch (status.toLowerCase()) {
      case "pending":
        return const Color(0xFFD1B000);
      case "accepted":
        return const Color(0xFF004A8B);
      case "on_delivery":
      case "on_route":
        return const Color(0xFF004A8B);
      case "delivered":
        return const Color(0xFF137713);
      case "rejected":
      case "delivery_failed":
        return const Color(0xFFCC0000);
      default:
        return Colors.grey;
    }
  }

  Color _priorityColor(String priority) {
    if (priority.toLowerCase() == "high") {
      return const Color(0xFFCC0000);
    }
    return const Color(0xFFFFCC00);
  }

  /// Determines if the "Report" button should open the report screen.
  bool _canOpenReport(hs.OrderSummaryModel order) {
    final s = order.status.toLowerCase();
    final isFinished =
        (s == 'delivered' || s == 'delivery_failed' || s == 'completed');
    return order.canGenerateReport || isFinished;
  }

  Color _reportColor(bool enabled) {
    return enabled ? const Color(0xFF004A8B) : const Color(0xFF8D8D8D);
  }

  String? _statusIcon(String status) {
    switch (status.toLowerCase()) {
      case "on_delivery":
      case "on_route":
        return "assets/icons/on delivery.svg";
      case "delivered":
        return "assets/icons/delivered.svg";
      case "rejected":
      case "delivery_failed":
        return "assets/icons/rejected.svg";
      case "pending":
      case "accepted":
      default:
        return null;
    }
  }

  String _formatPlacedAt(DateTime dt) {
    final locale = context.locale.toString();
    final df = DateFormat('dd MMM yyyy, h:mm a', locale);
    return df.format(dt);
  }

  // -------------------------------------------------
  // UI
  // -------------------------------------------------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,

      // ========================= APP BAR =========================
      appBar: PreferredSize(
        preferredSize: Size.fromHeight(90.h),
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFFD5F7FF),
            borderRadius: BorderRadius.only(
              bottomLeft: Radius.circular(25.r),
              bottomRight: Radius.circular(25.r),
            ),
          ),
          child: SafeArea(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 23.w, vertical: 10.h),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      GestureDetector(
                        onTap: () => Navigator.pop(context),
                        child: const Icon(
                          Icons.arrow_back_ios_new_rounded,
                          color: AppColors.headingText,
                        ),
                      ),
                      Image.asset('assets/tglogo.png', height: 30.h),
                    ],
                  ),
                  Text(
                    "orders".tr(),
                    style: TextStyle(
                      fontSize: 25.sp,
                      fontWeight: FontWeight.w700,
                      color: AppColors.headingText,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),

      // ========================= BODY =========================
      body: RefreshIndicator(
        onRefresh: _loadOrders,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(
            parent: BouncingScrollPhysics(),
          ),
          padding: EdgeInsets.only(top: 30.h, left: 25.w, right: 25.w),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ------------------------- FILTER BAR -------------------------
              SizedBox(
                height: 30.h,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  clipBehavior: Clip.none,
                  child: Row(
                    children: [
                      Padding(
                        padding: EdgeInsets.only(right: 6.w, left: 6.w),
                        child: Text(
                          "filter".tr(),
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 14.sp,
                            fontWeight: FontWeight.w600,
                            color: const Color(0xFF013A3C),
                          ),
                        ),
                      ),

                      _filterChip("all".tr(), "All"),
                      SizedBox(width: 10.w),
                      _filterChip("pending".tr(), "Pending"),
                      SizedBox(width: 10.w),
                      _filterChip("rejected".tr(), "Rejected"),
                      SizedBox(width: 10.w),
                      _filterChip("accepted".tr(), "Accepted"),
                      SizedBox(width: 10.w),

                      // ✅ ADDED: On Route filter
                      _filterChip("on_route".tr(), "On Route"),
                      SizedBox(width: 10.w),

                      _filterChip("on_delivery".tr(), "On Delivery"),
                      SizedBox(width: 10.w),
                      _filterChip("delivered".tr(), "Delivered"),
                      SizedBox(width: 10.w),
                      _filterChip("delivery_failed".tr(), "Delivery Failed"),
                    ],
                  ),
                ),
              ),
              SizedBox(height: 20.h),

              // ------------------------- SEARCH BAR -------------------------
              Container(
                height: 41.h,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20.r),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF0E5D7C).withOpacity(0.18),
                      blurRadius: 14,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        onChanged: (value) {
                          setState(() {
                            searchQuery = value;
                          });
                        },
                        textAlignVertical: TextAlignVertical.center,
                        strutStyle: StrutStyle(fontSize: 16.sp, height: 1.2),
                        style: TextStyle(
                          fontSize: 16.sp,
                          color: AppColors.bodyText,
                        ),
                        decoration: InputDecoration(
                          isDense: true,
                          hintText: "search".tr(),
                          hintStyle: TextStyle(
                            fontSize: 15.sp,
                            color: Colors.grey,
                          ),
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.symmetric(vertical: 8.h),
                          prefixIcon: Icon(
                            Icons.search,
                            size: 22.sp,
                            color: AppColors.bodyText,
                          ),
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.arrow_forward_ios_rounded),
                      iconSize: 18.sp,
                      color: AppColors.bodyText,
                      onPressed: _loadOrders,
                    ),
                  ],
                ),
              ),

              SizedBox(height: 30.h),

              // ------------------------- LOADING / ERROR / DATA -------------------------
              if (_isLoading)
                Center(
                  child: Padding(
                    padding: EdgeInsets.only(top: 40.h),
                    child: const CircularProgressIndicator(),
                  ),
                )
              else if (_errorMessage != null)
                Padding(
                  padding: EdgeInsets.only(top: 40.h),
                  child: Column(
                    children: [
                      Text(
                        'Failed to load orders',
                        style: TextStyle(
                          fontSize: 14.sp,
                          color: Colors.red,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      SizedBox(height: 8.h),
                      Text(
                        _errorMessage!,
                        style: TextStyle(
                          fontSize: 12.sp,
                          color: Colors.grey[700],
                        ),
                        textAlign: TextAlign.center,
                      ),
                      SizedBox(height: 16.h),
                      TextButton(
                        onPressed: _loadOrders,
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                )
              else if (_orders.isEmpty)
                Padding(
                  padding: EdgeInsets.only(top: 40.h),
                  child: Center(
                    child: Text(
                      'no_orders_found'.tr(),
                      style: TextStyle(
                        fontSize: 14.sp,
                        color: Colors.grey[700],
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                )
              else
                Column(
                  children: _orders.map<Widget>((order) {
                    return Padding(
                      padding: EdgeInsets.only(bottom: 12.h),
                      child: Center(child: _buildOrderCard(order)),
                    );
                  }).toList(),
                ),
            ],
          ),
        ),
      ),
    );
  }

  // =================================================
  // FILTER CHIP WIDGET
  // =================================================
  Widget _filterChip(String label, String key) {
    final bool isSelected = selectedFilter == key;

    return GestureDetector(
      onTap: () {
        setState(() {
          selectedFilter = key;
        });
        _loadOrders();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 6.h),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.buttonBlue : Colors.white,
          borderRadius: BorderRadius.circular(14.r),
          boxShadow: AppColors.universalShadow,
        ),
        child: Text(
          label,
          style: TextStyle(
            fontFamily: 'Poppins',
            fontSize: 13.sp,
            fontWeight: FontWeight.w600,
            color: isSelected ? Colors.white : AppColors.headingText,
          ),
        ),
      ),
    );
  }

  // =================================================
  // SINGLE ORDER CARD
  // =================================================
  Widget _buildOrderCard(hs.OrderSummaryModel order) {
    final statusColor = _statusColor(order.status);
    final levelColor = _priorityColor(order.priorityLevel);
    final bool canOpenReport = _canOpenReport(order);
    final reportColor = _reportColor(canOpenReport);
    final iconPath = _statusIcon(order.status);

    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(15.w, 12.h, 15.w, 14.h),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16.r),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0E5D7C).withOpacity(0.11),
            blurRadius: 11,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ========== HEADER ROW ==========
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Left: status icon
              Container(
                width: 51.w,
                height: 52.h,
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(12.r),
                ),
                child: Center(
                  child: iconPath != null && iconPath.isNotEmpty
                      ? SvgPicture.asset(
                          iconPath,
                          width: 26.w,
                          height: 30.h,
                          color: statusColor,
                        )
                      : Icon(
                          Icons.access_time,
                          color: statusColor,
                          size: 28.sp,
                        ),
                ),
              ),
              SizedBox(width: 10.w),

              // Middle: status + priority + order code
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 150.w,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Flexible(
                          child: Text(
                            translateStatus(order.status),
                            style: TextStyle(
                              fontSize: 15.sp,
                              fontWeight: FontWeight.w800,
                              color: statusColor,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        SizedBox(width: 10.w),
                        Text(
                          translateLevel(order.priorityLevel),
                          style: TextStyle(
                            fontSize: 13.sp,
                            fontWeight: FontWeight.w600,
                            color: levelColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: 4.h),
                  Text(
                    "#${order.code}",
                    style: TextStyle(
                      fontSize: 10.sp,
                      color: AppColors.bodyText,
                    ),
                  ),
                ],
              ),

              const Spacer(),

              // Right: View + Report actions
              Column(
                children: [
                  // View button
                  GestureDetector(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              OrderReviewScreen(orderId: order.orderId),
                        ),
                      );
                    },
                    child: _actionButton(
                      "view".tr(),
                      borderColor: const Color(0xFF137713),
                      textColor: const Color(0xFF137713),
                    ),
                  ),
                  SizedBox(height: 6.h),

                  // Report button
                  GestureDetector(
                    onTap: canOpenReport
                        ? () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => HospitalReportScreen(
                                  orderId: order.orderId,
                                ),
                              ),
                            );
                          }
                        : null,
                    child: Opacity(
                      opacity: canOpenReport ? 1.0 : 0.5,
                      child: _actionButton(
                        "report".tr(),
                        borderColor: reportColor,
                        textColor: reportColor,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),

          SizedBox(height: 9.h),

          // Medication name
          Text(
            order.medicineName,
            style: TextStyle(
              fontSize: 14.sp,
              fontWeight: FontWeight.w600,
              color: AppColors.buttonRed,
            ),
          ),

          SizedBox(height: 6.h),

          // Patient + placed_at rows
          _infoRow("patient_name".tr(), order.patientName),
          SizedBox(height: 3.h),
          _infoRow("placed_at".tr(), _formatPlacedAt(order.placedAt)),
        ],
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: EdgeInsets.only(left: 15.w),
      child: Row(
        children: [
          SizedBox(
            width: 110.w,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12.sp,
                fontWeight: FontWeight.w700,
                color: AppColors.bodyText,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 12.sp,
                fontWeight: FontWeight.w500,
                color: const Color(0xFF4B4B4B),
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  // =================================================
  // ✅ ACTION BUTTON (FIXED + COMPLETED)
  // =================================================
  Widget _actionButton(
    String text, {
    required Color borderColor,
    required Color textColor,
  }) {
    return Container(
      width: 61.w,
      height: 24.h,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8.r),
        border: Border.all(color: borderColor, width: 1.3),
      ),
      child: Center(
        child: Text(
          text,
          style: TextStyle(
            fontSize: 10.sp,
            fontWeight: FontWeight.w500,
            color: textColor,
          ),
        ),
      ),
    );
  }
}
