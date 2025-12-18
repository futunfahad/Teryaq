// lib/features/hospital/manage_patients.dart

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:easy_localization/easy_localization.dart';

import '../../constants/app_colors.dart';
import '../../widgets/custom_top_bar.dart';
import 'add_patient.dart';
import 'patient_profile.dart';

// Backend service + models
import 'package:teryagapptry/services/hospital_service.dart';

/// ===================================================================
///  🧑‍⚕️ MANAGE PATIENTS SCREEN (Hospital)
///  - Lists patients from backend
///  - Filter: All / Active / Inactive
///  - Search by national ID or name (handled by backend)
///  - Add new patient
///  - View patient profile
///  - Soft-remove patient (status → inactive)
/// ===================================================================
class ManagePatients extends StatefulWidget {
  const ManagePatients({super.key});

  @override
  State<ManagePatients> createState() => _ManagePatientsState();
}

class _ManagePatientsState extends State<ManagePatients> {
  /// Current status filter (sent directly to backend):
  /// "All" | "Active" | "Inactive"
  String selectedFilter = "All";

  /// Local search query (sent as `search` to backend)
  String searchQuery = "";

  // ---------------------------------------------------
  // Backend state
  // ---------------------------------------------------
  List<PatientModel> patients = [];
  bool _isLoading = true;
  String? _errorMessage;

