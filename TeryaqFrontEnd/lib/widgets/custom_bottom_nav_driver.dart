import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:teryagapptry/constants/app_colors.dart';
import 'package:easy_localization/easy_localization.dart';

import '../features/driver/driver_home.dart';
import '../features/driver/driver_notification.dart';
import '../features/driver/driver_profile.dart';

class CustomBottomNavDriver extends StatelessWidget {
  final int currentIndex;
  final Function(int) onTap;

  const CustomBottomNavDriver({
    super.key,
    required this.currentIndex,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.backgroundGrey,
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
          onTap: (index) {
            onTap(index); // Call callback

            // Navigate only if not already on current
            if (index == 0 && currentIndex != 0) {
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (_) => const DriverHome()),
              );
            } else if (index == 1 && currentIndex != 1) {
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (_) => DriverNotification()),
              );
            } else if (index == 2 && currentIndex != 2) {
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (_) => const DriverProfile()),
              );
            }
          },
          selectedItemColor: AppColors.alertRed, // Active pink
          unselectedItemColor: AppColors.bodyText, // Inactive dark blue
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
                  currentIndex == 0
                      ? AppColors.alertRed
                      : AppColors.bodyText,
                  BlendMode.srcIn,
                ),
              ),
              label: "home".tr(),
            ),
            BottomNavigationBarItem(
              icon: SvgPicture.asset(
                'assets/icons/notification.svg', // Make sure you have this icon
                height: 27,
                colorFilter: ColorFilter.mode(
                  currentIndex == 1
                      ? AppColors.alertRed
                      : AppColors.bodyText,
                  BlendMode.srcIn,
                ),
              ),
              label: "notifications".tr(),
            ),
            BottomNavigationBarItem(
              icon: SvgPicture.asset(
                'assets/icons/profile.svg',
                height: 27,
                colorFilter: ColorFilter.mode(
                  currentIndex == 2
                      ? AppColors.alertRed
                      : AppColors.bodyText,
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
