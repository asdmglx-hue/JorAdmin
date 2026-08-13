import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'utils/theme.dart';
import 'services/fcm_service.dart';
import 'services/supabase_service.dart';
import 'screens/admin_login_screen.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  Standalone Admin App entry point.
//  Build/run with: flutter run -t lib/admin/main_admin.dart
//
//  This mirrors the exact initialization sequence from lib/main.dart
//  (Firebase, Supabase, notifications, FCM) so AdminService /
//  SupabaseService behave identically to how they did inside the
//  combined app. Nothing about admin logic, screens, or behavior
//  was changed — only the surrounding app shell.
// ─────────────────────────────────────────────────────────────────────────────

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Firebase is only needed for FCM (mobile push notifications).
  // On web, skip it entirely — no push needed for admin web panel.
  if (!kIsWeb) {
    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
    } catch (e) {
      debugPrint('Firebase init error: $e');
    }
  }

  try {
    await Supabase.initialize(
      url: 'https://olzfarkfxhwcwabgribo.supabase.co',
      anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im9semZhcmtmeGh3Y3dhYmdyaWJvIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODAyMDI5NTEsImV4cCI6MjA5NTc3ODk1MX0.Vqo_21U6zW7Igc7th_LPt5AEv238G4lBCYSVW4l8WxI',
    ).timeout(
      const Duration(seconds: 10),
      onTimeout: () {
        debugPrint('Supabase init timed out — running in offline mode');
        return Supabase.instance;
      },
    );
  } catch (e) {
    debugPrint('Supabase init error: $e');
  }

  // FCM device registration only (permission + token sync). Push-sending
  // logic and the in-app notification system have been removed and are
  // pending a fresh implementation.
  if (!kIsWeb) await FCMService.instance.init();

  // Fetch DB-driven lists in background — castes, cities, occupations
  // use SharedPreferences caching so they're available immediately on
  // next launch even without network.
  SupabaseService.instance.fetchCastes();
  SupabaseService.instance.fetchCities();
  SupabaseService.instance.fetchOccupations();

  if (!kIsWeb) SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
  ));

  runApp(const JorAdminApp());
}

class JorAdminApp extends StatelessWidget {
  const JorAdminApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Jor Admin',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      home: const AdminLoginScreen(),
    );
  }
}
