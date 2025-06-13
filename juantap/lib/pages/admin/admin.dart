import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:fl_chart/fl_chart.dart';
import 'userlist.dart';
import 'analytics.dart';
import 'incidents.dart';
import 'package:juantap/pages/users/login.dart';
import 'package:firebase_database/firebase_database.dart';

class admin extends StatefulWidget {
  const admin({super.key});

  @override
  State<admin> createState() => _adminState();
}

class _adminState extends State<admin> {
  List<String> recentLocations = [];
  List<int> monthlyCounts = List.filled(12, 0);
  Set<int> availableYears = {};
  int selectedYear = DateTime.now().year;

  @override
  void initState() {
    super.initState();
    fetchRecentLocations();
    fetchAvailableYears();
  }

  void fetchRecentLocations() async {
    final dbRef = FirebaseDatabase.instance.ref("responder_reports");
    final snapshot = await dbRef.get();

    List<String> locations = [];

    for (var userEntry in snapshot.children) {
      for (var report in userEntry.children) {
        final location = report.child("location").value;
        if (location != null && location.toString().isNotEmpty) {
          locations.add(location.toString());
        }
      }
    }

    setState(() {
      recentLocations = locations.take(3).toList();
    });
  }

  void fetchAvailableYears() async {
    final dbRef = FirebaseDatabase.instance.ref("responder_reports");
    final snapshot = await dbRef.get();

    Set<int> years = {};

    for (var userEntry in snapshot.children) {
      for (var report in userEntry.children) {
        final rawDate = report.child("date").value?.toString();
        final cleanedDate = rawDate?.replaceAll('"', '').trim();

        if (cleanedDate != null && cleanedDate.contains("/")) {
          final parts = cleanedDate.split("/");
          if (parts.length >= 3) {
            final year = int.tryParse(parts[2]);
            if (year != null) years.add(year);
          }
        }
      }
    }

    setState(() {
      availableYears = years;
      if (!years.contains(selectedYear)) {
        selectedYear = years.isNotEmpty ? years.first : DateTime.now().year;
      }
    });

    fetchMonthlyReportCounts(selectedYear);
  }

  void fetchMonthlyReportCounts(int yearToFilter) async {
    final dbRef = FirebaseDatabase.instance.ref("responder_reports");
    final snapshot = await dbRef.get();

    List<int> counts = List.filled(12, 0);
    Set<String> seenReports = {};

    for (var userEntry in snapshot.children) {
      for (var report in userEntry.children) {
        final rawDate = report.child("date").value?.toString();
        final cleanedDate = rawDate?.replaceAll('"', '').trim();

        if (cleanedDate != null && cleanedDate.contains("/")) {
          final parts = cleanedDate.split("/");
          if (parts.length >= 3) {
            final uniqueKey = "${userEntry.key}_${report.key}";
            if (!seenReports.contains(uniqueKey)) {
              seenReports.add(uniqueKey);

              final month = int.tryParse(parts[0]) ?? 0;
              final year = int.tryParse(parts[2]) ?? 0;

              if (month >= 1 && month <= 12 && year == yearToFilter) {
                counts[month - 1]++;
              }
            }
          }
        }
      }
    }

    setState(() {
      monthlyCounts = counts;
    });
  }

