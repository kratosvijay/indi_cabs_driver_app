import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:project_taxi_driver_app/utils/app_colors.dart';
import 'package:project_taxi_driver_app/widgets/pro_library.dart';
import 'package:project_taxi_driver_app/screens/chat_screen.dart';

class TrackSharedRideScreen extends StatelessWidget {
  final Map<String, dynamic> rideData;
  final String rideId;

  const TrackSharedRideScreen({
    super.key,
    required this.rideData,
    required this.rideId,
  });

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color bgColor = isDark ? const Color(0xFF0E0E13) : const Color(0xFFF5F7FA);

    return Scaffold(
      backgroundColor: bgColor,
      appBar: ProAppBar(
        titleText: 'Track Ride',
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline, color: Colors.white),
            onPressed: () => _confirmDelete(context, isDark),
          ),
          IconButton(
            icon: const Icon(Icons.info_outline, color: Colors.white),
            onPressed: () => _showRideDetails(context, isDark),
          ),
        ],
      ),
      body: Column(
        children: [
          _buildRideSummaryHeader(context, isDark),
          Expanded(
            child: _buildBookingsList(context, isDark),
          ),
        ],
      ),
    );
  }

  Widget _buildRideSummaryHeader(BuildContext context, bool isDark) {
    final int available = rideData['available_seats'] ?? 0;
    final int total = rideData['total_seats'] ?? 0;
    final int booked = total - available;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: AppColors.getAppBarGradient(context),
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(30)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 10,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _summaryItem('Booked', '$booked', Icons.people_alt),
          _summaryItem('Available', '$available', Icons.event_seat),
          _summaryItem('Price', '₹${rideData['price_per_seat'] ?? 0}', Icons.payments),
        ],
      ),
    );
  }

  Widget _summaryItem(String label, String value, IconData icon) {
    return Column(
      children: [
        Icon(icon, color: Colors.white70, size: 20),
        const SizedBox(height: 8),
        Text(value, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
        Text(label, style: const TextStyle(color: Colors.white60, fontSize: 12)),
      ],
    );
  }

  Widget _buildBookingsList(BuildContext context, bool isDark) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('shared_rides')
          .doc(rideId)
          .collection('bookings')
          .orderBy('created_at', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.no_accounts_outlined, size: 80, color: isDark ? Colors.white12 : Colors.grey[300]),
                const SizedBox(height: 16),
                Text(
                  'No bookings yet',
                  style: TextStyle(color: isDark ? Colors.white60 : Colors.grey, fontSize: 16, fontWeight: FontWeight.w500),
                ),
              ],
            ),
          );
        }

        final bookings = snapshot.data!.docs;

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: bookings.length,
          itemBuilder: (context, index) {
            final data = bookings[index].data() as Map<String, dynamic>;
            return _passengerCard(context, data, isDark);
          },
        );
      },
    );
  }

  Widget _passengerCard(BuildContext context, Map<String, dynamic> data, bool isDark) {
    final String name = data['passenger_name'] ?? 'Passenger';
    final String phone = data['passenger_phone'] ?? '';
    final String userId = data['passenger_id'] ?? '';
    final int seats = data['seats_booked'] ?? 1;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: AppColors.primary.withValues(alpha: 0.1),
            child: Text(name.isNotEmpty ? name[0].toUpperCase() : 'P', style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold)),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontWeight: FontWeight.bold, fontSize: 16)),
                const SizedBox(height: 2),
                Text(phone, style: TextStyle(color: isDark ? Colors.white60 : Colors.grey, fontSize: 13)),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(color: Colors.green.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
            child: Text('$seats Seat${seats > 1 ? 's' : ''}', style: const TextStyle(color: Colors.green, fontSize: 12, fontWeight: FontWeight.bold)),
          ),
          const SizedBox(width: 8),
          _actionBtn(Icons.phone, Colors.blue, () => _handleCall(phone)),
          _actionBtn(Icons.chat_bubble_outline, Colors.orange, () => _handleMessage(context, name, userId)),
        ],
      ),
    );
  }

  Widget _actionBtn(IconData icon, Color color, VoidCallback onTap) {
    return IconButton(
      icon: Icon(icon, color: color, size: 22),
      onPressed: onTap,
    );
  }

  void _handleCall(String phone) async {
    if (phone.isEmpty) return;
    final Uri url = Uri.parse('tel:$phone');
    if (await canLaunchUrl(url)) {
      await launchUrl(url);
    }
  }

  void _handleMessage(BuildContext context, String name, String userId) {
    Get.to(() => ChatScreen(
          rideId: rideId,
          currentUserId: rideData['driver_id'] ?? '',
          otherUserName: name,
          chatCollection: 'shared_rides',
        ));
  }

  void _confirmDelete(BuildContext context, bool isDark) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        title: const Text('Delete Ride', style: TextStyle(fontWeight: FontWeight.bold)),
        content: const Text('Are you sure you want to delete this posted ride? This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel', style: TextStyle(color: isDark ? Colors.white70 : Colors.grey)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _deleteRide();
            },
            child: const Text('Delete', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteRide() async {
    try {
      await FirebaseFirestore.instance.collection('shared_rides').doc(rideId).delete();
      Get.back();
      Get.snackbar(
        'Ride Deleted',
        'Your ride has been successfully removed.',
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: Colors.red.shade100,
        colorText: Colors.red.shade900,
      );
    } catch (e) {
      debugPrint("Error deleting ride: $e");
      Get.snackbar('Error', 'Failed to delete ride.');
    }
  }

  void _showRideDetails(BuildContext context, bool isDark) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Ride Path', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            _locationRow(Icons.my_location, rideData['start_location'] ?? '', Colors.blue),
            Padding(
              padding: const EdgeInsets.only(left: 11),
              child: Container(width: 2, height: 20, color: Colors.grey.withValues(alpha: 0.3)),
            ),
            _locationRow(Icons.location_on, rideData['destination'] ?? '', Colors.red),
          ],
        ),
      ),
    );
  }

  Widget _locationRow(IconData icon, String text, Color color) {
    return Row(
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(width: 12),
        Expanded(child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis)),
      ],
    );
  }
}
