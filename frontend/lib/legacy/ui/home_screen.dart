import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:io';
import 'dart:typed_data';

import '../services/api_service.dart';
import '../models/scan_result.dart';
import '../widgets/upload_card.dart';
import '../widgets/recent_scans.dart';
import '../widgets/stats_card.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final ApiService _apiService = ApiService();
  final ImagePicker _imagePicker = ImagePicker();
  bool _isScanning = false;
  String? _selectedFilePath;
  Uint8List? _selectedFileBytes;
  String? _selectedFileName;
  int _totalScans = 0;
  int _highRiskCount = 0;

  @override
  void initState() {
    super.initState();
    _requestPermissions();
    _loadStats();
  }

  Future<void> _loadStats() async {
    try {
      final invoices = await _apiService.getInvoices();
      setState(() {
        _totalScans = invoices.length;
        _highRiskCount = invoices.where((inv) => 
          (inv['risk_level'] == 'high' || (inv['risk_score'] ?? 0) > 70)
        ).length;
      });
    } catch (e) {
      debugPrint('Failed to load stats: $e');
    }
  }

  Future<void> _refreshData() async {
    setState(() {
      _isScanning = true;
    });
    
    try {
      await _loadStats();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Data refreshed successfully'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Refresh failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() {
        _isScanning = false;
      });
    }
  }

  Future<void> _requestPermissions() async {
    // Skip permissions on web platform - not supported
    if (kIsWeb) return;
    
    await Permission.camera.request();
    await Permission.storage.request();
  }

  Future<void> _pickImageFromCamera() async {
    try {
      final XFile? image = await _imagePicker.pickImage(
        source: ImageSource.camera,
        maxWidth: 2048,
        maxHeight: 2048,
        imageQuality: 85,
      );
      
      if (image != null) {
        final bytes = await image.readAsBytes();
        setState(() {
          // Don't use path on web - it's not available
          _selectedFilePath = null; // Set to null for web
          _selectedFileBytes = bytes;
          _selectedFileName = image.name;
        });
        _scanInvoice();
      }
    } catch (e) {
      _showErrorDialog('Camera Error', 'Failed to capture image: ${e.toString()}');
    }
  }

  Future<void> _pickImageFromGallery() async {
    try {
      ImagePicker picker = ImagePicker();
      XFile? image = await picker.pickImage(source: ImageSource.gallery);

      if (image != null) {
        // For web, we need to read bytes
        Uint8List imageBytes = await image.readAsBytes();
        setState(() {
          _selectedFileBytes = imageBytes;
          _selectedFileName = image.name;
          _selectedFilePath = null; // Set to null for web
        });
        _scanInvoice();
      }
    } catch (e) {
      _showErrorDialog('Gallery Error', 'Failed to pick image: ${e.toString()}');
    }
  }

  Future<void> _pickFile() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['jpg', 'jpeg', 'png', 'pdf'],
        allowMultiple: false,
      );

      if (result != null && result.files.single.bytes != null) {
        setState(() {
          _selectedFileBytes = result.files.single.bytes;
          _selectedFileName = result.files.single.name;
          // Don't use path on web - it's not available
          _selectedFilePath = null; // Set to null for web
        });
        _scanInvoice();
      }
    } catch (e) {
      _showErrorDialog('File Picker Error', 'Failed to pick file: ${e.toString()}');
    }
  }

  Future<void> _scanInvoice() async {
    if (_selectedFileBytes == null || _selectedFileName == null) {
      _showErrorDialog('No File Selected', 'Please select a file to scan.');
      return;
    }

    setState(() {
      _isScanning = true;
    });

    try {
      print('Starting invoice scan...');
      print('File: ${_selectedFileName}');
      print('Size: ${_selectedFileBytes!.length} bytes');

      final result = await _apiService.scanInvoice(
        _selectedFileBytes!,
        _selectedFileName!,
      );

      print('Scan completed successfully');
      print('Risk score: ${result.riskScore}');
      print('Risk level: ${result.riskLevel}');

      if (mounted) {
        // Pass file bytes along with result to display in verification screen
        final resultWithBytes = ScanResult(
          fileId: result.fileId,
          filename: result.filename,
          extractedData: result.extractedData,
          ocrConfidence: result.ocrConfidence,
          deterministicValidation: result.deterministicValidation,
          mlAnalysis: result.mlAnalysis,
          riskScore: result.riskScore,
          riskLevel: result.riskLevel,
          reasoning: result.reasoning,
          needsVerification: result.needsVerification,
          verificationFields: result.verificationFields,
          processingTime: result.processingTime,
          timestamp: result.timestamp,
          fileBytes: _selectedFileBytes, // Pass the uploaded file bytes
        );
        
        // Refresh stats and recent scans after successful scan
        await _loadStats();
        
        Navigator.pushNamed(
          context,
          '/scan_result',
          arguments: resultWithBytes,
        );
      }
    } catch (e) {
      print('Scan failed: $e');
      
      // Provide more specific error messages
      String errorMessage = 'Failed to scan invoice';
      String errorDetail = e.toString();
      
      if (e.toString().contains('connection')) {
        errorMessage = 'Connection Error';
        errorDetail = 'Unable to connect to the backend server. Please check if the server is running.';
      } else if (e.toString().contains('timeout')) {
        errorMessage = 'Timeout Error';
        errorDetail = 'The request took too long. Please try again.';
      } else if (e.toString().contains('400')) {
        errorMessage = 'Invalid File';
        errorDetail = 'The file format is not supported or the file is corrupted.';
      } else if (e.toString().contains('500')) {
        errorMessage = 'Server Error';
        errorDetail = 'The backend server encountered an error. Please try again.';
      } else if (e.toString().contains('size')) {
        errorMessage = 'File Too Large';
        errorDetail = 'The file size exceeds the maximum allowed limit (10MB).';
      }
      
      if (mounted) {
        _showErrorDialog(errorMessage, errorDetail);
      }
    } finally {
      if (mounted) {
        setState(() {
          _isScanning = false;
          _selectedFileBytes = null;
          _selectedFileName = null;
          _selectedFilePath = null;
        });
      }
    }
  }

  void _showErrorDialog(String title, String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Invoice Forgery Detection'),
        actions: [
          IconButton(
            icon: const Icon(Icons.cloud_upload),
            tooltip: 'Batch Upload (up to 5)',
            onPressed: () {
              Navigator.pushNamed(context, '/batch_upload');
            },
          ),
          IconButton(
            icon: const Icon(Icons.history),
            onPressed: () {
              // Navigate to history
            },
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Stats Cards
              Container(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Expanded(
                      child: StatsCard(
                        title: 'Total Scans',
                        value: _totalScans.toString(),
                        icon: Icons.analytics,
                        color: Colors.blue,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: StatsCard(
                        title: 'High Risk',
                        value: _highRiskCount.toString(),
                        icon: Icons.warning,
                        color: Colors.red,
                      ),
                    ),
                  ],
                ),
              ),
              // Upload Options
              UploadCard(
                title: 'Camera Scan',
                description: 'Take a photo of invoice',
                icon: Icons.camera_alt,
                color: Colors.purple,
                onTap: _pickImageFromCamera,
                isLoading: _isScanning,
              ),
              const SizedBox(height: 12),
              UploadCard(
                title: 'Gallery Upload',
                description: 'Choose from photo gallery',
                icon: Icons.photo_library,
                color: Colors.blue,
                onTap: _pickImageFromGallery,
                isLoading: _isScanning,
              ),
              const SizedBox(height: 12),
              UploadCard(
                title: 'File Upload',
                description: 'Upload PDF or image file',
                icon: Icons.file_upload,
                color: Colors.orange,
                onTap: _pickFile,
                isLoading: _isScanning,
              ),
              const SizedBox(height: 24),
              // Recent Scans
              const RecentScans(),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
      floatingActionButton: Container(
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF1976D2), Color(0xFF42A5F5)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.blue.withOpacity(0.4),
              blurRadius: 12,
              spreadRadius: 2,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: _refreshData,
            borderRadius: BorderRadius.circular(16),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.refresh,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Text(
                    'Reload',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
