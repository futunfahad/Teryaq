import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:teryagapptry/constants/app_colors.dart';
import 'package:easy_localization/easy_localization.dart'; // ⭐ for .tr()

/// ⭐ Global config for all order statuses (icon + color)
final Map<String, Map<String, dynamic>> orderStatusConfig = {
  "On Delivery": {
    "color": AppColors.statusOnDelivery,
    "icon": Icons.directions_car_filled_rounded,
    "bgColor": AppColors.statusOnDeliveryLight,
  },
  "Pending": {
    "color": AppColors.statusPending,
    "icon": Icons.access_time_rounded,
    "bgColor": AppColors.statusPendingLight,
  },
  "Delivered": {
    "color": AppColors.statusDelivered,
    "icon": Icons.task_alt_rounded,
    "bgColor": AppColors.statusDeliveredLight,
  },
  "Rejected": {
    "color": AppColors.statusRejected,
    "icon": Icons.cancel_outlined,
    "bgColor": AppColors.statusRejectedLight,
  },  
  "Accepted": {
    "color": AppColors.statusAccepted,
    "icon": Icons.done_rounded,
    "bgColor": AppColors.statusAcceptedLight,
  },
  "Delivery Failed": {
    "color": AppColors.statusFailed,
    "icon": Icons.do_not_disturb_on_rounded,
    "bgColor": AppColors.statusFailedLight,
  },
};

/// ⭐ Map backend status text → localization key
const Map<String, String> statusTranslationKeys = {
  "On Delivery": "on_delivery",
  "Pending": "pending",
  "Delivered": "delivered", 
  "Rejected": "rejected",  
  "Accepted": "accepted",
  "Delivery Failed": "delivery_failed",
};

Widget buildStatusBadge(
  String status, {
  Widget? bottomWidget, // 👈 optional widget under the status text
}) {
  final config = orderStatusConfig[status];

  if (config == null) {
    return Text(
      status,
      style: TextStyle(
        fontSize: 14.sp,
        fontWeight: FontWeight.w600,
        color: Colors.grey,
      ),
    );
  }

  final String? key = statusTranslationKeys[status];
  final String displayLabel = key != null ? key.tr() : status;

  final Color mainColor = config["color"] as Color;
  final Color boxColor =
      (config["bgColor"] as Color?) ?? mainColor.withOpacity(0.12);

  return Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      // 🔹 Square with icon
      Container(
        width: 55.w,
        height: 55.w,
        decoration: BoxDecoration(
          color: boxColor,
          borderRadius: BorderRadius.circular(10.r),
        ),
        child: Center(
          child: Icon(
            config["icon"] as IconData,
            size: 28.sp,
            color: mainColor,
          ),
        ),
      ),

      SizedBox(width: 8.w),

      // 🔹 Status text (and optional second line) NEXT to the square
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            displayLabel,
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 15.sp,
              fontWeight: FontWeight.w800,
              color: mainColor,
            ),
          ),

          if (bottomWidget != null) ...[
            SizedBox(height: 2.h),
            bottomWidget, 
          ],
        ],
      ),
    ],
  );
}











/// ⭐ Reusable status badge widget
/// Use this everywhere (home, orders, reports…)
/*Widget buildStatusBadge(String status) {
  final config = orderStatusConfig[status];

  // ✅ Fallback in case backend sends unknown status
  if (config == null) {
    return Text(
      status,
      style: TextStyle(
        fontSize: 14.sp,
        fontWeight: FontWeight.w600,
        color: Colors.grey,
      ),
    );
  }

  // ⭐ If we have a key, use .tr(), otherwise show raw status
  final String? key = statusTranslationKeys[status];
  final String displayLabel = key != null ? key.tr() : status;
// ⭐ Main color and box color taken from config
  final Color mainColor = config["color"] as Color;
  // If bgColor missing, fall back to a light version of mainColor
  final Color boxColor =
      (config["bgColor"] as Color?) ?? mainColor.withOpacity(0.12);

  return Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      // ⭐ Light rounded square with the icon inside (like your Figma)
      Container(
        width: 50.w,
        height: 50.w,
        decoration: BoxDecoration(
          color: boxColor,                 // light colored square
          borderRadius: BorderRadius.circular(10.r),
        ),
        child: Center(
          child: Icon(
            config["icon"] as IconData,
            size: 20.sp,
            color: mainColor,              // main status color
          ),
        ),
      ),

      SizedBox(width: 8.w),

      // ⭐ Status text (localized)
      Text(
        displayLabel,
        style: TextStyle(
          fontSize: 14.sp,
          fontWeight: FontWeight.w800,
          color: mainColor,
        ),
      ),
    ],
  );
}*/