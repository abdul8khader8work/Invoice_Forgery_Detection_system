import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:invoice_forgery_detection/features/scan/screens/scan_result_screen.dart';
import 'package:invoice_forgery_detection/core/api/models/scan_response.dart';

void main() {
  group('Scan Result Screen Integration Tests', () {
    late ScanResponse mockResult;

    setUp(() {
      mockResult = ScanResponse(
        fileId: 'test-file-123',
        filename: 'test_invoice.pdf',
        extractedData: {
          'vendor_name': 'Test Vendor Inc.',
          'invoice_number': 'INV-2026-001',
          'invoice_date': '05-Mar-2026',
          'subtotal': 270.00,
          'tax': 0.00,
          'total': 270.00,
          'payment_method': 'UPI',
          'vendor_address': 'H.NO 123, MAIN ROAD, BANGALORE PIN:560001',
          'vendor_phone': '+91-80-12345678',
          'line_items': [
            {
              'item_number': '1',
              'description': 'Kashmiri Walnut',
              'quantity': 0.1,
              'unit': 'Kgs',
              'unit_price': 1600.00,
              'amount': 160.00
            },
            {
              'item_number': '2',
              'description': 'Open Item',
              'quantity': 1,
              'unit': 'Pcs',
              'unit_price': 100.00,
              'amount': 100.00
            },
            {
              'item_number': '3',
              'description': 'Asli Ghee 500g',
              'quantity': 1,
              'unit': 'Pkt',
              'unit_price': 280.00,
              'amount': 280.00
            },
            {
              'item_number': '4',
              'description': 'Special Product',
              'quantity': 2.5,
              'unit': 'Kgs',
              'unit_price': 50.00,
              'amount': 125.00
            }
          ],
        },
        deterministicValidation: {
          'validation_score': 85,
          'math_validation': {
            'score': 100,
            'passed': True,
            'findings': []
          },
          'date_validation': {
            'passed': True
          }
        },
        mlAnalysis: {
          'anomaly_score': 15.5,
          'anomalies_detected': false
        },
        riskScore: 15.5,
        riskLevel: 'LOW',
        reasoning: [
          'All mathematical validations passed',
          'Date is within acceptable range',
          'No anomalies detected'
        ],
        needsVerification: false,
        verificationFields: [],
        processingTime: 2.5,
        timestamp: '2026-03-05T10:30:00Z',
        validationScore: 85,
        mlScore: 15.5,
        lineItems: [
          {
            'item_number': '1',
            'description': 'Kashmiri Walnut',
            'quantity': 0.1,
            'unit': 'Kgs',
            'unit_price': 1600.00,
            'amount': 160.00
          },
          {
            'item_number': '2',
            'description': 'Open Item',
            'quantity': 1,
            'unit': 'Pcs',
            'unit_price': 100.00,
            'amount': 100.00
          }
        ],
        paymentMethod: 'UPI',
        vendorAddress: 'H.NO 123, MAIN ROAD, BANGALORE PIN:560001',
        vendorPhone: '+91-80-12345678',
      );
    });

    testWidgets('Scan result screen displays line items correctly', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: ScanResultScreen(result: mockResult),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Verify line items section is present
      expect(find.text('Line Items:'), findsOneWidget);
      
      // Verify line items table headers
      expect(find.text('#'), findsOneWidget);
      expect(find.text('Description'), findsOneWidget);
      expect(find.text('Qty'), findsOneWidget);
      expect(find.text('Price'), findsOneWidget);
      expect(find.text('Amount'), findsOneWidget);
      
      // Verify line items data
      expect(find.text('1'), findsOneWidget);
      expect(find.text('Kashmiri Walnut'), findsOneWidget);
      expect(find.text('0.1 Kgs'), findsOneWidget);
      expect(find.text('1600.00'), findsOneWidget);
      expect(find.text('160.00'), findsOneWidget);
      
      expect(find.text('2'), findsOneWidget);
      expect(find.text('Open Item'), findsOneWidget);
      expect(find.text('1 Pcs'), findsOneWidget);
      expect(find.text('100.00'), findsOneWidget);
      expect(find.text('100.00'), findsOneWidget);
    });

    testWidgets('Validation score displays correctly with color coding', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: ScanResultScreen(result: mockResult),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Verify validation score is displayed correctly
      expect(find.text('Validation Score: 85/100'), findsOneWidget);
      
      // Find the validation score text widget to check its color
      final validationScoreText = tester.widget<Text>(
        find.text('Validation Score: 85/100')
      );
      
      // Score 85 should be green (since >= 80)
      expect(validationScoreText.style?.color, isNotNull);
    });

    testWidgets('ML anomaly score displays correctly', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: ScanResultScreen(result: mockResult),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Verify ML anomaly score is displayed correctly
      expect(find.text('Anomaly Score: 15.5/100'), findsOneWidget);
      
      // Find the ML score text widget to check its color
      final mlScoreText = tester.widget<Text>(
        find.text('Anomaly Score: 15.5/100')
      );
      
      // Score 15.5 should be green (since < 30)
      expect(mlScoreText.style?.color, isNotNull);
    });

    testWidgets('Enhanced fields display correctly', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: ScanResultScreen(result: mockResult),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Verify enhanced fields are displayed
      expect(find.text('Payment Method: UPI'), findsOneWidget);
      expect(find.text('Vendor Address: H.NO 123, MAIN ROAD, BANGALORE PIN:560001'), findsOneWidget);
      expect(find.text('Vendor Phone: +91-80-12345678'), findsOneWidget);
    });

    testWidgets('Action buttons are present and functional', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: ScanResultScreen(result: mockResult),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Verify primary action buttons
      expect(find.text('Download Report'), findsOneWidget);
      expect(find.text('Edit Data'), findsOneWidget);
      expect(find.text('Approve'), findsOneWidget);
      
      // Verify secondary action buttons
      expect(find.text('Home'), findsOneWidget);
      expect(find.text('Rescan'), findsOneWidget);
      
      // Test download button tap
      await tester.tap(find.text('Download Report'));
      await tester.pumpAndSettle();
      
      // Verify snackbar is shown
      expect(find.text('Downloading report for invoice test-file-123...'), findsOneWidget);
    });

    testWidgets('Risk warning only shows for MEDIUM/HIGH risk', (tester) async {
      // Test LOW risk - should not show warning
      var lowRiskResult = mockResult.copyWith(riskLevel: 'LOW');
      
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: ScanResultScreen(result: lowRiskResult),
          ),
        ),
      );

      await tester.pumpAndSettle();
      
      // Should not show verification warning for LOW risk
      expect(find.text('Human Verification Required'), findsNothing);
      
      // Test MEDIUM risk - should show warning
      var mediumRiskResult = mockResult.copyWith(riskLevel: 'MEDIUM');
      
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: ScanResultScreen(result: mediumRiskResult),
          ),
        ),
      );

      await tester.pumpAndSettle();
      
      // Should show verification warning for MEDIUM risk
      expect(find.text('Human Verification Required'), findsOneWidget);
      expect(find.text('Risk level: MEDIUM - Manual review recommended'), findsOneWidget);
    });

    testWidgets('ML anomaly score shows "Not calculated" when score is 0', (tester) async {
      var resultWithZeroAnomaly = mockResult.copyWith(
        mlAnalysis: {'anomaly_score': 0.0}
      );
      
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: ScanResultScreen(result: resultWithZeroAnomaly),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Should show "Not calculated" message
      expect(find.text('Anomaly Score: Not calculated (insufficient data)'), findsOneWidget);
    });

    testWidgets('Extracted data card expands and collapses correctly', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: ScanResultScreen(result: mockResult),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Initially should see the expansion tile header
      expect(find.text('Extracted Data'), findsOneWidget);
      
      // Tap to expand
      await tester.tap(find.text('Extracted Data'));
      await tester.pumpAndSettle();
      
      // Should now see the extracted data content
      expect(find.text('Vendor: Test Vendor Inc.'), findsOneWidget);
      expect(find.text('Invoice Number: INV-2026-001'), findsOneWidget);
      expect(find.text('Line Items:'), findsOneWidget);
    });

    testWidgets('Validation results card shows math validation details', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: ScanResultScreen(result: mockResult),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Tap to expand validation results
      await tester.tap(find.text('Validation Results'));
      await tester.pumpAndSettle();
      
      // Should show validation score
      expect(find.text('Validation Score: 85/100'), findsOneWidget);
    });

    testWidgets('ML analysis card shows anomaly details', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: ScanResultScreen(result: mockResult),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Tap to expand ML analysis
      await tester.tap(find.text('ML Analysis'));
      await tester.pumpAndSettle();
      
      // Should show ML analysis details
      expect(find.text('Anomaly Score: 15.5/100'), findsOneWidget);
      expect(find.text('Anomalies Detected: No'), findsOneWidget);
    });
  });
}
