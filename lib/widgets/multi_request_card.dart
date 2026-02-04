import 'dart:async';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:project_taxi_driver_app/services/request_queue_service.dart';
import 'package:project_taxi_driver_app/services/location_service.dart';
import 'package:project_taxi_driver_app/utils/app_colors.dart';
import 'package:project_taxi_driver_app/widgets/ride_request.dart';

class MultiRequestCard extends StatefulWidget {
  final Function(RideRequest request) onAccept;
  final Function(RideRequest request) onReject;

  const MultiRequestCard({
    super.key,
    required this.onAccept,
    required this.onReject,
  });

  @override
  State<MultiRequestCard> createState() => _MultiRequestCardState();
}

class _MultiRequestCardState extends State<MultiRequestCard> {
  final PageController _pageController = PageController();
  final RequestQueueService _queueService = RequestQueueService.instance;

  int _currentPage = 0;
  Timer? _timer;
  double _progressValue = 1.0;

  // Translation cache
  final Map<String, Map<String, String?>> _translationCache = {};
  final Set<String> _translatingIds = {};

  @override
  void initState() {
    super.initState();
    _startTimer();
    _pageController.addListener(() {
      if (_pageController.page != null) {
        setState(() {
          _currentPage = _pageController.page!.round();
        });
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  void _startTimer() {
    _progressValue = 1.0;
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(milliseconds: 50), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        _progressValue -= 0.01; // 5 seconds total
      });
      if (_progressValue <= 0) {
        timer.cancel();
        _autoRejectCurrent();
      }
    });
  }

  void _autoRejectCurrent() {
    final requests = _queueService.getAllRequests();
    if (requests.isNotEmpty && _currentPage < requests.length) {
      widget.onReject(requests[_currentPage]);
    }
  }

