import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:timezone/timezone.dart' as tz;
import 'dart:math';

/// Custom Reminders Scheduler - Manages multiple custom reminder notifications
/// Similar to daily notifications but supports multiple messages with individual controls
class CustomRemindersScheduler {
  static const String _workTagPrefix = 'custom_reminder_';
  static const String _prefsEnabled = 'custom_reminders_enabled';
  static const String _prefsMessages = 'custom_reminders_messages';
  static const String _prefsTimeWindow = 'custom_reminders_time_window';
  static const String _prefsMaxPerDay = 'custom_reminders_max_per_day';

  final FlutterLocalNotificationsPlugin _notifications = FlutterLocalNotificationsPlugin();

  // Default settings
  static const int defaultMaxPerDay = 2;
  static const int defaultStartHour = 8;
  static const int defaultEndHour = 20; // 8 PM

  Future<void> initialize() async {
    // Initialize notifications
    const initializationSettingsAndroid = AndroidInitializationSettings('app_icon');
    const initializationSettingsIOS = DarwinInitializationSettings();
    const initializationSettings = InitializationSettings(
      android: initializationSettingsAndroid,
      iOS: initializationSettingsIOS,
    );

    await _notifications.initialize(
      initializationSettings,
      onDidReceiveNotificationResponse: _onNotificationTapped,
    );

    // Create notification channel (no need for platformChannel variable since we're not showing a notification)
    const AndroidNotificationDetails(
      'veer_custom_reminders',
      'Veer Custom Reminders',
      channelDescription: 'Custom motivational reminders',
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
      sound: RawResourceAndroidNotificationSound('notification'),
    );

    // Removed the problematic notification.show() call that was causing app freeze
    // The notification channel creation is sufficient for initialization

    // Initialize WorkManager
    await Workmanager().initialize(
      _handleCustomReminderCallback,
      isInDebugMode: false,
    );
  }

  Future<void> _onNotificationTapped(NotificationResponse response) async {
    // Handle notification tap - could navigate to specific screen
    debugPrint('Custom reminder notification tapped: ${response.payload}');
  }

  Future<void> _handleCustomReminderCallback() async {
    try {
      final settings = await _getSettings();

      if (!settings.enabled || settings.messages.isEmpty) {
        return;
      }

      // Get Android SDK version for permission handling
      final deviceInfo = DeviceInfoPlugin();
      final androidInfo = await deviceInfo.androidInfo;
      final sdkVersion = androidInfo.version.sdkInt;

      // Check permission on Android 13+
      if (sdkVersion >= 33) {
        final status = await Permission.notification.status;
        if (!status.isGranted) {
          debugPrint('Notification permission not granted, skipping custom reminders');
          return;
        }
      }

      // Select random messages up to max per day
      final availableMessages = List<String>.from(settings.messages);
      final maxReminders = min(settings.maxPerDay, availableMessages.length);

      if (availableMessages.isEmpty) return;

      // Shuffle and take up to max per day
      availableMessages.shuffle();
      final selectedMessages = availableMessages.take(maxReminders).toList();

      // Send notifications with slight delays to avoid overwhelming
      for (int i = 0; i < selectedMessages.length; i++) {
        final message = selectedMessages[i];
        final notificationId = 1000 + i; // Use IDs 1000-1004 for custom reminders

        const androidDetails = AndroidNotificationDetails(
          'veer_custom_reminders',
          'Veer Custom Reminders',
          channelDescription: 'Custom motivational reminders',
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
          sound: RawResourceAndroidNotificationSound('notification'),
        );

        const details = NotificationDetails(android: androidDetails);

        await Future.delayed(Duration(seconds: i * 2)); // Stagger notifications

        await _notifications.show(
          notificationId,
          'Custom Reminder',
          message,
          details,
          payload: 'custom_reminder_$notificationId',
        );
      }

      // Schedule next batch for tomorrow
      await _scheduleNextBatch();

    } catch (e) {
      debugPrint('Error handling custom reminder: $e');
    }
  }

