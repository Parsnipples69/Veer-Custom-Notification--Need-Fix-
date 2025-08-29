import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:url_launcher/url_launcher.dart';
import 'package:youtube_player_flutter/youtube_player_flutter.dart';
import 'package:provider/provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import 'services/daily_notification_scheduler.dart';
import 'services/custom_reminders_scheduler.dart';
import 'screens/notification_soft_ask_screen.dart';
import 'screens/custom_reminders_soft_ask_screen.dart';


void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  print('=== APP STARTUP ===');

  // Initialize services with timeout and error handling to prevent app freeze
  try {
    // Initialize notification services with timeout
    await Future.wait([
      NotificationService().init().timeout(const Duration(seconds: 10)),
      DailyNotificationScheduler().initialize().timeout(const Duration(seconds: 10)),
      CustomRemindersScheduler().initialize().timeout(const Duration(seconds: 10)),
    ]).catchError((error) {
      print('Warning: Some notification services failed to initialize: $error');
      // Continue app startup even if services fail
      return <void>[]; // Return empty list to satisfy Future.wait type
    });
  } catch (e) {
    print('Error during service initialization: $e');
    // Continue app startup
  }

  // Request notification permission on app start (with timeout)
  try {
    final hasPermission = await NotificationService().requestNotificationPermission()
        .timeout(const Duration(seconds: 5));
    if (hasPermission) {
      print('Notification permission granted');
    }
  } catch (e) {
    print('Warning: Could not request notification permission: $e');
  }

  // Handle notification taps when app is opened from notification (with timeout)
  try {
    final NotificationAppLaunchDetails? notificationAppLaunchDetails =
        await NotificationService().plugin.getNotificationAppLaunchDetails()
            .timeout(const Duration(seconds: 5));

    if (notificationAppLaunchDetails?.didNotificationLaunchApp ?? false) {
      print('App opened from notification tap');
    }
  } catch (e) {
    print('Warning: Could not get notification launch details: $e');
  }

  // Initialize premium service with timeout
  try {
    await PremiumService.initialize().timeout(const Duration(seconds: 15));
  } catch (e) {
    print('Warning: Premium service initialization failed: $e');
    // Continue app startup - premium features will be disabled
  }

  runApp(
    ChangeNotifierProvider(
      create: (_) => ThemeNotifier(),
      child: VeerApp(),
    ),
  );
}

