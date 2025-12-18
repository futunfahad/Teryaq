// lib/map_page.dart
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:http/http.dart' as http;

// ============================
// 🌐 CONFIG — your real servers
// ============================
const String kBaseProxy = "http://192.168.8.104:8088";
const String kBackendBase = kBaseProxy;
const String kOsrmBase = kBaseProxy;
const String kTilesBase = "$kBaseProxy/tiles";

class MapPage extends StatefulWidget {
  const MapPage({super.key});

  @override
  State<MapPage> createState() => _MapPageState();
}

class _MapPageState extends State<MapPage> {
  final MapController _mapController = MapController();
  final Distance _distance = const Distance();

  // ======================================
  // REAL HGS ROUTE VARIABLES
  // ======================================
  List<List<LatLng>> _allStops = [];
  List<List<String?>> _allNames = [];
  List<LatLng> _stops = [];
  List<String?> _names = [];
  List<LatLng> _plannedRoute = [];
  List<LatLng> _liveRoute = [];

  LatLng? _userPos;
  StreamSubscription<Position>? _posSub;

  double _etaNextSec = 0.0;
  double _distNextMeters = 0.0;

  final List<String> _logs = [];

  // ======================================
  // 🧊 STABILITY VARIABLES
  // ======================================
  String orderId = ""; // YOU TYPE IT
  bool stabilityActive = false;
  double currentTemp = 1.0;
  double? minSafeTemp;
  double? maxSafeTemp;
  int? stabilityCountdown;
  String stabilityStatus = "Idle";

  // ======================================
  void _log(String msg) {
    final ts = DateTime.now().toIso8601String().substring(11, 19);
    setState(() => _logs.add("[$ts] $msg"));
  }

  @override
  void initState() {
    super.initState();
    _fetchHgs();
    _initLocationTracking();
  }

  @override
  void dispose() {
    _posSub?.cancel();
    super.dispose();
  }

