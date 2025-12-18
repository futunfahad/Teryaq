import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:easy_localization/easy_localization.dart';

import 'package:teryagapptry/constants/app_colors.dart';
import 'package:teryagapptry/widgets/custom_top_bar.dart';
import 'package:teryagapptry/services/patient_service.dart';

class PatientNotificationsScreen extends StatefulWidget {
  const PatientNotificationsScreen({super.key});

  @override
  State<PatientNotificationsScreen> createState() =>
      _PatientNotificationsScreenState();
}

class _PatientNotificationsScreenState
    extends State<PatientNotificationsScreen> {
  List<Map<String, dynamic>> _notifications = [];
  bool _isLoading = false;
  String? _errorMessage;

  // Tracks which order is currently being canceled (so we can show per-card loading)
  final Set<String> _cancelingOrderIds = <String>{};

  @override
  void initState() {
    super.initState();
    _loadNotifications();
  }

  /// Fetch notifications from backend using PatientService
  Future<void> _loadNotifications() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final data = await PatientService.fetchNotifications();
      setState(() {
        _notifications = data;
      });
    } catch (e) {
      setState(() {
        _errorMessage = e.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  /// Cancel an order from a notification (if the payload includes order_id)
  Future<void> _cancelOrderFromNotification(String orderId) async {
    final oid = orderId.trim();
    if (oid.isEmpty) return;

    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (_) {
        return AlertDialog(
          title: Text(
            // Add localization key if you want: confirm_cancel_order
            "Confirm cancel".tr(),
            style: TextStyle(
              fontFamily: "Poppins",
              fontWeight: FontWeight.w700,
              fontSize: 14.sp,
              color: AppColors.headingText,
            ),
          ),
          content: Text(
            // Add localization key if you want: cancel_order_confirm_message
            "Do you want to cancel this order?".tr(),
            style: TextStyle(
              fontFamily: "Poppins",
              fontWeight: FontWeight.w600,
              fontSize: 12.sp,
              color: AppColors.bodyText,
              height: 1.4,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(
                // Add localization key if you want: no
                "No".tr(),
                style: TextStyle(
                  fontFamily: "Poppins",
                  fontWeight: FontWeight.w700,
                  fontSize: 12.sp,
                  color: AppColors.bodyText.withOpacity(0.8),
                ),
              ),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.buttonRed,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10.r),
                ),
              ),
              child: Text(
                // Add localization key if you want: yes_cancel
                "Yes, cancel".tr(),
                style: TextStyle(
                  fontFamily: "Poppins",
                  fontWeight: FontWeight.w700,
                  fontSize: 12.sp,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;

    setState(() {
      _cancelingOrderIds.add(oid);
    });

    try {
      await PatientService.cancelOrder(orderId: oid);

      if (!mounted) return;

      // Reload notifications so event-based notifications reflect the cancellation
      await _loadNotifications();

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            // Add localization key if you want: order_cancelled_success
            "Order cancelled successfully.".tr(),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            // Add localization key if you want: order_cancelled_failed
            "Failed to cancel order: ${e.toString()}".tr(),
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _cancelingOrderIds.remove(oid);
        });
      }
    }
  }

  /// Map backend "level" string to UI color
  Color _colorForLevel(String? level) {
    switch (level) {
      case "success":
        return AppColors.notificationGreen;
      case "danger":
        return AppColors.statusRejected;
      case "warning":
      default:
        return AppColors.notificationYellow;
    }
  }

  /// Determines whether this notification should show "Cancel Order" action.
  /// Works with event-style payloads too.
  bool _canShowCancelAction(Map<String, dynamic> item) {
    final action = (item["action"] ?? item["action_type"] ?? item["type"])
        .toString()
        .toLowerCase();

    final canCancel =
        item["can_cancel"] == true || item["allow_cancel"] == true;

    final status = (item["status"] ?? "").toString().toLowerCase();

    // If backend explicitly says can_cancel => show.
    if (canCancel) return true;

    // Otherwise best-effort inference:
    // - allow cancel for pending/accepted/on_route (you can tune this)
    final statusCancelable = status == "pending" ||
        status == "accepted" ||
        status == "on_route" ||
        status == "on_delivery";

    final actionCancelable =
        action.contains("cancel") || action.contains("cancellable");

    return statusCancelable || actionCancelable;
  }

  String _getOrderId(Map<String, dynamic> item) {
    final id =
        item["order_id"] ?? item["orderId"] ?? item["order_uuid"] ?? item["uuid"];
    return (id ?? "").toString();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.appBackground,

      // Top bar with back button
      appBar: PreferredSize(
        preferredSize: Size.fromHeight(90.h),
        child: CustomTopBar(
          title: "notifications".tr(),
          showBackButton: true,
          onBackTap: () => Navigator.pop(context),
        ),
      ),

      // Body
      body: Padding(
        padding: EdgeInsets.symmetric(horizontal: 18.w, vertical: 20.h),
        child: _isLoading
            ? Center(
                child: SizedBox(
                  width: 32.w,
                  height: 32.w,
                  child: const CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            : _errorMessage != null
                ? _buildErrorState()
                : _notifications.isEmpty
                    ? _buildEmptyState()
                    : RefreshIndicator(
                        onRefresh: _loadNotifications,
                        child: ListView.builder(
                          physics: const AlwaysScrollableScrollPhysics(),
                          itemCount: _notifications.length,
                          itemBuilder: (context, index) {
                            final item = _notifications[index];

                            final String title =
                                (item["title"] ?? "Medication").toString();
                            final String description =
                                (item["description"] ?? "").toString();
                            final String level =
                                (item["level"] ?? "warning").toString();

                            final color = _colorForLevel(level);

                            final orderId = _getOrderId(item);
                            final showCancel =
                                orderId.isNotEmpty && _canShowCancelAction(item);
                            final canceling = _cancelingOrderIds.contains(orderId);

                            return NotificationCard(
                              title: title,
                              description: description,
                              color: color,
                              showCancel: showCancel,
                              cancelLoading: canceling,
                              onCancelTap: showCancel && !canceling
                                  ? () => _cancelOrderFromNotification(orderId)
                                  : null,
                            );
                          },
                        ),
                      ),
      ),
    );
  }

  // Empty state
  Widget _buildEmptyState() {
    return Padding(
      padding: EdgeInsets.only(top: 0.h, bottom: 80.h),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset(
              'assets/icons/tick.png',
              width: 180.w,
              height: 180.h,
            ),
            SizedBox(height: 16.h),
            Text(
              "no_notifications_yet".tr(),
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

  // Error state
  Widget _buildErrorState() {
    return Center(
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
            "notifications_error".tr(),
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
              onPressed: _loadNotifications,
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
    );
  }
}

// ====================================================================
// Reusable Notification Card
// - Supports optional "Cancel Order" action button
// ====================================================================
class NotificationCard extends StatelessWidget {
  final String title;
  final String description;
  final Color color;

  final bool showCancel;
  final bool cancelLoading;
  final VoidCallback? onCancelTap;

  const NotificationCard({
    super.key,
    required this.title,
    required this.description,
    required this.color,
    this.showCancel = false,
    this.cancelLoading = false,
    this.onCancelTap,
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
          // Title
          Text(
            title,
            style: TextStyle(
              fontFamily: 'Poppins',
              fontWeight: FontWeight.w800,
              color: AppColors.headingText,
              fontSize: 12.sp,
            ),
          ),
          SizedBox(height: 6.h),

          // Icon + message
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 34.w,
                height: 34.w,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.15),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: color.withOpacity(0.4),
                    width: 0.4.w,
                  ),
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
                    fontFamily: 'Poppins',
                    fontWeight: FontWeight.w600,
                    color: AppColors.bodyText,
                    fontSize: 12.sp,
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),

          // Optional action row
          if (showCancel) ...[
            SizedBox(height: 10.h),
            Align(
              alignment: Alignment.centerRight,
              child: SizedBox(
                height: 34.h,
                child: ElevatedButton(
                  onPressed: onCancelTap,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.buttonRed,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10.r),
                    ),
                    padding: EdgeInsets.symmetric(horizontal: 14.w),
                  ),
                  child: cancelLoading
                      ? SizedBox(
                          width: 16.w,
                          height: 16.w,
                          child: const CircularProgressIndicator(
                            strokeWidth: 2,
                          ),
                        )
                      : Text(
                          // Add localization key if you want: cancel_order
                          "Cancel Order".tr(),
                          style: TextStyle(
                            fontFamily: "Poppins",
                            fontWeight: FontWeight.w700,
                            fontSize: 11.sp,
                            color: Colors.white,
                          ),
                        ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
