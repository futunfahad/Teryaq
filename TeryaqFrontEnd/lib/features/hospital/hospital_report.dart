// lib/features/hospital/hospital_report.dart

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:intl/intl.dart'; // ✅ required for DateFormat + Intl.defaultLocale

import 'package:teryagapptry/constants/app_colors.dart';
import 'package:teryagapptry/widgets/custom_top_bar.dart';

import 'package:teryagapptry/services/hospital_service.dart';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart';

/// Displays a full delivery & stability report for an order
class HospitalReportScreen extends StatefulWidget {
  final String orderId;
  final HospitalService? service;

  const HospitalReportScreen({super.key, required this.orderId, this.service});

  @override
  State<HospitalReportScreen> createState() => _HospitalReportScreenState();
}

class _HospitalReportScreenState extends State<HospitalReportScreen> {
  late final HospitalService _hospitalService;

  OrderReportModel? _report;
  bool _isLoading = true;
  bool _isExporting = false;
  String? _error;

  @override
  void initState() {
    super.initState();

    // Use global HospitalService.baseUrl (no IP inside the screen)
    _hospitalService =
        widget.service ?? HospitalService(baseUrl: HospitalService.baseUrl);

    // Force all dates to display in English (your preference)
    Intl.defaultLocale = 'en';

    _fetchReport();
  }

  // =====================================================
  // Fetch typed report model from backend
  // =====================================================
  Future<void> _fetchReport() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final data = await _hospitalService.getOrderReportModel(widget.orderId);
      setState(() => _report = data);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  // =====================================================
  // ✅ EVENTS / TIMELINE (Extract from report safely)
  //   - We keep extraction logic
  //   - But we DO NOT show a separate timeline card
  //   - We merge events into Delivery Details table (UI + PDF)
  // =====================================================
  List<_ReportEvent> _extractEvents(OrderReportModel report) {
    try {
      final dyn = report as dynamic;

      dynamic raw =
          dyn.events ??
          dyn.timeline ??
          dyn.deliveryEvents ??
          dyn.delivery_events;

      if (raw is! List) return [];

      final List<_ReportEvent> out = [];
      for (final item in raw) {
        if (item is Map) {
          final status =
              (item['status'] ?? item['event'] ?? item['type'] ?? '-')
                  .toString();
          final desc =
              (item['description'] ??
                      item['message'] ??
                      item['note'] ??
                      item['details'] ??
                      '-')
                  .toString();

          final tsRaw =
              item['timestamp'] ?? item['time'] ?? item['created_at'] ?? null;

          DateTime? ts;
          if (tsRaw is String) {
            ts = DateTime.tryParse(tsRaw);
          } else if (tsRaw is int) {
            ts = tsRaw > 1000000000000
                ? DateTime.fromMillisecondsSinceEpoch(tsRaw)
                : DateTime.fromMillisecondsSinceEpoch(tsRaw * 1000);
          }

          out.add(_ReportEvent(time: ts, status: status, description: desc));
        } else {
          out.add(
            _ReportEvent(time: null, status: '-', description: item.toString()),
          );
        }
      }

      // sort by time if available
      out.sort((a, b) {
        final at = a.time;
        final bt = b.time;
        if (at == null && bt == null) return 0;
        if (at == null) return 1;
        if (bt == null) return -1;
        return at.compareTo(bt);
      });

      return out;
    } catch (_) {
      return [];
    }
  }

  // =====================================================
  // PDF HELPERS (ONLY FOR EXPORT, DOES NOT TOUCH UI)
  // =====================================================

  String _normalizeText(String? value) {
    if (value == null || value.isEmpty) return "-";
    return value.replaceAll("–", "-").replaceAll("—", "-");
  }

  String _formatDateTimeForPdf(DateTime? dt) {
    if (dt == null) return "-";
    return _formatDateTime(dt);
  }

  pw.Widget _pdfSectionTitle(String text) {
    return pw.Text(
      text,
      style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
    );
  }

