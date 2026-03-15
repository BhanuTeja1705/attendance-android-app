import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'firebase_options.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'dart:io';
import 'package:excel/excel.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_file/open_file.dart';
import '../services/google_sheet_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  runApp(const MyApp());
}

/* ================= APP ================= */

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: AuthPage(),
    );
  }
}

/* ================= AUTH ================= */

class AuthPage extends StatelessWidget {
  const AuthPage({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.hasData) {
          return const RoleCheckPage();
        }

        return const LoginPage();
      },
    );
  }
}

/* ================= LOGIN ================= */

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final email = TextEditingController();
  final password = TextEditingController();

  bool loading = false;
  
  Future<void> login() async {
  setState(() => loading = true);
  

  try {
    await FirebaseAuth.instance.signInWithEmailAndPassword(
      email: email.text.trim(),
      password: password.text.trim(),
    );

  } on FirebaseAuthException catch (e) {

    String message = "Login Failed";

    if (e.code == 'user-not-found') {
      message = "No user found with this email";
    } 
    else if (e.code == 'wrong-password') {
      message = "Incorrect password";
    } 
    else if (e.code == 'invalid-email') {
      message = "Invalid email format";
    } 
    else if (e.code == 'invalid-credential') {
      message = "Invalid email or password";
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  setState(() => loading = false);
}

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Login")),

      body: Padding(
        padding: const EdgeInsets.all(20),

        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,

          children: [
            Image.asset(
              'assets/app_logo.png',
                height: 120,
              ),

            TextField(
              controller: email,
              decoration: const InputDecoration(labelText: "Email"),
            ),

            

            const SizedBox(height: 15),

            TextField(
              controller: password,
              obscureText: true,
              decoration: const InputDecoration(labelText: "Password"),
            ),

            const SizedBox(height: 20),

            loading
                ? const CircularProgressIndicator()
                : ElevatedButton(
                    onPressed: login,
                    child: const Text("Login"),
                  ),
          ],
        ),
      ),
    );
  }
}

/* ================= ROLE CHECK ================= */

class RoleCheckPage extends StatelessWidget {
  const RoleCheckPage({super.key});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser!;

    return FutureBuilder(
      future: FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get(),

      builder: (context, snapshot) {

        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final data = snapshot.data!.data();

        final role = data?['role'] ?? 'student';

        if (role == 'admin') {
          return const AdminPage();
        }

        return const StudentPage();
      },
    );
  }
}

/* ================= STUDENT ================= */

/* ================= STUDENT DASHBOARD ================= */

class StudentPage extends StatefulWidget {
  const StudentPage({super.key});

  @override
  State<StudentPage> createState() => _StudentPageState();
}

class _StudentPageState extends State<StudentPage> {

  String status = "Not Marked";
  bool markedToday = false;
  bool loading = false;

  String today() {
    return DateFormat('yyyy-MM-dd').format(DateTime.now());
  }

  /* ================= LOAD TODAY STATUS ================= */

  @override
  void initState() {
    super.initState();
    checkTodayStatus();
  }

  Future<void> checkTodayStatus() async {

    final user = FirebaseAuth.instance.currentUser!;
    final id = "${user.uid}_${today()}";

    final doc = await FirebaseFirestore.instance
        .collection('attendance')
        .doc(id)
        .get();

    if (doc.exists) {
      setState(() {
        markedToday = true;
        status = doc['status'];
      });
    }
  }

  /* ================= MARK ATTENDANCE ================= */