  // ---------------------------------------------------
  // Shared card shadow style
  // ---------------------------------------------------
  BoxDecoration _shadowBox() => BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16.r),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0E5D7C).withOpacity(0.11),
            blurRadius: 11,
            spreadRadius: 1,
            offset: const Offset(0, 4),
          ),
        ],
      );

  // ---------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------
  @override
  void initState() {
    super.initState();
    _loadPatients(); // Initial fetch from backend
  }

  // ---------------------------------------------------
  // API: load patients from backend according to filter + search
  // ---------------------------------------------------
  Future<void> _loadPatients() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final hospitalId = HospitalService.currentHospitalId;
      if (hospitalId == null || hospitalId.isEmpty) {
        throw Exception('Hospital ID is not set. Please login first.');
      }

      // ✅ No IP here, baseUrl is handled inside HospitalService
      final api = HospitalService();

      // Backend expects "All" | "Active" | "Inactive"
      final String statusParam = selectedFilter;
      final String? searchParam =
          searchQuery.trim().isEmpty ? null : searchQuery.trim();

      final list = await api.getPatients(
        hospitalId: hospitalId,
        status: statusParam,
        search: searchParam,
      );

      setState(() {
        patients = list;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = e.toString();
      });
    }
  }

  // ---------------------------------------------------
  // API: mark patient as inactive (soft delete)
  // ---------------------------------------------------
  Future<void> _removePatient(PatientModel patient) async {
    try {
      // ✅ No IP here, baseUrl is handled inside HospitalService
      final api = HospitalService();

      await api.updatePatientStatus(
        patientId: patient.patientId,
        status: 'inactive',
      );

      // Reload list from backend to reflect updated status
      await _loadPatients();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Failed to remove patient',
            style: TextStyle(fontSize: 12.sp),
          ),
        ),
      );
    }
  }

  // ---------------------------------------------------
  // UI
  // ---------------------------------------------------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,

      appBar: CustomTopBar(title: "patients".tr(), showBackButton: true),

      body: SingleChildScrollView(
        physics: const ClampingScrollPhysics(),
        child: Padding(
          padding: EdgeInsets.only(top: 30.h, left: 25.w, right: 25.w),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ----------------------- FILTER ROW -----------------------
              Row(
                mainAxisAlignment: MainAxisAlignment.start,
                children: [
                  Text(
                    "filter".tr(),
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      color: const Color(0xFF013A3C),
                      fontSize: 14.sp,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  SizedBox(width: 12.w),
                  _filterButton("All"),
                  SizedBox(width: 20.w),
                  _filterButton("Active"),
                  SizedBox(width: 12.w),
                  _filterButton("Inactive"),
                ],
              ),

              SizedBox(height: 20.h),

              // ----------------------- SEARCH BAR -----------------------
              Container(
                height: 41.h,
                width: double.infinity,
                decoration: _shadowBox().copyWith(
                  borderRadius: BorderRadius.circular(20.r),
                ),
                child: TextField(
                  // Local state update only, backend fetch on submit
                  onChanged: (v) => setState(() => searchQuery = v),

                  // When user presses "Search" on keyboard, trigger backend
                  onSubmitted: (_) => _loadPatients(),

                  textAlignVertical: TextAlignVertical.center,
                  strutStyle: StrutStyle(fontSize: 17.sp, height: 1.2),

                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 17.sp,
                    color: const Color(0xFF11607E),
                  ),

                  decoration: InputDecoration(
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(vertical: 8.h),
                    prefixIcon: Icon(
                      Icons.search,
                      color: const Color(0xFF11607E),
                      size: 22.sp,
                    ),
                    hintText: "search_patient".tr(),
                    hintStyle: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 15.sp,
                      color: const Color(0x806F8FA0),
                    ),
                    border: InputBorder.none,
                  ),
                ),
              ),

              SizedBox(height: 25.h),

              // ----------------------- ADD NEW PATIENT BUTTON -----------------------
              Center(
                child: Container(
                  width: 232.w,
                  height: 44.h,
                  decoration: BoxDecoration(
                    color: const Color(0xFF4F869D),
                    borderRadius: BorderRadius.circular(12.r),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0x1C0E5D7C),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: TextButton(
                    onPressed: () async {
                      final result = await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const AddPatientScreen(),
                        ),
                      );

                      // Handle different return types from AddPatientScreen
                      if (result != null) {
                        setState(() {
                          if (result is PatientModel) {
                            patients.insert(0, result);
                          } else if (result is Map<String, dynamic>) {
                            patients.insert(
                              0,
                              PatientModel.fromJson(result),
                            );
                          }
                        });
                      }
                    },
                    child: Text(
                      "add_new_patient".tr(),
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        color: Colors.white,
                        fontSize: 13.sp,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),

              SizedBox(height: 30.h),

              // ----------------------- LOADING / ERROR / LIST -----------------------
              if (_isLoading)
                Center(
                  child: Padding(
                    padding: EdgeInsets.only(top: 40.h),
                    child: const CircularProgressIndicator(),
                  ),
                )
              else if (_errorMessage != null)
                Padding(
                  padding: EdgeInsets.only(top: 40.h),
                  child: Column(
                    children: [
                      Text(
                        'Failed to load patients',
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
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 12.sp,
                          color: Colors.grey[700],
                        ),
                        textAlign: TextAlign.center,
                      ),
                      SizedBox(height: 16.h),
                      TextButton(
                        onPressed: _loadPatients,
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
                  ),
                )
              else if (patients.isEmpty)
                Padding(
                  padding: EdgeInsets.only(top: 40.h),
                  child: Center(
                    child: Text(
                      'no_patients_found'.tr(),
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 14.sp,
                        color: Colors.grey[700],
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                )
              else
                Column(
                  children: patients
                      .map(
                        (p) => _patientCard(
                          context,
                          patient: p,
                        ),
                      )
                      .toList(),
                ),

              SizedBox(height: 50.h),
            ],
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------
  // Filter button (All / Active / Inactive)
  // ---------------------------------------------------
  Widget _filterButton(String englishKey) {
    final isSelected = selectedFilter == englishKey;
    return GestureDetector(
      onTap: () {
        setState(() => selectedFilter = englishKey);
        _loadPatients(); // Reload from backend with new status
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: englishKey == "All"
            ? 55.w
            : englishKey == "Active"
                ? 90.w
                : 103.w,
        height: 28.h,
        alignment: Alignment.center,
        decoration: _shadowBox().copyWith(
          borderRadius: BorderRadius.circular(14.r),
          color: isSelected ? const Color(0xFF4F869D) : Colors.white,
        ),
        child: Text(
          englishKey.toLowerCase().tr(),
          style: TextStyle(
            fontFamily: 'Poppins',
            fontSize: 13.sp,
            fontWeight: FontWeight.w600,
            color: isSelected ? Colors.white : const Color(0xFF013A3C),
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------
  // Patient card (uses PatientModel from backend)
  // ---------------------------------------------------
  Widget _patientCard(
    BuildContext context, {
    required PatientModel patient,
  }) {
    final isActive = patient.status.toLowerCase() == "active";

    return Container(
      width: double.infinity,
      margin: EdgeInsets.only(bottom: 10.h),
      padding: EdgeInsets.fromLTRB(15.w, 14.h, 18.w, 14.h),
      decoration: _shadowBox(),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Avatar icon
              Container(
                width: 51.w,
                height: 52.h,
                decoration: BoxDecoration(
                  color: const Color(0xFF134B63).withOpacity(0.12),
                  borderRadius: BorderRadius.circular(12.r),
                ),
                child: Center(
                  child: SvgPicture.asset(
                    'assets/icons/profile.svg',
                    width: 34.w,
                    height: 34.h,
                    color: const Color(0xFF31728E),
                  ),
                ),
              ),
              SizedBox(width: 14.w),

              // Name + ID + status
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      patient.name ?? '',
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 15.sp,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF013A3C),
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    SizedBox(height: 6.h),
                    Row(
                      children: [
                        Text(
                          patient.nationalId,
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 10.sp,
                            fontWeight: FontWeight.w600,
                            color: const Color(0xFF11607E),
                          ),
                        ),
                        SizedBox(width: 10.w),
                        Text(
                          patient.status.toLowerCase().tr(),
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 12.sp,
                            fontWeight: FontWeight.w700,
                            color: isActive
                                ? const Color(0xFF137713)
                                : const Color(0xFFCC0000),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // View + Remove buttons
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  GestureDetector(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => PatientProfileScreen(
                            patientId: patient.patientId,
                          ),
                        ),
                      );
                    },
                    child: _actionButton(
                      "view".tr(),
                      const Color(0xFF137713),
                    ),
                  ),
                  SizedBox(height: 8.h),
                  GestureDetector(
                    onTap: () => _showRemoveDialog(patient),
                    child: _actionButton(
                      "remove".tr(),
                      const Color(0xFFE7525D),
                    ),
                  ),
                ],
              ),
            ],
          ),

          SizedBox(height: 12.h),

          // Phone row
          Row(
            children: [
              Text(
                "phone".tr(),
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 12.sp,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF11607E),
                ),
              ),
              SizedBox(width: 12.w),
              Text(
                patient.phoneNumber ?? '',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 12.sp,
                  fontWeight: FontWeight.w400,
                  color: const Color(0xFF000000),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------
  // Small outline button (View / Remove)
  // ---------------------------------------------------
  Widget _actionButton(String text, Color borderColor) => Container(
        width: 61.w,
        height: 24.h,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12.r),
          border: Border.all(color: borderColor),
        ),
        child: Center(
          child: Text(
            text,
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 10.sp,
              fontWeight: FontWeight.w600,
              color: borderColor,
            ),
          ),
        ),
      );

  // ---------------------------------------------------
  // Remove confirmation dialog
  // ---------------------------------------------------
  void _showRemoveDialog(PatientModel patient) {
    showDialog(
      context: context,
      builder: (_) => Center(
        child: Container(
          width: 331.w,
          height: 178.h,
          padding: EdgeInsets.all(18.w),
          decoration: _shadowBox().copyWith(
            borderRadius: BorderRadius.circular(20.r),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Icon
              Container(
                width: 40.w,
                height: 40.h,
                decoration: BoxDecoration(
                  color: const Color(0xFFE39C56),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Center(
                  child: SvgPicture.asset(
                    'assets/icons/question.svg',
                    width: 25.w,
                    height: 25.h,
                    colorFilter: const ColorFilter.mode(
                      Colors.white,
                      BlendMode.srcIn,
                    ),
                  ),
                ),
              ),
              SizedBox(height: 10.h),

              // Title
              Text(
                "remove_confirm".tr(),
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 16.sp,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF4B4B4B),
                ),
                textAlign: TextAlign.center,
              ),
              SizedBox(height: 16.h),

              // Buttons
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _dialogButton(
                    "no".tr(),
                    const Color(0xFF8D8D8D),
                    const Color(0xFF8D8D8D),
                    onTap: () => Navigator.pop(context),
                  ),
                  SizedBox(width: 10.w),
                  _dialogButton(
                    "yes_remove".tr(),
                    const Color(0xFFE7525D),
                    const Color(0xFFE7525D),
                    onTap: () async {
                      Navigator.pop(context);
                      await _removePatient(patient);
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------
  // Dialog small button
  // ---------------------------------------------------
  Widget _dialogButton(
    String text,
    Color color,
    Color borderColor, {
    required VoidCallback onTap,
  }) =>
      GestureDetector(
        onTap: onTap,
        child: Container(
          width: 98.w,
          height: 24.h,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(30.r),
            border: Border.all(color: borderColor),
          ),
          child: Text(
            text,
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 10.sp,
              color: color,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      );
}
