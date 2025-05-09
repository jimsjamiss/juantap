import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';

class ContactListPage extends StatefulWidget {
  @override
  _ContactListPageState createState() => _ContactListPageState();
}

class _ContactListPageState extends State<ContactListPage> {
  final TextEditingController _searchController = TextEditingController();
  final DatabaseReference _contactsRef = FirebaseDatabase.instance.ref('contacts');
  List<Map<String, dynamic>> _searchResults = [];
  Map<String, dynamic> _rawData = {};

  @override
  void initState() {
    super.initState();
    _searchContacts('');
  }

  void _searchContacts(String query) async {
    final snapshot = await _contactsRef.get();
    final List<Map<String, dynamic>> tempResults = [];

    if (snapshot.exists) {
      final data = Map<String, dynamic>.from(snapshot.value as Map);
      _rawData = data;
      data.forEach((key, value) {
        final contact = Map<String, dynamic>.from(value);
        final name = contact['name']?.toString().toLowerCase() ?? '';
        final phone = contact['phone']?.toString() ?? '';
        if (name.contains(query.toLowerCase()) || phone.contains(query)) {
          tempResults.add({
            'key': key,
            'name': contact['name'],
            'phone': contact['phone'],
            'nickname': contact['nickname'] ?? '',
          });
        }
      });
    }

    setState(() => _searchResults = tempResults);
  }

  void _editNickname(String key, String currentNickname) async {
    TextEditingController _nicknameController =
    TextEditingController(text: currentNickname);

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Edit Nickname'),
        content: TextField(
          controller: _nicknameController,
          decoration: InputDecoration(hintText: 'Enter nickname'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              await _contactsRef.child(key).update({
                'nickname': _nicknameController.text,
              });
              Navigator.pop(context);
              _searchContacts(_searchController.text);
            },
            child: Text('Save'),
          ),
        ],
      ),
    );
  }

  void _deleteContact(String key) async {
    await _contactsRef.child(key).remove();
    _searchContacts(_searchController.text);
  }

  void _showAddContactModal(BuildContext context) {
    final nameController = TextEditingController();
    final phoneController = TextEditingController();
    final nicknameController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Add New Contact'),
        content: SingleChildScrollView(
          child: Column(
            children: [
              TextField(
                controller: nameController,
                decoration: InputDecoration(labelText: 'Username'),
              ),
              TextField(
                controller: phoneController,
                decoration: InputDecoration(labelText: 'Phone'),
                keyboardType: TextInputType.phone,
              ),
              TextField(
                controller: nicknameController,
                decoration: InputDecoration(labelText: 'Nickname (optional)'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            child: Text('Cancel'),
            onPressed: () => Navigator.pop(context),
          ),
          ElevatedButton(
            child: Text('Add'),
            onPressed: () async {
              final name = nameController.text.trim();
              final phone = phoneController.text.trim();

              if (name.isEmpty || phone.isEmpty) return;

              await _contactsRef.push().set({
                'name': name,
                'phone': phone,
                'nickname': nicknameController.text.trim(),
              });

              Navigator.pop(context);
              _searchContacts(_searchController.text);
            },
          ),
        ],
      ),
    );
  }

  void _showRequestSentModal(BuildContext context, String name) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Request Sent'),
        content: Text('Your request to "$name" has been sent successfully.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black87,
      floatingActionButton: FloatingActionButton(
        backgroundColor: Colors.teal,
        child: Icon(Icons.person_add),
        onPressed: () => _showAddContactModal(context),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Container(
              color: Color(0xFF26A69A),
              padding: EdgeInsets.all(16),
              child: Column(
                children: [
                  Row(
                    children: [
                      Icon(Icons.arrow_back, color: Colors.black),
                      SizedBox(width: 12),
                      _tabButton('Contacts', true),
                      SizedBox(width: 12),
                      _tabButton('Request', false),
                      Spacer(),
                    ],
                  ),
                  SizedBox(height: 10),
                  TextField(
                    controller: _searchController,
                    onChanged: _searchContacts,
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: Colors.white,
                      hintText: 'Search',
                      prefixIcon: Icon(Icons.search),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(20),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: _searchResults.isEmpty
                  ? Center(
                child: Text(
                  'No contacts found.',
                  style: TextStyle(color: Colors.white54),
                ),
              )
                  : ListView.builder(
                itemCount: _searchResults.length,
                itemBuilder: (context, index) {
                  final contact = _searchResults[index];
                  return ListTile(
                    leading: CircleAvatar(child: Icon(Icons.person)),
                    title: Text(
                      contact['name'],
                      style: TextStyle(color: Colors.white),
                    ),
                    subtitle: Text(
                      'Nickname: ${contact['nickname'] ?? 'None'}\n${contact['phone']}',
                      style: TextStyle(color: Colors.white70),
                    ),
                    tileColor: Color(0xFF388E8E),
                    shape: Border(bottom: BorderSide(color: Colors.white24)),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: Icon(Icons.edit, color: Colors.yellow),
                          onPressed: () =>
                              _editNickname(contact['key'], contact['nickname']),
                        ),
                        IconButton(
                          icon: Icon(Icons.delete, color: Colors.redAccent),
                          onPressed: () => _deleteContact(contact['key']),
                        ),
                        IconButton(
                          icon: Icon(Icons.send, color: Colors.greenAccent),
                          onPressed: () =>
                              _showRequestSentModal(context, contact['name']),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tabButton(String text, bool selected) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: selected ? Colors.white : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: selected ? Colors.black : Colors.white,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
