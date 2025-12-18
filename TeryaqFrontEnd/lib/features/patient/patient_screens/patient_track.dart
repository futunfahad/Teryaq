// lib/features/patient/patient_screens/patient_track.dart
//
// PatientTrackScreen (FINAL MERGE)
// ✅ Preserves teammate UI/styling (cards/layout/colors).
// ✅ Preserves your map/dashboard behavior:
//    - View -> PatientDashboardScreen(orderId, showMap)
//    - showMap ONLY when status is "On Route"
// ✅ Safe logic: always tracks the selected orderId (never “switches orders”)
// ✅ Timeline uses backend-provided "events" from /patient/{national_id}/track
// ✅ Adds pull-to-refresh + safe polling (same endpoint) without altering UI.
// ✅ FIX: OTP now shows real value (from /track or from report endpoint).

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

import 'package:teryagapptry/constants/app_colors.dart';
import 'package:teryagapptry/widgets/custom_top_bar.dart';
import 'package:teryagapptry/widgets/order_status_badge.dart';
import 'package:teryagapptry/services/patient_service.dart';

// IMPORTANT: make sure this import matches your actual dashboard file name
import 'patient_dashboard.dart';

// Same gateway used in dashboard (only for ETA formatting consistency)
const String kGatewayBase = 'http://192.168.8.113:8088';

class PatientTrackScreen extends StatefulWidget {
  final String? orderId; // UUID (preferred)
  final String? codeFallback; // fallback if you ever pass code instead of UUID

  const PatientTrackScreen({super.key, this.orderId, this.codeFallback});

  @override
  State<PatientTrackScreen> createState() => _PatientTrackScreenState();
}

// ============================================================================
// Timeline entry extracted from backend "events" list (returned by /track).
// ============================================================================
class _TimelineEntry {
  final String status;
  final String message;
  final String time;

  const _TimelineEntry({
    required this.status,
    required this.message,
    required this.time,
  });
}

class _PatientTrackScreenState extends State<PatientTrackScreen> {
  Map<String, dynamic>? _order;

  // -----------------------
  // Date/time formatting
  // -----------------------
  final DateFormat _uiDt = DateFormat('d MMM yyyy, h:mm a', 'en');

  String _formatUiTime(String raw) {
    final s = raw.trim();
    if (s.isEmpty || s == "-") return "";

    // 1) ISO parse
    try {
      final dt = DateTime.parse(s).toLocal();
      return _uiDt.format(dt);
    } catch (_) {}

    // 2) Common backend/display parse: "14 Dec 2025, 10:00 AM"
    try {
      final dt = DateFormat('d MMM yyyy, h:mm a', 'en').parseLoose(s);
      return _uiDt.format(dt);
    } catch (_) {}

    // fallback: keep original but not empty
    return s;
  }

  String _formatMinutesToHm(int minutes) {
    if (minutes <= 0) return "0m";
    final h = minutes ~/ 60;
    final m = minutes % 60;
    if (h > 0 && m > 0) return "${h}h ${m}m";
    if (h > 0) return "${h}h";
    return "${m}m";
  }

  // -----------------------
  // ETA (dashboard-like)
  // -----------------------
  String? _osrmEtaHm;
  bool _etaBusy = false;

  Map<String, double>? _extractCoords(Map<String, dynamic> track) {
    double? dLat, dLon, pLat, pLon;

    final driver = track["driver"];
    if (driver is Map) {
      if (driver["lat"] is num) dLat = (driver["lat"] as num).toDouble();
      if (driver["lon"] is num) dLon = (driver["lon"] as num).toDouble();
    }

    final patient = track["patient"];
    if (patient is Map) {
      if (patient["lat"] is num) pLat = (patient["lat"] as num).toDouble();
      if (patient["lon"] is num) pLon = (patient["lon"] as num).toDouble();
    }

    // fallback flat keys
    if (dLat == null && track["driver_lat"] is num) {
      dLat = (track["driver_lat"] as num).toDouble();
    }
    if (dLon == null && track["driver_lon"] is num) {
      dLon = (track["driver_lon"] as num).toDouble();
    }
    if (pLat == null && track["patient_lat"] is num) {
      pLat = (track["patient_lat"] as num).toDouble();
    }
    if (pLon == null && track["patient_lon"] is num) {
      pLon = (track["patient_lon"] as num).toDouble();
    }

    if (dLat == null || dLon == null || pLat == null || pLon == null) {
      return null;
    }

    return {"dLat": dLat, "dLon": dLon, "pLat": pLat, "pLon": pLon};
  }