// --- NOTIFICATION SERVICE ---
class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin plugin = FlutterLocalNotificationsPlugin();
  final DeviceInfoPlugin deviceInfo = DeviceInfoPlugin();

    Future<void> init() async {
    try {
      tz.initializeTimeZones();

      // Set local timezone
      try {
        tz.setLocalLocation(tz.getLocation('America/New_York'));
      } catch (e) {
        tz.setLocalLocation(tz.getLocation('UTC'));
      }

      const AndroidInitializationSettings initializationSettingsAndroid =
          AndroidInitializationSettings('@mipmap/ic_launcher');
      final InitializationSettings initializationSettings =
          InitializationSettings(android: initializationSettingsAndroid);

      await plugin.initialize(initializationSettings);
      await _createNotificationChannels();

    } catch (e) {
      // Silent fail in production
    }
  }

  Future<void> _createNotificationChannels() async {
    try {
      final androidInfo = await deviceInfo.androidInfo;
      final sdkVersion = androidInfo.version.sdkInt;

      if (sdkVersion >= 26) {
        const AndroidNotificationChannel customChannel = AndroidNotificationChannel(
          'veer_custom_channel_id',
          'Veer Custom',
          description: 'Custom reminders from Veer',
          importance: Importance.high,
          playSound: true,
          enableVibration: true,
          enableLights: true,
          showBadge: true,
        );

        final androidImplementation = plugin
            .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin>();

        if (androidImplementation != null) {
          await androidImplementation.createNotificationChannel(customChannel);
        }
      }
    } catch (e) {
      // Silent fail in production
    }
  }

  Future<bool> requestNotificationPermission() async {
    try {
      final androidInfo = await deviceInfo.androidInfo;
      final sdkVersion = androidInfo.version.sdkInt;

      if (sdkVersion >= 33) {
        final status = await Permission.notification.request();
        return status.isGranted;
      } else if (sdkVersion >= 26) {
        final status = await Permission.notification.status;
        return status.isGranted;
      } else {
        return true;
      }
    } catch (e) {
      return false;
    }
  }

  Future<bool> checkNotificationPermission() async {
    try {
      final status = await Permission.notification.status;
      return status.isGranted;
    } catch (e) {
      return false;
    }
  }



  Future<void> checkBatteryOptimization() async {
    try {
      final androidInfo = await deviceInfo.androidInfo;
      final sdkVersion = androidInfo.version.sdkInt;

      if (sdkVersion >= 23) {
        final isIgnoringBatteryOptimizations = await Permission.ignoreBatteryOptimizations.status;

        if (!isIgnoringBatteryOptimizations.isGranted) {
          // Battery optimization not disabled - notifications may be delayed
        }
      }
    } catch (e) {
      // Silent fail in production
    }
  }



  Future<void> scheduleCustomNotification(int id, String body) async {
    try {
      final hasPermission = await checkNotificationPermission();
      if (!hasPermission) {
        return;
      }

      final random = Random();
      final randomHour = random.nextInt(12) + 8; // 8am - 8pm
      final randomMinute = random.nextInt(60);

      final now = tz.TZDateTime.now(tz.local);
      var scheduled = tz.TZDateTime(tz.local, now.year, now.month, now.day, randomHour, randomMinute);
      if (scheduled.isBefore(now)) {
        scheduled = scheduled.add(Duration(days: 1));
      }

      await scheduleNotificationPlayStoreCompliant(id, body, scheduled);

    } catch (e) {
      // Silent fail in production
    }
  }





  Future<void> scheduleNotificationPlayStoreCompliant(int id, String body, tz.TZDateTime scheduled) async {
    try {
      await plugin.zonedSchedule(
        id,
        'Veer Reminder',
        body,
        scheduled,
        _getNotificationDetails(),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        matchDateTimeComponents: DateTimeComponents.time,
      );
    } catch (e) {
      // Try periodic scheduling as fallback
      try {
        await plugin.periodicallyShow(
          id,
          'Veer Reminder',
          body,
          RepeatInterval.daily,
          _getNotificationDetails(),
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        );
      } catch (periodicError) {
        // Silent fail in production
      }
    }
  }

  NotificationDetails _getNotificationDetails() {
    return NotificationDetails(
      android: AndroidNotificationDetails(
        'veer_custom_channel_id',
        'Veer Custom',
        channelDescription: 'Custom reminders from Veer',
        importance: Importance.high,
        priority: Priority.high,
        playSound: true,
        enableVibration: true,
        icon: '@mipmap/ic_launcher',
        category: AndroidNotificationCategory.reminder,
        // Play Store compliant settings
        ongoing: false,
        autoCancel: true,
        channelShowBadge: true,
      ),
    );
  }
