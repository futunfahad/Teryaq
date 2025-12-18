import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:teryagapptry/services/driver_service.dart';

import '../../widgets/custom_top_bar.dart';
import '../../widgets/custom_bottom_nav_driver.dart';
import '../../widgets/show_teryaq_menu.dart';
import '../../constants/app_colors.dart';

class DriverProfile extends StatefulWidget {
  const DriverProfile({super.key});

  @override
  State<DriverProfile> createState() => _DriverProfileState();
}

class _DriverProfileState extends State<DriverProfile> {
  bool loading = true;

  String name = "";
  String phone = "";
  String email = "";
  String nationalId = "";
  String hospitalName = "";

  @override
  void initState() {
    super.initState();
    _loadDriverProfile();
  }

  /// =====================================================
  ///  Load driver profile from FastAPI backend
  ///   GET /driver/me  (  DriverService)
  /// =====================================================
  Future<void> _loadDriverProfile() async {
    try {
      final data = await DriverService.getDriverProfile();

      setState(() {
        name = data["name"] ?? "Driver";
        phone = data["phone_number"] ?? "N/A";
        email = data["email"] ?? "N/A";
        nationalId = data["national_id"] ?? "";
        hospitalName = data["hospital_name"] ?? "";
        loading = false;
      });
    } catch (e) {
      print("Profile load error: $e");
      setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Color(0xFFD5F7FF),
        statusBarIconBrightness: Brightness.dark,
      ),
    );

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: PreferredSize(
        preferredSize: Size.fromHeight(90.h),
        child: CustomTopBar(
          title: tr("profile"),
          onMenuTap: () => showTeryaqMenu(context),
        ),
      ),
      bottomNavigationBar: CustomBottomNavDriver(
        currentIndex: 2,
        onTap: (index) {
        },
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : _buildBody(),
    );
  }

  Widget _buildBody() {
    return SingleChildScrollView(
      child: Column(
        children: [
          SizedBox(height: 30.h),
          _buildUserCard(),
          SizedBox(height: 12.h),
          _infoCard(
            title: "personal_information".tr(),
            items: [
              _infoItem(Icons.person, "name".tr(), name),
              _infoItem(Icons.badge, "national_id".tr(), nationalId),
              _infoItem(Icons.local_hospital, "hospital".tr(), hospitalName),
              _infoItem(Icons.phone, "mobile_number".tr(), phone),
              _infoItem(Icons.email_outlined, "email".tr(), email),
            ],
          ),
          SizedBox(height: 30.h),
        ],
      ),
    );
  }

  // ============================
  // 🔹 Profile Header Card
  // ============================
  Widget _buildUserCard() {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 23.w, vertical: 6.h),
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 66.w, vertical: 18.h),
        decoration: BoxDecoration(
          color: AppColors.cardBackground,
          borderRadius: BorderRadius.circular(14.r),
          boxShadow: AppColors.universalShadow,
        ),
        child: Column(
          children: [
            Text(
              name,
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 19.sp,
                fontWeight: FontWeight.w800,
                color: AppColors.buttonRed,
              ),
            ),
            SizedBox(height: 12.h),
            Text(
              "ID: $nationalId",
              style: TextStyle(
                fontSize: 14.sp,
                color: AppColors.bodyText,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ============================
  // 🔹 Info Card Container
  // ============================
  Widget _infoCard({
    required String title,
    required List<Widget> items,
  }) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 23.w, vertical: 6.h),
      child: Container(
        padding: EdgeInsets.all(16.w),
        decoration: BoxDecoration(
          color: AppColors.cardBackground,
          borderRadius: BorderRadius.circular(14.r),
          boxShadow: AppColors.universalShadow,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 18.sp,
                color: AppColors.headingText,
              ),
            ),
            SizedBox(height: 10.h),
            ...items,
          ],
        ),
      ),
    );
  }

  // ============================
  // 🔹 Info Row Item
  // ============================
  Widget _infoItem(IconData icon, String label, String value) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 5.h),
      child: Row(
        children: [
          Icon(icon, size: 20.w, color: AppColors.bodyText),
          SizedBox(width: 14.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13.sp,
                    color: AppColors.bodyText,
                  ),
                ),
                SizedBox(height: 1.h),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 13.sp,
                    color: AppColors.detailText,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
