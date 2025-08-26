import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:permission_handler/permission_handler.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  static const MethodChannel _channel = MethodChannel(
    'smarthaus/notifications',
  );

  Future<void> initialize() async {
    await _initializeFirebaseMessaging();
    await _requestPermissions();
  }

  Future<void> _initializeFirebaseMessaging() async {
    // Get FCM token for this device
    String? token = await _messaging.getToken();
    debugPrint('FCM Token: $token');

    // Handle background messages
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

    // Handle foreground messages
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      debugPrint('Received foreground message: ${message.notification?.title}');
      _handleForegroundMessage(message);
    });

    // Handle notification taps when app is in background
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      debugPrint('Notification tapped: ${message.notification?.title}');
      _handleNotificationTap(message.data);
    });
  }

  Future<void> _requestPermissions() async {
    // Request notification permission
    await Permission.notification.request();

    // Request FCM permission
    NotificationSettings settings = await _messaging.requestPermission(
      alert: true,
      announcement: false,
      badge: true,
      carPlay: false,
      criticalAlert: true,
      provisional: false,
      sound: true,
    );

    debugPrint(
      'Notification permission status: ${settings.authorizationStatus}',
    );
  }

  Future<void> showSecurityAlert({
    required String title,
    required String body,
    required int failedAttempts,
  }) async {
    debugPrint('Security Alert: $title - $body');

    // Show system notification with sound
    await _showSystemNotification(title, body);
  }

  Future<void> _showSystemNotification(String title, String body) async {
    try {
      await _channel.invokeMethod('showNotification', {
        'title': title,
        'body': body,
        'channelId': 'security_alerts',
        'channelName': 'Security Alerts',
        'importance': 'high',
        'priority': 'high',
        'sound': true,
        'vibrate': true,
      });
      debugPrint('System notification triggered: $title');
    } catch (e) {
      debugPrint('Error showing system notification: $e');
      // Fallback to simple debug print
      debugPrint('SECURITY ALERT: $title - $body');
    }
  }

  void _handleForegroundMessage(RemoteMessage message) {
    // Handle messages received while app is in foreground
    debugPrint('Handling foreground message: ${message.notification?.body}');

    // Show system notification even when app is in foreground
    if (message.notification != null) {
      _showSystemNotification(
        message.notification!.title ?? 'Security Alert',
        message.notification!.body ?? 'Security event detected',
      );
    }
  }

  void _handleNotificationTap(Map<String, dynamic> data) {
    // Handle notification tap - could navigate to specific screen
    debugPrint('Handling notification tap with data: $data');
  }

  Future<String?> getFCMToken() async {
    return await _messaging.getToken();
  }

  Future<void> subscribeToTopic(String topic) async {
    await _messaging.subscribeToTopic(topic);
    debugPrint('Subscribed to topic: $topic');
  }

  Future<void> unsubscribeFromTopic(String topic) async {
    await _messaging.unsubscribeFromTopic(topic);
    debugPrint('Unsubscribed from topic: $topic');
  }
}

// Background message handler (must be top-level function)
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  debugPrint('Handling background message: ${message.notification?.title}');

  // For background messages, FCM automatically shows notifications
  // if the message has a notification payload
}
