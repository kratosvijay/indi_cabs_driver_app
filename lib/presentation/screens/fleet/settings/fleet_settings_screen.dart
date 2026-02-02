import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:project_taxi_driver_app/screens/login.dart';
import 'package:project_taxi_driver_app/screens/language.dart';
import 'package:project_taxi_driver_app/utils/fleet_translations.dart';

class FleetSettingsScreen extends StatefulWidget {
  final User user;
  final VoidCallback? onLanguageChanged;
  const FleetSettingsScreen({
    super.key,
    required this.user,
    this.onLanguageChanged,
  });

  @override
  State<FleetSettingsScreen> createState() => _FleetSettingsScreenState();
}

class _FleetSettingsScreenState extends State<FleetSettingsScreen> {
  bool _isLoading = true;
  String _displayName = "Fleet Operator";
  String? _photoUrl;
  int _totalDrivers = 0;
  int _totalVehicles = 0;

  // Language State
  String _selectedLanguageCode = 'en';

  // Theme Constants
  final Color _bgDark = const Color(0xFF0F1115);
  final Color _cardDark = const Color(0xFF181B21);
  final Color _neonBlue = const Color(0xFF00E5FF);
  final Color _neonTeal = const Color(0xFF00FFA3);
  final Color _textWhite = Colors.white;
  final Color _textGrey = Colors.white54;

  @override
  void initState() {
    super.initState();
    _loadLanguage();
    _fetchOperatorData();
  }

