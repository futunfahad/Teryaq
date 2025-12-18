import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:easy_localization/easy_localization.dart';

import 'package:teryagapptry/constants/app_colors.dart';
import 'package:teryagapptry/widgets/custom_top_bar.dart';
import 'package:teryagapptry/widgets/custom_bottom_nav_driver.dart';
import 'package:teryagapptry/widgets/show_teryaq_menu.dart';

import 'package:teryagapptry/services/driver_service.dart';

class DriverNotification extends StatefulWidget {
  const DriverNotification({super.key});

  @override
  State<DriverNotification> createState() => _DriverNotificationState();
}

class _DriverNotificationState extends State<DriverNotification> {
  bool loading = true;
  List<Map<String, dynamic>> notifications = [];

  @override
  void initState() {
    super.initState();
    _loadNotifications();
  }

  // ===========================================================
  // LOAD NOTIFICATIONS DYNAMICALLY FOR LOGGED-IN DRIVER
  // ===========================================================
  // ===========================================================
  // LOAD NOTIFICATIONS DYNAMICALLY FOR LOGGED-IN DRIVER
  // ===========================================================
  Future<void> _loadNotifications() async {
    try {
      loading = true;
      setState(() {});

      // 1️⃣ Get driver profile → driver_id
      final profile = await DriverService.getDriverProfile();
      final String driverId = (profile["driver_id"] ?? "").toString();

      if (driverId.isEmpty) {
        throw Exception("Invalid driver_id from backend");
      }

      // 2️⃣ Fetch ALL notifications (backend returns all)
      final data = await DriverService.getNotifications();

      List rawList = [];
      if (data is Map && data["notifications"] is List) {
        rawList = data["notifications"];
      } else if (data is List) {
        rawList = data;
      }

      // Convert to List<Map>
      List<Map<String, dynamic>> parsed = rawList
          .whereType<Map>()
          .map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e))
          .toList();

      // 3️⃣ Fetch THIS driver’s orders
      final todayOrders = await DriverService.getTodayOrders(
        driverId: driverId,
      );
      final historyOrders = await DriverService.getOrdersHistory(
        driverId: driverId,
      );

      // Collect order_ids that belong to Matthew
      final Set<String> driverOrderIds = {};

      for (final o in todayOrders) {
        if (o is Map && o["order_id"] != null) {
          driverOrderIds.add(o["order_id"].toString());
        }
      }
      for (final o in historyOrders) {
        if (o is Map && o["order_id"] != null) {
          driverOrderIds.add(o["order_id"].toString());
        }
      }

      // 4️⃣ Final filtering: ONLY show notifications that belong to Matthew
      final filtered = parsed.where((n) {
        final oid = n["order_id"]?.toString() ?? "";
        return driverOrderIds.contains(oid);
      }).toList();

      if (!mounted) return;

      // 5️⃣ Update UI
      setState(() {
        notifications = filtered;
        loading = false;
      });
    } catch (e) {
      debugPrint("DriverNotification ERROR → $e");

      if (!mounted) return;
      setState(() {
        notifications = [];
        loading = false;
      });
    }
  }

  // Notification colors used in UI
  final List<Color> _notificationColors = const [
    AppColors.notificationGreen,
    AppColors.notificationYellow,
    AppColors.statusRejected,
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      bottomNavigationBar: CustomBottomNavDriver(
        currentIndex: 1,
        onTap: (index) {},
      ),
      backgroundColor: AppColors.appBackground,
      appBar: PreferredSize(
        preferredSize: Size.fromHeight(90.h),
        child: CustomTopBar(
          title: "notifications".tr(),
          onMenuTap: () => showTeryaqMenu(context),
        ),
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: EdgeInsets.symmetric(horizontal: 18.w, vertical: 20.h),
              child: notifications.isEmpty
                  ? Center(
                      child: Text(
                        tr("no_notifications"),
                        style: TextStyle(
                          fontSize: 14.sp,
                          fontWeight: FontWeight.w600,
                          color: AppColors.bodyText,
                        ),
                      ),
                    )
                  : ListView.builder(
                      itemCount: notifications.length,
                      itemBuilder: (context, index) {
                        final n = notifications[index];

                        final color =
                            _notificationColors[index %
                                _notificationColors.length];

                        final String title =
                            (n["title"] ??
                                    n["notification_type"] ??
                                    "Notification")
                                .toString();

                        final String description =
                            (n["notification_content"] ??
                                    n["message"] ??
                                    n["body"] ??
                                    "")
                                .toString();

                        return NotificationCard(
                          title: title,
                          description: description,
                          color: color,
                        );
                      },
                    ),
            ),
    );
  }
}

// ====================================================================
// 🔔 REUSABLE NOTIFICATION CARD
// ====================================================================

class NotificationCard extends StatelessWidget {
  final String title;
  final String description;
  final Color color;

  const NotificationCard({
    super.key,
    required this.title,
    required this.description,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.only(bottom: 12.h),
      padding: EdgeInsets.all(12.w),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(12.r),
        boxShadow: AppColors.universalShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontWeight: FontWeight.w800,
              color: AppColors.headingText,
              fontSize: 12.sp,
            ),
          ),
          SizedBox(height: 6.h),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 34.w,
                height: 34.w,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.15),
                  shape: BoxShape.circle,
                  border: Border.all(color: color.withOpacity(0.4)),
                ),
                child: Icon(
                  Icons.notifications_none_rounded,
                  color: color,
                  size: 22.w,
                ),
              ),
              SizedBox(width: 12.w),
              Expanded(
                child: Text(
                  description,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: AppColors.bodyText,
                    fontSize: 12.sp,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
