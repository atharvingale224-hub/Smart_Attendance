import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

void main() {
  runApp(const TeacherApp());
}

class TeacherApp extends StatelessWidget {
  const TeacherApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Attendio - Teacher Console',
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

// Global server configuration
class AppConfig {
  static String baseUrl = "https://smart-attendance-rbsm.onrender.com";
  static String? authToken;
  static Map<String, dynamic>? currentUser;
}

// -------------------------------------------------------------
// AUTH GATE & LOGIN SCREEN
// -------------------------------------------------------------
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  final _emailController = TextEditingController(text: "teacher@gcek.ac.in");
  final _passwordController = TextEditingController(text: "Teacher@1234");
  final _serverUrlController = TextEditingController(text: AppConfig.baseUrl);
  bool _isLoading = false;
  String? _errorMessage;

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
      ).timeout(const Duration(seconds: 10));

      final data = jsonDecode(response.body);

      if (response.statusCode == 200 && data['status'] == 'success') {
        AppConfig.authToken = data['auth_token'];
        AppConfig.currentUser = data['user'];

        if (mounted) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => const TeacherDashboardScreen()),
          );
        }
      } else {
        setState(() {
          _errorMessage = data['message'] ?? 'Login failed. Please check credentials.';
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Connection error: Unable to reach backend server at ${AppConfig.baseUrl}';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _bypassToDirectDashboard() {
    // Quick prototype access mode
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const TeacherDashboardScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Card(
              elevation: 4,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              child: Padding(
                padding: const EdgeInsets.all(28.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Icon(Icons.school_rounded, size: 56, color: Colors.indigo),
                    const SizedBox(height: 12),
                    const Text(
                      'Attendio',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: Colors.indigo),
                    ),
                    const Text(
                      'Faculty Attendance Portal',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 14, color: Colors.grey),
                    ),
                    const SizedBox(height: 24),
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
                        labelText: 'Faculty Email',
                        prefixIcon: Icon(Icons.email_outlined),
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _passwordController,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: 'Password',
                        prefixIcon: Icon(Icons.lock_outline),
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _serverUrlController,
                      decoration: const InputDecoration(
                        labelText: 'Backend Server URL',
                        prefixIcon: Icon(Icons.dns_outlined),
                        border: OutlineInputBorder(),
                        helperText: 'e.g. http://127.0.0.1:5000 or http://10.0.2.2:5000',
                      ),
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.indigo,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      onPressed: _isLoading ? null : _login,
                      child: _isLoading
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                            )
                          : const Text('Log In to Faculty Console', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    ),
                    const SizedBox(height: 12),
                    TextButton(
                      onPressed: _bypassToDirectDashboard,
                      child: const Text('Skip to Attendance Dashboard (Prototype Mode)'),
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
}

// -------------------------------------------------------------
// TEACHER DASHBOARD SCREEN
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

  @override
  void initState() {
    super.initState();
    fetchAttendanceReport();
  }

  @override
  void dispose() {
    _rotationTimer?.cancel();
    super.dispose();
  }

  Future<void> createSession() async {
    setState(() {
      isLoading = true;
    });

    try {
      final headers = {'Content-Type': 'application/json'};
      if (AppConfig.authToken != null) {
        headers['Authorization'] = 'Bearer ${AppConfig.authToken}';
      }

      final response = await http.post(
        Uri.parse('${AppConfig.baseUrl}/api/create-session'),
        headers: headers,
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          activeSessionId = data['session_id'];
          generatedUrl = data['url'];
          currentToken = data['token'] ?? '';
          secondsRemaining = data['valid_for_seconds'] ?? 80;
          isSessionActive = true;
        });
        showSnackBar('Attendance Session Started! Rotating QR is Live.');
        startQRRotationPoll();
        fetchAttendanceReport();
      } else {
        showSnackBar('Failed to create session!');
      }
    } catch (e) {
      showSnackBar('Error connecting to Backend Server at ${AppConfig.baseUrl}!');
    } finally {
      setState(() {
        isLoading = false;
      });
    }
  }

  void startQRRotationPoll() {
    _rotationTimer?.cancel();
    _rotationTimer = Timer.periodic(const Duration(seconds: 1), (timer) async {
      if (!isSessionActive || activeSessionId.isEmpty) {
        timer.cancel();
        return;
      }

      if (secondsRemaining > 1) {
        setState(() {
          secondsRemaining--;
        });
      } else {
        // Fetch new rotated token from server
        await pollRotatedQR();
      }

      // Periodically refresh attendance list every 3 seconds
      if (timer.tick % 3 == 0) {
        fetchAttendanceReport();
      }
    });
  }

  Future<void> pollRotatedQR() async {
    try {
      final response = await http.get(
        Uri.parse('${AppConfig.baseUrl}/api/teacher/session/$activeSessionId/live-qr'),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          currentToken = data['current_token'];
          generatedUrl = data['student_url'];
          secondsRemaining = data['seconds_remaining'] ?? 80;
        });
      }
    } catch (e) {
      // Ignore network flutter glitch
    }
  }

  Future<void> endSession() async {
    if (activeSessionId.isEmpty) return;

    try {
      final response = await http.post(
        Uri.parse('${AppConfig.baseUrl}/api/teacher/session/$activeSessionId/end'),
      );

      _rotationTimer?.cancel();

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final summary = data['summary'];
        setState(() {
          isSessionActive = false;
        });

        if (mounted && summary != null) {
          showDialog(
            context: context,
            builder: (_) => AlertDialog(
              title: const Text('📋 Attendance Session Finalized'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Total Enrolled: ${summary['total_enrolled']}'),
                  Text('Present: ${summary['total_present']}'),
                  Text('Absent: ${summary['total_absent']}'),
                  const SizedBox(height: 8),
                  Text(
                    'Overall Attendance: ${summary['attendance_percentage']}%',
                    style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.indigo),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Close'),
                )
              ],
            ),
          );
        }
      }
    } catch (e) {
      showSnackBar('Failed to finalize session on server.');
    }
  }

  Future<void> fetchAttendanceReport() async {
    try {
      final endpoint = activeSessionId.isNotEmpty
          ? '${AppConfig.baseUrl}/api/attendance-report?session_id=$activeSessionId'
          : '${AppConfig.baseUrl}/api/attendance-report';

      final response = await http.get(Uri.parse(endpoint));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          attendanceList = data['records'];
        });
      }
    } catch (e) {
      // Silently fail background stats polling
    }
  }

  void showSnackBar(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('👨‍🏫 Attendio - Faculty Dashboard'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: fetchAttendanceReport,
            tooltip: 'Refresh Attendance List',
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () {
              AppConfig.authToken = null;
              Navigator.of(context).pushReplacement(
                MaterialPageRoute(builder: (_) => const AuthGate()),
              );
            },
            tooltip: 'Sign Out',
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Projector Notice Banner
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.amber.shade50,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.amber.shade200),
                ),
                child: Row(
                  children: [
                    Icon(Icons.shield_outlined, color: Colors.amber.shade900, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Classroom Projector Mode: QR rotates every 80s to prevent proxy sharing.',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.amber.shade900),
                      ),
                    ),
                  ],
                ),
              ),

              // Attendance Control Card
              Card(
                elevation: 4,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                child: Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: Column(
                    children: [
                      const Text(
                        'Classroom Attendance Control',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.indigo),
                      ),
                      const SizedBox(height: 15),
                      if (!isSessionActive)
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.indigo,
                            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          onPressed: isLoading ? null : createSession,
                          icon: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 22),
                          label: Text(
                            isLoading ? 'Starting Session...' : 'Start 80s Dynamic QR Session',
                            style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                        )
                      else ...[
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
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
                          ],
                        ),
                        const SizedBox(height: 20),
                        // 40s Countdown indicator
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
                        // High resolution Projector QR Display
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

              // Live Attendance Roster
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '📋 Present Students (${attendanceList.length})',
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.indigo),
                  ),
                  IconButton(
                    onPressed: fetchAttendanceReport,
                    icon: const Icon(Icons.sync, color: Colors.indigo),
                    tooltip: 'Refresh Roster',
                  )
                ],
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
                        return Card(
                          margin: const EdgeInsets.symmetric(vertical: 6),
                          elevation: 1,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          child: ListTile(
                            leading: const CircleAvatar(
                              backgroundColor: Colors.green,
                              child: Icon(Icons.check, color: Colors.white),
                            ),
                            title: Text('PRN: ${record['prn']}', style: const TextStyle(fontWeight: FontWeight.bold)),
                            subtitle: Text('Recorded: ${record['timestamp']}'),
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