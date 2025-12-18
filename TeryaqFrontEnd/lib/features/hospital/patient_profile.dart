// lib/features/hospital/patient_profile.dart
// ===============================================================
// BACKEND MODEL EXPECTATIONS (EDIT IF YOUR API CHANGES)
// ===============================================================
//
// PATIENT PROFILE MODEL:
// {
//   "name": String,
//   "patient_id": String,
//   "gender": String,
//   "birth_date": String? (ISO string),
//   "phone": String,
//   "email": String?,
//   "status": "Active" | "Inactive"
// }
//
// PRESCRIPTIONS LIST:
// [
//   {
//     "medicine_name": String,
//     "prescription_id": String,
//     "status": "Active" | "Expired" | "Invalid",
//     "refill_limit": String,
//     "start_date": String,
//     "end_date": String
//   }
// ]
//
// ===============================================================

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:intl/intl.dart';

import '../../constants/app_colors.dart';
import '../../widgets/custom_top_bar.dart';
import 'package:teryagapptry/services/hospital_service.dart';

class PatientProfileScreen extends StatefulWidget {
  final String patientId;

  const PatientProfileScreen({super.key, required this.patientId});

  @override
  State<PatientProfileScreen> createState() => _PatientProfileScreenState();
}

class _PatientProfileScreenState extends State<PatientProfileScreen> {
  PatientProfileModel? _profile;
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  // ---------------------------------------------------
  // Fetch patient profile from backend
  // ---------------------------------------------------
  Future<void> _loadProfile() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final api = HospitalService(); // ✅ NO IP HERE

      debugPrint("🔍 Loading profile for patient: ${widget.patientId}");

      final profile = await api.getPatientProfile(widget.patientId);

      debugPrint("✅ Profile loaded: ${profile.name}");

      setState(() {
        _profile = profile;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint("❌ Error loading profile: $e");
      setState(() {
        _isLoading = false;
        _errorMessage = e.toString();
      });
    }
  }