  Future<void> _refreshOsrmEtaIfNeeded(
    Map<String, dynamic> orderMap,
    String status,
  ) async {
    // Only show/compute ETA for On Route (your rule)
    if (status != "On Route") {
      if (_osrmEtaHm != null && mounted) {
        setState(() => _osrmEtaHm = null);
      }
      return;
    }

    if (_etaBusy) return;

    final coords = _extractCoords(orderMap);
    if (coords == null) return;

    _etaBusy = true;
    try {
      final fromLat = coords["dLat"]!;
      final fromLon = coords["dLon"]!;
      final toLat = coords["pLat"]!;
      final toLon = coords["pLon"]!;

      final uri = Uri.parse(
        "$kGatewayBase/route/v1/driving/$fromLon,$fromLat;$toLon,$toLat?overview=false",
      );

      final res = await http.get(uri).timeout(const Duration(seconds: 6));
      if (res.statusCode != 200) return;

      final decoded = jsonDecode(res.body);
      final routes = decoded["routes"] as List?;
      if (routes == null || routes.isEmpty) return;

      final first = routes.first as Map<String, dynamic>;
      final durationRaw = first["duration"]; // seconds
      final seconds = (durationRaw is num)
          ? durationRaw.toDouble()
          : double.tryParse(durationRaw.toString()) ?? 0;

      final minutes = (seconds / 60.0).round();

      if (!mounted) return;
      setState(() => _osrmEtaHm = _formatMinutesToHm(minutes));
    } catch (_) {
      // ignore
    } finally {
      _etaBusy = false;
    }
  }

  bool _isLoading = true;
  String? _errorMessage;

  bool _eventsLoading = false;
  List<_TimelineEntry> _timeline = const [];

  // ✅ OTP state
  String? _otp;
  bool _otpLoading = false;

  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _loadTrackOrder();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // STATUS NORMALIZATION (UI labels)
  // ---------------------------------------------------------------------------
  String _normalizeStatus(dynamic raw) {
    final s = (raw ?? "").toString().trim().toLowerCase();

    if (s == "pending") return "Pending";
    if (s == "accepted") return "Accepted";

    if (s == "on_delivery" ||
        s == "on delivery" ||
        s == "out_for_delivery" ||
        s == "out for delivery" ||
        s == "in_progress" ||
        s == "in progress") {
      return "On Delivery";
    }

    if (s == "on_route" ||
        s == "on route" ||
        s == "en_route" ||
        s == "en route" ||
        s == "en-route") {
      return "On Route";
    }

    if (s == "delivered") return "Delivered";
    if (s == "delivery_failed" || s == "delivery failed" || s == "failed") {
      return "Delivery Failed";
    }
    if (s == "rejected") return "Rejected";

    final rawStr = (raw ?? "").toString().trim();
    return rawStr.isEmpty ? "Pending" : rawStr;
  }

  bool _isTrackableStatus(String status) {
    return status == "On Delivery" || status == "On Route";
  }

  String _safeStr(dynamic v) => v == null ? "" : v.toString();

  String _extractOrderId(Map<String, dynamic> m) {
    final a = _safeStr(m["order_id"]);
    final b = _safeStr(m["orderId"]);
    final c = _safeStr(m["id"]);
    final d = _safeStr(m["uuid"]);
    final e = _safeStr(m["code"]);
    final f = _safeStr(m["order_code"]);
    final g = _safeStr(m["orderCode"]);

    for (final x in [a, b, c, d, e, f, g]) {
      if (x.trim().isNotEmpty) return x.trim();
    }
    return "";
  }

  String _truncateId(String id, {int keep = 10}) {
    if (id.trim().isEmpty) return "-";
    final v = id.trim();
    if (v.length <= keep) return v;
    return v.substring(0, keep);
  }

  double _calculateProgress(String status) {
    switch (status) {
      case "Pending":
        return 1 / 4;
      case "Accepted":
        return 2 / 4;
      case "On Delivery":
        return 3 / 4;
      case "On Route":
        return 1.0;
      case "Delivered":
      case "Delivery Failed":
      case "Rejected":
        return 1.0;
      default:
        return 0.0;
    }
  }

