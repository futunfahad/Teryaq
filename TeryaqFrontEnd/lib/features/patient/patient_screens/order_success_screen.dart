import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:easy_localization/easy_localization.dart';

import 'patient_home.dart'; // ⭐
import 'package:teryagapptry/constants/app_colors.dart';

class OrderSuccessScreen extends StatelessWidget {
  const OrderSuccessScreen({super.key});

  @override
  Widget build(BuildContext context) {
    Future.delayed(const Duration(seconds: 2), () {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => PatientHome(initialIndex: 2), // 👈 Orders tab
        ),
      );
    });

    return Scaffold(
      backgroundColor: AppColors.appBackground,
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.check_circle_outline_outlined,
                color: AppColors.bigIcons,
                size: 270.w,
              ),

              SizedBox(height: 24.h),

              Text(
                "success".tr(),
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 40.sp,
                  fontWeight: FontWeight.w800,
                  color: AppColors.bodyText,
                ),
              ),

              SizedBox(height: 8.h),

              Text(
                "success_message".tr(),
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 15.sp,
                  fontWeight: FontWeight.w500,
                  color: AppColors.bodyText,
                ),
              ),

              SizedBox(height: 6.h),

              Text(
                "redirect_message".tr(),
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 12.sp,
                  color: AppColors.detailText,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}


// تم تغير اللغه 