/////////////////////////////////////////////////////////////////////////////////////////////////////

    // Custom Reminders Button (Enhanced)
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => CustomRemindersSoftAskScreen()),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: accentBlue,
                foregroundColor: Colors.white,
                minimumSize: Size(0, 60),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                  side: BorderSide(color: primaryBlue, width: 2),
                ),
                elevation: 8,
                shadowColor: accentBlue.withOpacity(0.4),
                textStyle: TextStyle(
                  fontFamily: 'Inter',
                  fontWeight: FontWeight.w800,
                  fontSize: 18,
                  letterSpacing: 0.5,
                ),
              ),
              icon: Icon(Icons.notifications_active_rounded, color: Colors.white, size: 24),
              label: Text("Custom Reminders"),
            ),
          ),
        SizedBox(height: 24),
        Text(
          "Press this button in case of urges",
          style: TextStyle(
            fontFamily: 'Inter',
              color: isDark ? Colors.white.withOpacity(0.6) : primaryBlue.withOpacity(0.6),
            fontSize: 13,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.1,
          ),
            textAlign: TextAlign.center,
        ),
        SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => EmergencyHelpPage()),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              minimumSize: Size(0, 60),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              elevation: 8,
              shadowColor: Colors.red.withOpacity(0.4),
              textStyle: TextStyle(
                fontFamily: 'Inter',
                fontWeight: FontWeight.w900,
                fontSize: 20,
                letterSpacing: 0.5,
              ),
            ),
            icon: Icon(Icons.emergency, color: Colors.white, size: 24),
            label: Text("Emergency"),
          ),
        ),
      ],
      ),
    );
  }
}
///////////////////////////////////////////////////////////////////////////////////////////////////
// --- SETTINGS PAGE WITH LEGAL ---
class SettingsPage extends StatelessWidget {
  void _showAboutDialog(BuildContext context) {
    showAboutDialog(
      context: context,
      applicationName: 'Veer',
      applicationVersion: '1.0.0',
      applicationLegalese: '© 2025 Veer Team',
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 16),
          child: Text(
            'Veer helps you build a new identity and overcome addiction, with motivational tools and daily support.\n\nAll content © their respective authors.',
          ),
        ),
      ],
    );
  }

  Future<void> _deleteAllData(BuildContext context) async {
    final confirm = await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text("Delete All Data"),
        content: Text("Are you sure you want to permanently delete all local data? This cannot be undone."),
        actions: [
          TextButton(
            child: Text("Cancel"),
            onPressed: () => Navigator.pop(ctx, false),
          ),
          TextButton(
            child: Text("Delete", style: TextStyle(color: Colors.red)),
            onPressed: () => Navigator.pop(ctx, true),
          ),
        ],
      ),
    );
    if (confirm == true) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("All local data deleted.")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final darkBlue = Color(0xFF003366);
    final themeNotifier = Provider.of<ThemeNotifier>(context);

    return Scaffold(
      appBar: AppBar(
        title: Text("Settings"),
        backgroundColor: darkBlue,
      ),
      body: ListView(
        padding: EdgeInsets.all(22),
        children: [
          ListTile(
            title: Row(
              children: [
                Text("Dark Mode", style: TextStyle(fontWeight: FontWeight.bold)),
                SizedBox(width: 8),
                Icon(Icons.lock, size: 16, color: Colors.orange.shade600),
              ],
            ),
            trailing: Switch(
              value: themeNotifier.themeMode == ThemeMode.dark,
              onChanged: (value) async {
                final isPremium = await PremiumService.isPremiumUser();
                if (!isPremium) {
                  PremiumService.showPremiumRequiredDialog(context, 'Dark Mode');
                  return;
                }
                themeNotifier.setDarkMode(value);
              },
            ),
            subtitle: Text("Switch between light and dark themes (Premium)"),
          ),
          Divider(height: 36),
          ListTile(
            title: Text("Daily Notifications", style: TextStyle(fontWeight: FontWeight.bold)),
            trailing: Icon(Icons.notifications, color: darkBlue),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => NotificationSoftAskScreen()),
              );
            },
            subtitle: Text("Configure daily reminder notifications"),
          ),
          Divider(height: 36),
          ListTile(
            title: Text("About Us", style: TextStyle(fontWeight: FontWeight.bold)),
            trailing: Icon(Icons.info_outline, color: darkBlue),
            onTap: () => _showAboutDialog(context),
          ),
          Divider(height: 36),
          ListTile(
            title: Text("Delete All Local Data", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red)),
            trailing: Icon(Icons.delete_forever, color: Colors.red),
            onTap: () => _deleteAllData(context),
          ),
          Divider(height: 36),
          ListTile(
            title: Text("Legal", style: TextStyle(fontWeight: FontWeight.bold)),
            trailing: Icon(Icons.gavel, color: darkBlue),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => LegalPage()),
              );
            },
          ),
        ],
      ),
    );
  }
}
  
