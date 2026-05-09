import 'package:intl/intl.dart';

/// Chart formatting utilities for analytics dashboard
class ChartFormatters {
  /// Format date for chart labels
  static String formatDate(DateTime date, {String format = 'MMM dd'}) {
    return DateFormat(format).format(date);
  }
  
  /// Format date string for chart labels
  static String formatDateString(String dateString, {String format = 'MMM dd'}) {
    try {
      final date = DateTime.parse(dateString);
      return formatDate(date, format: format);
    } catch (e) {
      return dateString;
    }
  }
  
  /// Format number with commas
  static String formatNumber(int number) {
    return NumberFormat.decimalPattern().format(number);
  }
  
  /// Format percentage
  static String formatPercentage(double value, {int decimalPlaces = 1}) {
    return '${value.toStringAsFixed(decimalPlaces)}%';
  }
  
  /// Format risk score
  static String formatRiskScore(double score) {
    return score.toStringAsFixed(2);
  }
  
  /// Format currency amount
  static String formatCurrency(double amount) {
    return NumberFormat.currency(symbol: '₹').format(amount);
  }
  
  /// Get risk level color
  static String getRiskLevelColor(String riskLevel) {
    switch (riskLevel.toLowerCase()) {
      case 'high':
        return '#EF4444'; // Red
      case 'medium':
        return '#F59E0B'; // Amber
      case 'low':
        return '#10B981'; // Green
      default:
        return '#6B7280'; // Gray
    }
  }
  
  /// Get risk level from score
  static String getRiskLevelFromScore(double score) {
    if (score >= 0.7) return 'high';
    if (score >= 0.4) return 'medium';
    return 'low';
  }
  
  /// Format time range label
  static String formatTimeRangeLabel(String timeRange) {
    switch (timeRange) {
      case '7d':
        return 'Last 7 Days';
      case '30d':
        return 'Last 30 Days';
      case '90d':
        return 'Last 90 Days';
      case 'custom':
        return 'Custom Range';
      default:
        return timeRange;
    }
  }
  
  /// Format large numbers (K, M, B)
  static String formatLargeNumber(int number) {
    if (number >= 1000000000) {
      return '${(number / 1000000000).toStringAsFixed(1)}B';
    } else if (number >= 1000000) {
      return '${(number / 1000000).toStringAsFixed(1)}M';
    } else if (number >= 1000) {
      return '${(number / 1000).toStringAsFixed(1)}K';
    }
    return number.toString();
  }
  
  /// Format duration in human-readable format
  static String formatDuration(Duration duration) {
    if (duration.inDays > 0) {
      return '${duration.inDays}d';
    } else if (duration.inHours > 0) {
      return '${duration.inHours}h';
    } else if (duration.inMinutes > 0) {
      return '${duration.inMinutes}m';
    } else {
      return '${duration.inSeconds}s';
    }
  }
  
  /// Format file size
  static String formatFileSize(int bytes) {
    if (bytes >= 1073741824) {
      return '${(bytes / 1073741824).toStringAsFixed(1)} GB';
    } else if (bytes >= 1048576) {
      return '${(bytes / 1048576).toStringAsFixed(1)} MB';
    } else if (bytes >= 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    return '$bytes bytes';
  }
}
