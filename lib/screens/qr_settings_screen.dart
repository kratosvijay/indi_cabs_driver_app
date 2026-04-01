import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:project_taxi_driver_app/services/id_service.dart';
import 'package:project_taxi_driver_app/widgets/pro_library.dart';

class QrSettingsScreen extends StatefulWidget {
  final User user;
  const QrSettingsScreen({super.key, required this.user});

  @override
  State<QrSettingsScreen> createState() => _QrSettingsScreenState();
}

class _QrSettingsScreenState extends State<QrSettingsScreen> {
  final TextEditingController _upiController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = true;
  List<String> _upiIds = [];
  String? _activeUpiId;
  String? _driverDocId;

  @override
  void initState() {
    super.initState();
    _loadDriverData();
  }

  @override
  void dispose() {
    _upiController.dispose();
    super.dispose();
  }
  Future<void> _loadDriverData() async {
    try {
      final docId = await IdService.getDriverDocId(widget.user.uid);
      _driverDocId = docId;

      final doc = await FirebaseFirestore.instance
          .collection('drivers')
          .doc(_driverDocId)
          .get();

      if (doc.exists && mounted) {
        final data = doc.data() as Map<String, dynamic>;
        setState(() {
          _upiIds = List<String>.from(data['upiIds'] ?? []);
          _activeUpiId = data['activeUpiId'];
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        Get.snackbar(
          'Error',
          'Failed to load UPI settings: $e',
          backgroundColor: Colors.red,
          colorText: Colors.white,
        );
      }
    }
  }

  Future<void> _addUpiId() async {
    if (!_formKey.currentState!.validate()) return;

    final newUpi = _upiController.text.trim();
    if (_upiIds.contains(newUpi)) {
      Get.snackbar(
        'Duplicate',
        'This UPI ID is already added.',
        backgroundColor: Colors.orange,
        colorText: Colors.white,
      );
      return;
    }

    setState(() => _isLoading = true);
    try {
      final updatedList = [..._upiIds, newUpi];
      // If it's the first one, make it active automatically
      final newActiveId = _activeUpiId ?? newUpi;

      await FirebaseFirestore.instance
          .collection('drivers')
          .doc(_driverDocId ?? widget.user.uid)
          .update({'upiIds': updatedList, 'activeUpiId': newActiveId});

      setState(() {
        _upiIds = updatedList;
        _activeUpiId = newActiveId;
        _upiController.clear();
        _isLoading = false;
      });

      Get.back(); // Close dialog
      Get.snackbar(
        'Success',
        'UPI ID added successfully',
        backgroundColor: Colors.green,
        colorText: Colors.white,
      );
    } catch (e) {
      setState(() => _isLoading = false);
      Get.snackbar(
        'Error',
        'Failed to add UPI ID: $e',
        backgroundColor: Colors.red,
        colorText: Colors.white,
      );
    }
  }

  Future<void> _setActive(String upiId) async {
    setState(() => _isLoading = true);
    try {
      await FirebaseFirestore.instance
          .collection('drivers')
          .doc(_driverDocId ?? widget.user.uid)
          .update({'activeUpiId': upiId});

      setState(() {
        _activeUpiId = upiId;
        _isLoading = false;
      });

      Get.snackbar(
        'Updated',
        'Active payment QR updated',
        backgroundColor: Colors.green,
        colorText: Colors.white,
      );
    } catch (e) {
      setState(() => _isLoading = false);
      Get.snackbar(
        'Error',
        'Failed to update active QR: $e',
        backgroundColor: Colors.red,
        colorText: Colors.white,
      );
    }
  }

  Future<void> _deleteUpiId(String upiId) async {
    setState(() => _isLoading = true);
    try {
      final updatedList = List<String>.from(_upiIds)..remove(upiId);
      String? newActiveId = _activeUpiId;

      if (_activeUpiId == upiId) {
        newActiveId = updatedList.isNotEmpty ? updatedList.first : null;
      }

      await FirebaseFirestore.instance
          .collection('drivers')
          .doc(_driverDocId ?? widget.user.uid)
          .update({'upiIds': updatedList, 'activeUpiId': newActiveId});

      setState(() {
        _upiIds = updatedList;
        _activeUpiId = newActiveId;
        _isLoading = false;
      });

      Get.back(); // Close dialog or whatever view
      Get.snackbar(
        'Deleted',
        'UPI ID removed',
        backgroundColor: Colors.green,
        colorText: Colors.white,
      );
    } catch (e) {
      setState(() => _isLoading = false);
      Get.snackbar(
        'Error',
        'Failed to delete UPI ID: $e',
        backgroundColor: Colors.red,
        colorText: Colors.white,
      );
    }
  }

  void _showAddDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add UPI ID'),
        content: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _upiController,
                      decoration: const InputDecoration(
                        labelText: 'UPI ID (e.g. name@bank)',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.payment),
                      ),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Please enter a UPI ID';
                        }
                        if (!value.contains('@')) {
                          return 'Invalid UPI ID format';
                        }
                        return null;
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filledTonal(
                    onPressed: _scanQrCode,
                    icon: const Icon(Icons.qr_code_scanner),
                    tooltip: "Scan QR",
                  ),
                ],
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Get.back(), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              _addUpiId();
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  Future<void> _scanQrCode() async {
    final result = await Get.to<String?>(() => const QrScannerView());
    if (result != null && result.isNotEmpty) {
      // Attempt to extract 'pa' param if it's a UPI link
      String extractedId = result;
      if (result.startsWith('upi://')) {
        try {
          final uri = Uri.parse(result);
          final pa = uri.queryParameters['pa'];
          if (pa != null && pa.isNotEmpty) {
            extractedId = pa;
          }
        } catch (e) {
          debugPrint("Error parsing UPI URI: $e");
        }
      }

      setState(() {
        _upiController.text = extractedId;
      });
    }
  }

  void _showQrDialog(String upiId) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Scan to Pay',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : Colors.black,
                ),
              ),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: QrImageView(
                  data: 'upi://pay?pa=$upiId&pn=Driver&cu=INR',
                  version: QrVersions.auto,
                  size: 250,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                upiId,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  if (_activeUpiId != upiId)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(right: 8.0),
                        child: ProButton(
                          text: 'Set Active',
                          onPressed: () {
                            Get.back();
                            _setActive(upiId);
                          },
                          // Default is primary
                        ),
                      ),
                    ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(left: 8.0),
                      child: ProButton(
                        text: 'Delete',
                        onPressed: () {
                          Get.back();
                          _deleteUpiId(upiId);
                        },
                        backgroundColor: Colors.redAccent,
                        textColor: Colors.white,
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

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      appBar: const ProAppBar(titleText: 'QR Settings'),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _upiIds.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.qr_code_scanner,
                    size: 80,
                    color: Colors.grey.shade400,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No UPI IDs added yet',
                    style: TextStyle(fontSize: 18, color: Colors.grey.shade600),
                  ),
                  const SizedBox(height: 24),
                  ProButton(text: 'Add UPI ID', onPressed: _showAddDialog),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _upiIds.length,
              itemBuilder: (context, index) {
                final upiId = _upiIds[index];
                final isActive = upiId == _activeUpiId;

                return Card(
                  elevation: 2,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: isActive
                        ? const BorderSide(color: Colors.green, width: 2)
                        : BorderSide.none,
                  ),
                  margin: const EdgeInsets.only(bottom: 12),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    leading: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: isDark
                            ? Colors.grey.shade800
                            : Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        Icons.qr_code_2,
                        color: isActive
                            ? Colors.green
                            : (isDark ? Colors.white : Colors.black87),
                      ),
                    ),
                    title: Text(
                      upiId,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: isActive ? Colors.green : null,
                      ),
                    ),
                    trailing: isActive
                        ? const ContainerTag(
                            text: 'Active',
                            color: Colors.green,
                          )
                        : null,
                    onTap: () => _showQrDialog(upiId),
                  ),
                );
              },
            ),
      floatingActionButton: _upiIds.isNotEmpty
          ? FloatingActionButton(
              onPressed: _showAddDialog,
              child: const Icon(Icons.add),
            )
          : null,
    );
  }
}

