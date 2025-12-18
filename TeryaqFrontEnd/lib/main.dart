// lib/main.dart
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:easy_localization/easy_localization.dart';

// ✅ Intl (for localized date formatting)
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';

// Firebase
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';

// Screens
import 'features/authentication/splash_screen.dart';
import 'features/patient/patient_screens/patient_home.dart';
import 'features/driver/driver_home.dart';
import 'features/hospital/hospital_home.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 🌍 Easy Localization
  await EasyLocalization.ensureInitialized();

  // ✅ Important: initialize date formatting symbols for both locales
  // This fixes months/AM-PM not switching correctly when changing language.
  await initializeDateFormatting('en', null);
  await initializeDateFormatting('ar', null);

  // 🔥 Firebase init (FirebaseAuth, Firestore, ...)
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  runApp(
    EasyLocalization(
      supportedLocales: const [
        Locale('en'),
        Locale('ar'),
      ],
      path: 'lib/l10n', // مسار ملفات الترجمة (en.json & ar.json)
      fallbackLocale: const Locale('en'),
      child: const TeryaqApp(),
    ),
  );
}

class TeryaqApp extends StatelessWidget {
  const TeryaqApp({super.key});

  @override
  Widget build(BuildContext context) {
    // ✅ Make Intl follow the app locale (critical for DateFormat)
    Intl.defaultLocale = context.locale.toLanguageTag(); // "en" / "ar"

    return ScreenUtilInit(
      designSize: const Size(390, 844),
      minTextAdapt: true,
      splitScreenMode: true,

      // 👇 أول صفحة
      child: const SplashScreen(),

      builder: (_, child) {
        return MaterialApp(
          title: 'Teryaq',
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            fontFamily: 'Poppins',
            scaffoldBackgroundColor: const Color(0xFFFCFFFF),
          ),

          // 🌍 Localization
          locale: context.locale,
          supportedLocales: context.supportedLocales,
          localizationsDelegates: context.localizationDelegates,

          // 📌 Named Routes
          routes: {
            '/patientHome': (context) => const PatientHome(),
            '/driverHome': (context) => const DriverHome(),
            '/hospitalHome': (context) => const HospitalHome(),
          },

          home: child,
        );
      },
    );
  }
}
