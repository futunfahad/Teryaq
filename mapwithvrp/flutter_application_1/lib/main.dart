import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

// -----------------------------------------------------------------------------
// 🌐 CONFIG
// -----------------------------------------------------------------------------

// 👇 CHANGE THIS TO YOUR GATEWAY IP
const String kBaseProxy = "http://192.168.8.177:8088";

// 👇 CHANGE THIS TO THE DRIVER YOU WANT TO TEST (Matthew / Driver Two)
const String kDriverId = "9ad5acec-537d-4d80-b929-2074e946e5e0";

// Distance helper
const Distance kDistance = Distance();

// -----------------------------------------------------------------------------
// 🚦 Route + Stability Models
// -----------------------------------------------------------------------------

enum RouteStopStatus { depot, pending, delivered, spoiled }

class StopInfo {
  final int node; // HGS node number (0 = depot)
  final LatLng position;
  final String? name;
  final String? orderId;
  RouteStopStatus status;

  // Stability config (from /stability/config)
  double? maxExcTemp;
  int? maxTimeSec;

  // Stability runtime
  bool timerStarted;
  int? remainingSec;
  bool maxExceeded;
  bool timeExpired;

  StopInfo({
    required this.node,
    required this.position,
    required this.name,
    required this.orderId,
    required this.status,
    this.maxExcTemp,
    this.maxTimeSec,
    this.timerStarted = false,
    this.remainingSec,
    this.maxExceeded = false,
    this.timeExpired = false,
  });
}

// -----------------------------------------------------------------------------
// APP ENTRY
// -----------------------------------------------------------------------------

void main() {
  runApp(const MapApp());
}

class MapApp extends StatelessWidget {
  const MapApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: MapPage(),
    );
  }
}

class MapPage extends StatefulWidget {
  const MapPage({super.key});

  @override
  State<MapPage> createState() => _MapPageState();
}

class _MapPageState extends State<MapPage> {
  final MapController _mapController = MapController();

  // All stops INCLUDING depot (index 0 and last)
  List<StopInfo> _stops = [];

  // Current remaining route polyline (blue)
  List<LatLng> _routePolyline = [];

  // Car position (simulated OR GPS)
  LatLng? _carPos;
  int _carIndex = 0;

  // Timers
  Timer? _simTimer;
  Timer? _stabilityTimer;

  // Logs
  final List<String> _logs = [];

  // For manual temperature control
  final TextEditingController _tempController = TextEditingController(
    text: "10.0",
  );

  // ETA / Distance to next active stop
  double _etaNextSec = 0.0;
  double _distNextMeters = 0.0;

  // For debugging: driver id display (you can make it input later)
  String get _driverId => kDriverId;

  // ---------------------------------------------------------------------------
  // 🔐 Logging helpers
  // ---------------------------------------------------------------------------

