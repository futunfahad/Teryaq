// lib/features/hospital/add_prescription.dart

// ======================================================================
//  Add Prescription Screen
//  - Medication dropdown loaded from DB (backend)
//  - باقي الكود كما هو (بدون فلتر/بحث للأدوية)
// ======================================================================

import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../constants/app_colors.dart';
import '../../widgets/custom_top_bar.dart';
import 'package:flutter_svg/flutter_svg.dart';

// Backend service
import 'package:teryagapptry/services/hospital_service.dart';

// Temporary local storage (for testing / UI only)
List<Map<String, dynamic>> createdPrescriptions = [];

// Fake patients (local DB for overlay + fallback)
final List<Map<String, String>> fakePatients = [
  {
    "id": "0101010101",
    "name":
        "Futun Fahadaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
    "dob": "12-08-2000",
    "gender": "Female",
  },
  {
    "id": "0102020202",
    "name":
        "Aisha Fahadaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
    "dob": "03-02-1999",
    "gender": "Female",
  },
  {
    "id": "0203030303",
    "name": "Omar Khalid",
    "dob": "18-06-1998",
    "gender": "Male",
  },
];

class AddPrescriptionScreen extends StatefulWidget {
  const AddPrescriptionScreen({super.key});

  @override
  State<AddPrescriptionScreen> createState() => _AddPrescriptionScreenState();
}

class _AddPrescriptionScreenState extends State<AddPrescriptionScreen> {
  final LayerLink _layerLink = LayerLink();
  OverlayEntry? _overlayEntry;

  final TextEditingController _patientIdController = TextEditingController();

  String patientSearch = "";
  Map<String, String>? selectedPatient;
  bool patientFound = false;

  // ✅ Medications from DB
  bool _isLoadingMeds = false;
  List<Map<String, dynamic>> _dbMedications = []; // each has medication_id + name
  String? selectedMedicationId; // ✅ will be sent to backend
  String? selectedMedicationName; // UI only

  String? instructions;
  String? refillLimit;
  String? validUntil;
  String? doctor;

  // Backend flags (logic only)
  bool _isSearchingPatient = false;
  bool _isSavingPrescription = false;

  @override
  void initState() {
    super.initState();
    _loadMedicationsFromDb(); // ✅ load meds once on open
  }

  @override
  void dispose() {
    _removeOverlay();
    _patientIdController.dispose();
    super.dispose();
  }

  // =========================================================
  // ✅ LOAD MEDICATIONS FROM DB (Backend)
  // =========================================================
  String _medId(Map<String, dynamic> m) {
    return (m["medication_id"] ?? m["id"] ?? m["medicationId"] ?? "").toString();
  }

  String _medName(Map<String, dynamic> m) {
    return (m["name"] ?? m["medication_name"] ?? m["title"] ?? "").toString();
  }

  Future<void> _loadMedicationsFromDb() async {
    if (_isLoadingMeds) return;

    final hospitalId = HospitalService.currentHospitalId;
    if (hospitalId == null || hospitalId.isEmpty) {
      // ما نوقف الصفحة، بس ما نقدر نجيب قائمة أدوية بدون hospital_id
      return;
    }

    setState(() => _isLoadingMeds = true);

    try {
      final api = HospitalService(baseUrl: HospitalService.baseUrl);

      // ✅ لازم تضيف هذه الدالة في HospitalService (تحت بشرحها لك)
      final meds = await api.getHospitalMedications(hospitalId: hospitalId);

      // sanitize + sort
      final cleaned = meds
          .where((m) => _medId(m).isNotEmpty && _medName(m).isNotEmpty)
          .toList()
        ..sort((a, b) => _medName(a).toLowerCase().compareTo(_medName(b).toLowerCase()));

      if (!mounted) return;
      setState(() => _dbMedications = cleaned);
    } catch (e) {
      // debugPrint("❌ Failed to load medications: $e");
      if (!mounted) return;
      setState(() => _dbMedications = []);
    } finally {
      if (mounted) setState(() => _isLoadingMeds = false);
    }
  }

