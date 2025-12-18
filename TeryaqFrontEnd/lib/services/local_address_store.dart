import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class LocalAddressStore {
  static const String _kPrefix = "patient_saved_addresses_v1_";
  static String _keyFor(String nationalId) => "$_kPrefix$nationalId";

  static Future<List<Map<String, dynamic>>> getAll(String nationalId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_keyFor(nationalId));
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

  static Future<void> _saveAll(
    String nationalId,
    List<Map<String, dynamic>> items,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyFor(nationalId), jsonEncode(items));
  }

  static Future<Map<String, dynamic>?> getDefaultOrLast(
    String nationalId,
  ) async {
    final all = await getAll(nationalId);
    if (all.isEmpty) return null;

    final def = all.where((a) => a["is_default"] == true).toList();
    if (def.isNotEmpty) return def.first;

    all.sort(
      (a, b) => (b["updated_at"] ?? "").toString().compareTo(
        (a["updated_at"] ?? "").toString(),
      ),
    );
    return all.first;
  }

  static Future<void> addOrUpdate(
    String nationalId, {
    required String label,
    required String address,
    double? lat,
    double? lon,
    bool setAsDefault = false,
  }) async {
    final now = DateTime.now().toIso8601String();
    final all = await getAll(nationalId);

    // IMPORTANT: do NOT force "Home" always
    // If user didn't type a label:
    // - first saved => Home
    // - others => Saved
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
      final aLat = a["lat"];
      final aLon = a["lon"];
      final sameLat =
          (aLat == null && lat == null) ||
          (aLat is num && lat != null && aLat.toDouble() == lat);
      final sameLon =
          (aLon == null && lon == null) ||
          (aLon is num && lon != null && aLon.toDouble() == lon);
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
        "is_default":
            setAsDefault || all.isEmpty, // first entry becomes default
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

    await _saveAll(nationalId, all);
  }

  static Future<void> setDefault(String nationalId, String id) async {
    final all = await getAll(nationalId);
    for (final a in all) {
      a["is_default"] = (a["id"]?.toString() == id);
    }
    await _saveAll(nationalId, all);
  }

  static Future<void> remove(String nationalId, String id) async {
    final all = await getAll(nationalId);
    all.removeWhere((a) => a["id"]?.toString() == id);

    if (all.isNotEmpty && all.every((a) => a["is_default"] != true)) {
      all.first["is_default"] = true;
    }

    await _saveAll(nationalId, all);
  }
}