  // ======================================
  // 📍 REAL GPS POSITION TRACKING
  // ======================================
  Future<void> _initLocationTracking() async {
    final perm = await Geolocator.requestPermission();
    if (perm == LocationPermission.denied ||
        perm == LocationPermission.deniedForever)
      return;

    _posSub =
        Geolocator.getPositionStream(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.best,
            distanceFilter: 1,
          ),
        ).listen((pos) async {
          final newPos = LatLng(pos.latitude, pos.longitude);
          setState(() => _userPos = newPos);

          _mapController.move(newPos, _mapController.camera.zoom);

          // When moving, update ETA + stability
          await _updateRouteFromUserToNextStop();
          await _sendStabilityUpdate();
        });
  }

  // ======================================
  // 🧠 REAL HGS ROUTE FETCH
  // ======================================
  Future<void> _fetchHgs() async {
    final url = "$kBackendBase/hgs";
    final res = await http.get(Uri.parse(url));

    final data = json.decode(res.body);
    final routes = data["routes"] as List;

    final parsedCoords = <List<LatLng>>[];
    final parsedNames = <List<String?>>[];

    for (final r in routes) {
      final one = <LatLng>[];
      final names = <String?>[];
      for (final p in r) {
        one.add(LatLng(p["lat"], p["lon"]));
        names.add(p["name"]);
      }
      parsedCoords.add(one);
      parsedNames.add(names);
    }

    final streetRoute = await _buildStreetRouteFromHgs(parsedCoords.first);

    setState(() {
      _allStops = parsedCoords;
      _allNames = parsedNames;
      _stops = parsedCoords.first;
      _names = parsedNames.first;
      _plannedRoute = streetRoute;
    });
  }

  // REAL STREET ROUTE BUILDER (OSRM)
  Future<List<LatLng>> _buildStreetRouteFromHgs(List<LatLng> pts) async {
    List<LatLng> route = [];
    for (int i = 0; i < pts.length - 1; i++) {
      final p1 = pts[i];
      final p2 = pts[i + 1];
      final url =
          "$kOsrmBase/route/v1/driving/${p1.longitude},${p1.latitude};${p2.longitude},${p2.latitude}?overview=full&geometries=geojson";

      final res = await http.get(Uri.parse(url));
      final coords =
          (json.decode(res.body)["routes"][0]["geometry"]["coordinates"]
                  as List)
              .map((c) => LatLng(c[1], c[0]))
              .toList();

      if (route.isNotEmpty && route.last == coords.first) coords.removeAt(0);
      route.addAll(coords);
    }
    return route;
  }

  // UPDATE ROUTE + ETA USING REAL OSRM
  Future<void> _updateRouteFromUserToNextStop() async {
    if (_userPos == null || _stops.isEmpty) return;

    final next = _stops.first;
    final url =
        "$kOsrmBase/route/v1/driving/${_userPos!.longitude},${_userPos!.latitude};${next.longitude},${next.latitude}?overview=full&geometries=geojson";

    final res = await http.get(Uri.parse(url));
    final r = json.decode(res.body)["routes"][0];

    final coords = (r["geometry"]["coordinates"] as List)
        .map((c) => LatLng(c[1], c[0]))
        .toList();

    setState(() {
      _liveRoute = coords;
      _etaNextSec = r["duration"].toDouble();
      _distNextMeters = r["distance"].toDouble();
    });
  }

  // ===============================
  // 🌡 START STABILITY
  // ===============================
  Future<void> _startStability() async {
    if (orderId.isEmpty) {
      _snack("Enter Order ID first!");
      return;
    }

    final url = Uri.parse(
      "$kBackendBase/stability/start?order_id=$orderId&eta_seconds=${_etaNextSec.round()}",
    );

    final res = await http.post(url);
    final data = json.decode(res.body);

    if (data["status"] == "started") {
      setState(() {
        minSafeTemp = data["limits"]["min_safe"].toDouble();
        maxSafeTemp = data["limits"]["max_safe"].toDouble();
        stabilityActive = true;
        stabilityStatus = "Monitoring...";
      });
    } else {
      stabilityStatus = "Error";
    }
  }

  // ===============================
  // 🌡 UPDATE STABILITY
  // ===============================
  Future<void> _sendStabilityUpdate() async {
    if (!stabilityActive) return;
    if (_userPos == null) return;

    final url = Uri.parse(
      "$kBackendBase/stability/update"
      "?temp=$currentTemp"
      "&lat=${_userPos!.latitude}"
      "&lon=${_userPos!.longitude}"
      "&eta_seconds=${_etaNextSec.round()}",
    );

    final res = await http.post(url);
    final data = json.decode(res.body);

    if (data["status"] == "ok") {
      setState(() {
        stabilityCountdown = data["remaining_exertion_seconds"];
        stabilityStatus = "OK";
      });
    } else if (data["status"] == "exertion_exceeded") {
      setState(() {
        stabilityStatus = "🚨 Stability Exceeded";
        stabilityActive = false;
      });
    } else if (data["status"] == "critical_spoilage") {
      setState(() {
        stabilityStatus = "💀 SPOILED";
        stabilityActive = false;
      });
    }
  }

  // ===============================
  // 🌡 FINISH STABILITY
  // ===============================
  Future<void> _finishStability() async {
    await http.post(Uri.parse("$kBackendBase/stability/finish"));
    setState(() {
      stabilityActive = false;
      stabilityCountdown = null;
      stabilityStatus = "Finished";
    });
  }

  // ===============================
  void _snack(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  // ===============================
  // UI
  // ===============================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("🚚 Teryaq Delivery + Stability")),
      body: Column(
        children: [
          // ========================= MAP =========================
          Expanded(
            child: FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: const LatLng(24.7136, 46.6753),
                initialZoom: 13,
              ),
              children: [
                TileLayer(
                  urlTemplate:
                      "$kTilesBase/styles/basic-preview/{z}/{x}/{y}.png",
                ),

                if (_plannedRoute.length > 2)
                  PolylineLayer(
                    polylines: [
                      Polyline(
                        points: _plannedRoute,
                        color: Colors.grey,
                        strokeWidth: 3,
                      ),
                    ],
                  ),

                if (_liveRoute.length > 2)
                  PolylineLayer(
                    polylines: [
                      Polyline(
                        points: _liveRoute,
                        color: Colors.blue,
                        strokeWidth: 4,
                      ),
                    ],
                  ),

                MarkerLayer(
                  markers: [
                    if (_userPos != null)
                      Marker(
                        point: _userPos!,
                        width: 50,
                        height: 50,
                        child: const Icon(Icons.person_pin_circle, size: 40),
                      ),
                  ],
                ),
              ],
            ),
          ),

          // ========================= STABILITY PANEL =========================
          Container(
            color: Colors.white,
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("Order ID"),
                TextField(
                  onChanged: (v) => orderId = v.trim(),
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                  ),
                ),

                const SizedBox(height: 10),
                Text("Temperature: ${currentTemp.toStringAsFixed(1)}°C"),
                Slider(
                  value: currentTemp,
                  min: -5,
                  max: 20,
                  onChanged: (v) {
                    setState(() => currentTemp = v);
                    _sendStabilityUpdate();
                  },
                ),

                if (minSafeTemp != null)
                  Text(
                    "Safe Range: $minSafeTemp°C → $maxSafeTemp°C",
                    style: const TextStyle(color: Colors.green),
                  ),

                if (stabilityCountdown != null)
                  Text(
                    "Stability Countdown: ${stabilityCountdown}s",
                    style: const TextStyle(color: Colors.red),
                  ),

                Text(
                  "Status: $stabilityStatus",
                  style: const TextStyle(fontSize: 18),
                ),

                Row(
                  children: [
                    ElevatedButton(
                      onPressed: stabilityActive ? null : _startStability,
                      child: const Text("Start"),
                    ),
                    const SizedBox(width: 10),
                    ElevatedButton(
                      onPressed: stabilityActive ? _finishStability : null,
                      child: const Text("Finish"),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
