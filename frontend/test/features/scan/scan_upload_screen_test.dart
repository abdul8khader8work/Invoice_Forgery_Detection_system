import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:invoice_forgery_detection/features/scan/screens/scan_upload_screen.dart';

void main() {
  group('ScanUploadScreen Widget Tests', () {
    testWidgets('renders upload screen with drag drop zone', (WidgetTester tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: ScanUploadScreen(),
          ),
        ),
      );

      expect(find.text('Upload Invoice'), findsOneWidget);
      expect(find.text('Drag & drop invoice'), findsOneWidget);
      expect(find.text('or click to browse'), findsOneWidget);
      expect(find.text('Supported: JPG, PNG, PDF (max 10MB)'), findsOneWidget);
      expect(find.text('Gallery'), findsOneWidget);
      expect(find.text('Camera'), findsOneWidget);
    });

    testWidgets('shows gallery and camera buttons', (WidgetTester tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: ScanUploadScreen(),
          ),
        ),
      );

      expect(find.byType(ElevatedButton), findsWidgets);
      expect(find.text('Gallery'), findsOneWidget);
      expect(find.text('Camera'), findsOneWidget);
    });
  });
}
