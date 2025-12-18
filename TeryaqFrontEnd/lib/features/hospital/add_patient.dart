// lib/features/hospital/add_patient.dart

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:easy_localization/easy_localization.dart';
import '../../constants/app_colors.dart';

// Backend hospital service
import 'package:teryagapptry/services/hospital_service.dart';

// =============================================================
// LOCAL FAKE PATIENT DATABASE (FALLBACK ONLY)
// =============================================================
// Used only when backend lookup fails or returns nothing.
final Map<String, Map<String, String>> fakePatientsDatabase = {
  "0102020202": {
    "name": "Aisha Ahmed Ali",
    "phone": "+966 55 123 4456",
    "gender": "Female",
    "dob": "03-02-1999",
    "id": "0102020202",
  },
  "0101010101": {
    "name":
        "Futun Fahadddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd",
    "phone": "+966 54 815 2271",
    "gender": "Female",
    "dob": "14-07-2001",
    "id": "0101010101",
  },
  "0203030303": {
    "name": "Omar Khalid Salem",
    "phone": "+966 58 661 2234",
    "gender": "Male",
    "dob": "18-06-1998",
    "id": "0203030303",
  },
};

// =============================================================
// SCREEN
// =============================================================
class AddPatientScreen extends StatefulWidget {
  const AddPatientScreen({super.key});

  @override
  State<AddPatientScreen> createState() => _AddPatientScreenState();
}

class _AddPatientScreenState extends State<AddPatientScreen> {
  String? name, dob, gender, phone, email;

  final TextEditingController _idController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();

  // Backend flags (logic only, no UI change)
  bool _isLookingUp = false;
  bool _isSaving = false;

  // =========================================================
  // CLEAR PATIENT FIELDS (USED WHEN ID CHANGES)
  // =========================================================
  void _clearPatientFields() {
    setState(() {
      name = null;
      dob = null;
      gender = null;
      phone = null;
      // Do not clear email controller here — email is independent
    });
  }

