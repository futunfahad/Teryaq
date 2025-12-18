// lib/features/patient/patient_screens/patient_home.dart
//
// Patient Home
// - Loads home summary from backend (PatientService.fetchHomeSummary)
// - Order Status card:
//     • Shows ONLY the latest order (uses last item fallback)
//     • Tapping card or Track opens PatientTrackScreen with that orderId
// - Notifications:
//     • Mask any long IDs (digits/UUID) to show ONLY first 10 characters/digits

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:easy_localization/easy_localization.dart';

import 'chat_page.dart';
import 'patient_notifications.dart';
import 'patient_orders.dart';
import 'patient_prescriptions.dart';
import 'patient_profile.dart';
import 'patient_track.dart';

import 'package:teryagapptry/widgets/custom_bottom_nav.dart';
import 'package:teryagapptry/widgets/custom_top_bar.dart';
import 'package:teryagapptry/widgets/show_teryaq_menu.dart';
import 'package:teryagapptry/constants/app_colors.dart';

// Backend service
import 'package:teryagapptry/services/patient_service.dart';

class PatientHome extends StatefulWidget {
  final int initialIndex;

  const PatientHome({super.key, this.initialIndex = 0});

  @override
  State<PatientHome> createState() => _PatientHomeState();
}

class _PatientHomeState extends State<PatientHome> {
  // Updated from backend (patient home summary)
  String patientName = "Durrah Aloulah";

  late int currentIndex;

  // Notifications (will be replaced by backend data)
  final List<Map<String, dynamic>> notificationsList = [
    {"message": "Your medication has been prepared by the hospital."},
    {"message": "Driver has arrived at the hospital for pickup."},
    {"message": "Your refill request was submittssssed successfully."},
    {"message": "Your Order is on the way! have your OTP ready."},
  ];

  // Refill card structure (will be updated from backend)
  final Map<String, dynamic> refillData = {
    "medName": "Propranolol",
    "daysLeft": 20,
  };

  // Health tip structure (localization keys only)
  final Map<String, String> healthTip = {
    "titleKey": "health_tip_title",
    "bodyKey": "health_tip_msg",
  };

  // Recent orders list for the Order Status card (backend replaces this).
  // We'll display ONLY the latest (robust: last item if no timestamps).
  final List<Map<String, String>> recentOrders = [
    {"status": "On Delivery", "id": "UOT-847362"},
    {"status": "Delivered", "id": "UOT-847190"},
  ];

  // Shared text style (12.sp) for all body text
  late final TextStyle bodyText12 = TextStyle(
    fontFamily: 'Poppins',
    fontSize: 12.sp,
    fontWeight: FontWeight.w500,
    color: const Color(0xFF013A3C),
  );

  @override
  void initState() {
    super.initState();
    currentIndex = widget.initialIndex;

    // Load patient home summary from backend
    _loadHomeData();
  }

  // ------------------------------------------------------------
  // Helpers (Orders-screen style)
  // ------------------------------------------------------------
  String _safeStr(dynamic v) => v == null ? "" : v.toString();

  String _truncateCode(String code, {int keep = 10}) {
    if (code.isEmpty) return "";
    if (code.length <= keep) return code;
    return code.substring(0, keep);
  }

  int _statusRank(String raw) {
    final s = _normalizeStatus(raw);
    switch (s) {
      case "on_route":
        return 400;
      case "on_delivery":
        return 300;
      case "accepted":
        return 200;
      case "pending":
        return 100;
      // terminal states
      case "delivered":
      case "delivery_failed":
      case "rejected":
        return 0;
      default:
        return 50;
    }
  }

  // ✅ Mask long digits/UUIDs inside notification messages:
  // Keep first 10, hide the rest.
  String _maskSensitiveNotification(String msg) {
    if (msg.trim().isEmpty) return msg;

    String maskToken(String token) {
      if (token.length <= 10) return token;
      return "${token.substring(0, 10)}••••";
    }

    // UUID pattern
    final uuidRegex = RegExp(
      r'\b[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}\b',
    );

    // Long digit runs (11+ digits)
    final longDigits = RegExp(r'\b\d{11,}\b');

    // Also mask any very long "code-like" token without spaces (optional)
    final longToken = RegExp(r'\b[^\s]{16,}\b');

    var out = msg;
    out = out.replaceAllMapped(uuidRegex, (m) => maskToken(m.group(0)!));
    out = out.replaceAllMapped(longDigits, (m) => maskToken(m.group(0)!));
    out = out.replaceAllMapped(longToken, (m) => maskToken(m.group(0)!));
    return out;
  }

