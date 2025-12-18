// lib/features/patient/patient_screens/patient_profile.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:easy_localization/easy_localization.dart';

import '../patient_location_screen.dart';
import 'package:teryagapptry/widgets/custom_top_bar.dart';
import 'package:teryagapptry/widgets/show_teryaq_menu.dart';
import 'package:teryagapptry/constants/app_colors.dart';

// Backend service
import 'package:teryagapptry/services/patient_service.dart';

class PatientProfile extends StatefulWidget {
  const PatientProfile({super.key});

  @override
  State<PatientProfile> createState() => _PatientProfileState();
}

class _PatientProfileState extends State<PatientProfile> {
  // UI state
  bool _isLoading = true; // start loading immediately to avoid fake-data flash
  String? _errorMessage;

  // ✅ Prevent showing any placeholder/dummy profile before first backend load
  bool _hasLoadedProfile = false;

  /// Patient data map backing the UI (updated from backend)
  /// NOTE: empty initial values → no fake data flash.
  Map<String, String> patientData = {
    "name": "",
    "gender": "",
    "dob": "",
    "national_id": "",
    "mobile": "",
    "email": "",
    "marital_status": "",
    "address": "",
    "primaryhospital": "",
  };

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  /// Loads current patient profile from backend using PatientService
  /// and updates patientData map used by the UI.
  Future<void> _loadProfile() async {
    try {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });

      final data = await PatientService.fetchCurrentPatient();
      if (!mounted) return;

      if (data == null) {
        setState(() {
          _hasLoadedProfile = true; // allow UI to render (empty) + show error
          _errorMessage = "Profile data not available.";
        });
        return;
      }

      setState(() {
        patientData = {
          "name": data["name"]?.toString() ?? "",
          "gender": data["gender"]?.toString() ?? "female",

          // Adjust formatting if your backend returns ISO date
          "dob": data["birth_date"]?.toString() ?? "",

          "national_id": data["national_id"]?.toString() ?? "",
          "mobile": data["phone_number"]?.toString() ?? "",
          "email": data["email"]?.toString() ?? "",

          "marital_status": data["marital_status"]?.toString() ?? "single",

          // Address: if you have city, you can optionally concat it
          "address": _buildFullAddressFromBackend(data) ?? "",

          "primaryhospital":
              data["primary_hospital"]?.toString() ??
              data["hospital_name"]?.toString() ??
              "",
        };

        _hasLoadedProfile = true; // ✅ first real load completed
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = e.toString();
        _hasLoadedProfile = true; // allow UI to render (empty) + show error
      });
    } finally {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
      });
    }
  }

  static String? _buildFullAddressFromBackend(Map<String, dynamic> data) {
    final addr = data["address"]?.toString() ?? "";
    final city = data["city"]?.toString() ?? "";
    if (addr.isEmpty && city.isEmpty) return null;
    if (addr.isNotEmpty && city.isNotEmpty) return "$addr, $city";
    return addr.isNotEmpty ? addr : city;
  }

  @override
  Widget build(BuildContext context) {
    // Same status bar style as other screens
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Color(0xFFD5F7FF),
        statusBarIconBrightness: Brightness.dark,
      ),
    );

    final bool hideContentUntilLoaded = !_hasLoadedProfile;

    return Scaffold(
      backgroundColor: Colors.white,

      // Top bar with 3-lines menu
      appBar: PreferredSize(
        preferredSize: Size.fromHeight(90.h),
        child: CustomTopBar(
          title: "profile_for_topbar".tr(),
          onMenuTap: () => showTeryaqMenu(context),
        ),
      ),

      body: Stack(
        children: [
          // ✅ Keep the exact same UI, but hide it until first real profile load
          Opacity(
            opacity: hideContentUntilLoaded ? 0.0 : 1.0,
            child: SingleChildScrollView(
              child: Column(
                children: [
                  SizedBox(height: 30.h),

                  // User Summary Card
                  _buildUserCard(patientData),

                  SizedBox(height: 12.h),

                  // Personal Info Card
                  _infoCard(
                    title: "personal_information".tr(),
                    items: [
                      _infoItem(
                        Icons.phone,
                        "mobile_number".tr(),
                        patientData["mobile"] ?? "",
                      ),
                      _infoItem(
                        Icons.email_outlined,
                        "email".tr(),
                        patientData["email"] ?? "",
                        withArrow: true,
                      ),
                      _infoItem(
                        Icons.favorite_border,
                        "marital_status".tr(),
                        (patientData["marital_status"] ?? "").tr(),
                      ),
                    ],
                  ),

                  SizedBox(height: 12.h),

                  // Location & Hospital Center card
                  _infoCard(
                    title: "location_and_hospital".tr(),
                    items: [
                      _infoItem(
                        Icons.location_on_outlined,
                        "address".tr(),
                        patientData["address"] ?? "",
                        withArrow: true,
                        onTap: () async {
                          // Open location screen and wait for save result
                          final changed = await Navigator.push<bool>(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const PatientLocationScreen(),
                            ),
                          );

                          // If location screen saved successfully, refresh profile
                          if (changed == true) {
                            await _loadProfile();
                          }
                        },
                      ),
                      _infoItem(
                        Icons.local_hospital_outlined,
                        "primary_hospital_center".tr(),
                        patientData["primaryhospital"] ?? "",
                      ),
                    ],
                  ),

                  SizedBox(height: 30.h),
                ],
              ),
            ),
          ),

          // Loading overlay
          if (_isLoading)
            Positioned.fill(
              child: Container(
                color: Colors.black.withOpacity(0.08),
                child: const Center(child: CircularProgressIndicator()),
              ),
            ),

          // Error message (optional)
          if (_errorMessage != null && !_isLoading)
            Positioned(
              left: 20.w,
              right: 20.w,
              bottom: 18.h,
              child: Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.alertRed),
              ),
            ),
        ],
      ),
    );
  }

  // =========================
  // UI Helpers
  // =========================

  static Widget _buildUserCard(Map<String, String> data) {
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
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              data["name"] ?? "",
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 19.sp,
                fontWeight: FontWeight.w800,
                color: AppColors.buttonRed,
              ),
            ),
            SizedBox(height: 12.h),

            _infoRow("${"gender".tr()}: ", (data["gender"] ?? "female").tr()),
            _infoRow("${"date_of_birth".tr()}: ", data["dob"] ?? ""),
            _infoRow("${"national_id".tr()}: ", data["national_id"] ?? ""),
          ],
        ),
      ),
    );
  }

  static Widget _infoRow(String label, String value) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 4.h),
      child: Row(
        children: [
          SizedBox(
            width: 135.w,
            child: Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: AppColors.bodyText,
                fontSize: 13.sp,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 13.sp,
                color: AppColors.detailText,
              ),
            ),
          ),
        ],
      ),
    );
  }

  static Widget _infoCard({
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

  static Widget _infoItem(
    IconData icon,
    String label,
    String value, {
    bool withArrow = false,
    VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: 5.h),
        child: Row(
          children: [
            Icon(icon, color: AppColors.bodyText, size: 21.w),
            SizedBox(width: 10.w),
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
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            if (withArrow)
              const Icon(
                Icons.arrow_forward_ios,
                size: 13,
                color: Colors.black54,
              ),
          ],
        ),
      ),
    );
  }
}