  Future<void> mark(String statusValue) async {

    final user = FirebaseAuth.instance.currentUser!;
    final date = today();

    final id = "${user.uid}_$date";

    final ref = FirebaseFirestore.instance
        .collection('attendance')
        .doc(id);

    if ((await ref.get()).exists) {
      setState(() {
        markedToday = true;
        status = "Already Marked";
      });

      throw "Attendance already marked today";
    }

    /// ✅ INSTANT UI UPDATE (FAST)
    setState(() {
      status = statusValue;
      markedToday = true;
      loading = true;
    });

    /// Run heavy work in BACKGROUND
    Future(() async {

      try {

        /// 📍 LOCATION
        final position = await Geolocator.getCurrentPosition(
            desiredAccuracy: LocationAccuracy.high);

        double lat = position.latitude;
        double lng = position.longitude;

        /// 🌍 PLACE NAME
        List<Placemark> places =
            await placemarkFromCoordinates(lat, lng);

        String locationName = "Unknown";

        if (places.isNotEmpty) {
          final place = places.first;
          locationName =
              "${place.locality}, ${place.administrativeArea}";
        }

        /// ✅ SAVE FIRESTORE
        await ref.set({
          'email': user.email,
          'uid': user.uid,
          'date': date,
          'time': DateFormat('HH:mm:ss').format(DateTime.now()),
          'status': statusValue,
          'timestamp': FieldValue.serverTimestamp(),
          'location': locationName,
          'lat': lat,
          'lng': lng,
        });

        /// ✅ GOOGLE SHEET (BACKGROUND)
        await GoogleSheetService.sendAttendance(
          email: user.email!,
          date: date,
          time: DateFormat('HH:mm:ss').format(DateTime.now()),
          status: statusValue,
          location: locationName,
        );

      } catch (e) {
        debugPrint("Background error: $e");
      }

      if (mounted) {
        setState(() {
          loading = false;
        });
      }
    });
  }

  /* ================= LOCATION CHECK FUNCTION ================= */

Future<bool> checkLocation(BuildContext context) async {

  bool serviceEnabled =
      await Geolocator.isLocationServiceEnabled();

  if (!serviceEnabled) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
          content: Text("Turn ON Location Services")),
    );
    return false;
  }

  LocationPermission permission =
      await Geolocator.checkPermission();

  /// FIRST TIME DENIED
  if (permission == LocationPermission.denied) {
    permission = await Geolocator.requestPermission();
  }

  /// USER DENIED AGAIN
  if (permission == LocationPermission.denied) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
          content: Text("Location permission required")),
    );
    return false;
  }

  /// PERMANENTLY DENIED
  if (permission == LocationPermission.deniedForever) {

    await Geolocator.openAppSettings();

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
          content:
              Text("Enable location permission from settings")),
    );
    return false;
  }

  /// ✅ GET LOCATION
  Position position =
      await Geolocator.getCurrentPosition(
    desiredAccuracy: LocationAccuracy.high,
  );

  print(position.latitude);

  return true;
}

/* ================= UI ================= */

@override
Widget build(BuildContext context) {

  final user = FirebaseAuth.instance.currentUser!;

  String currentTime =
      DateFormat('hh:mm a').format(DateTime.now());

  return Scaffold(
    appBar: AppBar(
      title: const Text("Student Dashboard"),
      actions: [
        IconButton(
          icon: const Icon(Icons.logout),
          onPressed: () =>
              FirebaseAuth.instance.signOut(),
        )
      ],
    ),

    body: Padding(
      padding: const EdgeInsets.all(20),

      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [

          /// ✅ APP LOGO
          Image.asset(
            "assets/app_logo.png",
            height: 120,
          ),

          const SizedBox(height: 20),

          /// ✅ EMAIL
          Text(
            user.email!,
            style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),

          const SizedBox(height: 25),

          /// ✅ DATE CARD
          Card(
            elevation: 3,
            child: ListTile(
              leading: const Icon(Icons.calendar_today),
              title: Text(today()),
              subtitle: Text("Time: $currentTime"),
            ),
          ),

          const SizedBox(height: 25),

          /// ✅ STATUS
          Text(
            "Status: $status",
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: status == "Present"
                  ? Colors.green
                  : status == "Absent"
                      ? Colors.red.shade400
                      : const Color.fromARGB(255, 54, 53, 53),
            ),
          ),

          const SizedBox(height: 30),

          if (loading)
            const CircularProgressIndicator(),

          const SizedBox(height: 15),

          /// ✅ PRESENT BUTTON
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              icon: const Icon(Icons.check),
              label: const Text("Mark Present"),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                padding:
                    const EdgeInsets.symmetric(vertical: 15),
              ),
              onPressed: markedToday
                  ? null
                  : () async {

                      bool allowed =
                          await checkLocation(context);

                      if (!allowed) return;

                      ScaffoldMessenger.of(context)
                          .showSnackBar(
                        const SnackBar(
                            content: Text("Present ✅")),
                      );

                      mark("Present");
                    },
            ),
          ),

          const SizedBox(height: 15),

          /// ❌ ABSENT BUTTON (LIGHT RED + LOCATION CHECK)
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              icon: const Icon(Icons.close),
              label: const Text("Mark Absent"),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red.shade400,
                padding:
                    const EdgeInsets.symmetric(vertical: 15),
              ),
              onPressed: markedToday
                  ? null
                  : () async {

                      bool allowed =
                          await checkLocation(context);

                      if (!allowed) return;

                      ScaffoldMessenger.of(context)
                          .showSnackBar(
                        const SnackBar(
                            content: Text("Absent ❌")),
                      );

                      mark("Absent");
                    },
            ),
          ),
        ],
      ),
    ),
  );
}
}
/* ================= ADMIN ================= */

