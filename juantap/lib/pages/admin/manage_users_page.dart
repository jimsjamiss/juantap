import 'dart:math';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:juantap/pages/admin/email_service_responder.dart';

class ManageUsersPage extends StatefulWidget {
  const ManageUsersPage({super.key});

  @override
  State<ManageUsersPage> createState() => _ManageUsersPageState();
}

class _ManageUsersPageState extends State<ManageUsersPage> {
  final _queryCtrl = TextEditingController();
  String _roleFilter = 'All';
  late final DatabaseReference _usersRef;
  List<_UserRow> _rows = [];
  bool _loading = true;

  // 🔑 Random password generator
  String _generatePassword(int length) {
    const chars =
        'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789@#%&!';
    final rand = Random.secure();
    return List.generate(length, (_) => chars[rand.nextInt(chars.length)]).join();
  }

  @override
  void initState() {
    super.initState();
    _usersRef = FirebaseDatabase.instance.ref('users');
    _loadUsers();
  }

  void _loadUsers() {
    _usersRef.onValue.listen((e) {
      final List<_UserRow> rows = [];
      for (final user in e.snapshot.children) {
        rows.add(_UserRow(
          uid: user.key ?? '',
          name: (user.child('username').value ?? '') as String,
          email: (user.child('email').value ?? '') as String,
          role: (user.child('role').value ?? 'user') as String,
          status: (user.child('status').value ?? 'Active') as String,
        ));
      }

      rows.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

      setState(() {
        _rows = rows;
        _loading = false;
      });
    });
  }

  // ✅ Filtered view
  List<_UserRow> get _filtered {
    final query = _queryCtrl.text.trim().toLowerCase();
    return _rows.where((r) {
      final matchesRole =
          _roleFilter == 'All' || r.role.toLowerCase() == _roleFilter.toLowerCase();
      final matchesQuery = query.isEmpty ||
          r.name.toLowerCase().contains(query) ||
          r.email.toLowerCase().contains(query);
      return matchesRole && matchesQuery;
    }).toList();
  }