class ContainerTag extends StatelessWidget {
  final String text;
  final Color color;
  const ContainerTag({super.key, required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          color: color,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

class QrScannerView extends StatefulWidget {
  const QrScannerView({super.key});

  @override
  State<QrScannerView> createState() => _QrScannerViewState();
}

class _QrScannerViewState extends State<QrScannerView> {
  final MobileScannerController controller = MobileScannerController();
  bool _hasScanned = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan UPI QR'),
        leading: IconButton(
          onPressed: () => Get.back(),
          icon: const Icon(Icons.close),
        ),
        actions: [
          ValueListenableBuilder(
            valueListenable: controller,
            builder: (context, state, child) {
              if (state.torchState == TorchState.off) {
                return IconButton(
                  onPressed: () => controller.toggleTorch(),
                  icon: const Icon(Icons.flash_off, color: Colors.grey),
                );
              } else {
                return IconButton(
                  onPressed: () => controller.toggleTorch(),
                  icon: const Icon(Icons.flash_on, color: Colors.yellow),
                );
              }
            },
          ),
          ValueListenableBuilder(
            valueListenable: controller,
            builder: (context, state, child) {
              if (state.cameraDirection == CameraFacing.front) {
                return IconButton(
                  onPressed: () => controller.switchCamera(),
                  icon: const Icon(Icons.camera_front),
                );
              } else {
                return IconButton(
                  onPressed: () => controller.switchCamera(),
                  icon: const Icon(Icons.camera_rear),
                );
              }
            },
          ),
        ],
      ),
      body: MobileScanner(
        controller: controller,
        onDetect: (capture) {
          if (_hasScanned) return;
          final List<Barcode> barcodes = capture.barcodes;
          for (final barcode in barcodes) {
            if (barcode.rawValue != null) {
              _hasScanned = true;
              Get.back(result: barcode.rawValue);
              break;
            }
          }
        },
      ),
    );
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }
}