class AdminPage extends StatefulWidget {
  const AdminPage({super.key});

  @override
  State<AdminPage> createState() => _AdminPageState();
}

class _AdminPageState extends State<AdminPage> {

  // ✅ Selected Date (Default = Today)
  String selectedDate =
      DateFormat('yyyy-MM-dd').format(DateTime.now());

  // ✅ Pick Date Function
  Future<void> pickDate() async {

    DateTime? picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2023),
      lastDate: DateTime.now(),
    );

    if (picked != null) {
      setState(() {
        selectedDate =
            DateFormat('yyyy-MM-dd').format(picked);
      });
    }
  }

  



  /*Future<void> exportToExcel() async {
  try {
    final snapshot = await FirebaseFirestore.instance
        .collection('attendance')
        .where('date', isEqualTo: selectedDate)
        .orderBy('timestamp', descending: true)
        .get();

    if (snapshot.docs.isEmpty) {
      throw "No data found";
    }

    var excel = Excel.createExcel();
    Sheet sheet = excel['Attendance'];

    // Header
    sheet.appendRow([
      TextCellValue('Email'),
      TextCellValue('Date'),
      TextCellValue('Time'),
      TextCellValue('Status'),
    ]);

    // Data
    for (var doc in snapshot.docs) {
      final d = doc.data();

      sheet.appendRow([
        TextCellValue(d['email'] ?? ''),
        TextCellValue(d['date'] ?? ''),
        TextCellValue(d['time'] ?? ''),
        TextCellValue(d['status'] ?? ''),
      ]);
    }

    final dir = await getExternalStorageDirectory();
    final path = "${dir!.path}/attendance.xlsx";

    final file = File(path);
    file.writeAsBytesSync(excel.encode()!);

    await OpenFile.open(path);

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Excel Exported ✅")),
    );

  } catch (e) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(e.toString())),
    );
  }
}*/
Future<void> exportStudentReport() async {

  final snapshot = await FirebaseFirestore.instance
      .collection('attendance')
      .orderBy('email')
      .orderBy('timestamp', descending: true)
      .get();

  if (snapshot.docs.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("No student data found")),
    );
    return;
  }

  var excel = Excel.createExcel();
  Sheet sheet = excel['Student Report'];

  sheet.appendRow([
    TextCellValue('Email'),
    TextCellValue('Date'),
    TextCellValue('Time'),
    TextCellValue('Status'),
  ]);

  for (var doc in snapshot.docs) {
    final d = doc.data() as Map<String, dynamic>;

    sheet.appendRow([
      TextCellValue(d['email'] ?? ''),
      TextCellValue(d['date'] ?? ''),
      TextCellValue(d['time'] ?? ''),
      TextCellValue(d['status'] ?? ''),
    ]);
  }

  final dir = await getExternalStorageDirectory();
  final path = "${dir!.path}/Student_Report.xlsx";

  final file = File(path);
  file.writeAsBytesSync(excel.encode()!);

  await OpenFile.open(path);

  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(content: Text("Student Report Downloaded ✅")),
  );
}

