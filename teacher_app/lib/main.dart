import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:geolocator/geolocator.dart';

void main() {
  runApp(const TeacherApp());
}

class TeacherApp extends StatelessWidget {
  const TeacherApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Attendio - BVCOEK Smart Attendance',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFF8FAFC),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.indigo,
          foregroundColor: Colors.white,
          elevation: 2,
        ),
      ),
      home: const AuthGate(),
    );
  }
}

// Global server configuration & Session State
class AppConfig {
  static String baseUrl = "https://smart-attendance-rbsm.onrender.com";
  static String? authToken;
  static Map<String, dynamic>? currentUser;

  static bool isClassTeacher() {
    if (currentUser == null) return false;
    if (currentUser!['is_class_teacher'] == true) return true;
    final tp = currentUser!['teacher_profile'];
    if (tp != null && tp['is_class_teacher'] == true) return true;
    final email = currentUser!['email']?.toString().toLowerCase() ?? '';
    return email == 'upadhye@bvcoek.edu.in' || email == 'teacher@gcek.ac.in';
  }

  static bool isAdmin() {
    if (currentUser == null) return false;
    final role = currentUser!['role']?.toString().toUpperCase() ?? '';
    final email = currentUser!['email']?.toString().toLowerCase() ?? '';
    return role == 'ADMIN' || email == 'admin@gcek.ac.in';
  }
}

enum AppRole { admin, classTeacher, teacher }

// Preset Faculty for Quick Switching
final List<Map<String, String>> presetFaculty = [
  {
    'name': 'Prof. V. A. Upadhye',
    'subject': 'OOMD (CS504) - Class Teacher',
    'email': 'upadhye@bvcoek.edu.in',
    'password': 'Teacher@1234',
  },
  {
    'name': 'Mr. K. P. Nilje',
    'subject': 'AI (Artificial Intelligence, CS501)',
    'email': 'nilje@bvcoek.edu.in',
    'password': 'Teacher@1234',
  },
  {
    'name': 'Dr. S. B. Patil',
    'subject': 'CA (Computer Algorithm, CS502)',
    'email': 'patil@bvcoek.edu.in',
    'password': 'Teacher@1234',
  },
  {
    'name': 'Ms. A. B. Pawar',
    'subject': 'JP (Java Programming, CS503)',
    'email': 'pawar@bvcoek.edu.in',
    'password': 'Teacher@1234',
  },
  {
    'name': 'Ms. M. P. Kulkarni',
    'subject': 'MDM-03 (Minor 3, CS505)',
    'email': 'kulkarni@bvcoek.edu.in',
    'password': 'Teacher@1234',
  },
  {
    'name': 'Ms. S. M. Bagban',
    'subject': 'OE-03 (Elective 3, CS506)',
    'email': 'bagban@bvcoek.edu.in',
    'password': 'Teacher@1234',
  },
];

// -------------------------------------------------------------
// REUSABLE DIALOG HELPERS (EXCEL, TIMETABLE, SERVER, ABOUT)
// -------------------------------------------------------------
void showMasterExcelDialog(BuildContext context) {
  final url = '${AppConfig.baseUrl}/api/reports/export-master-excel';
  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Row(
        children: [
          Icon(Icons.table_chart_rounded, color: Colors.green, size: 28),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Master Excel Report (.xlsx)',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Downloads an official multi-sheet Excel spreadsheet with real-time database calculations:',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.green.shade200),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('📗 Sheet 1: Master Attendance Matrix (Roll 1-77, all subjects)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                  SizedBox(height: 4),
                  Text('🚨 Sheet 2: Defaulters Notice (<50% attendance list)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.red)),
                  SizedBox(height: 4),
                  Text('📅 Sheet 3: Daily Lecture Logs (Every session, IST time, present/absent counts)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                ],
              ),
            ),
            const SizedBox(height: 12),
            const Text('Live Cloud Download URL:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
            const SizedBox(height: 4),
            SelectableText(
              url,
              style: const TextStyle(color: Colors.blue, fontSize: 12, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('Close'),
        ),
      ],
    ),
  );
}

void showTimetableDialog(BuildContext context) {
  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Row(
        children: [
          Icon(Icons.schedule_rounded, color: Colors.indigo, size: 26),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'T.Y. CSE Timetable (Weekly)',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: ListView(
          shrinkWrap: true,
          children: const [
            _TimetableDayTile(
              day: 'Monday',
              slots: [
                '11:30 - 12:30 | OOMD (Prof. Upadhye) - LH2',
                '12:30 - 01:30 | MDM-03 (Ms. Kulkarni) - LH2',
                '02:15 - 04:15 | MDM-03 Lab (Ms. Kulkarni) - L5',
              ],
            ),
            _TimetableDayTile(
              day: 'Tuesday',
              slots: [
                '09:15 - 10:15 | JP (Ms. Pawar) - LH3',
                '10:15 - 11:15 | OOMD (Prof. Upadhye) - LH3',
                '11:30 - 12:30 | CA (Dr. Patil) - L4',
                '12:30 - 01:30 | JP (Ms. Pawar) - L1',
                '02:15 - 04:15 | MDM-03 (Ms. Kulkarni) - L6',
              ],
            ),
            _TimetableDayTile(
              day: 'Wednesday',
              slots: [
                '09:15 - 10:15 | OE-03 (Ms. Bagban) - LH2',
                '10:15 - 11:15 | CA (Dr. Patil) - LH2',
                '11:30 - 12:30 | AI (Mr. Nilje) - LH2',
                '12:30 - 01:30 | MDM-03 (Ms. Kulkarni) - LH2',
                '02:15 - 04:15 | MDM-03 (Ms. Kulkarni) - L6',
              ],
            ),
            _TimetableDayTile(
              day: 'Thursday',
              slots: [
                '09:15 - 11:15 | OOMD (Prof. Upadhye) - L5',
                '11:30 - 01:30 | JP (Ms. Pawar) - L8',
                '02:15 - 04:15 | MDM-03 (Ms. Kulkarni) - L6',
              ],
            ),
            _TimetableDayTile(
              day: 'Friday',
              slots: [
                '09:15 - 10:15 | OE-03 (Ms. Bagban) - LH2',
                '10:15 - 11:15 | CA (Dr. Patil) - LH2',
                '11:30 - 12:30 | AI (Mr. Nilje) - LH2',
                '12:30 - 01:30 | MDM-03 (Ms. Kulkarni) - LH2',
                '02:15 - 04:15 | OOMD (Prof. Upadhye) - L5',
              ],
            ),
            _TimetableDayTile(
              day: 'Saturday',
              slots: [
                '09:00 - 09:55 | OOMD (Prof. Upadhye) - LH2',
                '09:55 - 10:50 | JP (Ms. Pawar) - LH2',
                '11:10 - 12:05 | CA (Dr. Patil) - LH3',
                '12:05 - 01:00 | AI (Mr. Nilje) - LH3',
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Close')),
      ],
    ),
  );
}

class _TimetableDayTile extends StatelessWidget {
  final String day;
  final List<String> slots;
  const _TimetableDayTile({required this.day, required this.slots});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      elevation: 0.5,
      color: Colors.indigo.shade50.withValues(alpha: 0.5),
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(day, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.indigo, fontSize: 13)),
            const SizedBox(height: 4),
            ...slots.map((s) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 1),
              child: Text('• $s', style: const TextStyle(fontSize: 11)),
            )),
          ],
        ),
      ),
    );
  }
}

void showServerStatusDialog(BuildContext context) {
  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Row(
        children: [
          Icon(Icons.dns_rounded, color: Colors.blue, size: 26),
          SizedBox(width: 10),
          Expanded(child: Text('Cloud Server Status', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Container(width: 10, height: 10, decoration: const BoxDecoration(color: Colors.green, shape: BoxShape.circle)),
                const SizedBox(width: 8),
                const Text('Render Cloud: ONLINE', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green)),
              ],
            ),
            const SizedBox(height: 10),
            Text('Base URL: ${AppConfig.baseUrl}', style: const TextStyle(fontSize: 12)),
            const SizedBox(height: 6),
            const Text('Timezone: Asia/Kolkata (IST, UTC+5:30)', style: TextStyle(fontSize: 12)),
            const SizedBox(height: 6),
            const Text('Phone Proximity Geofence: 50.0 meters', style: TextStyle(fontSize: 12)),
            const SizedBox(height: 6),
            const Text('Dynamic Token Rotation: 80 seconds', style: TextStyle(fontSize: 12)),
            const SizedBox(height: 6),
            const Text('Defaulter Criteria: Strict < 50.0%', style: TextStyle(fontSize: 12, color: Colors.red)),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('OK')),
      ],
    ),
  );
}

void showAboutAttendioDialog(BuildContext context) {
  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Row(
        children: [
          Icon(Icons.school_rounded, color: Colors.indigo, size: 28),
          SizedBox(width: 10),
          Expanded(child: Text('Attendio v2.4', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
        ],
      ),
      content: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            "Bharati Vidyapeeth's College of Engineering, Kolhapur (BVCOEK)",
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.indigo),
          ),
          SizedBox(height: 4),
          Text("Department of Computer Science & Engineering (T.Y. CSE)", style: TextStyle(fontSize: 12, color: Colors.grey)),
          SizedBox(height: 12),
          Text(
            "An enterprise smart attendance system engineered with 3-tier role architecture:\n\n"
            "• 🏫 College Admin: Manage faculty, subjects, & master sheets\n"
            "• 🎓 Class Teacher: 50% Defaulter tagging, student breakdown & 6-month lecture logs\n"
            "• 👨‍🏫 Subject Faculty: 50m phone GPS geofence & 80s rotating QR code\n"
            "• 📊 Automated 3-Sheet Master Excel Export",
            style: TextStyle(fontSize: 12),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Close')),
      ],
    ),
  );
}