  // ---------------------------------------------------------------------------
  // ✅ OTP helpers
  // ---------------------------------------------------------------------------
  String? _extractOtpFromTrack(Map<String, dynamic> orderMap) {
    final candidates = <dynamic>[
      orderMap["otp"],
      orderMap["otp_code"],
      orderMap["otpCode"],
      orderMap["code"],
      orderMap["otpCodeMasked"],
    ];

    for (final v in candidates) {
      final s = _safeStr(v).trim();
      if (s.isNotEmpty) return s;
    }

    // Sometimes nested
    final o = orderMap["order"];
    if (o is Map) {
      final vv = (o["otp"] ?? o["otp_code"] ?? o["otpCode"] ?? "").toString();
      final s = vv.trim();
      if (s.isNotEmpty) return s;
    }

    return null;
  }

  Future<void> _refreshOtpIfNeeded({
    required String orderId,
    required String currentStatus,
    required Map<String, dynamic> orderMap,
    bool silent = false,
  }) async {
    // Show OTP only when On Route (your rule)
    if (currentStatus != "On Route") {
      if (_otp != null || _otpLoading) {
        if (!mounted) return;
        setState(() {
          _otp = null;
          _otpLoading = false;
        });
      }
      return;
    }

    // 1) try from track payload
    final direct = _extractOtpFromTrack(orderMap);
    if (direct != null && direct.trim().isNotEmpty) {
      if (!mounted) return;
      setState(() {
        _otp = direct.trim();
        _otpLoading = false;
      });
      return;
    }

    // 2) otherwise fetch from report endpoint (so OTP actually appears)
    if (_otpLoading) return;

    if (!mounted) return;
    setState(() => _otpLoading = true);

    try {
      final otp = await PatientService.fetchOtpForOrder(orderId: orderId);
      if (!mounted) return;

      setState(() {
        _otp = (otp ?? "").trim().isEmpty ? null : otp!.trim();
        _otpLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _otpLoading = false);
    }
  }

  // ---------------------------------------------------------------------------
  // Load Track (always for the selected orderId if provided)
  // ---------------------------------------------------------------------------
  Future<void> _loadTrackOrder() async {
    _pollTimer?.cancel();

    setState(() {
      _isLoading = true;
      _errorMessage = null;

      _timeline = const [];
      _eventsLoading = false;

      _otp = null;
      _otpLoading = false;

      // ETA state reset
      _osrmEtaHm = null;
    });

    try {
      final targetId = (widget.orderId ?? "").trim();
      final targetCode = (widget.codeFallback ?? "").trim();

      String queryId = "";
      if (targetId.isNotEmpty) queryId = targetId;
      if (queryId.isEmpty && targetCode.isNotEmpty) queryId = targetCode;

      debugPrint("TRACK: calling /track with order_id=$queryId");

      final Map<String, dynamic> track = queryId.isNotEmpty
          ? await PatientService.fetchTrackOrder(orderId: queryId)
          : await PatientService.fetchTrackOrder();

      if (track.isEmpty) {
        throw Exception("No order found to track.");
      }

      if (!mounted) return;

      final orderMap = Map<String, dynamic>.from(track);
      setState(() {
        _order = orderMap;
        _isLoading = false;
      });

      // Build timeline from backend-provided events (preferred)
      await _loadTimelineFromOrder(orderMap);

      final oid = _extractOrderId(orderMap).trim();
      if (oid.isEmpty) return;

      final currentStatus = _normalizeStatus(orderMap["status"]);

      // ✅ ETA refresh (only On Route)
      await _refreshOsrmEtaIfNeeded(orderMap, currentStatus);

      // ✅ OTP refresh (only On Route)
      await _refreshOtpIfNeeded(
        orderId: oid,
        currentStatus: currentStatus,
        orderMap: orderMap,
      );

      if (_isTrackableStatus(currentStatus)) {
        _startPolling(oid);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = e.toString();
      });
    }
  }

