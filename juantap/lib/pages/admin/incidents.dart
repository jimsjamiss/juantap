import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';

class AdminIncidentListPage extends StatefulWidget {
  const AdminIncidentListPage({super.key});

  @override
  State<AdminIncidentListPage> createState() => _AdminIncidentListPageState();
}

class _AdminIncidentListPageState extends State<AdminIncidentListPage> {
  List<Map<String, String>> incidents = [];
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    fetchIncidents();
  }

  Future<void> fetchIncidents() async {
    try {
      final dbRef = FirebaseDatabase.instance.ref().child('responder_reports');
      final snapshot = await dbRef.get();

      if (snapshot.exists) {
        final Map data = snapshot.value as Map;
        final List<Map<String, String>> loaded = [];

        data.forEach((responderId, reportGroup) {
          final reports = Map<String, dynamic>.from(reportGroup);
          reports.forEach((reportId, reportData) {
            final report = Map<String, dynamic>.from(reportData);
            loaded.add({
              'name': responderId, // Can replace with actual username if needed
              'location': report['location'] ?? 'Unknown',
              'image': 'https://i.imgur.com/8Km9tLL.jpg',
              'reason': report['description'] ?? 'N/A',
              'time': report['time'] ?? '',
              'date': report['date'] ?? '',
            });
          });
        });

        setState(() {
          incidents = loaded;
          isLoading = false;
        });
      } else {
        setState(() {
          isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error fetching incident reports: $e');
      setState(() {
        isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF2A9D8F),
      appBar: AppBar(
        backgroundColor: const Color(0xFF2A9D8F),
        elevation: 0,
        title: const Text('Incidents', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: const Icon(Icons.download, color: Colors.white),
            onPressed: () {},
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 10),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(25),
              ),
              child: const TextField(
                decoration: InputDecoration(
                  icon: Icon(Icons.search),
                  hintText: 'Search',
                  border: InputBorder.none,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: isLoading
                  ? const Center(child: CircularProgressIndicator(color: Colors.white))
                  : incidents.isEmpty
                  ? const Center(
                child: Text('No reports found', style: TextStyle(color: Colors.white)),
              )
                  : ListView.builder(
                itemCount: incidents.length,
                itemBuilder: (context, index) {
                  final incident = incidents[index];
                  return Container(
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF25C09C), Color(0xFFFF0000)],
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                      ),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.network(
                              incident['image']!,
                              width: 60,
                              height: 60,
                              fit: BoxFit.cover,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  incident['name']!,
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.black),
                                ),
                                Row(
                                  children: [
                                    const Icon(Icons.location_on, size: 14, color: Colors.black54),
                                    const SizedBox(width: 4),
                                    Text(
                                      incident['location']!,
                                      style: const TextStyle(color: Colors.black54, fontSize: 13),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text('Time\n${incident['time']}',
                                        style: const TextStyle(fontSize: 12, color: Colors.black)),
                                    Text('Reason\n${incident['reason']}',
                                        style: const TextStyle(fontSize: 12, color: Colors.black)),
                                    Text('Date\n${incident['date']}',
                                        style: const TextStyle(fontSize: 12, color: Colors.black)),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            )
          ],
        ),
      ),
    );
  }
}