// -------------------------------------------------------------
// NAVIGATION DRAWER (3 HORIZONTAL LINES MENU)
// -------------------------------------------------------------
class AttendioDrawer extends StatelessWidget {
  final String activeScreen; // 'login', 'admin', 'class_teacher', 'teacher'
  const AttendioDrawer({super.key, this.activeScreen = ''});

  @override
  Widget build(BuildContext context) {
    final user = AppConfig.currentUser;
    final isCT = AppConfig.isClassTeacher();
    final isAdmin = AppConfig.isAdmin();

    return Drawer(
      child: Column(
        children: [
          // Realistic University Drawer Header
          Container(
            width: double.infinity,
            padding: const EdgeInsets.only(top: 50, bottom: 20, left: 20, right: 20),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.indigo, Color(0xFF1E1B4B)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.school_rounded, color: Colors.white, size: 36),
                    ),
                    const SizedBox(width: 12),
                    const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Attendio', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                        Text('BVCOEK Kolhapur', style: TextStyle(color: Colors.amber, fontSize: 12, fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Text(
                  user?['full_name'] ?? (isAdmin ? 'College Administrator' : (isCT ? 'Prof. V. A. Upadhye' : 'Faculty Member')),
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  user?['email'] ?? 'BVCOEK T.Y. CSE Department',
                  style: TextStyle(color: Colors.indigo.shade100, fontSize: 12),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: isAdmin
                        ? Colors.purple
                        : (isCT ? Colors.amber : Colors.indigo.shade300),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    isAdmin
                        ? '🏫 COLLEGE ADMIN'
                        : (isCT ? '🎓 CLASS TEACHER' : '👨‍🏫 SUBJECT FACULTY'),
                    style: TextStyle(
                      color: isCT ? Colors.black87 : Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Navigation Links
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                const SizedBox(height: 8),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  child: Text('ROLE PORTALS', style: TextStyle(color: Colors.grey, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1)),
                ),

                // 1. Admin Console
                ListTile(
                  leading: const Icon(Icons.admin_panel_settings_rounded, color: Colors.purple),
                  title: const Text('Admin Console', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                  subtitle: const Text('Add teachers, subjects & system matrix', style: TextStyle(fontSize: 11)),
                  selected: activeScreen == 'admin',
                  selectedTileColor: Colors.purple.shade50,
                  onTap: () {
                    Navigator.of(context).pop();
                    if (activeScreen != 'admin') {
                      Navigator.of(context).pushReplacement(
                        MaterialPageRoute(builder: (_) => const AdminDashboardScreen()),
                      );
                    }
                  },
                ),

                // 2. Class Teacher Portal
                ListTile(
                  leading: const Icon(Icons.school_rounded, color: Colors.amber),
                  title: const Text('Class Teacher Portal', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                  subtitle: const Text('Defaulters (<50%), 77 students & lecture logs', style: TextStyle(fontSize: 11)),
                  selected: activeScreen == 'class_teacher',
                  selectedTileColor: Colors.amber.shade50,
                  onTap: () {
                    Navigator.of(context).pop();
                    if (activeScreen != 'class_teacher') {
                      Navigator.of(context).pushReplacement(
                        MaterialPageRoute(builder: (_) => const ClassTeacherPortalScreen()),
                      );
                    }
                  },
                ),

                // 3. Subject Faculty Console
                ListTile(
                  leading: const Icon(Icons.qr_code_scanner_rounded, color: Colors.indigo),
                  title: const Text('Subject Teacher Console', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                  subtitle: const Text('80s rotating QR & 50m GPS attendance', style: TextStyle(fontSize: 11)),
                  selected: activeScreen == 'teacher',
                  selectedTileColor: Colors.indigo.shade50,
                  onTap: () {
                    Navigator.of(context).pop();
                    if (activeScreen != 'teacher') {
                      Navigator.of(context).pushReplacement(
                        MaterialPageRoute(builder: (_) => const TeacherDashboardScreen()),
                      );
                    }
                  },
                ),

                const Divider(),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  child: Text('QUICK TOOLS & DATA', style: TextStyle(color: Colors.grey, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1)),
                ),

                ListTile(
                  leading: const Icon(Icons.file_download_outlined, color: Colors.green),
                  title: const Text('Download Master Excel (.xlsx)', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                  subtitle: const Text('All 3 sheets: Matrix, Defaulters & Daily Log', style: TextStyle(fontSize: 11)),
                  onTap: () {
                    Navigator.of(context).pop();
                    showMasterExcelDialog(context);
                  },
                ),

                ListTile(
                  leading: const Icon(Icons.schedule_rounded, color: Colors.indigo),
                  title: const Text('T.Y. CSE Timetable', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                  subtitle: const Text('Monday to Saturday lecture schedule', style: TextStyle(fontSize: 11)),
                  onTap: () {
                    Navigator.of(context).pop();
                    showTimetableDialog(context);
                  },
                ),

                ListTile(
                  leading: const Icon(Icons.dns_rounded, color: Colors.blue),
                  title: const Text('Server Diagnostics', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                  subtitle: const Text('Render cloud backend & GPS specs', style: TextStyle(fontSize: 11)),
                  onTap: () {
                    Navigator.of(context).pop();
                    showServerStatusDialog(context);
                  },
                ),

                ListTile(
                  leading: const Icon(Icons.info_outline_rounded, color: Colors.teal),
                  title: const Text('About BVCOEK Attendio', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                  onTap: () {
                    Navigator.of(context).pop();
                    showAboutAttendioDialog(context);
                  },
                ),

                const Divider(),

                ListTile(
                  leading: const Icon(Icons.logout_rounded, color: Colors.red),
                  title: const Text('Sign Out / Switch Role', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.red)),
                  onTap: () {
                    AppConfig.authToken = null;
                    AppConfig.currentUser = null;
                    Navigator.of(context).pop();
                    Navigator.of(context).pushReplacement(
                      MaterialPageRoute(builder: (_) => const AuthGate()),
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// -------------------------------------------------------------
// 3-DOTS KEBAB POPUP MENU IN APPBAR
// -------------------------------------------------------------
class AttendioPopupMenu extends StatelessWidget {
  const AttendioPopupMenu({super.key});

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert_rounded),
      tooltip: 'Options & Tools',
      onSelected: (val) {
        if (val == 'excel') {
          showMasterExcelDialog(context);
        } else if (val == 'timetable') {
          showTimetableDialog(context);
        } else if (val == 'server') {
          showServerStatusDialog(context);
        } else if (val == 'about') {
          showAboutAttendioDialog(context);
        } else if (val == 'logout') {
          AppConfig.authToken = null;
          AppConfig.currentUser = null;
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => const AuthGate()),
          );
        }
      },
      itemBuilder: (ctx) => [
        const PopupMenuItem(
          value: 'excel',
          child: Row(
            children: [
              Icon(Icons.file_download_outlined, color: Colors.green, size: 20),
              SizedBox(width: 10),
              Text('Download Master Excel'),
            ],
          ),
        ),
        const PopupMenuItem(
          value: 'timetable',
          child: Row(
            children: [
              Icon(Icons.schedule_rounded, color: Colors.indigo, size: 20),
              SizedBox(width: 10),
              Text('Weekly Timetable'),
            ],
          ),
        ),
        const PopupMenuItem(
          value: 'server',
          child: Row(
            children: [
              Icon(Icons.dns_rounded, color: Colors.blue, size: 20),
              SizedBox(width: 10),
              Text('Server Status'),
            ],
          ),
        ),
        const PopupMenuItem(
          value: 'about',
          child: Row(
            children: [
              Icon(Icons.info_outline_rounded, color: Colors.teal, size: 20),
              SizedBox(width: 10),
              Text('About Attendio'),
            ],
          ),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem(
          value: 'logout',
          child: Row(
            children: [
              Icon(Icons.logout_rounded, color: Colors.red, size: 20),
              SizedBox(width: 10),
              Text('Logout / Switch Role', style: TextStyle(color: Colors.red)),
            ],
          ),
        ),
      ],
    );
  }
}

// -------------------------------------------------------------
// AUTH GATE & MULTI-ROLE LOGIN SCREEN (ADMIN / CLASS TEACHER / TEACHER)
// -------------------------------------------------------------
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  AppRole _selectedRole = AppRole.classTeacher;

  final _emailController = TextEditingController(text: "upadhye@bvcoek.edu.in");
  final _passwordController = TextEditingController(text: "Teacher@1234");
  final _serverUrlController = TextEditingController(text: AppConfig.baseUrl);

  String _selectedTeacherEmail = 'upadhye@bvcoek.edu.in';
  bool _isLoading = false;
  String? _errorMessage;

  void _onRoleChanged(AppRole role) {
    setState(() {
      _selectedRole = role;
      _errorMessage = null;

      if (role == AppRole.admin) {
        _emailController.text = "admin@gcek.ac.in";
        _passwordController.text = "Admin@1234";
      } else if (role == AppRole.classTeacher) {
        _emailController.text = "upadhye@bvcoek.edu.in";
        _passwordController.text = "Teacher@1234";
      } else {
        // Teacher
        final t = presetFaculty.firstWhere(
          (f) => f['email'] == _selectedTeacherEmail,
          orElse: () => presetFaculty[0],
        );
        _emailController.text = t['email']!;
        _passwordController.text = t['password']!;
      }
    });
  }

  Future<void> _login() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    AppConfig.baseUrl = _serverUrlController.text.trim();

    try {
      final response = await http.post(
        Uri.parse('${AppConfig.baseUrl}/api/auth/login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'email': _emailController.text.trim(),
          'password': _passwordController.text,
        }),
      ).timeout(const Duration(seconds: 60));

      final data = jsonDecode(response.body);

      if (response.statusCode == 200 && data['status'] == 'success') {
        AppConfig.authToken = data['auth_token'];
        AppConfig.currentUser = data['user'];

        if (mounted) {
          // Route according to chosen role
          if (_selectedRole == AppRole.admin || AppConfig.isAdmin()) {
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(builder: (_) => const AdminDashboardScreen()),
            );
          } else if (_selectedRole == AppRole.classTeacher) {
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(builder: (_) => const ClassTeacherPortalScreen()),
            );
          } else {
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(builder: (_) => const TeacherDashboardScreen()),
            );
          }
        }
      } else {
        setState(() {
          _errorMessage = data['message'] ?? 'Login failed. Please check credentials.';
        });
      }
    } on TimeoutException {
      setState(() {
        _errorMessage = 'Cloud server waking up from sleep. Please tap Log In again!';
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Connection error: Unable to reach backend server.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _bypassToSelectedRole() {
    if (_selectedRole == AppRole.admin) {
      AppConfig.currentUser = {
        'full_name': 'College Administrator',
        'email': 'admin@gcek.ac.in',
        'role': 'ADMIN',
      };
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const AdminDashboardScreen()),
      );
    } else if (_selectedRole == AppRole.classTeacher) {
      AppConfig.currentUser = {
        'full_name': 'Prof. V. A. Upadhye',
        'email': 'upadhye@bvcoek.edu.in',
        'role': 'TEACHER',
        'is_class_teacher': true,
      };
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const ClassTeacherPortalScreen()),
      );
    } else {
      AppConfig.currentUser = {
        'full_name': 'Subject Faculty Member',
        'email': _emailController.text,
        'role': 'TEACHER',
        'is_class_teacher': false,
      };
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const TeacherDashboardScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Attendio BVCOEK'),
        actions: const [
          AttendioPopupMenu(),
        ],
      ),
      drawer: const AttendioDrawer(activeScreen: 'login'),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20.0),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Card(
              elevation: 5,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 28.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // College Branding Header
                    Center(
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.indigo.shade50,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.school_rounded, size: 48, color: Colors.indigo),
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'Attendio',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: Colors.indigo),
                    ),
                    const Text(
                      "Bharati Vidyapeeth's College of Engg., Kolhapur\nT.Y. Computer Science & Engineering",
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12, color: Colors.grey, height: 1.3),
                    ),
                    const SizedBox(height: 22),