  void _startPolling(String orderId) {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 20), (_) async {
      if (!mounted) return;
      await _silentRefresh(orderId);
    });
  }

  Future<void> _silentRefresh(String orderId) async {
    try {
      final track = await PatientService.fetchTrackOrder(orderId: orderId);
      if (track.isNotEmpty && mounted) {
        final orderMap = Map<String, dynamic>.from(track);
        final status = _normalizeStatus(orderMap["status"]);

        setState(() => _order = orderMap);
        await _loadTimelineFromOrder(orderMap, silent: true);

        // ✅ ETA refresh (only On Route)
        await _refreshOsrmEtaIfNeeded(orderMap, status);

        await _refreshOtpIfNeeded(
          orderId: orderId,
          currentStatus: status,
          orderMap: orderMap,
          silent: true,
        );
      }
    } catch (_) {
      // silent refresh: ignore errors
    }
  }

  Future<void> _loadTimelineFromOrder(
    Map<String, dynamic> orderMap, {
    bool silent = false,
  }) async {
    if (!silent) {
      setState(() {
        _eventsLoading = true;
        _timeline = const [];
      });
    }

    try {
      final rawEvents = orderMap["events"];
      final List<_TimelineEntry> timeline = _buildTimelineFromEvents(rawEvents);

      if (!mounted) return;
      setState(() {
        _timeline = timeline;
        _eventsLoading = false;
      });
    } catch (_) {
      // fallback: simple timeline based on current status
      final s = _normalizeStatus(orderMap["status"]);
      final fallback = _fallbackTimelineForStatus(s);

      if (!mounted) return;
      setState(() {
        _timeline = fallback;
        _eventsLoading = false;
      });
    }
  }

  List<_TimelineEntry> _buildTimelineFromEvents(dynamic rawEvents) {
    if (rawEvents is! List) return const [];

    final List<Map<String, dynamic>> events = rawEvents
        .where((e) => e is Map)
        .map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e as Map))
        .toList();

    if (events.isEmpty) return const [];

    final List<_TimelineEntry> out = [];
    for (final ev in events) {
      final status = _normalizeStatus(ev["status"] ?? ev["event_status"]);
      final msg = _safeStr(
        ev["description"] ?? ev["event_message"] ?? ev["message"],
      );

      final tsRaw = _safeStr(
        ev["timestamp"] ?? ev["time"] ?? ev["created_at"] ?? ev["createdAt"],
      );

      out.add(
        _TimelineEntry(
          status: status,
          message: msg,
          time: _formatUiTime(tsRaw),
        ),
      );
    }

    return out;
  }

  List<_TimelineEntry> _fallbackTimelineForStatus(String status) {
    final now = "";
    final List<_TimelineEntry> base = [
      const _TimelineEntry(
        status: "Pending",
        message: "Order created.",
        time: "",
      ),
    ];

    if (status == "Accepted") {
      base.add(
        const _TimelineEntry(
          status: "Accepted",
          message: "Hospital approved the order.",
          time: "",
        ),
      );
    } else if (status == "On Delivery") {
      base.add(
        const _TimelineEntry(
          status: "Accepted",
          message: "Hospital approved the order.",
          time: "",
        ),
      );
      base.add(
        const _TimelineEntry(
          status: "On Delivery",
          message: "Driver started delivery process.",
          time: "",
        ),
      );
    } else if (status == "On Route") {
      base.add(
        const _TimelineEntry(
          status: "Accepted",
          message: "Hospital approved the order.",
          time: "",
        ),
      );
      base.add(
        const _TimelineEntry(
          status: "On Delivery",
          message: "Driver started delivery process.",
          time: "",
        ),
      );
      base.add(
        const _TimelineEntry(
          status: "On Route",
          message: "Driver is on route to the patient.",
          time: "",
        ),
      );
    } else if (status == "Delivered") {
      base.add(
        const _TimelineEntry(
          status: "Delivered",
          message: "Order delivered successfully.",
          time: "",
        ),
      );
    } else if (status == "Delivery Failed") {
      base.add(
        const _TimelineEntry(
          status: "Delivery Failed",
          message: "Delivery failed. Please contact support.",
          time: "",
        ),
      );
    } else if (status == "Rejected") {
      base.add(
        const _TimelineEntry(
          status: "Rejected",
          message: "Order was canceled/rejected.",
          time: "",
        ),
      );
    }

    return base
        .map(
          (e) => _TimelineEntry(
            status: e.status,
            message: e.message,
            time: e.time.isEmpty ? now : e.time,
          ),
        )
        .toList();
  }

  List<_TimelineEntry> _timelineNewestFirst() {
    if (_timeline.isEmpty) return const [];
    return _timeline.reversed.toList();
  }

  // ---------------------------------------------------------------------------
  // ETA resolution: prefer telemetry strings from /track (fallback)
  // ---------------------------------------------------------------------------
  String _etaDateFromTrack(Map<String, dynamic> track) {
    final candidates = <dynamic>[
      track["estimatedDate"],
      track["estimated_date"],
      track["estimated_delivery_date"],
      track["estimatedDeliveryDate"],
    ];
    for (final v in candidates) {
      final s = _safeStr(v).trim();
      if (s.isNotEmpty) return s;
    }
    return "-";
  }

  String _etaTextFromTrack(Map<String, dynamic> track) {
    final candidates = <dynamic>[
      track["arrival_time"],
      track["eta_hm"],
      track["etaHm"],
      track["eta"],
    ];
    for (final v in candidates) {
      final s = _safeStr(v).trim();
      if (s.isNotEmpty) return s;
    }
    return "-";
  }

  // ---------------------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.appBackground,
      appBar: PreferredSize(
        preferredSize: Size.fromHeight(90.h),
        child: CustomTopBar(
          title: "track_order".tr(),
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
            "no_active_order_or_error".tr(args: [_errorMessage ?? ""]),
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

    if (_order == null || _order!.isEmpty) {
      return Padding(
        padding: EdgeInsets.symmetric(horizontal: 24.w),
        child: Center(
          child: Text(
            "no_active_order".tr(),
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

    final map = _order!;
    final String currentStatus = _normalizeStatus(map["status"]);
    final String orderId = _extractOrderId(map);

    final bool canView = _isTrackableStatus(currentStatus);
    final bool showEta = (currentStatus == "On Route");

    // showMap ONLY when On Route
    final bool showMap = (currentStatus == "On Route");

    final rawEtaDate = _etaDateFromTrack(map);
    final formattedEtaDate = _formatUiTime(rawEtaDate);
    final String estimatedDate = showEta
        ? (formattedEtaDate.isNotEmpty ? formattedEtaDate : rawEtaDate)
        : "";

    final String estimatedAfterText = showEta
        ? (_osrmEtaHm ?? _etaTextFromTrack(map))
        : "";

    final double progress = _calculateProgress(currentStatus);
    final newestFirstTimeline = _timelineNewestFirst();

    return RefreshIndicator(
      onRefresh: () async => _loadTrackOrder(),
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        child: Padding(
          padding: EdgeInsets.only(top: 25.h, left: 25.w, right: 25.w),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildPrimaryStatusCard(
                currentStatus: currentStatus,
                orderId: orderId,
                progress: progress,
                canView: canView,
                showMap: showMap,
                showEta: showEta,
                estimatedDate: estimatedDate,
                estimatedAfterText: estimatedAfterText,
              ),
              SizedBox(height: 10.h),
              SizedBox(height: 15.h),
              if (_eventsLoading)
                Center(
                  child: Padding(
                    padding: EdgeInsets.only(top: 10.h, bottom: 10.h),
                    child: SizedBox(
                      width: 28.w,
                      height: 28.w,
                      child: const CircularProgressIndicator(),
                    ),
                  ),
                )
              else if (newestFirstTimeline.isEmpty)
                _noEventsCard()
              else
                ..._buildTimelineCardsFromEntries(newestFirstTimeline),
              SizedBox(height: 30.h),
            ],
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // PRIMARY CARD (UI preserved)
  // ---------------------------------------------------------------------------
  Widget _buildPrimaryStatusCard({
    required String currentStatus,
    required String orderId,
    required double progress,
    required bool canView,
    required bool showMap,
    required bool showEta,
    required String estimatedDate,
    required String estimatedAfterText,
  }) {
    final shownId = _truncateId(orderId, keep: 10);

    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(15.w, 15.h, 19.w, 15.h),
      decoration: BoxDecoration(
        color: const Color(0xFFEBF4F6),
        borderRadius: BorderRadius.circular(12.r),
        boxShadow: AppColors.universalShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              buildStatusBadge(
                currentStatus,
                bottomWidget: Text(
                  shownId != "-" ? "#$shownId" : "-",
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 11.sp,
                    fontWeight: FontWeight.w500,
                    color: AppColors.bodyText,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: 12.h),
          Container(
            height: 4.h,
            decoration: BoxDecoration(
              color: AppColors.buttonRed.withOpacity(0.12),
              borderRadius: BorderRadius.circular(25.r),
            ),
            child: Align(
              alignment: Alignment.centerLeft,
              child: FractionallySizedBox(
                widthFactor: progress.clamp(0.0, 1.0),
                child: Container(
                  height: 4.h,
                  decoration: BoxDecoration(
                    color: AppColors.buttonRed,
                    borderRadius: BorderRadius.circular(999.r),
                  ),
                ),
              ),
            ),
          ),
          if (showEta) ...[
            SizedBox(height: 14.h),
            Text(
              "estimated_delivery_time".tr(),
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 13.sp,
                fontWeight: FontWeight.w600,
                color: AppColors.bodyText,
              ),
            ),
            SizedBox(height: 8.h),
            Row(
              children: [
                Icon(
                  Icons.calendar_today_rounded,
                  size: 15.sp,
                  color: AppColors.bodyText,
                ),
                SizedBox(width: 10.w),
                Text(
                  estimatedDate,
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 13.sp,
                    fontWeight: FontWeight.w500,
                    color: AppColors.detailText,
                  ),
                ),
                SizedBox(width: 16.w),
                Icon(
                  Icons.access_time_rounded,
                  size: 16.sp,
                  color: AppColors.bodyText,
                ),
                SizedBox(width: 10.w),
                Expanded(
                  child: Text(
                    estimatedAfterText,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 13.sp,
                      fontWeight: FontWeight.w500,
                      color: AppColors.detailText,
                    ),
                  ),
                ),
              ],
            ),
          ],
          SizedBox(height: 14.h),
          Align(
            alignment: Alignment.centerRight,
            child: SizedBox(
              width: 61.w,
              height: 24.h,
              child: IgnorePointer(
                ignoring: !canView,
                child: Opacity(
                  opacity: canView ? 1.0 : 0.55,
                  child: TextButton(
                    onPressed: () {
                      if (!canView) return;

                      final fullOrderId = orderId.trim();
                      if (fullOrderId.isEmpty) return;

                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => PatientDashboardScreen(
                            orderId: fullOrderId,
                            showMap: showMap,
                          ),
                        ),
                      );
                    },
                    style: TextButton.styleFrom(
                      padding: EdgeInsets.zero,
                      backgroundColor: canView
                          ? AppColors.buttonRed
                          : const Color(0xFFBDBDBD),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(9.r),
                      ),
                    ),
                    child: Text(
                      "view".tr(),
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 10.sp,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Timeline UI (UI preserved)
  // ---------------------------------------------------------------------------
  Widget _noEventsCard() {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(15.w, 15.h, 19.w, 15.h),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(12.r),
        boxShadow: AppColors.universalShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          buildStatusBadge("Pending"),
          SizedBox(height: 10.h),
          Text(
            "No delivery events recorded yet.",
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 12.sp,
              fontWeight: FontWeight.w500,
              color: AppColors.detailText,
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildTimelineCardsFromEntries(
    List<_TimelineEntry> entriesNewestFirst,
  ) {
    final List<Widget> list = [];
    for (final entry in entriesNewestFirst) {
      list.add(_buildStatusCardFromEntry(entry));
      list.add(SizedBox(height: 20.h));
    }
    return list;
  }

  Widget _buildStatusCardFromEntry(_TimelineEntry entry) {
    switch (entry.status) {
      case "On Route":
        return _onRouteCard(entry: entry);
      case "On Delivery":
        return _onDeliveryCard(entry: entry);
      case "Accepted":
        return _acceptedCard(entry: entry);
      case "Pending":
        return _pendingCard(entry: entry);
      default:
        return _genericEventCard(entry);
    }
  }

  Widget _genericEventCard(_TimelineEntry entry) {
    return _statusCard(
      status: entry.status,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (entry.message.trim().isNotEmpty)
            Text(
              entry.message,
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 12.sp,
                fontWeight: FontWeight.w500,
                color: AppColors.headingText,
              ),
            ),
          if (entry.time.trim().isNotEmpty) ...[
            SizedBox(height: 8.h),
            Text(
              entry.time,
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 11.sp,
                fontWeight: FontWeight.w500,
                color: AppColors.detailText,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _pendingCard({required _TimelineEntry entry}) {
    final String orderType = _safeStr(_order?["order_type"]).isNotEmpty
        ? _safeStr(_order?["order_type"])
        : (_safeStr(_order?["orderType"]).isNotEmpty
              ? _safeStr(_order?["orderType"])
              : "Delivery");

    final String placedAtRaw = _safeStr(_order?["created_at"]).isNotEmpty
        ? _safeStr(_order?["created_at"])
        : (_safeStr(_order?["placed_at"]).isNotEmpty
              ? _safeStr(_order?["placed_at"])
              : "-");

    final String placedAt = (placedAtRaw.trim() == "-")
        ? "-"
        : (_formatUiTime(placedAtRaw).isNotEmpty
              ? _formatUiTime(placedAtRaw)
              : placedAtRaw);

    return _statusCard(
      status: "Pending",
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "pending_message".tr(),
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 12.sp,
              fontWeight: FontWeight.w500,
              color: AppColors.headingText,
            ),
          ),
          if (entry.message.trim().isNotEmpty) ...[
            SizedBox(height: 8.h),
            Text(
              entry.message,
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 11.sp,
                fontWeight: FontWeight.w500,
                color: AppColors.detailText,
              ),
            ),
          ],
          SizedBox(height: 10.h),
          Row(
            children: [
              Text(
                "${"order_type".tr()}:",
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 12.sp,
                  fontWeight: FontWeight.w700,
                  color: AppColors.bodyText,
                ),
              ),
              SizedBox(width: 6.w),
              Text(
                orderType,
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 12.sp,
                  fontWeight: FontWeight.w500,
                  color: AppColors.detailText,
                ),
              ),
            ],
          ),

          if (entry.time.trim().isNotEmpty) ...[
            SizedBox(height: 6.h),
            Text(
              entry.time,
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 11.sp,
                fontWeight: FontWeight.w500,
                color: AppColors.detailText,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _acceptedCard({required _TimelineEntry entry}) {
    final String priority = _safeStr(_order?["priority_level"]).isNotEmpty
        ? _safeStr(_order?["priority_level"])
        : (_safeStr(_order?["priority"]).isNotEmpty
              ? _safeStr(_order?["priority"])
              : "Normal");

    return _statusCard(
      status: "Accepted",
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "accepted_message".tr(),
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 12.sp,
              fontWeight: FontWeight.w500,
              color: AppColors.headingText,
            ),
          ),
          if (entry.message.trim().isNotEmpty) ...[
            SizedBox(height: 8.h),
            Text(
              entry.message,
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 11.sp,
                fontWeight: FontWeight.w500,
                color: AppColors.detailText,
              ),
            ),
          ],
          SizedBox(height: 10.h),
          Row(
            children: [
              Text(
                "${"order_priority_level".tr()}:",
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 12.sp,
                  fontWeight: FontWeight.w700,
                  color: AppColors.bodyText,
                ),
              ),
              SizedBox(width: 6.w),
              Text(
                priority,
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 12.sp,
                  fontWeight: FontWeight.w700,
                  color: AppColors.buttonRed,
                ),
              ),
            ],
          ),
          if (entry.time.trim().isNotEmpty) ...[
            SizedBox(height: 6.h),
            Text(
              entry.time,
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 11.sp,
                fontWeight: FontWeight.w500,
                color: AppColors.detailText,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _onDeliveryCard({required _TimelineEntry entry}) {
    final String driverName = _safeStr(_order?["driverName"]).isNotEmpty
        ? _safeStr(_order?["driverName"])
        : (_safeStr(_order?["driver_name"]).isNotEmpty
              ? _safeStr(_order?["driver_name"])
              : "-");

    final String driverPhone = _safeStr(_order?["driverPhone"]).isNotEmpty
        ? _safeStr(_order?["driverPhone"])
        : (_safeStr(_order?["driver_phone"]).isNotEmpty
              ? _safeStr(_order?["driver_phone"])
              : "-");

    return _statusCard(
      status: "On Delivery",
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "driver_on_the_way".tr(),
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 12.sp,
              fontWeight: FontWeight.w500,
              color: AppColors.headingText,
            ),
          ),
          if (entry.message.trim().isNotEmpty) ...[
            SizedBox(height: 8.h),
            Text(
              entry.message,
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 11.sp,
                fontWeight: FontWeight.w500,
                color: AppColors.detailText,
              ),
            ),
          ],
          SizedBox(height: 10.h),
          Row(
            children: [
              Text(
                "${"driver_name".tr()}:",
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 12.sp,
                  fontWeight: FontWeight.w700,
                  color: AppColors.bodyText,
                ),
              ),
              SizedBox(width: 6.w),
              Expanded(
                child: Text(
                  driverName,
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
          Row(
            children: [
              Text(
                "${"driver_phone_number".tr()}:",
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 12.sp,
                  fontWeight: FontWeight.w700,
                  color: AppColors.bodyText,
                ),
              ),
              SizedBox(width: 6.w),
              Expanded(
                child: Text(
                  driverPhone,
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
          if (entry.time.trim().isNotEmpty) ...[
            SizedBox(height: 6.h),
            Text(
              entry.time,
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 11.sp,
                fontWeight: FontWeight.w500,
                color: AppColors.detailText,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _onRouteCard({required _TimelineEntry entry}) {
    const Color accent = Color(0xFF6B7280);

    final String driverName = _safeStr(_order?["driverName"]).isNotEmpty
        ? _safeStr(_order?["driverName"])
        : (_safeStr(_order?["driver_name"]).isNotEmpty
              ? _safeStr(_order?["driver_name"])
              : "-");

    final String driverPhone = _safeStr(_order?["driverPhone"]).isNotEmpty
        ? _safeStr(_order?["driverPhone"])
        : (_safeStr(_order?["driver_phone"]).isNotEmpty
              ? _safeStr(_order?["driver_phone"])
              : "-");

    // ✅ Real OTP display (fallback to masked while loading/empty)
    final String otpDisplay = (_otp != null && _otp!.trim().isNotEmpty)
        ? _otp!.trim()
        : (_otpLoading ? "..." : "• • • •");

    return _statusCard(
      status: "On Route",
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "driver_on_route_live_tracking".tr(),
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 12.sp,
              fontWeight: FontWeight.w500,
              color: AppColors.headingText,
            ),
          ),
          if (entry.message.trim().isNotEmpty) ...[
            SizedBox(height: 8.h),
            Text(
              entry.message,
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 11.sp,
                fontWeight: FontWeight.w500,
                color: AppColors.detailText,
              ),
            ),
          ],
          SizedBox(height: 10.h),
          Row(
            children: [
              Text(
                "${"driver_name".tr()}:",
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 12.sp,
                  fontWeight: FontWeight.w700,
                  color: AppColors.bodyText,
                ),
              ),
              SizedBox(width: 6.w),
              Expanded(
                child: Text(
                  driverName,
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
          Row(
            children: [
              Text(
                "${"driver_phone_number".tr()}:",
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 12.sp,
                  fontWeight: FontWeight.w700,
                  color: AppColors.bodyText,
                ),
              ),
              SizedBox(width: 6.w),
              Expanded(
                child: Text(
                  driverPhone,
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
          if (entry.time.trim().isNotEmpty) ...[
            SizedBox(height: 6.h),
            Text(
              entry.time,
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 11.sp,
                fontWeight: FontWeight.w500,
                color: AppColors.detailText,
              ),
            ),
          ],
          SizedBox(height: 10.h),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Text(
                "otp".tr(),
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 13.sp,
                  fontWeight: FontWeight.w800,
                  color: accent,
                ),
              ),
              SizedBox(width: 8.w),
              Container(
                padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 3.h),
                decoration: BoxDecoration(
                  color: accent,
                  borderRadius: BorderRadius.circular(20.r),
                ),
                child: Text(
                  otpDisplay,
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 12.sp,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _statusCard({required String status, required Widget child}) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(15.w, 15.h, 19.w, 15.h),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(12.r),
        boxShadow: AppColors.universalShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          buildStatusBadge(status),
          SizedBox(height: 10.h),
          child,
        ],
      ),
    );
  }
}