  pw.Widget _pdfFieldRow(String label, String value) {
    return pw.Padding(
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
          pw.Expanded(child: pw.Text(value)),
        ],
      ),
    );
  }

  pw.Widget _pdfColoredReportHeader(OrderReportModel r) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(
        color: PdfColor.fromInt(0xFF478FA7),
        borderRadius: pw.BorderRadius.circular(12),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            "Report Information",
            style: pw.TextStyle(
              color: PdfColors.white,
              fontSize: 18,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.SizedBox(height: 6),
          pw.Text(
            "Report ID: ${r.reportId}",
            style: pw.TextStyle(color: PdfColors.white),
          ),
          pw.Text(
            "Report Type: ${r.type}",
            style: pw.TextStyle(color: PdfColors.white),
          ),
          pw.Text(
            "Generated: ${_formatDateTimeForPdf(r.generated)}",
            style: pw.TextStyle(color: PdfColors.white),
          ),
        ],
      ),
    );
  }

  pw.Widget _pdfCardSection({
    required String title,
    required List<pw.Widget> children,
  }) {
    return pw.Container(
      margin: const pw.EdgeInsets.only(top: 12),
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(
        color: PdfColors.white,
        borderRadius: pw.BorderRadius.circular(12),
        border: pw.Border.all(color: PdfColors.grey300, width: 0.8),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          _pdfSectionTitle(title),
          pw.SizedBox(height: 6),
          ...children,
        ],
      ),
    );
  }

  pw.Widget _pdfCellWidget(String text, {bool bold = false}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(6),
      child: pw.Text(
        text,
        textAlign: pw.TextAlign.center,
        style: pw.TextStyle(
          fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
          fontSize: 10,
        ),
      ),
    );
  }

  // ✅ Delivery Details table (PDF) + events appended inside same table
  pw.Widget _pdfDeliveryDetailsTable(OrderReportModel r) {
    final events = _extractEvents(r);

    return pw.Container(
      margin: const pw.EdgeInsets.only(top: 16),
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        color: PdfColors.white,
        borderRadius: pw.BorderRadius.circular(12),
        border: pw.Border.all(color: PdfColors.grey300, width: 0.8),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          _pdfSectionTitle("Delivery Details"),
          pw.SizedBox(height: 8),
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
              // Header: delivery details
              pw.TableRow(
                children: [
                  _pdfCellWidget("Status", bold: true),
                  _pdfCellWidget("Description", bold: true),
                  _pdfCellWidget("Delivery Duration", bold: true),
                  _pdfCellWidget("Remaining Stability", bold: true),
                  _pdfCellWidget("Condition", bold: true),
                ],
              ),

              // Rows: delivery details
              for (final d in r.deliveryDetails)
                pw.TableRow(
                  children: [
                    _pdfCellWidget(d.status),
                    _pdfCellWidget(d.description),
                    _pdfCellWidget(d.duration),
                    _pdfCellWidget(d.stability),
                    _pdfCellWidget(d.condition),
                  ],
                ),

              // ✅ Append events (no separate section/table)
              if (events.isNotEmpty)
                pw.TableRow(
                  children: [
                    _pdfCellWidget("Event", bold: true),
                    _pdfCellWidget("Note", bold: true),
                    _pdfCellWidget("Time", bold: true),
                    _pdfCellWidget("-", bold: true),
                    _pdfCellWidget("-", bold: true),
                  ],
                ),

              for (final e in events)
                pw.TableRow(
                  children: [
                    _pdfCellWidget(e.status),
                    _pdfCellWidget(e.description),
                    _pdfCellWidget(_formatDateTimeForPdf(e.time)),
                    _pdfCellWidget("-"),
                    _pdfCellWidget("-"),
                  ],
                ),
            ],
          ),
        ],
      ),
    );
  }

  // =====================================================
  // Export PDF – FRONTEND ONLY
  //   ✅ No separate events table: events are inside delivery details
  // =====================================================
  Future<void> _exportPdf() async {
    if (_report == null || _isExporting) return;

    setState(() => _isExporting = true);

    try {
      final r = _report!;
      final pdf = pw.Document();

      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(24),
          build: (pw.Context ctx) {
            return [
              pw.Text(
                "Delivery Report",
                style: pw.TextStyle(
                  fontSize: 22,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 16),

              _pdfColoredReportHeader(r),
              pw.SizedBox(height: 12),

              _pdfCardSection(
                title: "Order Information",
                children: [
                  _pdfFieldRow("Order ID", r.orderId),
                  _pdfFieldRow("Order Type", r.orderType ?? "-"),
                  _pdfFieldRow("Status", r.orderStatus),
                  _pdfFieldRow(
                    "Created At",
                    _formatDateTimeForPdf(r.createdAt),
                  ),
                  _pdfFieldRow(
                    "Delivered At",
                    _formatDateTimeForPdf(r.deliveredAt),
                  ),
                  _pdfFieldRow("OTP", r.otpCode),
                  _pdfFieldRow("Priority", r.priority),
                ],
              ),

              _pdfCardSection(
                title: "Patient & Hospital",
                children: [
                  _pdfFieldRow("Patient", r.patientName),
                  _pdfFieldRow(
                    "Phone",
                    r.phoneNumber == null ? "-" : r.phoneNumber!,
                  ),
                  _pdfFieldRow("Hospital", r.hospitalName),
                ],
              ),

              _pdfCardSection(
                title: "Medication Information",
                children: [
                  _pdfFieldRow("Medication Name", r.medicationName),
                  _pdfFieldRow("Allowed Temp", _normalizeText(r.allowedTemp)),
                  _pdfFieldRow("Max Excursion", _normalizeText(r.maxExcursion)),
                  _pdfFieldRow(
                    "Return to Fridge",
                    _normalizeText(r.returnToFridge),
                  ),
                ],
              ),

              // ✅ Delivery details table includes events
              _pdfDeliveryDetailsTable(r),
            ];
          },
        ),
      );

      final bytes = await pdf.save();

      final dir = await getApplicationDocumentsDirectory();
      final filePath = "${dir.path}/report_${r.orderId}.pdf";
      final file = File(filePath);
      await file.writeAsBytes(bytes, flush: true);

      try {
        final result = await OpenFilex.open(filePath);
        if (result.type != ResultType.done) {
          await Printing.sharePdf(
            bytes: bytes,
            filename: "report_${r.orderId}.pdf",
          );
        }
      } catch (_) {
        await Printing.sharePdf(
          bytes: bytes,
          filename: "report_${r.orderId}.pdf",
        );
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Report PDF generated successfully.')),
      );
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Failed to export PDF: $e")));
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  // =====================================================
  // Format date as English string (forced to English)
  // =====================================================
  String _formatDateTime(DateTime? dt) {
    if (dt == null) return "-";
    final local = dt.toLocal();
    return DateFormat('d MMM yyyy, h:mm a').format(local);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          if (_isLoading)
            Center(
              child: CircularProgressIndicator(color: AppColors.buttonBlue),
            )
          else if (_error != null)
            _errorView()
          else if (_report == null)
            Center(
              child: Text(
                "No report data",
                style: TextStyle(fontSize: 14.sp, color: AppColors.detailText),
              ),
            )
          else
            _buildContent(_report!),

          CustomTopBar(title: "report".tr(), showBackButton: true),
        ],
      ),
    );
  }

  // Error UI
  Widget _errorView() {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 25.w),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              "Failed to load report",
              style: TextStyle(
                fontSize: 16.sp,
                fontWeight: FontWeight.w600,
                color: AppColors.alertRed,
              ),
            ),
            SizedBox(height: 8.h),
            Text(
              _error ?? "",
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12.sp, color: AppColors.detailText),
            ),
            SizedBox(height: 20.h),
            ElevatedButton(onPressed: _fetchReport, child: Text("retry".tr())),
          ],
        ),
      ),
    );
  }

  // =====================================================
  // Main content (UI preserved)
  //   ✅ NO events card
  //   ✅ events are appended inside Delivery Details table
  // =====================================================
  Widget _buildContent(OrderReportModel report) {
    return SingleChildScrollView(
      physics: const ClampingScrollPhysics(),
      child: Padding(
        padding: EdgeInsets.only(top: 130.h, left: 25.w, right: 25.w),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _reportInfoCard(report),
            SizedBox(height: 20.h),
            _orderInfoCard(report),
            SizedBox(height: 20.h),
            _patientHospitalCard(report),
            SizedBox(height: 20.h),
            _medicationCard(report),
            SizedBox(height: 20.h),

            // ✅ Delivery details now includes events
            _deliveryDetailsCard(report),

            SizedBox(height: 20.h),
            _exportButton(),
            SizedBox(height: 40.h),
          ],
        ),
      ),
    );
  }

  // Report info
  Widget _reportInfoCard(OrderReportModel r) {
    return _card(
      color: const Color(0xFF478FA7),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _title("report_information".tr(), color: Colors.white, size: 19),
          _row("report_id".tr(), r.reportId, color: Colors.white),
          _row("report_type".tr(), r.type, color: Colors.white),
          _row(
            "generated".tr(),
            _formatDateTime(r.generated),
            color: Colors.white,
            keepOnOneLine: true,
          ),
        ],
      ),
    );
  }

  // Order info
  Widget _orderInfoCard(OrderReportModel r) {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _title("order_information".tr()),
          _row("order_id".tr(), r.orderId),
          _row("order_type".tr(), r.orderType ?? "-"),
          _row("order_status".tr(), r.orderStatus),
          _row("created_at".tr(), _formatDateTime(r.createdAt)),
          _row("delivered_at".tr(), _formatDateTime(r.deliveredAt)),
          _otpRow(r),
          _row(
            "priority".tr(),
            r.priority,
            color: r.priority == "High"
                ? const Color(0xFFCC0000)
                : const Color(0xFF525252),
          ),
        ],
      ),
    );
  }

  // Patient / Hospital info
  Widget _patientHospitalCard(OrderReportModel r) {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _title("patient_hospital".tr()),
          _row("patient".tr(), r.patientName),
          _row("phone_number".tr(), r.phoneNumber ?? "-"),
          _row("hospital".tr(), r.hospitalName, color: const Color(0xFF8FB8C7)),
        ],
      ),
    );
  }

  // Medication info
  Widget _medicationCard(OrderReportModel r) {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _title("medication_information".tr()),
          _row("medication_name_label".tr(), r.medicationName),
          _title("safety_conditions".tr(), size: 13, weight: FontWeight.w600),
          _row("allowed_temp".tr(), r.allowedTemp ?? "-", labelWidth: 180),
          _row("max_excursion".tr(), r.maxExcursion ?? "-"),
          _row(
            "return_to_fridge".tr(),
            r.returnToFridge ?? "-",
            color: const Color(0xFF137713),
          ),
        ],
      ),
    );
  }

  // ✅ Delivery details (UI) + events appended inside same table
  Widget _deliveryDetailsCard(OrderReportModel r) {
    final events = _extractEvents(r);

    final rows = <TableRow>[
      _header([
        "status".tr(),
        "description".tr(),
        "delivery_duration".tr(),
        "remaining_stability".tr(),
        "condition".tr(),
      ]),

      // Delivery details rows
      for (final d in r.deliveryDetails)
        _data(d.status, d.description, d.duration, d.stability, d.condition),

      // ✅ Append events under the same table (no separate timeline)
      if (events.isNotEmpty)
        _header([
          "event".tr(), // add to localization to avoid warning
          "note".tr(), // you already referenced this before
          "time".tr(), // add to localization to avoid warning
          "-", // keep layout stable
          "-", // keep layout stable
        ]),

      for (final e in events)
        TableRow(
          children: [
            _cell(e.status),
            _cell(e.description),
            _cell(_formatDateTime(e.time)),
            _cell("-"),
            _cell("-"),
          ],
        ),
    ];

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
            children: rows,
          ),
        ],
      ),
    );
  }

  // Export button (PDF)
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

  // OTP row
  Widget _otpRow(OrderReportModel r) {
    return Padding(
      padding: EdgeInsets.only(left: 10.w, top: 3.h, bottom: 3.h),
      child: Row(
        children: [
          SizedBox(
            width: 150.w,
            child: Text(
              "otp".tr(),
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: const Color(0xFF11607E),
                fontSize: 13.sp,
              ),
            ),
          ),
          RichText(
            text: TextSpan(
              style: TextStyle(fontSize: 13.sp),
              children: [
                TextSpan(
                  text: "${r.otpCode} ",
                  style: const TextStyle(
                    fontWeight: FontWeight.w500,
                    color: Color(0xFF525252),
                  ),
                ),
                TextSpan(
                  text: r.verified ? "verified".tr() : "",
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF137713),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // =====================================================
  // Helper UI Widgets (UNCHANGED)
  // =====================================================
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
    Color color = const Color(0xFF013A3C),
    double size = 18,
    FontWeight weight = FontWeight.w700,
  }) {
    return Text(
      t,
      style: TextStyle(fontSize: size.sp, fontWeight: weight, color: color),
    );
  }

  Widget _row(
    String label,
    String value, {
    Color color = const Color(0xFF525252),
    double labelWidth = 150,
    bool keepOnOneLine = false,
  }) {
    return Padding(
      padding: EdgeInsets.only(left: 10.w, top: 3.h, bottom: 3.h),
      child: Row(
        children: [
          SizedBox(
            width: labelWidth.w,
            child: Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: color == Colors.white
                    ? Colors.white
                    : const Color(0xFF11607E),
                fontSize: 13.sp,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              softWrap: !keepOnOneLine,
              overflow: TextOverflow.visible,
              style: TextStyle(
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

  // Table header
  TableRow _header(List<String> headers) {
    return TableRow(
      children: headers
          .map(
            (x) => Padding(
              padding: EdgeInsets.symmetric(vertical: 8.h, horizontal: 6.w),
              child: Text(
                x,
                textAlign: TextAlign.center,
                style: TextStyle(
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

  // Table row for delivery details
  TableRow _data(
    String status,
    String description,
    String duration,
    String stability,
    String condition,
  ) {
    final condColor = condition == "Risk"
        ? const Color(0xFFE4C600)
        : const Color(0xFF137713);

    return TableRow(
      children: [
        _cell(status),
        _cell(description),
        _colored(duration, const Color(0xFF137713)),
        _colored(stability, const Color(0xFFCC0000)),
        _cell(condition, condColor),
      ],
    );
  }

  // Highlighted cell
  Widget _colored(String text, Color c) {
    final match = RegExp(r'(\d+\s*h\s*\d*\s*m?)').firstMatch(text);
    if (match == null) return _cell(text);

    final timePart = match.group(0)!;

    return Padding(
      padding: EdgeInsets.symmetric(vertical: 6.h),
      child: RichText(
        textAlign: TextAlign.center,
        text: TextSpan(
          children: [
            TextSpan(
              text: timePart,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: c,
                fontSize: 12.sp,
              ),
            ),
            TextSpan(
              text: text.replaceAll(timePart, ''),
              style: TextStyle(
                fontWeight: FontWeight.w500,
                color: const Color(0xFF525252),
                fontSize: 12.sp,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Normal table cell
  Widget _cell(String text, [Color c = const Color(0xFF525252)]) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 6.h, horizontal: 6.w),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontWeight: FontWeight.w500,
          color: c,
          fontSize: 11.sp,
        ),
      ),
    );
  }
}

// =====================================================
// Internal event model for UI/PDF (no backend changes here)
// =====================================================
class _ReportEvent {
  final DateTime? time;
  final String status;
  final String description;

  _ReportEvent({
    required this.time,
    required this.status,
    required this.description,
  });
}