                    // ---------------------------------------------------------
                    // 3 EXPLICIT ROLE SELECTOR TABS (ADMIN / CLASS TEACHER / TEACHER)
                    // ---------------------------------------------------------
                    const Text(
                      'Select Your Portal Role:',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.black87),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        // Option 1: Admin
                        Expanded(
                          child: _RoleTabButton(
                            title: 'Admin',
                            icon: Icons.admin_panel_settings_rounded,
                            isSelected: _selectedRole == AppRole.admin,
                            activeColor: Colors.purple,
                            onTap: () => _onRoleChanged(AppRole.admin),
                          ),
                        ),
                        const SizedBox(width: 8),
                        // Option 2: Class Teacher
                        Expanded(
                          child: _RoleTabButton(
                            title: 'Class Teacher',
                            icon: Icons.school_rounded,
                            isSelected: _selectedRole == AppRole.classTeacher,
                            activeColor: Colors.amber.shade800,
                            onTap: () => _onRoleChanged(AppRole.classTeacher),
                          ),
                        ),
                        const SizedBox(width: 8),
                        // Option 3: Teacher
                        Expanded(
                          child: _RoleTabButton(
                            title: 'Teacher',
                            icon: Icons.person_rounded,
                            isSelected: _selectedRole == AppRole.teacher,
                            activeColor: Colors.indigo,
                            onTap: () => _onRoleChanged(AppRole.teacher),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Role Details & Responsibilities Card
                    _buildRoleBanner(),
                    const SizedBox(height: 16),

                    // If Teacher Role: Quick Faculty Dropdown
                    if (_selectedRole == AppRole.teacher) ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.indigo.shade50,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.indigo.shade200),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              '👨‍🏫 Quick Select Subject Faculty:',
                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.indigo),
                            ),
                            const SizedBox(height: 8),
                            DropdownButtonFormField<String>(
                              isExpanded: true,
                              decoration: const InputDecoration(
                                contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                border: OutlineInputBorder(),
                                fillColor: Colors.white,
                                filled: true,
                              ),
                              value: _selectedTeacherEmail,
                              items: presetFaculty.map((f) {
                                return DropdownMenuItem<String>(
                                  value: f['email'],
                                  child: Text(
                                    '${f['name']} (${f['subject']})',
                                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                );
                              }).toList(),
                              onChanged: (email) {
                                if (email != null) {
                                  final fac = presetFaculty.firstWhere((f) => f['email'] == email);
                                  setState(() {
                                    _selectedTeacherEmail = email;
                                    _emailController.text = fac['email']!;
                                    _passwordController.text = fac['password']!;
                                  });
                                }
                              },
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],

                    if (_errorMessage != null)
                      Container(
                        padding: const EdgeInsets.all(12),
                        margin: const EdgeInsets.only(bottom: 16),
                        decoration: BoxDecoration(
                          color: Colors.red.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.red.shade200),
                        ),
                        child: Text(
                          _errorMessage!,
                          style: TextStyle(color: Colors.red.shade800, fontSize: 13),
                        ),
                      ),

                    TextField(
                      controller: _emailController,
                      decoration: const InputDecoration(
                        labelText: 'Email Address',
                        prefixIcon: Icon(Icons.email_outlined),
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                      ),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: _passwordController,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: 'Password',
                        prefixIcon: Icon(Icons.lock_outline),
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                      ),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: _serverUrlController,
                      decoration: const InputDecoration(
                        labelText: 'Render Backend Server URL',
                        prefixIcon: Icon(Icons.dns_outlined),
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Login Button customized per role
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _selectedRole == AppRole.admin
                            ? Colors.purple
                            : (_selectedRole == AppRole.classTeacher ? Colors.amber.shade800 : Colors.indigo),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      onPressed: _isLoading ? null : _login,
                      child: _isLoading
                          ? const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                SizedBox(
                                  height: 18,
                                  width: 18,
                                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                                ),
                                SizedBox(width: 12),
                                Text('Connecting...', style: TextStyle(fontWeight: FontWeight.bold)),
                              ],
                            )
                          : Text(
                              _selectedRole == AppRole.admin
                                  ? 'Log In to Admin Console'
                                  : (_selectedRole == AppRole.classTeacher
                                      ? 'Log In to Class Teacher Portal'
                                      : 'Log In to Subject Console'),
                              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                            ),
                    ),
                    const SizedBox(height: 10),

                    // Direct Demo Preview Button
                    TextButton.icon(
                      onPressed: _bypassToSelectedRole,
                      icon: const Icon(Icons.bolt_rounded, size: 18),
                      label: Text(
                        'Direct Open ${_selectedRole == AppRole.admin ? "Admin" : (_selectedRole == AppRole.classTeacher ? "Class Teacher" : "Teacher")} Preview',
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRoleBanner() {
    if (_selectedRole == AppRole.admin) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.purple.shade50,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.purple.shade200),
        ),
        child: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.shield_rounded, color: Colors.purple, size: 18),
                SizedBox(width: 8),
                Text('Admin Privileges Active', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.purple, fontSize: 13)),
              ],
            ),
            SizedBox(height: 6),
            Text(
              '• Add new faculty members & assign subjects\n'
              '• Add new subjects & course curriculum\n'
              '• View master matrix & export monthly Excel (.xlsx)\n'
              '• Manage college 50m phone geofence boundary',
              style: TextStyle(fontSize: 11, height: 1.4, color: Colors.black87),
            ),
          ],
        ),
      );
    } else if (_selectedRole == AppRole.classTeacher) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.amber.shade50,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.amber.shade300),
        ),
        child: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.stars_rounded, color: Colors.black87, size: 18),
                SizedBox(width: 8),
                Text('Class Teacher: Prof. V. A. Upadhye', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black87, fontSize: 13)),
              ],
            ),
            SizedBox(height: 6),
            Text(
              '• Automated Defaulters list (<50% attendance)\n'
              '• Complete roster of all 77 students (PRN 2024071601 - 2024071677)\n'
              '• Historical lecture logs with present/absent student breakdown\n'
              '• Start OOMD lecture according to timetable',
              style: TextStyle(fontSize: 11, height: 1.4, color: Colors.black87),
            ),
          ],
        ),
      );
    } else {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.indigo.shade50,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.indigo.shade200),
        ),
        child: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.co_present_rounded, color: Colors.indigo, size: 18),
                SizedBox(width: 8),
                Text('Subject Teacher Console', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.indigo, fontSize: 13)),
              ],
            ),
            SizedBox(height: 6),
            Text(
              '• Mark attendance for your assigned timetable subject only\n'
              '• Strict 50-meter radius geofence tied to teacher phone GPS\n'
              '• Dynamic rotating QR code refreshing every 80 seconds\n'
              '• Real-time student check-in list with exact distance',
              style: TextStyle(fontSize: 11, height: 1.4, color: Colors.black87),
            ),
          ],
        ),
      );
    }
  }
}