  Future<void> _loadLanguage() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _selectedLanguageCode = prefs.getString('selectedLanguage') ?? 'en';
      });
    }
  }

  String _t(String key) {
    return FleetTranslations.get(_selectedLanguageCode, key);
  }

  Future<void> _fetchOperatorData() async {
    try {
      // 1. Fetch Profile
      final doc = await FirebaseFirestore.instance
          .collection('drivers')
          .doc(widget.user.uid)
          .get();

      if (doc.exists) {
        final data = doc.data() as Map<String, dynamic>;
        _displayName =
            data['displayName'] ?? widget.user.displayName ?? "Fleet Operator";
        _photoUrl = data['photoUrl'] ?? widget.user.photoURL;
      } else {
        _displayName = widget.user.displayName ?? "Fleet Operator";
        _photoUrl = widget.user.photoURL;
      }

      // 2. Fetch Stats
      final driversSnapshot = await FirebaseFirestore.instance
          .collection('drivers')
          .where('fleetOperatorId', isEqualTo: widget.user.uid)
          .count()
          .get();

      final vehiclesSnapshot = await FirebaseFirestore.instance
          .collection('vehicles')
          .where('ownerId', isEqualTo: widget.user.uid)
          .count()
          .get();

      if (mounted) {
        setState(() {
          _totalDrivers = driversSnapshot.count ?? 0;
          _totalVehicles = vehiclesSnapshot.count ?? 0;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Error fetching settings data: $e");
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _logout() async {
    await FirebaseAuth.instance.signOut();
    Get.offAll(() => const LoginScreen());
  }

  void _showDeleteAccountDialog() {
    Get.dialog(
      AlertDialog(
        backgroundColor: _cardDark,
        title: Text(_t('deleteAccount'), style: TextStyle(color: _textWhite)),
        content: Text(
          _t('deleteAccountMsg'),
          style: TextStyle(color: _textGrey),
        ),
        actions: [
          TextButton(onPressed: () => Get.back(), child: Text(_t('no'))),
          TextButton(
            onPressed: () {
              Get.back();
              Get.snackbar(
                _t('support'), // "Contact Support" title
                _t('contactSupportMsg'),
                backgroundColor: Colors.orange,
                colorText: Colors.white,
              );
            },
            child: Text(_t('yes'), style: const TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Center(child: CircularProgressIndicator(color: _neonBlue));
    }

    return Scaffold(
      backgroundColor: _bgDark,
      appBar: AppBar(
        title: Text(
          _t('settings'),
          style: TextStyle(color: _textWhite, fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        automaticallyImplyLeading: false, // Managed by Dashboard
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // 1. Profile Header
          Center(
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: _neonBlue, width: 2),
                    boxShadow: [
                      BoxShadow(
                        color: _neonBlue.withValues(alpha: 0.3),
                        blurRadius: 20,
                      ),
                    ],
                  ),
                  child: CircleAvatar(
                    radius: 50,
                    backgroundColor: _cardDark,
                    backgroundImage: _photoUrl != null
                        ? NetworkImage(_photoUrl!)
                        : null,
                    child: _photoUrl == null
                        ? Icon(Icons.person, size: 50, color: _textGrey)
                        : null,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  _displayName,
                  style: TextStyle(
                    color: _textWhite,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: _neonAnswer.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: _neonAnswer.withValues(alpha: 0.5)),
                  ),
                  child: Text(
                    _t('fleetOperator'),
                    style: TextStyle(
                      color: _neonAnswer,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 30),

          // 2. Stats
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: _cardDark,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildStatItem(_t('drivers'), "$_totalDrivers", _neonTeal),
                Container(width: 1, height: 40, color: Colors.white10),
                _buildStatItem(_t('vehicles'), "$_totalVehicles", _neonBlue),
              ],
            ),
          ),

          const SizedBox(height: 30),

          // 3. Settings Menus
          _buildSectionHeader(_t('account')),
          _buildSettingsOption(
            icon: Icons.language,
            title: _t('appLanguage'),
            subtitle: _getLanguageName(_selectedLanguageCode),
            onTap: () async {
              await Get.to(
                () => const LanguageSelectionScreen(isFromProfile: true),
              );
              await _loadLanguage();
              widget.onLanguageChanged?.call();
            },
          ),
          _buildSettingsOption(
            icon: Icons.logout,
            title: _t('logout'),
            color: Colors.orangeAccent,
            onTap: _logout,
          ),
          _buildSettingsOption(
            icon: Icons.delete_forever,
            title: _t('deleteAccount'),
            color: Colors.redAccent,
            onTap: _showDeleteAccountDialog,
          ),

          const SizedBox(height: 20),
          _buildSectionHeader(_t('support')),
          _buildSettingsOption(
            icon: Icons.help_outline,
            title: _t('helpCenter'),
            onTap: () {
              // Placeholder
              Get.snackbar(
                _t('support'),
                "${_t('helpCenter')} ${_t('comingSoon')}",
                colorText: _textWhite,
              );
            },
          ),
          _buildSettingsOption(
            icon: Icons.privacy_tip_outlined,
            title: _t('privacyPolicy'),
            onTap: () {},
          ),

          const SizedBox(height: 40),
          Center(
            child: Text(
              "Indi Cabs Fleet v1.2.1",
              style: TextStyle(color: _textGrey, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem(String label, String value, Color color) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            color: color,
            fontSize: 24,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 4),
        Text(label, style: TextStyle(color: _textGrey, fontSize: 12)),
      ],
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12, left: 4),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          color: _textGrey,
          fontSize: 12,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.2,
        ),
      ),
    );
  }

  Widget _buildSettingsOption({
    required IconData icon,
    required String title,
    String? subtitle,
    required VoidCallback onTap,
    Color? color,
  }) {
    final effectiveColor = color ?? _textWhite;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: _cardDark,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: ListTile(
        onTap: onTap,
        leading: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: effectiveColor.withValues(alpha: 0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: effectiveColor, size: 20),
        ),
        title: Text(
          title,
          style: TextStyle(
            color: effectiveColor,
            fontWeight: FontWeight.w600,
            fontSize: 16,
          ),
        ),
        subtitle: subtitle != null
            ? Text(subtitle, style: TextStyle(color: _textGrey, fontSize: 12))
            : null,
        trailing: Icon(
          Icons.arrow_forward_ios_rounded,
          color: _textGrey,
          size: 16,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    );
  }

  String _getLanguageName(String code) {
    switch (code) {
      case 'ta':
        return 'Tamil';
      case 'hi':
        return 'Hindi';
      case 'te':
        return 'Telugu';
      case 'kn':
        return 'Kannada';
      case 'ml':
        return 'Malayalam';
      case 'gu':
        return 'Gujarati';
      default:
        return 'English';
    }
  }

  // Helper color for "Fleet Operator" badge
  Color get _neonAnswer => const Color(0xFF00E5FF);
}