  void _logout() async {
    await FirebaseAuth.instance.signOut();
    if (mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const LoginPage()),
      );
    }
  }

  void _showExportDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFFFF8A65), Color(0xFFFF5252)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.all(Radius.circular(20)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.arrow_downward, color: Colors.white, size: 40),
              const SizedBox(height: 10),
              const Text(
                'Export as CSV file',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF28A361),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(30),
                  ),
                ),
                onPressed: () {
                  Navigator.of(context).pop();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('CSV file exported')),
                  );
                },
                child: const Text('Export'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildYearDropdown() {
    final sortedYears = availableYears.toList()..sort();
    return DropdownButton<int>(
      dropdownColor: Colors.teal[800],
      value: selectedYear,
      style: const TextStyle(color: Colors.white),
      iconEnabledColor: Colors.white,
      underline: const SizedBox(),
      onChanged: (int? newYear) {
        if (newYear != null) {
          setState(() => selectedYear = newYear);
          fetchMonthlyReportCounts(newYear);
        }
      },
      items: sortedYears.map((year) {
        return DropdownMenuItem(
          value: year,
          child: Text('$year'),
        );
      }).toList(),
    );
  }

  Widget _summaryCard(String label, String value) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.2),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          children: [
            Text(label,
                style: const TextStyle(color: Colors.white, fontSize: 14)),
            const SizedBox(height: 4),
            Text(value,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }

  Widget _buildSection({required String title, required List<Widget> children}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: const TextStyle(
                  fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
          const SizedBox(height: 12),
          ...children
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF2A9D8F),
      drawer: Drawer(
        backgroundColor: const Color(0xFF264653),
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            UserAccountsDrawerHeader(
              decoration: const BoxDecoration(
                color: Color(0xFF2A9D8F),
              ),
              accountName: GestureDetector(
                onTap: () {
                  showDialog(
                    context: context,
                    builder: (context) {
                      final nameController = TextEditingController(text: "Admin");
                      return AlertDialog(
                        title: const Text("Edit Name"),
                        content: TextField(
                          controller: nameController,
                          decoration: const InputDecoration(hintText: "Enter your name"),
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text("Cancel"),
                          ),
                          TextButton(
                            onPressed: () {
                              // Optionally: Save to Firebase
                              Navigator.pop(context);
                            },
                            child: const Text("Save"),
                          ),
                        ],
                      );
                    },
                  );
                },
                child: const Text("Admin", style: TextStyle(fontSize: 18)),
              ),
              accountEmail: const Text("admin@juantap.com"),
              currentAccountPicture: const CircleAvatar(
                backgroundColor: Colors.white,
                child: Icon(Icons.person, size: 40, color: Color(0xFF2A9D8F)),
              ),
            ),

            // Dashboard link
            ListTile(
              leading: const Icon(Icons.dashboard, color: Colors.white),
              title: const Text('Dashboard', style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(context); // Just closes drawer
              },
            ),

            // User List
            ListTile(
              leading: const Icon(Icons.people, color: Colors.white),
              title: const Text('Manage Users', style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const userlist()),
                );
              },
            ),

            // Incident Reports
            ListTile(
              leading: const Icon(Icons.report, color: Colors.white),
              title: const Text('Incident Reports', style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const AdminIncidentListPage()),
                );
              },
            ),

            // Statistics
            ListTile(
              leading: const Icon(Icons.bar_chart, color: Colors.white),
              title: const Text('Statistics', style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const AdminAnalyticsPage()),
                );
              },
            ),

            const Divider(color: Colors.white54),

            // Logout
            ListTile(
              leading: const Icon(Icons.logout, color: Colors.white),
              title: const Text('Logout', style: TextStyle(color: Colors.white)),
              onTap: () {
                showDialog(
                  context: context,
                  builder: (BuildContext context) {
                    return AlertDialog(
                      title: const Text("Confirm Logout"),
                      content: const Text("Are you sure you want to logout?"),
                      actions: [
                        TextButton(
                          child: const Text("Cancel"),
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                        TextButton(
                          child: const Text("Logout"),
                          onPressed: () {
                            Navigator.of(context).pop();
                            _logout();
                          },
                        ),
                      ],
                    );
                  },
                );
              },
            ),
          ],
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(12.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Builder(
                          builder: (context) => IconButton(
                            icon: const Icon(Icons.menu, color: Colors.white),
                            onPressed: () {
                              Scaffold.of(context).openDrawer(); // opens the Drawer
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Text('Dashboard',
                            style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 28)),
                      ],
                    ),
                    Row(
                      children: [
                        IconButton(
                          onPressed: () => _showExportDialog(context),
                          icon: const Icon(Icons.download, color: Colors.white),
                        )
                      ],
                    )
                  ],
                ),
                const SizedBox(height: 20),
                GestureDetector(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => const userlist()),
                    );
                  },
                  child: _buildSection(title: 'Manage Users', children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: List.generate(
                        5,
                            (index) => const CircleAvatar(
                          radius: 20,
                          backgroundImage: NetworkImage('https://i.imgur.com/8Km9tLL.jpg'),
                        ),
                      ),
                    ),
                  ]),
                ),
                const SizedBox(height: 20),
                GestureDetector(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => const AdminIncidentListPage()),
                    );
                  },
                  child: _buildSection(title: 'Incident Reports', children: [
                    for (String loc in recentLocations)
                      Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.map_outlined, color: Colors.white70),
                            const SizedBox(width: 8),
                            Text(loc, style: const TextStyle(color: Colors.white)),
                          ],
                        ),
                      )
                  ]),
                ),
                const SizedBox(height: 20),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    GestureDetector(
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (context) => const AdminAnalyticsPage()),
                        );
                      },
                      child: _buildSection(title: 'Statistics', children: [
                        const SizedBox(height: 10),
                        SizedBox(
                          height: 150,
                          child: BarChart(
                            BarChartData(
                              borderData: FlBorderData(show: false),
                              titlesData: FlTitlesData(
                                leftTitles: AxisTitles(
                                  sideTitles: SideTitles(
                                    showTitles: true,
                                    reservedSize: 28,
                                    getTitlesWidget: (value, meta) {
                                      return Text(
                                        value.toInt().toString(),
                                        style: const TextStyle(color: Colors.white, fontSize: 10),
                                      );
                                    },
                                  ),
                                ),
                                rightTitles: AxisTitles(
                                  sideTitles: SideTitles(showTitles: false),
                                ),
                                topTitles: AxisTitles(
                                  sideTitles: SideTitles(showTitles: false),
                                ),
                                bottomTitles: AxisTitles(
                                  sideTitles: SideTitles(
                                    showTitles: true,
                                    getTitlesWidget: (value, meta) {
                                      const months = [
                                        'JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN',
                                        'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC'
                                      ];
                                      return Padding(
                                        padding: const EdgeInsets.only(top: 4),
                                        child: Text(months[value.toInt()],
                                            style: const TextStyle(
                                                color: Colors.white, fontSize: 10)),
                                      );
                                    },
                                  ),
                                ),
                              ),
                              barGroups: List.generate(
                                12,
                                    (i) => BarChartGroupData(x: i, barRods: [
                                  BarChartRodData(
                                    toY: monthlyCounts[i].toDouble(),
                                    color: Colors.white,
                                    width: 8,
                                  ),
                                ]),
                              ),
                            ),
                          ),
                        ),
                      ]),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        const Text('Year: ', style: TextStyle(color: Colors.white)),
                        _buildYearDropdown(),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    _summaryCard('SOS Counts', '9'),
                    const SizedBox(width: 12),
                    _summaryCard('Active Users', '40/68'),
                  ],
                )
              ],
            ),
          ),
        ),
      ),
    );
  }
}