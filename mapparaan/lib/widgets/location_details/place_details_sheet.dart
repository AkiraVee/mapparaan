import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart';
import 'package:uuid/uuid.dart';

import '../../services/ai_assistant_service.dart';
import '../../services/auth_service.dart';
import '../../services/commuter_preference_service.dart';
import '../../services/friend_sharing_service.dart';
import '../../services/memory_photo_compression_service.dart';
import '../../services/memory_pin_service.dart';
import '../../services/route_planner_service.dart';
import '../../services/transit_planner_service.dart';
import '../photo_sharing_dialog.dart';
import 'notice_banner.dart';
import 'passenger_type_selector.dart';
import 'preference_button.dart';
import 'route_result_card.dart';

/// Draggable sliding bottom panel for location and route details.
class PlaceDetailsSheet extends StatefulWidget {
  final String placeName;
  final String address;
  final LatLng coordinates;
  final bool isSaved;
  final bool isOfflineFallback;
  final String? serviceAreaMessage;
  final String? serverErrorMessage;
  final bool noRouteFound;
  final RoutePreference selectedPreference;
  final PassengerType passengerType;
  final DateTime? departureTime;
  final Set<String> avoidModes;
  final List<TransitPlanOption> routeOptions;
  final TransitPlanOption? selectedOption;
  final VoidCallback onSaveToggle;
  final VoidCallback onSaveCommute;
  final VoidCallback onShare;
  final VoidCallback onInviteCommuter;
  final VoidCallback onClose;
  final ValueChanged<RoutePreference> onPreferenceSelected;
  final ValueChanged<PassengerType> onPassengerTypeSelected;
  final ValueChanged<TransitPlanOption> onOptionSelected;
  final VoidCallback onReportProblem;
  final VoidCallback onDepartureTimeSelected;
  final void Function(String mode, bool selected) onAvoidModeChanged;

  const PlaceDetailsSheet({
    super.key,
    required this.placeName,
    required this.address,
    required this.coordinates,
    required this.isSaved,
    required this.isOfflineFallback,
    required this.serviceAreaMessage,
    required this.serverErrorMessage,
    required this.noRouteFound,
    required this.selectedPreference,
    required this.passengerType,
    required this.departureTime,
    required this.avoidModes,
    required this.routeOptions,
    required this.selectedOption,
    required this.onSaveToggle,
    required this.onSaveCommute,
    required this.onShare,
    required this.onInviteCommuter,
    required this.onClose,
    required this.onPreferenceSelected,
    required this.onPassengerTypeSelected,
    required this.onOptionSelected,
    required this.onReportProblem,
    required this.onDepartureTimeSelected,
    required this.onAvoidModeChanged,
  });

  @override
  State<PlaceDetailsSheet> createState() => _PlaceDetailsSheetState();
}

class _PlaceDetailsSheetState extends State<PlaceDetailsSheet> {
  double _heightFactor = 0.42;
  bool _isUploadingMemory = false;

  static const double _minFactor = 0.30;
  static const double _maxFactor = 0.90;

