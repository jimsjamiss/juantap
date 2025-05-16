import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';

class ContactListsRequestsPage extends StatefulWidget {
  @override
  _ContactListsRequestsPageState createState() => _ContactListsRequestsPageState();
}

class _ContactListsRequestsPageState extends State<ContactListsRequestsPage> {
  final currentUser = FirebaseAuth.instance.currentUser;
  final DatabaseReference _requestsRef = FirebaseDatabase.instance.ref('contact_requests');
  final DatabaseReference _contactsRef = FirebaseDatabase.instance.ref('contacts');
  Map<String, dynamic> _requests = {};

  @override
  void initState() {
    super.initState();
    _loadRequests();
  }

  void _loadRequests() async {
    final snapshot = await _requestsRef.child(currentUser!.uid).get();
    if (snapshot.exists) {
      setState(() {
        _requests = Map<String, dynamic>.from(snapshot.value as Map);
      });
    }
  }

  Future<void> _acceptRequest(String senderUid, String senderUsername) async {
    // Save contact to both users
    await _contactsRef.child(currentUser!.uid).child(senderUid).set({
      'name': senderUsername,
      'nickname': '',
    });

    await _contactsRef.child(senderUid).child(currentUser!.uid).set({
      'name': currentUser!.displayName ?? 'You',
      'nickname': '',
    });

    // Remove the request
    await _requestsRef.child(currentUser!.uid).child(senderUid).remove();

    _loadRequests();
  }

  Future<void> _declineRequest(String senderUid) async {
    await _requestsRef.child(currentUser!.uid).child(senderUid).remove();
    _loadRequests();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black87,
      appBar: AppBar(
        backgroundColor: Colors.teal,
        title: Text('Contact Requests'),
      ),
      body: _requests.isEmpty
          ? Center(
        child: Text('No pending requests', style: TextStyle(color: Colors.white54)),
      )
          : ListView(
        children: _requests.entries.map((entry) {
          final senderUid = entry.key;
          final request = Map<String, dynamic>.from(entry.value);
          final senderUsername = request['senderUsername'];

          return Card(
            color: Color(0xFF388E8E),
            margin: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: ListTile(
              title: Text(senderUsername, style: TextStyle(color: Colors.white)),
              subtitle: Text("wants to add you as a contact"),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: Icon(Icons.check, color: Colors.greenAccent),
                    onPressed: () => _acceptRequest(senderUid, senderUsername),
                  ),
                  IconButton(
                    icon: Icon(Icons.close, color: Colors.redAccent),
                    onPressed: () => _declineRequest(senderUid),
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}
