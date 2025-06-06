import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'send_alert_response.dart';
import 'incident_reports.dart';

class ResponderDashboard extends StatefulWidget {
  const ResponderDashboard({super.key});

  @override
  State<ResponderDashboard> createState() => _ResponderDashboardState();
}

class _ResponderDashboardState extends State<ResponderDashboard> {
  File? _profileImage;

  Future<void> _pickImage() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (picked != null) {
      setState(() {
        _profileImage = File(picked.path);
      });
    }
  }

  void _showNotificationDialog(BuildContext context, Map<String, String> item) {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF25C09C), Color(0xFFFF0000)],
              begin: Alignment.bottomLeft,
              end: Alignment.topRight,
            ),
            borderRadius: BorderRadius.all(Radius.circular(20)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Align(
                alignment: Alignment.topRight,
                child: GestureDetector(
                  onTap: () => Navigator.of(context).pop(),
                  child: const Icon(Icons.close, color: Colors.white),
                ),
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image.network(
                  item['image']!,
                  width: 90,
                  height: 90,
                  fit: BoxFit.cover,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                item['name']!,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
              ),
              const SizedBox(height: 4),
              Text(item['location']!, style: const TextStyle(color: Colors.white70)),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text("Time in location\n${item['time']}", style: const TextStyle(color: Colors.white, fontSize: 12)),
                  Text("Reason\n${item['reason']}", style: const TextStyle(color: Colors.white, fontSize: 12)),
                  Text("Date\n${item['date']}", style: const TextStyle(color: Colors.white, fontSize: 12)),
                ],
              ),
              const SizedBox(height: 20),
              GestureDetector(
                onTap: () {
                  Navigator.of(context).pop();
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => SendAlertResponsePage(data: item),
                    ),
                  );
                },
                child: Container(
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF25C09C), Color(0xFFFF0000)],
                      begin: Alignment.bottomLeft,
                      end: Alignment.topRight,
                    ),
                    borderRadius: BorderRadius.circular(30),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.2),
                        offset: const Offset(0, 2),
                        blurRadius: 4,
                      ),
                    ],
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                  child: const Text(
                    'Accept Alert',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final List<Map<String, String>> notifications = [
      {
        'name': 'Juan Dela Cruz',
        'location': 'Brgy. Opao, Umapad',
        'time': '12:04 am',
        'reason': 'no response',
        'date': '02/14/2025',
        'image': 'https://i.imgur.com/8Km9tLL.jpg'
      },
      {
        'name': 'Kai Sotto',
        'location': 'Brgy. Opao, Looc',
        'time': '01:00 am',
        'reason': 'SOS Alert',
        'date': '02/13/2025',
        'image': 'https://i.imgur.com/QCNbOAo.png'
      },
      {
        'name': 'Tralalio Tropa Lang',
        'location': 'Brgy. Opao, Umapad',
        'time': '7:04 am',
        'reason': 'SOS Alert',
        'date': '02/12/2025',
        'image': 'https://i.imgur.com/BoN9kdC.png'
      },
      {
        'name': 'Biningit',
        'location': 'Brgy. Opao, Umapad',
        'time': '12:04 am',
        'reason': 'no response',
        'date': '02/11/2025',
        'image': 'https://i.imgur.com/uQw7pDa.jpg'
      },
    ];

    return Scaffold(
      backgroundColor: const Color(0xFF2A9D8F),
      appBar: AppBar(
        title: const Text('Responder', style: TextStyle(color: Colors.white)),
        backgroundColor: const Color(0xFF2A9D8F),
        elevation: 0,
      ),
      drawer: Drawer(
        child: Column(
          children: [
            const SizedBox(height: 40),
            GestureDetector(
              onTap: _pickImage,
              child: CircleAvatar(
                radius: 50,
                backgroundImage: _profileImage != null
                    ? FileImage(_profileImage!)
                    : const AssetImage('assets/shield.png') as ImageProvider,
              ),
            ),
            const SizedBox(height: 10),
            const Text('Responder Name', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 5),
            const Text('responder@email.com', style: TextStyle(color: Colors.grey)),
          ],
        ),
      ),
      body: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 12),
                const Text(
                  'Emergency Notifications',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: ListView.builder(
                    itemCount: notifications.length,
                    itemBuilder: (context, index) {
                      final item = notifications[index];
                      return GestureDetector(
                        onTap: () => _showNotificationDialog(context, item),
                        child: Container(
                          margin: const EdgeInsets.symmetric(vertical: 10),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFF25C09C), Color(0xFFFF0000)],
                              begin: Alignment.bottomLeft,
                              end: Alignment.topRight,
                            ),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Stack(
                            children: [
                              Padding(
                                padding: const EdgeInsets.all(12),
                                child: Row(
                                  children: [
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(8),
                                      child: Image.network(
                                        item['image']!,
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
                                            item['name']!,
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 16,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(item['location']!, style: const TextStyle(color: Colors.white)),
                                          const SizedBox(height: 8),
                                          Row(
                                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                            children: [
                                              Text("Time in location\n${item['time']}", style: const TextStyle(color: Colors.white, fontSize: 12)),
                                              Text("Reason\n${item['reason']}", style: const TextStyle(color: Colors.white, fontSize: 12)),
                                              Text("Date\n${item['date']}", style: const TextStyle(color: Colors.white, fontSize: 12)),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const Positioned(
                                top: 8,
                                right: 8,
                                child: Icon(Icons.arrow_circle_right, size: 32, color: Colors.white),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            top: 12,
            right: 16,
            child: FloatingActionButton(
              mini: true,
              backgroundColor: Colors.white,
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const IncidentReportsPage()),
                );
              },
              child: const Icon(Icons.description_outlined, color: Colors.black),
            ),
          ),
        ],
      ),
    );
  }
}