  Future<void> _translateAddress(RideRequest request) async {
    if (_translatingIds.contains(request.rideId)) return;
    if (_translationCache.containsKey(request.rideId)) return;

    final langCode = Get.locale?.languageCode ?? 'en';
    if (langCode == 'en') return;

    _translatingIds.add(request.rideId);

    try {
      final results = await Future.wait([
        LocationService().getLocalizedAddress(request.pickupLocation, langCode),
        LocationService().getLocalizedAddress(request.dropoffLocation, langCode),
      ]);

      if (mounted) {
        setState(() {
          _translationCache[request.rideId] = {
            'pickupAddress': results[0],
            'pickupTitle': results[0] != null ? RideRequest.extractTitle(results[0]!) : null,
            'dropoffAddress': results[1],
            'dropoffTitle': results[1] != null ? RideRequest.extractTitle(results[1]!) : null,
          };
          _translatingIds.remove(request.rideId);
        });
      }
    } catch (e) {
      debugPrint('Translation error: $e');
      _translatingIds.remove(request.rideId);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final requests = _queueService.getAllRequests();

      if (requests.isEmpty) {
        return const SizedBox.shrink();
      }

      // Start translating current and next request
      if (_currentPage < requests.length) {
        _translateAddress(requests[_currentPage]);
        if (_currentPage + 1 < requests.length) {
          _translateAddress(requests[_currentPage + 1]);
        }
      }

      return Positioned(
        bottom: 0,
        left: 0,
        right: 0,
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.primary,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            boxShadow: [
              BoxShadow(
                blurRadius: 15,
                color: Colors.black.withValues(alpha: 0.3),
              ),
            ],
          ),
          child: Stack(
            children: [
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Header with counter and sort button
                  _buildHeader(requests.length),

                  // Page view for requests
                  SizedBox(
                    height: 450,
                    child: PageView.builder(
                      controller: _pageController,
                      itemCount: requests.length,
                      onPageChanged: (index) {
                        setState(() {
                          _currentPage = index;
                          _startTimer(); // Restart timer on page change
                        });
                      },
                      itemBuilder: (context, index) {
                        return _buildRequestContent(requests[index]);
                      },
                    ),
                  ),

                  // Page indicator
                  if (requests.length > 1) _buildPageIndicator(requests.length),

                  // Action buttons
                  _buildActionButtons(requests),
                ],
              ),

              // Close button
              Positioned(
                top: 8,
                right: 8,
                child: IconButton(
                  icon: const Icon(Icons.close, color: Colors.white),
                  onPressed: () {
                    if (_currentPage < requests.length) {
                      widget.onReject(requests[_currentPage]);
                    }
                  },
                ),
              ),

              // Progress bar
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: ClipRRect(
                  borderRadius: const BorderRadius.vertical(
                    bottom: Radius.circular(20),
                  ),
                  child: LinearProgressIndicator(
                    value: _progressValue,
                    backgroundColor: Colors.blue.shade300,
                    valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
                    minHeight: 6,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    });
  }

  Widget _buildHeader(int count) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Counter
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.layers, color: Colors.white, size: 18),
                const SizedBox(width: 6),
                Text(
                  '${_currentPage + 1}/$count ${'requests'.tr}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),

          // Sort button
          PopupMenuButton<SortType>(
            icon: const Icon(Icons.sort, color: Colors.white),
            onSelected: (type) {
              _queueService.changeSortType(type);
              _pageController.jumpToPage(0);
              _startTimer();
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: SortType.priceHighToLow,
                child: Row(
                  children: [
                    Icon(
                      _queueService.currentSortType.value == SortType.priceHighToLow
                          ? Icons.check_circle
                          : Icons.circle_outlined,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Text(_queueService.getSortTypeName(SortType.priceHighToLow)),
                  ],
                ),
              ),
              PopupMenuItem(
                value: SortType.distanceLowToHigh,
                child: Row(
                  children: [
                    Icon(
                      _queueService.currentSortType.value == SortType.distanceLowToHigh
                          ? Icons.check_circle
                          : Icons.circle_outlined,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Text(_queueService.getSortTypeName(SortType.distanceLowToHigh)),
                  ],
                ),
              ),
              PopupMenuItem(
                value: SortType.timeNewest,
                child: Row(
                  children: [
                    Icon(
                      _queueService.currentSortType.value == SortType.timeNewest
                          ? Icons.check_circle
                          : Icons.circle_outlined,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Text(_queueService.getSortTypeName(SortType.timeNewest)),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRequestContent(RideRequest request) {
    final translations = _translationCache[request.rideId];
    final isTranslating = _translatingIds.contains(request.rideId);

    final pickupTitle = translations?['pickupTitle'] ?? request.pickupTitle;
    final pickupAddress = translations?['pickupAddress'] ?? request.pickupFullAddress;
    final dropoffTitle = translations?['dropoffTitle'] ?? request.dropoffTitle;
    final dropoffAddress = translations?['dropoffAddress'] ?? request.dropoffFullAddress;

    String headerText = _getPaymentHeaderText(request);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Center(
            child: Text(
              headerText,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.white.withValues(alpha: 0.9),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Pickup
          if (isTranslating)
            _buildShimmerRow()
          else
            _buildDetailRow(
              Icons.location_on,
              pickupTitle,
              pickupAddress,
              request.rideType == 'rental'
                  ? "Rental"
                  : "${request.driverDistance.toStringAsFixed(1)} ${'kmAway'.tr}",
            ),

          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8.0, horizontal: 12.0),
            child: Icon(Icons.more_vert, color: Colors.white54, size: 20),
          ),

          // Dropoff
          if (isTranslating)
            _buildShimmerRow()
          else
            _buildDetailRow(
              Icons.flag,
              dropoffTitle,
              dropoffAddress,
              request.rideType == 'rental'
                  ? ""
                  : "${request.rideDistance.toStringAsFixed(1)} ${'kmRide'.tr}",
            ),

          if (request.stops.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.add_location_alt_outlined,
                    color: Colors.yellowAccent,
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      "${request.stops.length} ${'stopsAdded'.tr}",
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],

          const Divider(height: 32, color: Colors.white54),

          // Fare
          Center(
            child: Column(
              children: [
                Text(
                  "₹${request.rideFare.toStringAsFixed(2)}",
                  style: const TextStyle(
                    fontSize: 36,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                if (request.tip != null && request.tip! > 0) ...[
                  const SizedBox(height: 4),
                  Text(
                    "+ ₹${request.tip!.toStringAsFixed(0)} Tip Included",
                    style: const TextStyle(
                      color: Colors.greenAccent,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(
    IconData icon,
    String title,
    String fullAddress,
    String distanceInfo,
  ) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: Colors.white, size: 28),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                  fontSize: 18,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                fullAddress,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.9),
                  fontSize: 14,
                ),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
              if (distanceInfo.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  distanceInfo,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildShimmerRow() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                height: 18,
                width: 120,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(height: 8),
              Container(
                height: 14,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPageIndicator(int count) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(count, (index) {
          return Container(
            margin: const EdgeInsets.symmetric(horizontal: 4),
            width: _currentPage == index ? 24 : 8,
            height: 8,
            decoration: BoxDecoration(
              color: _currentPage == index
                  ? Colors.white
                  : Colors.white.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(4),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildActionButtons(List<RideRequest> requests) {
    if (_currentPage >= requests.length) return const SizedBox.shrink();

    final currentRequest = requests[_currentPage];

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      child: Row(
        children: [
          Expanded(
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.grey.shade800,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: () => widget.onReject(currentRequest),
              child: Text(
                'Pass',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: () => widget.onAccept(currentRequest),
              child: Text(
                'Accept',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _getPaymentHeaderText(RideRequest request) {
    if (request.rideType == 'rental') {
      return "${request.vehicleClass} ${'rideHeader'.tr}";
    }

    final method = request.paymentMethod;
    final walletUsed = request.paidByWallet ?? 0.0;

    if (walletUsed > 0 || method == 'Cash + Wallet') {
      return "cashPlusWallet".tr;
    }
    if (method.toLowerCase() == 'cash') {
      return "cashPayment".tr;
    }
    return "digitalPayment".tr;
  }
}
