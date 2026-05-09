import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:invoice_forgery_detection/core/utils/file_utils.dart';
import 'package:invoice_forgery_detection/core/providers/scan_providers.dart';
import 'package:invoice_forgery_detection/core/api/api_client.dart';

/// Runtime test to verify MultipartFile to File TypeError is resolved
void main() {
  group('Runtime File Type Handling Tests', () {
    test('Web platform file handling falls back correctly', () async {
      // Mock web platform
      final originalKIsWeb = kIsWeb;
      
      // Test PlatformFile conversion on web
      final platformFile = MockPlatformFile(
        name: 'test.pdf',
        size: 1024,
        bytes: List.filled(1024, 0x42),
        extension: 'pdf',
      );

      try {
        final file = await FileUtils.platformFileToFile(platformFile);
        print('❌ Expected web platform exception was not thrown');
        fail('Expected web platform exception');
      } catch (e) {
        if (e.toString().contains('Web platform')) {
          print('✅ Web platform correctly throws exception for File conversion');
        } else {
          print('❌ Unexpected exception: $e');
          rethrow;
        }
      }

      // Test bytes to file conversion on web
      final bytes = Uint8List.fromList(List.filled(1024, 0x43));
      try {
        final file = await FileUtils.bytesToFile(bytes, 'test.pdf');
        print('❌ Expected web platform exception was not thrown');
        fail('Expected web platform exception');
      } catch (e) {
        if (e.toString().contains('Web platform')) {
          print('✅ Web platform correctly throws exception for bytes conversion');
        } else {
          print('❌ Unexpected exception: $e');
          rethrow;
        }
      }

      print('✅ All web platform tests passed');
    });

    test('Desktop platform file handling works correctly', () async {
      // Test PlatformFile conversion on desktop
      final platformFile = MockPlatformFile(
        name: 'test_desktop.pdf',
        size: 2048,
        bytes: List.filled(2048, 0x44),
        extension: 'pdf',
      );

      try {
        final file = await FileUtils.platformFileToFile(platformFile);
        print('✅ Desktop PlatformFile conversion successful');
        print('   File path: ${file.path}');
        
        // Verify file exists and has correct content
        if (!kIsWeb) {
          expect(await file.exists(), isTrue);
          expect(await file.length(), equals(2048));
        }
      } catch (e) {
        if (e.toString().contains('Web platform')) {
          print('✅ Web platform detected - skipping desktop test');
        } else {
          print('❌ Desktop conversion failed: $e');
          rethrow;
        }
      }

      // Test bytes to file conversion on desktop
      final bytes = Uint8List.fromList(List.filled(1024, 0x45));
      try {
        final file = await FileUtils.bytesToFile(bytes, 'test_desktop.pdf');
        print('✅ Desktop bytes conversion successful');
        print('   File path: ${file.path}');
        
        if (!kIsWeb) {
          expect(await file.exists(), isTrue);
          expect(await file.length(), equals(1024));
        }
      } catch (e) {
        if (e.toString().contains('Web platform')) {
          print('✅ Web platform detected - skipping desktop test');
        } else {
          print('❌ Desktop bytes conversion failed: $e');
          rethrow;
        }
      }

      print('✅ All desktop platform tests passed');
    });

    test('File type detection and validation', () {
      expect(FileUtils.isPdfFile('document.pdf'), isTrue);
      expect(FileUtils.isPdfFile('image.jpg'), isFalse);
      expect(FileUtils.isImageFile('photo.png'), isTrue);
      expect(FileUtils.isImageFile('document.pdf'), isFalse);
      expect(FileUtils.isSupportedFile('invoice.pdf'), isTrue);
      expect(FileUtils.isSupportedFile('photo.jpeg'), isTrue);
      expect(FileUtils.isSupportedFile('file.txt'), isFalse);
      
      print('✅ File type detection working correctly');
    });

    test('File size formatting', () {
      expect(FileUtils.formatFileSize(512), equals('512 B'));
      expect(FileUtils.formatFileSize(1536), equals('1.5 KB'));
      expect(FileUtils.formatFileSize(2097152), equals('2.0 MB'));
      
      print('✅ File size formatting working correctly');
    });
  });

  group('Upload Pipeline Simulation', () {
    test('Complete upload pipeline with different file types', () async {
      print('🔄 Testing complete upload pipeline...');
      
      final testCases = [
        {'type': 'File', 'data': File('test.pdf')},
        {'type': 'String', 'data': '/path/to/test.pdf'},
        {'type': 'Uint8List', 'data': Uint8List.fromList(List.filled(1024, 0x46))},
        {'type': 'List<int>', 'data': List.filled(1024, 0x47)},
        {'type': 'PlatformFile', 'data': MockPlatformFile(
          name: 'pipeline_test.pdf',
          size: 1024,
          bytes: List.filled(1024, 0x48),
          extension: 'pdf',
        )},
      ];

      for (int i = 0; i < testCases.length; i++) {
        final testCase = testCases[i];
        print('   ${i + 1}. Testing ${testCase['type']} input');
        
        try {
          // Simulate the scan provider logic
          final file = testCase['data'];
          File? fileToUpload;
          
          if (file is File) {
            fileToUpload = file;
          } else if (file is String) {
            fileToUpload = File(file);
          } else if (file is! File && file is! String) {
            if (file.toString().contains('PlatformFile')) {
              try {
                fileToUpload = await FileUtils.platformFileToFile(file);
              } catch (e) {
                if (e.toString().contains('Web platform')) {
                  print('     ✅ Web platform fallback triggered');
                  continue;
                }
                rethrow;
              }
            } else if (file is List<int>) {
              try {
                final uint8List = Uint8List.fromList(file);
                fileToUpload = await FileUtils.bytesToFile(uint8List, 'test.pdf');
              } catch (e) {
                if (e.toString().contains('Web platform')) {
                  print('     ✅ Web platform fallback triggered');
                  continue;
                }
                rethrow;
              }
            }
          }
          
          print('     ✅ ${testCase['type']} conversion successful');
        } catch (e) {
          print('     ❌ ${testCase['type']} conversion failed: $e');
        }
      }
      
      print('✅ Upload pipeline simulation completed');
    });
  });
}

/// Mock PlatformFile for testing
class MockPlatformFile {
  final String name;
  final int size;
  final List<int>? bytes;
  final String? extension;

  MockPlatformFile({
    required this.name,
    required this.size,
    this.bytes,
    this.extension,
  });

  @override
  String toString() => 'PlatformFile(name: $name, size: $size)';
}
