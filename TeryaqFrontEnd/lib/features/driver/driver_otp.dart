import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/services.dart';

import '../../constants/app_colors.dart';
import 'driver_success.dart';
import 'package:teryagapptry/services/driver_service.dart';

class OTP extends StatefulWidget {
  final String orderId;

  const OTP({super.key, required this.orderId});

  @override
  State<OTP> createState() => _OTPState();
}

class _OTPState extends State<OTP> {
  final TextEditingController _otp1 = TextEditingController();
  final TextEditingController _otp2 = TextEditingController();
  final TextEditingController _otp3 = TextEditingController();
  final TextEditingController _otp4 = TextEditingController();

  bool showError = false;
  bool isLoading = false;

  @override
  void dispose() {
    _otp1.dispose();
    _otp2.dispose();
    _otp3.dispose();
    _otp4.dispose();
    super.dispose();
  }

  Future<void> _verifyOtp() async {
    final otp = (_otp1.text + _otp2.text + _otp3.text + _otp4.text).trim();

    if (otp.length != 4) {
      setState(() {
        showError = true;
        _otp1.clear();
        _otp2.clear();
        _otp3.clear();
        _otp4.clear();
      });
      return;
    }

    setState(() {
      isLoading = true;
      showError = false;
    });

    try {
      final resp = await DriverService.verifyOtp(widget.orderId, otp);
      final bool verified = resp["verified"] == true;

      if (!verified) {
        setState(() {
          showError = true;
          _otp1.clear();
          _otp2.clear();
          _otp3.clear();
          _otp4.clear();
        });
        return;
      }

      await DriverService.markOrderDelivered(widget.orderId);

      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const DriverSuccess()),
      );
    } catch (e) {
      debugPrint("OTP verify/mark-delivered error: $e");
      setState(() {
        showError = true;
        _otp1.clear();
        _otp2.clear();
        _otp3.clear();
        _otp4.clear();
      });
    } finally {
      if (mounted) {
        setState(() {
          isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 24.w),
          child: Column(
            children: [
              const Spacer(),

              Column(
                children: [
                  SvgPicture.asset(
                    'assets/icons/otp.svg',
                    height: 143.h,
                    width: 128.w,
                  ),
                  SizedBox(height: 24.h),
                  Text(
                    'otp_heading'.tr(),
                    style: TextStyle(
                      fontSize: 18.sp,
                      fontWeight: FontWeight.w500,
                      color: AppColors.bodyText,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  if (showError) ...[
                    SizedBox(height: 10.h),
                    Text(
                      'otp_error'.tr(),
                      style: TextStyle(
                        fontSize: 14.sp,
                        fontWeight: FontWeight.w500,
                        color: AppColors.alertRed,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                  SizedBox(height: 30.h),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _otpBox(_otp1),
                      _otpBox(_otp2),
                      _otpBox(_otp3),
                      _otpBox(_otp4),
                    ],
                  ),
                ],
              ),

              const Spacer(),

              Padding(
                padding: EdgeInsets.only(bottom: 36.h),
                child: SizedBox(
                  width: double.infinity,
                  height: 48.h,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.buttonRed,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12.r),
                      ),
                    ),
                    onPressed: isLoading ? null : _verifyOtp,
                    child: isLoading
                        ? const CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          )
                        : Text(
                            'otp_verify'.tr(),
                            style: TextStyle(
                              fontSize: 16.sp,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _otpBox(TextEditingController controller) {
    return SizedBox(
      width: 69.w,
      height: 69.h,
      child: TextField(
        controller: controller,
        keyboardType: TextInputType.number,
        textAlign: TextAlign.center,
        maxLength: 1,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        style: TextStyle(fontSize: 24.sp, fontWeight: FontWeight.bold),
        onChanged: (value) {
          if (value.length == 1) {
            FocusScope.of(context).nextFocus();
          }
        },
        decoration: InputDecoration(
          counterText: '',
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12.r),
            borderSide: const BorderSide(color: Color(0xFFD2D2D2)),
          ),
        ),
      ),
    );
  }
}