  // ---------------------------------------------------
  // Card base decoration
  // ---------------------------------------------------
  BoxDecoration _cardShadow() => BoxDecoration(
    color: Colors.white,
    borderRadius: BorderRadius.circular(16.r),
    boxShadow: [
      BoxShadow(
        color: const Color(0x1C0E5D7C),
        blurRadius: 11,
        spreadRadius: 1,
        offset: const Offset(0, 4),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: CustomTopBar(title: "patient_profile".tr(), showBackButton: true),
      body: SingleChildScrollView(
        padding: EdgeInsets.symmetric(horizontal: 25.w, vertical: 25.h),
        child: _buildBody(),
      ),
    );
  }

  // ---------------------------------------------------
  // Main body rendering
  // ---------------------------------------------------
  Widget _buildBody() {
    if (_isLoading) {
      return Center(
        child: Padding(
          padding: EdgeInsets.only(top: 40.h),
          child: const CircularProgressIndicator(),
        ),
      );
    }

    if (_errorMessage != null) {
      return Column(
        children: [
          SizedBox(height: 30.h),
          Text(
            'Failed to load patient profile',
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 14.sp,
              color: Colors.red,
              fontWeight: FontWeight.w600,
            ),
          ),
          SizedBox(height: 8.h),
          Text(
            _errorMessage!,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 12.sp,
              color: Colors.grey[700],
            ),
          ),
          SizedBox(height: 16.h),
          TextButton(
            onPressed: _loadProfile,
            child: Text(
              'Retry',
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 13.sp,
                color: AppColors.buttonBlue,
              ),
            ),
          ),
        ],
      );
    }

    final p = _profile!;
    final dateFmt = DateFormat('dd MMM yyyy', 'en'); // ⭐ Always English dates

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ================== PATIENT INFORMATION ==================
        _card(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _sectionTitle("patient_information".tr()),
              SizedBox(height: 12.h),

              _infoRow("patient_name".tr(), p.name),
              _infoRow("gender".tr(), p.gender ?? "—"),
              _infoRow("national_id".tr(), p.nationalId),
              _infoRow(
                "date_of_birth".tr(),
                p.birthDate != null ? dateFmt.format(p.birthDate!) : "—",
              ),
              _infoRow("phone_number".tr(), p.phoneNumber ?? "—"),
              _infoRow("email".tr(), p.email ?? "—"),
              _infoRow("status".tr(), p.status.toLowerCase().tr()),
            ],
          ),
        ),

        SizedBox(height: 25.h),

        // ================== PRESCRIPTIONS ==================
        _card(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _sectionTitle("prescriptions".tr()),
              SizedBox(height: 12.h),

              if (p.prescriptions.isEmpty)
                Text(
                  "no_prescriptions".tr(),
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 13.sp,
                    color: AppColors.detailText,
                  ),
                )
              else
                ...p.prescriptions.map((presc) {
                  final start = presc.startDate != null
                      ? dateFmt.format(presc.startDate!)
                      : "—";

                  final end = presc.endDate != null
                      ? dateFmt.format(presc.endDate!)
                      : "—";

                  return Padding(
                    padding: EdgeInsets.only(bottom: 12.h),
                    child: _prescriptionCard(
                      presc.medicineName,
                      presc.prescriptionId,
                      presc.status,
                      presc.refillLimitText ?? "",
                      start,
                      end,
                    ),
                  );
                }),
            ],
          ),
        ),

        SizedBox(height: 50.h),
      ],
    );
  }

  // ---------------------------------------------------
  // Card wrapper
  // ---------------------------------------------------
  Widget _card(Widget child) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(horizontal: 18.w, vertical: 16.h),
      decoration: _cardShadow(),
      child: child,
    );
  }

  // ---------------------------------------------------
  // Section title
  // ---------------------------------------------------
  Widget _sectionTitle(String text) {
    return Text(
      text,
      softWrap: true,
      overflow: TextOverflow.visible,
      style: TextStyle(
        fontFamily: 'Poppins',
        color: AppColors.headingText,
        fontSize: 18.sp,
        fontWeight: FontWeight.w700,
      ),
    );
  }

  // ---------------------------------------------------
  // Key-value row
  // ---------------------------------------------------
  Widget _infoRow(String label, String value) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 4.h),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120.w,
            child: Text(
              label,
              style: TextStyle(
                fontFamily: 'Poppins',
                color: Color(0xFF11607E),
                fontSize: 13.sp,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontFamily: 'Poppins',
                color: AppColors.detailText,
                fontSize: 13.sp,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------
  // Prescription card section
  // ---------------------------------------------------
  Widget _prescriptionCard(
    String medName,
    String id,
    String status,
    String refill,
    String start,
    String end,
  ) {
    final isActive = status.toLowerCase() == "active";

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            // ICON
            Container(
              width: 40.w,
              height: 40.h,
              decoration: BoxDecoration(
                color: Color(0xFFD5F7FF),
                borderRadius: BorderRadius.circular(8.r),
              ),
              child: Padding(
                padding: EdgeInsets.all(8.w),
                child: SvgPicture.asset(
                  'assets/icons/prescription.svg',
                  colorFilter: const ColorFilter.mode(
                    Color(0xFF488099),
                    BlendMode.srcIn,
                  ),
                ),
              ),
            ),
            SizedBox(width: 12.w),

            // NAME + STATUS
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    medName,
                    softWrap: true,
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 13.sp,
                      fontWeight: FontWeight.w700,
                      color: AppColors.headingText,
                    ),
                  ),
                  SizedBox(height: 4.h),
                  Text(
                    id,
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      color: Color(0xFF4B4B4B),
                      fontSize: 12.sp,
                    ),
                  ),
                ],
              ),
            ),

            // STATUS LABEL
            Text(
              status.toLowerCase().tr(),
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 13.sp,
                fontWeight: FontWeight.w700,
                color: isActive ? Color(0xFF137713) : Color(0xFFCC0000),
              ),
            ),
          ],
        ),

        SizedBox(height: 10.h),

        _detailRow("refill_limit".tr(), refill),
        _detailRow("start_date".tr(), start),
        _detailRow("end_date".tr(), end),
      ],
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 2.h),
      child: Row(
        children: [
          SizedBox(
            width: 120.w,
            child: Text(
              label,
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 12.sp,
                color: Color(0xFF11607E),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 12.sp,
                fontWeight: FontWeight.w500,
                color: AppColors.detailText,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
