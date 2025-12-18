// 📂 lib/features/driver/driver_home.dart

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;

import 'package:teryagapptry/constants/app_colors.dart';
import 'package:teryagapptry/widgets/custom_top_bar.dart';
import 'package:teryagapptry/widgets/custom_bottom_nav_driver.dart';
import 'package:teryagapptry/widgets/show_teryaq_menu.dart';

import 'package:teryagapptry/services/driver_service.dart';
import 'package:teryagapptry/features/driver/driver_delivery.dart';
import 'package:teryagapptry/features/driver/driver_history.dart';

// 🔵 Proxy gateway (map + HGS + stability)
const String kDriverGatewayBase = "http://192.168.8.113:8088";

class DriverHome extends StatefulWidget {
  const DriverHome({super.key});

  @override
  State<DriverHome> createState() => _DriverHomeState();
}

class _DriverHomeState extends State<DriverHome> with WidgetsBindingObserver {
  bool loading = true;

  // blocks multiple taps + shows overlay
  bool _isStartingDay = false;

  // avoid overlapping refreshes
  bool _loadingInFlight = false;

  String driverName = "Driver";
  List<Map<String, dynamic>> todayOrders = [];
  List<Map<String, dynamic>> historyOrders = [];

  // Local cache: order_id → {'eta_minutes': int, 'max_excursion_minutes': int}
  Map<String, Map<String, int>> _localTimesByOrder = {};

