// lib/features/patient/patient_screens/patient_orders.dart

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:intl/intl.dart';

import 'package:teryagapptry/constants/app_colors.dart';
import 'package:teryagapptry/widgets/custom_top_bar.dart';
import 'package:teryagapptry/widgets/show_teryaq_menu.dart';
import 'package:teryagapptry/widgets/custom_popup.dart';

import 'package:teryagapptry/features/patient/patient_screens/patient_report.dart';
import 'package:teryagapptry/features/patient/patient_screens/patient_track.dart';

import 'package:teryagapptry/services/patient_service.dart';

class PatientOrders extends StatefulWidget {
  const PatientOrders({super.key});

  @override
  State<PatientOrders> createState() => _PatientOrdersState();
}

class _PatientOrdersState extends State<PatientOrders> {
  String selectedFilter = "All"; // "Active" | "Completed" | "All"
  String searchQuery = "";

  // Normalized orders for UI
  List<Map<String, String>> _orders = [];

  bool _isLoading = false;
  String? _errorMessage;

  // Prevent double-cancel taps
  String? _cancelingOrderId;

  @override
  void initState() {
    super.initState();
    _loadOrders();
  }

  // ------------------------------------------------------------
  // Helpers
  // ------------------------------------------------------------
  String _safeStr(dynamic v) => v == null ? "" : v.toString();

  String _truncateCode(String code, {int keep = 10}) {
    if (code.isEmpty) return "";
    if (code.length <= keep) return code;
    return code.substring(0, keep);
  }

