/*import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

/// ✅ Reusable Bottom Sheet for the 3-lines menu in Teryaq App.
/// Call it anywhere using:
/// ```dart
/// onMenuTap: () => showTeryaqMenu(context),
/// ```
void showTeryaqMenu(BuildContext context) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: const Color(0x00000000),
    builder: (context) {
      return DraggableScrollableSheet(
        initialChildSize: 0.70,
        maxChildSize: 0.7,
        expand: false,
        builder: (context, scrollController) {
          return Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(
                top: Radius.circular(32.r),
              ),
            ),
            padding: EdgeInsets.symmetric(horizontal: 20.w, vertical: 4.h),
            child: ListView(
              controller: scrollController,
              children: [
                // 🔹 Drag handle
                Center(
                  child: Container(
                    width: 40.w,
                    height: 4.h,
                    margin: EdgeInsets.only(bottom: 20.h),
                    decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(2.r),
                    ),
                  ),
                ),

                // 🔹 Close button
                Align(
                  alignment: Alignment.topRight,
                  child: IconButton(
                    icon: const Icon(Icons.close, color: Color(0xFF11607E)),
                    onPressed: () => Navigator.pop(context),
                  ),
                ),

                // 🔹 Menu items
                const ListTile(
                  leading: Icon(Icons.favorite_border, color: Color(0xFF11607E)),
                  title: Text(
                    "About Teryaq",
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      color: Color(0xFF013A3C),
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                const ListTile(
                  leading: Icon(Icons.description_outlined, color: Color(0xFF11607E)),
                  title: Text(
                    "Terms and Conditions",
                    style: TextStyle(
                      color: Color(0xFF013A3C),
                      fontFamily: 'Poppins',
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                const ListTile(
                  leading: Icon(Icons.lock_outline, color: Color(0xFF11607E)),
                  title: Text(
                    "Privacy Policy",
                    style: TextStyle(
                      color: Color(0xFF013A3C),
                      fontFamily: 'Poppins',
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                const ListTile(
                  leading: Icon(Icons.headphones_outlined, color: Color(0xFF11607E)),
                  title: Text(
                    "Contact Us",
                    style: TextStyle(
                      color: Color(0xFF013A3C),
                      fontFamily: 'Poppins',
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),

                SizedBox(height: 170.h),

                // 🔹 Language option
                const Row(
                  mainAxisAlignment: MainAxisAlignment.start,
                  children: [
                    Icon(Icons.translate, color: Color(0xFFDD5B69)),
                    SizedBox(width: 8),
                    Text(
                      "Arabic",
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        color: Color(0xFFDD5B69),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      );
    },
  );
}*/



/* THE GOOD LAST ONE 
import 'package:easy_localization/easy_localization.dart';//for langauge changing
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

void showTeryaqMenu(BuildContext context) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: const Color(0x00000000),
    builder: (context) {
      return DraggableScrollableSheet(
        initialChildSize: 0.70,
        maxChildSize: 0.7,
        expand: false,
        builder: (context, scrollController) {
          return Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(
                top: Radius.circular(32.r),
              ),
            ),
            padding: EdgeInsets.symmetric(horizontal: 20.w, vertical: 4.h),
            child: ListView(
              controller: scrollController,
              children: [
                // 🔹 Drag handle
                Center(
                  child: Container(
                    width: 40.w,
                    height: 4.h,
                    margin: EdgeInsets.only(bottom: 20.h),
                    decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(2.r),
                    ),
                  ),
                ),

                // 🔹 Close button
                Align(
                  alignment: Alignment.topRight,
                  child: IconButton(
                    icon: const Icon(Icons.close, color: Color(0xFF11607E)),
                    onPressed: () => Navigator.pop(context),
                  ),
                ),

                // 🔹 Menu items
                ListTile(
                  leading: Icon(Icons.favorite_border, color: Color(0xFF11607E)),
                  title: Text(
                    "about".tr(),
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      color: Color(0xFF013A3C),
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                 ListTile(
                  leading: Icon(Icons.description_outlined, color: Color(0xFF11607E)),
                  title: Text(
                    "terms".tr(),
                    style: TextStyle(
                      color: Color(0xFF013A3C),
                      fontFamily: 'Poppins',
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                ListTile(
                  leading: Icon(Icons.lock_outline, color: Color(0xFF11607E)),
                  title: Text(
                    "privacy".tr(),
                    style: TextStyle(
                      color: Color(0xFF013A3C),
                      fontFamily: 'Poppins',
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                ListTile(
                  leading: Icon(Icons.headphones_outlined, color: Color(0xFF11607E)),
                  title: Text(
                    "contact".tr(),
                    style: TextStyle(
                      color: Color(0xFF013A3C),
                      fontFamily: 'Poppins',
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),

                SizedBox(height: 170.h),

                // 🔹 Language option (temporary test button)

                
GestureDetector(
  onTap: () {
    Navigator.pop(context); // ✅ closes the menu smoothly

    final isEnglish = context.locale.languageCode == 'en'; // ✅ check the current language
    context.setLocale(isEnglish ? const Locale('ar') : const Locale('en')); // ✅ switch language between English & Arabic

    // ✅ Show a floating message confirming the change
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'language_changed'.tr(), // ✅ translation key for snackbar text
          style: const TextStyle(
            fontFamily: 'Poppins',
            fontWeight: FontWeight.w500,
          ),
        ),
        backgroundColor: const Color(0xFF013A3C),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  },
  child: Row(
    mainAxisAlignment: MainAxisAlignment.start,
    children: [
      const Icon(Icons.translate, color: Color(0xFFDD5B69)),
      const SizedBox(width: 8),
      Text(
        "language_button".tr(), // ✅ translation key for the button label
        style: const TextStyle(
          fontFamily: 'Poppins',
          color: Color(0xFFDD5B69),
          fontWeight: FontWeight.w500,
        ),
      ),
    ],
  ),
),

              ],
            ),
          );
        },
      );
    },
  );
}*/





