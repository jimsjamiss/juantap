import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:intl/intl.dart';

class ResponderChatScreen extends StatefulWidget {
  final String chatId;
  final String responderId;
  final Map<String, dynamic> userInfo;

  const ResponderChatScreen({
    super.key,
    required this.chatId,
    required this.responderId,
    required this.userInfo,
  });

  @override
  State<ResponderChatScreen> createState() => _ResponderChatScreenState();
}

class _ResponderChatScreenState extends State<ResponderChatScreen> {
  final _msgCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  late DatabaseReference _msgRef;

  @override
  void initState() {
    super.initState();
    _msgRef = FirebaseDatabase.instance.ref("messages/${widget.chatId}");
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 300), () {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.jumpTo(_scrollCtrl.position.maxScrollExtent);
      }
    });
  }

  void _sendText() async {
    final text = _msgCtrl.text.trim();
    if (text.isEmpty) return;

    _msgCtrl.clear();

    await _msgRef.push().set({
      "senderId": widget.responderId,
      "text": text,
      "imageUrl": "",
      "type": "text",
      "timestamp": ServerValue.timestamp,
    });

    FirebaseDatabase.instance.ref("chat_rooms/${widget.chatId}").update({
      "lastMessage": text,
      "lastTimestamp": ServerValue.timestamp,
    });

    _scrollToBottom();
  }

  @override
  Widget build(BuildContext context) {
    final user = widget.userInfo;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0.5,
        title: Row(
          children: [
            CircleAvatar(
              radius: 22,
              backgroundImage: (user["profileImage"] != null &&
                  user["profileImage"].toString().isNotEmpty)
                  ? NetworkImage(user["profileImage"])
                  : const AssetImage("assets/images/user_profile.png")
              as ImageProvider,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    user["username"] ?? "User",
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                  Text(
                    user["phone"] ?? "",
                    style: const TextStyle(fontSize: 12, color: Colors.black54),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),

      body: Column(
        children: [
          Expanded(
            child: StreamBuilder(
              stream: _msgRef.orderByChild("timestamp").onValue,
              builder: (context, snapshot) {
                if (!snapshot.hasData ||
                    snapshot.data?.snapshot.value == null) {
                  return const Center(child: Text("No messages yet."));
                }

                final raw = Map<dynamic, dynamic>.from(
                    snapshot.data!.snapshot.value as dynamic);

                final messages = raw.entries.map((e) {
                  final msg = Map<String, dynamic>.from(e.value);
                  msg["id"] = e.key;
                  return msg;
                }).toList()
                  ..sort((a, b) => a["timestamp"].compareTo(b["timestamp"]));

                WidgetsBinding.instance.addPostFrameCallback((_) {
                  _scrollToBottom();
                });

                return ListView.builder(
                  controller: _scrollCtrl,
                  padding: const EdgeInsets.all(12),
                  itemCount: messages.length,
                  itemBuilder: (_, i) {
                    final msg = messages[i];
                    final bool isMe =
                        msg["senderId"] == widget.responderId;

                    return Align(
                      alignment: isMe
                          ? Alignment.centerRight
                          : Alignment.centerLeft,
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        margin: const EdgeInsets.symmetric(
                            vertical: 4, horizontal: 4),
                        constraints:
                        const BoxConstraints(maxWidth: 250),
                        decoration: BoxDecoration(
                          color: isMe
                              ? Colors.blue[600]
                              : Colors.grey.shade200,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Text(
                          msg["text"] ?? "",
                          style: TextStyle(
                            color: isMe
                                ? Colors.white
                                : Colors.black87,
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),

          _buildInputField(),
        ],
      ),
    );
  }

  Widget _buildInputField() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      color: Colors.white,
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _msgCtrl,
              decoration: InputDecoration(
                hintText: "Type a message…",
                filled: true,
                fillColor: Colors.grey.shade100,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(20),
                    borderSide: BorderSide.none),
              ),
            ),
          ),
          const SizedBox(width: 8),
          CircleAvatar(
            radius: 22,
            backgroundColor: Colors.blue[700],
            child: IconButton(
              icon: const Icon(Icons.send, color: Colors.white),
              onPressed: _sendText,
            ),
          ),
        ],
      ),
    );
  }
}
