// lib/widgets/report_issue_dialog.dart

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:easy_localization/easy_localization.dart';

/// Simple reusable dialog to report an issue.
/// Usage:
///   final reason = await showReportIssueDialog(context);
///   if (reason != null) { ... }
Future<String?> showReportIssueDialog(BuildContext context) async {
  final TextEditingController controller = TextEditingController();

  return showDialog<String>(
    context: context,
    builder: (dialogContext) {
      return Dialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16.r),
        ),
        child: Container(
          width: 300.w,
          height: 260.h,
          padding: EdgeInsets.all(16.w),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 🔹 Title (centered)
              Center(
                child: Text(
                  'report_issue_title'.tr(), // e.g. "Report an Issue"
                  style: TextStyle(
                    fontSize: 14.sp,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),

              SizedBox(height: 10.h),

              // 🔹 Input area
              Container(
                width: double.infinity,
                height: 120.h,
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade300),
                  borderRadius: BorderRadius.circular(10.r),
                ),
                child: TextField(
                  controller: controller,
                  maxLines: null,
                  decoration: InputDecoration(
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 8.w,
                      vertical: 4.h,
                    ),
                    border: InputBorder.none,
                    hintText: 'report_issue_hint'.tr(),
                    hintStyle: TextStyle(
                      color: Colors.grey.shade300,
                      fontSize: 12.sp,
                    ),
                  ),
                ),
              ),

              SizedBox(height: 10.h),

              // 🔹 Cancel / Submit
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  // ❌ Cancel
                  OutlinedButton(
                    onPressed: () => Navigator.of(dialogContext).pop(null),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Colors.grey),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20.r),
                      ),
                      padding: EdgeInsets.symmetric(
                        horizontal: 20.w,
                        vertical: 8.h,
                      ),
                    ),
                    child: Text(
                      'cancel'.tr(),
                      style: const TextStyle(color: Colors.grey),
                    ),
                  ),

                  // ✅ Submit
                  OutlinedButton(
                    onPressed: () {
                      final message = controller.text.trim();
                      if (message.isEmpty) {
                        // لو حابة، ممكن نرجعه null عشان ما يرسل شي فاضي
                        Navigator.of(dialogContext).pop(null);
                      } else {
                        Navigator.of(dialogContext).pop(message);
                      }
                    },
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Color(0xFFE7525D)),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20.r),
                      ),
                      padding: EdgeInsets.symmetric(
                        horizontal: 20.w,
                        vertical: 8.h,
                      ),
                    ),
                    child: Text(
                      'submit'.tr(),
                      style: const TextStyle(color: Color(0xFFE7525D)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    },
  );
}
