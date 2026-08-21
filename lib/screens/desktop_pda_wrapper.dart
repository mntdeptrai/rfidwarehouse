import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'desktop/desktop_main_layout.dart';
import 'pda/pda_home_screen.dart';

class DesktopPdaWrapper extends StatelessWidget {
  const DesktopPdaWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Tự động nhận diện thiết bị 100% không cần nút chuyển mode:
        // 1. Nếu chạy trên Windows / macOS / Linux -> Tự động vào giao diện Desktop Quản Trị
        // 2. Nếu chạy trên Android / iOS (Tay cầm PDA C72e / Cruise2) -> Tự động vào giao diện Tay Cầm Mobile
        // 3. Nếu chạy trên Web -> Tự động theo độ phân giải màn hình (>= 850px là Desktop, < 850px là Mobile)
        bool isDesktopPlatform = false;

        if (kIsWeb) {
          isDesktopPlatform = constraints.maxWidth >= 850;
        } else {
          if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
            isDesktopPlatform = true;
          } else {
            // Android / iOS
            isDesktopPlatform = false;
          }
        }

        if (isDesktopPlatform) {
          return const DesktopMainLayout();
        }

        return const PdaHomeScreen();
      },
    );
  }
}
