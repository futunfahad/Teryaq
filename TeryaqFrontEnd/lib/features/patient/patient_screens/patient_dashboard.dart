// lib/features/patient/patient_screens/patient_dashboard.dart

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' as latlng;
import 'package:easy_localization/easy_localization.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:teryagapptry/constants/app_colors.dart';
import 'package:teryagapptry/widgets/custom_top_bar.dart';
import 'package:teryagapptry/services/patient_service.dart';

// ===============================================================
// PATIENT DASHBOARD — DRIVER-LIKE (IoT GPS authoritative)
// ✅ /iot/live is authoritative for GPS + temperature + allowed_range
// ✅ Track used ONLY once (patient destination fallback)
// ✅ Throttled route fetching to avoid map crashes / spam
// ✅ Periodic notifications refresh (order-specific)
// ✅ Smooth map re-centering only when movement is meaningful
// ===============================================================

const String kGatewayBase = 'http://192.168.8.113:8088';
const String kApiBase = 'http://192.168.8.113:8000';

class PatientDashboardScreen extends StatefulWidget {
  final String orderId;

  /// Privacy rule:
  /// - true: show map
  /// - false: hide map and show privacy message (e.g., when status is "On Delivery")
  final bool showMap;

  const PatientDashboardScreen({
    super.key,
    required this.orderId,
    this.showMap = true,
  });

  @override
  State<PatientDashboardScreen> createState() => _PatientDashboardState();
}

class _PatientDashboardState extends State<PatientDashboardScreen> {
  final MapController _mapController = MapController();

  bool _mapReady = false;

  bool _isBootstrapping = true;
  bool _isRouteLoading = false;
  String? _error;

  // Map state
  latlng.LatLng? _patientLatLng; // destination
  latlng.LatLng? _driverLatLng; // moving from iot/live

  List<Marker> _markers = [];
  List<Polyline> _polylines = [];

  // Dashboard values
  String _temperatureText = "—";
  String _arrivalTimeText = "—";
  String _stabilityTimeText = "—";

  // Allowed temp range
  double _minTemp = 2.0;
  double _maxTemp = 8.0;

  // Timers
  Timer? _pollTimer;
  Timer? _countdownTimer;

  int _maxExcursionSeconds = 0;
  int _elapsedExcursionSeconds = 0;
  bool _inExcursion = false;
  DateTime? _lastCountdownTick;

  bool _tickBusy = false;

  // Notifications (same expandable bottom bar as Driver)
  bool _isExpanded = true;
  bool _isNotifLoading = false;
  List<String> _notifications = [];

  // SharedPrefs keys for countdown state
  String _excKey(String orderId) => "excursion_state_$orderId";

  // Refresh cadence
  int _pollCount = 0; // increments every tick
  static const int _notifRefreshEveryTicks = 5; // every 10 seconds (poll=2s)

  // Throttle route fetching
  DateTime? _lastRouteFetchAt;
  latlng.LatLng? _lastRouteFrom;
  latlng.LatLng? _lastRouteTo;
  static const int _routeMinIntervalSeconds = 6;

  // Smooth map centering
  latlng.LatLng? _lastMapCenter;

  // Used to reduce jitter & unnecessary marker animations
  static const double _gpsMoveThresholdMeters = 8.0;

  int get _remainingSeconds {
    final rem = _maxExcursionSeconds - _elapsedExcursionSeconds;
    return rem < 0 ? 0 : rem;
  }

  String _formatMinutes(int minutes) {
    if (minutes <= 0) return "0m";
    final h = minutes ~/ 60;
    final m = minutes % 60;
    if (h > 0 && m > 0) return "${h}h ${m}m";
    if (h > 0) return "${h}h";
    return "${m}m";
  }

  String _formatSeconds(int seconds) {
    if (seconds <= 0) return "0m";
    final mins = (seconds / 60.0).floor();
    final h = mins ~/ 60;
    final m = mins % 60;
    if (h > 0 && m > 0) return "${h}h ${m}m";
    if (h > 0) return "${h}h";
    return "${m}m";
  }

