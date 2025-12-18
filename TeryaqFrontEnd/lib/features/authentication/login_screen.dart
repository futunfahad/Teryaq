// lib/features/authentication/login_screen.dart

import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'package:teryagapptry/services/driver_service.dart';
import 'package:teryagapptry/services/hospital_service.dart';
import 'package:teryagapptry/services/patient_service.dart';

import '../patient/patient_screens/patient_home.dart';
import '../hospital/hospital_home.dart';
import '../driver/driver_home.dart';

const String hospitalApiBaseUrl = "http://192.168.8.113:8000";

class LoginScreen extends StatefulWidget {
  /// IMPORTANT: role must be internal stable value:
  /// "patient" | "driver" | "hospital"
  final String role;

  const LoginScreen({super.key, required this.role});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController idController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();

  bool isLoading = false;

  @override
  void dispose() {
    idController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  // ============================
  // Toast helper
  // ============================
  void _showErrorToastKey(String key) {
    Fluttertoast.showToast(
      msg: tr(key),
      backgroundColor: Colors.red,
      textColor: Colors.white,
    );
  }

  // ============================
  // UI role label (localized)
  // ============================
  String _roleLabel() {
    final r = widget.role.trim().toLowerCase();
    if (r == "patient") return tr("patient_rule");
    if (r == "driver") return tr("driver_rule");
    if (r == "hospital") return tr("hospital_rule");
    return r; // fallback
  }

  // ============================
  // Login handler
  // ============================
  Future<void> _handleLogin() async {
    final nationalId = idController.text.trim();
    final password = passwordController.text.trim();
    final role = widget.role.trim().toLowerCase();

    // ---------- Validation ----------
    if (nationalId.isEmpty || password.isEmpty) {
      _showErrorToastKey("error_enter_all_fields");
      return;
    }

    if (nationalId.length != 10) {
      _showErrorToastKey("error_national_id_exact");
      return;
    }

    if (!RegExp(r'^\d+$').hasMatch(nationalId)) {
      _showErrorToastKey("error_national_id_digits");
      return;
    }

    setState(() => isLoading = true);

    try {
      // ============================
      // PATIENT (Firebase + SharedPrefs via PatientService)
      // ============================
      if (role == "patient") {
        await PatientService.loginPatient(
          nationalId: nationalId,
          password: password,
        );

        if (!mounted) return;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const PatientHome()),
        );
        return;
      }

      // ============================
      // DRIVER
      // ============================
      if (role == "driver") {
        await DriverService.loginDriver(
          nationalId: nationalId,
          password: password,
        );

        await DriverService.getDriverProfile();

        if (!mounted) return;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const DriverHome()),
        );
        return;
      }

      // ============================
      // HOSPITAL
      // ============================
      if (role == "hospital") {
        await HospitalService.loginHospital(
          nationalId: nationalId,
          password: password,
        );

        final hospitalApi = HospitalService(baseUrl: hospitalApiBaseUrl);
        await hospitalApi.fetchHospitalIdByNationalId(nationalId);

        if (!mounted) return;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const HospitalHome()),
        );
        return;
      }

      // Unknown role
      _showErrorToastKey("error_login_failed");
    } on FirebaseAuthException catch (e) {
      if (e.code == "invalid-credential" ||
          e.code == "wrong-password" ||
          e.code == "user-not-found") {
        _showErrorToastKey("error_invalid_credentials");
      } else {
        _showErrorToastKey("error_login_failed");
      }
    } catch (_) {
      _showErrorToastKey("error_login_failed");
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  // ============================
  // UI
  // ============================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFCFFFF),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Color(0xFF3D7180)),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.only(bottom: 24),
          child: Column(
            children: [
              const SizedBox(height: 16),
              Center(child: Image.asset("assets/tglogo.png", height: 80)),
              const SizedBox(height: 24),

              Text(
                "${tr("login_as")} ${_roleLabel()}",
                style: const TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF1E637A),
                ),
              ),

              const SizedBox(height: 24),

              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x1C0E5D7C),
                        blurRadius: 11,
                        offset: Offset(0, 4),
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      TextField(
                        enabled: !isLoading,
                        controller: idController,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          prefixIcon: const Icon(
                            Icons.person,
                            color: Color(0xFF7EAEBE),
                          ),
                          hintText: tr("national_id"),
                          filled: true,
                          fillColor: const Color(0xFFD2EAEC),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),

                      const SizedBox(height: 16),

                      TextField(
                        enabled: !isLoading,
                        controller: passwordController,
                        obscureText: true,
                        decoration: InputDecoration(
                          prefixIcon: const Icon(
                            Icons.lock,
                            color: Color(0xFF7EAEBE),
                          ),
                          hintText: tr("password"),
                          filled: true,
                          fillColor: const Color(0xFFD2EAEC),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),

                      const SizedBox(height: 40),

                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: ElevatedButton(
                          onPressed: isLoading ? null : _handleLogin,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: isLoading
                                ? Colors.grey.shade400
                                : const Color(0xFF4F869D),
                            disabledBackgroundColor: Colors.grey.shade400,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: isLoading
                              ? const SizedBox(
                                  height: 22,
                                  width: 22,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.5,
                                    color: Colors.white,
                                  ),
                                )
                              : Text(
                                  tr("login_button"),
                                  style: const TextStyle(
                                    fontFamily: 'Poppins',
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.white,
                                  ),
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 40),

              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Image.asset('assets/Securityicon.png', height: 22),
                  const SizedBox(width: 8),
                  Text(
                    tr("secure_login"),
                    style: const TextStyle(
                      fontFamily: 'Poppins',
                      color: Color(0xFF227691),
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
