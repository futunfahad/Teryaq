import 'package:flutter/material.dart';
import 'role_selection_screen.dart';

class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // صورة الخلفية
          Positioned.fill(
            child: Image.asset(
              'assets/firstpage.png',
              fit: BoxFit.cover,
            ),
          ),

          // زر دائري بالأسفل (مو بالوسط)
          Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 300), // نزل الزر من تحت (تقدر تغير الرقم)
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  shape: const CircleBorder(),
                  padding: const EdgeInsets.all(20),
                  backgroundColor: const Color(0xFF94C3CC),
                ),
                onPressed: () {
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const RoleSelectionScreen(),
                    ),
                  );
                },
                child: const Icon(Icons.arrow_forward, color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
