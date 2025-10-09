// lib/pages/admin/admin.dart
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'analytics_page.dart';
import 'settings_page.dart';

// Import each separated page
import 'dashboard_overview.dart';
import 'manage_users_page.dart';
import 'incident_reports_page.dart';
import 'geofencing_page.dart';

class AdminDashboardPage extends StatefulWidget {
  const AdminDashboardPage({super.key});

  @override
  State<AdminDashboardPage> createState() => _AdminDashboardPageState();
}

class _AdminDashboardPageState extends State<AdminDashboardPage> {
  int _selectedIndex = 0;

  void _onSelect(int index) {
    setState(() => _selectedIndex = index);
  }

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width >= 1100;

    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        title: Row(
          children: [
            // ✅ AppBar logo (Top Left)
            Image.asset(
              'assets/images/app_logo.png',
              height: 45, // ⬅️ CHANGE THIS to resize the AppBar logo
            ),
            const SizedBox(width: 10),
            const Text(
              "JuanTap Admin Panel",
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const Spacer(),
            _ProfileMenu(),
          ],
        ),
      ),
      drawer: isWide
          ? null
          : Drawer(
        child: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF11998E), Color(0xFF38EF7D)],
            ),
          ),
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              DrawerHeader(
                decoration: const BoxDecoration(color: Colors.transparent),
                child: Row(
                  children: [
                    // ✅ Drawer logo (Mobile)
                    Image.asset(
                      'assets/images/app_logo.png',
                      height: 55, // ⬅️ CHANGE THIS to resize Drawer logo
                    ),
                    const SizedBox(width: 10),
                    const Text(
                      "JuanTap Admin",
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              _drawerTile(0, Icons.dashboard, "Dashboard"),
              _drawerTile(1, Icons.people, "Manage Users"),
              _drawerTile(2, Icons.report, "Incident Reports"),
              _drawerTile(3, Icons.map, "Geofencing"),
              _drawerTile(4, Icons.insights, "Analytics"),
              _drawerTile(5, Icons.settings, "Settings"),
            ],
          ),
        ),
      ),
      body: Row(
        children: [
          if (isWide)
          // ✅ Sidebar (Desktop)
            Container(
              width: 260,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0xFF11998E),
                    Color(0xFF38EF7D),
                  ],
                ),
              ),
              child: Column(
                children: [
                  const SizedBox(height: 30),
                  // ✅ Sidebar logo (Desktop)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Image.asset(
                        'assets/images/app_logo.png',
                        height: 60, // ⬅️ CHANGE THIS to resize Sidebar logo
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        "Admin Panel",
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 40),

                  // ✅ Sidebar Buttons
                  _navButton(Icons.dashboard, "Dashboard", 0),
                  _navButton(Icons.people, "Manage Users", 1),
                  _navButton(Icons.report, "Incident Reports", 2),
                  _navButton(Icons.map, "Geofencing", 3),
                  _navButton(Icons.insights, "Analytics", 4),
                  _navButton(Icons.settings, "Settings", 5),

                  const Spacer(),
                  const Padding(
                    padding: EdgeInsets.only(bottom: 16),
                    child: Text(
                      "© JuanTap 2025",
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),

          // ✅ Main Dashboard Pages
          Expanded(
            child: IndexedStack(
              index: _selectedIndex,
              children: [
                const DashboardOverview(),
                ManageUsersPage(),
                IncidentReportsPage(),
                GeofencingPage(),
                AnalyticsPage(),
                SettingsPage(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ✅ Sidebar Button Builder
  Widget _navButton(IconData icon, String label, int index) {
    final isSelected = _selectedIndex == index;
    return InkWell(
      onTap: () => _onSelect(index),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        margin: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? Colors.white.withOpacity(0.15) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          boxShadow: isSelected
              ? [
            BoxShadow(
              color: Colors.black26.withOpacity(0.15),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ]
              : [],
        ),
        child: Row(
          children: [
            Icon(icon,
                color: isSelected ? Colors.white : Colors.white70, size: 22),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: isSelected ? Colors.white : Colors.white70,
                  fontSize: 15,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ✅ Drawer menu for small screens
  Widget _drawerTile(int idx, IconData icon, String label) {
    return ListTile(
      leading: Icon(
        icon,
        color: _selectedIndex == idx ? Colors.white : Colors.white70,
      ),
      title: Text(
        label,
        style: TextStyle(
          color: _selectedIndex == idx ? Colors.white : Colors.white70,
        ),
      ),
      onTap: () {
        setState(() => _selectedIndex = idx);
        Navigator.pop(context);
      },
    );
  }
}

// ✅ Profile Menu (top-right)
class _ProfileMenu extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final display = user?.email ?? 'admin@juantap';

    return PopupMenuButton<String>(
      tooltip: 'Profile',
      itemBuilder: (ctx) => [
        const PopupMenuItem(
          value: 'logout',
          child: Row(
            children: [Icon(Icons.logout), SizedBox(width: 8), Text('Logout')],
          ),
        ),
      ],
      onSelected: (v) async {
        if (v == 'logout') {
          await FirebaseAuth.instance.signOut();
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Logged out')),
            );
            Navigator.of(context).maybePop();
          }
        }
      },
      child: Row(
        children: [
          const CircleAvatar(
            backgroundColor: Color(0xFF38EF7D),
            child: Icon(Icons.admin_panel_settings, color: Colors.white),
          ),
          const SizedBox(width: 8),
          Text(display, style: const TextStyle(fontWeight: FontWeight.w600)),
          const Icon(Icons.expand_more),
        ],
      ),
    );
  }
}