  Future<void> _updateStatus(_UserRow row, String newStatus) async {
    await _usersRef.child(row.uid).update({'status': newStatus});
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('${row.role} ${row.name} set to $newStatus')));
    }
  }

  Future<void> _deleteUser(_UserRow row) async {
    await _usersRef.child(row.uid).remove();
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('${row.role} ${row.name} deleted')));
    }
  }

  // ✅ Add Responder Dialog (auto role = responder)
  Future<void> _showAddResponderDialog() async {
    final nameCtrl = TextEditingController();
    final emailCtrl = TextEditingController();
    const role = "responder";
    const status = "Active";

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Create Responder Account"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(labelText: "Responder Name"),
            ),
            TextField(
              controller: emailCtrl,
              decoration: const InputDecoration(labelText: "Responder Email"),
              keyboardType: TextInputType.emailAddress,
            ),
          ],
        ),
        actions: [
          TextButton(
            child: const Text("Cancel"),
            onPressed: () => Navigator.pop(ctx),
          ),
          ElevatedButton(
            child: const Text("Create"),
            onPressed: () async {
              final name = nameCtrl.text.trim();
              final email = emailCtrl.text.trim();

              if (name.isEmpty || email.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("Please fill in all fields")),
                );
                return;
              }

              // ✅ Validate email format
              final emailPattern = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');
              if (!emailPattern.hasMatch(email)) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("Invalid email format")),
                );
                return;
              }

              try {
                final password = _generatePassword(10);
                print("🟢 Generated Password: $password");

                final auth = FirebaseAuth.instance;

                // ✅ Check if email is already used
                final methods = await auth.fetchSignInMethodsForEmail(email);
                if (methods.isNotEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("Email already registered")),
                  );
                  return;
                }

                print("🟢 Creating Firebase Auth account...");
                final userCred = await auth.createUserWithEmailAndPassword(
                  email: email,
                  password: password,
                );

                await userCred.user?.sendEmailVerification();

                // ✅ Save new responder to /users node
                await _usersRef.child(userCred.user!.uid).set({
                  "username": name,
                  "email": email,
                  "role": role,
                  "status": status,
                  "phone": "",
                });

                print("✅ Responder saved successfully with exact email: $email");

                // ✅ Send account email via EmailJS
                final success = await EmailResponderService.sendResponderAccountEmail(
                  email: email,
                  username: name,
                  password: password,
                  role: role,
                );

                if (success) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text("Responder '$name' created ✅ Email sent!")),
                  );
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("Responder created, but email failed ❌")),
                  );
                }

                if (mounted) Navigator.pop(ctx);
              } on FirebaseAuthException catch (e) {
                print("🔥 FirebaseAuthException: ${e.code}");
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text("FirebaseAuth error: ${e.message}")),
                );
              } catch (e, stack) {
                print("🔥 General Error: $e");
                print(stack);
                ScaffoldMessenger.of(context)
                    .showSnackBar(SnackBar(content: Text("Error: $e")));
              }
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(
        child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()),
      );
    }

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Row(
            children: [
              SizedBox(
                width: 260,
                child: TextField(
                  controller: _queryCtrl,
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search),
                    hintText: 'Search by name or email',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(width: 12),
              DropdownButton<String>(
                value: _roleFilter,
                items: const [
                  DropdownMenuItem(value: 'All', child: Text('All roles')),
                  DropdownMenuItem(value: 'user', child: Text('User')),
                  DropdownMenuItem(value: 'responder', child: Text('Responder')),
                  DropdownMenuItem(value: 'admin', child: Text('Admin')),
                ],
                onChanged: (v) => setState(() => _roleFilter = v ?? 'All'),
              ),
              const Spacer(),
              ElevatedButton.icon(
                icon: const Icon(Icons.add),
                label: const Text("Add Responder"),
                onPressed: _showAddResponderDialog,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: Card(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: _UsersDataTable(
                  rows: _filtered,
                  onSuspend: (r) => _updateStatus(r, 'Suspended'),
                  onActivate: (r) => _updateStatus(r, 'Active'),
                  onDelete: _deleteUser,
                  onResetPassword: (r) async {
                    try {
                      await FirebaseAuth.instance.sendPasswordResetEmail(email: r.email);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Password reset email sent to ${r.email} ✅')),
                      );
                    } catch (e) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Error: $e')),
                      );
                    }
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// -------------------- Data Classes --------------------
class _UserRow {
  final String uid;
  final String name;
  final String email;
  final String role;
  final String status;

  _UserRow({
    required this.uid,
    required this.name,
    required this.email,
    required this.role,
    required this.status,
  });
}

// -------------------- Data Table --------------------
class _UsersDataTable extends StatelessWidget {
  final List<_UserRow> rows;
  final void Function(_UserRow) onSuspend;
  final void Function(_UserRow) onActivate;
  final void Function(_UserRow) onDelete;
  final void Function(_UserRow) onResetPassword;

  const _UsersDataTable({
    required this.rows,
    required this.onSuspend,
    required this.onActivate,
    required this.onDelete,
    required this.onResetPassword,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.vertical,
      child: PaginatedDataTable(
        header: const Text('Responder Accounts'),
        rowsPerPage: 6,
        columnSpacing: 20,
        columns: const [
          DataColumn(label: Text('Name')),
          DataColumn(label: Text('Email')),
          DataColumn(label: Text('Role')),
          DataColumn(label: Text('Status')),
          DataColumn(label: Text('Actions')),
        ],
        source: _UsersSource(rows, onSuspend, onActivate, onDelete, onResetPassword),
      ),
    );
  }
}

class _UsersSource extends DataTableSource {
  final List<_UserRow> rows;
  final void Function(_UserRow) onSuspend;
  final void Function(_UserRow) onActivate;
  final void Function(_UserRow) onDelete;
  final void Function(_UserRow) onResetPassword;

  _UsersSource(this.rows, this.onSuspend, this.onActivate, this.onDelete, this.onResetPassword);

  @override
  DataRow? getRow(int index) {
    if (index >= rows.length) return null;
    final r = rows[index];
    return DataRow(cells: [
      DataCell(Text(r.name.isEmpty ? '(Unnamed)' : r.name)),
      DataCell(Text(r.email)),
      DataCell(Text(r.role)),
      DataCell(Text(r.status)),
      DataCell(Row(
        children: [
          IconButton(icon: const Icon(Icons.key), tooltip: 'Reset Password', onPressed: () => onResetPassword(r)),
          IconButton(
            icon: Icon(r.status == 'Active' ? Icons.pause_circle_outline : Icons.play_circle_outline),
            tooltip: r.status == 'Active' ? 'Suspend' : 'Activate',
            onPressed: () => r.status == 'Active' ? onSuspend(r) : onActivate(r),
          ),
          IconButton(icon: const Icon(Icons.delete_outline), onPressed: () => onDelete(r)),
        ],
      )),
    ]);
  }

  @override
  bool get isRowCountApproximate => false;
  @override
  int get rowCount => rows.length;
  @override
  int get selectedRowCount => 0;
}