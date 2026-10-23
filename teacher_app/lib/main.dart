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

  static bool isClassTeacher() {
    if (currentUser == null) return false;
    if (currentUser!['is_class_teacher'] == true) return true;
    final tp = currentUser!['teacher_profile'];
    if (tp != null && tp['is_class_teacher'] == true) return true;
    final email = currentUser!['email']?.toString().toLowerCase() ?? '';
    return email == 'upadhye@bvcoek.edu.in' || email == 'teacher@gcek.ac.in';
  }
}

// Preset Teachers for Quick Switching & Testing
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
// AUTH GATE & LOGIN SCREEN
// -------------------------------------------------------------
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  final _emailController = TextEditingController(text: "upadhye@bvcoek.edu.in");
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
      ).timeout(const Duration(seconds: 60));

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
    } on TimeoutException {
      setState(() {
        _errorMessage = 'Cloud server waking up from idle. Please tap "Log In to Faculty Console" again!';
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Connection error: Unable to reach backend server at ${AppConfig.baseUrl}.';
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
            constraints: const BoxConstraints(maxWidth: 440),
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
                      'BVCOEK T.Y. CSE Faculty Portal',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 14, color: Colors.grey),
                    ),
                    const SizedBox(height: 20),

                    // Quick Faculty Preset Selector
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
                            '👨‍🏫 Quick Select Faculty Member:',
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
                            value: _emailController.text,
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
                    const SizedBox(height: 14),
                    TextField(
                      controller: _passwordController,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: 'Password',
                        prefixIcon: Icon(Icons.lock_outline),
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: _serverUrlController,
                      decoration: const InputDecoration(
                        labelText: 'Cloud Server URL',
                        prefixIcon: Icon(Icons.dns_outlined),
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 20),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.indigo,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      onPressed: _isLoading ? null : _login,
                      child: _isLoading
                          ? Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: const [
                                SizedBox(
                                  height: 18,
                                  width: 18,
                                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                                ),
                                SizedBox(width: 12),
                                Text('Logging In...', style: TextStyle(fontWeight: FontWeight.bold)),
                              ],
                            )
                          : const Text('Log In to Faculty Console', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    ),
                    const SizedBox(height: 10),
                    TextButton(
                      onPressed: _bypassToDirectDashboard,
                      child: const Text('Direct Prototype Dashboard'),
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
      // ignore
    }
  }

  Future<void> createSession() async {
    setState(() {
      isLoading = true;
    });

    try {
      final pos = _currentTeacherPosition ?? await _getTeacherLocation();

      final double teacherLat = pos?.latitude ?? 16.6631;
      final double teacherLng = pos?.longitude ?? 74.2642;

      final headers = {'Content-Type': 'application/json'};
      if (AppConfig.authToken != null) {
        headers['Authorization'] = 'Bearer ${AppConfig.authToken}';
      }

      final body = {
        'slot_id': selectedSlot?['id'],
        'subject_id': selectedSlot?['subject_id'],
        'proximity_radius': 50.0,
        'teacher_lat': teacherLat,
        'teacher_lng': teacherLng
      };

      final response = await http.post(
        Uri.parse('${AppConfig.baseUrl}/api/create-session'),
        headers: headers,
        body: jsonEncode(body),
      ).timeout(const Duration(seconds: 40));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          activeSessionId = data['session_id'];
          generatedUrl = data['url'];
          currentToken = data['token'] ?? '';
          secondsRemaining = data['valid_for_seconds'] ?? 80;
          currentSubjectName = data['subject_name'] ?? '';
          currentRoom = data['room'] ?? '';
          _activeSessionTeacherLat = teacherLat;
          _activeSessionTeacherLng = teacherLng;
          isSessionActive = true;
        });
        showSnackBar('Attendance Session Started! 50m radius locked to this phone.');
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
        await pollRotatedQR();
      }

      if (timer.tick % 3 == 0) {
        fetchAttendanceReport();
      }
    });
  }

  Future<void> pollRotatedQR() async {
    try {
      final response = await http.get(
        Uri.parse('${AppConfig.baseUrl}/api/teacher/session/$activeSessionId/live-qr'),
      ).timeout(const Duration(seconds: 20));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          currentToken = data['current_token'] ?? '';
          secondsRemaining = data['seconds_remaining'] ?? 80;
          generatedUrl = data['student_url'] ?? generatedUrl;
        });
      }
    } catch (e) {
      // ignore
    }
  }

  Future<void> endSession() async {
    if (activeSessionId.isEmpty) return;
    try {
      final response = await http.post(
        Uri.parse('${AppConfig.baseUrl}/api/teacher/session/$activeSessionId/end'),
      );
      if (response.statusCode == 200) {
        setState(() {
          isSessionActive = false;
          activeSessionId = "";
          generatedUrl = "";
        });
        _rotationTimer?.cancel();
        showSnackBar('Attendance Session Ended.');
        fetchAttendanceReport();
      }
    } catch (e) {
      showSnackBar('Error ending session.');
    }
  }

  Future<void> fetchAttendanceReport() async {
    try {
      final url = activeSessionId.isNotEmpty
          ? '${AppConfig.baseUrl}/api/attendance-report?session_id=$activeSessionId'
          : '${AppConfig.baseUrl}/api/attendance-report';

      final response = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 20));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          attendanceList = data['records'] ?? [];
        });
      }
    } catch (e) {
      // ignore
    }
  }

  void showSnackBar(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  void _openClassTeacherPortal() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const ClassTeacherPortalScreen()),
    );
  }

  void _handleLogout() {
    AppConfig.authToken = null;
    AppConfig.currentUser = null;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const AuthGate()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = AppConfig.currentUser;
    final isCT = AppConfig.isClassTeacher();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Attendio Faculty Console'),
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
                label: const Text('Class Teacher Portal', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
              ),
            ),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Log Out',
            onPressed: _handleLogout,
          ),
        ],
      ),
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
                        // High resolution Classroom Projector QR Display
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

              // Live Attendance Roster with IST Time & Student Names
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
// CLASS TEACHER PORTAL & DEFAULTER ANALYSIS SCREEN (<50%)
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
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _fetchClassTeacherData();
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

  void _applySearch() {
    final query = _searchController.text.trim().toLowerCase();
    if (query.isEmpty) {
      _filteredStudents = List.from(_allStudents);
      _filteredDefaulters = List.from(_defaulters);
    } else {
      _filteredStudents = _allStudents.where((st) {
        final name = (st['full_name'] ?? '').toString().toLowerCase();
        final prn = (st['prn'] ?? '').toString().toLowerCase();
        final roll = (st['roll_no'] ?? '').toString().toLowerCase();
        return name.contains(query) || prn.contains(query) || roll.contains(query);
      }).toList();

      _filteredDefaulters = _defaulters.where((st) {
        final name = (st['full_name'] ?? '').toString().toLowerCase();
        final prn = (st['prn'] ?? '').toString().toLowerCase();
        final roll = (st['roll_no'] ?? '').toString().toLowerCase();
        return name.contains(query) || prn.contains(query) || roll.contains(query);
      }).toList();
    }
  }

  void _showStudentDetail(dynamic student) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        final bool isDef = student['is_defaulter'] ?? false;
        final subBreakdown = student['subject_breakdown'] as List<dynamic>? ?? [];

        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.75,
          maxChildSize: 0.95,
          minChildSize: 0.5,
          builder: (context, scrollController) {
            return SingleChildScrollView(
              controller: scrollController,
              padding: const EdgeInsets.all(20.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 5,
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              student['full_name'] ?? 'Student',
                              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                            ),
                            Text(
                              'Roll: ${student['roll_no'] ?? '-'} | PRN: ${student['prn']}',
                              style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: isDef ? Colors.red.shade100 : Colors.green.shade100,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          isDef ? '🚨 Defaulter (<50%)' : '✅ Good Standing',
                          style: TextStyle(
                            color: isDef ? Colors.red.shade900 : Colors.green.shade900,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Overall card
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: isDef ? Colors.red.shade50 : Colors.indigo.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: isDef ? Colors.red.shade200 : Colors.indigo.shade200),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        Column(
                          children: [
                            const Text('Overall Attendance', style: TextStyle(fontSize: 12, color: Colors.grey)),
                            const SizedBox(height: 4),
                            Text(
                              '${student['percentage']}%',
                              style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                color: isDef ? Colors.red.shade700 : Colors.indigo.shade900,
                              ),
                            ),
                          ],
                        ),
                        Column(
                          children: [
                            const Text('Attended / Total', style: TextStyle(fontSize: 12, color: Colors.grey)),
                            const SizedBox(height: 4),
                            Text(
                              '${student['total_attended']} / ${student['total_conducted']}',
                              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  const Text(
                    '📚 Subject-wise Attendance Breakdown',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.indigo),
                  ),
                  const SizedBox(height: 10),

                  if (subBreakdown.isEmpty)
                    const Text('No subject breakdown available.', style: TextStyle(color: Colors.grey))
                  else
                    ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: subBreakdown.length,
                      itemBuilder: (context, idx) {
                        final sub = subBreakdown[idx];
                        final bool subDef = sub['is_defaulter'] ?? false;
                        return Container(
                          margin: const EdgeInsets.symmetric(vertical: 4),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.grey.shade200),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      sub['name'] ?? '',
                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                    ),
                                    Text(
                                      'Code: ${sub['code']} | Attended: ${sub['attended']}/${sub['conducted']}',
                                      style: const TextStyle(fontSize: 11, color: Colors.grey),
                                    ),
                                  ],
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: subDef ? Colors.red.shade50 : Colors.green.shade50,
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: subDef ? Colors.red.shade300 : Colors.green.shade300),
                                ),
                                child: Text(
                                  '${sub['percentage']}%',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                    color: subDef ? Colors.red.shade700 : Colors.green.shade800,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_dashboardData != null ? '${_dashboardData!['class_name']} Defaulters (<50%)' : 'Class Teacher Defaulter Portal'),
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
          ],
        ),
      ),
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
                              ? Center(
                                  child: Padding(
                                    padding: const EdgeInsets.all(24.0),
                                    child: Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: const [
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
                        ],
                      ),
                    ),
                  ],
                ),
    );
  }
}