  Future<void> _scheduleNextBatch() async {
    try {
      final settings = await _getSettings();
      if (!settings.enabled || settings.messages.isEmpty) {
        return;
      }

      // Calculate next trigger time (tomorrow within time window)
      final now = tz.TZDateTime.now(tz.local);
      var nextTrigger = tz.TZDateTime(
        tz.local,
        now.year,
        now.month,
        now.day + 1, // Tomorrow
        settings.startHour,
        0,
      );

      // If tomorrow's start time has passed, schedule for today
      if (nextTrigger.isBefore(now)) {
        nextTrigger = tz.TZDateTime(
          tz.local,
          now.year,
          now.month,
          now.day,
          settings.startHour,
          0,
        );

        // If today's start time has passed, add a day
        if (nextTrigger.isBefore(now)) {
          nextTrigger = nextTrigger.add(const Duration(days: 1));
        }
      }

      // Add random minutes within the time window
      final random = Random();
      final timeWindowMinutes = (settings.endHour - settings.startHour) * 60;
      final randomMinutes = random.nextInt(timeWindowMinutes);

      nextTrigger = nextTrigger.add(Duration(minutes: randomMinutes));

      // Use unique work name to avoid duplicates
      final workName = '${_workTagPrefix}batch_${DateTime.now().millisecondsSinceEpoch}';

      await Workmanager().registerOneOffTask(
        workName,
        'customReminderTask',
        initialDelay: nextTrigger.difference(now),
        existingWorkPolicy: ExistingWorkPolicy.replace,
      );

    } catch (e) {
      debugPrint('Error scheduling custom reminder batch: $e');
    }
  }

  Future<void> enableCustomReminders(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsEnabled, enabled);

    if (enabled) {
      await _scheduleNextBatch();
    } else {
      await _cancelAllReminders();
    }
  }

  Future<void> setMessages(List<String> messages) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_prefsMessages, messages);

    // Update scheduling
    final settings = await _getSettings();
    if (settings.enabled) {
      if (messages.isEmpty) {
        await _cancelAllReminders();
      } else {
        await _scheduleNextBatch();
      }
    }
  }

  Future<void> setTimeWindow(int startHour, int endHour) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_prefsTimeWindow, startHour * 100 + endHour);

    // Reschedule with new time window
    final settings = await _getSettings();
    if (settings.enabled) {
      await _scheduleNextBatch();
    }
  }

  Future<void> setMaxPerDay(int maxPerDay) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_prefsMaxPerDay, maxPerDay);

    // Reschedule with new limit
    final settings = await _getSettings();
    if (settings.enabled) {
      await _scheduleNextBatch();
    }
  }

  Future<CustomRemindersSettings> getSettings() async {
    return await _getSettings();
  }

  Future<CustomRemindersSettings> _getSettings() async {
    final prefs = await SharedPreferences.getInstance();

    final enabled = prefs.getBool(_prefsEnabled) ?? false;
    final messages = prefs.getStringList(_prefsMessages) ?? [];
    final timeWindow = prefs.getInt(_prefsTimeWindow) ?? (defaultStartHour * 100 + defaultEndHour);
    final maxPerDay = prefs.getInt(_prefsMaxPerDay) ?? defaultMaxPerDay;

    final startHour = timeWindow ~/ 100;
    final endHour = timeWindow % 100;

    return CustomRemindersSettings(
      enabled: enabled,
      messages: messages,
      startHour: startHour,
      endHour: endHour,
      maxPerDay: maxPerDay,
    );
  }

  Future<void> _cancelAllReminders() async {
    // Cancel all work with custom reminder tag
    await Workmanager().cancelByTag(_workTagPrefix);

    // Cancel all notifications
    await _notifications.cancelAll();
  }

  Future<void> cancelAll() async {
    await _cancelAllReminders();
  }
}

class CustomRemindersSettings {
  final bool enabled;
  final List<String> messages;
  final int startHour;
  final int endHour;
  final int maxPerDay;

  CustomRemindersSettings({
    required this.enabled,
    required this.messages,
    required this.startHour,
    required this.endHour,
    required this.maxPerDay,
  });

  String get formattedTimeWindow {
    final startTime = '${startHour.toString().padLeft(2, '0')}:00';
    final endTime = '${endHour.toString().padLeft(2, '0')}:00';
    return '$startTime - $endTime';
  }

  String get scheduleSummary {
    if (!enabled) return 'Disabled';
    if (messages.isEmpty) return 'No messages configured';

    final messageCount = messages.length;
    final maxCount = min(maxPerDay, messageCount);

    return '$maxCount reminder${maxCount != 1 ? 's' : ''} per day from ${messages.length} message${messages.length != 1 ? 's' : ''}';
  }
}