  // =========================================================
  // FILL PATIENT INFO FROM BACKEND (WITH LOCAL FALLBACK)
  // =========================================================
  Future<void> _fillPatientFromDatabase(String fullId) async {
    if (_isLookingUp) return; // avoid multiple parallel calls

    setState(() {
      _isLookingUp = true;
    });

    try {
      // 1) Try backend first – 🔵 use HospitalService baseUrl (no hardcoded IP)
      final api = HospitalService(baseUrl: HospitalService.baseUrl);

      final backendJson = await api.getPatientByNationalId(nationalId: fullId);

      if (backendJson != null) {
        setState(() {
          name =
              (backendJson['name'] ??
                      backendJson['full_name'] ??
                      backendJson['patient_name'] ??
                      '')
                  .toString();
          phone =
              (backendJson['phone_number'] ??
                      backendJson['phone'] ??
                      backendJson['mobile'] ??
                      '')
                  .toString();
          gender = (backendJson['gender'] ?? '').toString();
          dob =
              (backendJson['date_of_birth'] ??
                      backendJson['dob'] ??
                      backendJson['birth_date'] ??
                      '')
                  .toString();
          email = backendJson['email']?.toString();

          // Sync backend email to controller if present
          if (email != null && email!.isNotEmpty) {
            _emailController.text = email!;
          }
        });
        return; // success from backend
      }

      // 2) Backend returned null → try local fake DB as fallback
      if (fakePatientsDatabase.containsKey(fullId)) {
        final p = fakePatientsDatabase[fullId]!;
        setState(() {
          name = p["name"];
          phone = p["phone"];
          gender = p["gender"];
          dob = p["dob"];
        });
      } else {
        _clearPatientFields();
      }
    } catch (e) {
      // 3) On error → fallback to local fake DB if available
      if (fakePatientsDatabase.containsKey(fullId)) {
        final p = fakePatientsDatabase[fullId]!;
        setState(() {
          name = p["name"];
          phone = p["phone"];
          gender = p["gender"];
          dob = p["dob"];
        });
      } else {
        _clearPatientFields();
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLookingUp = false;
        });
      }
    }
  }

  // =========================================================
  // SUBMIT: CREATE/ATTACH PATIENT IN BACKEND
  // =========================================================
  Future<void> _onAddPatientPressed() async {
    if (_isSaving) return;

    final nationalId = _idController.text.trim();

    // Local payload used as fallback if backend is not available
    final localPayload = {
      "patient_id": nationalId,
      "national_id": nationalId,
      "name": name ?? "Unknown",
      "phone_number": phone ?? "N/A",
      "email": email,
      "gender": gender,
      "date_of_birth": dob,
      "status": "Active",
    };

    setState(() {
      _isSaving = true;
    });

    try {
      // Get current hospital_id from HospitalService
      final hospitalId = HospitalService.currentHospitalId;

      // If hospitalId is not set, just return local payload
      if (hospitalId == null || hospitalId.isEmpty) {
        if (mounted) {
          Navigator.pop(context, localPayload);
        }
        return;
      }

      // 🔵 Use HospitalService baseUrl (no hardcoded IP)
      final api = HospitalService(baseUrl: HospitalService.baseUrl);

      // Build DTO for backend – ✅ includes DOB now
      final dto = PatientCreateDto(
        nationalId: nationalId,
        name: name ?? "Unknown",
        phoneNumber: phone ?? "N/A",
        address: null,
        email: email,
        gender: gender,
        dateOfBirth: dob,
        lat: null,
        lon: null,
      );

      // Use createOrAttachPatient:
      // If patient exists → returns existing
      // Else → creates new patient
      final backendCreated = await api.createOrAttachPatient(
        hospitalId: hospitalId,
        payload: dto,
      );

      // Convert backend model to JSON for caller screen
      final backendMap = backendCreated.toJson();

      if (mounted) {
        Navigator.pop(context, backendMap);
      }
    } catch (e) {
      // If backend fails, fallback to old behavior: return local map
      if (mounted) {
        Navigator.pop(context, localPayload);
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,

      // ======================================================
      // TOP BAR
      // ======================================================
      appBar: PreferredSize(
        preferredSize: Size.fromHeight(90.h),
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFFD5F7FF),
            borderRadius: BorderRadius.vertical(bottom: Radius.circular(25.r)),
          ),
          child: SafeArea(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 23.w, vertical: 10.h),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      GestureDetector(
                        onTap: () => Navigator.pop(context),
                        child: const Icon(
                          Icons.arrow_back_ios_new_rounded,
                          color: Color(0xFF013A3C),
                        ),
                      ),
                      Image.asset('assets/tglogo.png', height: 30.h),
                    ],
                  ),
                  Text(
                    "add_patient".tr(),
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 25.sp,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF013A3C),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),

      // ======================================================
      // BODY
      // ======================================================
      body: SingleChildScrollView(
        padding: EdgeInsets.symmetric(horizontal: 25.w, vertical: 25.h),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ======================================================
            // CARD 1 — NATIONAL ID
            // ======================================================
            Container(
              width: double.infinity,
              padding: EdgeInsets.symmetric(horizontal: 18.w, vertical: 16.h),
              decoration: _cardStyle(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _sectionTitle("patient_information".tr()),
                  SizedBox(height: 10.h),
                  _label("national_id".tr()),
                  SizedBox(height: 6.h),

                  // ID INPUT
                  Container(
                    width: double.infinity,
                    height: 32.h,
                    decoration: _inputBorder(),
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: 10.w),
                      child: TextField(
                        controller: _idController,
                        maxLength: 10,
                        keyboardType: TextInputType.number,
                        textAlignVertical: TextAlignVertical.center,
                        strutStyle: StrutStyle(fontSize: 14.sp, height: 1.2),
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 14.sp,
                          color: AppColors.detailText,
                        ),
                        decoration: InputDecoration(
                          counterText: "",
                          border: InputBorder.none,
                          isDense: true,
                          contentPadding: EdgeInsets.only(
                            top: 4.h,
                            bottom: 4.h,
                          ),
                        ),
                        onChanged: (value) {
                          if (value.length == 10) {
                            // Trigger backend lookup (with fallback)
                            _fillPatientFromDatabase(value);
                          } else {
                            _clearPatientFields();
                          }
                        },
                      ),
                    ),
                  ),

                  SizedBox(height: 12.h),

                  // Nafath-style info box
                  Container(
                    width: double.infinity,
                    padding: EdgeInsets.all(10.w),
                    decoration: BoxDecoration(
                      color: const Color(0xFFD5F7FF),
                      borderRadius: BorderRadius.circular(10.r),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.info_outline,
                          size: 20.sp,
                          color: const Color(0xFF005F94),
                        ),
                        SizedBox(width: 8.w),
                        Expanded(
                          child: Text(
                            "nafath_info".tr(),
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              color: const Color(0xFF005F94),
                              fontSize: 11.sp,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            SizedBox(height: 25.h),

            // ======================================================
            // CARD 2 — AUTO-FILLED PATIENT DATA
            // ======================================================
            Container(
              width: double.infinity,
              padding: EdgeInsets.symmetric(horizontal: 18.w, vertical: 16.h),
              decoration: _cardStyle(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _infoRow("name".tr(), name ?? ""),
                  _infoRow("dob".tr(), dob ?? ""),
                  _infoRow("gender".tr(), gender ?? ""),
                  _infoRow("phone".tr(), phone ?? ""),
                ],
              ),
            ),

            SizedBox(height: 25.h),

            // ======================================================
            // CARD 3 — EMAIL INPUT
            // ======================================================
            Container(
              width: double.infinity,
              padding: EdgeInsets.symmetric(horizontal: 18.w, vertical: 16.h),
              decoration: _cardStyle(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _sectionTitle("email_optional".tr()),
                  SizedBox(height: 10.h),
                  Container(
                    width: double.infinity,
                    height: 32.h,
                    decoration: _inputBorder(),
                    padding: EdgeInsets.symmetric(horizontal: 10.w),
                    child: TextField(
                      controller: _emailController,
                      textAlignVertical: TextAlignVertical.center,
                      strutStyle: StrutStyle(fontSize: 14.sp, height: 1.2),
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 14.sp,
                        color: AppColors.detailText,
                      ),
                      decoration: InputDecoration(
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: EdgeInsets.only(top: 4.h, bottom: 4.h),
                      ),
                      onChanged: (v) => email = v,
                    ),
                  ),
                ],
              ),
            ),

            SizedBox(height: 30.h),

            // ======================================================
            // BUTTON — ADD PATIENT
            // ======================================================
            Center(
              child: Container(
                width: 232.w,
                height: 44.h,
                decoration: BoxDecoration(
                  color: AppColors.buttonBlue,
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
                  onPressed: _isSaving ? null : _onAddPatientPressed,
                  child: Text(
                    "add_patient".tr(),
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
          ],
        ),
      ),
    );
  }

  // ======================================================
  // HELPERS
  // ======================================================
  BoxDecoration _cardStyle() => BoxDecoration(
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

  BoxDecoration _inputBorder() => BoxDecoration(
    border: Border.all(color: const Color(0xFFBDBDBD)),
    borderRadius: BorderRadius.circular(8.r),
  );

  Widget _sectionTitle(String text) => Text(
    text,
    style: TextStyle(
      fontFamily: 'Poppins',
      color: AppColors.headingText,
      fontSize: 18.sp,
      fontWeight: FontWeight.w700,
    ),
  );

  Widget _label(String text) => Text(
    text,
    style: TextStyle(
      fontFamily: 'Poppins',
      color: const Color(0xFF11607E),
      fontSize: 14.sp,
      fontWeight: FontWeight.w600,
    ),
  );

  Widget _infoRow(String label, String value) => Padding(
    padding: EdgeInsets.symmetric(vertical: 5.h),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 120.w,
          child: Text(
            label,
            softWrap: true,
            style: TextStyle(
              fontFamily: 'Poppins',
              color: const Color(0xFF11607E),
              fontSize: 13.sp,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            softWrap: true,
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
