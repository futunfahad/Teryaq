/*import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'package:teryagapptry/constants/app_colors.dart';
import 'package:teryagapptry/widgets/custom_top_bar.dart';
import 'package:teryagapptry/widgets/show_teryaq_menu.dart';

class PatientPrescriptions extends StatefulWidget {
  const PatientPrescriptions({super.key});

  @override
  State<PatientPrescriptions> createState() => _PatientPrescriptionsState();
}

class _PatientPrescriptionsState extends State<PatientPrescriptions> {
  String selectedFilter = "All"; 
  String searchQuery = "";

  // ⭐ Dummy prescription data (we will update later)
  final List<Map<String, String>> prescriptions = [
    {
      "medicine": "Propranolol 20mg",
      "refillDate": "12 Jan 2025",
      "status": "Active",
    },
    {
      "medicine": "Insulin (Pen)",
      "refillDate": "05 Feb 2025",
      "status": "Expired",
    },
  ];

  @override
  Widget build(BuildContext context) {
    final String q = searchQuery.trim().toLowerCase();

    // ⭐ FILTER + SEARCH LOGIC (same as Orders)
    final List<Map<String, String>> filteredPrescriptions =
        prescriptions.where((item) {
      final String medicine = (item["medicine"] ?? "").toLowerCase();
      final String status = item["status"] ?? "";

      bool matchesFilter;
      if (selectedFilter == "Active") {
        matchesFilter = status == "Active";
      } else if (selectedFilter == "Expired") {
        matchesFilter = status == "Expired";
      } else {
        matchesFilter = true; // All
      }

      bool matchesSearch = q.isEmpty || medicine.contains(q);

      return matchesFilter && matchesSearch;
    }).toList();

    return Scaffold(
      backgroundColor: AppColors.appBackground,

      // ⭐ SAME TOP BAR
      appBar: PreferredSize(
        preferredSize: Size.fromHeight(90.h),
        child: CustomTopBar(
          title: "prescriptions".tr(),
          onMenuTap: () => showTeryaqMenu(context),
        ),
      ),

      // ⭐ SAME SCROLLING + PADDING
      body: SingleChildScrollView(
        physics: const ClampingScrollPhysics(),
        child: Padding(
          padding: EdgeInsets.only(top: 25.h, left: 25.w, right: 25.w),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [

              // ⭐ SAME FILTER BAR
              Row(
                children: [
                  Text(
                    "${"filter".tr()}:",
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      color: AppColors.headingText,
                      fontSize: 14.sp,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  SizedBox(width: 20.w),
                  _filterButton("active".tr(), "Active"),
                  SizedBox(width: 12.w),
                  _filterButton("expired".tr(), "Expired"),
                  SizedBox(width: 12.w),
                  _filterButton("all".tr(), "All"),
                ],
              ),

              SizedBox(height: 20.h),

              // ⭐ SAME SEARCH BAR (with your corrected alignment)
              Container(
                height: 41.h,
                decoration: BoxDecoration(
                  color: AppColors.cardBackground,
                  borderRadius: BorderRadius.circular(20.r),
                  boxShadow: AppColors.universalShadow,
                ),
                child: TextField(
                  onChanged: (value) => setState(() => searchQuery = value),
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    color: AppColors.bodyText,
                    fontSize: 17.sp,
                  ),
                  decoration: InputDecoration(
                    prefixIcon: Icon(
                      Icons.search,
                      color: AppColors.bodyText,
                      size: 22.sp,
                    ),

                    hintText: "search".tr(),
                    hintStyle: TextStyle(
                      fontFamily: 'Poppins',
                      color: const Color(0xFFC6D9E0),
                      fontSize: 15.sp,
                    ),
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(vertical: 13.h),

                  ),
                ),
              ),

              SizedBox(height: 33.h),

              // ⭐ LIST OR EMPTY STATE
              if (filteredPrescriptions.isEmpty)
                _buildEmptyState()
              else
                Column(
                  children: [
                    ...filteredPrescriptions.map(_buildPrescriptionCard),
                    SizedBox(height: 50.h),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  // ============================================================
  // ⭐ FILTER BUTTON (same as Orders)
  // ============================================================
  Widget _filterButton(String labelText, String key) {
    final bool isSelected = selectedFilter == key;

    return GestureDetector(
      onTap: () => setState(() => selectedFilter = key),
      child: SizedBox(
        width: key == "All"
            ? 55.w
            : key == "Active"
                ? 90.w
                : 103.w,
        height: 28.h,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          decoration: BoxDecoration(
            color: isSelected
                ? AppColors.buttonBlue
                : AppColors.appBackground,
            borderRadius: BorderRadius.circular(14.r),
            boxShadow: AppColors.universalShadow,
          ),
          alignment: Alignment.center,
          child: Text(
            labelText,
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 13.sp,
              fontWeight: FontWeight.w600,
              color: isSelected
                  ? AppColors.appBackground
                  : AppColors.headingText,
            ),
          ),
        ),
      ),
    );
  }

  // ============================================================
  // ⭐ EMPTY STATE (temporary — same as orders)
  // ============================================================
  Widget _buildEmptyState() {
    return Padding(
      padding: EdgeInsets.only(top: 60.h, bottom: 40.h),
      child: Center(
        child: Text(
          "no_prescriptions".tr(),
          style: TextStyle(
            fontFamily: 'Poppins',
            fontSize: 18.sp,
            fontWeight: FontWeight.w600,
            color: AppColors.bodyText,
          ),
        ),
      ),
    );
  }

  // ============================================================
  // ⭐ PRESCRIPTION CARD (placeholder – next step we build it!)
  // ============================================================
  Widget _buildPrescriptionCard(Map<String, String> item) {
    return Container(
      width: double.infinity,
      margin: EdgeInsets.only(bottom: 12.h),
      padding: EdgeInsets.all(18.w),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(12.r),
        boxShadow: AppColors.universalShadow,
      ),
      child: Text(
        item["medicine"] ?? "",
        style: TextStyle(
          fontFamily: 'Poppins',
          fontSize: 16.sp,
          fontWeight: FontWeight.w600,
          color: AppColors.headingText,
        ),
      ),
    );
  }
}*/

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'package:teryagapptry/features/patient/patient_screens/patient_order_review.dart';
import 'package:teryagapptry/constants/app_colors.dart';
import 'package:teryagapptry/widgets/custom_top_bar.dart';
import 'package:teryagapptry/widgets/show_teryaq_menu.dart';

