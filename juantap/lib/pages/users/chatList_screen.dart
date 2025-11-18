import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'chat_screen.dart';

class ChatListScreen extends StatelessWidget {
  final String myId;

  const ChatListScreen({super.key, required this.myId});

  @override
  Widget build(BuildContext context) {
    final ref = FirebaseDatabase.instance.ref("chat_rooms");

    return Scaffold(
      appBar: AppBar(
        title: const Text("Messages"),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0.5,
      ),

      body: StreamBuilder(
        stream: ref.onValue,
        builder: (context, snapshot) {
          if (!snapshot.hasData ||
              snapshot.data?.snapshot.value == null) {
            return const Center(child: Text("No conversations"));
          }

          final raw = Map<dynamic, dynamic>.from(
              snapshot.data!.snapshot.value as dynamic);

          // filter rooms where user is included
          final chats = raw.entries.where((e) {
            final data = Map<String, dynamic>.from(e.value);
            return data["userId"] == myId || data["responderId"] == myId;
          }).map((e) {
            final room = Map<String, dynamic>.from(e.value);
            room["chatId"] = e.key;
            return room;
          }).toList()
            ..sort((a, b) =>
                (b["lastTimestamp"] ?? 0).compareTo(a["lastTimestamp"] ?? 0));

          return ListView.builder(
            itemCount: chats.length,
            itemBuilder: (_, i) {
              final chat = chats[i];
              final chatId = chat["chatId"];

              return ListTile(
                title: Text("Responder"), // or username
                subtitle: Text(chat["lastMessage"] ?? ""),
                trailing: Text(_format(chat["lastTimestamp"])),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ChatScreen(
                        chatId: chatId,
                        myId: myId,
                      ),
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }

  String _format(ts) {
    if (ts == null) return "";
    final dt = DateTime.fromMillisecondsSinceEpoch(ts);
    return "${dt.hour}:${dt.minute.toString().padLeft(2, '0')}";
  }
}