  // Convert backend/home statuses like "On Delivery" into DB-style keys like "on_delivery"
  String _normalizeStatus(String raw) {
    final s = (raw).trim().toLowerCase();

    // Already normalized
    if (s.contains("_")) return s;

    // Common UI labels -> internal keys
    if (s == "on delivery") return "on_delivery";
    if (s == "delivery failed") return "delivery_failed";
    if (s == "on route") return "on_route";

    return s; // fallback
  }

  // Translate DB status to localized label keys
  String _translateStatus(String raw) {
    final s = _normalizeStatus(raw);

    switch (s) {
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
        return raw; // show as-is if unknown
    }
  }

  Color _statusColor(String raw) {
    final s = _normalizeStatus(raw);

    switch (s) {
      case "pending":
        return const Color(0xFFD1B000); // yellow
      case "accepted":
        return const Color(0xFF004A8B); // dark blue
      case "on_delivery":
      case "on_route":
        return const Color(0xFF004A8B); // dark blue (in-progress)
      case "delivered":
        return const Color(0xFF137713); // green
      case "rejected":
      case "delivery_failed":
        return const Color(0xFFCC0000); // red
      default:
        return Colors.grey;
    }
  }

  String? _statusIcon(String raw) {
    final s = _normalizeStatus(raw);

    switch (s) {
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

  // ✅ pick latest order robustly:
  // - If list has "createdAt" (not currently used in UI), you can sort by it later.
  // - Otherwise: use last item (as you requested "آخر واحد").
  Map<String, String> _pickLatestOrder(List<Map<String, String>> list) {
    if (list.isEmpty) return {};
    return list.first; // most advanced first (backend-sorted)
  }

  // ------------------------------------------------------------
  // Load home summary from backend:
  // - patient_name
  // - recent_orders
  // - next_refill
  // - notifications
  // ------------------------------------------------------------
  Future<void> _loadHomeData() async {
    try {
      final data = await PatientService.fetchHomeSummary();
      if (!mounted || data == null) return;

      setState(() {
        // 1) Patient name
        patientName = data["patient_name"]?.toString() ?? patientName;

        // 2) Recent orders
        final ro = (data["recent_orders"] as List<dynamic>? ?? [])
            .map<Map<String, String>>((e) {
              final status = e["status"]?.toString() ?? "";

              // Prefer order_id then code
              final oid =
                  e["order_id"]?.toString() ?? e["orderId"]?.toString() ?? "";
              final code = e["code"]?.toString() ?? "";
              final effective = oid.isNotEmpty ? oid : code;

              return {
                "status": status,
                "id": effective, // used as orderId in tracking
              };
            })
            .toList();

        if (ro.isNotEmpty) {
          recentOrders
            ..clear()
            ..addAll(ro);
        }

        // 3) Next refill
        final nr = data["next_refill"];
        if (nr != null) {
          refillData["medName"] =
              nr["medication_name"]?.toString() ?? refillData["medName"];
          refillData["daysLeft"] = nr["days_left"] ?? refillData["daysLeft"];
        }

        // 4) Notifications
        final noti = (data["notifications"] as List<dynamic>? ?? [])
            .map<Map<String, dynamic>>((e) {
              final rawMsg = e["message"]?.toString() ?? "";

              // Optional: If backend includes an ID/code, append it then mask it
              final id =
                  e["order_id"]?.toString() ??
                  e["code"]?.toString() ??
                  e["orderId"]?.toString() ??
                  "";

              final msgWithId = id.isNotEmpty
                  ? "$rawMsg  #${_truncateCode(id, keep: 10)}"
                  : rawMsg;

              return {"message": _maskSensitiveNotification(msgWithId)};
            })
            .toList();

        if (noti.isNotEmpty) {
          notificationsList
            ..clear()
            ..addAll(noti);
        }
      });
    } catch (e) {
      // Optional: show a snackbar/log in debug
    }
  }

  Widget _chatFloatingButton(BuildContext context) {
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const ChatBotPage()),
        );
      },
      child: Container(
        width: 50.w,
        height: 50.w,
        decoration: BoxDecoration(
          color: AppColors.buttonBlue,
          shape: BoxShape.circle,
          boxShadow: AppColors.universalShadow,
        ),
        child: const Icon(Icons.smart_toy, color: Colors.white, size: 26),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final String lastNotificationRaw = notificationsList.isNotEmpty
        ? _safeStr(notificationsList.last["message"])
        : "no_noti_yet".tr();

    // ✅ Ensure masking even for local/dummy messages
    final String lastNotification = _maskSensitiveNotification(
      lastNotificationRaw,
    );

    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: AppColors.appHeader,
        statusBarIconBrightness: Brightness.dark,
      ),
    );

    final List<Widget> pages = [
      _buildHomePage(lastNotification),
      const PatientPrescriptions(),
      const PatientOrders(),
      const PatientProfile(),
    ];

    return Scaffold(
      body: Stack(
        children: [
          pages[currentIndex],

          // Floating Chat Button (Bottom Left)
          Positioned(
            left: 20.w,
            bottom: 10.h,
            child: _chatFloatingButton(context),
          ),
        ],
      ),
      bottomNavigationBar: CustomBottomNavBar(
        currentIndex: currentIndex,
        onTap: (index) {
          setState(() => currentIndex = index);
        },
      ),
    );
  }

  // ------------------------------------------------------------
  // Home Page UI
  // ------------------------------------------------------------
  Widget _buildHomePage(String lastNotification) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: CustomTopBar(title: "", onMenuTap: () => showTeryaqMenu(context)),
      body: Stack(
        children: [
          Container(
            height: 260.h,
            decoration: BoxDecoration(
              color: AppColors.appHeader,
              borderRadius: BorderRadius.only(
                bottomLeft: Radius.circular(80.r),
                bottomRight: Radius.circular(80.r),
              ),
            ),
          ),
          SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            padding: EdgeInsets.only(top: 95.h, left: 25.w, right: 25.w),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "${"hello".tr()} $patientName 👋",
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 24.sp,
                    fontWeight: FontWeight.w800,
                    color: AppColors.headingText,
                  ),
                ),
                SizedBox(height: 4.h),
                Text(
                  "what_you_like".tr(),
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 15.sp,
                    fontWeight: FontWeight.w600,
                    color: AppColors.bodyText,
                  ),
                ),
                SizedBox(height: 30.h),
                _buildHealthTip(),
                SizedBox(height: 22.h),

                // Updated Order Status card (latest only + open View Track)
                _buildOrderStatusCard(),
                SizedBox(height: 22.h),

                _buildHomeCard(
                  title: "your_next_refill".tr(),
                  body: Wrap(
                    alignment: WrapAlignment.start,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 6.w,
                    runSpacing: 6.h,
                    children: [
                      Text(refillData["medName"], style: bodyText12),
                      Icon(
                        Icons.arrow_forward,
                        size: 18.sp,
                        color: AppColors.bodyText,
                      ),
                      Text(
                        "${refillData["daysLeft"]} ${"days_left".tr()}",
                        style: bodyText12,
                      ),
                    ],
                  ),
                  onTap: null,
                ),

                SizedBox(height: 22.h),

                _buildHomeCard(
                  title: "",
                  body: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(height: 4.h),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            "notification_card".tr(),
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 18.sp,
                              fontWeight: FontWeight.w700,
                              color: AppColors.headingText,
                            ),
                          ),
                          GestureDetector(
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) =>
                                      const PatientNotificationsScreen(),
                                ),
                              );
                            },
                            child: Text(
                              "view_all".tr(),
                              style: TextStyle(
                                fontFamily: 'Poppins',
                                fontSize: 12.sp,
                                fontWeight: FontWeight.w600,
                                color: const Color(0xFF57A4B7),
                              ),
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 12.h),
                      Text(lastNotification, style: bodyText12),
                    ],
                  ),
                  onTap: null,
                ),

                SizedBox(height: 80.h),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHomeCard({
    required String title,
    required Widget body,
    required VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.symmetric(vertical: 18.h, horizontal: 18.w),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12.r),
          boxShadow: AppColors.universalShadow,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (title.isNotEmpty)
              Text(
                title,
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 18.sp,
                  fontWeight: FontWeight.w700,
                  color: AppColors.headingText,
                ),
              ),
            SizedBox(height: title.isNotEmpty ? 12.h : 0),
            body,
          ],
        ),
      ),
    );
  }

  // ------------------------------------------------------------
  // Order Status Card (latest only + tap opens View Track)
  // ------------------------------------------------------------
  Widget _buildOrderStatusCard() {
    if (recentOrders.isEmpty) {
      return _buildHomeCard(
        title: "order_status".tr(),
        body: Text("no_orders_yet".tr(), style: bodyText12),
        onTap: null,
      );
    }

    // ✅ Use آخر واحد (last item)
    final Map<String, String> latestOrder = _pickLatestOrder(recentOrders);

    final String statusRaw = latestOrder["status"] ?? "";
    final String orderId = latestOrder["id"] ?? "";

    final String statusNorm = _normalizeStatus(statusRaw);
    final Color statusColor = _statusColor(statusNorm);
    final String? iconPath = _statusIcon(statusNorm);
    final String codeShown = _truncateCode(orderId, keep: 10);

    final bool canTrack =
        (statusNorm == "on_route" || statusNorm == "on_delivery") &&
        orderId.isNotEmpty;

    void openTrack() {
      // ✅ View Track with the same orderId
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) =>
              PatientTrackScreen(orderId: orderId, codeFallback: orderId),
        ),
      );
    }

    return GestureDetector(
      onTap: canTrack
          ? openTrack
          : () {
              // If not trackable, open orders screen as a sensible fallback
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const PatientOrders()),
              );
            },
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.symmetric(vertical: 18.h, horizontal: 18.w),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12.r),
          boxShadow: AppColors.universalShadow,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "order_status".tr(),
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
                // Left: status icon box
                Container(
                  width: 51.w,
                  height: 52.h,
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(12.r),
                  ),
                  child: Center(
                    child: (iconPath != null && iconPath.isNotEmpty)
                        ? SvgPicture.asset(
                            iconPath,
                            width: 26.w,
                            height: 30.h,
                            colorFilter: ColorFilter.mode(
                              statusColor,
                              BlendMode.srcIn,
                            ),
                          )
                        : Icon(
                            Icons.access_time,
                            color: statusColor,
                            size: 28.sp,
                          ),
                  ),
                ),
                SizedBox(width: 10.w),

                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _translateStatus(statusNorm),
                        style: TextStyle(
                          fontSize: 15.sp,
                          fontWeight: FontWeight.w800,
                          color: statusColor,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      SizedBox(height: 4.h),
                      Text(
                        codeShown.isNotEmpty ? "#$codeShown" : "",
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 11.sp,
                          fontWeight: FontWeight.w500,
                          color: AppColors.bodyText,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),

                SizedBox(width: 10.w),

                // Right: Track button
                SizedBox(
                  height: 24.h,
                  width: 61.w, // ✅ FIX: was 61.h
                  child: TextButton(
                    onPressed: canTrack ? openTrack : null,
                    style: TextButton.styleFrom(
                      padding: EdgeInsets.zero,
                      backgroundColor: canTrack
                          ? AppColors.buttonBlue
                          : AppColors.buttonBlue.withOpacity(0.5),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8.r),
                      ),
                    ),
                    child: Text(
                      "track".tr(),
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 10.sp,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ------------------------------------------------------------
  // Health Tip Card
  // ------------------------------------------------------------
  Widget _buildHealthTip() {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(14.w),
      decoration: BoxDecoration(
        color: AppColors.buttonBlue,
        borderRadius: BorderRadius.circular(12.r),
        boxShadow: AppColors.universalShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            healthTip["titleKey"]!.tr(),
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 18.sp,
              fontWeight: FontWeight.w900,
              color: Colors.white,
            ),
          ),
          SizedBox(height: 6.h),
          Text(
            healthTip["bodyKey"]!.tr(),
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 15.sp,
              fontWeight: FontWeight.w500,
              color: Colors.white,
              height: 1.2,
            ),
          ),
        ],
      ),
    );
  }
}
