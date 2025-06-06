import 'package:flutter/material.dart';

class AdminIncidentListPage extends StatelessWidget {
  const AdminIncidentListPage({super.key});

  @override
  Widget build(BuildContext context) {
    final List<Map<String, String>> incidents = [
      {
        'name': 'Juan Dela Cruz',
        'location': 'Brgy. Opao, Umapad',
        'image': 'https://i.imgur.com/8Km9tLL.jpg',
        'reason': 'no response',
        'time': '12:04 am',
        'date': '02/14/2025'
      },
      {
        'name': 'Kai sotto ginulay ang munggo',
        'location': 'Brgy. Opao, Looc',
        'image': 'https://i.imgur.com/QCNbOAo.png',
        'reason': 'SOS Alert',
        'time': '01:00 am',
        'date': '02/13/2025'
      },
      {
        'name': 'Tralalio Tropa Lang',
        'location': 'Brgy. Opao, Umapad',
        'image': 'https://i.imgur.com/BoN9kdC.png',
        'reason': 'SOS Alert',
        'time': '7:04 am',
        'date': '02/12/2025'
      },
      {
        'name': 'Biningit',
        'location': 'Brgy. Opao, Umapad',
        'image': 'https://i.imgur.com/uQw7pDa.jpg',
        'reason': 'no response',
        'time': '12:04 am',
        'date': '02/11/2025'
      },
    ];

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
              child: ListView.builder(
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
                                    Text('Time in location\n${incident['time']}',
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