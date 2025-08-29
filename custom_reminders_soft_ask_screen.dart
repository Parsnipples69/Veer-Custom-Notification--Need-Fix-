import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'custom_reminders_settings_screen.dart';
import 'package:url_launcher/url_launcher.dart';
import '../main.dart';

class CustomRemindersSoftAskScreen extends StatefulWidget {
  @override
  _CustomRemindersSoftAskScreenState createState() => _CustomRemindersSoftAskScreenState();
}

class _CustomRemindersSoftAskScreenState extends State<CustomRemindersSoftAskScreen> {
  String _permissionStatus = 'Checking...';

  @override
  void initState() {
    super.initState();
    _checkPermissionStatus();
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
        // Show system settings guidance for permanently denied
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _showSystemSettingsDialog();
        });
      } else if (status.isDenied) {
        // Automatically request permission when entering the page
        final newStatus = await Permission.notification.request();
        if (newStatus.isGranted) {
          statusText = 'Granted';
        } else if (newStatus.isPermanentlyDenied) {
          statusText = 'Permanently Denied';
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _showSystemSettingsDialog();
          });
        } else {
          statusText = 'Denied';
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _showPermissionExplanation();
          });
        }
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
      // Navigate to settings screen
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => CustomRemindersSettingsScreen()),
      );
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
          'Custom reminders require notification permission to send you personalized motivational messages throughout the day. This helps you stay on track with your goals.'
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

  void _showPremiumDialog() {
    showDialog(
      context: context,
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
                'Upgrade to Premium',
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
                'Unlock up to 5 custom reminders and enjoy the full Veer experience!',
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
              // Feature benefits
              _buildFeatureItem('Up to 5 Custom Reminders', Icons.notifications),
              _buildFeatureItem('Dark Mode', Icons.dark_mode),
              _buildFeatureItem('Ad-free Experience', Icons.block),
              SizedBox(height: 16),
              // Terms of Service link
              GestureDetector(
                onTap: () async {
                  const url = 'https://support.google.com/googleplay/answer/7018481';
                  if (await canLaunchUrl(Uri.parse(url))) {
                    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
                  }
                },
                child: Text(
                  'Terms of Service & Refund Policy',
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: Colors.orange.shade600,
                    decoration: TextDecoration.underline,
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
                        // Navigate to purchase flow - this would need to be implemented
                        // For now, just show a placeholder
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

  Widget _buildFeatureItem(String feature, IconData icon) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 16, color: Colors.orange.shade600),
          SizedBox(width: 8),
          Text(
            feature,
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: Colors.grey[700],
            ),
          ),
        ],
      ),
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

  @override
  Widget build(BuildContext context) {
    final darkBlue = Color(0xFF1A365D);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: Text('Custom Reminders'),
        backgroundColor: darkBlue,
        leading: IconButton(
          icon: Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Column(
            children: [
              // Flexible content area that shrinks if needed
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
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
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  Icons.notifications_active_rounded,
                                  color: darkBlue,
                                  size: 32,
                                ),
                                SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    'Custom Reminders',
                                    style: TextStyle(
                                      fontSize: 24,
                                      fontWeight: FontWeight.bold,
                                      color: isDark ? Colors.white : darkBlue,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            SizedBox(height: 16),
                            Text(
                              'Create personalized motivational messages to help you stay on track with your goals.',
                              style: TextStyle(
                                fontSize: 16,
                                height: 1.4,
                                color: isDark ? Colors.white.withOpacity(0.8) : Colors.black87,
                              ),
                            ),
                          ],
                        ),
                      ),

                      SizedBox(height: 24),

                      // Value Proposition Cards
                      Container(
                        padding: EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.blue.shade50,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.blue.shade200),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.lightbulb, color: Colors.blue.shade700),
                                SizedBox(width: 8),
                                Text(
                                  'Why Custom Reminders?',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.blue.shade700,
                                    fontSize: 16,
                                  ),
                                ),
                              ],
                            ),
                            SizedBox(height: 12),
                            Text(
                              '• Personalized messages tailored to your specific goals\n'
                              '• Multiple reminders per day to keep you motivated\n'
                              '• Random delivery times within your preferred window\n'
                              '• Easy to manage and update anytime\n'
                              '• Works even when the app is closed',
                              style: TextStyle(
                                fontSize: 14,
                                height: 1.5,
                                color: Colors.blue.shade700,
                              ),
                            ),
                          ],
                        ),
                      ),

                      SizedBox(height: 16),

                      Container(
                        padding: EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.green.shade50,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.green.shade200),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.settings, color: Colors.green.shade700),
                                SizedBox(width: 8),
                                Text(
                                  'Complete Control',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.green.shade700,
                                    fontSize: 16,
                                  ),
                                ),
                              ],
                            ),
                            SizedBox(height: 12),
                            Text(
                              '• Choose how many reminders per day\n'
                              '• Set your preferred time window\n'
                              '• Add, edit, or remove messages anytime\n'
                              '• Enable/disable individual reminders\n'
                              '• Premium: Up to 5 custom reminders',
                              style: TextStyle(
                                fontSize: 14,
                                height: 1.5,
                                color: Colors.green.shade700,
                              ),
                            ),
                          ],
                        ),
                      ),

                      SizedBox(height: 24),

                      // Premium Advertisement Card
                      Container(
                        padding: EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [Colors.orange.shade50, Colors.orange.shade100],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.orange.shade200, width: 2),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: EdgeInsets.all(10),
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
                                    color: Colors.white,
                                    size: 24,
                                  ),
                                ),
                                SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Unlock Premium Features',
                                        style: TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.orange.shade800,
                                        ),
                                      ),
                                      SizedBox(height: 4),
                                      Text(
                                        'Get up to 5 custom reminders',
                                        style: TextStyle(
                                          fontSize: 14,
                                          color: Colors.orange.shade700,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            SizedBox(height: 16),
                            Row(
                              children: [
                                Expanded(
                                  child: ElevatedButton.icon(
                                    onPressed: _showPremiumDialog,
                                    icon: Icon(Icons.upgrade, size: 18),
                                    label: Text('Upgrade Now'),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.orange.shade500,
                                      foregroundColor: Colors.white,
                                      padding: EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            SizedBox(height: 12),
                            Text(
                              '• Up to 5 custom reminders (instead of 2)\n'
                              '• Dark mode support\n'
                              '• Ad-free experience\n'
                              '• Support app development',
                              style: TextStyle(
                                fontSize: 12,
                                height: 1.4,
                                color: Colors.orange.shade700,
                              ),
                            ),
                            SizedBox(height: 8),
                            Container(
                              padding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.orange.shade200,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                'Only ${PremiumService.getLocalizedPrice()}/month',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.orange.shade800,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                      SizedBox(height: 24),

                      // Permission Status
                      Container(
                        padding: EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: _getPermissionStatusColor().withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: _getPermissionStatusColor()),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              _permissionStatus == 'Granted' ? Icons.check_circle :
                              _permissionStatus == 'Not Required (Pre-Android 13)' ? Icons.info :
                              Icons.warning,
                              color: _getPermissionStatusColor(),
                            ),
                            SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Notification Permission',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: _getPermissionStatusColor(),
                                    ),
                                  ),
                                  Text(
                                    _permissionStatus == 'Granted' ? 'Ready to send reminders' :
                                    _permissionStatus == 'Not Required (Pre-Android 13)' ? 'No permission needed on this Android version' :
                                    _permissionStatus == 'Permanently Denied' ? 'Grant permission in system settings' :
                                    'Tap below to enable notifications',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: _getPermissionStatusColor(),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),

                      SizedBox(height: 24),
                    ],
                  ),
                ),
              ),

              // Fixed bottom buttons area
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_permissionStatus == 'Granted' || _permissionStatus == 'Not Required (Pre-Android 13)')
                    Container(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: () {
                          Navigator.pushReplacement(
                            context,
                            MaterialPageRoute(builder: (_) => CustomRemindersSettingsScreen()),
                          );
                        },
                        icon: Icon(Icons.settings, size: 20),
                        label: Expanded(
                          child: Text(
                            'Manage Custom Reminders',
                            textAlign: TextAlign.center,
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: darkBlue,
                          foregroundColor: Colors.white,
                          padding: EdgeInsets.symmetric(vertical: 16, horizontal: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          minimumSize: Size(double.infinity, 56),
                        ),
                      ),
                    )
                  else
                    Container(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _requestPermission,
                        icon: Icon(Icons.notifications_active, size: 20),
                        label: Expanded(
                          child: Text(
                            'Enable Custom Reminders',
                            textAlign: TextAlign.center,
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: darkBlue,
                          foregroundColor: Colors.white,
                          padding: EdgeInsets.symmetric(vertical: 16, horizontal: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          minimumSize: Size(double.infinity, 56),
                        ),
                      ),
                    ),

                  SizedBox(height: 12),

                  OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text('Maybe Later'),
                    style: OutlinedButton.styleFrom(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
