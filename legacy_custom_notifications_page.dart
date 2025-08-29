import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:permission_handler/permission_handler.dart';

// This file contains the legacy CustomNotificationPage
// It's kept for reference but the new system uses CustomRemindersSoftAskScreen and CustomRemindersSettingsScreen

class CustomNotificationPage extends StatefulWidget {
  @override
  _CustomNotificationPageState createState() => _CustomNotificationPageState();
}

class _CustomNotificationPageState extends State<CustomNotificationPage> {
  final darkBlue = const Color(0xFF003366);
  final TextEditingController _controller = TextEditingController();
  List<String> _messages = [];
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _loadMessages();
  }

  Future<void> _loadMessages() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    final List<String> saved = prefs.getStringList('custom_notifications') ?? [];
    setState(() {
      _messages = saved;
      _loaded = true;
    });
  }

  Future<void> _saveMessages() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('custom_notifications', _messages);
  }

  void _addNotification() async {
    final input = _controller.text.trim();

    if (input.isEmpty || _messages.length >= 5) {
      if (_messages.length >= 5) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Maximum of 5 reminders reached'),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return;
    }

    // Check notification permission first
    final hasPermission = await Permission.notification.status.isGranted;
    if (!hasPermission) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Please enable notifications in your device settings to use custom reminders'),
          backgroundColor: Colors.orange,
          duration: Duration(seconds: 3),
        ),
      );
      return;
    }

    setState(() {
      _messages.insert(0, input);
      _controller.clear();
    });
    await _saveMessages();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Reminder scheduled successfully!'),
        backgroundColor: Colors.green,
        duration: Duration(seconds: 2),
      ),
    );
  }

  void _deleteNotification(int idx) async {
    setState(() => _messages.removeAt(idx));
    await _saveMessages();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Reminder deleted successfully!'),
        backgroundColor: Colors.green,
        duration: Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final primaryBlue = const Color(0xFF1A365D);
    final accentBlue = const Color(0xFF3182CE);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: primaryBlue,
        title: Text("Custom Reminders"),
        centerTitle: true,
      ),
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SingleChildScrollView(
        padding: EdgeInsets.all(24),
        child: Column(
          children: [
            // Header Section
            Container(
              padding: EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: isDark ? Color(0xFF2D3748) : Colors.grey[50],
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isDark ? Colors.white.withOpacity(0.1) : Colors.grey[200]!,
                  width: 1,
                ),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.notifications_active,
                        color: accentBlue,
                        size: 24,
                      ),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          "Custom Reminders (${_messages.length}/5)",
                          style: TextStyle(
                            fontFamily: 'Inter',
                            fontWeight: FontWeight.w700,
                            fontSize: 18,
                            color: isDark ? Colors.white : primaryBlue,
                          ),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 12),
                  Text(
                    "Write a short reason to remind yourself why you're making this change. We'll send it to you once each day, at a random time.",
                    style: TextStyle(
                      fontFamily: 'Inter',
                      color: isDark ? Colors.white.withOpacity(0.8) : primaryBlue.withOpacity(0.8),
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      height: 1.4,
                    ),
                    textAlign: TextAlign.left,
                  ),
                ],
              ),
            ),
            SizedBox(height: 24),

            // Input Section
            Container(
              padding: EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isDark ? Color(0xFF2D3748) : Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isDark ? Colors.white.withOpacity(0.1) : Colors.grey[200]!,
                  width: 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 10,
                    offset: Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "Add New Reminder",
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white : primaryBlue,
                    ),
                  ),
                  SizedBox(height: 12),
                  TextField(
                    controller: _controller,
                    maxLines: 3,
                    maxLength: 200,
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 14,
                    ),
                    decoration: InputDecoration(
                      hintText: "Enter your reminder message...",
                      hintStyle: TextStyle(
                        fontFamily: 'Inter',
                        color: Colors.grey[500],
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: Colors.grey[300]!),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: accentBlue, width: 2),
                      ),
                      contentPadding: EdgeInsets.all(12),
                    ),
                  ),
                  SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _addNotification,
                      icon: Icon(Icons.add, size: 18),
                      label: Text("Add Reminder"),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: accentBlue,
                        foregroundColor: Colors.white,
                        padding: EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        textStyle: TextStyle(
                          fontFamily: 'Inter',
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: 24),

            // Messages List
            if (_messages.isNotEmpty) ...[
              Container(
                width: double.infinity,
                padding: EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: isDark ? Color(0xFF2D3748) : Colors.grey[50],
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isDark ? Colors.white.withOpacity(0.1) : Colors.grey[200]!,
                    width: 1,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Your Custom Reminders",
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: isDark ? Colors.white : primaryBlue,
                      ),
                    ),
                    SizedBox(height: 16),
                    ...List.generate(_messages.length, (index) {
                      return Container(
                        margin: EdgeInsets.only(bottom: 12),
                        padding: EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: isDark ? Color(0xFF1A202C) : Colors.white,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: isDark ? Colors.white.withOpacity(0.1) : Colors.grey[200]!,
                            width: 1,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.05),
                              blurRadius: 4,
                              offset: Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                _messages[index],
                                style: TextStyle(
                                  fontFamily: 'Inter',
                                  fontSize: 14,
                                  color: isDark ? Colors.white : Colors.black87,
                                  height: 1.4,
                                ),
                              ),
                            ),
                            SizedBox(width: 12),
                            IconButton(
                              onPressed: () => _deleteNotification(index),
                              icon: Icon(
                                Icons.delete,
                                color: Colors.red[400],
                                size: 20,
                              ),
                              tooltip: 'Delete reminder',
                            ),
                          ],
                        ),
                      );
                    }),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
