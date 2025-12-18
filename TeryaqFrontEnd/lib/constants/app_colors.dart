import 'package:flutter/material.dart';

/// 🎨 Teryaq App Color Palette
/// A captivating, intricate mosaic of colors that orchestrates the UI.

class AppColors {
  // ============================
  // TEXT
  // ============================
  static const Color headingText = Color(0xFF013A3C);
  static const Color bodyText = Color(0xFF11607E);
  static const Color detailText = Color(0xFF525252);

  // ============================
  // ACTION / INTERACTION
  //============================
  static const Color buttonBlue = Color(0xFF4F869D);
  static const Color cardBlue = Color(0xFF478FA7);
  static const Color cardBlueLight = Color(0xFFB5DBF8);
  static const Color buttonRed = Color(0xFFE7525D);
  static const Color alertRed = Color(0xFFE45E6C);
  static const Color bigIcons = Color(0xffD2E4E8);

  // ============================
  // STATUS
  // ============================
  static const Color statusDelivered = Color(0xFF137713);
  static const Color statusDeliveredLight = Color(0xFFDEEAE2);

  static const Color statusPending = Color(0xFFC9A100);
  static const Color statusPendingLight = Color(0xFFF7EEC9);

  static const Color statusRejected = Color(0xFFCC0000);
  static const Color statusRejectedLight = Color(0xFFF8B8B8);

  static const Color statusOnDelivery = Color(0xFF004A8B);
  static const Color statusOnDeliveryLight = Color(0xFFBCDBF7);

  static const Color statusAccepted = Color(0xFF3657D6);
  static const Color statusAcceptedLight = Color(0xFFC8D0ED);

  static const Color statusFailed = Color(0xFFFFA500);
  static const Color statusFailedLight = Color(0xFFF7E2BC);

  // ============================
  // SURFACES
  // ============================
  static const Color appBackground = Color(0xFFFCFFFF);
  static const Color cardBackground = Color(0xFFFFFFFF);
  static const Color appHeader = Color(0xFFD5F7FF);

  // ============================
  // NEUTRALS
  // ============================
  static const Color grayDisabled = Color(0xFF8D8D8D);
  static const Color borderGray = Color(0xFFB0B0B0);
  static const Color backgroundGrey = Color(0xFFEAF5F8);

  static const Color Chevronicon = Color(0xFF201F29);
  static const Color softBlue = Color(0xFF8FB8C7);

  // ============================
  // NOTIFICATION
  // ============================
  static const Color notificationGreen = Color(0xFF0D862D);
  static const Color notificationGreenLight = Color(0xFFC7DFCD);

  static const Color notificationYellow = Color(0xFFFFCC00);
  // notificationYellowLight & notificationRedLight left intentionally blank

  // ============================
  // SHADOW
  // ============================
  static final List<BoxShadow> universalShadow = [
    BoxShadow(
      color:  Color(0xFF0E5D7C).withOpacity(0.11),
      blurRadius: 11,
      spreadRadius: 1,
      offset: Offset(0, 4),
    ),
  ];
}