  Future<void> _addMemoryPhoto() async {
    if (_isUploadingMemory) return;
    setState(() => _isUploadingMemory = true);

    try {
      final source = await showModalBottomSheet<ImageSource>(
        context: context,
        builder: (context) => SafeArea(
          child: Wrap(
            children: [
              ListTile(
                leading: const Icon(Icons.photo_library_outlined),
                title: const Text('Choose from gallery'),
                onTap: () => Navigator.pop(context, ImageSource.gallery),
              ),
              ListTile(
                leading: const Icon(Icons.photo_camera_outlined),
                title: const Text('Take a photo'),
                onTap: () => Navigator.pop(context, ImageSource.camera),
              ),
            ],
          ),
        ),
      );
      if (source == null || !mounted) return;

      final pickedFile = await ImagePicker().pickImage(
        source: source,
        maxWidth: MemoryPhotoCompressionService.maxDimension.toDouble(),
        maxHeight: MemoryPhotoCompressionService.maxDimension.toDouble(),
        imageQuality: 100,
      );
      if (pickedFile == null || !mounted) return;

      final originalBytes = await pickedFile.readAsBytes();
      final imageBytes = await MemoryPhotoCompressionService.compress(
        originalBytes,
      );

      List<CommuterFriend> friends = [];
      String? friendLoadMessage;
      try {
        friends = await FriendSharingService.listFriends();
      } catch (error, stackTrace) {
        FlutterError.reportError(
          FlutterErrorDetails(
            exception: error,
            stack: stackTrace,
            context: ErrorDescription('while loading photo sharing options'),
          ),
        );
        friendLoadMessage =
            'Accepted friends could not be loaded. This photo can only be kept private right now.';
      }
      if (!mounted) return;

      final sharing = await showDialog<PhotoShareSelection>(
        context: context,
        builder: (_) => PhotoSharingDialog(
          friends: friends,
          informationMessage: friendLoadMessage,
        ),
      );
      if (sharing == null || !mounted) return;

      final pinId = await MemoryPinService.addPin(
        placeName: widget.placeName,
        address: widget.address,
        coordinates: widget.coordinates,
        fileName: 'memory-${const Uuid().v4()}.jpg',
        contentType: 'image/jpeg',
        imageBytes: imageBytes,
      );

      var sharingFailed = false;
      if (sharing.friendIds.isNotEmpty) {
        try {
          await FriendSharingService.setPhotoShares(
            photoId: pinId,
            friendIds: sharing.friendIds,
          );
        } catch (error, stackTrace) {
          sharingFailed = true;
          FlutterError.reportError(
            FlutterErrorDetails(
              exception: error,
              stack: stackTrace,
              context: ErrorDescription('while sharing a memory photo'),
            ),
          );
        }
      }

      if (mounted) {
        _showMemoryPhotoMessage(
          sharingFailed
              ? 'Photo uploaded privately. Sharing failed; you can try again from your profile.'
              : sharing.friendIds.isEmpty
              ? 'Memory photo compressed and uploaded privately.'
              : 'Memory photo shared with your selected friends.',
        );
      }
    } on FormatException catch (error) {
      if (mounted) _showMemoryPhotoMessage(error.message);
    } catch (error, stackTrace) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          context: ErrorDescription('while uploading a memory photo'),
        ),
      );
      if (mounted) {
        _showMemoryPhotoMessage(
          'Could not upload the photo. Check your connection and try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _isUploadingMemory = false);
    }
  }

  void _showMemoryPhotoMessage(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _showBudgetCalculator() async {
    final route = widget.selectedOption;
    if (route == null) {
      _showMemoryPhotoMessage('Choose a route first to calculate its budget.');
      return;
    }
    final fareController = TextEditingController(
      text: formatPesoPlain(route.effectiveFare(widget.passengerType)),
    );
    final tripsController = TextEditingController(text: '2');
    final daysController = TextEditingController(text: '22');

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          final fare = double.tryParse(fareController.text) ?? 0;
          final trips = double.tryParse(tripsController.text) ?? 0;
          final days = double.tryParse(daysController.text) ?? 0;
          final daily = fare * trips;
          final monthly = daily * days;
          return AlertDialog(
            title: const Text('Commute budget'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: fareController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'One-way fare (₱)',
                    ),
                    onChanged: (_) => setDialogState(() {}),
                  ),
                  TextField(
                    controller: tripsController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Trips per day',
                    ),
                    onChanged: (_) => setDialogState(() {}),
                  ),
                  TextField(
                    controller: daysController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Commute days per month',
                    ),
                    onChanged: (_) => setDialogState(() {}),
                  ),
                  const SizedBox(height: 16),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Daily: ₱${daily.toStringAsFixed(2)}\nMonthly: ₱${monthly.toStringAsFixed(2)}',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Done'),
              ),
            ],
          );
        },
      ),
    );
    fareController.dispose();
    tripsController.dispose();
    daysController.dispose();
  }

  Future<void> _showFareChecker() async {
    final route = widget.selectedOption;
    if (route == null) {
      _showMemoryPhotoMessage('Choose a route first to check the fare.');
      return;
    }
    final chargedController = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Fare checker'),
        content: TextField(
          controller: chargedController,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            labelText: 'What were you charged? (₱)',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final charged = double.tryParse(chargedController.text);
              if (charged == null) return;
              final expected = route.effectiveFare(widget.passengerType);
              Navigator.pop(dialogContext);
              final upTo = route.effectiveFareUpTo(widget.passengerType);
              final estimate = route.hasFareRange(widget.passengerType)
                  ? '${formatPeso(expected)} to ${formatPeso(upTo)}'
                  : formatPeso(expected);
              final result =
                  charged >= expected - 0.01 && charged <= upTo + 0.01
                  ? 'This is within the current estimate of $estimate.'
                  : charged > upTo
                  ? 'This is ${formatPeso(charged - upTo)} above the estimate of $estimate.'
                  : 'This is ${formatPeso(expected - charged)} below the estimate of $estimate.';
              ScaffoldMessenger.of(context)
                  .showSnackBar(SnackBar(content: Text(result)));
            },
            child: const Text('Check'),
          ),
        ],
      ),
    );
    chargedController.dispose();
  }

  Future<void> _showEmergencyInfo() async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Emergency information'),
        content: const Text(
          'National emergency hotline: 911\n\n'
          'Police, fire, and medical assistance: 911\n\n'
          'If you are in immediate danger, move to a staffed public area and contact local authorities.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _onDragUpdate(DragUpdateDetails details) {
    final screenHeight = MediaQuery.of(context).size.height;
    setState(() {
      _heightFactor -= details.primaryDelta! / screenHeight;
      _heightFactor = _heightFactor.clamp(_minFactor, _maxFactor);
    });
  }

  void _onDragEnd(DragEndDetails details) {
    const targets = [0.30, 0.42, 0.65, 0.90];
    var closest = targets.first;
    var minDist = (_heightFactor - closest).abs();
    for (final t in targets) {
      final d = (_heightFactor - t).abs();
      if (d < minDist) {
        minDist = d;
        closest = t;
      }
    }
    setState(() => _heightFactor = closest);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final primary = colorScheme.primary;
    final screenHeight = MediaQuery.of(context).size.height;
    final compactUi = CommuterPreferencesService.current.value.compactUi;
    const modeLabels = {
      'jeepney': 'Jeepney',
      'bus': 'Bus',
      'lrt1': 'LRT-1',
      'lrt2': 'LRT-2',
    };

    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      height:
          screenHeight *
          (compactUi ? _heightFactor.clamp(0.25, 0.55) : _heightFactor),
      child: Material(
        color: colorScheme.surface,
        elevation: 12,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            // Drag handle + title → moves WHOLE sheet
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onVerticalDragUpdate: _onDragUpdate,
              onVerticalDragEnd: _onDragEnd,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Center(
                      child: Container(
                        width: 40,
                        height: 5,
                        decoration: BoxDecoration(
                          color: Colors.grey[400],
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 8, 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            widget.placeName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: widget.isSaved
                              ? 'Remove saved place'
                              : 'Save place',
                          visualDensity: VisualDensity.compact,
                          icon: Icon(
                            widget.isSaved
                                ? Icons.bookmark
                                : Icons.bookmark_border,
                            color: widget.isSaved
                                ? primary
                                : colorScheme.onSurface,
                          ),
                          onPressed: widget.onSaveToggle,
                        ),
                        IconButton(
                          tooltip: 'Save commute shortcut',
                          visualDensity: VisualDensity.compact,
                          icon: const Icon(Icons.route_outlined),
                          onPressed: widget.onSaveCommute,
                        ),
                        IconButton(
                          tooltip: 'Share place',
                          visualDensity: VisualDensity.compact,
                          icon: Icon(Icons.share, color: colorScheme.onSurface),
                          onPressed: widget.onShare,
                        ),
                        IconButton(
                          tooltip: 'Invite a commuter',
                          visualDensity: VisualDensity.compact,
                          icon: Icon(
                            Icons.group_add_outlined,
                            color: colorScheme.onSurface,
                          ),
                          onPressed: widget.onInviteCommuter,
                        ),
                        IconButton(
                          tooltip: 'Close route details',
                          visualDensity: VisualDensity.compact,
                          icon: Icon(Icons.close, color: colorScheme.onSurface),
                          onPressed: widget.onClose,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Content scrolls independently
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                children: [
                  ValueListenableBuilder<bool>(
                    valueListenable: AuthService.isLoggedIn,
                    builder: (context, isLoggedIn, _) {
                      if (!isLoggedIn) return const SizedBox.shrink();
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: OutlinedButton.icon(
                          icon: _isUploadingMemory
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.camera_alt, size: 18),
                          label: Text(
                            _isUploadingMemory
                                ? 'Uploading photo...'
                                : 'Add Memory Photo',
                          ),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: primary,
                            side: BorderSide(color: primary),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(24),
                            ),
                          ),
                          onPressed: _isUploadingMemory
                              ? null
                              : _addMemoryPhoto,
                        ),
                      );
                    },
                  ),

                  PassengerTypeSelector(
                    selectedType: widget.passengerType,
                    onSelected: widget.onPassengerTypeSelected,
                  ),
                  const SizedBox(height: 10),

                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      OutlinedButton.icon(
                        onPressed: _showBudgetCalculator,
                        icon: const Icon(Icons.calculate_outlined, size: 17),
                        label: const Text('Budget'),
                      ),
                      OutlinedButton.icon(
                        onPressed: _showFareChecker,
                        icon: const Icon(Icons.receipt_long_outlined, size: 17),
                        label: const Text('Check fare'),
                      ),
                      OutlinedButton.icon(
                        onPressed: _showEmergencyInfo,
                        icon: const Icon(Icons.emergency_outlined, size: 17),
                        label: const Text('Emergency'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  Row(
                    children: [
                      PreferenceButton(
                        label: 'Fastest',
                        active:
                            widget.selectedPreference ==
                            RoutePreference.fastest,
                        accent: primary,
                        onPressed: () => widget.onPreferenceSelected(
                          RoutePreference.fastest,
                        ),
                      ),
                      const SizedBox(width: 8),
                      PreferenceButton(
                        label: 'Cheapest',
                        active:
                            widget.selectedPreference ==
                            RoutePreference.cheapest,
                        accent: primary,
                        onPressed: () => widget.onPreferenceSelected(
                          RoutePreference.cheapest,
                        ),
                      ),
                      const SizedBox(width: 8),
                      PreferenceButton(
                        label: 'Fewest\nTransfers',
                        active:
                            widget.selectedPreference ==
                            RoutePreference.fewestTransfers,
                        accent: primary,
                        onPressed: () => widget.onPreferenceSelected(
                          RoutePreference.fewestTransfers,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: widget.onDepartureTimeSelected,
                    icon: const Icon(Icons.schedule, size: 17),
                    label: Text(
                      widget.departureTime == null
                          ? 'Leave now'
                          : 'Depart at ${widget.departureTime!.hour.toString().padLeft(2, '0')}:${widget.departureTime!.minute.toString().padLeft(2, '0')}',
                    ),
                  ),
                  const SizedBox(height: 4),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Avoid modes (optional)',
                      style: TextStyle(
                        fontSize: 12,
                        color: colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Wrap(
                    spacing: 6,
                    children: modeLabels.entries
                        .map(
                          (entry) => FilterChip(
                            label: Text(entry.value),
                            selected: widget.avoidModes.contains(entry.key),
                            onSelected: (selected) =>
                                widget.onAvoidModeChanged(entry.key, selected),
                          ),
                        )
                        .toList(),
                  ),

                  if (widget.isOfflineFallback)
                    Container(
                      margin: const EdgeInsets.only(top: 8),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF3E0),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFFFFE0B2)),
                      ),
                      child: const Row(
                        children: [
                          Icon(
                            Icons.info_outline,
                            size: 14,
                            color: Color(0xFFE65100),
                          ),
                          SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              'Server offline: these are rough distance-based samples, not real routes. Start backend/planner/api.py for real routes.',
                              style: TextStyle(
                                fontSize: 10,
                                color: Color(0xFFBF360C),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                  if (widget.serviceAreaMessage != null)
                    NoticeBanner(
                      icon: Icons.location_off_outlined,
                      text:
                          '${widget.serviceAreaMessage} Choose a start and destination inside the City of Manila.',
                    ),
                  if (widget.serverErrorMessage != null)
                    NoticeBanner(
                      icon: Icons.error_outline,
                      text: widget.serverErrorMessage!,
                    ),
                  if (widget.noRouteFound)
                    const NoticeBanner(
                      icon: Icons.alt_route,
                      text:
                          'No transit route found for this trip. Try another departure time, or allow more modes.',
                    ),

                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: widget.onReportProblem,
                      icon: const Icon(Icons.flag_outlined, size: 16),
                      label: const Text('Report a problem'),
                    ),
                  ),

                  const SizedBox(height: 12),

                  ...widget.routeOptions.map((route) {
                    final isSelected =
                        widget.selectedOption == route ||
                        (widget.selectedOption == null &&
                            route == widget.routeOptions.first);
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: RouteResultCard(
                        route: route,
                        isSelected: isSelected,
                        passengerType: widget.passengerType,
                        onTap: () => widget.onOptionSelected(route),
                      ),
                    );
                  }),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

