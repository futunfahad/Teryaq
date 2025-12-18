// ======================================================================
//  PATIENT LOCATION SCREEN – FINAL WORKING VERSION (Dynamic Location)
//  + Reverse Geocoding (shows address under pin)
//  + Saves selected pin + address to backend
//  + B1: Saves addresses LOCALLY (SharedPreferences) per patient national_id
//  + Shows "Saved Addresses" ONLY if there are saved addresses
//  + Fix: title is NOT always "Home" (first saved can be Home; others keep label)
//  + Returns `true` to previous screen (Profile) after save
// ======================================================================

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' as latlng;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:teryagapptry/constants/app_colors.dart';
import 'package:teryagapptry/widgets/custom_top_bar.dart';
import 'package:teryagapptry/services/patient_service.dart';

/// NOTE: kept as-is (even if you use MapConfig.tilesTemplate below)
const String kGatewayBase = 'http://192.168.8.113:8081';

class PatientLocationScreen extends StatefulWidget {
  const PatientLocationScreen({super.key});

  @override
  State<PatientLocationScreen> createState() => _PatientLocationScreenState();
}

class _PatientLocationScreenState extends State<PatientLocationScreen> {
  String _currentSheet = "choose";

  // Backend identity (used for local storage key)
  String _nationalId = "unknown";

  // Address selected/loaded
  String _currentAddress = '';
  String _pinAddress = ''; // shown under the pin (reverse geocoded)
  bool _isPinAddressLoading = false;

  bool _isLoading = false;
  String? _errorMessage;

  final MapController _mapController = MapController();
  double _currentZoom = 14.2;
  bool _mapReady = false;

  // User-selected OR existing location
  latlng.LatLng _mapCenter = latlng.LatLng(24.7136, 46.6753);

  // Saved addresses list (LOCAL)
  List<Map<String, dynamic>> _savedAddresses = [];

  // Controllers (keep UI identical; prevents resets during rebuild)
  final TextEditingController _nameCtrl = TextEditingController();
  final TextEditingController _addrCtrl = TextEditingController();

  // Simple debounce to avoid many reverse-geocode calls on repeated taps
  DateTime _lastTap = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void initState() {
    super.initState();
    _loadInitialAddressFromBackend();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _addrCtrl.dispose();
    super.dispose();
  }