// 👇 import patient service
import 'package:teryagapptry/services/patient_service.dart';

class PatientPrescriptions extends StatefulWidget {
  const PatientPrescriptions({super.key});

  @override
  State<PatientPrescriptions> createState() => _PatientPrescriptionsState();
}

class _PatientPrescriptionsState extends State<PatientPrescriptions> {
  String selectedFilter = "All";
  String searchQuery = "";

  // Backend data
  List<Map<String, dynamic>> _allPrescriptions = [];
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadPrescriptions();
  }

  Future<void> _loadPrescriptions() async {
    try {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });

      final List<Map<String, dynamic>> data =
          await PatientService.fetchPrescriptions();

      setState(() {
        _allPrescriptions = data;
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
    final String q = searchQuery.trim().toLowerCase();

    // Filter + search logic based on backend fields
    final List<Map<String, dynamic>> filteredPrescriptions = _allPrescriptions
        .where((item) {
          final String medicine = (item["medicine"] ?? "")
              .toString()
              .toLowerCase();

          final bool needsNew =
              item["needs_new_prescription"] == true ||
              ((item["days_left"] ?? 0) as int) <= 0;

          final String status = needsNew ? "Expired" : "Active";

          bool matchesFilter;
          if (selectedFilter == "Active") {
            matchesFilter = status == "Active";
          } else if (selectedFilter == "Expired") {
            matchesFilter = status == "Expired";
          } else {
            matchesFilter = true; // All
          }

          final bool matchesSearch = q.isEmpty || medicine.contains(q);

          return matchesFilter && matchesSearch;
        })
        .toList();

    return Scaffold(
      backgroundColor: AppColors.appBackground,
      appBar: PreferredSize(
        preferredSize: Size.fromHeight(90.h),
        child: CustomTopBar(
          title: "prescriptions".tr(),
          onMenuTap: () => showTeryaqMenu(context),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: _loadPrescriptions,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: Padding(
            padding: EdgeInsets.only(top: 25.h, left: 25.w, right: 25.w),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Filter bar
                Row(
                  children: [
                    Text(
                      "${"filter".tr()}:",
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        color: AppColors.headingText,
                        fontSize: 14.sp,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    SizedBox(width: 20.w),
                    _filterButton("active".tr(), "Active"),
                    SizedBox(width: 12.w),
                    _filterButton("expired".tr(), "Expired"),
                    SizedBox(width: 12.w),
                    _filterButton("all".tr(), "All"),
                  ],
                ),

                SizedBox(height: 20.h),

                // Search bar
                Container(
                  height: 41.h,
                  decoration: BoxDecoration(
                    color: AppColors.cardBackground,
                    borderRadius: BorderRadius.circular(20.r),
                    boxShadow: AppColors.universalShadow,
                  ),
                  child: TextField(
                    onChanged: (value) {
                      setState(() {
                        searchQuery = value;
                      });
                    },
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      color: AppColors.bodyText,
                      fontSize: 17.sp,
                    ),
                    decoration: InputDecoration(
                      prefixIcon: Icon(
                        Icons.search,
                        color: AppColors.bodyText,
                        size: 22.sp,
                      ),
                      hintText: "search".tr(),
                      hintStyle: TextStyle(
                        fontFamily: 'Poppins',
                        color: const Color(0xFFC6D9E0),
                        fontSize: 15.sp,
                      ),
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.symmetric(vertical: 13.h),
                    ),
                  ),
                ),

                SizedBox(height: 33.h),

                // Loading / Error / Empty / List
                if (_isLoading)
                  Padding(
                    padding: EdgeInsets.only(top: 60.h),
                    child: Center(
                      child: SizedBox(
                        width: 32.w,
                        height: 32.w,
                        child: const CircularProgressIndicator(),
                      ),
                    ),
                  )
                else if (_errorMessage != null)
                  Padding(
                    padding: EdgeInsets.only(top: 60.h),
                    child: Center(
                      child: Text(
                        _errorMessage!,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 14.sp,
                          color: AppColors.buttonRed,
                        ),
                      ),
                    ),
                  )
                else if (filteredPrescriptions.isEmpty)
                  _buildEmptyState()
                else
                  Column(
                    children: [
                      ...filteredPrescriptions.map(_buildPrescriptionCard),
                      SizedBox(height: 50.h),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ============================================================
  // Filter button
  // ============================================================
  Widget _filterButton(String labelText, String key) {
    final bool isSelected = selectedFilter == key;

    return GestureDetector(
      onTap: () => setState(() => selectedFilter = key),
      child: SizedBox(
        width: key == "All"
            ? 55.w
            : key == "Active"
                ? 90.w
                : 103.w,
        height: 28.h,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          decoration: BoxDecoration(
            color: isSelected ? AppColors.buttonBlue : AppColors.appBackground,
            borderRadius: BorderRadius.circular(14.r),
            boxShadow: AppColors.universalShadow,
          ),
          alignment: Alignment.center,
          child: Text(
            labelText,
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 13.sp,
              fontWeight: FontWeight.w600,
              color: isSelected
                  ? AppColors.appBackground
                  : AppColors.headingText,
            ),
          ),
        ),
      ),
    );
  }

  // ============================================================
  // Empty state
  // ============================================================
  Widget _buildEmptyState() {
    return Padding(
      padding: EdgeInsets.only(top: 60.h, bottom: 40.h),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset('assets/icons/tick.png', width: 180.w, height: 180.h),
            SizedBox(height: 16.h),
            Text(
              "no_prescription_yet".tr(),
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 18.sp,
                fontWeight: FontWeight.w600,
                color: AppColors.bodyText,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // Single prescription card (FIX APPLIED HERE)
  // ============================================================
  Widget _buildPrescriptionCard(Map<String, dynamic> item) {
    final String medicine = (item["medicine"] ?? "").toString();
    final String dose = (item["dose"] ?? "").toString();
    final String doctor = (item["doctor"] ?? "").toString();

    final int daysLeft = item["days_left"] is int
        ? item["days_left"] as int
        : int.tryParse(item["days_left"]?.toString() ?? "") ?? 0;

    final bool needsNewPrescription =
        item["needs_new_prescription"] == true || daysLeft <= 0;

    final bool canOrder = !needsNewPrescription;

    final String daysText = needsNewPrescription
        ? "new_prescription_requierd".tr()
        : "$daysLeft ${"days_left".tr()}";

    // Read prescription_id from backend
    final String? prescriptionId = item["prescription_id"]?.toString();
    final bool hasValidId =
        prescriptionId != null && prescriptionId.trim().isNotEmpty;

    final bool canOrderFinal = canOrder && hasValidId;

    return Container(
      width: double.infinity,
      margin: EdgeInsets.only(bottom: 12.h),
      padding: EdgeInsets.fromLTRB(15.w, 15.h, 19.w, 15.h),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(12.r),
        boxShadow: AppColors.universalShadow,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // LEFT SIDE
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Square pill icon
                    Container(
                      width: 55.h,
                      height: 55.h,
                      decoration: BoxDecoration(
                        color: const Color(0xFFE2F2FF),
                        borderRadius: BorderRadius.circular(10.r),
                      ),
                      child: Center(
                        child: Icon(
                          Icons.vaccines,
                          size: 30.sp,
                          color: AppColors.cardBlue,
                        ),
                      ),
                    ),
                    SizedBox(width: 10.w),

                    // Text area
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            medicine,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 15.sp,
                              fontWeight: FontWeight.w800,
                              color: AppColors.buttonRed,
                            ),
                          ),
                          SizedBox(height: 4.h),
                          Text(
                            daysText,
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 11.sp,
                              fontWeight: FontWeight.w600,
                              color: AppColors.buttonBlue,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                SizedBox(height: 18.h),

                // Prescribed by
                Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: "${"prescribed_by".tr()}: ",
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 12.sp,
                          fontWeight: FontWeight.w600,
                          color: AppColors.headingText,
                        ),
                      ),
                      TextSpan(
                        text: doctor,
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 12.sp,
                          fontWeight: FontWeight.w500,
                          color: AppColors.detailText,
                        ),
                      ),
                    ],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),

          // RIGHT SIDE: dose + Order button
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              // FIX: limit dose width + lines
              SizedBox(
                width: 120.w,
                child: Text(
                  dose,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 13.sp,
                    fontWeight: FontWeight.w700,
                    color: AppColors.detailText,
                  ),
                ),
              ),

              SizedBox(height: 41.h),

              _buildOrderButton(
                enabled: canOrderFinal,
                onPressed: canOrderFinal
                    ? () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => PatientOrderReview(
                              prescriptionId: prescriptionId,
                            ),
                          ),
                        );
                      }
                    : null,
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ============================================================
  // Order button
  // ============================================================
  Widget _buildOrderButton({required bool enabled, VoidCallback? onPressed}) {
    final Color bgColor = enabled
        ? AppColors.buttonRed
        : AppColors.grayDisabled;
    const Color textColor = Colors.white;

    return SizedBox(
      width: 61.w,
      height: 24.h,
      child: TextButton(
        onPressed: enabled ? onPressed : null,
        style: TextButton.styleFrom(
          padding: EdgeInsets.zero,
          backgroundColor: bgColor,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(9.r),
          ),
        ),
        child: Text(
          "order".tr(),
          style: TextStyle(
            fontFamily: 'Poppins',
            fontSize: 10.sp,
            fontWeight: FontWeight.w600,
            color: textColor,
          ),
        ),
      ),
    );
  }
}