  String _translateStatus(String s) {
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
        return "on_route".tr();
      case "delivered":
        return "delivered".tr();
      case "delivery_failed":
        return "delivery_failed".tr();
      default:
        return s;
    }
  }

  String _translateLevel(String s) {
    switch (s.toLowerCase()) {
      case "normal":
        return "normal".tr();
      case "high":
        return "high".tr();
      default:
        return s;
    }
  }

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
    if (priority.toLowerCase() == "high") return const Color(0xFFCC0000);
    return const Color(0xFFFFCC00);
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
      default:
        return null;
    }
  }

  String _formatDateForUi(DateTime dt) {
    final localeTag = context.locale.toLanguageTag();
    final df = DateFormat.yMMMEd(localeTag).add_jm();
    return df.format(dt);
  }

  DateTime? _parseBackendDate(String raw) {
    final s = raw.trim();
    if (s.isEmpty) return null;

    // ISO
    try {
      return DateTime.parse(s);
    } catch (_) {}

    // English formats
    final formatsEn = <DateFormat>[
      DateFormat("dd MMM yyyy, hh:mm a", "en"),
      DateFormat("d MMM yyyy, hh:mm a", "en"),
      DateFormat("dd MMM yyyy, h:mm a", "en"),
      DateFormat("d MMM yyyy, h:mm a", "en"),
      DateFormat("dd MMM yyyy", "en"),
      DateFormat("d MMM yyyy", "en"),
    ];

    for (final f in formatsEn) {
      try {
        return f.parseStrict(s);
      } catch (_) {}
    }

    // Locale formats (in case Arabic month names)
    final localeTag = context.locale.toLanguageTag();
    final formatsLocale = <DateFormat>[
      DateFormat("dd MMM yyyy, hh:mm a", localeTag),
      DateFormat("d MMM yyyy, hh:mm a", localeTag),
      DateFormat("dd MMM yyyy", localeTag),
      DateFormat("d MMM yyyy", localeTag),
    ];

    for (final f in formatsLocale) {
      try {
        return f.parseStrict(s);
      } catch (_) {}
    }

    return null;
  }

  // ------------------------------------------------------------
  // Load orders from backend
  // ------------------------------------------------------------
  Future<void> _loadOrders() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final data = await PatientService.fetchOrders();

      final formatted = data.map<Map<String, String>>((order) {
        final status = _safeStr(order["status"]).toLowerCase();

        // Prefer order_id always
        final orderId = _safeStr(order["order_id"]).isNotEmpty
            ? _safeStr(order["order_id"])
            : _safeStr(order["orderId"]).isNotEmpty
            ? _safeStr(order["orderId"])
            : _safeStr(order["id"]).isNotEmpty
            ? _safeStr(order["id"])
            : _safeStr(order["code"]);

        // Display code = UUID
        final code = orderId;

        final medicine = _safeStr(order["medication_name"]);
        final priority = _safeStr(order["priority_level"]);

        final placedAtRaw = _safeStr(order["created_at"]).isNotEmpty
            ? _safeStr(order["created_at"])
            : _safeStr(order["placed_at"]).isNotEmpty
            ? _safeStr(order["placed_at"])
            : _safeStr(order["createdAt"]);

        final deliveredAtRaw = _safeStr(order["delivered_at"]).isNotEmpty
            ? _safeStr(order["delivered_at"])
            : _safeStr(order["deliveredAt"]);

        final placedAtDt = _parseBackendDate(placedAtRaw);
        final deliveredAtDt = _parseBackendDate(deliveredAtRaw);

        final placedAtText = placedAtDt != null
            ? _formatDateForUi(placedAtDt)
            : "-";
        final deliveredAtText = deliveredAtDt != null
            ? _formatDateForUi(deliveredAtDt)
            : "-";

        return {
          "status": status,
          "orderId": orderId,
          "code": code,
          "medicine": medicine,
          "priority": priority,
          "placedAt": placedAtText,
          "deliveredAt": deliveredAtText,
        };
      }).toList();

      if (!mounted) return;
      setState(() => _orders = formatted);
    } catch (e) {
      if (!mounted) return;
      setState(() => _errorMessage = e.toString());
    } finally {
      if (!mounted) return;
      setState(() => _isLoading = false);
    }
  }

  // ------------------------------------------------------------
  // Cancel order (optimistic hide)
  // ------------------------------------------------------------
  Future<void> _cancelOrder({
    required String orderId,
    required String codeFallback,
  }) async {
    final effectiveId = orderId.isNotEmpty ? orderId : codeFallback;
    if (effectiveId.isEmpty) return;

    setState(() {
      _cancelingOrderId = effectiveId;
      _orders.removeWhere((o) {
        final oid = (o["orderId"] ?? "");
        final c = (o["code"] ?? "");
        return oid == effectiveId || c == codeFallback;
      });
    });

    try {
      debugPrint("ORDERS: cancel orderId=$effectiveId");
      await PatientService.cancelOrder(orderId: effectiveId);

      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("order_cancelled".tr())));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (!mounted) return;
      setState(() => _cancelingOrderId = null);
    }
  }

  // ------------------------------------------------------------
  // Build
  // ------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    final q = searchQuery.trim().toLowerCase();

    final filteredOrders = _orders.where((order) {
      final status = (order["status"] ?? "").toLowerCase();
      final medicine = (order["medicine"] ?? "").toLowerCase();
      final orderCode = (order["code"] ?? "").toLowerCase();

      bool matchesFilter;
      if (selectedFilter == "Active") {
        matchesFilter =
            status == "pending" ||
            status == "accepted" ||
            status == "on_delivery" ||
            status == "on_route";
      } else if (selectedFilter == "Completed") {
        matchesFilter =
            status == "delivered" ||
            status == "delivery_failed" ||
            status == "rejected";
      } else {
        matchesFilter = true;
      }

      bool matchesSearch = true;
      if (q.isNotEmpty) {
        matchesSearch = medicine.contains(q) || orderCode.contains(q);
      }

      return matchesFilter && matchesSearch;
    }).toList();

    return Scaffold(
      backgroundColor: AppColors.appBackground,
      appBar: PreferredSize(
        preferredSize: Size.fromHeight(90.h),
        child: CustomTopBar(
          title: "orders".tr(),
          onMenuTap: () => showTeryaqMenu(context),
        ),
      ),
      body: _isLoading
          ? Center(
              child: SizedBox(
                width: 32.w,
                height: 32.w,
                child: const CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          : _errorMessage != null
          ? _buildErrorState()
          : RefreshIndicator(
              onRefresh: _loadOrders,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(
                  parent: BouncingScrollPhysics(),
                ),
                child: Padding(
                  padding: EdgeInsets.only(top: 25.h, left: 25.w, right: 25.w),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // FILTER ROW
                      Row(
                        children: [
                          Text(
                            "${"filter".tr()}:",
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              color: AppColors.headingText,
                              fontSize: 14.sp,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          SizedBox(width: 20.w),
                          _filterButton("active".tr(), "Active"),
                          SizedBox(width: 12.w),
                          _filterButton("completed".tr(), "Completed"),
                          SizedBox(width: 12.w),
                          _filterButton("all".tr(), "All"),
                        ],
                      ),
                      SizedBox(height: 20.h),

                      // SEARCH BAR
                      Container(
                        height: 41.h,
                        decoration: BoxDecoration(
                          color: AppColors.cardBackground,
                          borderRadius: BorderRadius.circular(20.r),
                          boxShadow: AppColors.universalShadow,
                        ),
                        child: TextField(
                          onChanged: (value) =>
                              setState(() => searchQuery = value),
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            color: AppColors.bodyText,
                            fontSize: 17.sp,
                          ),
                          decoration: InputDecoration(
                            prefixIcon: Icon(
                              Icons.search,
                              color: AppColors.bodyText,
                              size: 22.sp,
                            ),
                            hintText: "search".tr(),
                            hintStyle: TextStyle(
                              fontFamily: 'Poppins',
                              color: const Color(0xFFC6D9E0),
                              fontSize: 15.sp,
                            ),
                            border: InputBorder.none,
                            contentPadding: EdgeInsets.symmetric(
                              vertical: 13.h,
                            ),
                          ),
                        ),
                      ),

                      SizedBox(height: 33.h),

                      if (filteredOrders.isEmpty)
                        _buildEmptyState()
                      else
                        Column(
                          children: [
                            ...filteredOrders.map((o) => _buildOrderCard(o)),
                            SizedBox(height: 50.h),
                          ],
                        ),
                    ],
                  ),
                ),
              ),
            ),
    );
  }

  Widget _buildOrderCard(Map<String, String> order) {
    final status = (order["status"] ?? "").toLowerCase();

    final rawOrderId = order["orderId"] ?? "";
    final code = order["code"] ?? "";
    final effectiveId = rawOrderId.isNotEmpty ? rawOrderId : code;

    final codeShown = _truncateCode(code, keep: 10);
    final medicine = order["medicine"] ?? "";
    final priority = (order["priority"] ?? "").toLowerCase();

    final placedAtText = order["placedAt"] ?? "-";
    final deliveredAtText = order["deliveredAt"] ?? "-";

    final statusColor = _statusColor(status);
    final iconPath = _statusIcon(status);

    final canTrack =
        (status == "on_route" || status == "on_delivery") &&
        effectiveId.isNotEmpty;
    final canCancel = status == "pending" && effectiveId.isNotEmpty;
    final canReport =
        status == "rejected" ||
        status == "delivered" ||
        status == "delivery_failed";

    final isCancelingThis = _cancelingOrderId == effectiveId;

    return Container(
      margin: EdgeInsets.only(bottom: 12.h),
      padding: EdgeInsets.fromLTRB(
        16.w,
        20.h,
        16.w,
        14.h,
      ), // 🔧 more top padding
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
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ================= LEFT BLOCK =================
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // STATUS ROW (icon + status + code)
                    Padding(
                      padding: EdgeInsets.only(
                        top: 4.h,
                      ), // 🔧 pushes square down
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Container(
                            width: 44.w,
                            height: 44.w,
                            decoration: BoxDecoration(
                              color: statusColor.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(12.r),
                            ),
                            child: Center(
                              child: iconPath != null
                                  ? SvgPicture.asset(
                                      iconPath,
                                      width: 22.w,
                                      height: 22.w,
                                      colorFilter: ColorFilter.mode(
                                        statusColor,
                                        BlendMode.srcIn,
                                      ),
                                    )
                                  : Icon(Icons.access_time, color: statusColor),
                            ),
                          ),
                          SizedBox(width: 10.w),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        _translateStatus(status),
                                        style: TextStyle(
                                          fontSize: 15.sp,
                                          fontWeight: FontWeight.w800,
                                          color: statusColor,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    if (priority.isNotEmpty)
                                      Text(
                                        _translateLevel(priority),
                                        style: TextStyle(
                                          fontSize: 13.sp,
                                          fontWeight: FontWeight.w600,
                                          color: _priorityColor(priority),
                                        ),
                                      ),
                                  ],
                                ),
                                SizedBox(height: 2.h),
                                Text(
                                  "#$codeShown",
                                  style: TextStyle(
                                    fontSize: 10.sp,
                                    color: AppColors.bodyText,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),

                    SizedBox(height: 12.h),

                    // MEDICATION — stays ABOVE placed_at
                    Text(
                      medicine,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14.sp,
                        fontWeight: FontWeight.w600,
                        color: AppColors.buttonRed,
                      ),
                    ),

                    SizedBox(height: 6.h),

                    _infoRow("placed_at".tr(), placedAtText),
                    SizedBox(height: 3.h),
                    _infoRow("delivered_at".tr(), deliveredAtText),
                  ],
                ),
              ),

              SizedBox(width: 12.w),

              // ================= BUTTONS (UNCHANGED) =================
              Column(
                children: [
                  Opacity(
                    opacity: canTrack ? 1.0 : 0.5,
                    child: GestureDetector(
                      onTap: canTrack
                          ? () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => PatientTrackScreen(
                                    orderId: effectiveId,
                                    codeFallback: code,
                                  ),
                                ),
                              );
                            }
                          : null,
                      child: _actionButton(
                        "track".tr(),
                        borderColor: AppColors.buttonBlue,
                        textColor: AppColors.buttonBlue,
                      ),
                    ),
                  ),
                  SizedBox(height: 6.h),
                  Opacity(
                    opacity: canReport ? 1.0 : 0.5,
                    child: GestureDetector(
                      onTap: canReport
                          ? () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) =>
                                      PatientReportScreen(orderId: effectiveId),
                                ),
                              );
                            }
                          : null,
                      child: _actionButton(
                        "report".tr(),
                        borderColor: AppColors.buttonBlue,
                        textColor: AppColors.buttonBlue,
                      ),
                    ),
                  ),
                  SizedBox(height: 6.h),
                  Opacity(
                    opacity: canCancel ? 1.0 : 0.5,
                    child: GestureDetector(
                      onTap: (canCancel && !isCancelingThis)
                          ? () {
                              showCustomPopup(
                                context: context,
                                titleText: "are_you_sure".tr(),
                                subtitleText: "cancel_order_warning".tr(),
                                cancelText: "no_keep_it".tr(),
                                confirmText: "yes_cancel".tr(),
                                onCancel: () {},
                                onConfirm: () {
                                  _cancelOrder(
                                    orderId: effectiveId,
                                    codeFallback: code,
                                  );
                                },
                              );
                            }
                          : null,
                      child: isCancelingThis
                          ? SizedBox(
                              width: 61.w,
                              height: 24.h,
                              child: Center(
                                child: SizedBox(
                                  width: 14.w,
                                  height: 14.w,
                                  child: const CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                ),
                              ),
                            )
                          : _actionButton(
                              "cancel".tr(),
                              borderColor: AppColors.buttonRed,
                              textColor: AppColors.buttonRed,
                            ),
                    ),
                  ),
                ],
              ),
            ],
          ),
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
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12.sp,
                fontWeight: FontWeight.w500,
                color: const Color(0xFF4B4B4B),
              ),
            ),
          ),
        ],
      ),
    );
  }

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

  Widget _filterButton(String labelText, String key) {
    final isSelected = selectedFilter == key;

    return GestureDetector(
      onTap: () => setState(() => selectedFilter = key),
      child: SizedBox(
        width: key == "All"
            ? 55.w
            : key == "Active"
            ? 90.w
            : 103.w,
        height: 28.h,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          decoration: BoxDecoration(
            color: isSelected ? AppColors.buttonBlue : AppColors.appBackground,
            borderRadius: BorderRadius.circular(14.r),
            boxShadow: AppColors.universalShadow,
          ),
          alignment: Alignment.center,
          child: Text(
            labelText,
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 13.sp,
              fontWeight: FontWeight.w600,
              color: isSelected
                  ? AppColors.appBackground
                  : AppColors.headingText,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Padding(
      padding: EdgeInsets.only(top: 60.h, bottom: 40.h),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset('assets/icons/tick.png', width: 180.w, height: 180.h),
            SizedBox(height: 16.h),
            Text(
              "no_orders_yet".tr(),
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 18.sp,
                fontWeight: FontWeight.w600,
                color: AppColors.bodyText,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 24.w),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline,
              size: 40.w,
              color: AppColors.statusRejected,
            ),
            SizedBox(height: 12.h),
            Text(
              "orders_error".tr(),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 14.sp,
                fontWeight: FontWeight.w600,
                color: AppColors.statusRejected,
              ),
            ),
            if (_errorMessage != null) ...[
              SizedBox(height: 4.h),
              Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 11.sp,
                  color: AppColors.bodyText.withOpacity(0.6),
                ),
              ),
            ],
            SizedBox(height: 16.h),
            SizedBox(
              height: 38.h,
              child: ElevatedButton(
                onPressed: _loadOrders,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.buttonRed,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12.r),
                  ),
                  padding: EdgeInsets.symmetric(horizontal: 24.w),
                ),
                child: Text(
                  "retry".tr(),
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 13.sp,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
