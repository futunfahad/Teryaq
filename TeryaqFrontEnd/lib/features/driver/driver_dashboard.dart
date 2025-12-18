// ===============================================================
//                🔵 DRIVER DASHBOARD — TILESERVER EDITION
//   FlutterMap + OSRM + TileServer GL + LIVE GPS + LOCAL COUNTDOWN
//
//   ✅ Driver marker moves using /iot/live/{orderId} (gps table)
//   ✅ Stability countdown runs CLIENT-SIDE when temp out of range
//   ✅ No new DB table needed
// ===============================================================

import 'dart:async';
import 'dart:convert';
import 'dart:math' as Math;

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' as latlng;
import 'package:easy_localization/easy_localization.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:teryagapptry/widgets/custom_top_bar.dart';
import 'package:teryagapptry/constants/app_colors.dart';
import 'package:teryagapptry/services/driver_service.dart';

// Gateway (tiles + OSRM)
const String kGatewayBase = 'http://192.168.8.113:8088';

// Backend (IoT live polling)
const String kApiBase = 'http://192.168.8.113:8000';

// Fallback display
const Map<String, dynamic> kDashboardInfo = {
  "temperature": "—",
  "arrival_time": "—",
  "remaining_stability": "—",
};

class DriverMapOrder {
  final String orderId;
  final String? status;
  final DateTime? createdAt;
  final latlng.LatLng? driverLatLng;
  final latlng.LatLng? patientLatLng;

  DriverMapOrder({
    required this.orderId,
    required this.driverLatLng,
    required this.patientLatLng,
    this.status,
    this.createdAt,
  });

  factory DriverMapOrder.fromJson(Map<String, dynamic> json) {
    final Map<String, dynamic>? driver = json['driver'] is Map
        ? Map<String, dynamic>.from(json['driver'])
        : null;
    final Map<String, dynamic>? patient = json['patient'] is Map
        ? Map<String, dynamic>.from(json['patient'])
        : null;

    final num? dLat = driver?['lat'] as num?;
    final num? dLon = driver?['lon'] as num?;
    final num? pLat = patient?['lat'] as num?;
    final num? pLon = patient?['lon'] as num?;

    latlng.LatLng? driverPos;
    latlng.LatLng? patientPos;

    if (dLat != null && dLon != null) {
      driverPos = latlng.LatLng(dLat.toDouble(), dLon.toDouble());
    }
    if (pLat != null && pLon != null) {
      patientPos = latlng.LatLng(pLat.toDouble(), pLon.toDouble());
    }

    DateTime? created;
    final createdStr = json['created_at']?.toString();
    if (createdStr != null && createdStr.isNotEmpty) {
      try {
        created = DateTime.parse(createdStr);
      } catch (_) {}
    }

    return DriverMapOrder(
      orderId: json['order_id']?.toString() ?? '',
      status: json['status']?.toString(),
      createdAt: created,
      driverLatLng: driverPos,
      patientLatLng: patientPos,
    );
  }
}

class DriverDashboardScreen extends StatefulWidget {
  final String? initialOrderId;
  const DriverDashboardScreen({super.key, this.initialOrderId});

  @override
  State<DriverDashboardScreen> createState() => _DriverDashboardState();
}

class _DriverDashboardState extends State<DriverDashboardScreen> {
  final MapController _mapController = MapController();

  bool _isExpanded = true;

  bool _isMapDataLoading = true;
  bool _isRouteLoading = false;
  bool _isNotifLoading = false;
  bool _isCardLoading = false;
  String? _error;

  latlng.LatLng? _patientLatLng;
  latlng.LatLng? _driverLatLng;

  List<DriverMapOrder> _todayOrders = [];
  DriverMapOrder? _currentOrder;

  List<Marker> _markers = [];
  List<Polyline> _polylines = [];

  List<String> _notifications = [];

  String? _temperatureText;
  String? _arrivalTimeText;
  String? _stabilityTimeText;