  // HGS in-memory cache shared across ALL DriverHome instances
  static List<String>? _cachedHgsSequence;
  static DateTime? _lastHgsFetch;
  static const Duration _hgsCacheDuration = Duration(hours: 2);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadDriverData();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // Refresh when app returns (common case: user leaves delivery/dashboard then comes back)
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _loadDriverData();
    }
  }

  // =====================================================
  // LOCAL "DB" HELPERS (SharedPreferences)
  // =====================================================

  Future<void> _loadLocalOrderTimes() async {
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getKeys();

    final Map<String, Map<String, int>> result = {};

    for (final key in keys) {
      if (!key.startsWith("order_times_")) continue;

      final jsonString = prefs.getString(key);
      if (jsonString == null) continue;

      try {
        final data = jsonDecode(jsonString);
        final String orderId = key.replaceFirst("order_times_", "");

        final int? eta = data["eta_minutes"] is int
            ? data["eta_minutes"] as int
            : int.tryParse(data["eta_minutes"]?.toString() ?? "");

        final int? exc = data["max_excursion_minutes"] is int
            ? data["max_excursion_minutes"] as int
            : int.tryParse(data["max_excursion_minutes"]?.toString() ?? "");

        final Map<String, int> entry = {};
        if (eta != null) entry["eta_minutes"] = eta;
        if (exc != null) entry["max_excursion_minutes"] = exc;

        if (entry.isNotEmpty) {
          result[orderId] = entry;
        }
      } catch (_) {
        // ignore bad data
      }
    }

    _localTimesByOrder = result;
    debugPrint("DriverHome → Loaded local times: $_localTimesByOrder");
  }

  Future<void> _saveOrderTimesLocally(
    String orderId, {
    int? etaMinutes,
    int? maxExcursionMinutes,
  }) async {
    if (orderId.isEmpty) return;
    if (etaMinutes == null && maxExcursionMinutes == null) return;

    final prefs = await SharedPreferences.getInstance();
    final key = "order_times_$orderId";

    final existing = _localTimesByOrder[orderId] ?? {};
    if (etaMinutes != null) existing["eta_minutes"] = etaMinutes;
    if (maxExcursionMinutes != null) {
      existing["max_excursion_minutes"] = maxExcursionMinutes;
    }
    _localTimesByOrder[orderId] = existing;

    await prefs.setString(key, jsonEncode(existing));
    debugPrint("DriverHome → Saved local times for $orderId = $existing");
  }

  void _applyLocalTimes(List<Map<String, dynamic>> orders) {
    for (final o in orders) {
      final oid = (o["order_id"] ?? "").toString();
      if (oid.isEmpty) continue;

      final local = _localTimesByOrder[oid];
      if (local == null) continue;

      if (local["eta_minutes"] != null) {
        o["eta_minutes"] = local["eta_minutes"];
      }
      if (local["max_excursion_minutes"] != null) {
        o["max_excursion_minutes"] = local["max_excursion_minutes"];
      }
    }
  }

  // =====================================================
  // LOAD ALL DRIVER DATA + HGS ORDER + ETA + STABILITY
  // =====================================================
  Future<void> _loadDriverData() async {
    if (_loadingInFlight) return;
    _loadingInFlight = true;

    try {
      if (mounted) setState(() => loading = true);

      // 0) Local cache first
      await _loadLocalOrderTimes();

      // 1) Profile once (avoid multiple /driver/me calls)
      final profile = await DriverService.getDriverProfile();
      final String name = (profile["name"] ?? "Driver").toString();
      final String driverId = (profile["driver_id"] ?? profile["id"] ?? "")
          .toString();

      // 2) Today + History in parallel
      final results = await Future.wait([
        DriverService.getTodayOrders(driverId: driverId),
        DriverService.getOrdersHistory(driverId: driverId),
      ]);

      final rawToday = results[0];
      final rawHistory = results[1];

      // Flatten today
      List<Map<String, dynamic>> tOrders = [];
      if (rawToday is List) {
        tOrders = rawToday.whereType<Map>().map<Map<String, dynamic>>((e) {
          final m = Map<String, dynamic>.from(e as Map);
          if (m["order_id"] == null && m["order"] is Map) {
            final ord = Map<String, dynamic>.from(m["order"] as Map);
            m["order_id"] ??= ord["order_id"];
            m["arrival_time"] ??= ord["arrival_time"];
            m["remaining_stability"] ??= ord["remaining_stability"];
            m["eta_minutes"] ??= ord["eta_minutes"];
            m["max_excursion_minutes"] ??= ord["max_excursion_minutes"];
          }
          return m;
        }).toList();
      }

      // Flatten history
      List<Map<String, dynamic>> hOrders = [];
      if (rawHistory is List) {
        hOrders = rawHistory.whereType<Map>().map<Map<String, dynamic>>((e) {
          final m = Map<String, dynamic>.from(e as Map);
          if (m["order_id"] == null && m["order"] is Map) {
            final ord = Map<String, dynamic>.from(m["order"] as Map);
            m["order_id"] ??= ord["order_id"];
            m["arrival_time"] ??= ord["arrival_time"];
            m["remaining_stability"] ??= ord["remaining_stability"];
            m["eta_minutes"] ??= ord["eta_minutes"];
            m["max_excursion_minutes"] ??= ord["max_excursion_minutes"];
          }
          return m;
        }).toList();
      }

      // 3) Apply local cache to both lists
      _applyLocalTimes(tOrders);
      _applyLocalTimes(hOrders);

      // 4) Enrich today orders with HGS + cumulative ETA
      if (driverId.isNotEmpty && tOrders.isNotEmpty) {
        await _enrichTodayOrdersWithHgsAndTimes(
          driverId: driverId,
          todayOrders: tOrders,
        );
      }

      if (!mounted) return;
      setState(() {
        driverName = name;
        todayOrders = tOrders;
        historyOrders = hOrders;
        loading = false;
      });
    } catch (e) {
      debugPrint("DriverHome → Error: $e");
      if (!mounted) return;
      setState(() {
        loading = false;
        todayOrders = [];
        historyOrders = [];
      });
    } finally {
      _loadingInFlight = false;
    }
  }

  // =====================================================
  // HGS + ETA + Stability (optimized, cumulative ETA)
  // =====================================================
  Future<void> _enrichTodayOrdersWithHgsAndTimes({
    required String driverId,
    required List<Map<String, dynamic>> todayOrders,
  }) async {
    // do we need ETA for any order?
    final bool needsEtaForSomeOrder = todayOrders.any((o) {
      if (o["eta_minutes"] != null) return false;
      final oid = (o["order_id"] ?? "").toString();
      if (oid.isEmpty) return false;
      final local = _localTimesByOrder[oid];
      if (local != null && local["eta_minutes"] != null) return false;
      return true;
    });

    Map<String, int> etaCumulativeByOrder = {};
    List<String> hgsOrder = _cachedHgsSequence ?? [];

    final bool hgsCacheExpired =
        _lastHgsFetch == null ||
        DateTime.now().difference(_lastHgsFetch!) > _hgsCacheDuration;

    if (needsEtaForSomeOrder || _cachedHgsSequence == null || hgsCacheExpired) {
      try {
        final uri = Uri.parse(
          "$kDriverGatewayBase/driver/hgs?driver_id=$driverId",
        );
        debugPrint("DriverHome → Fetching HGS from: $uri");
        final res = await http.get(uri);

        if (res.statusCode == 200) {
          final data = jsonDecode(res.body);

          final List<dynamic> geo = (data["geo"] as List?) ?? [];
          final List<dynamic> routes = (data["routes"] as List?) ?? [];

          // HGS sequence
          if (data["debug"] is Map &&
              (data["debug"]["hgs_order"] is List<dynamic>)) {
            hgsOrder = (data["debug"]["hgs_order"] as List<dynamic>)
                .map((e) => e.toString())
                .toList();
          } else {
            hgsOrder = _extractOrderIdsFromHgsGeo(geo);
          }

          if (hgsOrder.isNotEmpty) {
            _cachedHgsSequence = hgsOrder;
            _lastHgsFetch = DateTime.now();
          }

          // cumulative ETA map if provided
          if (data["debug"] is Map &&
              (data["debug"]["eta_cumulative_by_order"] is Map)) {
            final rawMap =
                data["debug"]["eta_cumulative_by_order"]
                    as Map<String, dynamic>;
            rawMap.forEach((key, val) {
              int? mins;
              if (val is int) mins = val;
              if (val is num) mins = val.round();
              if (val is String) mins = int.tryParse(val);
              if (mins != null) etaCumulativeByOrder[key] = mins;
            });
          } else {
            // fallback rebuild from legs
            final Map<int, String> nodeOrder = {};
            for (final route in geo) {
              if (route is! List) continue;
              for (final node in route) {
                if (node is! Map) continue;
                if (node["kind"]?.toString() != "patient") continue;

                final nodeDyn = node["node"];
                final int? nodeId = nodeDyn is int
                    ? nodeDyn
                    : int.tryParse(nodeDyn.toString());
                if (nodeId == null) continue;

                final oid = node["order_id"]?.toString();
                if (oid == null || oid.isEmpty) continue;

                nodeOrder[nodeId] = oid;
              }
            }

            for (final route in routes) {
              if (route is! Map) continue;

              final List<dynamic>? pathList = route["path"] as List<dynamic>?;
              final List<dynamic>? legsList = route["legs"] as List<dynamic>?;
              if (pathList == null || legsList == null) continue;

              final List<int> pathNodes = pathList
                  .map<int?>((e) => e is int ? e : int.tryParse(e.toString()))
                  .whereType<int>()
                  .toList();

              for (
                int i = 0;
                i < legsList.length && i + 1 < pathNodes.length;
                i++
              ) {
                final leg = legsList[i];
                if (leg is! Map) continue;

                final arrivalNode = pathNodes[i + 1];
                final oid = nodeOrder[arrivalNode];
                if (oid == null) continue;

                final cumRaw = leg["cumulative_eta_min"];
                int? minutes;
                if (cumRaw is num) minutes = cumRaw.round();
                if (cumRaw is String) minutes = int.tryParse(cumRaw);
                if (minutes == null) continue;

                final existing = etaCumulativeByOrder[oid];
                if (existing == null || minutes < existing) {
                  etaCumulativeByOrder[oid] = minutes;
                }
              }
            }
          }
        } else {
          debugPrint("DriverHome → HGS error ${res.statusCode}: ${res.body}");
        }
      } catch (e) {
        debugPrint("DriverHome → HGS fetch failed: $e");
      }
    }

    // Sort today orders by HGS
    if (hgsOrder.isNotEmpty) {
      final Map<String, int> pos = {};
      for (int i = 0; i < hgsOrder.length; i++) {
        pos[hgsOrder[i]] = i;
      }

      todayOrders.sort((a, b) {
        final aId = (a["order_id"] ?? "").toString();
        final bId = (b["order_id"] ?? "").toString();
        final ai = pos[aId] ?? 999999;
        final bi = pos[bId] ?? 999999;
        return ai.compareTo(bi);
      });
    }

    // Attach ETA if missing
    if (etaCumulativeByOrder.isNotEmpty) {
      for (final o in todayOrders) {
        final oid = (o["order_id"] ?? "").toString();
        if (oid.isEmpty) continue;
        if (o["eta_minutes"] != null) continue;

        final eta = etaCumulativeByOrder[oid];
        if (eta != null) o["eta_minutes"] = eta;
      }
    }

    // Build UI cumulative ETA
    if (todayOrders.isNotEmpty) {
      int running = 0;
      for (final o in todayOrders) {
        final oid = (o["order_id"] ?? "").toString();
        if (oid.isEmpty) continue;

        int? base;
        final raw = o["eta_minutes"];
        if (raw is int) base = raw;
        if (raw is String) base = int.tryParse(raw);

        base ??= etaCumulativeByOrder[oid];
        if (base == null) continue;

        running += base;
        o["eta_cumulative_minutes"] = running;
      }
    }

    // Persist times locally
    for (final o in todayOrders) {
      final oid = (o["order_id"] ?? "").toString();
      if (oid.isEmpty) continue;

      int? etaMinutes;
      int? stabilityMinutes;

      final etaRaw = o["eta_minutes"];
      if (etaRaw is int) etaMinutes = etaRaw;
      if (etaRaw is String) etaMinutes = int.tryParse(etaRaw);

      final stRaw = o["max_excursion_minutes"];
      if (stRaw is int) stabilityMinutes = stRaw;
      if (stRaw is String) stabilityMinutes = int.tryParse(stRaw);

      await _saveOrderTimesLocally(
        oid,
        etaMinutes: etaMinutes,
        maxExcursionMinutes: stabilityMinutes,
      );
    }
  }

  List<String> _extractOrderIdsFromHgsGeo(dynamic geoRaw) {
    final List<String> result = [];
    if (geoRaw is! List) return result;

    for (final route in geoRaw) {
      if (route is! List) continue;
      for (final node in route) {
        if (node is! Map) continue;
        if (node["kind"]?.toString() != "patient") continue;

        final oid = node["order_id"]?.toString();
        if (oid == null || oid.isEmpty) continue;

        if (!result.contains(oid)) result.add(oid);
      }
    }
    return result;
  }

  // =====================================================
  // UI
  // =====================================================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: CustomTopBar(title: "", onMenuTap: () => showTeryaqMenu(context)),
      bottomNavigationBar: CustomBottomNavDriver(
        currentIndex: 0,
        onTap: (index) async {
          if (index == 2) {
            await Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const DriverHistory()),
            );
            // refresh after returning
            await _loadDriverData();
          }
        },
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : _buildHomeUI(),
    );
  }

  Widget _buildHomeUI() {
    final List<String> orderSequence = todayOrders
        .map((e) => (e["order_id"] ?? "").toString())
        .where((id) => id.isNotEmpty)
        .toList();

    return Stack(
      children: [
        Container(
          height: 225.h,
          decoration: const BoxDecoration(
            color: AppColors.appHeader,
            borderRadius: BorderRadius.only(
              bottomLeft: Radius.circular(80),
              bottomRight: Radius.circular(80),
            ),
          ),
        ),

        SingleChildScrollView(
          padding: EdgeInsets.symmetric(horizontal: 25.w, vertical: 70.h),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(height: 40.h),

              Row(
                children: [
                  Text(
                    "${"hello".tr()} $driverName",
                    style: TextStyle(
                      fontSize: 25.sp,
                      fontWeight: FontWeight.w600,
                      color: AppColors.headingText,
                    ),
                  ),
                  SizedBox(width: 6.w),
                  const Text("👋", style: TextStyle(fontSize: 26)),
                ],
              ),

              SizedBox(height: 25.h),

              Center(
                child: GestureDetector(
                  onTap: (todayOrders.isEmpty || _isStartingDay)
                      ? null
                      : () async {
                          final first = todayOrders.first;
                          final orderId = (first["order_id"] ?? "").toString();

                          if (orderId.isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text("Invalid order_id"),
                                backgroundColor: Colors.red,
                              ),
                            );
                            return;
                          }

                          setState(() => _isStartingDay = true);

                          try {
                            await DriverService.startDay(orderId);

                            // IMPORTANT: refresh after status change
                            await _loadDriverData();
                          } catch (e) {
                            debugPrint("DriverHome → startDay error: $e");
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text("Failed to start deliveries."),
                                  backgroundColor: Colors.red,
                                ),
                              );
                            }
                            return;
                          } finally {
                            if (mounted) setState(() => _isStartingDay = false);
                          }

                          final List<String> updatedSequence = todayOrders
                              .map((e) => (e["order_id"] ?? "").toString())
                              .where((id) => id.isNotEmpty)
                              .toList();

                          final int idx = updatedSequence.indexOf(orderId);

                          await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => DriverDelivery(
                                orderId: orderId,
                                orderSequence: updatedSequence,
                                currentIndex: idx < 0 ? 0 : idx,
                              ),
                            ),
                          );

                          // IMPORTANT: refresh when returning
                          await _loadDriverData();
                        },
                  child: Container(
                    width: 322.w,
                    height: 82.h,
                    decoration: BoxDecoration(
                      color: (todayOrders.isEmpty || _isStartingDay)
                          ? Colors.grey
                          : AppColors.buttonRed,
                      borderRadius: BorderRadius.circular(16.r),
                    ),
                    alignment: Alignment.center,
                    child: _isStartingDay
                        ? Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              SizedBox(
                                width: 22.w,
                                height: 22.w,
                                child: const CircularProgressIndicator(
                                  strokeWidth: 2.5,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    Colors.white,
                                  ),
                                ),
                              ),
                              SizedBox(width: 12.w),
                              Text(
                                "Starting...",
                                style: TextStyle(
                                  fontSize: 18.sp,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          )
                        : Text(
                            "start_delivery".tr(),
                            style: TextStyle(
                              fontSize: 20.sp,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                  ),
                ),
              ),

              SizedBox(height: 35.h),

              Text(
                "today_orders".tr(),
                style: TextStyle(
                  fontSize: 25.sp,
                  fontWeight: FontWeight.w600,
                  color: AppColors.headingText,
                ),
              ),

              SizedBox(height: 20.h),

              todayOrders.isEmpty
                  ? _buildNoOrdersWidget()
                  : Column(
                      children: todayOrders.asMap().entries.map((entry) {
                        final idx = entry.key + 1;
                        final order = entry.value;
                        final orderId = (order["order_id"] ?? "").toString();

                        return GestureDetector(
                          onTap: () async {
                            if (orderId.isEmpty) return;

                            final seqIndex = orderSequence.indexOf(orderId);

                            await Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => DriverDelivery(
                                  orderId: orderId,
                                  orderSequence: orderSequence,
                                  currentIndex: seqIndex < 0 ? 0 : seqIndex,
                                ),
                              ),
                            );

                            // IMPORTANT: refresh when returning
                            await _loadDriverData();
                          },
                          child: Padding(
                            padding: EdgeInsets.only(bottom: 14.h),
                            child: _buildTodayOrderCard(order, idx),
                          ),
                        );
                      }).toList(),
                    ),

              SizedBox(height: 35.h),

              Text(
                "order_history".tr(),
                style: TextStyle(
                  fontSize: 25.sp,
                  fontWeight: FontWeight.w600,
                  color: AppColors.headingText,
                ),
              ),

              SizedBox(height: 20.h),

              historyOrders.isEmpty
                  ? _buildNoOrdersWidget()
                  : Column(
                      children: historyOrders.asMap().entries.map((entry) {
                        final idx = entry.key + 1;
                        final order = entry.value;

                        return GestureDetector(
                          onTap: () async {
                            await Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const DriverHistory(),
                              ),
                            );
                            await _loadDriverData();
                          },
                          child: Padding(
                            padding: EdgeInsets.only(bottom: 14.h),
                            child: _buildHistoryOrderCard(order, idx),
                          ),
                        );
                      }).toList(),
                    ),

              SizedBox(height: 50.h),
            ],
          ),
        ),

        if (_isStartingDay)
          Positioned.fill(
            child: Container(
              color: Colors.black.withOpacity(0.35),
              child: Center(
                child: Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: 18.w,
                    vertical: 16.h,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16.r),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 22.w,
                        height: 22.w,
                        child: const CircularProgressIndicator(
                          strokeWidth: 2.5,
                        ),
                      ),
                      SizedBox(width: 12.w),
                      Text(
                        "Starting deliveries...",
                        style: TextStyle(
                          fontSize: 14.sp,
                          fontWeight: FontWeight.w600,
                          color: AppColors.headingText,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  // =====================================================
  // FORMAT MINUTES → "3h 40m"
  // =====================================================
  String _formatMinutes(int minutes) {
    if (minutes <= 0) return "0m";
    final h = minutes ~/ 60;
    final m = minutes % 60;
    if (h > 0 && m > 0) return "${h}h ${m}m";
    if (h > 0) return "${h}h";
    return "${m}m";
  }

  Widget _buildTimesRow(String arrivalTime, String stabilityTime) {
    final arrivalParts = arrivalTime.split(" ");
    String hospitalTime = "";
    String hospitalMinutes = "";
    if (arrivalParts.length >= 2) {
      hospitalTime = arrivalParts[0];
      hospitalMinutes = arrivalParts[1];
    } else if (arrivalParts.length == 1) {
      hospitalTime = arrivalParts[0];
    }

    final stabilityParts = stabilityTime.split(" ");
    String medTimeH = "";
    String medTimeM = "";
    if (stabilityParts.length >= 2) {
      medTimeH = stabilityParts[0];
      medTimeM = stabilityParts[1];
    } else if (stabilityParts.length == 1) {
      medTimeH = stabilityParts[0];
    }

    return Row(
      children: [
        Icon(Icons.access_time, size: 13.sp, color: AppColors.bodyText),
        SizedBox(width: 4.w),

        if (hospitalTime.isNotEmpty)
          Text(hospitalTime, style: TextStyle(fontSize: 11.sp)),
        if (hospitalMinutes.isNotEmpty) ...[
          SizedBox(width: 10.w),
          Text(hospitalMinutes, style: TextStyle(fontSize: 11.sp)),
        ],

        SizedBox(width: 14.w),

        SvgPicture.asset(
          "assets/icons/prescription.svg",
          width: 14.w,
          height: 14.h,
          colorFilter: const ColorFilter.mode(
            AppColors.bodyText,
            BlendMode.srcIn,
          ),
        ),
        SizedBox(width: 4.w),

        if (medTimeH.isNotEmpty)
          Text(medTimeH, style: TextStyle(fontSize: 11.sp)),
        if (medTimeM.isNotEmpty) ...[
          SizedBox(width: 6.w),
          Text(medTimeM, style: TextStyle(fontSize: 11.sp)),
        ],
      ],
    );
  }

  Widget _buildTodayOrderCard(Map<String, dynamic> data, int number) {
    final String hospital =
        (data["hospital_name"] ?? data["hospital"] ?? "King Khalid Hospital")
            .toString();

    final String stopStreet =
        (data["first_stop"] ??
                data["patient_area"] ??
                data["patient_address"] ??
                data["district"] ??
                "Nuzha")
            .toString();

    final dynamic rawCount = data["orders_count"] ?? data["order_count"];
    String ordersCount;

    if (rawCount == null) {
      ordersCount = "one_order".tr();
    } else if (rawCount is int) {
      ordersCount = rawCount == 1
          ? "one_order".tr()
          : "multiple_orders".tr().replaceAll("{count}", rawCount.toString());
    } else if (rawCount is String) {
      final firstWord = rawCount.split(" ").first;
      final count = int.tryParse(firstWord);
      if (count != null) {
        ordersCount = count == 1
            ? "one_order".tr()
            : "multiple_orders".tr().replaceAll("{count}", count.toString());
      } else {
        ordersCount = rawCount;
      }
    } else {
      ordersCount = "one_order".tr();
    }

    // ETA — prefer cumulative if present
    String arrivalTime;
    final dynamic etaRaw =
        data["eta_cumulative_minutes"] ?? data["eta_minutes"];
    if (etaRaw is int) {
      arrivalTime = _formatMinutes(etaRaw);
    } else if (etaRaw is String && int.tryParse(etaRaw) != null) {
      arrivalTime = _formatMinutes(int.parse(etaRaw));
    } else {
      arrivalTime = (data["arrival_time"] ?? "2h 30m").toString();
    }

    // MAX EXCURSION (stability)
    String stabilityTime;
    final dynamic excRaw = data["max_excursion_minutes"];
    if (excRaw is int) {
      stabilityTime = _formatMinutes(excRaw);
    } else if (excRaw is String && int.tryParse(excRaw) != null) {
      stabilityTime = _formatMinutes(int.parse(excRaw));
    } else {
      stabilityTime = (data["remaining_stability"] ?? "1h 20m").toString();
    }

    return _buildCardShell(
      number: number,
      hospital: hospital,
      stopStreet: stopStreet,
      ordersCount: ordersCount,
      timesRow: _buildTimesRow(arrivalTime, stabilityTime),
    );
  }

  Widget _buildHistoryOrderCard(Map<String, dynamic> data, int number) {
    final String hospital =
        (data["hospital_name"] ?? data["hospital"] ?? "King Khalid Hospital")
            .toString();

    final String stopStreet =
        (data["first_stop"] ??
                data["patient_area"] ??
                data["patient_address"] ??
                data["district"] ??
                "Nuzha")
            .toString();

    final dynamic rawCount = data["orders_count"] ?? data["order_count"];
    String ordersCount;

    if (rawCount == null) {
      ordersCount = "one_order".tr();
    } else if (rawCount is int) {
      ordersCount = rawCount == 1
          ? "one_order".tr()
          : "multiple_orders".tr().replaceAll("{count}", rawCount.toString());
    } else if (rawCount is String) {
      final firstWord = rawCount.split(" ").first;
      final count = int.tryParse(firstWord);
      if (count != null) {
        ordersCount = count == 1
            ? "one_order".tr()
            : "multiple_orders".tr().replaceAll("{count}", count.toString());
      } else {
        ordersCount = rawCount;
      }
    } else {
      ordersCount = "one_order".tr();
    }

    return _buildCardShell(
      number: number,
      hospital: hospital,
      stopStreet: stopStreet,
      ordersCount: ordersCount,
      timesRow: const SizedBox.shrink(),
    );
  }

  Widget _buildCardShell({
    required int number,
    required String hospital,
    required String stopStreet,
    required String ordersCount,
    required Widget timesRow,
  }) {
    return Container(
      width: double.infinity,
      height: 102.h,
      padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16.r),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 6,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          SizedBox(
            width: 60.w,
            child: Center(
              child: Text(
                "$number",
                style: TextStyle(
                  fontSize: 35.sp,
                  fontWeight: FontWeight.w900,
                  color: AppColors.buttonRed,
                ),
              ),
            ),
          ),
          SizedBox(width: 12.w),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  hospital,
                  style: TextStyle(
                    fontSize: 15.sp,
                    fontWeight: FontWeight.w600,
                    color: AppColors.headingText,
                  ),
                ),
                SizedBox(height: 4.h),
                Row(
                  children: [
                    Text(
                      "first_stop".tr(),
                      style: TextStyle(
                        fontSize: 12.sp,
                        fontWeight: FontWeight.w500,
                        color: AppColors.buttonBlue,
                      ),
                    ),
                    Expanded(
                      child: Text(
                        stopStreet,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12.sp,
                          fontWeight: FontWeight.w600,
                          color: AppColors.buttonRed,
                        ),
                      ),
                    ),
                    SizedBox(width: 6.w),
                    Text(
                      ordersCount,
                      style: TextStyle(
                        fontSize: 11.sp,
                        fontWeight: FontWeight.w600,
                        color: AppColors.bodyText,
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 6.h),
                timesRow,
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNoOrdersWidget() {
    return Center(
      child: Column(
        children: [
          Image.asset("assets/icons/tick.png", width: 170.w, height: 170.h),
          SizedBox(height: 12.h),
          Text(
            "there_are_no_orders_for_today".tr(),
            style: TextStyle(
              fontSize: 18.sp,
              fontWeight: FontWeight.w600,
              color: AppColors.bodyText,
            ),
          ),
        ],
      ),
    );
  }
}
