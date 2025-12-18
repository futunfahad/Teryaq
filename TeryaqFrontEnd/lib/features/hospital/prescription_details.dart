// lib/features/hospital/prescription_detail_screen.dart
// ===================================================================
// PRESCRIPTION DETAIL SCREEN
// Displays:
//  - Patient information (name, gender, DOB, national ID, phone)
//  - Prescription details (medicine, doctor, hospital, instructions, dates)
// Backend is accessed through HospitalService (no hard-coded URLs)
// ===================================================================

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../constants/app_colors.dart';
import '../../widgets/custom_top_bar.dart';
import 'package:teryagapptry/services/hospital_service.dart';

class PrescriptionDetailScreen extends StatefulWidget {
  final String prescriptionCode;

  const PrescriptionDetailScreen({super.key, required this.prescriptionCode});

  @override
  State<PrescriptionDetailScreen> createState() =>
      _PrescriptionDetailScreenState();
}

class _PrescriptionDetailScreenState extends State<PrescriptionDetailScreen> {
  PrescriptionDetailModel? _detail;

  bool _isLoading = true;
  String? _errorMessage;

  // ================================================================
  // LIFECYCLE
  // ================================================================
  @override
  void initState() {
    super.initState();
    _fetchDetails();
  }

  // Fetch full prescription details from backend
  Future<void> _fetchDetails() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final api = HospitalService();
      final result = await api.getPrescriptionDetail(widget.prescriptionCode);

      setState(() {
        _detail = result;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = e.toString();
        _isLoading = false;
      });
    }
  }

  // ================================================================
  // SAFE GETTERS + NORMALIZERS
  // ================================================================

  String get _patientName => _detail?.patientName ?? "-";
  String get _patientNationalId => _detail?.patientNationalId ?? "-";
  String get _patientPhone => _detail?.patientPhoneNumber ?? "-";

  // FIXED GENDER → English or Arabic depending on current locale
  String get _patientGender {
    final g = _detail?.patientGender ?? "";
    if (g.isEmpty) return "-";

    final lower = g.toLowerCase();

    if (lower == "m" || lower == "male") {
      return context.locale.languageCode == "ar" ? "ذكر" : "Male";
    }
    if (lower == "f" || lower == "female") {
      return context.locale.languageCode == "ar" ? "أنثى" : "Female";
    }

    return g; // fallback for unknown values
  }

  // Force date format → English always
  String _formatDate(DateTime? d) {
    if (d == null) return "-";
    return DateFormat('yyyy-MM-dd', 'en').format(d);
  }

  String get _patientDob => _formatDate(_detail?.patientBirthDate);
  String get _validUntil => _formatDate(_detail?.validUntil);

  String get _medicationName => _detail?.medicationName ?? "-";
  String get _doctorName => _detail?.prescribingDoctor ?? "-";
  String get _hospitalName => _detail?.hospitalName ?? "-";
  String get _instructions => _detail?.instructions ?? "-";
  String get _refillLimit =>
      _detail?.refillLimit == null ? "-" : _detail!.refillLimit.toString();

  String get _prescriptionId => _detail?.prescriptionId ?? "-";

  // ================================================================
  // UI
  // ================================================================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: CustomTopBar(title: "prescription".tr(), showBackButton: true),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null) {
      return _buildError();
    }

    if (_detail == null) {
      return Center(
        child: Text(
          "no_data_found".tr(),
          style: TextStyle(fontSize: 14.sp, color: Colors.grey[700]),
        ),
      );
    }

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: EdgeInsets.symmetric(horizontal: 25.w, vertical: 30.h),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _patientInfoCard(),
          SizedBox(height: 20.h),
          _prescriptionCard(),
          SizedBox(height: 40.h),
        ],
      ),
    );
  }

  // ================================================================
  // ERROR UI
  // ================================================================
  Widget _buildError() {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 25.w),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            "failed_to_load_prescription".tr(),
            style: TextStyle(
              fontSize: 16.sp,
              fontWeight: FontWeight.w600,
              color: Colors.red,
            ),
            textAlign: TextAlign.center,
          ),
          SizedBox(height: 10.h),
          Text(
            _errorMessage!,
            style: TextStyle(fontSize: 12.sp, color: Colors.grey[700]),
            textAlign: TextAlign.center,
          ),
          SizedBox(height: 16.h),
          TextButton(
            onPressed: _fetchDetails,
            child: Text(
              "retry".tr(),
              style: TextStyle(fontSize: 14.sp, color: AppColors.buttonBlue),
            ),
          ),
        ],
      ),
    );
  }

  // ================================================================
  // CARD WRAPPER
  // ================================================================
  Widget _card({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(horizontal: 24.w, vertical: 17.h),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15.r),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1C0E5D7C),
            blurRadius: 11,
            spreadRadius: 1,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: child,
    );
  }

  // ================================================================
  // PATIENT INFORMATION CARD
  // ================================================================
  Widget _patientInfoCard() => _card(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _title("patient_information".tr()),
        SizedBox(height: 10.h),
        _row("patient_name_label".tr(), _patientName),
        _row("gender_label".tr(), _patientGender),
        _row("national_id_label".tr(), _patientNationalId),
        _row("date_of_birth_label".tr(), _patientDob),
        _row("phone_number_label".tr(), _patientPhone),
      ],
    ),
  );

  // ================================================================
  // PRESCRIPTION INFORMATION CARD
  // ================================================================
  Widget _prescriptionCard() => _card(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _title("prescription_section".tr()),
        SizedBox(height: 12.h),

        Row(
          children: [
            Container(
              width: 64.w,
              height: 64.h,
              decoration: BoxDecoration(
                color: const Color(0xFFE4EEF2),
                borderRadius: BorderRadius.circular(12.r),
              ),
              child: Center(
                child: SvgPicture.asset(
                  'assets/icons/CapsuleandPill.svg',
                  width: 40.w,
                  height: 40.h,
                  color: AppColors.bodyText,
                ),
              ),
            ),
            SizedBox(width: 12.w),
            Expanded(
              child: Text(
                _medicationName,
                style: TextStyle(
                  fontSize: 16.sp,
                  fontWeight: FontWeight.w700,
                  color: AppColors.buttonRed,
                ),
              ),
            ),
          ],
        ),

        SizedBox(height: 14.h),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 40.w),
          child: Container(height: 1.h, color: const Color(0xFFE6E6E6)),
        ),
        SizedBox(height: 14.h),

        _row("prescribing_doctor_label".tr(), _doctorName),
        _row("hospital_label".tr(), _hospitalName),
        _row("instructions_label".tr(), _instructions),
        _row("valid_until_label".tr(), _validUntil),
        _row("refill_limit_label".tr(), _refillLimit),
        _row("prescription_id_label".tr(), _prescriptionId),
      ],
    ),
  );

  // ================================================================
  // SHARED UI HELPERS
  // ================================================================
  Widget _title(String t) => Text(
    t,
    style: TextStyle(
      fontSize: 18.sp,
      fontWeight: FontWeight.w700,
      color: AppColors.headingText,
    ),
  );

  Widget _row(String label, String value) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 6.h),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140.w,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13.sp,
                fontWeight: FontWeight.w600,
                color: AppColors.bodyText,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 13.sp,
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
