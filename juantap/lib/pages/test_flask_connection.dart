// import 'dart:convert';
// import 'package:flutter/material.dart';
// import 'package:http/http.dart' as http;
//
// class TestFlaskConnectionPage extends StatefulWidget {
//   const TestFlaskConnectionPage({super.key});
//
//   @override
//   State<TestFlaskConnectionPage> createState() => _TestFlaskConnectionPageState();
// }
//
// class _TestFlaskConnectionPageState extends State<TestFlaskConnectionPage> {
//   bool _loading = false;
//   String _result = '';
//
//   Future<void> _testFlaskRoute() async {
//     setState(() => _loading = true);
//     try {
//       final url = Uri.parse('http://192.168.1.5:5000/safe-route'); // 🔹 your Flask local IP
//       final response = await http.post(
//         url,
//         headers: {'Content-Type': 'application/json'},
//         body: jsonEncode({
//           "origin": [123.9183, 10.3110],
//           "destination": [123.9337, 10.3295]
//         }),
//       );
//
//       if (response.statusCode == 200) {
//         final data = jsonDecode(response.body);
//         setState(() => _result = const JsonEncoder.withIndent('  ').convert(data));
//         debugPrint("✅ Flask Response:\n$_result");
//       } else {
//         setState(() => _result = "❌ Error ${response.statusCode}: ${response.body}");
//       }
//     } catch (e) {
//       setState(() => _result = "🔥 Exception: $e");
//     } finally {
//       setState(() => _loading = false);
//     }
//   }
//
//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       appBar: AppBar(title: const Text("Flask Connection Test")),
//       body: Padding(
//         padding: const EdgeInsets.all(16.0),
//         child: Column(
//           children: [
//             ElevatedButton(
//               onPressed: _loading ? null : _testFlaskRoute,
//               child: _loading
//                   ? const CircularProgressIndicator(color: Colors.white)
//                   : const Text("Test Flask Safe Route"),
//             ),
//             const SizedBox(height: 20),
//             Expanded(
//               child: SingleChildScrollView(
//                 child: Text(_result, style: const TextStyle(fontSize: 14)),
//               ),
//             ),
//           ],
//         ),
//       ),
//     );
//   }
// }
