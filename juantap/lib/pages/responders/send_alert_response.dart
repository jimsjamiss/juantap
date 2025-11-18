import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'location_of_the_user.dart';
import 'responder.dart';
import 'video_proof_modal.dart';


class SendAlertResponsePage extends StatefulWidget {
  final Map<String, dynamic> alertData;

  const SendAlertResponsePage({super.key, required this.alertData});

  @override
  State<SendAlertResponsePage> createState() => _SendAlertResponsePageState();
}

class _SendAlertResponsePageState extends State<SendAlertResponsePage> {
  Map<String, dynamic>? userInfo;
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchUserInfo();
  }

  // ✅ Fetch user info from /users/{userId}
  Future<void> _fetchUserInfo() async {
    try {
      final userId = widget.alertData['userId'];
      if (userId == null || userId.toString().isEmpty) {
        debugPrint("❌ Missing userId in alertData: ${widget.alertData}");
        setState(() => isLoading = false);
        return;
      }

      final snapshot =
      await FirebaseDatabase.instance.ref('users/$userId').get();

      if (snapshot.exists) {
        final data = Map<String, dynamic>.from(snapshot.value as Map);
        setState(() {
          userInfo = data;
          isLoading = false;
        });
      } else {
        debugPrint("⚠️ No user data found for ID: $userId");
        setState(() => isLoading = false);
      }
    } catch (e) {
      debugPrint("❌ Error fetching user info: $e");
      setState(() => isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final info = userInfo;
    final alert = widget.alertData;
    final alertId = widget.alertData['alertId'] ?? '';
    final latitude = alert['location']?['lat'] ?? 0.0;
    final longitude = alert['location']?['lng'] ?? 0.0;

    return Scaffold(
      backgroundColor: const Color(0xFF2A9D8F),
      appBar: AppBar(
        backgroundColor: const Color(0xFF2A9D8F),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () {
            Navigator.pushAndRemoveUntil(
              context,
              MaterialPageRoute(builder: (_) => const ResponderDashboard()),
                  (route) => false,
            );
          },
        ),
        title: const Text('Responder', style: TextStyle(color: Colors.white)),
        actions: [
          IconButton(
            icon: const Icon(Icons.description_outlined, color: Colors.white),
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Incident Report button clicked')),
              );
            },
          ),
        ],
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.white))
          : info == null
          ? const Center(
        child: Text(
          'No user information found.',
          style: TextStyle(color: Colors.white),
        ),
      )
          : SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Container(
          padding: const EdgeInsets.all(20),
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
              // ✅ Top profile header
              Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: (info['profileImage'] != null && info['profileImage'].toString().isNotEmpty)
                        ? Image.network(
                      info['profileImage'],
                      width: 70,
                      height: 70,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) {
                        // If the Firebase image URL fails to load, fallback to default asset
                        return Image.asset(
                          'assets/images/user_profile.png',
                          width: 70,
                          height: 70,
                          fit: BoxFit.cover,
                        );
                      },
                    )
                        : Image.asset(
                      'assets/images/user_profile.png',
                      width: 70,
                      height: 70,
                      fit: BoxFit.cover,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          info['username'] ?? 'No Name',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          info['address'] ?? 'No Address',
                          style: const TextStyle(
                              color: Colors.white70, fontSize: 13),
                        ),
                        Text(
                          info['phone'] ?? 'No Phone',
                          style: const TextStyle(
                              color: Colors.white70, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                  Image.asset(
                    'assets/shield.png',
                    height: 40,
                    errorBuilder: (_, __, ___) => const Icon(
                      Icons.verified_user,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 16),

              // ✅ User Information
              _infoRow("Birthdate", info['birthdate'] ?? 'N/A'),
              _infoRow("Nationality", info['nationality'] ?? 'N/A'),
              _infoRow("Email", info['email'] ?? 'N/A'),
              _infoRow("Phone", info['phone'] ?? 'N/A'),
              _infoRow("Address", info['address'] ?? 'N/A'),
              _infoRow("Location", alert['location']?['placeName'] ?? 'N/A'),

              const SizedBox(height: 16),

              // ✅ Alert Info
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _infoMini(
                      "Reason", alert['reason'] ?? 'SOS Alert'),
                  _infoMini(
                      "Timestamp", alert['timestamp'] ?? 'N/A'),
                ],
              ),

              const SizedBox(height: 24),

              // =============================
// 🔥 PROOF SECTION (IMAGE + VIDEO MODAL)
// =============================
              if (alert['proofUrl'] != null && alert['proofUrl'].toString().isNotEmpty)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 16),
                    const Text(
                      "Proof Submitted",
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 10),

                    // === IMAGE PROOF ===
                    if (alert['isVideo'] == false)
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.network(
                          alert['proofUrl'],
                          height: 200,
                          width: double.infinity,
                          fit: BoxFit.cover,
                        ),
                      ),

                    // === VIDEO PROOF (Modal Popup) ===
                    if (alert['isVideo'] == true)
                      GestureDetector(
                        onTap: () {
                          showDialog(
                            context: context,
                            barrierDismissible: true,
                            builder: (_) =>
                                VideoProofModal(videoUrl: alert['proofUrl']),
                          );
                        },
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.black26,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            children: const [
                              Icon(Icons.play_circle_fill,
                                  color: Colors.white, size: 40),
                              SizedBox(width: 12),
                              Text(
                                "Tap to play video proof",
                                style: TextStyle(color: Colors.white, fontSize: 14),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),

              // ✅ Go to map button
              GestureDetector(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => LocationOfUserPage(
                        alertId: alertId,
                        latitude: latitude,
                        longitude: longitude,
                        userId: alert['userId'] ?? '',
                        userName: alert['username'] ?? 'Unknown User',
                      ),
                    ),
                  );
                },
                child: Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF25C09C), Color(0xFFFF0000)],
                      begin: Alignment.bottomLeft,
                      end: Alignment.topRight,
                    ),
                    borderRadius: BorderRadius.circular(30),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.25),
                        offset: const Offset(0, 2),
                        blurRadius: 6,
                      ),
                    ],
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  alignment: Alignment.center,
                  child: const Text(
                    'Send Alert Response',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
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

  Widget _infoRow(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        Text(label,
            style: const TextStyle(color: Colors.white70, fontSize: 13)),
        Text(
          value,
          style: const TextStyle(
              color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
        ),
        const Divider(color: Colors.white54),
      ],
    );
  }

  Widget _infoMini(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(color: Colors.white70, fontSize: 12)),
        Text(
          value,
          style: const TextStyle(
              color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
        ),
      ],
    );
  }
}