import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'dart:math';
import '../services/custom_reminders_scheduler.dart';
import 'custom_reminders_soft_ask_screen.dart';
import '../main.dart';

class CustomRemindersSettingsScreen extends StatefulWidget {
  @override
  _CustomRemindersSettingsScreenState createState() => _CustomRemindersSettingsScreenState();
}

class _CustomRemindersSettingsScreenState extends State<CustomRemindersSettingsScreen> {
  final CustomRemindersScheduler _scheduler = CustomRemindersScheduler();
  CustomRemindersSettings _settings = CustomRemindersSettings(
    enabled: false,
    messages: [],
    startHour: 8,
    endHour: 20,
    maxPerDay: 2,
  );

  bool _isLoading = true;
  String _permissionStatus = 'Checking...';
  bool _isPremium = false;
  final TextEditingController _messageController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _checkPremiumStatus().then((_) {
      _loadSettings();
    });
    _checkPermissionStatus();
  }

  Future<void> _checkPremiumStatus() async {
    final isPremium = await PremiumService.isPremiumUser();
    setState(() {
      _isPremium = isPremium;
    });
  }

  Future<void> _loadSettings() async {
    final loadedSettings = await _scheduler.getSettings();

    // Enforce premium limits for non-premium users
    CustomRemindersSettings settings;
    if (!_isPremium && loadedSettings.maxPerDay > 2) {
      // User is not premium but has premium-level settings, enforce the limit
      await _scheduler.setMaxPerDay(2);
      // Create new settings object with enforced limit
      settings = CustomRemindersSettings(
        enabled: loadedSettings.enabled,
        messages: loadedSettings.messages,
        startHour: loadedSettings.startHour,
        endHour: loadedSettings.endHour,
        maxPerDay: 2,
      );
    } else {
      settings = loadedSettings;
    }

    setState(() {
      _settings = settings;
      _isLoading = false;
    });
  }

  Future<void> _checkPermissionStatus() async {
    try {
      final deviceInfo = DeviceInfoPlugin();
      final androidInfo = await deviceInfo.androidInfo;
      final sdkVersion = androidInfo.version.sdkInt;

      // Pre-Android 13 doesn't require runtime permission
      if (sdkVersion < 33) {
        setState(() {
          _permissionStatus = 'Not Required (Pre-Android 13)';
        });
        return;
      }

      final status = await Permission.notification.status;
      String statusText;
      if (status.isGranted) {
        statusText = 'Granted';
      } else if (status.isPermanentlyDenied) {
        statusText = 'Permanently Denied';
      } else if (status.isDenied) {
        statusText = 'Denied';
      } else {
        statusText = 'Unknown';
      }

      setState(() {
        _permissionStatus = statusText;
      });
    } catch (e) {
      setState(() {
        _permissionStatus = 'Error checking';
      });
    }
  }

  Future<void> _requestPermission() async {
    final status = await Permission.notification.request();

    String statusText;
    if (status.isGranted) {
      statusText = 'Granted';
    } else if (status.isPermanentlyDenied) {
      statusText = 'Permanently Denied';
    } else {
      statusText = 'Denied';
    }

    setState(() {
      _permissionStatus = statusText;
    });

    if (status.isGranted) {
      // Re-enable notifications if they were disabled due to permission
      if (_settings.enabled) {
        await _scheduler.enableCustomReminders(true);
      }
    } else if (status.isPermanentlyDenied) {
      // Show system settings guidance
      _showSystemSettingsDialog();
    } else {
      // Show explanation dialog for regular denial
      _showPermissionExplanation();
    }
  }

  void _showPermissionExplanation() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Custom Reminders Need Permission'),
        content: Text(
          'Custom reminders require notification permission to send you personalized motivational messages throughout the day.'
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Maybe Later'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _requestPermission();
            },
            child: Text('Enable Permission'),
          ),
        ],
      ),
    );
  }

  void _showSystemSettingsDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Permission Needed in Settings'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'You previously denied notification permission with "Don\'t ask again". To enable custom reminders, you\'ll need to allow notifications in your device settings.',
            ),
            SizedBox(height: 12),
            Text(
              'This will open your device\'s app settings where you can enable notifications for Veer.',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey.shade600,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              openAppSettings();
            },
            child: Text('Open App Settings'),
          ),
        ],
      ),
    );
  }

  Future<void> _showTimePicker({
    required bool isStartTime,
    required int currentHour,
  }) async {
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: currentHour, minute: 0),
    );

    if (time != null) {
      if (isStartTime) {
        await _scheduler.setTimeWindow(
          time.hour,
          _settings.endHour,
        );
      } else {
        await _scheduler.setTimeWindow(
          _settings.startHour,
          time.hour,
        );
      }
      await _loadSettings();
    }
  }

  Future<void> _showMessageDialog({String? existingMessage, int? index}) async {
    final isEditing = existingMessage != null;

    // Check premium limit for adding new reminders (not editing)
    if (!isEditing && !_isPremium && _settings.messages.length >= 2) {
      _showPremiumRequiredDialog();
      return;
    }

    _messageController.text = existingMessage ?? '';

    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(isEditing ? 'Edit Reminder' : 'Add New Reminder'),
        content: TextField(
          controller: _messageController,
          maxLines: 3,
          maxLength: 200,
          decoration: InputDecoration(
            hintText: 'Enter your motivational reminder message',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, _messageController.text.trim()),
            child: Text(isEditing ? 'Update' : 'Add'),
          ),
        ],
      ),
    );

    if (result != null && result.isNotEmpty) {
      final updatedMessages = List<String>.from(_settings.messages);

      if (isEditing && index != null) {
        updatedMessages[index] = result;
      } else {
        updatedMessages.add(result);
      }

      await _scheduler.setMessages(updatedMessages);
      await _loadSettings();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(isEditing ? 'Reminder updated successfully!' : 'Reminder added successfully!'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  Future<void> _deleteMessage(int index) async {
    final updatedMessages = List<String>.from(_settings.messages);
    updatedMessages.removeAt(index);

    await _scheduler.setMessages(updatedMessages);
    await _loadSettings();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Reminder deleted successfully!'),
        backgroundColor: Colors.green,
      ),
    );
  }

  Future<void> _showMaxPerDayDialog() async {
    int selectedMax = _settings.maxPerDay;
    bool attemptedPremium = false;

    final result = await showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Max Reminders Per Day'),
        content: StatefulBuilder(
          builder: (context, setState) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Choose how many reminders you want to receive per day:'),
              SizedBox(height: 16),
              ...List.generate(
                _isPremium ? min(_settings.messages.length, 5) : min(_settings.messages.length, 2),
                (index) {
                  final value = index + 1;
                  final isPremiumRequired = value > 2;

                  return RadioListTile<int>(
                    title: Row(
                      children: [
                        Text('${value} reminder${value != 1 ? 's' : ''} per day'),
                        if (isPremiumRequired) ...[
                          SizedBox(width: 8),
                          Container(
                            padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.orange.shade100,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.orange.shade300),
                            ),
                            child: Text(
                              'PREMIUM',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: Colors.orange.shade700,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    value: value,
                    groupValue: selectedMax,
                    onChanged: (value) {
                      if (value != null && value > 2 && !_isPremium) {
                        // User attempted to select premium feature
                        attemptedPremium = true;
                        // Show premium required dialog instead
                        Navigator.of(context).pop(); // Close current dialog
                        // Use Future.delayed to ensure dialog is closed before showing new one
                        Future.delayed(Duration(milliseconds: 100), () {
                          _showPremiumRequiredDialog();
                        });
                      } else {
                        setState(() => selectedMax = value!);
                      }
                    },
                  );
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, (selectedMax > 2 && !_isPremium) || attemptedPremium ? null : selectedMax),
            child: Text('Save'),
          ),
        ],
      ),
    );

    if (result != null) {
      await _scheduler.setMaxPerDay(result);
      await _loadSettings();
    }
  }

  void _showPremiumRequiredDialog() {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Colors.orange.shade400, Colors.orange.shade600],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.star_rounded,
                  size: 40,
                  color: Colors.white,
                ),
              ),
              SizedBox(height: 20),
              Text(
                'Premium Required',
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  color: Colors.grey[800],
                ),
                textAlign: TextAlign.center,
              ),
              SizedBox(height: 12),
              Text(
                'More than 2 reminders per day requires a Premium subscription.',
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey[700],
                ),
                textAlign: TextAlign.center,
              ),
              SizedBox(height: 8),
              Container(
                padding: EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.orange.shade200),
                ),
                child: Text(
                  '${PremiumService.getLocalizedPrice()}/month',
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                    color: Colors.orange.shade700,
                  ),
                ),
              ),
              SizedBox(height: 8),
              Container(
                padding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.orange.shade100,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.orange.shade300, width: 1),
                ),
                child: Text(
                  'Monthly Subscription',
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.orange.shade700,
                  ),
                ),
              ),
              SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: Text(
                        'Maybe Later',
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 16,
                          color: Colors.grey[600],
                        ),
                      ),
                    ),
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.of(context).pop();
                        // Show placeholder for purchase flow
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Premium purchase flow would open here'),
                            backgroundColor: Colors.orange,
                          ),
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.orange.shade500,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(
                        'Get Premium',
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Color _getPermissionStatusColor() {
    if (_permissionStatus == 'Granted') {
      return Colors.green.shade700;
    } else if (_permissionStatus == 'Not Required (Pre-Android 13)') {
      return Colors.blue.shade700;
    } else if (_permissionStatus == 'Permanently Denied') {
      return Colors.orange.shade700;
    } else {
      return Colors.red.shade700;
    }
  }

  String _getPermissionStatusDescription() {
    if (_permissionStatus == 'Granted') {
      return 'Notifications are allowed';
    } else if (_permissionStatus == 'Not Required (Pre-Android 13)') {
      return 'No permission needed on this Android version';
    } else if (_permissionStatus == 'Permanently Denied') {
      return 'Tap to fix in system settings';
    } else if (_permissionStatus == 'Denied') {
      return 'Tap to request permission';
    } else {
      return 'Unknown permission status';
    }
  }

  VoidCallback? _getPermissionStatusAction() {
    if (_permissionStatus == 'Permanently Denied') {
      return () => _showSystemSettingsDialog();
    } else if (_permissionStatus == 'Denied') {
      return _requestPermission;
    } else {
      return null;
    }
  }

  Future<bool> Function(bool)? _getToggleAction() {
    return (bool value) async {
      if (value) {
        // Enabling notifications
        if (_permissionStatus == 'Denied') {
          // Request permission first
          await _requestPermission();
          if (_permissionStatus == 'Granted' || _permissionStatus == 'Not Required (Pre-Android 13)') {
            await _scheduler.enableCustomReminders(true);
            await _loadSettings();
          }
          return _settings.enabled; // Don't change if permission not granted
        } else if (_permissionStatus == 'Permanently Denied') {
          // Show system settings guidance
          _showSystemSettingsDialog();
          return false; // Don't enable
        } else {
          // Permission granted or not needed
          await _scheduler.enableCustomReminders(true);
          await _loadSettings();
          return true;
        }
      } else {
        // Disabling notifications
        await _scheduler.enableCustomReminders(false);
        await _loadSettings();
        return false;
      }
    };
  }

  String _getToggleSubtitle() {
    if (_settings.enabled) {
      return _settings.scheduleSummary;
    } else if (_permissionStatus == 'Permanently Denied') {
      return 'Grant notification permission to enable';
    } else if (_permissionStatus == 'Denied') {
      return 'Tap to request permission and enable';
    } else {
      return 'Custom reminders are disabled';
    }
  }

  @override
  Widget build(BuildContext context) {
    final darkBlue = Color(0xFF1A365D);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(
          title: Text('Custom Reminders'),
          backgroundColor: darkBlue,
        ),
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('Custom Reminders'),
        backgroundColor: darkBlue,
        actions: [
          TextButton(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => CustomRemindersSoftAskScreen(),
                ),
              );
            },
            child: Text(
              'About',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: EdgeInsets.fromLTRB(22, 22, 22, 32),
          children: [
          // Enable/Disable Toggle
          ListTile(
            title: Text('Enable Custom Reminders', style: TextStyle(fontWeight: FontWeight.bold)),
            trailing: Switch(
              value: _settings.enabled,
              onChanged: _getToggleAction(),
            ),
            subtitle: Text(_getToggleSubtitle()),
          ),
          Divider(height: 36),

          // Permission Status
          ListTile(
            title: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Notification Permission', style: TextStyle(fontWeight: FontWeight.bold)),
                      SizedBox(height: 2),
                      Text(
                        _getPermissionStatusDescription(),
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                      ),
                    ],
                  ),
                ),
                Container(
                  constraints: BoxConstraints(maxWidth: 100),
                  padding: EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                  decoration: BoxDecoration(
                    color: _getPermissionStatusColor().withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: _getPermissionStatusColor()),
                  ),
                  child: Text(
                    _permissionStatus == 'Not Required (Pre-Android 13)' ? 'Pre-Android 13' : _permissionStatus,
                    style: TextStyle(
                      color: _getPermissionStatusColor(),
                      fontWeight: FontWeight.bold,
                      fontSize: 10,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
            onTap: _getPermissionStatusAction(),
          ),
          Divider(height: 36),

          // Add New Reminder
          ListTile(
            title: Row(
              children: [
                Expanded(
                  child: Text('Add New Reminder', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
                if (_settings.messages.length >= 2 && !_isPremium) ...[
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade100,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.orange.shade300),
                    ),
                    child: Text(
                      'PREMIUM REQUIRED',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: Colors.orange.shade700,
                      ),
                    ),
                  ),
                ],
              ],
            ),
            trailing: Icon(
              Icons.add,
              color: (_settings.messages.length >= 2 && !_isPremium) ? Colors.grey : darkBlue,
            ),
            subtitle: Text(_settings.messages.length >= 2 && !_isPremium
              ? 'You have ${_settings.messages.length}/2 reminders • Upgrade for more'
              : 'Create a personalized reminder message (${_settings.messages.length}/2 used)'),
            onTap: () => _showMessageDialog(),
          ),
          Divider(height: 36),

          // Existing Messages
          if (_settings.messages.isNotEmpty) ...[
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Your Reminders (${_settings.messages.length})',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : darkBlue,
                    ),
                  ),
                ),
                if (_settings.messages.length >= 2 && !_isPremium) ...[
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.orange.shade200),
                    ),
                    child: Text(
                      'Free: 2/2 • Premium: 5',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Colors.orange.shade700,
                      ),
                    ),
                  ),
                ] else if (_isPremium) ...[
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.green.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.green.shade200),
                    ),
                    child: Text(
                      'Premium: ${_settings.messages.length}/5',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Colors.green.shade700,
                      ),
                    ),
                  ),
                ],
              ],
            ),
            SizedBox(height: 16),
            ..._settings.messages.asMap().entries.map((entry) {
              final index = entry.key;
              final message = entry.value;
              return Container(
                margin: EdgeInsets.only(bottom: 12),
                padding: EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: isDark ? Color(0xFF2D3748) : Colors.grey[50],
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isDark ? Colors.white.withOpacity(0.1) : Colors.grey[200]!,
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        message,
                        style: TextStyle(
                          fontSize: 14,
                          height: 1.4,
                        ),
                      ),
                    ),
                    PopupMenuButton<String>(
                      onSelected: (action) {
                        if (action == 'edit') {
                          _showMessageDialog(existingMessage: message, index: index);
                        } else if (action == 'delete') {
                          _deleteMessage(index);
                        }
                      },
                      itemBuilder: (context) => [
                        PopupMenuItem(
                          value: 'edit',
                          child: Row(
                            children: [
                              Icon(Icons.edit, size: 16),
                              SizedBox(width: 8),
                              Text('Edit'),
                            ],
                          ),
                        ),
                        PopupMenuItem(
                          value: 'delete',
                          child: Row(
                            children: [
                              Icon(Icons.delete, size: 16, color: Colors.red),
                              SizedBox(width: 8),
                              Text('Delete', style: TextStyle(color: Colors.red)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            }),
            Divider(height: 36),
          ],

          // Max Per Day Setting
          ListTile(
            title: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Max Reminders Per Day', style: TextStyle(fontWeight: FontWeight.bold)),
                      SizedBox(height: 2),
                      Container(
                        padding: EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.orange.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.orange.shade200),
                        ),
                        child: Text(
                          'Free: ${_settings.maxPerDay}/2 • Premium: Up to 5',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: Colors.orange.shade700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.settings, color: darkBlue),
              ],
            ),
            subtitle: Text(_settings.messages.isNotEmpty && _settings.maxPerDay >= 2 && !_isPremium
              ? '${_settings.maxPerDay} reminder${_settings.maxPerDay != 1 ? 's' : ''} per day • Tap for premium upgrade'
              : '${_settings.maxPerDay} reminder${_settings.maxPerDay != 1 ? 's' : ''} per day • Tap to change'),
            onTap: _settings.messages.isNotEmpty ? () {
              // If user is already at max (2) and not premium, show premium dialog directly
              if (_settings.maxPerDay >= 2 && !_isPremium) {
                _showPremiumRequiredDialog();
              } else {
                _showMaxPerDayDialog();
              }
            } : () {
              // If no messages, show a hint to add messages first
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Add some reminder messages first, then you can adjust the frequency'),
                  backgroundColor: Colors.blue,
                ),
              );
            },
          ),
          Divider(height: 36),

          // Time Window Start
          ListTile(
            title: Text('Time Window Start', style: TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text('${_settings.startHour.toString().padLeft(2, '0')}:00'),
            trailing: Icon(Icons.access_time, color: darkBlue),
            onTap: () => _showTimePicker(
              isStartTime: true,
              currentHour: _settings.startHour,
            ),
          ),
          Divider(height: 36),

          // Time Window End
          ListTile(
            title: Text('Time Window End', style: TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text('${_settings.endHour.toString().padLeft(2, '0')}:00'),
            trailing: Icon(Icons.access_time, color: darkBlue),
            onTap: () => _showTimePicker(
              isStartTime: false,
              currentHour: _settings.endHour,
            ),
          ),
          Divider(height: 36),

          // Current Settings Info
          Container(
            margin: EdgeInsets.only(bottom: 24),
            padding: EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isDark ? Color(0xFF2D3748) : Colors.blue.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: isDark ? Colors.white.withOpacity(0.1) : Colors.blue.shade200),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Current Settings',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: isDark ? Colors.white : Colors.blue.shade700,
                  ),
                ),
                SizedBox(height: 8),
                Text(
                  'Time Window: ${_settings.formattedTimeWindow}', 
                  style: TextStyle(color: isDark ? Colors.white70 : Colors.blue.shade700),
                ),
                Text(
                  'Max per day: ${_settings.maxPerDay}', 
                  style: TextStyle(color: isDark ? Colors.white70 : Colors.blue.shade700),
                ),
                Text(
                  'Messages: ${_settings.messages.length}', 
                  style: TextStyle(color: isDark ? Colors.white70 : Colors.blue.shade700),
                ),
                Text(
                  'Status: ${_settings.enabled ? 'Enabled' : 'Disabled'}', 
                  style: TextStyle(color: isDark ? Colors.white70 : Colors.blue.shade700),
                ),
                Text(
                  'Permission: $_permissionStatus', 
                  style: TextStyle(color: isDark ? Colors.white70 : Colors.blue.shade700),
                ),
              ],
            ),
          ),
          ],
        ),
      ),
    );
  }
}
