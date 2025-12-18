import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:teryagapptry/constants/app_colors.dart';

/// 🔹 Custom reusable popup for confirmation or alerts.
/// You can change the title, subtitle, and button texts freely.
Future<void> showCustomPopup({
  required BuildContext context,

  // 🔸 Texts to customize per use
  String titleText = "",
  String subtitleText = "",
  String cancelText = "",
  String confirmText = "",

  // 🔸 Actions for buttons
  VoidCallback? onCancel,
  VoidCallback? onConfirm,

  // 🔸 Optional icon path (SVG)
  String iconAsset = 'assets/icons/question.svg',

  bool barrierDismissible = false,
}) {
  return showDialog(
    context: context,
    barrierDismissible: barrierDismissible,
    builder: (BuildContext dialogContext) {
      return Center(
        child: Material(
          color: Colors.transparent,
          child: Container(
            constraints: BoxConstraints(
              maxWidth: 331.w,
              minHeight: 160.h,
              maxHeight: 240.h, // ✅ prevents overflow
            ),
            padding: EdgeInsets.symmetric(horizontal: 18.w, vertical: 18.h),
            decoration: BoxDecoration(
              color: AppColors.appBackground,
              borderRadius: BorderRadius.circular(20.r),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.10),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min, // ✅ auto height adjustment
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // 🟡 Icon section
                Container(
                  width: 45.w,
                  height: 45.h,
                  decoration: BoxDecoration(
                    color:  Color(0xFFFFC26F),
                    borderRadius: BorderRadius.circular(30.r),
                  ),
                  child: Center(
                    child: SvgPicture.asset(
                      iconAsset,
                      width: 40.w,
                      height: 40.h,
                      colorFilter: const ColorFilter.mode(
                        Colors.white,
                        BlendMode.srcIn,
                      ),
                    ),
                  ),
                ),

                SizedBox(height: 12.h),

                // 🔹 Title
                Text(
                  titleText,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 16.sp,
                    fontWeight: FontWeight.w700,
                    color:  Color(0xFF4B4B4B),
                  ),
                ),

                SizedBox(height: 8.h),

                // 🔹 Subtitle
                Text(
                  subtitleText,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 12.sp,
                    color: AppColors.grayDisabled,
                  ),
                ),

                SizedBox(height: 16.h),

                // 🔹 Buttons
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Cancel Button
                    GestureDetector(
                      onTap: () {
                        Navigator.of(dialogContext).pop();
                        onCancel?.call();
                      },
                      child: Container(
                        width: 120.w,
                        height: 35.h,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(30.r),
                          border: Border.all(
                            color:  Color(0xFFD2D2D2),
                            width: 1,
                          ),
                        ),
                        child: Text(
                          cancelText,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 12.sp,
                            color: AppColors.grayDisabled,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),

                    SizedBox(width: 12.w),

                    // Confirm Button
                    GestureDetector(
                      onTap: () {
                        Navigator.of(dialogContext).pop();
                        onConfirm?.call();
                      },
                      child: Container(
                        width: 120.w,
                        height: 35.h,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(30.r),
                          border: Border.all(
                            color: AppColors.buttonRed,
                            width: 1,
                          ),
                        ),
                        child: Text(
                          confirmText,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 12.sp,
                            color: AppColors.buttonRed,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}