class _RoleTabButton extends StatelessWidget {
  final String title;
  final IconData icon;
  final bool isSelected;
  final Color activeColor;
  final VoidCallback onTap;

  const _RoleTabButton({
    required this.title,
    required this.icon,
    required this.isSelected,
    required this.activeColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        decoration: BoxDecoration(
          color: isSelected ? activeColor : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected ? activeColor : Colors.grey.shade300,
            width: isSelected ? 2 : 1,
          ),
          boxShadow: isSelected
              ? [BoxShadow(color: activeColor.withValues(alpha: 0.3), blurRadius: 6, offset: const Offset(0, 2))]
              : null,
        ),
        child: Column(
          children: [
            Icon(
              icon,
              size: 22,
              color: isSelected ? Colors.white : Colors.grey.shade700,
            ),
            const SizedBox(height: 4),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                color: isSelected ? Colors.white : Colors.grey.shade800,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

// -------------------------------------------------------------
// COLLEGE ADMIN DASHBOARD SCREEN
// -------------------------------------------------------------
class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _isLoading = true;
  String? _errorMessage;

  Map<String, dynamic>? _stats;
  List<dynamic> _teachers = [];
  List<dynamic> _subjects = [];
  List<dynamic> _recentSessions = [];
  int _defaultersCount = 0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _fetchAdminData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _fetchAdminData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // 1. Fetch dashboard stats
      final statsRes = await http.get(
        Uri.parse('${AppConfig.baseUrl}/api/admin/dashboard-stats'),
      ).timeout(const Duration(seconds: 40));

      // 2. Fetch subjects
      final subjRes = await http.get(
        Uri.parse('${AppConfig.baseUrl}/api/admin/subjects'),
      ).timeout(const Duration(seconds: 40));

      // 3. Fetch defaulters count
      final defRes = await http.get(
        Uri.parse('${AppConfig.baseUrl}/api/class-teacher/dashboard-data'),
      ).timeout(const Duration(seconds: 40));

      if (statsRes.statusCode == 200) {
        final statsData = jsonDecode(statsRes.body);
        final subjData = subjRes.statusCode == 200 ? jsonDecode(subjRes.body) : {'subjects': []};
        final defData = defRes.statusCode == 200 ? jsonDecode(defRes.body) : {'defaulters': []};

        setState(() {
          _stats = statsData;
          _teachers = statsData['teachers'] ?? [];
          _recentSessions = statsData['recent_sessions'] ?? [];
          _subjects = subjData['subjects'] ?? [];
          _defaultersCount = (defData['defaulters'] as List?)?.length ?? 0;
          _isLoading = false;
        });
      } else {
        setState(() {
          _errorMessage = 'Failed to load administrator records.';
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Error connecting to backend server.';
        _isLoading = false;
      });
    }
  }

  // Admin Add Faculty Dialog
  void _showAddTeacherDialog() {
    final nameCtrl = TextEditingController();
    final emailCtrl = TextEditingController();
    final empIdCtrl = TextEditingController();
    final desigCtrl = TextEditingController(text: 'Assistant Professor');
    bool isCT = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Icon(Icons.person_add_rounded, color: Colors.purple),
              SizedBox(width: 10),
              Text('Register New Faculty', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(labelText: 'Full Name (e.g. Dr. A. K. Sharma)', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: emailCtrl,
                  decoration: const InputDecoration(labelText: 'College Email (e.g. sharma@bvcoek.edu.in)', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: empIdCtrl,
                  decoration: const InputDecoration(labelText: 'Employee ID (Optional)', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: desigCtrl,
                  decoration: const InputDecoration(labelText: 'Designation', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 10),
                CheckboxListTile(
                  title: const Text('Designate as Class Teacher', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                  value: isCT,
                  activeColor: Colors.purple,
                  contentPadding: EdgeInsets.zero,
                  onChanged: (val) {
                    setDialogState(() {
                      isCT = val ?? false;
                    });
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.purple, foregroundColor: Colors.white),
              onPressed: () async {
                final name = nameCtrl.text.trim();
                final email = emailCtrl.text.trim();
                final messenger = ScaffoldMessenger.of(context);
                if (name.isEmpty || email.isEmpty) {
                  messenger.showSnackBar(
                    const SnackBar(content: Text('Please enter name and email!')),
                  );
                  return;
                }

                Navigator.of(ctx).pop();
                try {
                  final res = await http.post(
                    Uri.parse('${AppConfig.baseUrl}/api/admin/teachers/add'),
                    headers: {'Content-Type': 'application/json'},
                    body: jsonEncode({
                      'full_name': name,
                      'email': email,
                      'employee_id': empIdCtrl.text.trim(),
                      'designation': desigCtrl.text.trim(),
                      'is_class_teacher': isCT,
                      'password': 'Teacher@1234',
                    }),
                  );

                  final data = jsonDecode(res.body);
                  if (res.statusCode == 201 && data['status'] == 'success') {
                    messenger.showSnackBar(
                      SnackBar(content: Text('Faculty $name registered successfully!'), backgroundColor: Colors.green),
                    );
                    _fetchAdminData();
                  } else {
                    messenger.showSnackBar(
                      SnackBar(content: Text(data['message'] ?? 'Failed to add faculty.'), backgroundColor: Colors.red),
                    );
                  }
                } catch (e) {
                  messenger.showSnackBar(
                    const SnackBar(content: Text('Network error adding faculty.')),
                  );
                }
              },
              child: const Text('Add Faculty'),
            ),
          ],
        ),
      ),
    );
  }

  // Admin Add Subject Dialog
  void _showAddSubjectDialog() {
    final nameCtrl = TextEditingController();
    final codeCtrl = TextEditingController();
    final semCtrl = TextEditingController(text: '5');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.library_books_rounded, color: Colors.purple),
            SizedBox(width: 10),
            Text('Add Course Subject', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(labelText: 'Subject Name (e.g. Cloud Computing)', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: codeCtrl,
                decoration: const InputDecoration(labelText: 'Course Code (e.g. CS507)', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: semCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Semester', border: OutlineInputBorder()),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.purple, foregroundColor: Colors.white),
            onPressed: () async {
              final name = nameCtrl.text.trim();
              final code = codeCtrl.text.trim();
              final messenger = ScaffoldMessenger.of(context);
              if (name.isEmpty || code.isEmpty) {
                messenger.showSnackBar(
                  const SnackBar(content: Text('Please enter subject name and code!')),
                );
                return;
              }

              Navigator.of(ctx).pop();
              try {
                final res = await http.post(
                  Uri.parse('${AppConfig.baseUrl}/api/admin/subjects/add'),
                  headers: {'Content-Type': 'application/json'},
                  body: jsonEncode({
                    'name': name,
                    'code': code,
                    'semester': int.tryParse(semCtrl.text) ?? 5,
                  }),
                );

                final data = jsonDecode(res.body);
                if (res.statusCode == 201 && data['status'] == 'success') {
                  messenger.showSnackBar(
                    SnackBar(content: Text('Subject $name ($code) added successfully!'), backgroundColor: Colors.green),
                  );
                  _fetchAdminData();
                } else {
                  messenger.showSnackBar(
                    SnackBar(content: Text(data['message'] ?? 'Failed to add subject.'), backgroundColor: Colors.red),
                  );
                }
              } catch (e) {
                messenger.showSnackBar(
                  const SnackBar(content: Text('Network error adding subject.')),
                );
              }
            },
            child: const Text('Add Subject'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.purple.shade900,
        title: Text(_stats != null ? 'Admin Console (${_stats!['college']?['code'] ?? 'BVCOEK'})' : 'Attendio Admin Console'),
        actions: [
          IconButton(
            icon: const Icon(Icons.file_download_outlined),
            tooltip: 'Download Master Excel',
            onPressed: () => showMasterExcelDialog(context),
          ),
          const AttendioPopupMenu(),
        ],
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.purple.shade200,
          indicatorColor: Colors.amber,
          indicatorWeight: 3,
          tabs: [
            Tab(icon: const Icon(Icons.people_alt_rounded), text: 'Faculty (${_teachers.length})'),
            Tab(icon: const Icon(Icons.menu_book_rounded), text: 'Subjects (${_subjects.length})'),
            Tab(icon: const Icon(Icons.history_rounded), text: 'Sessions (${_recentSessions.length})'),
          ],
        ),
      ),
      drawer: const AttendioDrawer(activeScreen: 'admin'),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.purple))
          : _errorMessage != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(_errorMessage!, style: const TextStyle(color: Colors.red)),
                      const SizedBox(height: 12),
                      ElevatedButton(onPressed: _fetchAdminData, child: const Text('Retry')),
                    ],
                  ),
                )
              : Column(
                  children: [
                    // Top Overview Metrics
                    Container(
                      padding: const EdgeInsets.all(12),
                      color: Colors.purple.shade50,
                      child: Column(
                        children: [
                          Row(
                            children: [
                              _buildStatCard('Enrolled Students', '77', Icons.school, Colors.indigo),
                              _buildStatCard('Faculty Members', '${_teachers.length}', Icons.groups, Colors.purple),
                              _buildStatCard('Course Subjects', '${_subjects.length}', Icons.library_books, Colors.teal),
                              _buildStatCard('Defaulters (<50%)', '$_defaultersCount', Icons.warning_rounded, Colors.red),
                            ],
                          ),
                          const SizedBox(height: 8),
                          // Action Shortcut Row
                          Row(
                            children: [
                              Expanded(
                                child: ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.purple,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(vertical: 8),
                                  ),
                                  onPressed: _showAddTeacherDialog,
                                  icon: const Icon(Icons.person_add, size: 16),
                                  label: const Text('Add Faculty', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.purple.shade700,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(vertical: 8),
                                  ),
                                  onPressed: _showAddSubjectDialog,
                                  icon: const Icon(Icons.add_box, size: 16),
                                  label: const Text('Add Subject', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.green.shade700,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(vertical: 8),
                                  ),
                                  onPressed: () => showMasterExcelDialog(context),
                                  icon: const Icon(Icons.table_chart, size: 16),
                                  label: const Text('Master Excel', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    // Tab View Contents
                    Expanded(
                      child: TabBarView(
                        controller: _tabController,
                        children: [
                          // Tab 1: Faculty List
                          ListView.builder(
                            padding: const EdgeInsets.all(12),
                            itemCount: _teachers.length,
                            itemBuilder: (context, index) {
                              final t = _teachers[index];
                              final bool isCT = t['is_class_teacher'] == true;
                              return Card(
                                margin: const EdgeInsets.symmetric(vertical: 4),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                child: ListTile(
                                  leading: CircleAvatar(
                                    backgroundColor: isCT ? Colors.amber.shade100 : Colors.purple.shade100,
                                    child: Icon(
                                      isCT ? Icons.stars_rounded : Icons.person_rounded,
                                      color: isCT ? Colors.amber.shade900 : Colors.purple,
                                    ),
                                  ),
                                  title: Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          t['full_name'] ?? 'Faculty Member',
                                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                        ),
                                      ),
                                      if (isCT)
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(color: Colors.amber, borderRadius: BorderRadius.circular(4)),
                                          child: const Text('CLASS TEACHER', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800)),
                                        ),
                                    ],
                                  ),
                                  subtitle: Text(
                                    '${t['designation'] ?? 'Professor'} • ${t['email']}\nID: ${t['employee_id'] ?? 'FAC'}',
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                ),
                              );
                            },
                          ),

                          // Tab 2: Course Subjects
                          ListView.builder(
                            padding: const EdgeInsets.all(12),
                            itemCount: _subjects.length,
                            itemBuilder: (context, index) {
                              final s = _subjects[index];
                              return Card(
                                margin: const EdgeInsets.symmetric(vertical: 4),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                child: ListTile(
                                  leading: CircleAvatar(
                                    backgroundColor: Colors.teal.shade100,
                                    child: Text(
                                      '${s['code'] ?? 'SUB'}'.substring(0, (s['code'] ?? 'SUB').length > 4 ? 4 : (s['code'] ?? 'SUB').length),
                                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.teal.shade900),
                                    ),
                                  ),
                                  title: Text(s['name'] ?? 'Subject', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                                  subtitle: Text('Code: ${s['code']} | Semester: ${s['semester'] ?? 5} | CSE Dept.', style: const TextStyle(fontSize: 12)),
                                  trailing: const Icon(Icons.check_circle_rounded, color: Colors.teal, size: 20),
                                ),
                              );
                            },
                          ),

                          // Tab 3: Recent Conducted Sessions
                          _recentSessions.isEmpty
                              ? const Center(child: Text('No conducted lecture sessions yet.'))
                              : ListView.builder(
                                  padding: const EdgeInsets.all(12),
                                  itemCount: _recentSessions.length,
                                  itemBuilder: (context, index) {
                                    final l = _recentSessions[index];
                                    return Card(
                                      margin: const EdgeInsets.symmetric(vertical: 4),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                      child: ListTile(
                                        leading: const CircleAvatar(
                                          backgroundColor: Colors.indigo,
                                          child: Icon(Icons.class_rounded, color: Colors.white, size: 18),
                                        ),
                                        title: Text(
                                          '${l['subject_name']} (${l['subject_code']})',
                                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                        ),
                                        subtitle: Text(
                                          '${l['started_at_ist'] ?? l['started_at']}\nTeacher: ${l['teacher_name']}',
                                          style: const TextStyle(fontSize: 12),
                                        ),
                                        trailing: Column(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          crossAxisAlignment: CrossAxisAlignment.end,
                                          children: [
                                            Text(
                                              '${l['attendance_count'] ?? 0} Present',
                                              style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green, fontSize: 13),
                                            ),
                                            const Text('77 Enrolled', style: TextStyle(fontSize: 11, color: Colors.grey)),
                                          ],
                                        ),
                                      ),
                                    );
                                  },
                                ),
                        ],
                      ),
                    ),
                  ],
                ),
    );
  }

  Widget _buildStatCard(String label, String value, IconData icon, Color color) {
    return Expanded(
      child: Card(
        elevation: 1,
        color: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          child: Column(
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(height: 2),
              Text(value, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: color)),
              Text(label, textAlign: TextAlign.center, style: const TextStyle(fontSize: 9, color: Colors.grey), maxLines: 1),
            ],
          ),
        ),
      ),
    );
  }
}

