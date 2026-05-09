import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Responsive navigation bar
/// - Mobile: Bottom navigation bar
/// - Desktop/Web: Side navigation rail or hidden (space for drawer)
class AppNavigationBar extends StatelessWidget {
  final int currentIndex;
  final Function(int)? onDestinationSelected;

  const AppNavigationBar({
    super.key,
    required this.currentIndex,
    this.onDestinationSelected,
  });

  // Navigation destinations
  static const List<_NavDestination> destinations = [
    _NavDestination(
      icon: Icons.upload_file,
      selectedIcon: Icons.upload_file,
      label: 'Scan',
      route: '/scan',
    ),
    _NavDestination(
      icon: Icons.batch_prediction_outlined,
      selectedIcon: Icons.batch_prediction,
      label: 'Batch',
      route: '/batch',
    ),
    _NavDestination(
      icon: Icons.analytics_outlined,
      selectedIcon: Icons.analytics,
      label: 'Analytics',
      route: '/analytics',
    ),
    _NavDestination(
      icon: Icons.history_outlined,
      selectedIcon: Icons.history,
      label: 'History',
      route: '/history',
    ),
    _NavDestination(
      icon: Icons.settings_outlined,
      selectedIcon: Icons.settings,
      label: 'Settings',
      route: '/settings',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    // Check if we're on a wide screen (desktop/web)
    final isWideScreen = MediaQuery.of(context).size.width >= 1024;

    if (isWideScreen) {
      // Desktop/Web: Navigation rail on the left
      return NavigationRail(
        selectedIndex: currentIndex,
        onDestinationSelected: (index) {
          _handleNavigation(context, index);
        },
        labelType: NavigationRailLabelType.selected,
        destinations: destinations
            .map((d) => NavigationRailDestination(
                  icon: Icon(d.icon),
                  selectedIcon: Icon(d.selectedIcon),
                  label: Text(d.label),
                ))
            .toList(),
      );
    }

    // Mobile: Bottom navigation bar
    return NavigationBar(
      selectedIndex: currentIndex,
      onDestinationSelected: (index) {
        _handleNavigation(context, index);
      },
      destinations: destinations
          .map((d) => NavigationDestination(
                icon: Icon(d.icon),
                selectedIcon: Icon(d.selectedIcon),
                label: d.label,
              ))
          .toList(),
    );
  }

  void _handleNavigation(BuildContext context, int index) {
    final destination = destinations[index];
    
    // Call callback if provided
    onDestinationSelected?.call(index);
    
    // Navigate using go_router
    // Note: Some routes are placeholders and will show 404 until implemented
    context.go(destination.route);
  }
}

/// Internal destination configuration
class _NavDestination {
  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final String route;

  const _NavDestination({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.route,
  });
}

/// Navigation scaffold that wraps screens with appropriate navigation
class NavigationScaffold extends StatelessWidget {
  final Widget body;
  final int currentIndex;
  final String title;
  final List<Widget>? actions;

  const NavigationScaffold({
    super.key,
    required this.body,
    required this.currentIndex,
    this.title = 'Invoice Forgery Detection',
    this.actions,
  });

  @override
  Widget build(BuildContext context) {
    final isWideScreen = MediaQuery.of(context).size.width >= 1024;

    if (isWideScreen) {
      // Desktop layout with side rail
      return Scaffold(
        appBar: AppBar(
          title: Text(title),
          actions: actions,
        ),
        body: Row(
          children: [
            AppNavigationBar(currentIndex: currentIndex),
            const VerticalDivider(thickness: 1, width: 1),
            Expanded(child: body),
          ],
        ),
      );
    }

    // Mobile layout with bottom bar
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: actions,
      ),
      body: body,
      bottomNavigationBar: AppNavigationBar(currentIndex: currentIndex),
    );
  }
}