  // -----------------------------------------
  // Utility: distance meters (haversine)
  // -----------------------------------------
  double _distMeters(latlng.LatLng a, latlng.LatLng b) {
    const R = 6371000.0;
    final dLat = _degToRad(b.latitude - a.latitude);
    final dLon = _degToRad(b.longitude - a.longitude);
    final lat1 = _degToRad(a.latitude);
    final lat2 = _degToRad(b.latitude);

    final sin1 = math.sin(dLat / 2);
    final sin2 = math.sin(dLon / 2);
    final h = sin1 * sin1 + math.cos(lat1) * math.cos(lat2) * sin2 * sin2;
    final c = 2 * math.atan2(math.sqrt(h), math.sqrt(1 - h));
    return R * c;
  }

  double _degToRad(double deg) => deg * (math.pi / 180.0);

  bool _movedMeaningfully(
    latlng.LatLng? oldP,
    latlng.LatLng? newP, {
    double thresholdMeters = 25,
  }) {
    if (oldP == null || newP == null) return true;
    return _distMeters(oldP, newP) >= thresholdMeters;
  }

  bool _movedSmall(latlng.LatLng? oldP, latlng.LatLng? newP) {
    if (oldP == null || newP == null) return true;
    return _distMeters(oldP, newP) >= _gpsMoveThresholdMeters;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _init();
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _countdownTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadExcursionState(String orderId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_excKey(orderId));
    if (raw == null) return;

    try {
      final m = jsonDecode(raw);
      final int elapsed = (m["elapsed"] is int)
          ? m["elapsed"]
          : int.tryParse(m["elapsed"].toString()) ?? 0;
      final bool inExc = (m["in_excursion"] == true);
      final int savedAt = (m["saved_at"] is int)
          ? m["saved_at"]
          : int.tryParse(m["saved_at"].toString()) ?? 0;

      _elapsedExcursionSeconds = elapsed;
      _inExcursion = inExc;

      if (_inExcursion && savedAt > 0) {
        final nowMs = DateTime.now().millisecondsSinceEpoch;
        final deltaSec = ((nowMs - savedAt) / 1000.0).floor();
        if (deltaSec > 0) _elapsedExcursionSeconds += deltaSec;
      }
    } catch (_) {}
  }

  Future<void> _saveExcursionState(String orderId) async {
    final prefs = await SharedPreferences.getInstance();
    final payload = {
      "elapsed": _elapsedExcursionSeconds,
      "in_excursion": _inExcursion,
      "saved_at": DateTime.now().millisecondsSinceEpoch,
    };
    await prefs.setString(_excKey(orderId), jsonEncode(payload));
  }