  double _currentBearing = 0;
  double _currentZoom = 16.0;

  bool _mapReady = false;
  Timer? _pollTimer; // every 2s: pull iot/live + update marker + update ETA
  Timer? _countdownTimer; // every 1s: decrement locally if in excursion

  // ---------------------------
  // Local stability countdown state (NO DB table)
  // ---------------------------
  int _maxExcursionSeconds = 0; // from stability/config
  int _elapsedExcursionSeconds = 0; // accumulated while out-of-range
  bool _inExcursion = false; // current temp out-of-range?
  DateTime? _lastCountdownTick; // used to accumulate seconds precisely

  // Allowed temp range (prefer backend, fallback 2..8)
  double _minTemp = 2.0;
  double _maxTemp = 8.0;

  bool _tickBusy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initDashboard();
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _countdownTimer?.cancel();
    super.dispose();
  }

  // =========================
  // Init
  // =========================
  Future<void> _initDashboard() async {
    await _loadMapData();
    await _initStabilityForCurrentOrder();
    _startCountdownTimer();
  }

  double get _markerSize {
    final z = _currentZoom.clamp(10.0, 19.0);
    return 32 + (z - 10) * 3.5;
  }

  // =========================
  // Formatting
  // =========================
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

  int get _remainingSeconds {
    final rem = _maxExcursionSeconds - _elapsedExcursionSeconds;
    return rem < 0 ? 0 : rem;
  }

  // =========================
  // SharedPrefs keys for countdown state
  // =========================
  String _excKey(String orderId) => "excursion_state_$orderId";

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

      // If it was in excursion when last saved, add time since then
      if (_inExcursion && savedAt > 0) {
        final nowMs = DateTime.now().millisecondsSinceEpoch;
        final deltaSec = ((nowMs - savedAt) / 1000.0).floor();
        if (deltaSec > 0) {
          _elapsedExcursionSeconds += deltaSec;
        }
      }
    } catch (_) {
      // ignore bad data
    }
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

  // =========================
  // Fetch stability config (max excursion)
  // =========================
  Future<int?> _fetchMaxExcursionSeconds(String orderId) async {
    try {
      final res = await http.get(
        Uri.parse("$kGatewayBase/stability/config/$orderId"),
      );
      if (res.statusCode != 200) {
        debugPrint(
          "Dashboard → stability/config error ${res.statusCode}: ${res.body}",
        );
        return null;
      }
      final cfg = jsonDecode(res.body);
      final raw = cfg["max_time_exertion_seconds"];

      if (raw is int) return raw;
      if (raw is num) return raw.toInt();
      return int.tryParse(raw.toString());
    } catch (e) {
      debugPrint("Dashboard → stability/config exception: $e");
      return null;
    }
  }

  // =========================
  // Poll IoT live: latest GPS + temp + allowed range
  // =========================
  Future<Map<String, dynamic>?> _fetchIotLive(String orderId) async {
    try {
      final res = await http.get(Uri.parse("$kApiBase/iot/live/$orderId"));
      if (res.statusCode != 200) {
        debugPrint(
          "Dashboard → /iot/live failed ${res.statusCode}: ${res.body}",
        );
        return null;
      }
      final decoded = jsonDecode(res.body);
      return decoded is Map<String, dynamic>
          ? decoded
          : Map<String, dynamic>.from(decoded as Map);
    } catch (e) {
      debugPrint("Dashboard → /iot/live exception: $e");
      return null;
    }
  }

  // =========================
  // Init stability for order
  // =========================
  Future<void> _initStabilityForCurrentOrder() async {
    if (_currentOrder == null) return;
    final orderId = _currentOrder!.orderId;

    setState(() => _isCardLoading = true);

    // Load persisted excursion state first
    await _loadExcursionState(orderId);

    // Load max excursion seconds from backend config
    final maxSec = await _fetchMaxExcursionSeconds(orderId);
    _maxExcursionSeconds = maxSec ?? 0;

    setState(() {
      _stabilityTimeText = _formatSeconds(_remainingSeconds);
    });

    await _saveExcursionState(orderId);

    setState(() => _isCardLoading = false);
  }

  // =========================
  // Countdown timer (1s)
  // =========================
  void _startCountdownTimer() {
    _countdownTimer?.cancel();
    _lastCountdownTick = DateTime.now();

    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) async {
      if (_currentOrder == null) return;
      if (_maxExcursionSeconds <= 0) return; // no config yet

      final now = DateTime.now();
      final last = _lastCountdownTick ?? now;
      _lastCountdownTick = now;

      final delta = now.difference(last).inSeconds;
      if (delta <= 0) return;

      // Only count down while currently out-of-range
      if (_inExcursion) {
        _elapsedExcursionSeconds += delta;
        if (_elapsedExcursionSeconds < 0) _elapsedExcursionSeconds = 0;

        // Update display
        setState(() {
          _stabilityTimeText = _formatSeconds(_remainingSeconds);
        });

        // Persist periodically (or each tick; kept simple)
        await _saveExcursionState(_currentOrder!.orderId);
      }
    });
  }

  // =========================
  // Load map data (today-orders-map)
  // =========================
  Future<void> _loadMapData() async {
    setState(() {
      _isMapDataLoading = true;
      _error = null;
    });

    try {
      final profile = await DriverService.getDriverProfile();
      final String driverId = profile["driver_id"]?.toString() ?? "";

      final rawOrders = await DriverService.getTodayOrdersMap(
        driverId: driverId,
      );
      debugPrint("Dashboard: driverId='$driverId'");
      debugPrint("Dashboard: rawOrders len=${rawOrders.length}");
      debugPrint(
        "Dashboard: first raw order=${rawOrders.isNotEmpty ? rawOrders.first : 'NONE'}",
      );

      final orders = rawOrders
          .map<DriverMapOrder>((m) => DriverMapOrder.fromJson(m))
          .where((o) => o.patientLatLng != null && o.orderId.isNotEmpty)
          .toList();

      if (orders.isEmpty) {
        setState(() {
          _isMapDataLoading = false;
          _error = 'No orders for today';
        });
        return;
      }

      _todayOrders = orders;

      DriverMapOrder selected = orders.first;
      if (widget.initialOrderId != null &&
          widget.initialOrderId!.trim().isNotEmpty) {
        final id = widget.initialOrderId!.trim();
        final found = orders.where((o) => o.orderId == id).toList();
        if (found.isNotEmpty) selected = found.first;
      }

      _currentOrder = selected;
      _patientLatLng = selected.patientLatLng;

      // NOTE: driverLatLng from today-orders-map might be stale.
      // We will override it continuously from /iot/live.
      _driverLatLng = selected.driverLatLng;

      _updateMarkers();

      setState(() {
        _isMapDataLoading = false;
      });

      if (_mapReady && _driverLatLng != null) {
        _mapController.move(_driverLatLng!, _currentZoom);
      }

      await _fetchRouteFromOsrmThroughGateway();
      await _loadNotificationsForCurrentOrder();
      await _loadEtaCardOnly(driverId);
    } catch (e) {
      setState(() {
        _isMapDataLoading = false;
        _error = e.toString();
      });
    }
  }

  // =========================
  // Poll tick (every 2 seconds)
  // - Move marker from /iot/live
  // - Update temperature
  // - Update in_excursion flag (temp outside range)
  // - Refresh route + ETA
  // =========================
  Future<void> _pollTick() async {
    if (_currentOrder == null || !_mapReady) return;
    if (_tickBusy) return;
    _tickBusy = true;

    try {
      final profile = await DriverService.getDriverProfile();
      final String driverId = profile["driver_id"]?.toString() ?? "";
      final String orderId = _currentOrder!.orderId;

      // 1) iot live (gps + temp + range)
      final live = await _fetchIotLive(orderId);
      if (live != null) {
        // range
        final range = live["allowed_range"];
        if (range is Map) {
          final minT = range["min_temp"];
          final maxT = range["max_temp"];
          if (minT is num) _minTemp = minT.toDouble();
          if (maxT is num) _maxTemp = maxT.toDouble();
        }

        // temperature
        double? temp;
        final t = live["temperature"];
        if (t is Map && t["value"] is num) {
          temp = (t["value"] as num).toDouble();
        }

        if (temp != null) {
          setState(() {
            _temperatureText = "${temp!.toStringAsFixed(1)}°C";
          });

          final bool nowOut = (temp < _minTemp) || (temp > _maxTemp);

          // If state changed, persist it immediately
          if (nowOut != _inExcursion) {
            _inExcursion = nowOut;
            await _saveExcursionState(orderId);
          }
        }

        // gps
        latlng.LatLng? newPos;
        final g = live["gps"];
        if (g is Map && g["lat"] is num && g["lon"] is num) {
          newPos = latlng.LatLng(
            (g["lat"] as num).toDouble(),
            (g["lon"] as num).toDouble(),
          );
        }

        if (newPos != null) {
          if (_driverLatLng != null) {
            _currentBearing = getBearing(_driverLatLng!, newPos);
            await animateDriverMarker(_driverLatLng!, newPos);
          } else {
            setState(() {
              _driverLatLng = newPos;
              _updateMarkers();
            });
          }
        }
      }

      // 2) route + ETA (depends on current driver->patient)
      await _fetchRouteFromOsrmThroughGateway();
      await _loadEtaCardOnly(driverId);

      // 3) ensure stability text always reflects remaining seconds
      if (_maxExcursionSeconds > 0) {
        setState(() {
          _stabilityTimeText = _formatSeconds(_remainingSeconds);
        });
      }
    } catch (_) {
      // ignore polling errors
    } finally {
      _tickBusy = false;
    }
  }

  // =========================
  // Smooth animation for marker
  // =========================
  Future<void> animateDriverMarker(latlng.LatLng from, latlng.LatLng to) async {
    const int steps = 25;
    const int ms = 500;
    const int interval = ms ~/ steps;

    for (int i = 0; i <= steps; i++) {
      final double t = i / steps;
      final double lat = from.latitude + (to.latitude - from.latitude) * t;
      final double lon = from.longitude + (to.longitude - from.longitude) * t;

      final latlng.LatLng newPos = latlng.LatLng(lat, lon);

      setState(() {
        _driverLatLng = newPos;
        _updateMarkers();
      });

      if (_mapReady) {
        _mapController.move(newPos, _currentZoom);
      }

      await Future.delayed(const Duration(milliseconds: interval));
    }
  }

  // =========================
  // Bearing
  // =========================
  double getBearing(latlng.LatLng start, latlng.LatLng end) {
    final double lat1 = start.latitude * Math.pi / 180;
    final double lat2 = end.latitude * Math.pi / 180;
    final double dLon = (end.longitude - start.longitude) * Math.pi / 180;

    final double y = Math.sin(dLon) * Math.cos(lat2);
    final double x =
        Math.cos(lat1) * Math.sin(lat2) -
        Math.sin(lat1) * Math.cos(lat2) * Math.cos(dLon);

    return ((Math.atan2(y, x) * 180 / Math.pi) + 360) % 360;
  }

  // =========================
  // Markers
  // =========================
  void _updateMarkers() {
    final markers = <Marker>[];
    final size = _markerSize;

    if (_driverLatLng != null) {
      markers.add(
        Marker(
          point: _driverLatLng!,
          width: size,
          height: size,
          child: Transform.rotate(
            angle: _currentBearing * Math.pi / 180,
            child: Image.asset("assets/car.png", width: size, height: size),
          ),
        ),
      );
    }

    if (_patientLatLng != null) {
      markers.add(
        Marker(
          point: _patientLatLng!,
          width: size * 1.1,
          height: size * 1.1,
          child: Image.asset(
            "assets/Locationpin.png",
            width: size * 1.1,
            height: size * 1.1,
          ),
        ),
      );
    }

    for (final o in _todayOrders) {
      if (o.patientLatLng == null) continue;
      if (_currentOrder != null && o.orderId == _currentOrder!.orderId)
        continue;

      markers.add(
        Marker(
          point: o.patientLatLng!,
          width: size * 0.7,
          height: size * 0.7,
          child: Icon(
            Icons.location_on,
            size: size * 0.7,
            color: AppColors.buttonBlue.withOpacity(0.8),
          ),
        ),
      );
    }

    _markers = markers;
  }

  // =========================
  // Route via OSRM through gateway
  // =========================
  Future<void> _fetchRouteFromOsrmThroughGateway() async {
    if (_driverLatLng == null || _patientLatLng == null) return;

    setState(() => _isRouteLoading = true);

    try {
      final fromLat = _driverLatLng!.latitude;
      final fromLon = _driverLatLng!.longitude;
      final toLat = _patientLatLng!.latitude;
      final toLon = _patientLatLng!.longitude;

      final uri = Uri.parse(
        "$kGatewayBase/route/v1/driving/"
        "$fromLon,$fromLat;$toLon,$toLat"
        "?overview=full&geometries=geojson",
      );

      final res = await http.get(uri);

      if (res.statusCode != 200) {
        setState(() => _error = "Routing server error: ${res.statusCode}");
      } else {
        final decoded = jsonDecode(res.body);
        final routes = decoded["routes"] as List?;
        if (routes == null || routes.isEmpty) {
          setState(() => _error = "No route found");
        } else {
          final first = routes.first as Map<String, dynamic>;
          final geom = first["geometry"] as Map<String, dynamic>;
          final coords = geom["coordinates"] as List<dynamic>;

          final List<latlng.LatLng> route = coords
              .map<latlng.LatLng>(
                (c) => latlng.LatLng(
                  (c[1] as num).toDouble(),
                  (c[0] as num).toDouble(),
                ),
              )
              .toList();

          setState(() {
            _polylines = [
              Polyline(
                points: route,
                color: AppColors.alertRed,
                strokeWidth: 5,
              ),
            ];
          });
        }
      }
    } catch (e) {
      setState(() => _error = "Routing failed: $e");
    }

    setState(() => _isRouteLoading = false);
  }

  // =========================
  // ETA via OSRM (live)
  // =========================
  Future<int?> _fetchEtaMinutes() async {
    if (_driverLatLng == null || _patientLatLng == null) return null;

    try {
      final fromLat = _driverLatLng!.latitude;
      final fromLon = _driverLatLng!.longitude;
      final toLat = _patientLatLng!.latitude;
      final toLon = _patientLatLng!.longitude;

      final uri = Uri.parse(
        "$kGatewayBase/route/v1/driving/"
        "$fromLon,$fromLat;$toLon,$toLat"
        "?overview=false",
      );

      final res = await http.get(uri);
      if (res.statusCode != 200) return null;

      final decoded = jsonDecode(res.body);
      final routes = decoded["routes"] as List?;
      if (routes == null || routes.isEmpty) return null;

      final first = routes.first as Map<String, dynamic>;
      final durationRaw = first["duration"]; // seconds

      double seconds;
      if (durationRaw is num) {
        seconds = durationRaw.toDouble();
      } else {
        seconds = double.tryParse(durationRaw.toString()) ?? 0;
      }

      return (seconds / 60.0).round();
    } catch (_) {
      return null;
    }
  }

  // Only updates ETA portion of top card
  Future<void> _loadEtaCardOnly(String driverId) async {
    if (_currentOrder == null) return;

    setState(() => _isCardLoading = true);

    final etaMin = await _fetchEtaMinutes();
    setState(() {
      _arrivalTimeText = etaMin != null ? _formatMinutes(etaMin) : null;
      _stabilityTimeText ??= _formatSeconds(_remainingSeconds);
    });

    setState(() => _isCardLoading = false);
  }

  // =========================
  // Notifications (unchanged)
  // =========================
  Future<void> _loadNotificationsForCurrentOrder() async {
    if (_currentOrder == null) return;

    setState(() => _isNotifLoading = true);

    try {
      final res = await DriverService.getNotifications();

      if (res is Map && res["notifications"] is List) {
        final List<String> msgs = [];
        final String oid = _currentOrder!.orderId;

        for (final n in res["notifications"]) {
          if (n is! Map) continue;
          final text = n["notification_content"]?.toString();
          final notifOrderId = n["order_id"]?.toString();

          if (notifOrderId != null && notifOrderId.isNotEmpty) {
            if (notifOrderId == oid && text != null && text.isNotEmpty)
              msgs.add(text);
          } else {
            if (text != null && text.isNotEmpty) msgs.add(text);
          }
        }

        if (msgs.isNotEmpty) setState(() => _notifications = msgs);
      }
    } catch (_) {}

    setState(() => _isNotifLoading = false);
  }

  // =========================
  // UI
  // =========================
  @override
  Widget build(BuildContext context) {
    final String temperature =
        _temperatureText ?? kDashboardInfo["temperature"].toString();

    final String arrival =
        (_arrivalTimeText != null && _arrivalTimeText!.isNotEmpty)
        ? _arrivalTimeText!
        : kDashboardInfo["arrival_time"].toString();

    final String stability =
        (_stabilityTimeText != null && _stabilityTimeText!.isNotEmpty)
        ? _stabilityTimeText!
        : kDashboardInfo["remaining_stability"].toString();

    return Scaffold(
      backgroundColor: AppColors.appBackground,
      appBar: PreferredSize(
        preferredSize: Size.fromHeight(90.h),
        child: CustomTopBar(title: "dashboard".tr(), showBackButton: true),
      ),
      body: Stack(
        children: [
          Positioned.fill(child: _buildMap()),

          if (_isRouteLoading || _isMapDataLoading)
            const Center(child: CircularProgressIndicator()),

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
              child: _isCardLoading
                  ? const Center(child: CircularProgressIndicator())
                  : Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _infoRow(
                          icon: Icons.thermostat_rounded,
                          label: "temperature".tr(),
                          valueText: temperature,
                        ),
                        SizedBox(height: 8.h),
                        _infoRow(
                          icon: Icons.access_time_rounded,
                          label: "arrival_time".tr(),
                          valueText: arrival,
                        ),
                        SizedBox(height: 8.h),
                        _infoRow(
                          icon: Icons.hourglass_empty_rounded,
                          label: "remaining_stability".tr(),
                          valueText: stability,
                        ),
                      ],
                    ),
            ),
          ),

          _buildBottomNotifications(),
        ],
      ),
    );
  }

  Widget _buildMap() {
    if (_error != null) {
      return Center(
        child: Text(
          _error!,
          style: TextStyle(color: AppColors.alertRed, fontSize: 14.sp),
          textAlign: TextAlign.center,
        ),
      );
    }

    final center =
        _driverLatLng ?? _patientLatLng ?? latlng.LatLng(24.7136, 46.6753);

    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: center,
        initialZoom: _currentZoom,
        onMapReady: () {
          _mapReady = true;

          // Start poll timer after map is ready
          _pollTimer?.cancel();
          _pollTimer = Timer.periodic(const Duration(seconds: 2), (_) async {
            await _pollTick();
          });

          if (_driverLatLng != null) {
            _mapController.move(_driverLatLng!, _currentZoom);
          }
        },
        onPositionChanged: (pos, hasGesture) {
          setState(() {
            _currentZoom = pos.zoom ?? _currentZoom;
            _updateMarkers();
          });
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
