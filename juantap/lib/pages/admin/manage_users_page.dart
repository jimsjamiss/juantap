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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${row.role} ${row.name} set to $newStatus')),
      );
    }
  }

  Future<void> _deleteUser(_UserRow row) async {
    await _usersRef.child(row.uid).remove();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${row.role} ${row.name} deleted')),
      );
    }
  }

  Future<void> _showAddResponderDialog() async {
    final nameCtrl = TextEditingController();
    final emailCtrl = TextEditingController();
    const role = "responder";
    const status = "Active";

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFFFAFCFF),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          "Create Responder Account",
          style: TextStyle(
            color: Color(0xFF084C41),
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(
                labelText: "Responder Name",
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: emailCtrl,
              decoration: const InputDecoration(
                labelText: "Responder Email",
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.emailAddress,
            ),
          ],
        ),
        actions: [
          TextButton(
            child: const Text("Cancel", style: TextStyle(color: Colors.grey)),
            onPressed: () => Navigator.pop(ctx),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1E88E5),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
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

              final emailPattern = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');
              if (!emailPattern.hasMatch(email)) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("Invalid email format")),
                );
                return;
              }

              try {
                final password = _generatePassword(10);
                final auth = FirebaseAuth.instance;

                final methods = await auth.fetchSignInMethodsForEmail(email);
                if (methods.isNotEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("Email already registered")),
                  );
                  return;
                }

                final userCred = await auth.createUserWithEmailAndPassword(
                  email: email,
                  password: password,
                );
                await userCred.user?.sendEmailVerification();

                await _usersRef.child(userCred.user!.uid).set({
                  "username": name,
                  "email": email,
                  "role": role,
                  "status": status,
                });

                final success = await EmailResponderService.sendResponderAccountEmail(
                  email: email,
                  username: name,
                  password: password,
                  role: role,
                );

                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      success
                          ? "Responder '$name' created ✅ Email sent!"
                          : "Responder created, but email failed ❌",
                    ),
                  ),
                );

                if (mounted) Navigator.pop(ctx);
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text("Error: $e")),
                );
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

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFFC8F4E4),
            Color(0xFFA7E2C9),
            Color(0xFF7FD1AE),
          ],
        ),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "Manage Responder Accounts",
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF084C41),
                ),
              ),
              const SizedBox(height: 20),
              _searchFilterBar(),
              const SizedBox(height: 20),
              Expanded(
                child: Card(
                  color: const Color(0xFFFAFCFF),
                  elevation: 6,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: _UsersDataTable(
                      rows: _filtered,
                      onSuspend: (r) => _updateStatus(r, 'Suspended'),
                      onActivate: (r) => _updateStatus(r, 'Active'),
                      onDelete: _deleteUser,
                      onResetPassword: (r) async {
                        try {
                          await FirebaseAuth.instance
                              .sendPasswordResetEmail(email: r.email);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                                content: Text(
                                    'Password reset email sent to ${r.email} ✅')),
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
        ),
      ),
    );
  }

  Widget _searchFilterBar() {
    return Row(
      children: [
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFFF4FFF9),
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: TextField(
              controller: _queryCtrl,
              decoration: const InputDecoration(
                hintText: 'Search by name or email',
                prefixIcon: Icon(Icons.search, color: Color(0xFF084C41)),
                border: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(vertical: 14),
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
        ),
        const SizedBox(width: 12),
        DropdownButton<String>(
          value: _roleFilter,
          icon: const Icon(Icons.arrow_drop_down, color: Color(0xFF084C41)),
          underline: const SizedBox(),
          items: const [
            DropdownMenuItem(value: 'All', child: Text('All Roles')),
            DropdownMenuItem(value: 'user', child: Text('User')),
            DropdownMenuItem(value: 'responder', child: Text('Responder')),
            DropdownMenuItem(value: 'admin', child: Text('Admin')),
          ],
          onChanged: (v) => setState(() => _roleFilter = v ?? 'All'),
        ),
      ],
    );
  }
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
    final totalUsers = rows.length;
    final responders = rows.where((r) => r.role == 'responder').length;
    final admins = rows.where((r) => r.role == 'admin').length;
    final suspended = rows.where((r) => r.status == 'Suspended').length;

    return Column(
      children: [
        _summaryBar(totalUsers, responders, admins, suspended),
        const SizedBox(height: 8),
        Expanded(
          child: SingleChildScrollView(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final nameWidth = constraints.maxWidth * 0.25;
                final emailWidth = constraints.maxWidth * 0.3;
                final roleWidth = constraints.maxWidth * 0.15;
                final statusWidth = constraints.maxWidth * 0.15;
                final actionsWidth = constraints.maxWidth * 0.15;

                return PaginatedDataTable(
                  header: null,
                  rowsPerPage: 6,
                  columnSpacing: 0,
                  headingRowHeight: 60,
                  dataRowMinHeight: 55,
                  dataRowMaxHeight: 65,
                  headingRowColor:
                  WidgetStateProperty.all(const Color(0xFFD7F9E9)),
                  columns: [
                    DataColumn(label: SizedBox(width: nameWidth, child: const Text('Name', style: TextStyle(fontWeight: FontWeight.bold)))),
                    DataColumn(label: SizedBox(width: emailWidth, child: const Text('Email', style: TextStyle(fontWeight: FontWeight.bold)))),
                    DataColumn(label: SizedBox(width: roleWidth, child: const Text('Role', style: TextStyle(fontWeight: FontWeight.bold)))),
                    DataColumn(label: SizedBox(width: statusWidth, child: const Text('Status', style: TextStyle(fontWeight: FontWeight.bold)))),
                    DataColumn(label: SizedBox(width: actionsWidth, child: const Text('Actions', style: TextStyle(fontWeight: FontWeight.bold)))),
                  ],
                  source: _UsersSource(
                    rows,
                    onSuspend,
                    onActivate,
                    onDelete,
                    onResetPassword,
                    widths: [nameWidth, emailWidth, roleWidth, statusWidth, actionsWidth],
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _summaryBar(int total, int responders, int admins, int suspended) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF4EFFB),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _summaryItem("Users", total, const Color(0xFF1E88E5)),
          _summaryItem("Responders", responders, const Color(0xFF38EF7D)),
          _summaryItem("Admins", admins, const Color(0xFF8E24AA)),
          _summaryItem("Suspended", suspended, Colors.redAccent),
        ],
      ),
    );
  }

  Widget _summaryItem(String label, int value, Color color) {
    return Row(
      children: [
        Icon(Icons.circle, color: color, size: 10),
        const SizedBox(width: 6),
        Text("$label: ",
            style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF084C41))),
        Text(value.toString(),
            style: TextStyle(fontWeight: FontWeight.bold, color: color)),
      ],
    );
  }
}

