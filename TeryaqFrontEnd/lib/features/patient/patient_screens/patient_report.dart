import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:intl/intl.dart';

import 'package:teryagapptry/widgets/custom_top_bar.dart';
import 'package:teryagapptry/constants/app_colors.dart';
import 'package:teryagapptry/services/patient_service.dart';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart';

class PatientReportScreen extends StatefulWidget {
  final String orderId;
  final String? codeFallback;

  const PatientReportScreen({
    super.key,
    required this.orderId,
    this.codeFallback,
  });

  @override
  State<PatientReportScreen> createState() => _PatientReportScreenState();
}

class _PatientReportScreenState extends State<PatientReportScreen> {
  Report? _report;
  bool _isLoading = true;
  bool _isExporting = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    Intl.defaultLocale = 'en';
    _loadReport();
  }

  String _formatEnglishDate(String raw) {
    final cleaned = raw.trim();
    if (cleaned.isEmpty || cleaned == "-") return raw;

    try {
      final dt = DateTime.parse(cleaned).toLocal();
      return DateFormat('d MMM yyyy, h:mm a', 'en').format(dt);
    } catch (_) {
      return raw;
    }
  }

  Future<void> _loadReport() async {
    try {
      Map<String, dynamic> data;

      try {
        data = await PatientService.fetchDeliveryReport(
          orderId: widget.orderId,
        );
      } catch (_) {
        final fb = (widget.codeFallback ?? "").trim();
        if (fb.isNotEmpty && fb != widget.orderId.trim()) {
          data = await PatientService.fetchDeliveryReport(orderId: fb);
        } else {
          rethrow;
        }
      }

      final report = Report.fromJsonLoose(data);

      // Format visible dates (English)
      report.generated = _formatEnglishDate(report.generated);
      report.createdAt = _formatEnglishDate(report.createdAt);
      report.deliveredAt = _formatEnglishDate(report.deliveredAt);

      // Format event timestamps if present
      for (final d in report.deliveryDetails) {
        if (d.time != null && d.time!.trim().isNotEmpty) {
          d.time = _formatEnglishDate(d.time!);
        }
      }

      if (!mounted) return;
      setState(() {
        _report = report;
        _isLoading = false;
        _errorMessage = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = e.toString();
      });
    }
  }

  Future<void> _exportPdf() async {
    if (_report == null || _isExporting) return;

    setState(() => _isExporting = true);

    try {
      final r = _report!;
      final pdf = pw.Document();

      pw.Widget sectionTitle(String text) => pw.Text(
        text,
        style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
      );

      pw.Widget fieldRow(String label, String value) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 2),
        child: pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.SizedBox(
              width: 150,
              child: pw.Text(
                label,
                style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
              ),
            ),
            pw.Expanded(child: pw.Text(value.trim().isEmpty ? "-" : value)),
          ],
        ),
      );

      pw.Widget cell(String t, {bool bold = false}) => pw.Padding(
        padding: const pw.EdgeInsets.all(6),
        child: pw.Text(
          (t.trim().isEmpty ? "-" : t),
          textAlign: pw.TextAlign.center,
          style: pw.TextStyle(
            fontSize: 10,
            fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
          ),
        ),
      );

      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(24),
          build: (_) => [
            pw.Text(
              "Delivery Report",
              style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 12),

            sectionTitle("Report Information"),
            fieldRow("Report ID", r.id),
            fieldRow("Report Type", r.type),
            fieldRow("Generated", r.generated),
            pw.SizedBox(height: 10),

            sectionTitle("Order Information"),
            fieldRow("Order ID", r.orderID),
            fieldRow("Order Code", r.orderCode),
            fieldRow("Order Type", r.orderType),
            fieldRow("Status", r.orderStatus),
            fieldRow("Created At", r.createdAt),
            fieldRow("Delivered At", r.deliveredAt),
            fieldRow("OTP", r.otpCode),
            fieldRow("OTP Verified", r.verified ? "Yes" : "No"),
            fieldRow("Priority", r.priority),
            pw.SizedBox(height: 10),

            sectionTitle("Patient & Hospital"),
            fieldRow("Patient", r.patientName),
            fieldRow("Phone", r.phoneNumber),
            fieldRow("Hospital", r.hospitalName),
            pw.SizedBox(height: 10),

            sectionTitle("Medication Information"),
            fieldRow("Medication Name", r.medicationName),
            fieldRow("Allowed Temp", r.allowedTemp),
            fieldRow("Max Excursion", r.maxExcursion),
            fieldRow("Return to Fridge", r.returnToFridge),
            pw.SizedBox(height: 14),

            sectionTitle("Delivery Details"),
            pw.SizedBox(height: 6),
            pw.Table(
              border: pw.TableBorder.all(),
              columnWidths: {
                0: const pw.FlexColumnWidth(1.4),
                1: const pw.FlexColumnWidth(2.4),
                2: const pw.FlexColumnWidth(1.7),
                3: const pw.FlexColumnWidth(1.7),
                4: const pw.FlexColumnWidth(1.3),
              },
              children: [
                pw.TableRow(
                  children: [
                    cell("Status", bold: true),
                    cell("Description", bold: true),
                    cell("Duration", bold: true),
                    cell("Stability", bold: true),
                    cell("Condition", bold: true),
                  ],
                ),
                for (final d in r.deliveryDetails)
                  pw.TableRow(
                    children: [
                      cell(d.status),
                      cell(d.description),
                      cell(d.duration),
                      cell(d.stability),
                      cell(d.condition),
                    ],
                  ),
              ],
            ),
          ],
        ),
      );

      final bytes = await pdf.save();

      final dir = await getApplicationDocumentsDirectory();
      final filePath = "${dir.path}/report_${r.orderID}.pdf";
      final file = File(filePath);
      await file.writeAsBytes(bytes, flush: true);

      try {
        final result = await OpenFilex.open(filePath);
        if (result.type != ResultType.done) {
          await Printing.sharePdf(
            bytes: bytes,
            filename: "report_${r.orderID}.pdf",
          );
        }
      } catch (_) {
        await Printing.sharePdf(
          bytes: bytes,
          filename: "report_${r.orderID}.pdf",
        );
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Report PDF generated successfully.")),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("Failed to export PDF: $e")));
      }
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: PreferredSize(
        preferredSize: Size.fromHeight(90.h),
        child: CustomTopBar(
          title: "report".tr(),
          showBackButton: true,
          onBackTap: () => Navigator.pop(context),
        ),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return Center(
        child: SizedBox(
          width: 32.w,
          height: 32.w,
          child: const CircularProgressIndicator(),
        ),
      );
    }

    if (_errorMessage != null) {
      return Padding(
        padding: EdgeInsets.symmetric(horizontal: 24.w),
        child: Center(
          child: Text(
            "report_load_error".tr(args: [_errorMessage ?? ""]),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 13.sp,
              fontWeight: FontWeight.w500,
              color: AppColors.detailText,
            ),
          ),
        ),
      );
    }

    if (_report == null) {
      return Padding(
        padding: EdgeInsets.symmetric(horizontal: 24.w),
        child: Center(
          child: Text(
            "no_report_data".tr(),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 13.sp,
              fontWeight: FontWeight.w500,
              color: AppColors.detailText,
            ),
          ),
        ),
      );
    }

    final r = _report!;

    return SingleChildScrollView(
      physics: const ClampingScrollPhysics(),
      child: Padding(
        padding: EdgeInsets.only(top: 25.h, left: 25.w, right: 25.w),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _reportInfoCard(r),
            SizedBox(height: 18.h),
            _orderInfoCard(r),
            SizedBox(height: 18.h),
            _patientHospitalCard(r),
            SizedBox(height: 18.h),
            _medicationCard(r),
            SizedBox(height: 18.h),
            _deliveryDetailsCard(r),
            SizedBox(height: 18.h),
            _exportButton(),
            SizedBox(height: 26.h),
          ],
        ),
      ),
    );
  }

  Widget _exportButton() {
    return Center(
      child: GestureDetector(
        onTap: _isExporting ? null : _exportPdf,
        child: Container(
          width: 190.w,
          height: 28.h,
          decoration: BoxDecoration(
            color: _isExporting
                ? AppColors.detailText.withOpacity(0.4)
                : const Color(0xFFE7525D),
            borderRadius: BorderRadius.circular(25.r),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 6,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Center(
            child: _isExporting
                ? SizedBox(
                    width: 16.w,
                    height: 16.w,
                    child: const CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : Text(
                    "export_as_pdf".tr(),
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
    );
  }

  // ================= UI Cards =================

  Widget _reportInfoCard(Report r) {
    return _card(
      color: AppColors.buttonBlue,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _title("report_information".tr(), color: Colors.white, size: 19),
          _row("report_id".tr(), r.id, color: Colors.white),
          _row("report_type".tr(), r.type, color: Colors.white),
          _row("generated".tr(), r.generated, color: Colors.white),
        ],
      ),
    );
  }

  Widget _orderInfoCard(Report r) {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _title("order_information".tr()),
          _row("order_id".tr(), r.orderID),
          _row("code".tr(), r.orderCode),
          _row("order_type".tr(), r.orderType),
          _row("order_status".tr(), r.orderStatus),
          _row("created_at".tr(), r.createdAt),
          _row("delivered_at".tr(), r.deliveredAt),
          _otpRow(r),
          _row("priority".tr(), r.priority),
        ],
      ),
    );
  }

  Widget _patientHospitalCard(Report r) {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _title("patient_and_hospital".tr()),
          _row("patient".tr(), r.patientName),
          _row("phone_number".tr(), r.phoneNumber),
          _row("hospital".tr(), r.hospitalName, color: AppColors.detailText),
        ],
      ),
    );
  }

  Widget _medicationCard(Report r) {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _title("medication_information".tr()),
          _row("medication_name".tr(), r.medicationName),
          _title("safety_conditions".tr(), size: 13, weight: FontWeight.w600),
          _row(
            "allowed_temperature_range".tr(),
            r.allowedTemp,
            labelWidth: 180,
          ),
          _row("max_excursion".tr(), r.maxExcursion),
          _row(
            "return_to_fridge".tr(),
            r.returnToFridge,
            color: AppColors.statusDelivered,
          ),
        ],
      ),
    );
  }

  Widget _deliveryDetailsCard(Report r) {
    return _card(
      padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 17.h),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _title("delivery_details".tr()),
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
              _header([
                "status".tr(),
                "description".tr(),
                "delivery_duration".tr(),
                "remaining_stability".tr(),
                "condition".tr(),
              ]),
              for (final d in r.deliveryDetails)
                _data(
                  d.status,
                  d.description,
                  d.duration,
                  d.stability,
                  d.condition,
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _otpRow(Report r) {
    final bool isDelivered = r.orderStatus.trim().toLowerCase() == "delivered";

    return Padding(
      padding: EdgeInsets.only(left: 10.w, top: 3.h, bottom: 3.h),
      child: Row(
        children: [
          SizedBox(
            width: 150.w,
            child: Text(
              "otp".tr(),
              style: TextStyle(
                fontFamily: 'Poppins',
                fontWeight: FontWeight.w600,
                color: AppColors.bodyText,
                fontSize: 13.sp,
              ),
            ),
          ),
          RichText(
            text: TextSpan(
              style: TextStyle(fontFamily: 'Poppins', fontSize: 13.sp),
              children: [
                TextSpan(
                  text: "${r.otpCode} ",
                  style: const TextStyle(
                    fontWeight: FontWeight.w500,
                    color: AppColors.detailText,
                  ),
                ),
                TextSpan(
                  text: isDelivered
                      ? "otp_verified".tr()
                      : "otp_not_verified".tr(),
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: isDelivered
                        ? AppColors.statusDelivered
                        : AppColors.statusRejected,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ================= UI Helpers =================

  Widget _card({
    required Widget child,
    Color color = Colors.white,
    EdgeInsets? padding,
  }) {
    return Container(
      width: double.infinity,
      padding:
          padding ?? EdgeInsets.symmetric(horizontal: 24.w, vertical: 17.h),
      decoration: BoxDecoration(
        color: color,
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
      child: child,
    );
  }

  Widget _title(
    String t, {
    Color color = AppColors.headingText,
    double size = 18,
    FontWeight weight = FontWeight.w700,
  }) {
    return Text(
      t,
      style: TextStyle(
        fontFamily: 'Poppins',
        fontSize: size.sp,
        fontWeight: weight,
        color: color,
      ),
    );
  }

  Widget _row(
    String label,
    String value, {
    Color color = AppColors.detailText,
    double labelWidth = 150,
  }) {
    final v = value.trim().isEmpty ? "-" : value;
    return Padding(
      padding: EdgeInsets.only(left: 10.w, top: 3.h, bottom: 3.h),
      child: Row(
        children: [
          SizedBox(
            width: labelWidth.w,
            child: Text(
              label,
              style: TextStyle(
                fontFamily: 'Poppins',
                fontWeight: FontWeight.w600,
                color: AppColors.bodyText,
                fontSize: 13.sp,
              ),
            ),
          ),
          Expanded(
            child: Text(
              v,
              style: TextStyle(
                fontFamily: 'Poppins',
                fontWeight: FontWeight.w500,
                color: color,
                fontSize: 13.sp,
              ),
            ),
          ),
        ],
      ),
    );
  }

  TableRow _header(List<String> h) {
    return TableRow(
      children: h
          .map(
            (x) => Padding(
              padding: EdgeInsets.symmetric(vertical: 8.h),
              child: Text(
                x,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontWeight: FontWeight.w600,
                  color: AppColors.bodyText,
                  fontSize: 10.sp,
                ),
              ),
            ),
          )
          .toList(),
    );
  }

  bool _isDash(String v) => v.trim().isEmpty || v.trim() == "-";

  TableRow _data(String s, String d, String dur, String stab, String cond) {
    final bool isEvent = _isDash(dur) && _isDash(stab);

    final String condLower = cond.trim().toLowerCase();
    final bool isRisk = condLower == "risk";
    final bool isSafe = condLower == "safe";

    Color condColor;
    if (isEvent) {
      condColor = AppColors.bodyText;
    } else if (isRisk) {
      condColor = const Color(0xFFE4C600);
    } else if (isSafe) {
      condColor = const Color(0xFF137713);
    } else {
      condColor = AppColors.detailText;
    }

    return TableRow(
      decoration: isEvent
          ? const BoxDecoration(color: Color(0xFFF8F9FB))
          : null,
      children: [
        _cell(s, isEvent ? AppColors.bodyText : AppColors.detailText),
        _cell(d),
        _cell(dur, const Color(0xFF137713)),
        _cell(stab, const Color(0xFFCC0000)),
        _cell(cond, condColor),
      ],
    );
  }

  Widget _cell(String t, [Color c = AppColors.detailText]) {
    final v = t.trim().isEmpty ? "-" : t;
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 6.h),
      child: Text(
        v,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontFamily: 'Poppins',
          fontWeight: FontWeight.w500,
          color: c,
          fontSize: 11.sp,
        ),
      ),
    );
  }
}

// ================= Models =================

// ================= Models =================

class Report {
  String id,
      type,
      generated,
      orderID,
      orderCode,
      orderType,
      orderStatus,
      createdAt,
      deliveredAt,
      otpCode,
      priority;

  bool verified;

  String patientName,
      phoneNumber,
      hospitalName,
      medicationName,
      allowedTemp,
      maxExcursion,
      returnToFridge;

  final List<DeliveryDetail> deliveryDetails;

  Report({
    required this.id,
    required this.type,
    required this.generated,
    required this.orderID,
    required this.orderCode,
    required this.orderType,
    required this.orderStatus,
    required this.createdAt,
    required this.deliveredAt,
    required this.otpCode,
    required this.priority,
    required this.verified,
    required this.patientName,
    required this.phoneNumber,
    required this.hospitalName,
    required this.medicationName,
    required this.allowedTemp,
    required this.maxExcursion,
    required this.returnToFridge,
    required this.deliveryDetails,
  });

  // ---------- helpers ----------

  static String _pickStr(
    Map<String, dynamic> j,
    List<String> keys, {
    String fallback = "",
  }) {
    for (final k in keys) {
      final v = j[k];
      if (v == null) continue;
      final s = v.toString();
      if (s.trim().isNotEmpty) return s;
    }
    return fallback;
  }

  static bool _pickBool(
    Map<String, dynamic> j,
    List<String> keys, {
    bool fallback = false,
  }) {
    for (final k in keys) {
      final v = j[k];
      if (v is bool) return v;
      if (v is num) return v != 0;
      if (v is String) {
        final s = v.toLowerCase().trim();
        if (s == "true" || s == "1" || s == "yes") return true;
        if (s == "false" || s == "0" || s == "no") return false;
      }
    }
    return fallback;
  }

  // ---------- factory ----------

  factory Report.fromJsonLoose(Map<String, dynamic> json) {
    // 🔥 NEW: merge report_content into root json
    final Map<String, dynamic> merged = {
      ...json,
      if (json["report_content"] is Map)
        ...Map<String, dynamic>.from(json["report_content"]),
    };

    final detailsRaw =
        (merged["deliveryDetails"] ?? merged["delivery_details"] ?? [])
            as List<dynamic>;

    return Report(
      id: _pickStr(merged, ["reportId", "report_id", "id"], fallback: ""),
      type: _pickStr(merged, [
        "type",
        "report_type",
      ], fallback: "Delivery Report"),
      generated: _pickStr(merged, ["generated", "generated_at"], fallback: ""),
      orderID: _pickStr(merged, [
        "orderId",
        "order_id",
        "orderID",
      ], fallback: ""),
      orderCode: _pickStr(merged, ["orderCode", "order_code"], fallback: ""),
      orderType: _pickStr(merged, ["orderType", "order_type"], fallback: ""),
      orderStatus: _pickStr(merged, [
        "orderStatus",
        "order_status",
        "status",
      ], fallback: ""),
      createdAt: _pickStr(merged, ["createdAt", "created_at"], fallback: ""),
      deliveredAt: _pickStr(merged, [
        "deliveredAt",
        "delivered_at",
      ], fallback: ""),
      otpCode: _pickStr(merged, ["otpCode", "otp_code", "otp"], fallback: ""),
      priority: _pickStr(merged, [
        "priority",
        "priority_level",
      ], fallback: "Normal"),

      // ✅ FIX: verified now works
      verified: _pickBool(merged, [
        "verified",
        "otp_verified",
      ], fallback: false),

      patientName: _pickStr(merged, [
        "patientName",
        "patient_name",
      ], fallback: ""),
      phoneNumber: _pickStr(merged, [
        "phoneNumber",
        "phone_number",
      ], fallback: ""),
      hospitalName: _pickStr(merged, [
        "hospitalName",
        "hospital_name",
      ], fallback: ""),
      medicationName: _pickStr(merged, [
        "medicationName",
        "medication_name",
      ], fallback: ""),
      allowedTemp: _pickStr(merged, [
        "allowedTemp",
        "allowed_temp",
      ], fallback: ""),
      maxExcursion: _pickStr(merged, [
        "maxExcursion",
        "max_excursion",
      ], fallback: ""),
      returnToFridge: _pickStr(merged, [
        "returnToFridge",
        "return_to_fridge",
      ], fallback: ""),
      deliveryDetails: detailsRaw
          .map(
            (e) => DeliveryDetail.fromJson(Map<String, dynamic>.from(e as Map)),
          )
          .toList(),
    );
  }
}

// ================= Delivery Detail =================

class DeliveryDetail {
  final String status;
  final String description;
  final String duration;
  final String stability;
  final String condition;

  // optional
  String? time;

  DeliveryDetail(
    this.status,
    this.description,
    this.duration,
    this.stability,
    this.condition, {
    this.time,
  });

  factory DeliveryDetail.fromJson(Map<String, dynamic> json) {
    String pick(List<String> keys, {String fallback = "-"}) {
      for (final k in keys) {
        final v = json[k];
        if (v == null) continue;
        final s = v.toString();
        if (s.trim().isNotEmpty) return s;
      }
      return fallback;
    }

    return DeliveryDetail(
      pick(["status", "event_status"], fallback: ""),
      pick(["description", "event_message", "message"], fallback: ""),
      pick(["duration"], fallback: "-"),
      pick(["stability", "remaining_stability"], fallback: "-"),
      pick(["condition"], fallback: "Normal"),
      time: json["time"]?.toString(),
    );
  }
}
