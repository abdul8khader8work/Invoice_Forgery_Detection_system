import 'dart:io';
import 'package:dio/dio.dart';

void main() async {
  final dio = Dio(BaseOptions(baseUrl: 'http://127.0.0.1:8000'));
  
  // Create a test file
  final testFile = File('test_invoice.jpg');
  await testFile.writeAsBytes([0xFF, 0xD8, 0xFF, 0xE0]); // Minimal JPEG header
  
  try {
    print('Testing scan endpoint with fixed API client...');
    
    final formData = FormData.fromMap({
      'file': await MultipartFile.fromFile(testFile.path),
    });
    
    final response = await dio.post('/scan', data: formData);
    print('✅ Success: ${response.statusCode}');
    print('Response: ${response.data}');
  } catch (e) {
    print('❌ Error: $e');
  } finally {
    await testFile.delete();
  }
}
