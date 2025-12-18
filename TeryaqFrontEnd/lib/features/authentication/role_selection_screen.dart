// lib/features/authentication/role_selection_screen.dart

import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';

import 'login_screen.dart';

// Durrah Modify the colors
const _bg        = Color(0xFFFCFFFF);
const _cardIcon  = Color(0xFF50869D);
const _title     = Color(0xFF1E637A);
const _subtitle  = Color(0xFF237691);
const _cardFill  = Colors.white;

class RoleSelectionScreen extends StatelessWidget {
  const RoleSelectionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 40),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 8),

              // Logo
              Center(
                child: Image.asset(
                  'assets/tglogo.png',
                  height: 80,
                ),
              ),
              const SizedBox(height: 24),

              // Title (localized)
              Text(
                "continue_as".tr(),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontFamily: 'Poppins',
                  color: Color(0xFF1E637A),
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 43),

              // ============================
              // Patient (UI localized, role internal ثابت)
              // ============================
              _RoleCard(
                icon: Icons.person,
                title: "patient_rule".tr(),
                subtitle: "patient_des".tr(),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const LoginScreen(role: "patient"),
                  ),
                ),
              ),
              const SizedBox(height: 18),

              // ============================
              // Hospital
              // ============================
              _RoleCard(
                icon: Icons.local_hospital,
                title: "hospital_rule".tr(),
                subtitle: "hospital_des".tr(),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const LoginScreen(role: "hospital"),
                  ),
                ),
              ),
              const SizedBox(height: 18),

              // ============================
              // Driver
              // ============================
              _RoleCard(
                icon: Icons.local_shipping,
                title: "driver_rule".tr(),
                subtitle: "driver_des".tr(),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const LoginScreen(role: "driver"),
                  ),
                ),
              ),

              const Spacer(),

              // Nafath (localized)
              Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Image.asset('assets/Securityicon.png', height: 22),
                    const SizedBox(width: 8),
                    Text(
                      "authenticate_nafath_text".tr(),
                      style: const TextStyle(
                        fontFamily: 'Poppins',
                        color: Color(0xFF227691),
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}

class _RoleCard extends StatelessWidget {
  const _RoleCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: _cardFill,
          borderRadius: BorderRadius.circular(12),
          boxShadow: const [
            BoxShadow(
              color: Color(0x1C0E5D7C),
              blurRadius: 11,
              spreadRadius: 1,
              offset: Offset(0, 4),
            ),
          ],
        ),
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            Icon(icon, size: 63, color: const Color(0xFF50869D)),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontFamily: 'Poppins',
                      color: _title,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontFamily: 'Poppins',
                      color: _subtitle,
                      fontSize: 14,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios, size: 15, color: _cardIcon),
          ],
        ),
      ),
    );
  }
}
