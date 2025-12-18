import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
//import 'patient_orders.dart';//غير مستخدمة الرجاء التأكد
import 'package:teryagapptry/widgets/custom_top_bar.dart'; // TOP BAR ADDED DURRAH


class PatientReportScreen extends StatelessWidget {
  const PatientReportScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      // ✅ Reusable Top Bar with back arrow
      appBar: PreferredSize(
        preferredSize: Size.fromHeight(90.h),
        child: CustomTopBar(
          title: "Report",
          showBackButton: true,
          onBackTap: () => Navigator.pop(context),
        ),
      ),
      body: Stack(
        children: [
          // ✅ Scroll view نفس الأوردير
          SingleChildScrollView(
            physics: const ClampingScrollPhysics(),
            child: Padding(
              padding: EdgeInsets.only(top: 30.h, left: 28.w, right: 28.w),// DURRAH FOR THE NEW TOP BAR
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ✅ Report Information Card
                  Container(
                    width: double.infinity, // 🔹 متأقلم مع كل الأجهزة
                    constraints: BoxConstraints(minHeight: 130.h), // 🔹 الطول مثل ما طلبت
                    padding: EdgeInsets.symmetric(horizontal: 24.w, vertical: 17.h),
                    decoration: BoxDecoration(
                      color: const Color(0xFF478FA7),
                      borderRadius: BorderRadius.circular(15.r),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0x1C0E5D7C),
                          blurRadius: 11,
                          spreadRadius: 1,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: EdgeInsets.only(left: 1.w),
                          child: Text(
                            "Report Information",
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 19.sp,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                        ),
                        SizedBox(height: 6.h),
                        _infoRow("Report ID:", "OIY-56844286"),
                        _infoRow("Report Type:", "Delivery Report"),
                        _infoRow("Generated:", "14 Sep 2025, 7:06 PM"),
                      ],
                    ),
                  ),

                  SizedBox(height: 20.h),

                  // ✅ Order Information Card
                  Container(
                    width: double.infinity,
                    constraints: BoxConstraints(minHeight: 255.h),
                    padding: EdgeInsets.symmetric(horizontal: 24.w, vertical: 17.h),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(15.r),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0x1C0E5D7C),
                          blurRadius: 11,
                          spreadRadius: 1,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "Order Information",
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 20.sp,
                            fontWeight: FontWeight.w600,
                            color: const Color(0xFF013A3C),
                          ),
                        ),
                        SizedBox(height: 8.h),
                        _orderRow("Order ID:", "OIY-56844286"),
                        _orderRow("Order Type:", "Delivery Report"),
                        _orderRow("Order Status:", "Delivered"),
                        _orderRow("Created at:", "1 Sep 2025, 4:26 PM"),
                        _orderRow("Delivered at:", "14 Sep 2025, 7:00 PM"),
                        _orderRow("OTP:", "9 7 4 5 (verified)"),
                        _orderRow("Priority:", "High", valueColor: const Color(0xFFCC0000)),
                      ],
                    ),
                  ),

                  SizedBox(height: 20.h),

                  // ✅ Patient & Hospital Card
                  Container(
                    width: double.infinity,
                    constraints: BoxConstraints(minHeight: 124.h),
                    padding: EdgeInsets.symmetric(horizontal: 24.w, vertical: 17.h),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(15.r),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0x1C0E5D7C),
                          blurRadius: 11,
                          spreadRadius: 1,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "Patient & Hospital",
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 18.sp,
                            fontWeight: FontWeight.w700,
                            color: const Color(0xFF013A3C),
                          ),
                        ),
                        SizedBox(height: 8.h),
                        _patientRow("Patient:", "Durrah Aloulah"),
                        _patientRow("Phone Number:", "+966 56 815 5377"),
                        _hospitalRow("Hospital:", "King Khalid Hospital, Riyadh"),
                      ],
                    ),
                  ),

                  SizedBox(height: 20.h),

                  // ✅ Medication Information Card
                  Container(
                    width: double.infinity,
                    constraints: BoxConstraints(minHeight: 160.h),
                    padding: EdgeInsets.symmetric(horizontal: 24.w, vertical: 17.h),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(15.r),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0x1C0E5D7C),
                          blurRadius: 11,
                          spreadRadius: 1,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "Medication Information",
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 18.sp,
                            fontWeight: FontWeight.w700,
                            color: const Color(0xFF013A3C),
                          ),
                        ),
                        SizedBox(height: 8.h),
                        _medRow("Medication Name:", "Insulin"),
                        Padding(
                          padding: EdgeInsets.only(top: 4.h),
                          child: Text(
                            "Safety Conditions:",
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              fontWeight: FontWeight.w600,
                              color: const Color(0xFF013A3C),
                              fontSize: 13.sp,
                            ),
                          ),
                        ),
                        SizedBox(height: 7.h), // المسافه بين السطر 2 و3 في كارد 4
                        _medRow("Allowed Temperature Range:", "2–8°C"),
                        _medRow("Max excursion:", "30 minutes"),
                        _medRow("Return to fridge:", "Yes", isGreen: true),
                      ],
                    ),
                  ),

                  SizedBox(height: 20.h),

                  // ✅ Delivery Details Card (الكارد الخامسة)
                  Container(
                    width: double.infinity,
                    constraints: BoxConstraints(minHeight: 360.h),
                    padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 17.h),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(15.r),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0x1C0E5D7C),
                          blurRadius: 11,
                          spreadRadius: 1,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "Delivery Details",
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontWeight: FontWeight.w700,
                            fontSize: 18.sp,
                            color: const Color(0xFF013A3C),
                          ),
                        ),
                        SizedBox(height: 12.h),
                        Table(
                          border: TableBorder.all(color: const Color(0xFFE5E5E5), width: 1),
                          columnWidths: const {
                            0: FlexColumnWidth(1.4),
                            1: FlexColumnWidth(2.4),
                            2: FlexColumnWidth(1.7),
                            3: FlexColumnWidth(1.7),
                            4: FlexColumnWidth(1.3),
                          },
                          children: [
                            _buildHeaderRow(["Status", "Description", "Delivery Duration", "Remaining Stability", "Condition"]),
                            _buildDataRow("Packed", "Released by hospital", "-", "-", "Normal"),
                            _buildDataRow("Assigned", "Driver assigned & picked up order", "0 h 12 m", "7 h 48 m", "Normal"),
                            _buildDataRow("Delivery", "Order in the way", "2 h 05 m", "7 h 05 m", "Normal"),
                            _buildDataRow("Warning", "Temp 8.4 °C for 9 min (limit 30)", "2 h 34 m", "6 h 56 m", "Risk"),
                            _buildDataRow("In Range", "Temp restored to 5.6 °C", "2 h 42 m", "6 h 54 m", "Normal"),
                            _buildDataRow("Arrived", "Driver arrived at the destination", "3 h 15 m", "6 h 41 m", "Normal"),
                            _buildDataRow("Delivered", "OTP Verified", "3 h 18 m", "6 h 40 m", "Normal"),
                          ],
                        ),
                      ],
                    ),
                  ),

                  // 🔻 زر "Export as PDF" 
                  SizedBox(height: 20.h),
                  Center(
                    child: Container(
                      width: 190.w, // تحكم بالعرض
                      height: 28.h, // تحكم بالطول
                      decoration: BoxDecoration(
                        color: const Color(0xFFE7525D), 
                        borderRadius: BorderRadius.circular(25.r), // حواف دائرية
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.1),
                            blurRadius: 6,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Center(
                        child: Text(
                          "Export as PDF",
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 15.sp,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ),

                  SizedBox(height: 40.h),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ✅ Table Helpers
  TableRow _buildHeaderRow(List<String> headers) {
    return TableRow(
      children: headers
          .map(
            (h) => Padding(
              padding: EdgeInsets.symmetric(vertical: 8.h),
              child: Text(
                h,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFF11607E),
                  fontSize: 10.sp,
                ),
              ),
            ),
          )
          .toList(),
    );
  }

  TableRow _buildDataRow(String status, String desc, String duration, String stability, String condition) {
    Color condColor = condition == "Risk" ? const Color(0xFFE4C600) : const Color(0xFF137713);
    return TableRow(
      children: [
        _tableCell(status, const Color(0xFF525252)),
        _tableCell(desc, const Color(0xFF525252)),
        _mixedColorCell(duration, const Color(0xFF137713)),
        _mixedColorCell(stability, const Color(0xFFCC0000)),
        _tableCell(condition, condColor),
      ],
    );
  }

  Widget _mixedColorCell(String text, Color numberColor) {
    final regex = RegExp(r'(\d+\s*h\s*\d*\s*m?)');
    final match = regex.firstMatch(text);
    if (match == null) return _tableCell(text, const Color(0xFF525252));
    String numberPart = match.group(0)!;
    String rest = text.replaceAll(numberPart, '');
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 6.h),
      child: RichText(
        textAlign: TextAlign.center,
        text: TextSpan(children: [
          TextSpan(
            text: numberPart,
            style: TextStyle(
              fontFamily: 'Poppins',
              fontWeight: FontWeight.w600,
              color: numberColor,
              fontSize: 12.sp,
            ),
          ),
          TextSpan(
            text: rest,
            style: TextStyle(
              fontFamily: 'Poppins',
              fontWeight: FontWeight.w500,
              color: const Color(0xFF525252),
              fontSize: 12.sp,
            ),
          ),
        ]),
      ),
    );
  }

  Widget _tableCell(String text, Color color) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 6.h),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontFamily: 'Poppins',
          fontWeight: FontWeight.w500,
          color: color,
          fontSize: 11.sp,
        ),
      ),
    );
  }


  Widget _infoRow(String label, String value) {
    return Padding(
      padding: EdgeInsets.only(left: 10.w, top: 3.h, bottom: 2.h),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140.w,
            child: Text(
              label,
              style: TextStyle(
                fontFamily: 'Poppins',
                fontWeight: FontWeight.w700,
                color: Colors.white,
                fontSize: 13.sp,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontFamily: 'Poppins',
                fontWeight: FontWeight.w600,
                color: Colors.white,
                fontSize: 13.sp,
              ),
            ),
          ),
        ],
      ),
    );
  }

  
  Widget _orderRow(String label, String value, {Color? valueColor}) {
    return Padding(
      padding: EdgeInsets.only(left: 10.w, top: 3.h, bottom: 4.h),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140.w,
            child: Text(
              label,
              style: TextStyle(
                fontFamily: 'Poppins',
                fontWeight: FontWeight.w700,
                color: const Color(0xFF11607E),
                fontSize: 13.sp,
              ),
            ),
          ),
          Expanded(
            child: value.contains('(verified)')
                ? RichText(
                    text: TextSpan(
                      style: TextStyle(fontFamily: 'Poppins', fontSize: 13.sp),
                      children: const [
                        // الأرقام بالرمادي
                        TextSpan(
                          text: '9 7 4 5 ',
                          style: TextStyle(
                            fontWeight: FontWeight.w500,
                            color: Color(0xFF525252),
                          ),
                        ),
                        // كلمة (verified) فقط بالأخضر
                        TextSpan(
                          text: '(verified)',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF137713),
                          ),
                        ),
                      ],
                    ),
                  )
                : Text(
                    value,
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontWeight: FontWeight.w500,
                      color: valueColor ?? const Color(0xFF525252),
                      fontSize: 13.sp,
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _patientRow(String label, String value) {
    return Padding(
      padding: EdgeInsets.only(left: 10.w, top: 3.h, bottom: 3.h),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140.w,
            child: Text(
              label,
              style: TextStyle(
                fontFamily: 'Poppins',
                fontWeight: FontWeight.w600,
                color: const Color(0xFF11607E),
                fontSize: 13.sp,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontFamily: 'Poppins',
                fontWeight: FontWeight.w500,
                color: const Color(0xFF525252),
                fontSize: 13.sp,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _hospitalRow(String label, String value) {
    return Padding(
      padding: EdgeInsets.only(left: 10.w, top: 3.h),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontFamily: 'Poppins',
              fontWeight: FontWeight.w600,
              color: const Color(0xFF8FB8C7),
              fontSize: 13.sp,
            ),
          ),
          SizedBox(width: 4.w),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontFamily: 'Poppins',
                fontWeight: FontWeight.w600,
                color: const Color(0xFF8FB8C7),
                fontSize: 13.sp,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _medRow(String label, String value, {bool isGreen = false}) {
    return Padding(
      padding: EdgeInsets.only(left: 10.w, top: 3.h, bottom: 3.h),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 185.w, // موقع العامود الثاني الكارد 4
            child: Text(
              label,
              style: TextStyle(
                fontFamily: 'Poppins',
                fontWeight: FontWeight.w600,
                color: (label == "Safety Conditions:")
                    ? const Color(0xFF013A3C)
                    : const Color(0xFF11607E),
                fontSize: 13.sp,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontFamily: 'Poppins',
                fontWeight: FontWeight.w500,
                color: isGreen ? const Color(0xFF137713) : const Color(0xFF525252),
                fontSize: 13.sp,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