  void _log(String msg) {
    final ts = DateTime.now().toIso8601String().substring(11, 19);
    setState(() => _logs.add("[$ts] $msg"));
    debugPrint("[$ts] $msg");
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 2)),
    );
  }

  // ---------------------------------------------------------------------------
  // INIT / DISPOSE
  // ---------------------------------------------------------------------------

  @override
  void initState() {
    super.initState();
    _initLocation(); // real GPS + simulation
    _loadDriverRoute();
  }

  @override
  void dispose() {
    _simTimer?.cancel();
    _stabilityTimer?.cancel();
    _tempController.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // 📍 GPS (optional real position; we still simulate car on streets)
  // ---------------------------------------------------------------------------

  Future<void> _initLocation() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        _log("GPS disabled (sim still works).");
        return;
      }

      LocationPermission perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        _log("GPS permission denied (sim still works).");
        return;
      }

      Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.best,
          distanceFilter: 5,
        ),
      ).listen((pos) {
        // Only for showing something if you want. We keep _carPos
        // controlled by simulation so the route logic is consistent.
        _log(
          "📍 Real GPS: ${pos.latitude.toStringAsFixed(5)}, ${pos.longitude.toStringAsFixed(5)}",
        );
      });
    } catch (e) {
      _log("GPS init error: $e");
    }
  }

  // ---------------------------------------------------------------------------
  // 🚚 Load Driver HGS Route from Backend
  // ---------------------------------------------------------------------------

  Future<void> _loadDriverRoute() async {
    _log("Fetching driver route for $_driverId ...");

    try {
      final url =
          "$kBaseProxy/driver/hgs?driver_id=$_driverId&runtime=20&multi_merge=true";
      final res = await http.get(Uri.parse(url));

      if (res.statusCode != 200) {
        _snack("Driver HGS error: ${res.statusCode}");
        _log("Body: ${res.body}");
        return;
      }

      final data = json.decode(res.body);
      if (data["error"] != null) {
        _snack("Driver HGS error: ${data["error"]}");
        _log("Error: ${data["error"]}");
        return;
      }

      final geo = data["geo"] as List<dynamic>?;
      if (geo == null || geo.isEmpty) {
        _snack("No geo routes for driver");
        _log("geo is empty");
        return;
      }

      // Use first merged route
      final route0 = geo[0] as List<dynamic>;
      if (route0.length < 2) {
        _snack("Route has too few points");
        return;
      }

      // Build StopInfo list
      final List<StopInfo> stops = [];
      for (final n in route0) {
        if (n is! Map<String, dynamic>) continue;
        final node = (n["node"] as num?)?.toInt() ?? 0;
        final lat = (n["lat"] as num).toDouble();
        final lon = (n["lon"] as num).toDouble();
        final name = n["name"] as String?;
        final kind = n["kind"] as String?;
        final orderId = n["order_id"] as String?;

        final status = (kind == "hospital")
            ? RouteStopStatus.depot
            : RouteStopStatus.pending;

        stops.add(
          StopInfo(
            node: node,
            position: LatLng(lat, lon),
            name: name,
            orderId: orderId,
            status: status,
          ),
        );
      }

      if (stops.length < 2) {
        _snack("Not enough stops in HGS result");
        return;
      }

      _stops = stops;
      _log("Loaded ${_stops.length} stops (including depot).");

      // Stability: start sessions + load config for every order
      await _initStabilityForAllOrders();

      // Build route polyline using OSRM from depot → pending stops → depot
      await _rebuildRoutePolyline(initial: true);

      // Start simulation timer
      _startSimulation();
      _startStabilityLoop();
    } catch (e) {
      _snack("Failed to load driver route: $e");
      _log("Exception in _loadDriverRoute: $e");
    }
  }

  // ---------------------------------------------------------------------------
  // 🧊 Stability: init for all orders
  // ---------------------------------------------------------------------------

  Future<void> _initStabilityForAllOrders() async {
    _log("Starting stability sessions for all orders...");

    for (final stop in _stops) {
      if (stop.orderId == null || stop.status != RouteStopStatus.pending) {
        continue;
      }

      final oid = stop.orderId!;
      try {
        // 1) start session
        final startRes = await http.post(
          Uri.parse("$kBaseProxy/stability/start?order_id=$oid"),
        );
        if (startRes.statusCode != 200) {
          _log("Stability start failed for $oid: ${startRes.statusCode}");
          continue;
        }

        // 2) load config
        final cfgRes = await http.get(
          Uri.parse("$kBaseProxy/stability/config/$oid"),
        );
        if (cfgRes.statusCode != 200) {
          _log("Stability config failed for $oid: ${cfgRes.statusCode}");
          continue;
        }

        final cfg = json.decode(cfgRes.body);
        final maxExc = (cfg["max_excursion_temp"] as num).toDouble();
        final maxTime = cfg["max_time_exertion_seconds"] as int;

        stop.maxExcTemp = maxExc;
        stop.maxTimeSec = maxTime;
        stop.remainingSec = maxTime;
        stop.timerStarted = false;
        stop.maxExceeded = false;
        stop.timeExpired = false;

        _log("Stability config $oid → maxExc=$maxExc° maxTime=${maxTime}s");
      } catch (e) {
        _log("Exception in _initStabilityForAllOrders ($oid): $e");
      }
    }
  }

  // ---------------------------------------------------------------------------
  // 🚗 Simulation: car moves along current OSRM route
  // ---------------------------------------------------------------------------

  void _startSimulation() {
    _simTimer?.cancel();

    if (_routePolyline.length < 2) {
      _log("No polyline to simulate on.");
      return;
    }

    _carIndex = 0;
    _carPos = _routePolyline.first;
    _mapController.move(_carPos!, 13);

    _simTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _tickSimulation();
    });

    _log("Simulation started.");
  }

  Future<void> _tickSimulation() async {
    if (_routePolyline.length < 2) return;
    if (_carIndex >= _routePolyline.length - 1) {
      _log("Route finished.");
      _simTimer?.cancel();
      return;
    }

    _carIndex++;
    _carPos = _routePolyline[_carIndex];

    // Center map
    _mapController.move(_carPos!, _mapController.camera.zoom);

    // Check if we reached current active stop
    _checkReachedCurrentStop();

    // Recalculate ETA & distance to next stop
    _updateEtaAndDistanceToNextStop();

    setState(() {});
  }

  // ---------------------------------------------------------------------------
  // 🎯 Find current active stop (first pending)
  // ---------------------------------------------------------------------------

  int _currentStopIndex() {
    for (int i = 0; i < _stops.length; i++) {
      final s = _stops[i];
      if (s.status == RouteStopStatus.pending && s.orderId != null) {
        return i;
      }
    }
    return -1;
  }

  StopInfo? get _currentStop {
    final idx = _currentStopIndex();
    if (idx < 0) return null;
    return _stops[idx];
  }

  // ---------------------------------------------------------------------------
  // 🎯 When car is close enough to current stop → deliver & remove
  // ---------------------------------------------------------------------------

  void _checkReachedCurrentStop() {
    if (_carPos == null) return;
    final idx = _currentStopIndex();
    if (idx < 0) return;

    final stop = _stops[idx];
    final d = kDistance(_carPos!, stop.position);
    if (d < 30.0) {
      _log("✅ Reached stop: ${stop.name ?? stop.orderId}");

      stop.status = RouteStopStatus.delivered;

      // After delivering, rebuild route from current carPos to remaining stops
      _rebuildRoutePolyline().then((_) {
        _carIndex = 0;
        if (_routePolyline.isNotEmpty) {
          _carPos = _routePolyline.first;
        }
        setState(() {});
      });
    }
  }

  // ---------------------------------------------------------------------------
  // 📏 Distance + ETA for current stop (approx based on remaining polyline)
  // ---------------------------------------------------------------------------

  void _updateEtaAndDistanceToNextStop() {
    if (_carPos == null || _routePolyline.isEmpty) {
      _etaNextSec = 0;
      _distNextMeters = 0;
      return;
    }

    double dist = 0;
    for (int i = _carIndex; i < _routePolyline.length - 1; i++) {
      dist += kDistance(_routePolyline[i], _routePolyline[i + 1]);
    }

    // approximate speed: 40 km/h = 11.11 m/s
    const double speedMps = 11.11;
    final double sec = dist / speedMps;

    _distNextMeters = dist;
    _etaNextSec = sec;
  }

  // ---------------------------------------------------------------------------
  // 🗺️ OSRM helper: route between two points
  // ---------------------------------------------------------------------------

  Future<List<LatLng>> _osrmRoute(LatLng a, LatLng b) async {
    final url =
        "$kBaseProxy/route/v1/driving/${a.longitude},${a.latitude};${b.longitude},${b.latitude}?overview=full&geometries=geojson";

    try {
      final res = await http.get(Uri.parse(url));
      if (res.statusCode != 200) {
        _log("OSRM error ${res.statusCode}: ${res.body}");
        return [a, b]; // fallback straight line
      }

      final data = json.decode(res.body);
      final routes = data["routes"] as List<dynamic>;
      if (routes.isEmpty) return [a, b];

      final geom = routes[0]["geometry"]["coordinates"] as List<dynamic>;
      final segment = geom
          .map<LatLng>(
            (c) => LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble()),
          )
          .toList();

      return segment;
    } catch (e) {
      _log("OSRM exception: $e");
      return [a, b];
    }
  }

  // ---------------------------------------------------------------------------
  // 🧱 Rebuild polyline from carPos → pending stops → depot
  // -----------------------------------------------------------------------------

  Future<void> _rebuildRoutePolyline({bool initial = false}) async {
    if (_stops.isEmpty) return;

    // depot is first + last
    final StopInfo depotStart = _stops.first;
    final StopInfo depotEnd = _stops.last;

    LatLng startPos;
    if (initial || _carPos == null) {
      startPos = depotStart.position;
    } else {
      startPos = _carPos!;
    }

    // pending stops
    final List<StopInfo> pendingStops = _stops
        .where((s) => s.status == RouteStopStatus.pending && s.orderId != null)
        .toList();

    // If no pending stops: route only to depot
    final List<LatLng> waypoints = [];
    waypoints.add(startPos);
    for (final s in pendingStops) {
      waypoints.add(s.position);
    }
    // Always go back to depot at end
    waypoints.add(depotEnd.position);

    List<LatLng> newPolyline = [];
    for (int i = 0; i < waypoints.length - 1; i++) {
      final seg = await _osrmRoute(waypoints[i], waypoints[i + 1]);
      if (newPolyline.isEmpty) {
        newPolyline.addAll(seg);
      } else {
        // avoid duplicate join point
        final toAdd = List<LatLng>.from(seg);
        if (newPolyline.last == toAdd.first) {
          toAdd.removeAt(0);
        }
        newPolyline.addAll(toAdd);
      }
    }

    if (newPolyline.isEmpty) {
      _log("Route polyline rebuild produced empty path.");
      return;
    }

    _routePolyline = newPolyline;
    _log(
      "Route polyline rebuilt with ${_routePolyline.length} points (pending: ${pendingStops.length}).",
    );
  }

  // ---------------------------------------------------------------------------
  // 🧊 Stability: periodic update for ALL pending orders
  // ---------------------------------------------------------------------------

  void _startStabilityLoop() {
    _stabilityTimer?.cancel();
    _stabilityTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => _tickStability(),
    );
    _log("Stability loop started.");
  }

  Future<void> _tickStability() async {
    if (_carPos == null) return;

    final tempStr = _tempController.text.trim();
    final double? temp = double.tryParse(tempStr);
    if (temp == null) {
      _log("Invalid temp: $tempStr");
      return;
    }

    // For each pending order, call /stability/update
    for (final stop in _stops) {
      if (stop.orderId == null) continue;
      if (stop.status != RouteStopStatus.pending) continue;

      final oid = stop.orderId!;

      try {
        final res = await http.post(
          Uri.parse("$kBaseProxy/stability/update?order_id=$oid"),
          headers: {"Content-Type": "application/json"},
          body: json.encode({
            "temp": temp,
            "lat": _carPos!.latitude,
            "lon": _carPos!.longitude,
          }),
        );

        if (res.statusCode != 200) {
          _log("Stability update error ($oid): ${res.statusCode}");
          continue;
        }

        final data = json.decode(res.body);

        // Failure: MAX_EXCURSION or TIME_EXPIRED
        if (data["alert"] == "MAX_EXCURSION_EXCEEDED") {
          stop.maxExceeded = true;
          stop.status = RouteStopStatus.spoiled;
          _log("🚨 MAX EXCURSION for $oid → skip stop");

          // After spoiling: rebuild route (skip this node)
          await _rebuildRoutePolyline();
          _carIndex = 0;
          if (_routePolyline.isNotEmpty) {
            _carPos = _routePolyline.first;
          }
          continue;
        }

        if (data["alert"] == "STABILITY_TIME_EXPIRED") {
          stop.timeExpired = true;
          stop.status = RouteStopStatus.spoiled;
          _log("⏰ STABILITY TIME EXPIRED for $oid → skip stop");

          await _rebuildRoutePolyline();
          _carIndex = 0;
          if (_routePolyline.isNotEmpty) {
            _carPos = _routePolyline.first;
          }
          continue;
        }

        if (data["timer_started"] == true) {
          stop.timerStarted = true;
        }

        if (data["remaining_seconds"] != null) {
          stop.remainingSec = (data["remaining_seconds"] as num).round();
        }
      } catch (e) {
        _log("Stability tick exception ($oid): $e");
      }
    }

    // Recompute ETA & distance (route may have changed)
    _updateEtaAndDistanceToNextStop();
    setState(() {});
  }

  // ---------------------------------------------------------------------------
  // 🧮 Formatters
  // ---------------------------------------------------------------------------

  String _fmtDuration(double sec) {
    if (sec <= 0) return "–";
    final m = (sec / 60).round();
    if (m < 60) return "${m}m";
    return "${m ~/ 60}h ${m % 60}m";
  }

  String _fmtDistance(double m) {
    if (m <= 0) return "–";
    if (m >= 1000) return "${(m / 1000).toStringAsFixed(1)} km";
    return "${m.toStringAsFixed(0)} m";
  }

  String _fmtStability(StopInfo? s) {
    if (s == null) return "–";
    if (s.maxExceeded == true) return "⚠ MAX TEMP EXCEEDED";
    if (s.timeExpired == true) return "⚠ STABILITY EXPIRED";
    if (s.timerStarted != true) return "Not started (≤8°C)";
    final sec = s.remainingSec ?? 0;
    final m = sec ~/ 60;
    final remS = sec % 60;
    return "${m}m ${remS}s";
  }

  // ---------------------------------------------------------------------------
  // 🖥 UI
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final currentStop = _currentStop;
    final depot = _stops.isNotEmpty ? _stops.first : null;

    final stabilityText = _fmtStability(currentStop);
    final maxExcText = (currentStop?.maxExcTemp != null)
        ? "Max Exc: ${currentStop!.maxExcTemp!.toStringAsFixed(1)}°C"
        : "Max Exc: –";

    return Scaffold(
      appBar: AppBar(
        title: const Text("🚗 Driver Route + Stability (Sim)"),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () async {
              _simTimer?.cancel();
              _stabilityTimer?.cancel();
              setState(() {
                _stops = [];
                _routePolyline = [];
                _carPos = null;
                _logs.clear();
              });
              await _loadDriverRoute();
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // ===================== MAP =====================
          Expanded(
            child: Stack(
              children: [
                FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    initialCenter:
                        depot?.position ?? const LatLng(24.7136, 46.6753),
                    initialZoom: 13,
                    interactionOptions: const InteractionOptions(
                      flags: InteractiveFlag.all,
                    ),
                  ),
                  children: [
                    TileLayer(
                      urlTemplate:
                          "$kBaseProxy/tiles/styles/basic-preview/{z}/{x}/{y}.png",
                      userAgentPackageName: "com.example.teryaqmap",
                    ),
                    if (_routePolyline.length >= 2)
                      PolylineLayer(
                        polylines: [
                          Polyline(
                            points: _routePolyline,
                            strokeWidth: 4,
                            color: Colors.blue,
                          ),
                        ],
                      ),
                    MarkerLayer(
                      markers: [
                        if (_carPos != null)
                          Marker(
                            point: _carPos!,
                            width: 40,
                            height: 40,
                            child: const Icon(
                              Icons.directions_car,
                              color: Colors.green,
                              size: 32,
                            ),
                          ),
                        // Mark ONLY pending stops (delivered/spoiled disappear)
                        for (final s in _stops)
                          if (s.status == RouteStopStatus.pending &&
                              s.orderId != null)
                            Marker(
                              point: s.position,
                              width: 140,
                              height: 60,
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.location_on,
                                    color: Colors.red,
                                    size: 30,
                                  ),
                                  if (s.name != null)
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 4,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        borderRadius: BorderRadius.circular(4),
                                        boxShadow: const [
                                          BoxShadow(
                                            blurRadius: 2,
                                            color: Colors.black26,
                                          ),
                                        ],
                                      ),
                                      child: Text(
                                        s.name!,
                                        style: const TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w500,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                      ],
                    ),
                  ],
                ),

                // Top overlay: ETA + distance + next + stability
                Positioned(
                  top: 10,
                  left: 10,
                  right: 10,
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.95),
                      borderRadius: BorderRadius.circular(8),
                      boxShadow: const [
                        BoxShadow(blurRadius: 4, color: Colors.black26),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Row 1: driver + depot
                        if (depot != null)
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Text(
                                  "Driver: $_driverId",
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 12),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  "Depot: ${depot.name ?? 'hospital'}",
                                  overflow: TextOverflow.ellipsis,
                                  textAlign: TextAlign.right,
                                  style: const TextStyle(fontSize: 12),
                                ),
                              ),
                            ],
                          ),
                        const SizedBox(height: 4),
                        // Row 2: ETA + distance + next stop name
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text("Next ETA: ${_fmtDuration(_etaNextSec)}"),
                            Text("Next dist: ${_fmtDistance(_distNextMeters)}"),
                            if (currentStop != null)
                              Expanded(
                                child: Text(
                                  "Next: ${currentStop.name ?? currentStop.orderId ?? '-'}",
                                  overflow: TextOverflow.ellipsis,
                                  textAlign: TextAlign.right,
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        // Row 3: Stability line
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Text(
                                "Stability: $stabilityText",
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color:
                                      (currentStop?.maxExceeded == true ||
                                          currentStop?.timeExpired == true)
                                      ? Colors.red
                                      : Colors.black87,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              maxExcText,
                              style: const TextStyle(fontSize: 12),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          // ===================== CONTROLS + LOGS =====================
          Container(
            color: Colors.grey.shade100,
            padding: const EdgeInsets.all(8),
            child: Column(
              children: [
                // Temperature control
                Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: TextField(
                        controller: _tempController,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: "Temp (°C)",
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 1,
                      child: ElevatedButton(
                        onPressed: _tickStability,
                        child: const Text("Send once"),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                SizedBox(
                  height: 140,
                  child: ListView.builder(
                    itemCount: _logs.length,
                    itemBuilder: (_, i) => Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 2,
                      ),
                      child: Text(
                        _logs[i],
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
