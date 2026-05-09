import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_border_radius.dart';
import '../theme/app_text_styles.dart';
import '../providers/auth_provider.dart';

class NavigationSidebar extends ConsumerWidget {
  const NavigationSidebar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.space4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Logo/Brand area
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.space8),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(AppSpacing.space2),
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(AppBorderRadius.radiusMd),
                  ),
                  child: const Icon(Icons.shield, color: Colors.white, size: 20),
                ),
                const SizedBox(width: AppSpacing.space2),
                const Text(
                  'InvoiceGuard',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
          
          // Navigation items
          const NavItem(
            icon: Icons.upload_file,
            label: 'Single Upload',
            route: '/scan',
          ),
          const SizedBox(height: AppSpacing.space1),
          const NavItem(
            icon: Icons.inventory_2,
            label: 'Batch Upload',
            route: '/batch',
          ),
          const SizedBox(height: AppSpacing.space1),
          const NavItem(
            icon: Icons.history,
            label: 'History',
            route: '/history',
          ),
          const SizedBox(height: AppSpacing.space1),
          const NavItem(
            icon: Icons.analytics,
            label: 'Analytics',
            route: '/analytics',
          ),
          const SizedBox(height: AppSpacing.space1),
          const NavItem(
            icon: Icons.settings,
            label: 'Settings',
            route: '/settings',
          ),
          
          const Spacer(),
          
          // Footer
          Container(
            padding: const EdgeInsets.all(AppSpacing.space4),
            decoration: BoxDecoration(
              color: Color(0xFF1A1A2E),
              borderRadius: BorderRadius.circular(AppBorderRadius.radiusMd),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'System Status',
                  style: AppTextStyles.caption.copyWith(
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: AppSpacing.space2),
                Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: AppColors.success,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.space2),
                    Text(
                      'All Systems Operational',
                      style: AppTextStyles.caption.copyWith(
                        color: Colors.grey[400],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          
          const SizedBox(height: 16),
          
          // Logout button
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: ElevatedButton.icon(
              onPressed: () {
                // Show confirmation dialog
                showDialog(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('Logout'),
                    content: const Text('Are you sure you want to logout?'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Cancel'),
                      ),
                      ElevatedButton(
                        onPressed: () {
                          // Call logout
                          ref.read(authProvider.notifier).logout();
                          Navigator.pop(context); // Close dialog
                          // Navigate to login
                          context.go('/login');
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red,
                          foregroundColor: Colors.white,
                        ),
                        child: const Text('Logout'),
                      ),
                    ],
                  ),
                );
              },
              icon: const Icon(Icons.logout, size: 20),
              label: const Text('Logout'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red[50],
                foregroundColor: Colors.red[700],
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final String route;
  
  const NavItem({
    super.key,
    required this.icon,
    required this.label,
    required this.route,
  });

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).uri.toString();
    final isActive = location == route || (route != '/' && location.startsWith(route));
    
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.space1),
      child: Material(
        color: isActive ? Color(0xFF2A2A4E) : Colors.transparent,
        borderRadius: BorderRadius.circular(AppBorderRadius.radiusMd),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppBorderRadius.radiusMd),
          onTap: () => context.push(route),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.space4,
              vertical: AppSpacing.space3,
            ),
            child: Row(
              children: [
                Icon(
                  icon,
                  size: 20,
                  color: isActive ? AppColors.primary : Colors.grey[400],
                ),
                const SizedBox(width: AppSpacing.space3),
                Expanded(
                  child: Text(
                    label,
                    style: AppTextStyles.body.copyWith(
                      color: isActive ? AppColors.primary : Colors.grey[400],
                      fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
