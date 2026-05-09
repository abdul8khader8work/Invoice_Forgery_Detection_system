import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../widgets/responsive_layout.dart';
import '../widgets/mobile_bottom_nav.dart';
import '../widgets/mobile_drawer.dart';
import 'app_header.dart';
import 'navigation_sidebar.dart';

class MainLayout extends StatefulWidget {
  final Widget child;
  
  const MainLayout({
    super.key,
    required this.child,
  });

  @override
  State<MainLayout> createState() => _MainLayoutState();
}

class _MainLayoutState extends State<MainLayout> {
  int _getBottomNavIndex(String currentPath) {
    if (currentPath.contains('/scan')) return 0;
    if (currentPath.contains('/batch')) return 1;
    if (currentPath.contains('/analytics')) return 2;
    if (currentPath.contains('/history')) return 3;
    if (currentPath.contains('/settings')) return 4;
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    final currentPath = GoRouterState.of(context).uri.toString();
    
    return ResponsiveLayout(
      // MOBILE LAYOUT
      mobile: Scaffold(
        appBar: AppBar(
          title: const Text('InvoiceGuard'),
          leading: Builder(
            builder: (context) => IconButton(
              icon: const Icon(Icons.menu),
              onPressed: () => Scaffold.of(context).openDrawer(),
            ),
          ),
        ),
        drawer: const MobileDrawer(),
        body: widget.child,
        bottomNavigationBar: MobileBottomNav(
          currentIndex: _getBottomNavIndex(currentPath),
        ),
      ),
      
      // DESKTOP LAYOUT (existing sidebar)
      desktop: Scaffold(
        backgroundColor: const Color(0xFF1A1A2E),
        body: Row(
          children: [
            // Sidebar
            Container(
              width: 256,
              color: const Color(0xFF16213E),
              child: const NavigationSidebar(),
            ),
            // Main content
            Expanded(
              child: Column(
                children: [
                  const AppHeader(),
                  Expanded(child: widget.child),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
