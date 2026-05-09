import 'package:flutter/material.dart';

/// Stub Lottie animation widget - Lottie dependency not available
/// Uses built-in animations as fallbacks
class AppLottieAnimation extends StatelessWidget {
  final String animationType;
  final double width;
  final double height;
  final bool repeat;

  const AppLottieAnimation({
    super.key,
    required this.animationType,
    this.width = 100,
    this.height = 100,
    this.repeat = true,
  });

  @override
  Widget build(BuildContext context) {
    // Return appropriate icon based on animation type
    IconData icon;
    Color color;
    
    switch (animationType) {
      case 'success':
        icon = Icons.check_circle;
        color = Colors.green;
        break;
      case 'error':
        icon = Icons.error;
        color = Colors.red;
        break;
      case 'loading':
        icon = Icons.hourglass_empty;
        color = Colors.blue;
        break;
      case 'scan':
        icon = Icons.document_scanner;
        color = Colors.blue;
        break;
      default:
        icon = Icons.animation;
        color = Colors.grey;
    }

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      child: Icon(
        icon,
        size: width,
        color: color,
      ),
    );
  }
}