/*import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_svg/flutter_svg.dart';//غير مستحدمه ليه محطوطه
import 'package:teryagapptry/features/patient/patient_screens/patient_order_review.dart'; 
import 'package:teryagapptry/widgets/custom_top_bar.dart'; // Top bar design
import 'package:teryagapptry/widgets/show_teryaq_menu.dart';// TOP BAR 3 lines action DURRAH
import 'package:teryagapptry/constants/app_colors.dart';
import 'package:easy_localization/easy_localization.dart';//for langauge changing

class PatientPrescriptions extends StatefulWidget {
  const PatientPrescriptions({super.key});

  @override
  State<PatientPrescriptions> createState() => _PatientPrescriptionsState();
}

class _PatientPrescriptionsState extends State<PatientPrescriptions> {
  String selectedFilter = "All";
  String searchQuery = "";

  // ✅ البيانات مع الحالات الصحيحة
  final List<Map<String, dynamic>> prescriptions = [
    {
      "name": "Amoxicillin",
      "daysLeft": "0 Days Left",
      "amount": "500 mg",
      "doctor": "Dr. Mohammed",
      "status": "Active", // ✅ الاكتف الوحيدة
    },
    {
      "name": "Insulin",
      "daysLeft": "35 Days Left",
      "amount": "10 m",
      "doctor": "Dr. Mohammed",
      "status": "Expired", // ❌ اكسبايرد
    },
    {
      "name": "Insulin",
      "daysLeft": "new prescription required",
      "amount": "10 m",
      "doctor": "Dr. Mohammed",
      "status": "Expired", // ❌ اكسبايرد
    },
  ];

  @override
  Widget build(BuildContext context) {
    //  فلترة الكروت حسب الفلتر + البحث
    List<Map<String, dynamic>> filteredList = prescriptions.where((p) {
      bool matchesFilter = true;
      if (selectedFilter == "Active") matchesFilter = p["status"] == "Active";
      if (selectedFilter == "Expired") matchesFilter = p["status"] == "Expired";

      bool matchesSearch = p["name"]
          .toString()
          .toLowerCase()
          .contains(searchQuery.toLowerCase());

      return matchesFilter && matchesSearch;
    }).toList();

    return Scaffold(
      backgroundColor:AppColors.appBackground, //تم التغير


        // ✅ NEW Top Bar (reusable) with three lines 
      appBar: PreferredSize(
        preferredSize: Size.fromHeight(90.h),
        child: CustomTopBar(
          title: "prescriptions".tr(),
          onMenuTap: () => showTeryaqMenu(context),
        ),
      ),
      // 🔹 Body
      body: SingleChildScrollView(
        physics: const ClampingScrollPhysics(),
        child: Padding(
          padding: EdgeInsets.only(top: 30.h, left: 28.w, right: 29.w),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 🔹 فلتر الأزرار
              Row(
                children: [
                  Text(
                    "filter".tr(),
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      color: AppColors.headingText, //تم التغير 
                      fontSize: 14.sp,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  SizedBox(width: 20.w),
                  _filterButton("active".tr(), "Active"),
                  SizedBox(width: 12.w),
                  _filterButton("expired".tr(), "Expired"),
                  SizedBox(width: 12.w),
                  _filterButton("all".tr(), "All"),
                ],
              ),
              SizedBox(height: 20.h),

              // 🔹 مربع البحث (نفس الشكل)
              Container(
                height: 41.h,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20.r),
                  boxShadow: AppColors.universalShadow, // تم التغير الشادو
                 
                ),
                child: TextField(
                  onChanged: (value) => setState(() => searchQuery = value),
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    color: AppColors.bodyText, // ماادري لون ايش مايطلع اذا غيرت 
                    fontSize: 17.sp,
                  ),
                  decoration: InputDecoration(
                    prefixIcon: Icon(
                      Icons.search,
                      color: AppColors.bodyText, // تم التغير
                      size: 25.sp,
                    ),
                    hintText: "search".tr(),
                    hintStyle: TextStyle(
                      fontFamily: 'Poppins',
                      color: const Color.fromARGB(105, 17, 95, 126), // االلون موب موجود حق السيرتش 
                      fontSize: 18.sp,
                    ),
                    border: InputBorder.none,
                  ),
                ),
              ),
              SizedBox(height: 33.h),

              // 🔹 عرض الكروت حسب الفلتر والبحث
              Column(
                children: filteredList.map((item) {
                  return _prescriptionCard(item);
                }).toList(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // 🔹 زر الفلتر
  Widget _filterButton(String labelText, String key) {
    bool isSelected = selectedFilter == key;
    return GestureDetector(
      onTap: () => setState(() => selectedFilter = key),
      child: SizedBox(
        width: key == "All"
            ? 55.w
            : key == "Active"
                ? 90.w
                : 103.w,
        height: 28.h,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFF4F869D) : Colors.white,
            borderRadius: BorderRadius.circular(14.r),
            boxShadow: AppColors.universalShadow,
          ),
          alignment: Alignment.center,
          child: Text(
            labelText,
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 13.sp,
              fontWeight: FontWeight.w600,
              color: isSelected ? AppColors.appBackground : AppColors.headingText, // تم التغيير 
            ),
          ),
        ),
      ),
    );
  }

  // 🔹 تصميم الكارد (بدون أيقونة داخل المربع)
  Widget _prescriptionCard(Map<String, dynamic> item) {
    bool isActive = item["status"] == "Active";

    return Container(
      width: double.infinity,
      height: 117.h,
      margin: EdgeInsets.only(bottom: 12.h),
      padding: EdgeInsets.fromLTRB(15.w, 9.h, 19.w, 10.h),
      decoration: BoxDecoration(
        color: AppColors.cardBackground, // تم التغير 
        borderRadius: BorderRadius.circular(16.r),
        boxShadow: AppColors.universalShadow, // تم تغير الشادو
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
                  color: const Color(0x330088FF), // اللون موب موجود ماعرفت اطلعه 
                  borderRadius: BorderRadius.circular(10.r),
                ),
              ),
              SizedBox(width: 10.w),
              Expanded(
                child: Padding(
                  padding: EdgeInsets.only(top: 6.h),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item["name"],
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 14.sp,
                          fontWeight: FontWeight.w700,
                          color: AppColors.buttonRed, // تم التغير 
                        ),
                      ),
                      SizedBox(height: 3.h),
                      Text(
                        item["daysLeft"],
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 12.sp,
                          fontWeight: FontWeight.w600,
                          color: AppColors.bodyText,// تم التغيير
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Text(
                item["amount"],
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 13.sp,
                  fontWeight: FontWeight.w600,
                 color: const Color(0xFF000000), // اللون موب موجود 
                ),
              ),
            ],
          ),
          SizedBox(height: 8.h),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Text(
                    "prescribed_by".tr(), 
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 12.sp,
                      fontWeight: FontWeight.w700,
                      color: AppColors.bodyText, // تم التغير 
                    ),
                  ),
                  SizedBox(width: 8.w),
                  Text(
                    item["doctor"],
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 12.sp,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF000000), // موب موجود اللون 
                    ),
                  ),
                ],
              ),
              GestureDetector(
                onTap: isActive
                    ? () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) =>
                                const PatientOrderReview(), // ✅ يفتح شاشة Order Review
                          ),
                        );
                      }
                    : null,
                child: Container(
                  width: 60.w,
                  height: 24.h,
                  decoration: BoxDecoration(
                    color: isActive
                        ? AppColors.buttonRed // تم التغير 
                        : AppColors.grayDisabled, // تم التغير 
                    borderRadius: BorderRadius.circular(8.r),
                  ),
                  child: Center(
                    child: Text(
                      "order".tr(), 
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 10.sp,
                        fontWeight: FontWeight.w600,
                        color: AppColors.appBackground, // تم التغير 
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}*/