  // Convert dynamic to double
  double? _toDouble(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString());
  }

  // Build full address from backend fields
  String _fullAddressFromBackend(Map<String, dynamic> data) {
    final addr = (data["address"] ?? "").toString();
    final city = (data["city"] ?? "").toString();
    if (addr.isEmpty && city.isEmpty) return "";
    if (addr.isNotEmpty && city.isNotEmpty) return "$addr, $city";
    return addr.isNotEmpty ? addr : city;
  }

  // ============================================================
  // Reverse geocoding (lat/lon -> readable address)
  // ============================================================
  Future<String> _reverseGeocode(latlng.LatLng p) async {
    final uri = Uri.parse(
      "https://nominatim.openstreetmap.org/reverse"
      "?format=jsonv2"
      "&lat=${p.latitude}"
      "&lon=${p.longitude}"
      "&zoom=18"
      "&addressdetails=1",
    );

    final res = await http.get(
      uri,
      headers: {
        "User-Agent": "teryagapptry/1.0 (patient-location)",
        "Accept": "application/json",
      },
    );

    if (res.statusCode != 200) {
      throw Exception("Reverse geocode failed (${res.statusCode})");
    }

    final jsonBody = json.decode(res.body) as Map<String, dynamic>;
    final displayName = (jsonBody["display_name"] ?? "").toString();
    return displayName;
  }

  Future<void> _updatePinAddressFromMapCenter() async {
    try {
      setState(() => _isPinAddressLoading = true);

      final addr = await _reverseGeocode(_mapCenter);

      if (!mounted) return;
      setState(() => _pinAddress = addr);
    } catch (_) {
      if (!mounted) return;
      setState(() => _pinAddress = "");
    } finally {
      if (!mounted) return;
      setState(() => _isPinAddressLoading = false);
    }
  }

  // ============================================================
  // LOCAL STORAGE (B1)
  // ============================================================
  static String _localKey(String nationalId) =>
      "patient_saved_addresses_v1_$nationalId";

  Future<List<Map<String, dynamic>>> _loadLocalAddresses() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_localKey(_nationalId));
    if (raw == null || raw.trim().isEmpty) return [];

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      return decoded
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> _saveLocalAddresses(List<Map<String, dynamic>> items) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_localKey(_nationalId), jsonEncode(items));
  }

  Future<void> _refreshSavedAddresses() async {
    final items = await _loadLocalAddresses();

    // Default first, then most recently updated
    items.sort((a, b) {
      final ad = a["is_default"] == true ? 0 : 1;
      final bd = b["is_default"] == true ? 0 : 1;
      if (ad != bd) return ad.compareTo(bd);
      return (b["updated_at"] ?? "").toString().compareTo(
        (a["updated_at"] ?? "").toString(),
      );
    });

    if (!mounted) return;
    setState(() => _savedAddresses = items);
  }

  Future<void> _addOrUpdateLocalAddress({
    required String label,
    required String address,
    required double lat,
    required double lon,
    bool setAsDefault = false,
  }) async {
    final now = DateTime.now().toIso8601String();
    final all = await _loadLocalAddresses();

    // Fix: do NOT force "Home" always.
    // If label empty -> first saved becomes "Home", otherwise "Saved".
    String fixedLabel = label.trim();
    if (fixedLabel.isEmpty) {
      fixedLabel = all.isEmpty ? "Home" : "Saved";
    }

    if (setAsDefault) {
      for (final a in all) {
        a["is_default"] = false;
      }
    }

    final idx = all.indexWhere((a) {
      final sameAddr = (a["address"] ?? "").toString().trim() == address.trim();
      final aLat = _toDouble(a["lat"]);
      final aLon = _toDouble(a["lon"]);
      final sameLat = aLat != null && aLat == lat;
      final sameLon = aLon != null && aLon == lon;
      return sameAddr && sameLat && sameLon;
    });

    if (idx >= 0) {
      all[idx]["label"] = fixedLabel;
      all[idx]["address"] = address;
      all[idx]["lat"] = lat;
      all[idx]["lon"] = lon;
      all[idx]["updated_at"] = now;
      if (setAsDefault) all[idx]["is_default"] = true;
    } else {
      final item = <String, dynamic>{
        "id": DateTime.now().millisecondsSinceEpoch.toString(),
        "label": fixedLabel,
        "address": address,
        "lat": lat,
        "lon": lon,
        "is_default": setAsDefault || all.isEmpty,
        "updated_at": now,
      };

      if (item["is_default"] == true) {
        for (final a in all) {
          a["is_default"] = false;
        }
      }

      all.insert(0, item);
    }

    // keep max 10
    if (all.length > 10) all.removeRange(10, all.length);

    await _saveLocalAddresses(all);
  }

  Future<void> _setDefaultLocal(String id) async {
    final all = await _loadLocalAddresses();
    for (final a in all) {
      a["is_default"] = (a["id"]?.toString() == id);
    }
    await _saveLocalAddresses(all);
  }

  // ============================================================
  // Load address + coordinates from backend, then load local list
  // ============================================================
  Future<void> _loadInitialAddressFromBackend() async {
    try {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });

      final data = await PatientService.fetchCurrentPatient();

      if (data != null) {
        _nationalId = (data["national_id"] ?? data["nationalId"] ?? "unknown")
            .toString();

        final rawLat = data["lat"] ?? data["home_lat"] ?? data["latitude"];
        final rawLon = data["lon"] ?? data["home_lon"] ?? data["longitude"];

        final homeLat = _toDouble(rawLat);
        final homeLon = _toDouble(rawLon);

        final full = _fullAddressFromBackend(data);

        setState(() {
          if (full.isNotEmpty) {
            _currentAddress = full;
            _pinAddress = full;
          }

          if (homeLat != null && homeLon != null) {
            _mapCenter = latlng.LatLng(homeLat, homeLon);
          }
        });

        if (_mapReady) {
          _mapController.move(_mapCenter, _currentZoom);
        }

        // Seed local store with backend "current home" (once) if it exists and no local addresses yet
        await _refreshSavedAddresses();
        if (_savedAddresses.isEmpty &&
            full.isNotEmpty &&
            homeLat != null &&
            homeLon != null) {
          await _addOrUpdateLocalAddress(
            label: "Home",
            address: full,
            lat: homeLat,
            lon: homeLon,
            setAsDefault: true,
          );
          await _refreshSavedAddresses();
        }

        // If backend had coords but no address text, reverse geocode once
        if (_pinAddress.isEmpty && homeLat != null && homeLon != null) {
          await _updatePinAddressFromMapCenter();
        }
      }
    } catch (e) {
      setState(() => _errorMessage = e.toString());
    } finally {
      setState(() => _isLoading = false);
    }
  }

  // ============================================================
  // Save updated address + lat + lon to backend + LOCAL
  // ============================================================
  Future<void> _saveLocationToBackend() async {
    try {
      await PatientService.updatePatientAddress(
        address: _currentAddress,
        lat: _mapCenter.latitude,
        lon: _mapCenter.longitude,
      );

      // Save locally as well (B1)
      await _addOrUpdateLocalAddress(
        label: _nameCtrl.text.trim(),
        address: _currentAddress,
        lat: _mapCenter.latitude,
        lon: _mapCenter.longitude,
        setAsDefault: true, // last saved becomes default/home for profile
      );
      await _refreshSavedAddresses();

      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("address_saved".tr())));

      // Return `true` so PatientProfile refreshes immediately
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  // ============================================================
  // MAP – supports tap to move pin + reverse geocode
  // ============================================================
  Widget _buildMap() {
    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: _mapCenter,
        initialZoom: _currentZoom,
        onMapReady: () {
          _mapReady = true;
          _mapController.move(_mapCenter, _currentZoom);
        },

        // Move pin when user taps
        onTap: (tapPosition, point) async {
          final now = DateTime.now();
          if (now.difference(_lastTap).inMilliseconds < 300) return;
          _lastTap = now;

          setState(() {
            _mapCenter = latlng.LatLng(point.latitude, point.longitude);
            _pinAddress = "";
          });

          await _updatePinAddressFromMapCenter();
        },

        onPositionChanged: (p, _) {
          _currentZoom = p.zoom ?? _currentZoom;
        },
      ),
      children: [
        TileLayer(
          urlTemplate:
              MapConfig.tilesTemplate, // keep your UI + config unchanged
          userAgentPackageName: "com.example.teryagapptry",
        ),
        MarkerLayer(
          markers: [
            Marker(
              width: 40.w,
              height: 40.h,
              point: _mapCenter,
              child: Icon(
                Icons.location_pin,
                size: 40.sp,
                color: AppColors.buttonRed,
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ============================================================
  // BOTTOM SHEET WRAPPER
  // ============================================================
  Widget _buildBottomSheet() {
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: Container(
        height: MediaQuery.of(context).size.height * 0.42,
        decoration: BoxDecoration(
          color: AppColors.cardBackground,
          borderRadius: BorderRadius.vertical(top: Radius.circular(32.r)),
          boxShadow: AppColors.universalShadow,
        ),
        padding: EdgeInsets.fromLTRB(20.w, 20.h, 20.w, 60.h),
        child: SingleChildScrollView(child: _buildSheetContent()),
      ),
    );
  }

  Widget _buildSheetContent() {
    switch (_currentSheet) {
      case "saved":
        return _savedAddressContent();
      case "add":
        return _addAddressContent();
      default:
        return _chooseContent();
    }
  }

  // ============================================================
  // 1) DEFAULT – Change or Save Location
  // ============================================================
  Widget _chooseContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.location_on_outlined, color: AppColors.bodyText),
            SizedBox(width: 6.w),
            Text(
              "map_change".tr(),
              style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w600),
            ),
          ],
        ),
        SizedBox(height: 14.h),

        // Pin address preview
        Container(
          width: double.infinity,
          padding: EdgeInsets.all(12.w),
          decoration: BoxDecoration(
            color: AppColors.cardBackground,
            borderRadius: BorderRadius.circular(12.r),
            border: Border.all(color: AppColors.grayDisabled),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.place_outlined,
                color: AppColors.bodyText,
                size: 20.sp,
              ),
              SizedBox(width: 10.w),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Selected Location",
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13.5.sp,
                        color: AppColors.bodyText,
                      ),
                    ),
                    SizedBox(height: 6.h),
                    if (_isPinAddressLoading)
                      Text(
                        "Loading address...",
                        style: TextStyle(
                          fontSize: 12.5.sp,
                          color: AppColors.detailText,
                        ),
                      )
                    else
                      Text(
                        _pinAddress.isNotEmpty
                            ? _pinAddress
                            : "Tap on the map to pick a location",
                        style: TextStyle(
                          fontSize: 12.5.sp,
                          color: AppColors.detailText,
                        ),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),

        SizedBox(height: 16.h),

        // Save new pin position to backend (opens add sheet)
        Center(
          child: SizedBox(
            width: 300.w,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.buttonBlue,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(25),
                ),
                padding: EdgeInsets.symmetric(vertical: 14.h),
              ),
              onPressed: () {
                // Prefill current address with reverse-geocode value if present
                if (_pinAddress.isNotEmpty) {
                  _currentAddress = _pinAddress;
                }
                _addrCtrl.text = _currentAddress.isNotEmpty
                    ? _currentAddress
                    : _pinAddress;

                // Suggest label:
                // - if no saved addresses yet => Home
                // - else empty (user can type Work, etc.)
                _nameCtrl.text = _savedAddresses.isEmpty ? "Home" : "";

                setState(() => _currentSheet = "add");
              },
              child: Text(
                "save_location".tr(),
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ),

        SizedBox(height: 12.h),

        // IMPORTANT: show this ONLY if there are saved addresses
        if (_savedAddresses.isNotEmpty)
          Center(
            child: SizedBox(
              width: 300.w,
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: AppColors.buttonRed),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(25),
                  ),
                  padding: EdgeInsets.symmetric(vertical: 14.h),
                ),
                onPressed: () => setState(() => _currentSheet = "saved"),
                child: Text(
                  "saved_addresses".tr(),
                  style: const TextStyle(
                    color: AppColors.buttonRed,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  // ============================================================
  // 2) ADD ADDRESS CONTENT – user edits name + address + save
  // ============================================================
  Widget _addAddressContent() {
    // Keep existing UI layout, just use persistent controllers
    if (_addrCtrl.text.trim().isEmpty) {
      _addrCtrl.text = _currentAddress.isNotEmpty
          ? _currentAddress
          : _pinAddress;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          "add_new_address".tr(),
          style: TextStyle(
            fontSize: 17.sp,
            fontWeight: FontWeight.w800,
            color: AppColors.bodyText,
          ),
        ),
        SizedBox(height: 10.h),

        // Editable full address (prefilled)
        _inputField("Full Address", _addrCtrl),
        SizedBox(height: 10.h),

        // Optional label (Home / Work ...)
        _inputField("address_placeholder".tr(), _nameCtrl),
        SizedBox(height: 14.h),

        Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            // Cancel
            _outlineBtn("cancel".tr(), AppColors.buttonRed, () {
              setState(() => _currentSheet = "choose");
            }),

            // Save
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.buttonBlue,
                padding: EdgeInsets.symmetric(vertical: 12.h, horizontal: 35.w),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(25),
                ),
              ),
              onPressed: () async {
                if (_addrCtrl.text.trim().isEmpty) return;

                setState(() {
                  _currentAddress = _addrCtrl.text.trim();
                });

                await _saveLocationToBackend();
              },
              child: Text(
                "save".tr(),
                style: const TextStyle(color: Colors.white),
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ============================================================
  // 3) SAVED ADDRESSES (LOCAL)
  // Tap a card to use it (moves map, sets default, returns to choose)
  // ============================================================
  Widget _savedAddressContent() {
    return Column(
      children: [
        for (final a in _savedAddresses)
          _addressCard(
            (a["label"] ?? "").toString(),
            (a["address"] ?? "").toString(),
            onTap: () async {
              final lat = _toDouble(a["lat"]);
              final lon = _toDouble(a["lon"]);
              final id = (a["id"] ?? "").toString();

              if (lat != null && lon != null) {
                setState(() {
                  _mapCenter = latlng.LatLng(lat, lon);
                  _pinAddress = (a["address"] ?? "").toString();
                  _currentAddress = (a["address"] ?? "").toString();
                  _currentSheet = "choose";
                });
                if (_mapReady) {
                  _mapController.move(_mapCenter, _currentZoom);
                }
              } else {
                setState(() {
                  _pinAddress = (a["address"] ?? "").toString();
                  _currentAddress = (a["address"] ?? "").toString();
                  _currentSheet = "choose";
                });
              }

              if (id.isNotEmpty) {
                await _setDefaultLocal(id);
                await _refreshSavedAddresses();
              }
            },
          ),
        SizedBox(height: 20.h),
        _outlineBtn(
          "back".tr(),
          AppColors.buttonRed,
          () => setState(() => _currentSheet = "choose"),
        ),
      ],
    );
  }

  // UI Helpers
  Widget _outlineBtn(String text, Color color, VoidCallback onTap) {
    return OutlinedButton(
      style: OutlinedButton.styleFrom(
        side: BorderSide(color: color, width: 1.5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
      ),
      onPressed: onTap,
      child: Text(
        text,
        style: TextStyle(color: color, fontWeight: FontWeight.w600),
      ),
    );
  }

  Widget _inputField(String hint, TextEditingController ctrl) {
    return TextField(
      controller: ctrl,
      decoration: InputDecoration(
        hintText: hint,
        filled: true,
        fillColor: AppColors.cardBackground,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.grayDisabled),
        ),
      ),
    );
  }

  Widget _addressCard(String title, String addr, {VoidCallback? onTap}) {
    return InkWell(
      onTap: onTap, // does not change UI visuals
      child: Container(
        margin: EdgeInsets.only(bottom: 12.h),
        padding: EdgeInsets.all(14.h),
        decoration: BoxDecoration(
          color: AppColors.cardBackground,
          borderRadius: BorderRadius.circular(12.r),
          border: Border.all(color: AppColors.grayDisabled),
        ),
        child: Row(
          children: [
            Icon(
              Icons.location_on_outlined,
              color: AppColors.bodyText,
              size: 22.sp,
            ),
            SizedBox(width: 10.w),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title.isNotEmpty ? title : "Saved",
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14.5.sp,
                    ),
                  ),
                  SizedBox(height: 4.h),
                  Text(
                    addr,
                    style: TextStyle(
                      fontSize: 13.sp,
                      color: AppColors.bodyText,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // MAIN BUILD
  // ============================================================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF149E9E),
      appBar: PreferredSize(
        preferredSize: Size.fromHeight(90.h),
        child: CustomTopBar(
          title: "address".tr(),
          showBackButton: true,
          onBackTap: () => Navigator.pop(context, false),
        ),
      ),
      body: Stack(
        children: [
          Positioned.fill(child: _buildMap()),
          _buildBottomSheet(),
          if (_isLoading) const Center(child: CircularProgressIndicator()),
          if (_errorMessage != null && !_isLoading)
            Positioned(
              bottom: 20.h,
              left: 20.w,
              right: 20.w,
              child: Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.alertRed),
              ),
            ),
        ],
      ),
    );
  }
}