// -------------------------------------------------------------
// TEACHER DASHBOARD SCREEN (SUBJECT FACULTY CONSOLE)
// -------------------------------------------------------------
class TeacherDashboardScreen extends StatefulWidget {
  const TeacherDashboardScreen({super.key});

  @override
  State<TeacherDashboardScreen> createState() => _TeacherDashboardScreenState();
}

class _TeacherDashboardScreenState extends State<TeacherDashboardScreen> {
  String generatedUrl = "";
  String activeSessionId = "";
  String currentToken = "";
  int secondsRemaining = 80;
  bool isSessionActive = false;
  bool isLoading = false;
  List<dynamic> attendanceList = [];
  Timer? _rotationTimer;

  List<dynamic> todaySlots = [];
  Map<String, dynamic>? selectedSlot;
  String currentSubjectName = "";
  String currentRoom = "";

  Position? _currentTeacherPosition;
  bool _isLocating = false;
  String _locationStatus = "Detecting phone GPS...";
  double _activeSessionTeacherLat = 16.6631;
  double _activeSessionTeacherLng = 74.2642;

  @override
  void initState() {
    super.initState();
    _getTeacherLocation();
    fetchTodayTimetable();
    fetchAttendanceReport();
  }

  Future<Position?> _getTeacherLocation() async {
    setState(() {
      _isLocating = true;
      _locationStatus = "Requesting device GPS...";
    });

    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        setState(() {
          _isLocating = false;
          _locationStatus = "GPS disabled on device.";
        });
        return null;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          setState(() {
            _isLocating = false;
            _locationStatus = "GPS permission denied.";
          });
          return null;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        setState(() {
          _isLocating = false;
          _locationStatus = "GPS permission permanently denied.";
        });
        return null;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      );

