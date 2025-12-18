import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:teryagapptry/constants/app_colors.dart';
import 'package:easy_localization/easy_localization.dart';

class CustomBottomNavBar extends StatelessWidget {
  final int currentIndex;
  final Function(int) onTap;

  const CustomBottomNavBar({
    super.key,
    required this.currentIndex,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.backgroundGrey, // اللون السماوي الفاتح جدًا مثل الصورة
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(28),
          topRight: Radius.circular(28),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 10,
            spreadRadius: 2,
            offset: Offset(0, -2),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(28),
          topRight: Radius.circular(28),
        ),
        child: BottomNavigationBar(
          type: BottomNavigationBarType.fixed,
          backgroundColor: AppColors.backgroundGrey, 
          elevation: 0,
          currentIndex: currentIndex,
          onTap: onTap,
          selectedItemColor: AppColors.alertRed, // الوردي للأيقونة المحددة
          unselectedItemColor: AppColors.bodyText, // أزرق غامق للأيقونات الباقية
          selectedLabelStyle: const TextStyle(
            fontFamily: 'Poppins',
            fontWeight: FontWeight.w600,
            fontSize: 12,
          ),
          unselectedLabelStyle: const TextStyle(
            fontFamily: 'Poppins',
            fontWeight: FontWeight.w600,
            fontSize: 12,
          ),
          items: [
            BottomNavigationBarItem(
              icon: SvgPicture.asset(
                'assets/icons/home.svg',
                height: 27,
                colorFilter: ColorFilter.mode(
                  currentIndex == 0 ? AppColors.alertRed : AppColors.bodyText,
                  BlendMode.srcIn,
                ),
              ),
              label: "home".tr(),
            ),
            BottomNavigationBarItem(
              icon: SvgPicture.asset(
                'assets/icons/prescription.svg',
                height: 27,
                colorFilter: ColorFilter.mode(
                  currentIndex == 1 ? AppColors.alertRed : AppColors.bodyText,
                  BlendMode.srcIn,
                ),
              ),
              label: "prescriptions".tr(),
            ),
            BottomNavigationBarItem(
              icon: SvgPicture.asset(
                'assets/icons/order.svg',
                height: 27,
                colorFilter: ColorFilter.mode(
                  currentIndex == 2 ? AppColors.alertRed : AppColors.bodyText,
                  BlendMode.srcIn,
                ),
              ),
              label: "orders".tr(),
            ),
            BottomNavigationBarItem(
              icon: SvgPicture.asset(
                'assets/icons/profile.svg',
                height: 27,
                colorFilter: ColorFilter.mode(
                  currentIndex == 3 ? AppColors.alertRed : AppColors.bodyText,
                  BlendMode.srcIn,
                ),
              ),
              label: "profile".tr(),
            ),
          ],
        ),
      ),
    );
  }
}
