// lib/features/hospital/manage_prescriptions.dart

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:intl/intl.dart';

import '../../constants/app_colors.dart';
import '../../widgets/custom_top_bar.dart';
import '../../widgets/custom_popup.dart';
import 'add_prescription.dart';
import 'prescription_details.dart';

// Backend service + models
import 'package:teryagapptry/services/hospital_service.dart';

/// ===================================================================
///  💊 MANAGE PRESCRIPTIONS SCREEN (Hospital)
///  - Fetches prescriptions from backend (always "All")
///  - Filter is applied LOCALLY: All / Active / Expired / Invalid
///  - Search is applied LOCALLY: name / code / patient
///  - Add / View / Invalidate / Remove
/// ===================================================================
class ManagePrescriptionsScreen extends StatefulWidget {
  const ManagePrescriptionsScreen({super.key});

  @override
  State<ManagePrescriptionsScreen> createState() =>
      _ManagePrescriptionsScreenState();
}

class _ManagePrescriptionsScreenState extends State<ManagePrescriptionsScreen> {
  String selectedFilter = "All";
  String searchQuery = "";

  final List<PrescriptionCardModel> _prescriptions = [];
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadPrescriptions();
  }

  String _formatDate(DateTime? dt) {
    if (dt == null) return "-";
    final locale = context.locale.toString();
    final df = DateFormat('dd MMM yyyy', locale);
    return df.format(dt);
  }

  Color _statusLabelColor(String status) {
    switch (status.trim().toLowerCase()) {
      case "active":
        return const Color(0xFF137713);
      case "expired":
        return const Color(0xFFD1B000);
      case "invalid":
        return const Color(0xFFCC0000);
      default:
        return Colors.grey;
    }
  }

  // -----------------------------------------
  // Fetch prescriptions from backend (ALWAYS All)
  // -----------------------------------------
  Future<void> _loadPrescriptions() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final hospitalId = HospitalService.currentHospitalId;
      if (hospitalId == null || hospitalId.isEmpty) {
        throw Exception('Hospital ID is not set. Please login first.');
      }

      final api = HospitalService();

      // IMPORTANT:
      // - Keep backend call stable: status="All" so it returns the full list.
      // - Filtering happens LOCALLY in this screen (reliable).
      final list = await api.getPrescriptions(
        hospitalId: hospitalId,
        status: "All",
        search: null, // local search instead (avoid backend differences)
      );

      if (!mounted) return;
      setState(() {
        _prescriptions
          ..clear()
          ..addAll(list);
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = e.toString();
      });
    }
  }

  Future<void> _invalidatePrescription(PrescriptionCardModel p) async {
    try {
      final api = HospitalService();

      // Backend expects UUID (you are passing prescriptionId)
      await api.invalidatePrescription(code: p.prescriptionId);

      // Update local list immediately (so filter reflects instantly)
      setState(() {
        final idx = _prescriptions.indexWhere(
          (x) => x.prescriptionId == p.prescriptionId,
        );
        if (idx != -1) {
          final old = _prescriptions[idx];
          _prescriptions[idx] = PrescriptionCardModel(
            prescriptionId: old.prescriptionId,
            name: old.name,
            code: old.code,
            patient: old.patient,
            refillLimit: old.refillLimit,
            startDate: old.startDate,
            endDate: old.endDate,
            status: "invalid",
          );
        }
      });

      // Optional: refresh from DB (keeps everything consistent)
      await _loadPrescriptions();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'prescription_invalidate'.tr(),
            style: TextStyle(fontSize: 12.sp),
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Failed to invalidate prescription',
            style: TextStyle(fontSize: 12.sp),
          ),
        ),
      );
    }
  }

  Future<void> _removePrescription(PrescriptionCardModel p) async {
    try {
      final api = HospitalService();
      await api.deletePrescription(prescriptionId: p.prescriptionId);

      setState(() {
        _prescriptions.removeWhere((x) => x.prescriptionId == p.prescriptionId);
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'prescription_removed'.tr(),
            style: TextStyle(fontSize: 12.sp),
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Failed to remove prescription',
            style: TextStyle(fontSize: 12.sp),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final lowerSearch = searchQuery.trim().toLowerCase();
    final filter = selectedFilter.trim().toLowerCase();

    final filtered = _prescriptions.where((p) {
      final status = p.status.trim().toLowerCase();

      final byStatus = filter == 'all' || status == filter;

      final bySearch =
          lowerSearch.isEmpty ||
          p.name.toLowerCase().contains(lowerSearch) ||
          p.code.toLowerCase().contains(lowerSearch) ||
          p.patient.toLowerCase().contains(lowerSearch);

      return byStatus && bySearch;
    }).toList();

    return Scaffold(
      backgroundColor: AppColors.appBackground,
      appBar: CustomTopBar(title: "prescriptions".tr(), showBackButton: true),
      body: SingleChildScrollView(
        padding: EdgeInsets.symmetric(horizontal: 25.w),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(height: 30.h),
            _buildFilterRow(),
            SizedBox(height: 20.h),
            _buildSearchBar(),
            SizedBox(height: 20.h),
            _buildAddButton(),
            SizedBox(height: 20.h),

            if (_isLoading)
              Center(
                child: Padding(
                  padding: EdgeInsets.only(top: 20.h),
                  child: const CircularProgressIndicator(),
                ),
              )
            else if (_errorMessage != null)
              Padding(
                padding: EdgeInsets.only(top: 20.h),
                child: Column(
                  children: [
                    Text(
                      'Failed to load prescriptions',
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
                    SizedBox(height: 12.h),
                    TextButton(
                      onPressed: _loadPrescriptions,
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
            else if (filtered.isEmpty)
              Center(
                child: Padding(
                  padding: EdgeInsets.only(top: 20.h),
                  child: Text(
                    'no_prescriptions_found'.tr(),
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
              ...filtered.map(
                (p) => Padding(
                  padding: EdgeInsets.only(bottom: 12.h),
                  child: _buildPrescriptionCard(context, p),
                ),
              ),

            SizedBox(height: 40.h),
          ],
        ),
      ),
    );
  }

  // -----------------------------------------
  // Filter row (LOCAL ONLY)
  // -----------------------------------------
  Widget _buildFilterRow() {
    final filters = ["All", "Active", "Expired", "Invalid"];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      clipBehavior: Clip.none,
      child: Row(
        children: [
          Padding(
            padding: EdgeInsetsDirectional.only(end: 14.w),
            child: Text(
              "filter".tr(),
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 14.sp,
                fontWeight: FontWeight.w600,
                color: AppColors.headingText,
              ),
            ),
          ),
          ...filters.map((label) {
            final isSelected = selectedFilter == label;
            return Padding(
              padding: EdgeInsetsDirectional.only(end: 10.w),
              child: GestureDetector(
                onTap: () {
                  // LOCAL filter only — no backend call
                  setState(() => selectedFilter = label);
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: EdgeInsets.symmetric(
                    horizontal: 14.w,
                    vertical: 6.h,
                  ),
                  decoration: BoxDecoration(
                    color: isSelected ? AppColors.buttonBlue : Colors.white,
                    borderRadius: BorderRadius.circular(14.r),
                    boxShadow: AppColors.universalShadow,
                  ),
                  child: Text(
                    label.toLowerCase().tr(),
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 13.sp,
                      fontWeight: FontWeight.w600,
                      color: isSelected ? Colors.white : AppColors.headingText,
                    ),
                  ),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  // -----------------------------------------
  // Search bar (LOCAL)
  // -----------------------------------------
  Widget _buildSearchBar() {
    return Container(
      width: double.infinity,
      height: 41.h,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20.r),
        boxShadow: AppColors.universalShadow,
      ),
      child: TextField(
        onChanged: (v) => setState(() => searchQuery = v),
        // optional refresh from server if you want
        onSubmitted: (_) => _loadPrescriptions(),
        textAlignVertical: TextAlignVertical.center,
        strutStyle: StrutStyle(fontSize: 16.sp, height: 1.2),
        style: TextStyle(
          fontFamily: 'Poppins',
          fontSize: 16.sp,
          color: AppColors.bodyText,
        ),
        decoration: InputDecoration(
          isDense: true,
          contentPadding: EdgeInsets.symmetric(vertical: 8.h),
          prefixIcon: Icon(
            Icons.search,
            color: AppColors.bodyText,
            size: 22.sp,
          ),
          hintText: "search".tr(),
          hintStyle: TextStyle(fontSize: 15.sp, color: Colors.grey),
          border: InputBorder.none,
        ),
      ),
    );
  }

  // -----------------------------------------
  // Add prescription button
  // -----------------------------------------
  Widget _buildAddButton() {
    return Center(
      child: SizedBox(
        width: 232.w,
        height: 44.h,
        child: ElevatedButton(
          onPressed: () async {
            await Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const AddPrescriptionScreen()),
            );
            await _loadPrescriptions();
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.buttonBlue,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12.r),
            ),
          ),
          child: Text(
            "add_prescription".tr(),
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 14.sp,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }

  // -----------------------------------------
  // Prescription card
  // -----------------------------------------
  Widget _buildPrescriptionCard(BuildContext context, PrescriptionCardModel p) {
    final isInvalid = p.status.trim().toLowerCase() == "invalid";

    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(15.w, 12.h, 15.w, 14.h),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16.r),
        boxShadow: AppColors.universalShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 51.w,
                height: 52.h,
                decoration: BoxDecoration(
                  color: AppColors.bigIcons,
                  borderRadius: BorderRadius.circular(10.r),
                ),
                child: Center(
                  child: SvgPicture.asset(
                    'assets/icons/prescription.svg',
                    width: 26.w,
                    height: 30.h,
                    color: AppColors.bodyText,
                  ),
                ),
              ),
              SizedBox(width: 10.w),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      p.name,
                      style: TextStyle(
                        fontSize: 15.sp,
                        fontWeight: FontWeight.w800,
                        color: AppColors.headingText,
                      ),
                    ),
                    SizedBox(height: 3.h),
                    Text(
                      p.code,
                      style: TextStyle(
                        fontSize: 10.sp,
                        color: const Color(0xFF11607E),
                      ),
                    ),
                    SizedBox(height: 2.h),
                    Text(
                      p.patient,
                      style: TextStyle(
                        fontSize: 10.sp,
                        fontWeight: FontWeight.w500,
                        color: AppColors.bodyText,
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: EdgeInsets.only(top: 2.h, right: 2.w),
                child: Text(
                  p.status.toLowerCase().tr(),
                  style: TextStyle(
                    fontSize: 13.sp,
                    fontWeight: FontWeight.w500,
                    color: _statusLabelColor(p.status),
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: 10.h),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _infoRow(
                      "refill_limit".tr(),
                      p.refillLimit != null ? p.refillLimit.toString() : "-",
                    ),
                    SizedBox(height: 3.h),
                    _infoRow("start_date".tr(), _formatDate(p.startDate)),
                    SizedBox(height: 3.h),
                    _infoRow("end_date".tr(), _formatDate(p.endDate)),
                  ],
                ),
              ),
              SizedBox(width: 10.w),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  _button("view".tr(), AppColors.statusDelivered, () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => PrescriptionDetailScreen(
                          prescriptionCode: p.prescriptionId,
                        ),
                      ),
                    );
                  }),
                  SizedBox(height: 6.h),
                  _button(
                    "invalidate".tr(),
                    AppColors.alertRed,
                    isInvalid
                        ? null
                        : () {
                            showCustomPopup(
                              context: context,
                              titleText: "confirm_title".tr(),
                              subtitleText: "confirm_cancel_body".tr(),
                              cancelText: "no".tr(),
                              confirmText: "yes_cancel".tr(),
                              iconAsset: 'assets/icons/question.svg',
                              onConfirm: () async => _invalidatePrescription(p),
                            );
                          },
                    disabled: isInvalid,
                  ),
                  if (isInvalid) ...[
                    SizedBox(height: 6.h),
                    _button("remove".tr(), AppColors.alertRed, () {
                      showCustomPopup(
                        context: context,
                        titleText: "confirm_title".tr(),
                        subtitleText: "confirm_delete_body".tr(),
                        cancelText: "no".tr(),
                        confirmText: "yes_cancel".tr(),
                        iconAsset: 'assets/icons/question.svg',
                        onConfirm: () async => _removePrescription(p),
                      );
                    }),
                  ],
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: EdgeInsets.only(left: 15.w),
      child: Row(
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 12.sp,
              fontWeight: FontWeight.w700,
              color: const Color(0xFF11607E),
            ),
          ),
          SizedBox(width: 5.w),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 12.sp,
                fontWeight: FontWeight.w500,
                color: const Color(0xFF4B4B4B),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _button(
    String label,
    Color color,
    VoidCallback? onTap, {
    bool disabled = false,
  }) {
    return GestureDetector(
      onTap: disabled ? null : onTap,
      child: Container(
        width: 75.w,
        height: 24.h,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8.r),
          border: Border.all(color: disabled ? Colors.grey : color, width: 1.3),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            fontSize: 10.sp,
            fontWeight: FontWeight.w500,
            color: disabled ? Colors.grey : color,
          ),
        ),
      ),
    );
  }
}
