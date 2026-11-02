import 'package:flutter/material.dart';

import '../../../../shared/theme/app_colors.dart';
import '../../../../shared/utils/date_utils.dart';
import '../../domain/tracking_models.dart';

/// "Tracking history": each step of the booking with its date and time, newest on top. Collapsed by default.
class TrackingHistoryCard extends StatelessWidget {
  const TrackingHistoryCard({super.key, required this.events});
  final List<TrackingHistoryEvent> events;

  static String timeOf(DateTime t) {
    final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
    final m = t.minute.toString().padLeft(2, '0');
    return '$h:$m ${t.hour < 12 ? 'AM' : 'PM'}';
  }

  @override
  Widget build(BuildContext context) {
    if (events.isEmpty) return const SizedBox.shrink();
    final newestFirst = events.reversed.toList();
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      // A Material (not a coloured box) so the row's tap ripple is visible.
      child: Material(
        color: Colors.white,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: const BorderSide(color: Color(0xFFE3E8EE))),
        child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          key: const Key('tracking_history'),
          leading: const Icon(Icons.history_rounded, color: AppColors.navy),
          title: const Text('Tracking history', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.navy)),
          subtitle: Text('${events.length} update${events.length == 1 ? '' : 's'}', style: const TextStyle(fontSize: 12)),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          children: [
            for (var i = 0; i < newestFirst.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Column(children: [
                    Icon(Icons.circle, size: 10, color: i == 0 ? AppColors.navy : const Color(0xFFB8C2CF)),
                    if (i < newestFirst.length - 1) Container(width: 2, height: 22, color: const Color(0xFFE3E8EE)),
                  ]),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(newestFirst[i].label, style: TextStyle(fontSize: 13.5, fontWeight: i == 0 ? FontWeight.w800 : FontWeight.w600)),
                  ),
                  Text('${formatDmy(newestFirst[i].at)}  ${timeOf(newestFirst[i].at)}', style: const TextStyle(fontSize: 11.5, color: Colors.black54)),
                ]),
              ),
          ],
        ),
      ),
      ),
    );
  }
}

/// The text shared from "Share tracking": a link anyone can open to follow this booking, without signing in.
String trackingShareText(String identifier, {String? serviceName}) {
  final what = (serviceName ?? '').trim().isEmpty ? 'my SEVO booking' : 'my SEVO booking (${serviceName!.trim()})';
  return 'Follow $what live: https://sevo.co.in/tracking/${Uri.encodeComponent(identifier)}';
}
