// lib/features/hospital/hospital_home.dart

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:easy_localization/easy_localization.dart';

import 'package:teryagapptry/constants/app_colors.dart';
import 'package:teryagapptry/widgets/custom_top_bar.dart';
import 'package:teryagapptry/widgets/show_teryaq_menu.dart';

import 'package:teryagapptry/features/hospital/manage_patients.dart'
    as hospitalPatients;
import 'package:teryagapptry/features/hospital/manage_orders.dart'
    as hospitalOrders;
import 'package:teryagapptry/features/hospital/manage_prescriptions.dart';

import 'package:teryagapptry/services/hospital_service.dart';

class HospitalHome extends StatefulWidget {
  const HospitalHome({super.key});

  @override
  State<HospitalHome> createState() => _HospitalHomeState();
}

class _HospitalHomeState extends State<HospitalHome> {
  /// Uses the same baseUrl already defined inside HospitalService
  final HospitalService _hospitalService = HospitalService(
    baseUrl: HospitalService.baseUrl,
  );

  HospitalDashboardSummary? _dashboard;
  bool _isLoading = true;
  String? _errorMessage;

  /// Hospital name stored during login
  String get _hospitalNameFromLogin =>
      HospitalService.currentHospitalName ?? 'Hospital';

  @override
  void initState() {
    super.initState();
    _initDashboard();
  }

  /// Initialize dashboard after login using stored hospital_id
  Future<void> _initDashboard() async {
    final hospitalId = HospitalService.currentHospitalId;

    if (hospitalId == null) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'No hospital selected. Please log in again.';
      });
      return;
    }

    await _loadDashboard(hospitalId);
  }

  /// Fetch dashboard data from backend
  Future<void> _loadDashboard(String hospitalId) async {
    print("🏥 Dashboard refresh: hospitalId=$hospitalId");

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final data = await _hospitalService.getDashboard(hospitalId);

      print(
        "✅ Dashboard response: "
        "activePatients=${data.activePatients}, "
        "newPatientsToday=${data.newPatientsToday}, "
        "activePrescriptions=${data.activePrescriptions}, "
        "ordersWaitingApproval=${data.ordersWaitingApproval}",
      );

      setState(() {
        _dashboard = data;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = e.toString();
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget bodyChild;

    // Loading state
    if (_isLoading) {
      bodyChild = Center(
        child: Padding(
          padding: EdgeInsets.only(top: 200.h),
          child: const CircularProgressIndicator(),
        ),
      );
    }
    // Error state
    else if (_errorMessage != null) {
      bodyChild = Center(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 24.w, vertical: 200.h),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                tr('something_went_wrong'),
                style: TextStyle(
                  fontSize: 16.sp,
                  fontWeight: FontWeight.w600,
                  color: AppColors.alertRed,
                ),
                textAlign: TextAlign.center,
              ),
              SizedBox(height: 8.h),
              Text(
                _errorMessage!,
                style: TextStyle(fontSize: 12.sp, color: AppColors.detailText),
                textAlign: TextAlign.center,
              ),
              SizedBox(height: 16.h),
              ElevatedButton(
                onPressed: () {
                  final hospitalId = HospitalService.currentHospitalId;
                  if (hospitalId != null) {
                    _loadDashboard(hospitalId);
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.buttonBlue,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12.r),
                  ),
                  padding: EdgeInsets.symmetric(
                    horizontal: 24.w,
                    vertical: 10.h,
                  ),
                ),
                child: Text(
                  tr('retry'),
                  style: TextStyle(
                    fontSize: 14.sp,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }
    // Success state
    else {
      final dashboard = _dashboard!;

      final Map<String, dynamic> hospitalData = {
        'hospitalName': _hospitalNameFromLogin,
        'activePatients': dashboard.activePatients,
        'newPatientsToday': dashboard.newPatientsToday,
        'activePrescriptions': dashboard.activePrescriptions,
        'ordersWaitingApproval': dashboard.ordersWaitingApproval,
      };

      bodyChild = SingleChildScrollView(
        padding: EdgeInsets.symmetric(horizontal: 25.w, vertical: 90.h),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(height: 30.h),

            /// Welcome message
            Text(
              '${"welcome_back".tr()} 👋🏻',
              style: TextStyle(
                fontSize: 25.sp,
                fontWeight: FontWeight.w800,
                color: AppColors.headingText,
              ),
            ),
            SizedBox(height: 10.h),

            /// Display hospital name
            Text(
              hospitalData['hospitalName'],
              style: TextStyle(
                fontSize: 22.sp,
                fontWeight: FontWeight.w700,
                color: AppColors.detailText,
              ),
            ),
            SizedBox(height: 5.h),

            /// Subtitle
            Text(
              'what_would_you_like_to_do'.tr(),
              style: TextStyle(
                fontSize: 15.sp,
                fontWeight: FontWeight.w500,
                color: AppColors.bodyText,
              ),
            ),

            SizedBox(height: 35.h),

            /// Cards
            _buildManageCard(
              context,
              title: 'manage_patients'.tr(),
              subtitle1: 'total_active_patients'.tr(),
              value1: '${hospitalData['activePatients']}',
              subtitle2: 'new_patients_today'.tr(),
              value2: '${hospitalData['newPatientsToday']}',
              onAfterReturn: () async {
                final hospitalId = HospitalService.currentHospitalId;
                if (hospitalId != null) await _loadDashboard(hospitalId);
              },
            ),

            SizedBox(height: 18.h),

            _buildManageCard(
              context,
              title: 'manage_prescriptions'.tr(),
              subtitle1: 'total_active_prescriptions'.tr(),
              value1: '${hospitalData['activePrescriptions']}',
              onAfterReturn: () async {
                final hospitalId = HospitalService.currentHospitalId;
                if (hospitalId != null) await _loadDashboard(hospitalId);
              },
            ),

            SizedBox(height: 18.h),

            _buildManageCard(
              context,
              title: 'manage_orders'.tr(),
              subtitle1: 'orders_waiting_approval'.tr(),
              value1: '${hospitalData['ordersWaitingApproval']}',
              onAfterReturn: () async {
                final hospitalId = HospitalService.currentHospitalId;
                if (hospitalId != null) await _loadDashboard(hospitalId);
              },
            ),

            SizedBox(height: 40.h),
          ],
        ),
      );
    }

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: CustomTopBar(title: '', onMenuTap: () => showTeryaqMenu(context)),
      body: Stack(
        children: [
          /// Background header
          Container(
            height: 340.h,
            decoration: BoxDecoration(
              color: AppColors.appHeader,
              borderRadius: BorderRadius.only(
                bottomLeft: Radius.circular(90.r),
                bottomRight: Radius.circular(90.r),
              ),
            ),
          ),

          /// Main content
          bodyChild,
        ],
      ),
    );
  }
}

