import 'package:flutter/material.dart';

import '../../services/ai_assistant_service.dart';
import '../../services/transit_planner_service.dart';

/// Card displaying an individual transit route option with mode icons, ETA,
/// step-by-step expandable legs, and passenger discount fare calculations.
class RouteResultCard extends StatelessWidget {
  final TransitPlanOption route;
  final bool isSelected;
  final PassengerType passengerType;
  final VoidCallback onTap;

  const RouteResultCard({
    super.key,
    required this.route,
    required this.isSelected,
    required this.passengerType,
    required this.onTap,
  });

  IconData _getLeadingIcon() {
    if (route.transfers == 0) {
      if (route.modes.contains('jeepney')) return Icons.airport_shuttle;
      if (route.modes.contains('bus')) return Icons.directions_bus;
      if (route.modes.any((m) => m.startsWith('lrt') || m.startsWith('mrt'))) {
        return Icons.train;
      }
      return Icons.directions_walk;
    }
    return Icons.alt_route;
  }

  @override
  Widget build(BuildContext context) {
    final isDiscounted = passengerType.isDiscounted;
    final effectiveFare = route.effectiveFare(passengerType);
    final fareUpTo = route.effectiveFareUpTo(passengerType);
    final hasFareRange = route.hasFareRange(passengerType);
    // Walking-only routes have no fare, so there is no discount to show.
    final showDiscount =
        isDiscounted && route.fare > route.fareDiscounted + 0.001;
    final colorScheme = Theme.of(context).colorScheme;
    final primary = colorScheme.primary;
    final container = colorScheme.primaryContainer;

    return Semantics(
      button: true,
      label:
          '${route.title}, estimated ${route.etaMinutes} minutes, '
          '${route.fareEstimated ? 'estimated ' : ''}fare ${formatPesoPlain(effectiveFare)} pesos'
          '${hasFareRange ? ', up to ${formatPesoPlain(fareUpTo)} pesos on a modern or air-conditioned vehicle' : ''}',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: isSelected
                ? container.withValues(alpha: 0.35)
                : colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isSelected ? primary : colorScheme.outlineVariant,
              width: isSelected ? 2 : 1,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: isSelected
                      ? container
                      : colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(_getLeadingIcon(), size: 22, color: primary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          route.title,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (isSelected) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: primary,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              'Active map route',
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w600,
                                color: colorScheme.onPrimary,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${route.etaMinutes} min • ${route.transfers} transfer${route.transfers == 1 ? '' : 's'}',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                    if (route.legs.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 4,
                        runSpacing: 4,
                        children: route.legs.map((leg) {
                          return Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: leg.color.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: leg.color.withValues(alpha: 0.3),
                                width: 1,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  leg.isWalk
                                      ? Icons.directions_walk
                                      : Icons.directions_bus,
                                  size: 11,
                                  color: leg.color,
                                ),
                                const SizedBox(width: 3),
                                Text(
                                  leg.isWalk
                                      ? '${leg.minutes}m'
                                      : '${leg.modeLabel ?? 'Ride'} ${leg.routeCode ?? ''} (${leg.minutes}m)',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                    color: leg.color,
                                  ),
                                ),
                              ],
                            ),
                          );
                        }).toList(),
                      ),
                    ],
                    if (route.summary.isNotEmpty) ...[
                      const SizedBox(height: 5),
                      Text(
                        route.summary,
                        style: TextStyle(
                          fontSize: 11,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                    if (route.legs.isNotEmpty)
                      Material(
                        type: MaterialType.transparency,
                        child: ExpansionTile(
                          tilePadding: EdgeInsets.zero,
                          dense: true,
                          title: const Text(
                            'View step-by-step directions',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          children: route.legs.asMap().entries.map((entry) {
                            final index = entry.key + 1;
                            final leg = entry.value;
                            final distance = leg.meters == null
                                ? ''
                                : ' • ${(leg.meters! / 1000).toStringAsFixed(1)} km';
                            final detail = leg.isWalk
                                ? 'Walk from ${leg.from} to ${leg.to}'
                                : 'Take ${leg.modeLabel ?? 'transit'}'
                                      '${leg.routeCode == null ? '' : ' ${leg.routeCode}'} '
                                      'from ${leg.from} to ${leg.to}';
                            return ListTile(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              leading: CircleAvatar(
                                radius: 13,
                                backgroundColor: leg.color.withValues(
                                  alpha: 0.15,
                                ),
                                child: Text(
                                  '$index',
                                  style: TextStyle(color: leg.color),
                                ),
                              ),
                              title: Text(
                                detail,
                                style: const TextStyle(fontSize: 11),
                              ),
                              subtitle: Text(
                                '${leg.minutes} min$distance${leg.stops == null ? '' : ' • ${leg.stops} stops'}',
                                style: const TextStyle(fontSize: 10),
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: colorScheme.surface,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: colorScheme.outlineVariant),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      formatPeso(effectiveFare),
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: primary,
                      ),
                    ),
                    if (hasFareRange)
                      Text(
                        'up to ${formatPeso(fareUpTo)} if modern/aircon',
                        textAlign: TextAlign.end,
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w600,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    Text(
                      route.fareEstimated ? 'Estimated' : 'Per fare table',
                      style: TextStyle(
                        fontSize: 9,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                    Text(
                      'Round trip ${formatPeso(effectiveFare * 2)}',
                      style: TextStyle(
                        fontSize: 9,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                    if (showDiscount) ...[
                      Text(
                        formatPeso(route.fare),
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w500,
                          color: colorScheme.onSurfaceVariant,
                          decoration: TextDecoration.lineThrough,
                        ),
                      ),
                      const SizedBox(height: 1),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: container,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          '-${route.discountPercent}%',
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            color: primary,
                          ),
                        ),
                      ),
                    ],
                    if (showDiscount)
                      Text(
                        'Bring a valid ID',
                        style: TextStyle(
                          fontSize: 9,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    Text(
                      route.fareSource,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 9,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