Future<void> exportSelectedDay() async {

  await exportToExcel(
    date: selectedDate, // 👈 use selected date
    fileName: "Day_Report_$selectedDate.xlsx",
  );
}




  Future<void> exportToExcel({
  String? date,
  String? month,
  String? email,
  required String fileName,
}) async {
  try {
    Query query =
        FirebaseFirestore.instance.collection('attendance');

    // 📅 Day-wise
    if (date != null) {
      query = query.where('date', isEqualTo: date);
    }

    // 📆 Month-wise (yyyy-MM)
    if (month != null) {
      query = query
          .where('date', isGreaterThanOrEqualTo: "$month-01")
          .where('date', isLessThanOrEqualTo: "$month-31");
    }

    // 👨‍🎓 Student-wise
    if (email != null) {
      query = query.where('email', isEqualTo: email);
    }

    final snapshot = await query
        .orderBy('timestamp', descending: true)
        .get();

    if (snapshot.docs.isEmpty) {
      throw "No data found";
    }

    // 📊 Create Excel
    var excel = Excel.createExcel();
    Sheet sheet = excel['Attendance'];

    // Header
    sheet.appendRow([
      TextCellValue('Email'),
      TextCellValue('Date'),
      TextCellValue('Time'),
      TextCellValue('Status'),
    ]);

    // Rows
    for (var doc in snapshot.docs) {
      final d = doc.data() as Map<String, dynamic>;

      sheet.appendRow([
        TextCellValue(d['email'] ?? ''),
        TextCellValue(d['date'] ?? ''),
        TextCellValue(d['time'] ?? ''),
        TextCellValue(d['status'] ?? ''),
      ]);
    }

    // 📁 Save
    final dir = await getExternalStorageDirectory();
    final path = "${dir!.path}/$fileName";

    final file = File(path);
    file.writeAsBytesSync(excel.encode()!);

    await OpenFile.open(path);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("Saved: $fileName ✅")),
    );
  } catch (e) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(e.toString())),
    );
  }
}




// ✅ Today Report
Future<void> exportToday() async {
  final today =
      DateFormat('yyyy-MM-dd').format(DateTime.now());

  await exportToExcel(
    date: today,
    fileName: "Today_Report_$today.xlsx",
  );
}

// ✅ Monthly Report
Future<void> exportMonth() async {
  final month =
      DateFormat('yyyy-MM').format(DateTime.now());

  await exportToExcel(
    month: month,
    fileName: "Month_Report_$month.xlsx",
  );
}

