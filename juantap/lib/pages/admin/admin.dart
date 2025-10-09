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
            const Icon(Icons.shield, color: Colors.blue),
            const SizedBox(width: 8),
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
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            const DrawerHeader(
              decoration: BoxDecoration(color: Colors.blue),
              child: Text(
                "JuanTap Admin",
                style: TextStyle(color: Colors.white, fontSize: 18),
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
      body: Row(
        children: [
          if (isWide)
            NavigationRail(
              selectedIndex: _selectedIndex,
              onDestinationSelected: _onSelect,
              extended: true,
              destinations: const [
                NavigationRailDestination(
                  icon: Icon(Icons.dashboard_outlined),
                  label: Text("Dashboard"),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.people_outline),
                  label: Text("Manage Users"),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.report_gmailerrorred_outlined),
                  label: Text("Incident Reports"),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.map_outlined),
                  label: Text("Geofencing"),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.insights_outlined),
                  label: Text("Analytics"),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.settings_outlined),
                  label: Text("Settings"),
                ),
              ],
            ),
          Expanded(
            child: IndexedStack(
              index: _selectedIndex,
              children: [
                const DashboardOverview(),
                ManageUsersPage(),
                IncidentReportsPage(),
                GeofencingPage(),
                AnalyticsPage(),   // ✅ now separate file
                SettingsPage(),    // ✅ now separate file
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _drawerTile(int idx, IconData icon, String label) {
    return ListTile(
      leading: Icon(icon,
          color: _selectedIndex == idx ? Colors.blue : Colors.black54),
      title: Text(
        label,
        style: TextStyle(
          color: _selectedIndex == idx ? Colors.blue : Colors.black87,
        ),
      ),
      onTap: () {
        setState(() => _selectedIndex = idx);
        Navigator.pop(context); // close drawer
      },
    );
  }
}

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
            child: Icon(Icons.admin_panel_settings),
          ),
          const SizedBox(width: 8),
          Text(display, style: const TextStyle(fontWeight: FontWeight.w600)),
          const Icon(Icons.expand_more),
        ],
      ),
    );
  }
}