// -------------------- Table Source --------------------
class _UsersSource extends DataTableSource {
  final List<_UserRow> rows;
  final void Function(_UserRow) onSuspend;
  final void Function(_UserRow) onActivate;
  final void Function(_UserRow) onDelete;
  final void Function(_UserRow) onResetPassword;
  final List<double> widths;

  _UsersSource(this.rows, this.onSuspend, this.onActivate, this.onDelete, this.onResetPassword,
      {required this.widths});

  @override
  DataRow? getRow(int index) {
    if (index >= rows.length) return null;
    final r = rows[index];
    return DataRow(
      cells: [
        DataCell(SizedBox(width: widths[0], child: Text(r.name))),
        DataCell(SizedBox(width: widths[1], child: Text(r.email))),
        DataCell(SizedBox(width: widths[2], child: Text(r.role))),
        DataCell(SizedBox(
          width: widths[3],
          child: Text(
            r.status,
            style: TextStyle(
              color: r.status == 'Active' ? Colors.green : Colors.redAccent,
              fontWeight: FontWeight.bold,
            ),
          ),
        )),
        DataCell(SizedBox(
          width: widths[4],
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                icon: const Icon(Icons.key, color: Color(0xFF1E88E5)),
                onPressed: () => onResetPassword(r),
              ),
              IconButton(
                icon: Icon(
                  r.status == 'Active'
                      ? Icons.pause_circle_outline
                      : Icons.play_circle_outline,
                  color: r.status == 'Active' ? Colors.orange : Colors.green,
                ),
                onPressed: () => r.status == 'Active' ? onSuspend(r) : onActivate(r),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                onPressed: () => onDelete(r),
              ),
            ],
          ),
        )),
      ],
    );
  }

  @override
  bool get isRowCountApproximate => false;
  @override
  int get rowCount => rows.length;
  @override
  int get selectedRowCount => 0;
}

// -------------------- Model --------------------
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
