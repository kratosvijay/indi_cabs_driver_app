import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:get/get.dart';
import 'package:project_taxi_driver_app/widgets/pro_library.dart';

/// A simple model for a notification
class AppNotification {
  final String id;
  final String title;
  final String body;
  final DateTime timestamp;
  final bool isRead;
  final Map<String, dynamic> data; // For extra data like 'rideId'

  AppNotification({
    required this.id,
    required this.title,
    required this.body,
    required this.timestamp,
    required this.isRead,
    required this.data,
  });

  factory AppNotification.fromFirestore(DocumentSnapshot doc) {
    Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
    return AppNotification(
      id: doc.id,
      title: data['title'] ?? 'No Title',
      body: data['body'] ?? 'No Content',
      timestamp: (data['timestamp'] as Timestamp? ?? Timestamp.now()).toDate(),
      isRead: data['isRead'] ?? false,
      data: data['data'] as Map<String, dynamic>? ?? {},
    );
  }
}

class NotificationsScreen extends StatefulWidget {
  final User? user; // Made optional to support calls without explicit user
  const NotificationsScreen({super.key, this.user});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  Stream<List<AppNotification>>? _notificationsStream; // Make nullable
  final FirebaseAuth _auth = FirebaseAuth.instance;

  @override
  void initState() {
    super.initState();
    _notificationsStream = _getNotificationsStream();
  }

  Stream<List<AppNotification>> _getNotificationsStream() {
    final uid = widget.user?.uid ?? _auth.currentUser?.uid;

    if (uid == null) {
      return Stream.value([]);
    }

    // This stream listens to the 'notifications' subcollection for the driver
    // Changed 'users' to 'drivers' to match app schema
    return FirebaseFirestore.instance
        .collection('drivers')
        .doc(uid)
        .collection('notifications')
        .orderBy('timestamp', descending: true)
        .limit(50)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => AppNotification.fromFirestore(doc))
              .toList(),
        )
        .handleError((error) {
          debugPrint("Error fetching notifications: $error");
          return <AppNotification>[];
        });
  }

  /// Marks a notification as read
  Future<void> _markAsRead(String notificationId) async {
    final uid = widget.user?.uid ?? _auth.currentUser?.uid;
    if (uid == null) return;

    try {
      await FirebaseFirestore.instance
          .collection('drivers')
          .doc(uid)
          .collection('notifications')
          .doc(notificationId)
          .update({'isRead': true});
    } catch (e) {
      debugPrint("Error marking notification as read: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: ProAppBar(titleText: "notifications".tr),
      body: StreamBuilder<List<AppNotification>>(
        stream: _notificationsStream,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return const Center(child: Text("Error loading notifications."));
          }
          if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return Center(
              child: FadeInSlide(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.notifications_off_outlined,
                      size: 80,
                      color: isDark
                          ? Colors.grey.shade700
                          : Colors.grey.shade300,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      "noNotifications".tr,
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white70 : Colors.grey.shade800,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      "noNotificationsMsg".tr,
                      style: TextStyle(
                        fontSize: 16,
                        color: isDark
                            ? Colors.grey.shade500
                            : Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }

          final notifications = snapshot.data!;
          return ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            itemCount: notifications.length,
            itemBuilder: (context, index) {
              final notif = notifications[index];
              return FadeInSlide(child: _buildNotificationCard(notif, isDark));
            },
          );
        },
      ),
    );
  }

  Widget _buildNotificationCard(AppNotification notif, bool isDark) {
    final isRead = notif.isRead;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: isRead
            ? null // No gradient for read items
            : LinearGradient(
                colors: isDark
                    ? [const Color(0xFF1E1E1E), const Color(0xFF2C2C2C)]
                    : [Colors.blue.shade50, Colors.white],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
        color: isRead
            ? (isDark ? Colors.black26 : Colors.white)
            : null, // Use gradient if unread
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(
          color: isRead
              ? (isDark ? Colors.white10 : Colors.grey.shade200)
              : (isDark
                    ? Colors.blueAccent.withValues(alpha: 0.3)
                    : Colors.blueAccent.withValues(alpha: 0.2)),
          width: 1,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () {
            if (!isRead) {
              _markAsRead(notif.id);
            }
          },
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Icon Indicator
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isRead
                        ? (isDark ? Colors.grey.shade800 : Colors.grey.shade100)
                        : (isDark ? Colors.blue.shade900 : Colors.blue.shade50),
                  ),
                  child: Icon(
                    isRead
                        ? Icons.notifications_outlined
                        : Icons.notifications_active,
                    size: 24,
                    color: isRead
                        ? (isDark ? Colors.grey : Colors.grey.shade500)
                        : Colors.blueAccent,
                  ),
                ),
                const SizedBox(width: 16),
                // Content
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              notif.title,
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: isRead
                                    ? FontWeight.w500
                                    : FontWeight.bold,
                                color: isDark ? Colors.white : Colors.black87,
                              ),
                            ),
                          ),
                          if (!isRead)
                            Container(
                              width: 8,
                              height: 8,
                              decoration: const BoxDecoration(
                                color: Colors.blueAccent,
                                shape: BoxShape.circle,
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        notif.body,
                        style: TextStyle(
                          fontSize: 14,
                          color: isDark
                              ? Colors.grey.shade400
                              : Colors.grey.shade600,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        _formatTimestamp(notif.timestamp),
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark
                              ? Colors.grey.shade600
                              : Colors.grey.shade400,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _formatTimestamp(DateTime timestamp) {
    final now = DateTime.now();
    final difference = now.difference(timestamp);

    if (difference.inDays > 0) {
      return DateFormat('dd MMM, hh:mm a').format(timestamp);
    } else if (difference.inHours > 0) {
      return '${difference.inHours}h ago';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes}m ago';
    } else {
      return 'justNow'.tr;
    }
  }
}