  // =========================================================
  // BACKEND: SEARCH PATIENT BY NATIONAL ID (10 DIGITS)
  // =========================================================
  Future<void> _searchPatientById(String nationalId) async {
    if (_isSearchingPatient) return;

    setState(() {
      _isSearchingPatient = true;
      patientFound = false;
      selectedPatient = null;
    });

    try {
      // Use shared HospitalService baseUrl (no hardcoded IP)
      final api = HospitalService(baseUrl: HospitalService.baseUrl);

      final backendJson = await api.getPatientByNationalId(
        nationalId: nationalId,
      );

      if (backendJson != null) {
        setState(() {
          selectedPatient = {
            "id":
                (backendJson['patient_id'] ??
                        backendJson['national_id'] ??
                        backendJson['id'] ??
                        nationalId)
                    .toString(),
            "national_id": (backendJson['national_id'] ?? nationalId).toString(),
            "name":
                (backendJson['name'] ??
                        backendJson['full_name'] ??
                        backendJson['patient_name'] ??
                        '')
                    .toString(),
            "dob":
                (backendJson['date_of_birth'] ??
                        backendJson['dob'] ??
                        backendJson['birth_date'] ??
                        '')
                    .toString(),
            "gender": (backendJson['gender'] ?? '').toString(),
          };
          patientFound = true;
        });
        return;
      }

      // Backend returned null → fallback to local fakePatients
      final localMatch = fakePatients.firstWhere(
        (p) => p["id"] == nationalId,
        orElse: () => {},
      );
      if (localMatch.isNotEmpty) {
        setState(() {
          selectedPatient = {
            "id": localMatch["id"]!,
            "national_id": localMatch["id"]!,
            "name": localMatch["name"] ?? "",
            "dob": localMatch["dob"] ?? "",
            "gender": localMatch["gender"] ?? "",
          };
          patientFound = true;
        });
      } else {
        setState(() {
          selectedPatient = null;
          patientFound = false;
        });
      }
    } catch (e) {
      // On error → still try local fakePatients
      final localMatch = fakePatients.firstWhere(
        (p) => p["id"] == nationalId,
        orElse: () => {},
      );
      if (localMatch.isNotEmpty) {
        setState(() {
          selectedPatient = {
            "id": localMatch["id"]!,
            "national_id": localMatch["id"]!,
            "name": localMatch["name"] ?? "",
            "dob": localMatch["dob"] ?? "",
            "gender": localMatch["gender"] ?? "",
          };
          patientFound = true;
        });
      } else {
        setState(() {
          selectedPatient = null;
          patientFound = false;
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSearchingPatient = false;
        });
      }
    }
  }

