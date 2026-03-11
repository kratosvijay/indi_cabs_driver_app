import 'dart:io';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:excel/excel.dart' as excel_pkg;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:project_taxi_driver_app/widgets/pro_library.dart';

enum BatchUploadMode { driver, vehicle }

class BatchUploadScreen extends StatefulWidget {
  final BatchUploadMode mode;
  const BatchUploadScreen({super.key, required this.mode});

  @override
  State<BatchUploadScreen> createState() => _BatchUploadScreenState();
}

class _BatchUploadScreenState extends State<BatchUploadScreen> {
  bool _isLoading = false;
  List<Map<String, dynamic>> _parsedData = [];
  String? _fileName;

  // Expected Headers
  List<String> get _requiredHeaders {
    if (widget.mode == BatchUploadMode.driver) {
      return [
        'Driver Name',
        'Phone',
        'Email',
        'License Number',
        'Aadhar Number',
      ];
    } else {
      return [
        'Vehicle Plate',
        'Vehicle Model',
        'Vehicle Brand',
        'Vehicle Type',
        'Color',
        'Fuel Type',
      ];
    }
  }

  Future<void> _pickAndParseFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx'],
        allowMultiple: false,
      );

      if (result == null || result.files.isEmpty) return;

      final file = File(result.files.single.path!);
      final bytes = await file.readAsBytes();
      final excel = excel_pkg.Excel.decodeBytes(bytes);

      if (excel.tables.isEmpty) {
        Get.snackbar(
          "Error",
          "No tables found in Excel file",
          backgroundColor: Colors.red,
          colorText: Colors.white,
        );
        return;
      }

      final sheet = excel.tables.keys.first;
      final table = excel.tables[sheet];

      if (table == null || table.rows.isEmpty) {
        Get.snackbar(
          "Error",
          "Excel sheet is empty",
          backgroundColor: Colors.red,
          colorText: Colors.white,
        );
        return;
      }

      // Check Headers
      final headers = table.rows.first
          .map((e) => e?.value?.toString().trim() ?? '')
          .toList();

      // Validation
      final primaryKey = widget.mode == BatchUploadMode.driver
          ? 'Email'
          : 'Vehicle Plate';

      if (!headers.contains(primaryKey)) {
        Get.snackbar(
          "Error",
          "Invalid Format. Header '$primaryKey' not found.",
          backgroundColor: Colors.red,
          colorText: Colors.white,
        );
        return;
      }

      List<Map<String, dynamic>> items = [];

      for (int i = 1; i < table.rows.length; i++) {
        final row = table.rows[i];
        if (row.isEmpty) continue;

        // Helper to safely get cell value
        String getVal(String headerName) {
          final index = headers.indexOf(headerName);
          if (index == -1 || index >= row.length) return '';
          return row[index]?.value?.toString().trim() ?? '';
        }

        if (widget.mode == BatchUploadMode.driver) {
          final email = getVal('Email');
          if (email.isEmpty) continue;
          items.add({
            'name': getVal('Driver Name'),
            'phone': getVal('Phone'),
            'email': email,
            'licenseNumber': getVal('License Number'),
            'aadharNumber': getVal('Aadhar Number'),
          });
        } else {
          final plate = getVal('Vehicle Plate');
          if (plate.isEmpty) continue;
          items.add({
            'vehiclePlate': plate,
            'vehicleModel': getVal('Vehicle Model'),
            'vehicleBrand': getVal('Vehicle Brand'),
            'vehicleType': getVal('Vehicle Type'),
            'color': getVal('Color'),
            'fuelType': getVal('Fuel Type'),
          });
        }
      }

      setState(() {
        _fileName = result.files.single.name;
        _parsedData = items;
      });
    } catch (e) {
      Get.snackbar(
        "Error",
        "Failed to parse file: $e",
        backgroundColor: Colors.red,
        colorText: Colors.white,
      );
    }
  }

  Future<void> _uploadBatch() async {
    if (_parsedData.isEmpty) return;

    setState(() => _isLoading = true);

    try {
      final HttpsCallable callable = FirebaseFunctions.instanceFor(
        region: 'asia-south1',
      ).httpsCallable('batchOnboard');

      final result = await callable.call(<String, dynamic>{
        'type': widget.mode == BatchUploadMode.driver ? 'driver' : 'vehicle',
        'data': _parsedData,
      });

      final data = result.data as Map<dynamic, dynamic>;
      final successCount = data['success'] ?? 0;
      final failedCount = data['failed'] ?? 0;
      final errors = List<String>.from(data['errors'] ?? []);

      _showResultDialog(successCount, failedCount, errors);
    } catch (e) {
      Get.snackbar(
        "Upload Failed",
        e.toString(),
        backgroundColor: Colors.red,
        colorText: Colors.white,
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _showResultDialog(int success, int failed, List<String> errors) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Batch Process Result"),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                "Successfully Added: $success",
                style: const TextStyle(
                  color: Colors.green,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                "Failed: $failed",
                style: const TextStyle(
                  color: Colors.red,
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (errors.isNotEmpty) ...[
                const SizedBox(height: 16),
                const Text(
                  "Errors:",
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                ...errors.map(
                  (e) => Text(
                    "• $e",
                    style: const TextStyle(
                      fontSize: 12,
                      color: Colors.redAccent,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Get.back();
              setState(() {
                _parsedData = [];
                _fileName = null;
              });
            },
            child: const Text("Close"),
          ),
        ],
      ),
    );
  }

  Future<void> _downloadTemplate() async {
    // 1. Request Permission
    if (Platform.isAndroid) {
      var status = await Permission.storage.status;
      if (!status.isGranted) {
        await Permission.storage.request();
      }
    }

    // 2. Create Excel
    var excel = excel_pkg.Excel.createExcel();
    var sheetName = excel.getDefaultSheet() ?? 'Sheet1';
    var sheet = excel[sheetName];

    // Add headers based on mode
    final headers = _requiredHeaders;
    for (int i = 0; i < headers.length; i++) {
      var cell = sheet.cell(
        excel_pkg.CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0),
      );
      cell.value = excel_pkg.TextCellValue(headers[i]);
      cell.cellStyle = excel_pkg.CellStyle(
        bold: true,
        horizontalAlign: excel_pkg.HorizontalAlign.Center,
      );
    }

    // 3. Save File
    try {
      Directory? directory;
      if (Platform.isAndroid) {
        directory = Directory('/storage/emulated/0/Download');
        if (!await directory.exists()) {
          directory = await getExternalStorageDirectory();
        }
      } else {
        directory = await getApplicationDocumentsDirectory();
      }

      if (directory != null) {
        if (!await directory.exists()) {
          await directory.create(recursive: true);
        }

        final prefix = widget.mode == BatchUploadMode.driver
            ? 'driver'
            : 'vehicle';
        final fileName =
            "${prefix}_upload_template_${DateTime.now().millisecondsSinceEpoch}.xlsx";
        final path = "${directory.path}/$fileName";
        final file = File(path);

        final fileBytes = excel.save();
        if (fileBytes != null) {
          await file.writeAsBytes(fileBytes);

          Get.snackbar(
            "Download Success",
            "Template saved to: $path",
            backgroundColor: Colors.green,
            colorText: Colors.white,
            duration: const Duration(seconds: 5),
            snackPosition: SnackPosition.BOTTOM,
            margin: const EdgeInsets.all(16),
          );
        }
      }
    } catch (e) {
      Get.snackbar(
        "Download Failed",
        "Could not save file: $e",
        backgroundColor: Colors.red,
        colorText: Colors.white,
        duration: const Duration(seconds: 5),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.mode == BatchUploadMode.driver
        ? "Batch Driver Upload"
        : "Batch Vehicle Upload";

    return Scaffold(
      appBar: ProAppBar(titleText: title),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            // Header Card
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: Theme.of(context).dividerColor.withValues(alpha: 0.1),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                children: [
                  Icon(
                    widget.mode == BatchUploadMode.driver
                        ? Icons.person_add_alt_1_outlined
                        : Icons.directions_car_filled_outlined,
                    size: 48,
                    color: Theme.of(context).primaryColor,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    "Upload ${widget.mode == BatchUploadMode.driver ? 'Driver' : 'Vehicle'} Data",
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).textTheme.titleLarge?.color,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    "Supported format: .xlsx",
                    style: TextStyle(
                      color: Theme.of(
                        context,
                      ).textTheme.bodyMedium?.color?.withValues(alpha: 0.7),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      OutlinedButton.icon(
                        onPressed: _downloadTemplate,
                        icon: const Icon(Icons.download),
                        label: const Text("Template Info"),
                        style: OutlinedButton.styleFrom(
                          foregroundColor:
                              Theme.of(context).brightness == Brightness.dark
                              ? Colors.white
                              : Theme.of(context).primaryColor,
                          side: BorderSide(
                            color:
                                Theme.of(context).brightness == Brightness.dark
                                ? Colors.white54
                                : Theme.of(
                                    context,
                                  ).primaryColor.withValues(alpha: 0.5),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      ElevatedButton.icon(
                        onPressed: _isLoading ? null : _pickAndParseFile,
                        icon: const Icon(Icons.folder_open),
                        label: const Text("Select File"),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Theme.of(context).primaryColor,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // Results Preview
            if (_fileName != null) ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    "File: $_fileName",
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  Text("${_parsedData.length} Items found"),
                ],
              ),
              const Divider(),
              Expanded(
                child: ListView.builder(
                  itemCount: _parsedData.length,
                  itemBuilder: (context, index) {
                    final d = _parsedData[index];
                    String titleText = "";
                    String subtitleText = "";

                    if (widget.mode == BatchUploadMode.driver) {
                      titleText = d['name'] ?? 'No Name';
                      subtitleText = "${d['email']} • ${d['phone']}";
                    } else {
                      titleText = d['vehiclePlate'] ?? 'No Plate';
                      subtitleText =
                          "${d['vehicleModel']} • ${d['vehicleBrand']} • ${d['vehicleType']}";
                    }

                    return ListTile(
                      dense: true,
                      leading: CircleAvatar(child: Text("${index + 1}")),
                      title: Text(titleText),
                      subtitle: Text(subtitleText),
                      trailing: const Icon(
                        Icons.check_circle_outline,
                        color: Colors.green,
                        size: 16,
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _uploadBatch,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : const Text(
                          "PROCESS BATCH",
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                ),
              ),
            ] else ...[
              const Expanded(
                child: Center(
                  child: Text("Select an Excel file to preview data"),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