      setState(() {
        _currentTeacherPosition = position;
        _isLocating = false;
        _locationStatus = "GPS Locked: ±${position.accuracy.toStringAsFixed(1)}m";
      });
      return position;
    } catch (e) {
      final lastPos = await Geolocator.getLastKnownPosition();
      setState(() {
        _currentTeacherPosition = lastPos;
        _isLocating = false;
        _locationStatus = lastPos != null ? "Using cached GPS" : "GPS detection error";
      });
      return lastPos;
    }
  }

  @override
  void dispose() {
    _rotationTimer?.cancel();
    super.dispose();
  }

  Future<void> fetchTodayTimetable() async {
    try {
      final headers = <String, String>{};
      if (AppConfig.authToken != null) {
        headers['Authorization'] = 'Bearer ${AppConfig.authToken}';
      }

      final response = await http.get(
        Uri.parse('${AppConfig.baseUrl}/api/timetable/today'),
        headers: headers,
      ).timeout(const Duration(seconds: 40));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final slots = data['slots'] as List<dynamic>? ?? [];
        setState(() {
          todaySlots = slots;
          if (todaySlots.isNotEmpty) {
            selectedSlot = todaySlots[0] as Map<String, dynamic>;
          }
        });
      }
    } catch (e) {
      debugPrint('Error fetching timetable: $e');
    }
  }

  void startTokenRotation() {
    _rotationTimer?.cancel();
    _rotationTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {
          if (secondsRemaining > 1) {
            secondsRemaining--;
          } else {
            secondsRemaining = 80;
            rotateToken();
          }
        });
      }
    });
  }

  Future<void> rotateToken() async {
    if (activeSessionId.isEmpty) return;
    try {
      final response = await http.post(
        Uri.parse('${AppConfig.baseUrl}/api/session/$activeSessionId/rotate-token'),
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          currentToken = data['token'];
          generatedUrl = '${AppConfig.baseUrl}/mark-attendance?session_id=$activeSessionId&token=$currentToken';
        });
        fetchAttendanceReport();
      }
    } catch (e) {
      debugPrint("Rotate Token Error: $e");
    }
  }

  Future<void> createSession() async {
    setState(() => isLoading = true);

    Position? pos = _currentTeacherPosition ?? await _getTeacherLocation();
    final double teacherLat = pos?.latitude ?? 16.6631;
    final double teacherLng = pos?.longitude ?? 74.2642;

    try {
      final payload = <String, dynamic>{
        'proximity_radius_meters': 50.0,
        'teacher_lat': teacherLat,
        'teacher_lng': teacherLng,
      };

      if (selectedSlot != null) {
        payload['timetable_slot_id'] = selectedSlot!['id'];
        payload['subject_id'] = selectedSlot!['subject_id'];
        payload['class_id'] = selectedSlot!['class_id'];
      }

      final headers = {'Content-Type': 'application/json'};
      if (AppConfig.authToken != null) {
        headers['Authorization'] = 'Bearer ${AppConfig.authToken}';
      }

      final response = await http.post(
        Uri.parse('${AppConfig.baseUrl}/api/session/create'),
        headers: headers,
        body: jsonEncode(payload),
      ).timeout(const Duration(seconds: 50));

      final data = jsonDecode(response.body);

      if (response.statusCode == 201 && data['status'] == 'success') {
        setState(() {
          activeSessionId = data['session_id'];
          currentToken = data['active_token'];
          generatedUrl = '${AppConfig.baseUrl}/mark-attendance?session_id=$activeSessionId&token=$currentToken';
          isSessionActive = true;
          secondsRemaining = 80;
          _activeSessionTeacherLat = teacherLat;
          _activeSessionTeacherLng = teacherLng;
          currentSubjectName = selectedSlot?['subject_name'] ?? 'Classroom Lecture';
          currentRoom = selectedSlot?['room'] ?? 'LH2';
          attendanceList = [];
        });
        startTokenRotation();
        _showSnackBar("Attendance Session Active! 50m phone radius locked.");
      } else {
        _showSnackBar("Failed: ${data['message'] ?? 'Could not start session'}");
      }
    } catch (e) {
      _showSnackBar("Network Error: Could not reach backend server.");
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  Future<void> endSession() async {
    if (activeSessionId.isEmpty) return;
    setState(() => isLoading = true);

    try {
      final response = await http.post(
        Uri.parse('${AppConfig.baseUrl}/api/session/$activeSessionId/end'),
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        _rotationTimer?.cancel();
        setState(() {
          isSessionActive = false;
          activeSessionId = "";
          currentToken = "";
          generatedUrl = "";
          secondsRemaining = 80;
        });
        _showSnackBar("Session ended. All attendance records saved to permanent database.");
      }
    } catch (e) {
      _showSnackBar("Error ending session.");
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  Future<void> fetchAttendanceReport() async {
    if (activeSessionId.isEmpty) return;

    try {
      final response = await http.get(
        Uri.parse('${AppConfig.baseUrl}/api/reports/session/$activeSessionId'),
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          attendanceList = data['records'] ?? [];
        });
      }
    } catch (e) {
      debugPrint("Fetch attendance error: $e");
    }
  }

  void _showSnackBar(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  void _openClassTeacherPortal() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const ClassTeacherPortalScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = AppConfig.currentUser;
    final isCT = AppConfig.isClassTeacher();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Faculty Console'),
        actions: [
          if (isCT)
            Padding(
              padding: const EdgeInsets.only(right: 6.0),
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.amber.shade700,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                ),
                onPressed: _openClassTeacherPortal,
                icon: const Icon(Icons.school, size: 18),
                label: const Text('Class Teacher', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
              ),
            ),
          const AttendioPopupMenu(),
        ],
      ),
      drawer: const AttendioDrawer(activeScreen: 'teacher'),
      body: RefreshIndicator(
        onRefresh: () async {
          await fetchTodayTimetable();
          await fetchAttendanceReport();
          await _getTeacherLocation();
        },
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Logged-in Faculty Header Card
              Card(
                color: Colors.indigo.shade900,
                elevation: 3,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 26,
                        backgroundColor: isCT ? Colors.amber : Colors.indigo.shade300,
                        child: Icon(
                          isCT ? Icons.stars_rounded : Icons.person_rounded,
                          size: 32,
                          color: isCT ? Colors.indigo.shade900 : Colors.white,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              user?['full_name'] ?? 'Faculty Member',
                              style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              user?['email'] ?? 'BVCOEK T.Y. CSE',
                              style: TextStyle(color: Colors.indigo.shade200, fontSize: 13),
                            ),
                            if (isCT)
                              Container(
                                margin: const EdgeInsets.only(top: 6),
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.amber,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Text(
                                  '🎓 Class Teacher (Defaulter & All-Student Access)',
                                  style: TextStyle(color: Colors.black87, fontSize: 11, fontWeight: FontWeight.w800),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Proximity GPS Sensor Status Card
              Card(
                elevation: 2,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(
                    children: [
                      Icon(
                        _currentTeacherPosition != null ? Icons.my_location_rounded : Icons.location_searching_rounded,
                        color: _currentTeacherPosition != null ? Colors.green.shade600 : Colors.orange,
                        size: 26,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Teacher Phone GPS Proximity (50m Radius)',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                            ),
                            Text(
                              _locationStatus,
                              style: TextStyle(
                                fontSize: 12,
                                color: _currentTeacherPosition != null ? Colors.green.shade700 : Colors.grey.shade600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      _isLocating
                          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                          : IconButton(
                              icon: const Icon(Icons.refresh, size: 20),
                              tooltip: 'Re-lock GPS',
                              onPressed: _getTeacherLocation,
                            )
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Class Teacher Portal Shortcut Banner
              if (isCT)
                Card(
                  color: Colors.amber.shade50,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(color: Colors.amber.shade400, width: 1.5),
                  ),
                  child: ListTile(
                    leading: const CircleAvatar(
                      backgroundColor: Colors.amber,
                      child: Icon(Icons.analytics_rounded, color: Colors.black87),
                    ),
                    title: const Text('Class Teacher Defaulter Portal (< 50%)', style: TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: const Text('View all 77 students, subject breakdowns & defaulters list.'),
                    trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 16, color: Colors.black54),
                    onTap: _openClassTeacherPortal,
                  ),
                ),
              if (isCT) const SizedBox(height: 16),

              // Session Control & Rotating Dynamic QR Card
              Card(
                elevation: 4,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                child: Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: Column(
                    children: [
                      if (!isSessionActive) ...[
                        const Text(
                          'Select Assigned Lecture to Start Attendance',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 12),
                        todaySlots.isEmpty
                            ? Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.grey.shade100,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Text(
                                  'Loading your scheduled subject slots...',
                                  style: TextStyle(color: Colors.grey),
                                ),
                              )
                            : DropdownButtonFormField<Map<String, dynamic>>(
                                isExpanded: true,
                                value: selectedSlot,
                                decoration: const InputDecoration(
                                  labelText: 'My Scheduled Timetable Slot',
                                  border: OutlineInputBorder(),
                                  prefixIcon: Icon(Icons.calendar_today_rounded),
                                ),
                                items: todaySlots.map((slot) {
                                  return DropdownMenuItem<Map<String, dynamic>>(
                                    value: slot as Map<String, dynamic>,
                                    child: Text(
                                      '${slot['day_of_week'] ?? ''} ${slot['start_time']}-${slot['end_time']}: ${slot['subject_name']} (${slot['room'] ?? 'LH2'})',
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                                    ),
                                  );
                                }).toList(),
                                onChanged: (slot) {
                                  setState(() {
                                    selectedSlot = slot;
                                  });
                                },
                              ),
                        const SizedBox(height: 20),
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.indigo,
                            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          onPressed: isLoading ? null : createSession,
                          icon: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 22),
                          label: Text(
                            isLoading ? 'Starting Session...' : 'Start 80s QR for ${selectedSlot?['subject_name'] ?? 'Lecture'}',
                            style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ] else ...[
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          margin: const EdgeInsets.only(bottom: 8),
                          decoration: BoxDecoration(
                            color: Colors.indigo.shade50,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.indigo.shade200),
                          ),
                          child: Text(
                            "Active Lecture: $currentSubjectName (Room: $currentRoom)",
                            style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.indigo),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          margin: const EdgeInsets.only(bottom: 12),
                          decoration: BoxDecoration(
                            color: Colors.green.shade50,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.green.shade300),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.gps_fixed, size: 16, color: Colors.green),
                              const SizedBox(width: 6),
                              Flexible(
                                child: Text(
                                  "50m Boundary Locked to this Phone (${_activeSessionTeacherLat.toStringAsFixed(4)}, ${_activeSessionTeacherLng.toStringAsFixed(4)})",
                                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.green),
                                ),
                              ),
                            ],
                          ),
                        ),
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red.shade600,
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          onPressed: endSession,
                          icon: const Icon(Icons.stop_rounded, color: Colors.white),
                          label: const Text(
                            'End Attendance Session',
                            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                          ),
                        ),
                        const SizedBox(height: 20),
                        // 80s Dynamic rotating countdown timer
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          decoration: BoxDecoration(
                            color: secondsRemaining <= 10 ? Colors.red.shade50 : Colors.indigo.shade50,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: secondsRemaining <= 10 ? Colors.red.shade300 : Colors.indigo.shade200,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.timer_outlined,
                                size: 18,
                                color: secondsRemaining <= 10 ? Colors.red : Colors.indigo,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'Token Refresh in: $secondsRemaining seconds',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: secondsRemaining <= 10 ? Colors.red : Colors.indigo,
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 15),
                        SelectableText(
                          generatedUrl,
                          style: const TextStyle(color: Colors.blue, fontWeight: FontWeight.bold, fontSize: 13),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 15),
                        // Classroom Projector QR Display
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            border: Border.all(color: Colors.grey.shade300, width: 2),
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [
                              BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 10, offset: const Offset(0, 4)),
                            ],
                          ),
                          child: Image.network(
                            'https://api.qrserver.com/v1/create-qr-code/?size=240x240&data=${Uri.encodeComponent(generatedUrl)}',
                            height: 220,
                            width: 220,
                            errorBuilder: (context, error, stackTrace) => const Column(
                              children: [
                                Icon(Icons.qr_code_2_rounded, size: 120, color: Colors.grey),
                                Text('QR Display (Projector URL Active)'),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // Live Attendance Roster with Real-Time Present & Absent Counters
              Card(
                color: Colors.white,
                elevation: 2,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: Padding(
                  padding: const EdgeInsets.all(14.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Text('📋 Live Roster: ', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(color: Colors.green.shade100, borderRadius: BorderRadius.circular(8)),
                                child: Text('✅ ${attendanceList.length} Present', style: TextStyle(color: Colors.green.shade900, fontWeight: FontWeight.bold, fontSize: 12)),
                              ),
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(color: Colors.red.shade100, borderRadius: BorderRadius.circular(8)),
                                child: Text('❌ ${77 - attendanceList.length} Absent', style: TextStyle(color: Colors.red.shade900, fontWeight: FontWeight.bold, fontSize: 12)),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          const Text('Total: 77 Enrolled | T.Y. CSE Div-A', style: TextStyle(color: Colors.grey, fontSize: 11)),
                        ],
                      ),
                      IconButton(
                        onPressed: fetchAttendanceReport,
                        icon: const Icon(Icons.sync, color: Colors.indigo),
                        tooltip: 'Refresh Roster',
                      )
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),

              attendanceList.isEmpty
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(28.0),
                        child: Text(
                          'No attendance marked yet. Awaiting student scans...',
                          style: TextStyle(color: Colors.grey, fontSize: 14),
                        ),
                      ),
                    )
                  : ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: attendanceList.length,
                      itemBuilder: (context, index) {
                        final record = attendanceList[index];
                        final name = record['student_name'];
                        final roll = record['roll_no'];
                        final prn = record['prn'];
                        final time = record['time_only'] ?? record['timestamp'] ?? '';

                        return Card(
                          margin: const EdgeInsets.symmetric(vertical: 6),
                          elevation: 1,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          child: ListTile(
                            leading: const CircleAvatar(
                              backgroundColor: Colors.green,
                              child: Icon(Icons.check, color: Colors.white),
                            ),
                            title: Text(
                              (name != null && name.toString().isNotEmpty) ? name.toString() : 'PRN: $prn',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                            ),
                            subtitle: Text(
                              'Roll: ${roll ?? '-'} | PRN: $prn\nTime (IST): $time',
                              style: const TextStyle(fontSize: 12),
                            ),
                            trailing: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.indigo.shade50,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                '${record['distance']} m',
                                style: const TextStyle(color: Colors.indigo, fontWeight: FontWeight.bold, fontSize: 13),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ],
          ),
        ),
      ),
    );
  }
}

// -------------------------------------------------------------
// CLASS TEACHER PORTAL, DEFAULTER & HISTORICAL LECTURES SCREEN
// -------------------------------------------------------------
class ClassTeacherPortalScreen extends StatefulWidget {
  const ClassTeacherPortalScreen({super.key});

  @override
  State<ClassTeacherPortalScreen> createState() => _ClassTeacherPortalScreenState();
}

class _ClassTeacherPortalScreenState extends State<ClassTeacherPortalScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _isLoading = true;
  String? _errorMessage;

  Map<String, dynamic>? _dashboardData;
  List<dynamic> _allStudents = [];
  List<dynamic> _defaulters = [];
  List<dynamic> _filteredStudents = [];
  List<dynamic> _filteredDefaulters = [];
  List<dynamic> _lectureHistory = [];
  bool _isLoadingLectures = false;

  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _fetchClassTeacherData();
    _fetchLectureHistory();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _fetchClassTeacherData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final response = await http.get(
        Uri.parse('${AppConfig.baseUrl}/api/class-teacher/dashboard-data'),
      ).timeout(const Duration(seconds: 40));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          _dashboardData = data;
          _allStudents = data['students'] ?? [];
          _defaulters = data['defaulters'] ?? [];
          _applySearch();
          _isLoading = false;
        });
      } else {
        setState(() {
          _errorMessage = 'Failed to load class teacher analysis.';
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Error connecting to backend server.';
        _isLoading = false;
      });
    }
  }

  Future<void> _fetchLectureHistory() async {
    setState(() {
      _isLoadingLectures = true;
    });

    try {
      final res = await http.get(
        Uri.parse('${AppConfig.baseUrl}/api/lectures/history'),
      ).timeout(const Duration(seconds: 30));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        setState(() {
          _lectureHistory = data['history'] ?? [];
          _isLoadingLectures = false;
        });
      } else {
        setState(() {
          _isLoadingLectures = false;
        });
      }
    } catch (e) {
      setState(() {
        _isLoadingLectures = false;
      });
    }
  }

  void _applySearch() {
    final query = _searchController.text.trim().toLowerCase();
    if (query.isEmpty) {
      _filteredStudents = List.from(_allStudents);
      _filteredDefaulters = List.from(_defaulters);
    } else {
      _filteredStudents = _allStudents.where((s) {
        final name = (s['full_name'] ?? '').toString().toLowerCase();
        final roll = (s['roll_no'] ?? '').toString();
        final prn = (s['prn'] ?? '').toString().toLowerCase();
        return name.contains(query) || roll.contains(query) || prn.contains(query);
      }).toList();

      _filteredDefaulters = _defaulters.where((s) {
        final name = (s['full_name'] ?? '').toString().toLowerCase();
        final roll = (s['roll_no'] ?? '').toString();
        final prn = (s['prn'] ?? '').toString().toLowerCase();
        return name.contains(query) || roll.contains(query) || prn.contains(query);
      }).toList();
    }
  }

  void _showStudentDetail(Map<String, dynamic> student) {
    final subjectBreakdown = student['subject_breakdown'] as Map<String, dynamic>? ?? {};
    final bool isDef = student['is_defaulter'] ?? false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        maxChildSize: 0.9,
        minChildSize: 0.4,
        expand: false,
        builder: (_, scrollController) => Padding(
          padding: const EdgeInsets.all(20.0),
          child: ListView(
            controller: scrollController,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)),
                ),
              ),
              Row(
                children: [
                  CircleAvatar(
                    radius: 28,
                    backgroundColor: isDef ? Colors.red.shade100 : Colors.indigo.shade100,
                    child: Text(
                      '${student['roll_no'] ?? '-'}',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: isDef ? Colors.red.shade900 : Colors.indigo.shade900,
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          student['full_name'] ?? 'Student Name',
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        Text(
                          'PRN: ${student['prn']} | Roll No: ${student['roll_no']}',
                          style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: isDef ? Colors.red.shade100 : Colors.green.shade100,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${student['percentage']}%',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: isDef ? Colors.red.shade900 : Colors.green.shade900,
                        fontSize: 16,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              if (isDef)
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.red.shade200),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.warning_amber_rounded, color: Colors.red, size: 20),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'DEFAULTER NOTICE: Attendance is below mandatory 50.0% threshold. Immediate remediation required.',
                          style: TextStyle(color: Colors.red, fontSize: 12, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 20),
              const Text(
                'Subject-Wise Attendance Breakdown:',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
              ),
              const SizedBox(height: 10),
              subjectBreakdown.isEmpty
                  ? const Text('No subject breakdown data available.', style: TextStyle(color: Colors.grey))
                  : Column(
                      children: subjectBreakdown.entries.map((entry) {
                        final subData = entry.value as Map<String, dynamic>;
                        final double subPct = (subData['percentage'] as num?)?.toDouble() ?? 0.0;
                        final bool subDef = subPct < 50.0;
                        return Card(
                          margin: const EdgeInsets.symmetric(vertical: 4),
                          elevation: 0.5,
                          child: ListTile(
                            title: Text(subData['subject_name'] ?? entry.key, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                            subtitle: Text('Attended: ${subData['attended']}/${subData['conducted']} lectures', style: const TextStyle(fontSize: 12)),
                            trailing: Text(
                              '$subPct%',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: subDef ? Colors.red : Colors.green.shade800,
                                fontSize: 14,
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showLectureDetailsModal(String sessionId) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final res = await http.get(
        Uri.parse('${AppConfig.baseUrl}/api/lectures/$sessionId/details'),
      ).timeout(const Duration(seconds: 30));

      if (mounted) Navigator.of(context).pop();

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final lecture = data['lecture'];
        final presentStudents = (data['present_students'] as List?) ?? [];
        final absentStudents = (data['absent_students'] as List?) ?? [];

        if (!mounted) return;
        showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
          builder: (ctx) => DefaultTabController(
            length: 2,
            child: SizedBox(
              height: MediaQuery.of(context).size.height * 0.8,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)),
                      ),
                    ),
                    Text(
                      '${lecture['subject_name']} (${lecture['subject_code']})',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                    ),
                    Text(
                      'Faculty: ${lecture['teacher_name']} | Time (IST): ${lecture['started_at_ist'] ?? lecture['date']}',
                      style: const TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                    const SizedBox(height: 12),
                    TabBar(
                      labelColor: Colors.indigo,
                      indicatorColor: Colors.indigo,
                      tabs: [
                        Tab(text: '✅ Present (${presentStudents.length})'),
                        Tab(text: '❌ Absent (${absentStudents.length})'),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Expanded(
                      child: TabBarView(
                        children: [
                          presentStudents.isEmpty
                              ? const Center(child: Text('No students attended this lecture.'))
                              : ListView.builder(
                                  itemCount: presentStudents.length,
                                  itemBuilder: (ctx, idx) {
                                    final s = presentStudents[idx];
                                    return ListTile(
                                      leading: CircleAvatar(
                                        backgroundColor: Colors.green.shade100,
                                        child: Text('${s['roll_no'] ?? '-'}', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green.shade900)),
                                      ),
                                      title: Text(s['student_name'] ?? 'Student', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                                      subtitle: Text('PRN: ${s['prn']} | Marked: ${s['time_only'] ?? ''}'),
                                      trailing: Text('${s['distance']}m', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.indigo)),
                                    );
                                  },
                                ),
                          absentStudents.isEmpty
                              ? const Center(
                                  child: Text('Zero absentees! Full class attended.', style: TextStyle(color: Colors.green)),
                                )
                              : ListView.builder(
                                  itemCount: absentStudents.length,
                                  itemBuilder: (ctx, idx) {
                                    final s = absentStudents[idx];
                                    return ListTile(
                                      leading: CircleAvatar(
                                        backgroundColor: Colors.red.shade100,
                                        child: Text('${s['roll_no'] ?? '-'}', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red.shade900)),
                                      ),
                                      title: Text(s['student_name'] ?? 'Student', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                                      subtitle: Text('PRN: ${s['prn']}'),
                                      trailing: const Text('ABSENT', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 12)),
                                    );
                                  },
                                ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Error loading lecture details.')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_dashboardData != null ? '${_dashboardData!['class_name']} Defaulters (<50%)' : 'Class Teacher Portal'),
        actions: [
          IconButton(
            icon: const Icon(Icons.file_download_outlined),
            tooltip: 'Download Master Excel',
            onPressed: () => showMasterExcelDialog(context),
          ),
          const AttendioPopupMenu(),
        ],
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.indigo.shade200,
          indicatorColor: Colors.amber,
          indicatorWeight: 3,
          tabs: [
            Tab(
              icon: const Icon(Icons.warning_amber_rounded),
              text: '🚨 Defaulters (<50%) (${_defaulters.length})',
            ),
            Tab(
              icon: const Icon(Icons.groups_rounded),
              text: '👥 All Students (${_allStudents.length})',
            ),
            Tab(
              icon: const Icon(Icons.history_edu_rounded),
              text: '📚 Lectures (${_lectureHistory.length})',
            ),
          ],
        ),
      ),
      drawer: const AttendioDrawer(activeScreen: 'class_teacher'),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(_errorMessage!, style: const TextStyle(color: Colors.red)),
                      const SizedBox(height: 12),
                      ElevatedButton(onPressed: _fetchClassTeacherData, child: const Text('Retry')),
                    ],
                  ),
                )
              : Column(
                  children: [
                    // Quick Search Bar
                    Padding(
                      padding: const EdgeInsets.all(12.0),
                      child: TextField(
                        controller: _searchController,
                        onChanged: (val) {
                          setState(() {
                            _applySearch();
                          });
                        },
                        decoration: InputDecoration(
                          hintText: 'Search by PRN, Roll No, or Student Name...',
                          prefixIcon: const Icon(Icons.search),
                          suffixIcon: _searchController.text.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear),
                                  onPressed: () {
                                    _searchController.clear();
                                    setState(() {
                                      _applySearch();
                                    });
                                  },
                                )
                              : null,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                          fillColor: Colors.white,
                          filled: true,
                        ),
                      ),
                    ),

                    Expanded(
                      child: TabBarView(
                        controller: _tabController,
                        children: [
                          // Tab 1: Defaulters List (< 50%)
                          _filteredDefaulters.isEmpty
                              ? const Center(
                                  child: Padding(
                                    padding: EdgeInsets.all(24.0),
                                    child: Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Icon(Icons.check_circle_outline_rounded, size: 56, color: Colors.green),
                                        SizedBox(height: 12),
                                        Text(
                                          'No students below 50% attendance!',
                                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.green),
                                        ),
                                      ],
                                    ),
                                  ),
                                )
                              : ListView.builder(
                                  padding: const EdgeInsets.symmetric(horizontal: 12),
                                  itemCount: _filteredDefaulters.length,
                                  itemBuilder: (context, index) {
                                    final student = _filteredDefaulters[index];
                                    return Card(
                                      margin: const EdgeInsets.symmetric(vertical: 4),
                                      elevation: 1,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(10),
                                        side: BorderSide(color: Colors.red.shade200),
                                      ),
                                      child: ListTile(
                                        leading: CircleAvatar(
                                          backgroundColor: Colors.red.shade100,
                                          child: Text(
                                            '${student['roll_no'] ?? '-'}',
                                            style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                              color: Colors.red.shade900,
                                              fontSize: 12,
                                            ),
                                          ),
                                        ),
                                        title: Text(
                                          student['full_name'] ?? 'Student',
                                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                        ),
                                        subtitle: Text(
                                          'PRN: ${student['prn']} | Attended: ${student['total_attended']}/${student['total_conducted']}',
                                          style: const TextStyle(fontSize: 12),
                                        ),
                                        trailing: Column(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          crossAxisAlignment: CrossAxisAlignment.end,
                                          children: [
                                            Text(
                                              '${student['percentage']}%',
                                              style: TextStyle(
                                                fontWeight: FontWeight.w800,
                                                color: Colors.red.shade700,
                                                fontSize: 16,
                                              ),
                                            ),
                                            const Text('Defaulter', style: TextStyle(color: Colors.red, fontSize: 10)),
                                          ],
                                        ),
                                        onTap: () => _showStudentDetail(student),
                                      ),
                                    );
                                  },
                                ),

                          // Tab 2: All 77 Students
                          _filteredStudents.isEmpty
                              ? const Center(child: Text('No students match query.'))
                              : ListView.builder(
                                  padding: const EdgeInsets.symmetric(horizontal: 12),
                                  itemCount: _filteredStudents.length,
                                  itemBuilder: (context, index) {
                                    final student = _filteredStudents[index];
                                    final bool isDef = student['is_defaulter'] ?? false;
                                    return Card(
                                      margin: const EdgeInsets.symmetric(vertical: 4),
                                      elevation: 1,
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                      child: ListTile(
                                        leading: CircleAvatar(
                                          backgroundColor: isDef ? Colors.red.shade100 : Colors.indigo.shade100,
                                          child: Text(
                                            '${student['roll_no'] ?? '-'}',
                                            style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                              color: isDef ? Colors.red.shade900 : Colors.indigo.shade900,
                                              fontSize: 12,
                                            ),
                                          ),
                                        ),
                                        title: Text(
                                          student['full_name'] ?? 'Student',
                                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                        ),
                                        subtitle: Text(
                                          'PRN: ${student['prn']} | Attended: ${student['total_attended']}/${student['total_conducted']}',
                                          style: const TextStyle(fontSize: 12),
                                        ),
                                        trailing: Column(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          crossAxisAlignment: CrossAxisAlignment.end,
                                          children: [
                                            Text(
                                              '${student['percentage']}%',
                                              style: TextStyle(
                                                fontWeight: FontWeight.bold,
                                                color: isDef ? Colors.red.shade700 : Colors.green.shade800,
                                                fontSize: 15,
                                              ),
                                            ),
                                            Text(
                                              isDef ? 'Defaulter' : 'Clear',
                                              style: TextStyle(
                                                color: isDef ? Colors.red : Colors.green,
                                                fontSize: 10,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ],
                                        ),
                                        onTap: () => _showStudentDetail(student),
                                      ),
                                    );
                                  },
                                ),

                          // Tab 3: Chronological Lecture History & Absentees
                          _isLoadingLectures
                              ? const Center(child: CircularProgressIndicator())
                              : _lectureHistory.isEmpty
                                  ? const Center(
                                      child: Padding(
                                        padding: EdgeInsets.all(24.0),
                                        child: Text('No historical lectures conducted yet.', style: TextStyle(color: Colors.grey)),
                                      ),
                                    )
                                  : ListView.builder(
                                      padding: const EdgeInsets.symmetric(horizontal: 12),
                                      itemCount: _lectureHistory.length,
                                      itemBuilder: (context, index) {
                                        final l = _lectureHistory[index];
                                        return Card(
                                          margin: const EdgeInsets.symmetric(vertical: 4),
                                          elevation: 1,
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                          child: ListTile(
                                            leading: CircleAvatar(
                                              backgroundColor: Colors.indigo.shade100,
                                              child: const Icon(Icons.class_rounded, color: Colors.indigo),
                                            ),
                                            title: Text(
                                              '${l['subject_name']} (${l['subject_code']})',
                                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                            ),
                                            subtitle: Text(
                                              '${l['started_at_ist'] ?? l['date']}\nFaculty: ${l['teacher_name']} | 77 Enrolled',
                                              style: const TextStyle(fontSize: 12),
                                            ),
                                            trailing: Column(
                                              mainAxisAlignment: MainAxisAlignment.center,
                                              crossAxisAlignment: CrossAxisAlignment.end,
                                              children: [
                                                Text(
                                                  '${l['present_count']} / 77',
                                                  style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 13),
                                                ),
                                                Text(
                                                  '${l['absent_count']} Absent',
                                                  style: const TextStyle(color: Colors.red, fontSize: 11, fontWeight: FontWeight.bold),
                                                ),
                                              ],
                                            ),
                                            onTap: () => _showLectureDetailsModal(l['session_id']),
                                          ),
                                        );
                                      },
                                    ),
                        ],
                      ),
                    ),
                  ],
                ),
    );
  }
}