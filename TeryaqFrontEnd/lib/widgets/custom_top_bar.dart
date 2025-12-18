import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:teryagapptry/constants/app_colors.dart';

class CustomTopBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final bool showBackButton;
  final VoidCallback? onMenuTap;
  final VoidCallback? onBackTap;

  const CustomTopBar({
    super.key,
    required this.title,
    this.showBackButton = false,
    this.onMenuTap,
    this.onBackTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.appHeader,//لون التوب بار 
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(17.r),//الريديس حق الزوايا
          bottomRight: Radius.circular(17.r),
        ),
      ),
      child: SafeArea(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 19.w, vertical: 10.h),//البادينق يمين ويسار
          child: Stack(
            alignment: Alignment.center,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  //Left (menu or back)
                  GestureDetector(
                    onTap: showBackButton
                        ? (onBackTap ?? () => Navigator.pop(context))
                        : onMenuTap,
                    child: Icon(
                      showBackButton ? Icons.arrow_back : Icons.menu,
                      color: const Color(0xFF11607E),
                      size: 24.w,
                    ),
                  ),

                  //Logo ترياق
                  GestureDetector(
                  child: Image.asset(
                    'assets/tglogo.png',
                    height: 27.h,
                  ),
                ),
              ],
            ),

              //center title
              Text(
                title,
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 25.sp,
                  fontWeight: FontWeight.w700,
                  color: AppColors.headingText,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Size get preferredSize => Size.fromHeight(90.h);//هذا الارتفاع حق التوب بار وعشان يناسب جميع مقاسات الجوالات
}
