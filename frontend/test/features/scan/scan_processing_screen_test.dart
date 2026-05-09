import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:invoice_forgery_detection/features/scan/screens/scan_processing_screen.dart';
import 'dart:io';

void main() {
  group('ScanProcessingScreen Widget Tests', () {
    testWidgets('renders processing screen with steps', (WidgetTester tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: ScanProcessingScreen(file: '/fake/path.jpg'),
          ),
        ),
      );

      expect(find.text('Processing Invoice'), findsOneWidget);
      expect(find.text('1. File Upload'), findsOneWidget);
      expect(find.text('2. OCR Processing'), findsOneWidget);
      expect(find.text('3. AI Analysis'), findsOneWidget);
      expect(find.text('4. Validation'), findsOneWidget);
      expect(find.text('5. ML Detection'), findsOneWidget);
    });

    testWidgets('shows progress indicator', (WidgetTester tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: ScanProcessingScreen(file: '/fake/path.jpg'),
          ),
        ),
      );

      expect(find.byType(LinearProgressIndicator), findsOneWidget);
    });
  });
}
