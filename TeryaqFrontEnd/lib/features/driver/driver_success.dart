import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:easy_localization/easy_localization.dart';

import '../../constants/app_colors.dart';
import 'driver_home.dart';

class DriverSuccess extends StatefulWidget {
  const DriverSuccess({super.key});

  @override
  State<DriverSuccess> createState() => _DriverSuccessState();
}

class _DriverSuccessState extends State<DriverSuccess> {
  @override
  void initState() {
    super.initState();
    // after 4 second return to home
    Future.delayed(const Duration(seconds: 4), () {
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => const DriverHome(),
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 24.w),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // ✅ Success Image
              Image.asset(
                'assets/icons/tick.png',
                height: 170.h,
                width: 170.w,
              ),

              SizedBox(height: 24.h),

              // 🎯 Success Title (heading text color)
              Text(
                'success_title'.tr(),
                style: TextStyle(
                  fontSize: 33.sp,
                  fontWeight: FontWeight.bold,
                  color: AppColors.bodyText,
                ),
                textAlign: TextAlign.center,
              ),

              SizedBox(height: 12.h),

              // 🎯 Success Subtitle (heading text color)
              Text(
                'success_subtitle'.tr(),
                style: TextStyle(
                  fontSize: 18.sp,
                  fontWeight: FontWeight.w500,
                  color: AppColors.bodyText,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