  // =========================================================
  // BACKEND: SAVE PRESCRIPTION  (POST /hospital/prescriptions)
  // =========================================================
  Future<void> _savePrescription() async {
    if (_isSavingPrescription) return;

    final data = {
      "patient": selectedPatient,
      "medication_id": selectedMedicationId,
      "medication_name": selectedMedicationName,
      "instructions": instructions,
      "refillLimit": refillLimit,
      "validUntil": validUntil,
      "doctor": doctor,
    };

    createdPrescriptions.add(data);
    debugPrint("📌 LOCAL PRESCRIPTION: $data");

    final hospitalId = HospitalService.currentHospitalId;
    if (hospitalId == null || hospitalId.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text("hospital_not_linked".tr())));
      return;
    }

    final String? patientNationalId =
        selectedPatient?["national_id"] ?? selectedPatient?["id"];

    // ✅ أهم سطر: نرسل medication_id الحقيقي (من DB)
    final String? medicationId = selectedMedicationId;

    if (patientNationalId == null ||
        patientNationalId.isEmpty ||
        medicationId == null ||
        medicationId.isEmpty ||
        instructions == null ||
        instructions!.isEmpty ||
        doctor == null ||
        doctor!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("please_fill_required_fields".tr())),
      );
      return;
    }

    setState(() {
      _isSavingPrescription = true;
    });

    try {
      final api = HospitalService(baseUrl: HospitalService.baseUrl);

      final Map<String, dynamic> backendPayload = {
        "patient_national_id": patientNationalId,
        "medication_id": medicationId,
        "instructions": instructions,
        "prescribing_doctor": doctor,
        "reorder_threshold":
            refillLimit != null ? int.tryParse(refillLimit!) : null,
      };

      final created = await api.createPrescription(payload: backendPayload);
      debugPrint("✅ BACKEND CREATED PRESCRIPTION: $created");
    } catch (e) {
      debugPrint("❌ BACKEND PRESCRIPTION CREATE FAILED: $e");
    } finally {
      if (mounted) {
        setState(() {
          _isSavingPrescription = false;
        });
      }
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("prescription_published".tr())),
    );
  }

  // =========================================================
  // PATIENT ID SEARCH FIELD
  // =========================================================
  Widget _searchPatientField() {
    return CompositedTransformTarget(
      link: _layerLink,
      child: Container(
        height: 32.h,
        padding: EdgeInsets.symmetric(horizontal: 10.w),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8.r),
          border: Border.all(color: const Color(0xffbdbdbdb)),
        ),
        child: TextField(
          controller: _patientIdController,
          onChanged: (v) {
            setState(() {
              patientSearch = v;
              patientFound = false;
            });

            if (v.isNotEmpty) {
              _showOverlay();
            } else {
              _removeOverlay();
            }

            if (v.length == 10) {
              _searchPatientById(v);
            } else {
              setState(() {
                selectedPatient = null;
                patientFound = false;
              });
            }
          },
          textAlignVertical: TextAlignVertical.center,
          style: TextStyle(
            fontFamily: "Poppins",
            fontSize: 14.sp,
            color: AppColors.detailText,
          ),
          decoration: InputDecoration(
            border: InputBorder.none,
            isDense: true,
            contentPadding: EdgeInsets.only(top: 4.h, bottom: 4.h),
            hintText: "search".tr(),
            hintStyle: TextStyle(
              fontFamily: "Poppins",
              fontSize: 14.sp,
              color: AppColors.bodyText.withOpacity(0.24),
            ),
          ),
        ),
      ),
    );
  }

  // =========================================================
  // FLOATING OVERLAY (LOCAL PATIENT SUGGESTIONS)
  // =========================================================
  void _showOverlay() {
    _removeOverlay();
    final overlay = Overlay.of(context);

    final filtered = fakePatients
        .where((p) => p["id"]!.startsWith(patientSearch))
        .toList();

    if (filtered.isEmpty) return;

    _overlayEntry = OverlayEntry(
      builder: (context) => Positioned(
        width: MediaQuery.of(context).size.width - 50.w,
        child: CompositedTransformFollower(
          link: _layerLink,
          offset: Offset(0, 36.h),
          child: Material(
            elevation: 8,
            borderRadius: BorderRadius.circular(10.r),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10.r),
              ),
              child: ListView(
                padding: EdgeInsets.zero,
                shrinkWrap: true,
                children: filtered.map((p) {
                  return ListTile(
                    dense: true,
                    onTap: () {
                      setState(() {
                        selectedPatient = {
                          "id": p["id"]!,
                          "national_id": p["id"]!,
                          "name": p["name"] ?? "",
                          "dob": p["dob"] ?? "",
                          "gender": p["gender"] ?? "",
                        };
                        patientFound = true;
                        _patientIdController.text = p["id"]!;
                        patientSearch = p["id"]!;
                      });
                      _removeOverlay();

                      if (p["id"] != null) {
                        _searchPatientById(p["id"]!);
                      }
                    },
                    title: Text(
                      p["id"]!,
                      style: TextStyle(
                        fontFamily: "Poppins",
                        fontSize: 14.sp,
                        color: AppColors.detailText,
                      ),
                    ),
                    subtitle: Text(
                      p["name"]!,
                      style: TextStyle(
                        fontFamily: "Poppins",
                        fontSize: 12.sp,
                        color: AppColors.detailText.withOpacity(0.7),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
        ),
      ),
    );

    overlay.insert(_overlayEntry!);
  }

  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  // =========================================================
  // ✅ MEDICATION DROPDOWN (FROM DB)
  // =========================================================
  Widget _medicationDropdown() {
    final bool hasMeds = _dbMedications.isNotEmpty;

    return Container(
      height: 32.h,
      padding: EdgeInsets.symmetric(horizontal: 10.w),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8.r),
        border: Border.all(color: const Color(0xffbdbdbdb)),
      ),
      child: DropdownButton<String>(
        isExpanded: true,
        underline: const SizedBox(),
        value: selectedMedicationId,
        hint: Text(
          _isLoadingMeds
              ? "loading".tr()
              : (hasMeds ? "choose_medication".tr() : "no_medications_found".tr()),
          style: TextStyle(
            fontFamily: "Poppins",
            fontSize: 14.sp,
            fontWeight: FontWeight.w600,
            color: const Color(0xFF005F94).withOpacity(0.75),
          ),
        ),
        items: _dbMedications.map((m) {
          final id = _medId(m);
          final name = _medName(m);
          return DropdownMenuItem<String>(
            value: id,
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: "Poppins",
                fontSize: 14.sp,
                color: AppColors.detailText,
              ),
            ),
          );
        }).toList(),
        onChanged: (!hasMeds || _isLoadingMeds)
            ? null
            : (v) {
                if (v == null) return;
                final m = _dbMedications.firstWhere(
                  (x) => _medId(x) == v,
                  orElse: () => {},
                );
                setState(() {
                  selectedMedicationId = v;
                  selectedMedicationName = m.isEmpty ? null : _medName(m);
                });
              },
      ),
    );
  }

  // =========================================================
  // DATE PICKER (VALID UNTIL)
  // =========================================================
  Widget _datePickerField() {
    return GestureDetector(
      onTap: () async {
        final date = await showDatePicker(
          context: context,
          initialDate: DateTime.now(),
          firstDate: DateTime(2024),
          lastDate: DateTime(2030),
        );
        if (date != null) {
          setState(() => validUntil = "${date.day}-${date.month}-${date.year}");
        }
      },
      child: Container(
        height: 32.h,
        alignment: Alignment.centerLeft,
        padding: EdgeInsets.symmetric(horizontal: 10.w),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8.r),
          border: Border.all(color: const Color(0xffbdbdbdb)),
        ),
        child: Text(
          validUntil ?? "",
          style: TextStyle(
            fontFamily: "Poppins",
            fontSize: 14.sp,
            color: AppColors.detailText,
          ),
        ),
      ),
    );
  }

  // =========================================================
  // GENERIC TEXT INPUT FIELD
  // =========================================================
  Widget _inputField(ValueChanged<String>? onChanged) {
    return Container(
      height: 32.h,
      padding: EdgeInsets.symmetric(horizontal: 10.w),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8.r),
        border: Border.all(color: const Color(0xffbdbdbdb)),
      ),
      child: TextField(
        onChanged: onChanged,
        textAlignVertical: TextAlignVertical.center,
        style: TextStyle(
          fontFamily: "Poppins",
          fontSize: 14.sp,
          color: AppColors.detailText,
        ),
        decoration: InputDecoration(
          border: InputBorder.none,
          isDense: true,
          contentPadding: EdgeInsets.only(top: 4.h, bottom: 4.h),
        ),
      ),
    );
  }

  // =========================================================
  // CARD + LABELS + INFO ROW
  // =========================================================
  Widget _card(Widget child) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(horizontal: 18.w, vertical: 16.h),
      decoration: BoxDecoration(
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
      ),
      child: child,
    );
  }

  Widget _label(String text) {
    return Text(
      text.tr(),
      style: TextStyle(
        fontFamily: "Poppins",
        fontSize: 14.sp,
        fontWeight: FontWeight.w600,
        color: const Color(0xFF11607E),
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 5.h),
      child: Row(
        children: [
          SizedBox(
            width: 120.w,
            child: Text(
              label.tr(),
              style: TextStyle(
                fontFamily: "Poppins",
                fontSize: 14.sp,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF11607E),
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontFamily: "Poppins",
                fontSize: 14.sp,
                fontWeight: FontWeight.w600,
                color: AppColors.detailText,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // =========================================================
  // BUILD UI
  // =========================================================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,

      appBar: CustomTopBar(
        title: "add_prescription_title".tr(),
        showBackButton: true,
      ),

      body: SingleChildScrollView(
        padding: EdgeInsets.symmetric(horizontal: 25.w, vertical: 20.h),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // CARD 1 — PATIENT SEARCH
            _card(
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "patient_information".tr(),
                    style: TextStyle(
                      fontFamily: "Poppins",
                      fontSize: 18.sp,
                      fontWeight: FontWeight.w600,
                      color: AppColors.headingText,
                    ),
                  ),
                  SizedBox(height: 10.h),
                  _label("national_id"),
                  SizedBox(height: 6.h),
                  _searchPatientField(),
                  SizedBox(height: 12.h),

                  // Nafath info box
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
                        SizedBox(
                          width: 200.w,
                          child: Text(
                            "nafath_info".tr(),
                            style: TextStyle(
                              fontFamily: "Poppins",
                              fontSize: 11.sp,
                              fontWeight: FontWeight.w500,
                              color: const Color(0xFF005F94),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  if (patientFound) ...[
                    SizedBox(height: 8.h),
                    Row(
                      children: [
                        Icon(
                          Icons.check_circle_outline,
                          size: 20.sp,
                          color: const Color(0xFF137713),
                        ),
                        SizedBox(width: 6.w),
                        Text(
                          "patient_found".tr(),
                          style: TextStyle(
                            fontFamily: "Poppins",
                            fontSize: 14.sp,
                            fontWeight: FontWeight.w600,
                            color: const Color(0xFF137713),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),

            SizedBox(height: 25.h),

            // CARD 2 — PATIENT DETAILS
            _card(
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _infoRow("name", selectedPatient?["name"] ?? ""),
                  _infoRow("dob", selectedPatient?["dob"] ?? ""),
                  _infoRow("gender", selectedPatient?["gender"] ?? ""),
                ],
              ),
            ),

            SizedBox(height: 25.h),

            // CARD 3 — PRESCRIPTION INFO
            _card(
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _label("medication_name"),
                  SizedBox(height: 6.h),
                  _medicationDropdown(),
                  SizedBox(height: 15.h),
                  _label("instructions"),
                  SizedBox(height: 6.h),
                  _inputField((v) => instructions = v),
                  SizedBox(height: 15.h),
                  Row(
                    children: [
                      // Refill limit
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _label("refill_limit"),
                            SizedBox(height: 6.h),
                            _inputField((v) => refillLimit = v),
                          ],
                        ),
                      ),
                      SizedBox(width: 12.w),
                      // Valid until
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _label("valid_until"),
                            SizedBox(height: 6.h),
                            _datePickerField(),
                          ],
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 15.h),
                  _label("prescribing_doctor"),
                  SizedBox(height: 6.h),
                  _inputField((v) => doctor = v),
                ],
              ),
            ),

            SizedBox(height: 35.h),

            // PUBLISH BUTTON
            Center(
              child: GestureDetector(
                onTap: _isSavingPrescription ? null : _savePrescription,
                child: Container(
                  width: 232.w,
                  height: 32.h,
                  decoration: BoxDecoration(
                    color: AppColors.buttonBlue,
                    borderRadius: BorderRadius.circular(12.r),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0x1C0E5D7C),
                        blurRadius: 10,
                        spreadRadius: 1,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Center(
                    child: Text(
                      "publish_to_patient".tr(),
                      style: TextStyle(
                        fontFamily: "Poppins",
                        fontSize: 13.sp,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
            ),

            SizedBox(height: 40.h),
          ],
        ),
      ),
    );
  }
}
