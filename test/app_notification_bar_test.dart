import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uhf/widgets/app_notification_bar.dart';

void main() {
  testWidgets('AppSnackBar shows and automatically slides down after 2s', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () {
                AppSnackBar.showSuccess(context, 'Thao tác thành công!');
              },
              child: const Text('Bấm thông báo'),
            ),
          ),
        ),
      ),
    );

    // Initial state: no snackbar
    expect(find.byType(SnackBar), findsNothing);

    // Tap button to trigger success notification
    await tester.tap(find.text('Bấm thông báo'));
    await tester.pump(); // Start animation
    await tester.pump(const Duration(milliseconds: 300)); // Finish slide up

    // SnackBar is now visible
    expect(find.byType(SnackBar), findsOneWidget);
    expect(find.text('Thao tác thành công!'), findsOneWidget);

    final SnackBar snackBar = tester.widget(find.byType(SnackBar));
    expect(snackBar.duration, const Duration(seconds: 2));
    expect(snackBar.dismissDirection, DismissDirection.down);
    expect(snackBar.backgroundColor, const Color(0xFF10B981));

    // Fast-forward by 2 seconds: SnackBar starts dismissing
    await tester.pump(const Duration(seconds: 2));
    await tester.pump(const Duration(milliseconds: 300)); // Finish slide down animation

    // SnackBar has auto-slid down and dismissed
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('AppSnackBar dismisses previous notification immediately when new one is triggered', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Column(
              children: [
                ElevatedButton(
                  onPressed: () => AppSnackBar.showError(context, 'Lỗi 1!'),
                  child: const Text('Lỗi'),
                ),
                ElevatedButton(
                  onPressed: () => AppSnackBar.showWarning(context, 'Cảnh báo 2!'),
                  child: const Text('Cảnh báo'),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    // Trigger error notification (Red)
    await tester.tap(find.text('Lỗi'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Lỗi 1!'), findsOneWidget);
    SnackBar snackBar1 = tester.widget(find.byType(SnackBar));
    expect(snackBar1.backgroundColor, const Color(0xFFEF4444));
    expect(snackBar1.dismissDirection, DismissDirection.down);

    // Trigger warning notification (Yellow/Amber) immediately:
    // previous one is dismissed without queueing
    await tester.tap(find.text('Cảnh báo'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Cảnh báo 2!'), findsOneWidget);
    SnackBar snackBar2 = tester.widget(find.byType(SnackBar));
    expect(snackBar2.backgroundColor, const Color(0xFFF59E0B));
    expect(snackBar2.duration, const Duration(seconds: 2));
  });

  testWidgets('AppSnackBar allows swiping down on PDA (DismissDirection.down)', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => AppSnackBar.showInfo(context, 'Thông tin hướng dẫn!'),
              child: const Text('Thông tin'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Thông tin'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Thông tin hướng dẫn!'), findsOneWidget);

    // Swipe down on the SnackBar to simulate user dragging down with finger on PDA
    await tester.drag(find.byType(SnackBar), const Offset(0, 300));
    await tester.pumpAndSettle();

    // SnackBar is immediately dismissed by finger swipe
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('AppSnackBar correctly formats workflow-specific completion messages', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Column(
              children: [
                ElevatedButton(
                  onPressed: () => AppSnackBar.showSuccess(context, '✓ Đã cất thành công 12 sản phẩm vào kệ KHO-A-01!'),
                  child: const Text('Cất kệ'),
                ),
                ElevatedButton(
                  onPressed: () => AppSnackBar.showSuccess(context, '✓ Đã chuyển thành công 5 sản phẩm sang kệ KHO-B-02!'),
                  child: const Text('Chuyển kho'),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    // Test Putaway notification
    await tester.tap(find.text('Cất kệ'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('✓ Đã cất thành công 12 sản phẩm vào kệ KHO-A-01!'), findsOneWidget);

    // Test Transfer notification
    await tester.tap(find.text('Chuyển kho'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('✓ Đã chuyển thành công 5 sản phẩm sang kệ KHO-B-02!'), findsOneWidget);
  });
}