/// Build the dashboard cards (Patients / Orders / Prescriptions)
Widget _buildManageCard(
  BuildContext context, {
  required String title,
  required String subtitle1,
  required String value1,
  String? subtitle2,
  String? value2,
  Future<void> Function()? onAfterReturn,
}) {
  return Center(
    child: Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(horizontal: 18.w, vertical: 18.h),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16.r),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 6,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 18.sp,
                    fontWeight: FontWeight.w700,
                    color: AppColors.headingText,
                  ),
                ),
              ),

              GestureDetector(
                onTap: () async {
                  if (title == 'manage_patients'.tr()) {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const hospitalPatients.ManagePatients(),
                      ),
                    );
                  } else if (title == 'manage_orders'.tr()) {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const hospitalOrders.ManageOrders(),
                      ),
                    );
                  } else if (title == 'manage_prescriptions'.tr()) {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const ManagePrescriptionsScreen(),
                      ),
                    );
                  }

                  // ✅ refresh dashboard counts after returning
                  if (onAfterReturn != null) await onAfterReturn();
                },
                child: Row(
                  children: [
                    Text(
                      'view_all'.tr(),
                      style: TextStyle(
                        fontSize: 13.sp,
                        fontWeight: FontWeight.w600,
                        color: AppColors.buttonBlue,
                      ),
                    ),
                    SizedBox(width: 4.w),
                    Icon(
                      Icons.arrow_forward_ios_rounded,
                      size: 11.sp,
                      color: AppColors.buttonBlue,
                    ),
                  ],
                ),
              ),
            ],
          ),

          SizedBox(height: 14.h),

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                subtitle1,
                style: TextStyle(
                  fontSize: 12.sp,
                  fontWeight: FontWeight.w500,
                  color: AppColors.detailText,
                ),
              ),
              Text(
                value1,
                style: TextStyle(
                  fontSize: 12.sp,
                  fontWeight: FontWeight.w700,
                  color: AppColors.buttonRed,
                ),
              ),
            ],
          ),

          if (subtitle2 != null && value2 != null) ...[
            SizedBox(height: 10.h),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  subtitle2,
                  style: TextStyle(
                    fontSize: 12.sp,
                    fontWeight: FontWeight.w500,
                    color: AppColors.detailText,
                  ),
                ),
                Text(
                  value2,
                  style: TextStyle(
                    fontSize: 12.sp,
                    fontWeight: FontWeight.w700,
                    color: AppColors.buttonRed,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    ),
  );
}
