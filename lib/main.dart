import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:intl/intl.dart';
import 'package:google_fonts/google_fonts.dart';

import 'firebase_options.dart';
import 'websocket_stream_widget.dart';
import 'services/simple_notification_service.dart';

// SmartHaus Color Palette
class SmartHausColors {
  static const Color primary = Color(0xFF0abcea); // Bright blue
  static const Color secondary = Color(0xFF57d4a6); // Light green
  static const Color accent = Color(0xFF146484); // Dark blue
  static const Color teal = Color(0xFF4aa78c); // Teal
  static const Color lightGray = Color(0xFF9cb7b6); // Light gray-green
  static const Color darkGreen = Color(0xFF345c4c); // Dark green
  static const Color white = Color(0xFFFFFFFF);
  static const Color background = Color(0xFFF8FAFA); // Very light gray-white
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // Initialize notification service
  await NotificationService().initialize();

  runApp(const MyApp());
}

final GlobalKey<ScaffoldMessengerState> _scaffoldMessengerKey =
    GlobalKey<ScaffoldMessengerState>();

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'SmartHaus',
    home: AuthGate(),
    debugShowCheckedModeBanner: false,
    scaffoldMessengerKey: _scaffoldMessengerKey,
    theme: ThemeData(
      primarySwatch: MaterialColor(SmartHausColors.primary.value, <int, Color>{
        50: SmartHausColors.primary.withOpacity(0.1),
        100: SmartHausColors.primary.withOpacity(0.2),
        200: SmartHausColors.primary.withOpacity(0.3),
        300: SmartHausColors.primary.withOpacity(0.4),
        400: SmartHausColors.primary.withOpacity(0.5),
        500: SmartHausColors.primary,
        600: SmartHausColors.accent,
        700: SmartHausColors.accent,
        800: SmartHausColors.darkGreen,
        900: SmartHausColors.darkGreen,
      }),
      primaryColor: SmartHausColors.primary,
      colorScheme: ColorScheme.fromSeed(
        seedColor: SmartHausColors.primary,
        primary: SmartHausColors.primary,
        secondary: SmartHausColors.secondary,
        background: SmartHausColors.background,
        surface: SmartHausColors.white,
      ),
      textTheme: GoogleFonts.interTextTheme(),
      appBarTheme: AppBarTheme(
        backgroundColor: SmartHausColors.white,
        foregroundColor: SmartHausColors.accent,
        elevation: 0,
        titleTextStyle: GoogleFonts.poppins(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: SmartHausColors.accent,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: SmartHausColors.primary,
          foregroundColor: SmartHausColors.white,
          textStyle: GoogleFonts.poppins(
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
        ),
      ),
      useMaterial3: true,
    ),
  );
}

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.hasData) {
          return DashboardPage();
        }
        return LoginPage();
      },
    );
  }
}

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  StreamSubscription? _securityListener;
  StreamSubscription? _waterLevelListener;
  DatabaseReference? _database;
  int _waterLevel = 1; // 1 = water present, 0 = no water
  String _waterLastUpdated = '';

  @override
  void initState() {
    super.initState();
    _initializeMonitoring();
  }

  @override
  void dispose() {
    _securityListener?.cancel();
    _waterLevelListener?.cancel();
    super.dispose();
  }

  void _initializeMonitoring() {
    _database = FirebaseDatabase.instance.ref();
    _initializeSecurityMonitoring();
    _initializeWaterLevelMonitoring();
  }

  void _initializeSecurityMonitoring() {
    // Listen for failed attempts on fingerprint door
    _securityListener = _database!
        .child('devices/fingerprint_door_001/failed_attempts')
        .onValue
        .listen((event) {
          final failedAttempts = event.snapshot.value as int? ?? 0;

          if (failedAttempts >= 3) {
            _showSecurityAlert(failedAttempts);
          }
        });
  }

  void _initializeWaterLevelMonitoring() {
    // Listen for water level changes
    _waterLevelListener = _database!
        .child('devices/water_level_001')
        .onValue
        .listen((event) {
          if (event.snapshot.value != null) {
            final data = event.snapshot.value as Map<dynamic, dynamic>;
            setState(() {
              _waterLevel = data['water_level'] ?? 1;
              _waterLastUpdated = data['last_updated'] ?? '';
            });

            // Show alert if water level is empty (0)
            if (_waterLevel == 0) {
              _showWaterAlert();
            }
          }
        });
  }

  void _showSecurityAlert(int failedAttempts) {
    // Show notification in notification bar with sound
    NotificationService().showSecurityAlert(
      title: 'Security Alert!',
      body:
          '$failedAttempts failed fingerprint attempts detected at your door.',
      failedAttempts: failedAttempts,
    );

    // Show in-app dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          backgroundColor: SmartHausColors.white,
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.security,
                  color: Colors.red.shade600,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Security Alert',
                  style: GoogleFonts.poppins(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: SmartHausColors.darkGreen,
                  ),
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Multiple Failed Access Attempts',
                style: GoogleFonts.poppins(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.red.shade700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '$failedAttempts failed fingerprint attempts detected at your door.',
                style: GoogleFonts.inter(
                  fontSize: 14,
                  color: SmartHausColors.darkGreen,
                ),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orange.shade200, width: 1),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.info_outline,
                      color: Colors.orange.shade700,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Time: ${DateFormat('MMM dd, yyyy - HH:mm').format(DateTime.now())}',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          color: Colors.orange.shade700,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: Text(
                'Dismiss',
                style: GoogleFonts.inter(
                  color: SmartHausColors.lightGray,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                gradient: const LinearGradient(
                  colors: [SmartHausColors.primary, SmartHausColors.secondary],
                ),
              ),
              child: TextButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  _resetFailedAttempts();
                },
                child: Text(
                  'Reset & Acknowledge',
                  style: GoogleFonts.inter(
                    color: SmartHausColors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  void _resetFailedAttempts() {
    _database?.child('devices/fingerprint_door_001/failed_attempts').set(0);

    _scaffoldMessengerKey.currentState?.showSnackBar(
      SnackBar(
        content: Text(
          'Failed attempts counter has been reset',
          style: GoogleFonts.inter(color: SmartHausColors.white),
        ),
        backgroundColor: SmartHausColors.secondary,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _showWaterAlert() {
    // Show notification in notification bar
    NotificationService().showSecurityAlert(
      title: 'Water Level Alert!',
      body: 'Water tank is empty. Please refill the tank.',
      failedAttempts: 0,
    );

    // Show in-app dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          backgroundColor: SmartHausColors.white,
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.water_drop_outlined,
                  color: Colors.orange.shade600,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Water Level Alert',
                  style: GoogleFonts.poppins(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: SmartHausColors.darkGreen,
                  ),
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Tank Empty',
                style: GoogleFonts.poppins(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.orange.shade700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Your water tank is empty. Please refill the tank to ensure continuous water supply.',
                style: GoogleFonts.inter(
                  fontSize: 14,
                  color: SmartHausColors.darkGreen,
                ),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.blue.shade200, width: 1),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.info_outline,
                      color: Colors.blue.shade700,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Time: ${DateFormat('MMM dd, yyyy - HH:mm').format(DateTime.now())}',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          color: Colors.blue.shade700,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                gradient: const LinearGradient(
                  colors: [SmartHausColors.primary, SmartHausColors.secondary],
                ),
              ),
              child: TextButton(
                onPressed: () {
                  Navigator.of(context).pop();
                },
                child: Text(
                  'Acknowledge',
                  style: GoogleFonts.inter(
                    color: SmartHausColors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SmartHausColors.background,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header Section
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'SmartHaus',
                    style: GoogleFonts.poppins(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      color: SmartHausColors.darkGreen,
                    ),
                  ),
                  Container(
                    decoration: BoxDecoration(
                      color: SmartHausColors.white,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: SmartHausColors.accent.withOpacity(0.08),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: IconButton(
                      icon: Icon(
                        Icons.logout,
                        color: SmartHausColors.accent,
                        size: 24,
                      ),
                      onPressed: () async {
                        await FirebaseAuth.instance.signOut();
                      },
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 32),

              // Welcome Text
              Text(
                'Welcome to your smart home dashboard',
                style: GoogleFonts.inter(
                  fontSize: 16,
                  color: SmartHausColors.lightGray,
                  fontWeight: FontWeight.w500,
                ),
              ),

              const SizedBox(height: 40),

              // First Section - ESP32 Camera
              Text(
                'Security',
                style: GoogleFonts.poppins(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  color: SmartHausColors.darkGreen,
                ),
              ),

              const SizedBox(height: 16),

              GestureDetector(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const IpStreamPage(),
                    ),
                  );
                },
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: SmartHausColors.white,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: SmartHausColors.accent.withOpacity(0.1),
                        blurRadius: 16,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [
                              SmartHausColors.primary,
                              SmartHausColors.secondary,
                            ],
                          ),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: const Icon(
                          Icons.videocam,
                          color: SmartHausColors.white,
                          size: 32,
                        ),
                      ),
                      const SizedBox(width: 20),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'ESP32 Camera',
                              style: GoogleFonts.poppins(
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                                color: SmartHausColors.darkGreen,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Live camera feed and capture',
                              style: GoogleFonts.inter(
                                fontSize: 14,
                                color: SmartHausColors.lightGray,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Icon(
                        Icons.arrow_forward_ios,
                        color: SmartHausColors.lightGray,
                        size: 20,
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 32),

              // Second Section - Future Features
              Text(
                'Smart Controls',
                style: GoogleFonts.poppins(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  color: SmartHausColors.darkGreen,
                ),
              ),

              const SizedBox(height: 16),

              GestureDetector(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const SmartControlsPage(),
                    ),
                  );
                },
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: SmartHausColors.white,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: SmartHausColors.accent.withOpacity(0.1),
                        blurRadius: 16,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [
                              SmartHausColors.secondary,
                              SmartHausColors.teal,
                            ],
                          ),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: const Icon(
                          Icons.electrical_services,
                          color: SmartHausColors.white,
                          size: 32,
                        ),
                      ),
                      const SizedBox(width: 20),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Smart Controls',
                              style: GoogleFonts.poppins(
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                                color: SmartHausColors.darkGreen,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Control relays and smart devices',
                              style: GoogleFonts.inter(
                                fontSize: 14,
                                color: SmartHausColors.lightGray,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Icon(
                        Icons.arrow_forward_ios,
                        color: SmartHausColors.lightGray,
                        size: 20,
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 32),

              // Third Section - Water Level Monitoring
              Text(
                'Monitoring',
                style: GoogleFonts.poppins(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  color: SmartHausColors.darkGreen,
                ),
              ),

              const SizedBox(height: 16),

              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: SmartHausColors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: SmartHausColors.accent.withOpacity(0.1),
                      blurRadius: 16,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    // Water Level Icon with Animation
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: _waterLevel == 1
                              ? [
                                  SmartHausColors.primary,
                                  SmartHausColors.secondary,
                                ]
                              : [Colors.orange.shade400, Colors.red.shade400],
                        ),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Stack(
                        children: [
                          Icon(
                            _waterLevel == 1
                                ? Icons.water_drop
                                : Icons.water_drop_outlined,
                            color: SmartHausColors.white,
                            size: 32,
                          ),
                          if (_waterLevel == 0)
                            Positioned(
                              right: -2,
                              top: -2,
                              child: Container(
                                width: 12,
                                height: 12,
                                decoration: BoxDecoration(
                                  color: Colors.red.shade600,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: SmartHausColors.white,
                                    width: 2,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 20),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Water Level Monitor',
                            style: GoogleFonts.poppins(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                              color: SmartHausColors.darkGreen,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Text(
                                'Status: ',
                                style: GoogleFonts.inter(
                                  fontSize: 14,
                                  color: SmartHausColors.lightGray,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              Text(
                                _waterLevel == 1
                                    ? 'Water Present'
                                    : 'Tank Empty',
                                style: GoogleFonts.inter(
                                  fontSize: 14,
                                  color: _waterLevel == 1
                                      ? SmartHausColors.teal
                                      : Colors.red.shade600,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                          if (_waterLastUpdated.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(
                              'Updated: ${_waterLastUpdated}',
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                color: SmartHausColors.lightGray.withOpacity(
                                  0.8,
                                ),
                                fontWeight: FontWeight.w400,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    // Status Indicator
                    Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: _waterLevel == 1
                            ? SmartHausColors.secondary
                            : Colors.red.shade500,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color:
                                (_waterLevel == 1
                                        ? SmartHausColors.secondary
                                        : Colors.red.shade500)
                                    .withOpacity(0.3),
                            blurRadius: 8,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 32),

              // Bottom Info
              Center(
                child: Text(
                  'SmartHaus v1.0',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: SmartHausColors.lightGray.withOpacity(0.7),
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ),

              const SizedBox(height: 20), // Bottom padding
            ],
          ),
        ),
      ),
    );
  }
}

class SmartControlsPage extends StatefulWidget {
  const SmartControlsPage({super.key});

  @override
  State<SmartControlsPage> createState() => _SmartControlsPageState();
}

class _SmartControlsPageState extends State<SmartControlsPage> {
  DatabaseReference? _database;
  List<Map<String, dynamic>> _relays = [];
  bool _isSystemEnabled = true;
  bool _isLoading = true;
  int _maxRelayCount = 6;
  int _nextRelayId = 1;

  @override
  void initState() {
    super.initState();
    print('SmartControlsPage initState called');
    _initializeDatabase();
    _initializeRelayData();

    // Add timeout to prevent infinite loading
    Timer(const Duration(seconds: 10), () {
      if (_isLoading) {
        print('Loading timeout reached, stopping loading...');
        setState(() {
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Connection timeout. Please check your internet connection.',
            ),
            backgroundColor: Colors.orange,
          ),
        );
      }
    });
  }

  void _initializeDatabase() {
    try {
      _database = FirebaseDatabase.instance.ref();
      print('Database initialized successfully');
    } catch (e) {
      print('Error initializing database: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _initializeRelayData() async {
    try {
      print('Starting relay data initialization...');

      // Check if database is initialized
      if (_database == null) {
        print('Database is null, reinitializing...');
        _initializeDatabase();
        return;
      }

      // Check if smart_controls exists
      final smartControlsRef = _database!.child('smart_controls/relays');
      final snapshot = await smartControlsRef.get();

      if (!snapshot.exists) {
        print('No smart_controls data exists, creating default structure...');
        await _createDefaultRelayData();
      }

      print('Relay initialization complete, loading states...');
      // Load relay states
      _loadRelayStates();
    } catch (e) {
      print('Error initializing relay data: $e');
      setState(() {
        _isLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error connecting to database: $e')),
      );
    }
  }

  void _loadRelayStates() {
    try {
      print('Setting up relay state listener...');
      _database!
          .child('smart_controls/relays')
          .onValue
          .listen(
            (event) {
              print('Relay data received: ${event.snapshot.exists}');
              if (event.snapshot.exists) {
                final rawData = event.snapshot.value;
                print('Raw relay data type: ${rawData.runtimeType}');
                print('Raw relay data: $rawData');

                setState(() {
                  _relays = [];

                  // Handle different data structures
                  if (rawData is Map<dynamic, dynamic>) {
                    // Load all relays dynamically (not just 1-3)
                    rawData.forEach((key, value) {
                      if (value is Map) {
                        final relayData = Map<String, dynamic>.from(value);
                        _relays.add(relayData);
                        print('Added relay: $relayData');
                      }
                    });

                    // Sort relays by ID
                    _relays.sort((a, b) => a['id'].compareTo(b['id']));

                    // Calculate next available relay ID
                    _calculateNextRelayId();
                  } else if (rawData is List) {
                    // Handle list structure
                    for (int i = 0; i < rawData.length; i++) {
                      if (rawData[i] != null && rawData[i] is Map) {
                        final relayData = Map<String, dynamic>.from(rawData[i]);
                        if (!_relays.any((r) => r['id'] == relayData['id'])) {
                          _relays.add(relayData);
                          print('Added relay from list: $relayData');
                        }
                      }
                    }

                    // Sort relays by ID
                    _relays.sort((a, b) => a['id'].compareTo(b['id']));

                    // Calculate next available relay ID
                    _calculateNextRelayId();
                  } else {
                    print('Unexpected data type: ${rawData.runtimeType}');
                  }

                  _isLoading = false;
                });
                print('Total relays loaded: ${_relays.length}');
              } else {
                print('No relay data exists, creating default data...');
                // Create default data and then load it
                _createDefaultRelayData().then((_) {
                  setState(() {
                    _isLoading = false;
                  });
                });
              }
            },
            onError: (error) {
              print('Error listening to relay states: $error');
              setState(() {
                _isLoading = false;
              });
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Error loading relay data: $error')),
              );
            },
          );
    } catch (e) {
      print('Error setting up relay listener: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _createDefaultRelayData() async {
    try {
      for (int i = 1; i <= 3; i++) {
        await _database!.child('smart_controls/relays/$i').set({
          'id': i,
          'name': 'Relay $i',
          'state': false,
          'last_updated': DateTime.now().toString().substring(0, 19),
        });
        print('Created default relay $i');
      }
    } catch (e) {
      print('Error creating default relay data: $e');
    }
  }

  void _toggleRelay(int relayId, bool currentState) async {
    if (!_isSystemEnabled) return;

    try {
      final newState = !currentState;
      final timestamp = DateTime.now().toString().substring(0, 19);

      // Update relay state
      await _database!.child('smart_controls/relays/$relayId').update({
        'state': newState,
        'last_updated': timestamp,
      });
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error toggling relay: $e')));
    }
  }

  void _updateRelayName(int relayId, String newName) async {
    try {
      final timestamp = DateTime.now().toString().substring(0, 19);

      await _database!.child('smart_controls/relays/$relayId').update({
        'name': newName,
        'last_updated': timestamp,
      });
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error updating name: $e')));
    }
  }

  void _calculateNextRelayId() {
    Set<int> existingIds = _relays.map((relay) => relay['id'] as int).toSet();
    _nextRelayId = 1;
    while (existingIds.contains(_nextRelayId) &&
        _nextRelayId <= _maxRelayCount) {
      _nextRelayId++;
    }
    print('Next available relay ID: $_nextRelayId');
  }

  void _addNewRelay() async {
    if (_relays.length >= _maxRelayCount) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Maximum $_maxRelayCount relays allowed'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    try {
      final newId = _nextRelayId;
      final timestamp = DateTime.now().toString().substring(0, 19);

      // Create new relay in database
      await _database!.child('smart_controls/relays/$newId').set({
        'id': newId,
        'name': 'Relay $newId',
        'state': false,
        'last_updated': timestamp,
      });

      print('Added new relay with ID: $newId');

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Relay $newId added successfully'),
          backgroundColor: SmartHausColors.secondary,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error adding relay: $e')));
    }
  }

  void _removeRelay(int relayId) {
    setState(() {
      _relays.removeWhere((relay) => relay['id'] == relayId);
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Relay $relayId removed from app (database data preserved)',
        ),
        backgroundColor: Colors.orange,
      ),
    );

    // Recalculate next relay ID
    _calculateNextRelayId();
  }

  void _showDeleteConfirmation(int relayId, String relayName) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Remove Relay', style: GoogleFonts.poppins()),
        content: Text(
          'Remove "$relayName" from the app?\n\nNote: Data will remain in database and can be restored by adding a relay with the same ID.',
          style: GoogleFonts.inter(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _removeRelay(relayId);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
  }

  void _showEditNameDialog(int relayId, String currentName) {
    final controller = TextEditingController(text: currentName);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Edit Relay Name', style: GoogleFonts.poppins()),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            hintText: 'Enter relay name (e.g., Fan, Lights)',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              if (controller.text.trim().isNotEmpty) {
                _updateRelayName(relayId, controller.text.trim());
                Navigator.pop(context);
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SmartHausColors.background,
      appBar: AppBar(
        backgroundColor: SmartHausColors.background,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios,
            color: SmartHausColors.darkGreen,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Smart Controls',
          style: GoogleFonts.poppins(
            fontSize: 24,
            fontWeight: FontWeight.w600,
            color: SmartHausColors.darkGreen,
          ),
        ),
        centerTitle: true,
        actions: [
          // System Enable/Disable Toggle
          Container(
            margin: const EdgeInsets.only(right: 16),
            child: Switch(
              value: _isSystemEnabled,
              onChanged: (value) {
                setState(() {
                  _isSystemEnabled = value;
                });
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      _isSystemEnabled
                          ? 'Smart Controls Enabled'
                          : 'Smart Controls Disabled',
                    ),
                    backgroundColor: _isSystemEnabled
                        ? SmartHausColors.secondary
                        : Colors.orange,
                  ),
                );
              },
              activeColor: SmartHausColors.secondary,
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: _isLoading
            ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(
                        SmartHausColors.secondary,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Loading Smart Controls...',
                      style: GoogleFonts.inter(
                        fontSize: 16,
                        color: SmartHausColors.lightGray,
                      ),
                    ),
                  ],
                ),
              )
            : SingleChildScrollView(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // System Status
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: _isSystemEnabled
                            ? SmartHausColors.secondary.withOpacity(0.1)
                            : Colors.orange.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: _isSystemEnabled
                              ? SmartHausColors.secondary
                              : Colors.orange,
                          width: 1,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            _isSystemEnabled ? Icons.power : Icons.power_off,
                            color: _isSystemEnabled
                                ? SmartHausColors.secondary
                                : Colors.orange,
                            size: 24,
                          ),
                          const SizedBox(width: 12),
                          Text(
                            _isSystemEnabled
                                ? 'System Enabled'
                                : 'System Disabled',
                            style: GoogleFonts.poppins(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: _isSystemEnabled
                                  ? SmartHausColors.secondary
                                  : Colors.orange,
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 32),

                    // Relay Controls Section
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Relay Controls',
                          style: GoogleFonts.poppins(
                            fontSize: 20,
                            fontWeight: FontWeight.w600,
                            color: SmartHausColors.darkGreen,
                          ),
                        ),
                        // Add Relay Button
                        Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: _relays.length < _maxRelayCount
                                  ? [
                                      SmartHausColors.secondary,
                                      SmartHausColors.teal,
                                    ]
                                  : [
                                      SmartHausColors.lightGray.withOpacity(
                                        0.5,
                                      ),
                                      SmartHausColors.lightGray.withOpacity(
                                        0.3,
                                      ),
                                    ],
                            ),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(12),
                              onTap: _relays.length < _maxRelayCount
                                  ? _addNewRelay
                                  : null,
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.add,
                                      color: _relays.length < _maxRelayCount
                                          ? SmartHausColors.white
                                          : SmartHausColors.lightGray,
                                      size: 20,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      'Add',
                                      style: GoogleFonts.inter(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                        color: _relays.length < _maxRelayCount
                                            ? SmartHausColors.white
                                            : SmartHausColors.lightGray,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 16),

                    // Relay Cards or Empty State
                    _relays.isEmpty
                        ? Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(32),
                            decoration: BoxDecoration(
                              color: SmartHausColors.white,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: SmartHausColors.lightGray.withOpacity(
                                  0.3,
                                ),
                                width: 1,
                              ),
                            ),
                            child: Column(
                              children: [
                                Icon(
                                  Icons.electrical_services_outlined,
                                  size: 48,
                                  color: SmartHausColors.lightGray,
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  'No Relays Added',
                                  style: GoogleFonts.poppins(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w600,
                                    color: SmartHausColors.darkGreen,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Click the + Add button above to add your first relay',
                                  style: GoogleFonts.inter(
                                    fontSize: 14,
                                    color: SmartHausColors.lightGray,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ),
                          )
                        : Column(
                            children: _relays
                                .map(
                                  (relay) => Container(
                                    width: double.infinity,
                                    margin: const EdgeInsets.only(bottom: 16),
                                    padding: const EdgeInsets.all(20),
                                    decoration: BoxDecoration(
                                      color: SmartHausColors.white,
                                      borderRadius: BorderRadius.circular(16),
                                      boxShadow: [
                                        BoxShadow(
                                          color: SmartHausColors.accent
                                              .withOpacity(0.1),
                                          blurRadius: 8,
                                          offset: const Offset(0, 2),
                                        ),
                                      ],
                                    ),
                                    child: Column(
                                      children: [
                                        Row(
                                          children: [
                                            // Relay Icon
                                            Container(
                                              padding: const EdgeInsets.all(12),
                                              decoration: BoxDecoration(
                                                color: relay['state']
                                                    ? SmartHausColors.secondary
                                                    : SmartHausColors.lightGray
                                                          .withOpacity(0.3),
                                                borderRadius:
                                                    BorderRadius.circular(12),
                                              ),
                                              child: Icon(
                                                Icons.electrical_services,
                                                color: relay['state']
                                                    ? SmartHausColors.white
                                                    : SmartHausColors.lightGray,
                                                size: 24,
                                              ),
                                            ),
                                            const SizedBox(width: 16),
                                            // Relay Info
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Row(
                                                    children: [
                                                      Text(
                                                        relay['name'],
                                                        style:
                                                            GoogleFonts.poppins(
                                                              fontSize: 18,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w600,
                                                              color:
                                                                  SmartHausColors
                                                                      .darkGreen,
                                                            ),
                                                      ),
                                                      const SizedBox(width: 8),
                                                      GestureDetector(
                                                        onTap: () =>
                                                            _showEditNameDialog(
                                                              relay['id'],
                                                              relay['name'],
                                                            ),
                                                        child: Icon(
                                                          Icons.edit,
                                                          color: SmartHausColors
                                                              .lightGray,
                                                          size: 16,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                  const SizedBox(height: 4),
                                                  Text(
                                                    'Status: ${relay['state'] ? 'ON' : 'OFF'}',
                                                    style: GoogleFonts.inter(
                                                      fontSize: 14,
                                                      color: relay['state']
                                                          ? SmartHausColors
                                                                .secondary
                                                          : SmartHausColors
                                                                .lightGray,
                                                      fontWeight:
                                                          FontWeight.w500,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            // Toggle Switch
                                            Switch(
                                              value: relay['state'],
                                              onChanged: _isSystemEnabled
                                                  ? (value) => _toggleRelay(
                                                      relay['id'],
                                                      relay['state'],
                                                    )
                                                  : null,
                                              activeColor:
                                                  SmartHausColors.secondary,
                                            ),
                                            const SizedBox(width: 8),
                                            // Delete Button
                                            Container(
                                              decoration: BoxDecoration(
                                                color: SmartHausColors.lightGray
                                                    .withOpacity(0.1),
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                              ),
                                              child: Material(
                                                color: Colors.transparent,
                                                child: InkWell(
                                                  borderRadius:
                                                      BorderRadius.circular(8),
                                                  onTap: () =>
                                                      _showDeleteConfirmation(
                                                        relay['id'],
                                                        relay['name'],
                                                      ),
                                                  child: Padding(
                                                    padding:
                                                        const EdgeInsets.all(8),
                                                    child: Icon(
                                                      Icons.delete_outline,
                                                      color: SmartHausColors
                                                          .lightGray,
                                                      size: 20,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                )
                                .toList(),
                          ),

                    const SizedBox(height: 40),
                  ],
                ),
              ),
      ),
    );
  }
}

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  String? _error;
  bool _loading = false;

  Future<void> _login() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );
    } catch (e) {
      setState(() {
        _error = e.toString();
      });
    } finally {
      setState(() {
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SmartHausColors.background,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 32.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SizedBox(height: 60),

                // SmartHaus Title with House Icon
                Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: SmartHausColors.primary.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Icon(
                        Icons.home_rounded,
                        size: 50,
                        color: SmartHausColors.accent,
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'SmartHaus',
                      style: GoogleFonts.poppins(
                        fontSize: 36,
                        fontWeight: FontWeight.w600,
                        color: SmartHausColors.accent,
                        letterSpacing: -0.5,
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 60),

                // Login Form Container
                Container(
                  padding: const EdgeInsets.all(32),
                  decoration: BoxDecoration(
                    color: SmartHausColors.white,
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                        color: SmartHausColors.accent.withOpacity(0.08),
                        blurRadius: 20,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Welcome',
                        style: GoogleFonts.poppins(
                          fontSize: 24,
                          fontWeight: FontWeight.w600,
                          color: SmartHausColors.darkGreen,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Sign in to continue',
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          color: SmartHausColors.lightGray,
                        ),
                        textAlign: TextAlign.center,
                      ),

                      const SizedBox(height: 32),

                      // Email Field
                      TextField(
                        controller: _emailController,
                        keyboardType: TextInputType.emailAddress,
                        style: GoogleFonts.inter(
                          fontSize: 16,
                          color: SmartHausColors.darkGreen,
                        ),
                        decoration: InputDecoration(
                          labelText: 'Email',
                          labelStyle: GoogleFonts.inter(
                            color: SmartHausColors.lightGray,
                            fontSize: 14,
                          ),
                          prefixIcon: Icon(
                            Icons.email_outlined,
                            color: SmartHausColors.teal,
                          ),
                          filled: true,
                          fillColor: SmartHausColors.background,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: BorderSide.none,
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: BorderSide(
                              color: SmartHausColors.primary,
                              width: 2,
                            ),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 16,
                          ),
                        ),
                      ),

                      const SizedBox(height: 20),

                      // Password Field
                      TextField(
                        controller: _passwordController,
                        obscureText: true,
                        style: GoogleFonts.inter(
                          fontSize: 16,
                          color: SmartHausColors.darkGreen,
                        ),
                        decoration: InputDecoration(
                          labelText: 'Password',
                          labelStyle: GoogleFonts.inter(
                            color: SmartHausColors.lightGray,
                            fontSize: 14,
                          ),
                          prefixIcon: Icon(
                            Icons.lock_outlined,
                            color: SmartHausColors.teal,
                          ),
                          filled: true,
                          fillColor: SmartHausColors.background,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: BorderSide.none,
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: BorderSide(
                              color: SmartHausColors.primary,
                              width: 2,
                            ),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 16,
                          ),
                        ),
                      ),

                      const SizedBox(height: 24),

                      // Error Message
                      if (_error != null) ...[
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.red.shade50,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: Colors.red.shade200,
                              width: 1,
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.error_outline,
                                color: Colors.red.shade600,
                                size: 20,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _error!,
                                  style: GoogleFonts.inter(
                                    color: Colors.red.shade700,
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),
                      ],

                      // Login Button
                      _loading
                          ? Container(
                              height: 56,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(16),
                                gradient: LinearGradient(
                                  colors: [
                                    SmartHausColors.primary.withOpacity(0.7),
                                    SmartHausColors.secondary.withOpacity(0.7),
                                  ],
                                ),
                              ),
                              child: const Center(
                                child: CircularProgressIndicator(
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    SmartHausColors.white,
                                  ),
                                ),
                              ),
                            )
                          : Container(
                              height: 56,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(16),
                                gradient: const LinearGradient(
                                  colors: [
                                    SmartHausColors.primary,
                                    SmartHausColors.secondary,
                                  ],
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: SmartHausColors.primary.withOpacity(
                                      0.3,
                                    ),
                                    blurRadius: 12,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: ElevatedButton(
                                onPressed: _login,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.transparent,
                                  shadowColor: Colors.transparent,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                ),
                                child: Text(
                                  'Sign In',
                                  style: GoogleFonts.poppins(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                    color: SmartHausColors.white,
                                  ),
                                ),
                              ),
                            ),
                    ],
                  ),
                ),

                const SizedBox(height: 40),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class IpStreamPage extends StatefulWidget {
  const IpStreamPage({super.key});

  @override
  State<IpStreamPage> createState() => _IpStreamPageState();
}

class _IpStreamPageState extends State<IpStreamPage> {
  String? ip;
  int? wsPort;
  Uint8List? _currentFrame;
  bool _isConnected = false;

  @override
  void initState() {
    super.initState();
    _fetchCameraInfo(); // Fetch IP and WebSocket port during initial load
  }

  Future<void> _requestStoragePermission() async {
    if (!kIsWeb && Platform.isAndroid) {
      await Permission.storage.request();
      await Permission.manageExternalStorage.request();
    }
  }

  void _showFullscreenVideo() {
    if (ip == null || wsPort == null) return;

    String wsUrl = 'ws://$ip:$wsPort/ws';

    showDialog(
      context: context,
      barrierColor: Colors.black,
      builder: (BuildContext context) {
        return Dialog.fullscreen(
          child: Scaffold(
            backgroundColor: Colors.black,
            body: SafeArea(
              child: GestureDetector(
                onTap: () => Navigator.of(context).pop(),
                child: Stack(
                  children: [
                    // Fullscreen video
                    Center(
                      child: WebSocketStreamWidget(
                        wsUrl: wsUrl,
                        fit: BoxFit.contain,
                        error: (context, error, stack) {
                          return Container(
                            padding: const EdgeInsets.all(32),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    color: Colors.red.shade50,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Icon(
                                    Icons.error_outline,
                                    color: Colors.red.shade600,
                                    size: 48,
                                  ),
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  'Connection Error',
                                  style: GoogleFonts.poppins(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.white,
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                    // Close button
                    Positioned(
                      top: 16,
                      right: 16,
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.6),
                          shape: BoxShape.circle,
                        ),
                        child: IconButton(
                          icon: const Icon(
                            Icons.close,
                            color: Colors.white,
                            size: 30,
                          ),
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                      ),
                    ),
                    // Tap anywhere to close hint
                    Positioned(
                      bottom: 32,
                      left: 0,
                      right: 0,
                      child: Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.6),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            'Tap anywhere to close',
                            style: GoogleFonts.inter(
                              color: Colors.white.withOpacity(0.8),
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _captureFrame() async {
    if (_currentFrame == null) {
      _scaffoldMessengerKey.currentState?.showSnackBar(
        const SnackBar(content: Text('No frame available to capture')),
      );
      return;
    }

    try {
      // Request permissions
      await _requestStoragePermission();

      Directory? directory;
      if (Platform.isAndroid) {
        // Use the public Downloads directory on Android
        directory = Directory('/storage/emulated/0/Download');
        if (!await directory.exists()) {
          // Fallback to external storage if Downloads doesn't exist
          directory = await getExternalStorageDirectory();
        }
      } else if (Platform.isIOS) {
        directory = await getApplicationDocumentsDirectory();
      } else {
        directory = await getDownloadsDirectory();
      }

      if (directory != null) {
        final now = DateTime.now();
        final dateFormat = DateFormat('yyyy-MM-dd');
        final timeFormat = DateFormat('HH-mm-ss');
        final fileName =
            '${dateFormat.format(now)}-${timeFormat.format(now)}.jpg';
        final file = File('${directory.path}/$fileName');

        await file.writeAsBytes(_currentFrame!);

        _scaffoldMessengerKey.currentState?.showSnackBar(
          SnackBar(
            content: Text('Image Saved'),
            backgroundColor: SmartHausColors.secondary,
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      _scaffoldMessengerKey.currentState?.showSnackBar(
        SnackBar(content: Text('Failed to capture frame: $e')),
      );
    }
  }

  Future<void> _logout() async {
    try {
      await FirebaseAuth.instance.signOut();
      _scaffoldMessengerKey.currentState?.showSnackBar(
        const SnackBar(
          content: Text('Successfully logged out'),
          backgroundColor: SmartHausColors.secondary,
        ),
      );
    } catch (e) {
      _scaffoldMessengerKey.currentState?.showSnackBar(
        SnackBar(content: Text('Error logging out: $e')),
      );
    }
  }

  Future<void> _fetchCameraInfo() async {
    setState(() {
      ip = null;
      wsPort = null;
    }); // Clear current values to show loading indicator

    try {
      // Fetch IP address
      final ipRef = FirebaseDatabase.instance.ref(
        'devices/esp32cam_001/ip_address',
      );
      final ipSnap = await ipRef.get();

      // Fetch WebSocket port
      final wsRef = FirebaseDatabase.instance.ref(
        'devices/esp32cam_001/ws_port',
      );
      final wsSnap = await wsRef.get();

      setState(() {
        ip = ipSnap.value as String?;
        wsPort = (wsSnap.value as int?) ?? 81; // Default to 81 if not found
      });
    } catch (e) {
      debugPrint('Error fetching camera info: $e');
      setState(() {
        ip = null;
        wsPort = null;
      }); // Reset on error
    }
  }

  @override
  Widget build(BuildContext context) {
    if (ip == null) {
      return Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: Icon(Icons.arrow_back_ios, color: SmartHausColors.accent),
            onPressed: () => Navigator.pop(context),
          ),
          title: Text(
            'ESP32-CAM Stream',
            style: GoogleFonts.poppins(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: SmartHausColors.accent,
            ),
          ),
          backgroundColor: SmartHausColors.white,
          elevation: 0,
        ),
        backgroundColor: SmartHausColors.background,
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final wsUrl = 'ws://$ip:$wsPort/ws';

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios, color: SmartHausColors.accent),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'ESP32-CAM Stream',
          style: GoogleFonts.poppins(
            fontSize: 20,
            fontWeight: FontWeight.w600,
            color: SmartHausColors.accent,
          ),
        ),
        backgroundColor: SmartHausColors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: SmartHausColors.secondary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(Icons.refresh, color: SmartHausColors.teal, size: 20),
            ),
            onPressed: _fetchCameraInfo,
            tooltip: 'Refresh Camera Info',
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(Icons.logout, color: Colors.red.shade600, size: 20),
            ),
            onPressed: _logout,
            tooltip: 'Logout',
          ),
          const SizedBox(width: 16),
        ],
      ),
      backgroundColor: SmartHausColors.background,
      body: Column(
        children: [
          // Simple Camera Status Card
          Container(
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: SmartHausColors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: SmartHausColors.accent.withOpacity(0.08),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: _isConnected
                        ? SmartHausColors.secondary.withOpacity(0.1)
                        : Colors.red.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    _isConnected ? Icons.videocam : Icons.videocam_off,
                    color: _isConnected
                        ? SmartHausColors.teal
                        : Colors.red.shade600,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  'Camera Status: ',
                  style: GoogleFonts.poppins(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: SmartHausColors.darkGreen,
                  ),
                ),
                Text(
                  _isConnected ? 'Connected' : 'Disconnected',
                  style: GoogleFonts.inter(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: _isConnected
                        ? SmartHausColors.teal
                        : Colors.red.shade600,
                  ),
                ),
              ],
            ),
          ),

          // Camera Stream Container
          Expanded(
            child: Container(
              margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              decoration: BoxDecoration(
                color: SmartHausColors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: SmartHausColors.accent.withOpacity(0.08),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: GestureDetector(
                  onTap: () => _showFullscreenVideo(),
                  child: WebSocketStreamWidget(
                    wsUrl: wsUrl,
                    onFrameUpdate: (frame) {
                      _currentFrame = frame;
                    },
                    onConnectionStatusChanged: (isConnected) {
                      setState(() {
                        _isConnected = isConnected;
                      });
                    },
                    error: (context, error, stack) {
                      debugPrint('WebSocket stream error: $error');
                      return Container(
                        padding: const EdgeInsets.all(32),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: Colors.red.shade50,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Icon(
                                Icons.error_outline,
                                color: Colors.red.shade600,
                                size: 48,
                              ),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'Connection Error',
                              style: GoogleFonts.poppins(
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                                color: SmartHausColors.darkGreen,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ),

          // Camera Capture Button
          Container(
            margin: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            child: Container(
              width: double.infinity,
              height: 56,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                gradient: const LinearGradient(
                  colors: [SmartHausColors.primary, SmartHausColors.secondary],
                ),
                boxShadow: [
                  BoxShadow(
                    color: SmartHausColors.primary.withOpacity(0.3),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: ElevatedButton.icon(
                onPressed: _captureFrame,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.transparent,
                  shadowColor: Colors.transparent,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                icon: Icon(
                  Icons.camera_alt,
                  color: SmartHausColors.white,
                  size: 24,
                ),
                label: Text(
                  'Capture Frame',
                  style: GoogleFonts.poppins(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: SmartHausColors.white,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