  Future<void> _init() async {
    setState(() {
      _isBootstrapping = true;
      _error = null;
    });

    // 1) Prime destination from track ONCE (fallback).
    // (We do NOT use track for driver GPS anymore.)
    await _primePatientDestinationFromTrackOnce();

    // 2) Init stability stability config + saved excursion state
    await _initStability();

    // 3) Load notifications for this order
    await _loadNotificationsForOrder();

    // 4) First poll (iot gps + temp + route + markers)
    await _pollTick();

    if (!mounted) return;
    setState(() => _isBootstrapping = false);

    // 5) Start polling
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 2), (_) async {
      await _pollTick();
    });

    // 6) Start countdown timer (local)
    _startCountdownTimer();
  }

  // ===============================================================
  // Track is ONLY used once to get patient destination coords
  // ===============================================================
  Future<void> _primePatientDestinationFromTrackOnce() async {
    final orderId = widget.orderId.trim();
    if (orderId.isEmpty) return;

    try {
      final track = await PatientService.fetchTrackOrder(orderId: orderId);

      latlng.LatLng? p;

      final patient = track["patient"];
      if (patient is Map && patient["lat"] is num && patient["lon"] is num) {
        p = latlng.LatLng(
          (patient["lat"] as num).toDouble(),
          (patient["lon"] as num).toDouble(),
        );
      }

      final pLat = track["patient_lat"];
      final pLon = track["patient_lon"];
      if (p == null && pLat is num && pLon is num) {
        p = latlng.LatLng(pLat.toDouble(), pLon.toDouble());
      }

      if (!mounted) return;
      setState(() {
        if (p != null) _patientLatLng = p;
        _updateMarkers();
      });
    } catch (_) {
      // If this fails, patient pin may remain null until you provide another endpoint.
    }
  }

  Future<void> _initStability() async {
    final orderId = widget.orderId.trim();
    if (orderId.isEmpty) return;

    await _loadExcursionState(orderId);

    final maxSec = await _fetchMaxExcursionSeconds(orderId);
    _maxExcursionSeconds = maxSec ?? 0;

    if (!mounted) return;
    setState(() {
      _stabilityTimeText = _maxExcursionSeconds > 0
          ? _formatSeconds(_remainingSeconds)
          : "—";
    });

    await _saveExcursionState(orderId);
  }

  Future<int?> _fetchMaxExcursionSeconds(String orderId) async {
    try {
      final res = await http
          .get(Uri.parse("$kGatewayBase/stability/config/$orderId"))
          .timeout(const Duration(seconds: 6));

      if (res.statusCode != 200) return null;

      final cfg = jsonDecode(res.body);
      final raw = cfg["max_time_exertion_seconds"];

      if (raw is int) return raw;
      if (raw is num) return raw.toInt();
      return int.tryParse(raw.toString());
    } catch (_) {
      return null;
    }
  }

  void _startCountdownTimer() {
    _countdownTimer?.cancel();
    _lastCountdownTick = DateTime.now();

    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) async {
      if (_maxExcursionSeconds <= 0) return;

      final now = DateTime.now();
      final last = _lastCountdownTick ?? now;
      _lastCountdownTick = now;

      final delta = now.difference(last).inSeconds;
      if (delta <= 0) return;

      if (_inExcursion) {
        _elapsedExcursionSeconds += delta;
        if (_elapsedExcursionSeconds < 0) _elapsedExcursionSeconds = 0;

        if (!mounted) return;
        setState(() {
          _stabilityTimeText = _formatSeconds(_remainingSeconds);
        });

        await _saveExcursionState(widget.orderId);
      }
    });
  }

  Future<Map<String, dynamic>?> _fetchIotLive(String orderId) async {
    try {
      final res = await http
          .get(Uri.parse("$kApiBase/iot/live/$orderId"))
          .timeout(const Duration(seconds: 6));

      if (res.statusCode != 200) return null;

      final decoded = jsonDecode(res.body);
      return decoded is Map<String, dynamic>
          ? decoded
          : Map<String, dynamic>.from(decoded as Map);
    } catch (_) {
      return null;
    }
  }

  // ===============================================================
  // Poll tick: IoT live is authoritative for GPS now (Driver-like)
  // ===============================================================
  Future<void> _pollTick() async {
    if (_tickBusy) return;
    _tickBusy = true;
    _pollCount++;

    try {
      final orderId = widget.orderId.trim();
      if (orderId.isEmpty) return;

      // 1) IoT live: allowed_range + temperature + GPS
      final live = await _fetchIotLive(orderId);
      if (live != null) {
        // allowed_range
        final range = live["allowed_range"];
        if (range is Map) {
          final minT = range["min_temp"];
          final maxT = range["max_temp"];
          if (minT is num) _minTemp = minT.toDouble();
          if (maxT is num) _maxTemp = maxT.toDouble();
        }

        // temperature
        final t = live["temperature"];
        if (t is Map && t["value"] is num) {
          final temp = (t["value"] as num).toDouble();
          _temperatureText = "${temp.toStringAsFixed(1)}°C";

          final nowOut = (temp < _minTemp) || (temp > _maxTemp);
          if (nowOut != _inExcursion) {
            _inExcursion = nowOut;
            await _saveExcursionState(orderId);
          }
        }

        // GPS (driver)
        latlng.LatLng? newDriver;
        final g = live["gps"];
        if (g is Map && g["lat"] is num && g["lon"] is num) {
          newDriver = latlng.LatLng(
            (g["lat"] as num).toDouble(),
            (g["lon"] as num).toDouble(),
          );
        }

        if (newDriver != null) {
          // update only if moved a little (reduces jitter)
          if (_movedSmall(_driverLatLng, newDriver)) {
            _driverLatLng = newDriver;
          }
        }
      }

      // 2) Notifications refresh periodically
      if (_pollCount % _notifRefreshEveryTicks == 0) {
        await _loadNotificationsForOrder();
      }

      // 3) Route + ETA throttled (only if map is allowed)
      if (widget.showMap) {
        if (_driverLatLng != null && _patientLatLng != null) {
          await _fetchRouteAndEtaThrottled();
        }
      }

      if (!mounted) return;
      setState(() {
        _error = null;
        _updateMarkers();
        if (_maxExcursionSeconds > 0) {
          _stabilityTimeText = _formatSeconds(_remainingSeconds);
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
      });
    } finally {
      _tickBusy = false;
    }
  }

  Future<void> _fetchRouteAndEtaThrottled() async {
    if (_driverLatLng == null || _patientLatLng == null) return;

    final now = DateTime.now();
    if (_lastRouteFetchAt != null) {
      final delta = now.difference(_lastRouteFetchAt!).inSeconds;
      if (delta < _routeMinIntervalSeconds) return;
    }

    final from = _driverLatLng!;
    final to = _patientLatLng!;

    final movedFrom = _movedMeaningfully(
      _lastRouteFrom,
      from,
      thresholdMeters: 35,
    );
    final movedTo = _movedMeaningfully(_lastRouteTo, to, thresholdMeters: 35);

    if (!movedFrom &&
        !movedTo &&
        _polylines.isNotEmpty &&
        _arrivalTimeText != "—") {
      return;
    }

    _lastRouteFetchAt = now;
    _lastRouteFrom = from;
    _lastRouteTo = to;

    await _fetchRouteAndEta();
  }

  Future<void> _fetchRouteAndEta() async {
    if (_driverLatLng == null || _patientLatLng == null) return;

    if (mounted) setState(() => _isRouteLoading = true);

    try {
      final fromLat = _driverLatLng!.latitude;
      final fromLon = _driverLatLng!.longitude;
      final toLat = _patientLatLng!.latitude;
      final toLon = _patientLatLng!.longitude;

      // polyline
      final polyUri = Uri.parse(
        "$kGatewayBase/route/v1/driving/"
        "$fromLon,$fromLat;$toLon,$toLat"
        "?overview=full&geometries=geojson",
      );

      final polyRes = await http
          .get(polyUri)
          .timeout(const Duration(seconds: 8));

      if (polyRes.statusCode == 200) {
        final decoded = jsonDecode(polyRes.body);
        final routes = decoded["routes"] as List?;
        if (routes != null && routes.isNotEmpty) {
          final first = routes.first as Map<String, dynamic>;
          final geom = first["geometry"] as Map<String, dynamic>;
          final coords = geom["coordinates"] as List<dynamic>;

          final route = coords
              .map<latlng.LatLng>(
                (c) => latlng.LatLng(
                  (c[1] as num).toDouble(),
                  (c[0] as num).toDouble(),
                ),
              )
              .toList();

          _polylines = [
            Polyline(points: route, color: AppColors.alertRed, strokeWidth: 5),
          ];
        }
      }

      // eta
      final etaUri = Uri.parse(
        "$kGatewayBase/route/v1/driving/"
        "$fromLon,$fromLat;$toLon,$toLat"
        "?overview=false",
      );

      final etaRes = await http.get(etaUri).timeout(const Duration(seconds: 8));

      if (etaRes.statusCode == 200) {
        final decoded = jsonDecode(etaRes.body);
        final routes = decoded["routes"] as List?;
        if (routes != null && routes.isNotEmpty) {
          final first = routes.first as Map<String, dynamic>;
          final durationRaw = first["duration"];

          final seconds = durationRaw is num
              ? durationRaw.toDouble()
              : double.tryParse(durationRaw.toString()) ?? 0;

          final minutes = (seconds / 60.0).round();
          _arrivalTimeText = _formatMinutes(minutes);
        }
      }
    } catch (_) {
      // keep last values
    } finally {
      if (!mounted) return;
      setState(() => _isRouteLoading = false);
    }
  }

  void _updateMarkers() {
    final markers = <Marker>[];

    if (_driverLatLng != null) {
      markers.add(
        Marker(
          point: _driverLatLng!,
          width: 44.w,
          height: 44.w,
          child: Image.asset("assets/car.png", width: 44.w, height: 44.w),
        ),
      );
    }

    if (_patientLatLng != null) {
      markers.add(
        Marker(
          point: _patientLatLng!,
          width: 46.w,
          height: 46.w,
          child: Image.asset(
            "assets/Locationpin.png",
            width: 46.w,
            height: 46.w,
          ),
        ),
      );
    }

    _markers = markers;

    // Smooth map centering
    if (_mapReady && widget.showMap) {
      final center = _driverLatLng ?? _patientLatLng;
      if (center != null) {
        final shouldMove =
            _lastMapCenter == null ||
            _movedMeaningfully(_lastMapCenter, center, thresholdMeters: 20);
        if (shouldMove) {
          _lastMapCenter = center;
          _mapController.move(center, 16.0);
        }
      }
    }
  }

  // ===============================================================
  // Notifications — order-specific
  // ===============================================================
  Future<void> _loadNotificationsForOrder() async {
    final oid = widget.orderId.trim();
    if (oid.isEmpty) return;

    if (mounted) setState(() => _isNotifLoading = true);

    try {
      final msgs = await _fetchOrderNotifications(oid);
      if (!mounted) return;
      setState(() => _notifications = msgs);
    } catch (_) {
      // keep empty
    } finally {
      if (!mounted) return;
      setState(() => _isNotifLoading = false);
    }
  }

  Future<List<String>> _fetchOrderNotifications(String orderId) async {
    final prefs = await SharedPreferences.getInstance();
    final token =
        prefs.getString("token") ?? prefs.getString("access_token") ?? "";
    final nationalId = prefs.getString("national_id") ?? "";

    if (nationalId.isEmpty) return [];

    final uri = Uri.parse(
      "$kApiBase/patient/$nationalId/notifications?order_id=$orderId",
    );

    final res = await http
        .get(
          uri,
          headers: {
            "Accept": "application/json",
            if (token.isNotEmpty) "Authorization": "Bearer $token",
          },
        )
        .timeout(const Duration(seconds: 6));

    if (res.statusCode != 200) {
      debugPrint("Order notifications failed: ${res.statusCode} ${res.body}");
      return [];
    }

    final decoded = jsonDecode(res.body);
    final items = (decoded is List) ? decoded : <dynamic>[];

    final out = <String>[];
    for (final it in items) {
      if (it is! Map) continue;
      final text = (it["description"] ?? it["message"] ?? it["text"])
          ?.toString()
          .trim();
      if (text != null && text.isNotEmpty) out.add(text);
    }

    return out;
  }

  // ------------------------------------------------------------
  // UI
  // ------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.appBackground,
      appBar: PreferredSize(
        preferredSize: Size.fromHeight(90.h),
        child: CustomTopBar(title: "dashboard".tr(), showBackButton: true),
      ),
      body: Stack(
        children: [
          if (widget.showMap) Positioned.fill(child: _buildMap()),
          if (!widget.showMap) Positioned.fill(child: _buildPrivacyView()),

          // Top info card
          Positioned(
            top: 15.h,
            left: (MediaQuery.of(context).size.width / 2) - (161.w),
            child: Container(
              width: 322.w,
              height: 124.h,
              padding: EdgeInsets.symmetric(vertical: 12.h, horizontal: 18.w),
              decoration: BoxDecoration(
                color: AppColors.cardBackground,
                borderRadius: BorderRadius.circular(15.r),
                boxShadow: AppColors.universalShadow,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _infoRow(
                    icon: Icons.thermostat_rounded,
                    label: "temperature".tr(),
                    valueText: _temperatureText,
                  ),
                  SizedBox(height: 8.h),
                  _infoRow(
                    icon: Icons.access_time_rounded,
                    label: "arrival_time".tr(),
                    valueText: _arrivalTimeText,
                  ),
                  SizedBox(height: 8.h),
                  _infoRow(
                    icon: Icons.hourglass_empty_rounded,
                    label: "remaining_stability".tr(),
                    valueText: _stabilityTimeText,
                  ),
                ],
              ),
            ),
          ),

          // Small non-blocking loading indicator
          Positioned(
            top: 150.h,
            right: 18.w,
            child: AnimatedOpacity(
              opacity: (_isBootstrapping || _isRouteLoading) ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 200),
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 8.h),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14.r),
                  boxShadow: AppColors.universalShadow,
                ),
                child: SizedBox(
                  width: 18.w,
                  height: 18.w,
                  child: const CircularProgressIndicator(strokeWidth: 2.5),
                ),
              ),
            ),
          ),

          // Error message (non-blocking)
          if (_error != null)
            Positioned(
              top: 150.h,
              left: 20.w,
              right: 70.w,
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 10.h),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14.r),
                  boxShadow: AppColors.universalShadow,
                ),
                child: Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12.sp,
                    fontWeight: FontWeight.w600,
                    color: AppColors.alertRed,
                  ),
                ),
              ),
            ),

          _buildBottomNotifications(),
        ],
      ),
    );
  }

  Widget _buildPrivacyView() {
    return Container(
      color: AppColors.appBackground,
      alignment: Alignment.center,
      padding: EdgeInsets.symmetric(horizontal: 28.w),
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 18.h),
        decoration: BoxDecoration(
          color: AppColors.cardBackground,
          borderRadius: BorderRadius.circular(18.r),
          boxShadow: AppColors.universalShadow,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.privacy_tip_rounded,
              size: 34.sp,
              color: AppColors.bodyText,
            ),
            SizedBox(height: 10.h),
            Text(
              "Live map is hidden for privacy. It will appear once the driver is On Route.",
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13.sp,
                fontWeight: FontWeight.w600,
                color: AppColors.detailText,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMap() {
    final center =
        _driverLatLng ?? _patientLatLng ?? latlng.LatLng(24.7136, 46.6753);

    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: center,
        initialZoom: 16.0,
        onMapReady: () {
          _mapReady = true;
          _updateMarkers();
        },
      ),
      children: [
        TileLayer(
          urlTemplate:
              "$kGatewayBase/tiles/styles/basic-preview/{z}/{x}/{y}.png",
          userAgentPackageName: "com.example.teryagapptry",
        ),
        if (_polylines.isNotEmpty) PolylineLayer(polylines: _polylines),
        if (_markers.isNotEmpty) MarkerLayer(markers: _markers),
      ],
    );
  }

  Widget _buildBottomNotifications() {
    return AnimatedPositioned(
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeInOut,
      bottom: 0,
      left: 0,
      right: 0,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 22.w, vertical: 20.h),
        decoration: BoxDecoration(
          color: AppColors.cardBackground,
          borderRadius: BorderRadius.vertical(top: Radius.circular(30.r)),
          boxShadow: AppColors.universalShadow,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            GestureDetector(
              onTap: () => setState(() => _isExpanded = !_isExpanded),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    "notifications".tr(),
                    style: TextStyle(
                      fontSize: 18.sp,
                      fontWeight: FontWeight.w700,
                      color: AppColors.headingText,
                    ),
                  ),
                  Icon(
                    _isExpanded
                        ? Icons.keyboard_arrow_down_rounded
                        : Icons.keyboard_arrow_up_rounded,
                    size: 26.sp,
                    color: AppColors.Chevronicon,
                  ),
                ],
              ),
            ),
            AnimatedCrossFade(
              duration: const Duration(milliseconds: 300),
              firstChild: const SizedBox.shrink(),
              secondChild: _isNotifLoading
                  ? Padding(
                      padding: EdgeInsets.only(top: 12.h),
                      child: const Center(child: CircularProgressIndicator()),
                    )
                  : Column(
                      children: [
                        SizedBox(height: 12.h),
                        if (_notifications.isEmpty)
                          Text(
                            "no_notifications".tr(),
                            style: TextStyle(
                              fontSize: 14.sp,
                              color: AppColors.bodyText,
                            ),
                          )
                        else
                          ..._notifications.map(
                            (msg) => _notificationItem(msg),
                          ),
                      ],
                    ),
              crossFadeState: _isExpanded
                  ? CrossFadeState.showSecond
                  : CrossFadeState.showFirst,
            ),
          ],
        ),
      ),
    );
  }

  Widget _notificationItem(String msg) {
    return Container(
      margin: EdgeInsets.only(bottom: 8.h),
      padding: EdgeInsets.symmetric(vertical: 10.h, horizontal: 12.w),
      decoration: BoxDecoration(
        color: AppColors.appBackground,
        borderRadius: BorderRadius.circular(12.r),
        boxShadow: AppColors.universalShadow,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.notifications_active_rounded,
            size: 20.sp,
            color: AppColors.buttonRed,
          ),
          SizedBox(width: 10.w),
          Expanded(
            child: Text(
              msg,
              style: TextStyle(
                fontSize: 14.sp,
                color: AppColors.bodyText,
                fontWeight: FontWeight.w400,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoRow({
    required IconData icon,
    required String label,
    required String valueText,
  }) {
    return Row(
      children: [
        Icon(icon, color: AppColors.bodyText, size: 20.sp),
        SizedBox(width: 10.w),
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 15.sp,
              fontWeight: FontWeight.w700,
              color: AppColors.bodyText,
            ),
          ),
        ),
        Text(
          valueText,
          style: TextStyle(
            fontSize: 14.sp,
            fontWeight: FontWeight.w700,
            color: AppColors.alertRed,
          ),
        ),
      ],
    );
  }
}
