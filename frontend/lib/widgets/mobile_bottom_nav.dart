import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class MobileBottomNav extends StatelessWidget {
  final int currentIndex;
  
  const MobileBottomNav({
    super.key,
    required this.currentIndex,
  });

  @override
  Widget build(BuildContext context) {
    return BottomNavigationBar(
      currentIndex: currentIndex,
      onTap: (index) {
        switch (index) {
          case 0:
            context.go('/scan');
            break;
          case 1:
            context.go('/batch');
            break;
          case 2:
            context.go('/analytics');
            break;
          case 3:
            context.go('/history');
            break;
          case 4:
            context.go('/settings');
            break;
        }
      },
      type: BottomNavigationBarType.fixed,
      selectedItemColor: Theme.of(context).colorScheme.primary,
      unselectedItemColor: Colors.grey[600],
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      items: const [
        BottomNavigationBarItem(
          icon: Icon(Icons.upload_file),
          label: 'Upload',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.inventory_2),
          label: 'Batch',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.analytics),
          label: 'Analytics',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.history),
          label: 'History',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.settings),
          label: 'Settings',
        ),
      ],
    );
  }
}