import 'package:easy_localization/easy_localization.dart'; //for langauge changing
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

void showTeryaqMenu(BuildContext context) {
  int? openIndex; // 🔹 tracks which menu item is open (only one allowed open)

  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: const Color(0x00000000),
    builder: (context) {
      return StatefulBuilder(
        builder: (context, setState) {
          return DraggableScrollableSheet(
            initialChildSize: 0.70,
            maxChildSize: 0.7,
            expand: false,
            builder: (context, scrollController) {
              return Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(
                    top: Radius.circular(32.r),
                  ),
                ),
                padding: EdgeInsets.only(left: 10.w, right: 1.w, top: 0.h, bottom: 4.h),
                child: ListView(
                  controller: scrollController,
                  children: [
                    // 🔹 Drag handle
                    Center(
                      child: Container(
                        width: 40.w,
                        height: 4.h,
                        margin: EdgeInsets.only(bottom: 0.h),
                        decoration: BoxDecoration(
                          color: Colors.grey[300],
                          borderRadius: BorderRadius.circular(2.r),
                        ),
                      ),
                    ),

                    // 🔹 Close button
                    Align(
                      alignment: Alignment.topRight,
                      child: IconButton(
                        icon: const Icon(Icons.close, color: Color(0xFF11607E)),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ),

                    // 🔹 Expandable Menu Items
                    _MenuExpandableItem(
                      index: 0,
                      openIndex: openIndex,
                      setOpen: (i) => setState(() => openIndex = i),
                      icon: Icons.favorite_border,
                      title: "about".tr(),
                      text: "About_text".tr(),
                    ),

                    _MenuExpandableItem(
                      index: 1,
                      openIndex: openIndex,
                      setOpen: (i) => setState(() => openIndex = i),
                      icon: Icons.description_outlined,
                      title: "terms".tr(),
                      text: "terms_text".tr(),
                    ),

                    _MenuExpandableItem(
                      index: 2,
                      openIndex: openIndex,
                      setOpen: (i) => setState(() => openIndex = i),
                      icon: Icons.lock_outline,
                      title: "privacy".tr(),
                      text: "privacy_text".tr(),
                    ),

                    _MenuExpandableItem(
                      index: 3,
                      openIndex: openIndex,
                      setOpen: (i) => setState(() => openIndex = i),
                      icon: Icons.headphones_outlined,
                      title: "contact".tr(),
                      text: "contact_text".tr(),
                    ),

                    SizedBox(height: 170.h),

                    // 🔹 Language option (unchanged)
                    GestureDetector(
                      onTap: () {
                        Navigator.pop(context); 
                        final isEnglish = context.locale.languageCode == 'en';
                        context.setLocale(
                            isEnglish ? const Locale('ar') : const Locale('en'));

                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                            "language_changed".tr(),
                              style: const TextStyle(
                                fontFamily: 'Poppins',
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            backgroundColor: const Color(0xFF013A3C),
                            behavior: SnackBarBehavior.floating,
                            duration: const Duration(seconds: 2),
                          ),
                        );
                      },
                      child: Row(
                        children: [
                          const Icon(Icons.translate, color: Color(0xFFDD5B69)),
                          const SizedBox(width: 8),
                          Text(
                            "language_button".tr(),
                            style: const TextStyle(
                              fontFamily: 'Poppins',
                              color: Color(0xFFDD5B69),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      );
    },
  );
}

/// --------------------------------------------------------------
///  🔹 REUSABLE EXPANDABLE MENU ITEM
/// --------------------------------------------------------------
class _MenuExpandableItem extends StatelessWidget {
  final int index;
  final int? openIndex;
  final Function(int?) setOpen;
  final IconData icon;
  final String title;
  final String text;

  const _MenuExpandableItem({
    required this.index,
    required this.openIndex,
    required this.setOpen,
    required this.icon,
    required this.title,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    final bool isOpen = openIndex == index;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: () {
            // 🔹 Toggle – but close others automatically
            setOpen(isOpen ? null : index);
          },
          child: ListTile(
            leading: Icon(icon, color: const Color(0xFF11607E)),
            title: Text(
              title,
              style: const TextStyle(
                fontFamily: 'Poppins',
                color: Color(0xFF013A3C),
                fontSize: 15,
                fontWeight: FontWeight.w500,
              ),
            ),
            trailing: Icon(
              isOpen ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
              color: const Color(0xFF013A3C),
            ),
          ),
        ),

        // 🔹 Expanded text (only visible when open)
        if (isOpen)
          Padding(
            padding: EdgeInsets.only(left: 20.w, right: 20.w, bottom: 10.h),
            child: Text(
              text,
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 11.sp,
                color: const Color(0xFF4F869D),
                fontWeight: FontWeight.w400
              ),
            ),
          ),
      ],
    );
  }
}