// ✅ Student Report
Future<void> exportStudent(String email) async {
  await exportToExcel(
    email: email,
    fileName: "Student_$email.xlsx",
  );
}




  @override
  Widget build(BuildContext context) {
    return Scaffold(

      // ================= APPBAR =================

      appBar: AppBar(
        title: const Text("Admin"),

        actions: [

          // 📅 Calendar Button
          IconButton(
            icon: const Icon(Icons.calendar_today),
            onPressed: pickDate,
          ),

          // ➕ Add User
          IconButton(
            icon: const Icon(Icons.person_add),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const AddUserPage(),
                ),
              );
            },
          ),

         // ⋮ Reports Menu (NEW)
    // ⋮ Reports Menu
PopupMenuButton<String>(
  tooltip: "Reports",

  onSelected: (value) async {

    if (value == 'day') {
      await exportSelectedDay();
    }

    if (value == 'month') {
      await exportMonth();
    }

    if (value == 'student') {
      //final user = FirebaseAuth.instance.currentUser!;
      await exportStudentReport();
    }

    if (value == 'logout') {
      await FirebaseAuth.instance.signOut();
    }
  },

  itemBuilder: (context) => const [

    PopupMenuItem(
      value: 'day',
      child: Text("📅 Today Report"),
    ),

    PopupMenuItem(
      value: 'month',
      child: Text("📊 Monthly Report"),
    ),

    PopupMenuItem(
      value: 'student',
      child: Text("👨‍🎓 Student Report"),
    ),

    PopupMenuItem(
      value: 'logout',
      child: Text("🚪 Logout"),
    ),
  ],
),
        ],
),

        
      

      // ================= BODY =================

      body: Column(
        children: [

          // ✅ Show Selected Date
          Padding(
            padding: const EdgeInsets.all(8),
            child: Text(
              "Showing: $selectedDate",
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
          ),

          // ================= STREAM =================

          Expanded(
            child: StreamBuilder(
              stream: FirebaseFirestore.instance
                  .collection('attendance')

                  // ✅ Date Filter
                  .where('date', isEqualTo: selectedDate)

                  // Order
                  .orderBy('timestamp', descending: true)
                  .snapshots(),

              builder: (context, snapshot) {

                if (!snapshot.hasData) {
                  return const Center(
                      child: CircularProgressIndicator());
                }

                final docs = snapshot.data!.docs;

                if (docs.isEmpty) {
                  return const Center(
                      child: Text("No Records"));
                }

                return ListView.builder(
                  itemCount: docs.length,

                  itemBuilder: (context, i) {

                    final d =
                        docs[i].data() as Map<String, dynamic>;

                    final time = d['time'] ?? 'N/A';

                    // ✅ NEW: Get Location
                    final location =
                        d['location'] ?? "Location not available";

                    return ListTile(

                      // 📧 Email
                      title: Text(d['email'] ?? ''),

                      // 📅 Date + Time + Location
                      subtitle: Text(
                        "${d['date']} | $time\n📍 $location",
                      ),

                      // ✅ Status
                      trailing: Text(
                        d['status'],
                        style: TextStyle(
                          color: d['status'] == "Present"
                              ? Colors.green
                              : Colors.red,
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/* ================= ADD USER ================= */

class AddUserPage extends StatefulWidget {
  const AddUserPage({super.key});

  @override
  State<AddUserPage> createState() => _AddUserPageState();
}

class _AddUserPageState extends State<AddUserPage> {

  final email = TextEditingController();
  final pass = TextEditingController();

  bool loading = false;

  Future<void> create() async {
  setState(() => loading = true);

  try {

    String userEmail = email.text.trim();

    /// ✅ Decide role automatically
    String role =
        userEmail.toLowerCase().endsWith("@gmail.com")
            ? "admin"
            : "student";

    final cred =
        await FirebaseAuth.instance.createUserWithEmailAndPassword(
      email: userEmail,
      password: pass.text.trim(),
    );

    /// ✅ Save in Firestore
    await FirebaseFirestore.instance
        .collection('users')
        .doc(cred.user!.uid)
        .set({
      'email': userEmail,
      'role': role,
    });

    Navigator.pop(context);

    /// ✅ Show correct message
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          role == "admin"
              ? "Admin Added ✅"
              : "Student Added ✅",
        ),
      ),
    );

  } catch (e) {

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(e.toString())),
    );
  }

  setState(() => loading = false);
}

  @override
  Widget build(BuildContext context) {

    return Scaffold(
      appBar: AppBar(title: const Text("Add Student")),

      body: Padding(
        padding: const EdgeInsets.all(20),

        child: Column(
          children: [

            TextField(
              controller: email,
              decoration: const InputDecoration(labelText: "Email"),
            ),

            const SizedBox(height: 15),

            TextField(
              controller: pass,
              obscureText: true,
              decoration: const InputDecoration(labelText: "Password"),
            ),

            const SizedBox(height: 20),

            loading
                ? const CircularProgressIndicator()
                : ElevatedButton(
                    onPressed: create,
                    child: const Text("Create"),
                  ),
          ],
        ),
      ),
    );
  }
}