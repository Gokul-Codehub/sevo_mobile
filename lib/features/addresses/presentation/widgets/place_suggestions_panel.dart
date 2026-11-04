import 'package:flutter/material.dart';

import '../../../../shared/theme/app_colors.dart';
import '../../../coverage/data/coverage_repository.dart';
import '../../domain/place_search.dart';

/// "Hosur, Tamil Nadu 635109, India" -> "Hosur, Tamil Nadu 635109" (the country adds nothing in an Indian address).
String withoutCountry(String address) => address.replaceAll(RegExp(r',\s*India$'), '').trim();

/// The suggestion list that drops down under any place text box: the same look and the same three honest states
/// everywhere a location is typed (add address, drop-off, guest location, the Home location sheet).
///
///  * results: up to 5 tappable places;
///  * no match / proxy unavailable: a short note that tells the customer the manual way still works;
///  * nothing typed yet: draws nothing at all.
class PlaceSuggestionsPanel extends StatelessWidget {
  const PlaceSuggestionsPanel({super.key, required this.search, required this.onPick, this.manualHint = 'Move the pin on the map, or type the address yourself.'});

  final PlaceSearch search;
  final ValueChanged<PlaceSuggestion> onPick;

  /// What to suggest instead when there are no suggestions (differs between a map screen and a plain form).
  final String manualHint;

  @override
  Widget build(BuildContext context) => ListenableBuilder(listenable: search, builder: (context, _) => _body());

  Widget _body() {
    const note = TextStyle(fontSize: 12, color: AppColors.textSecondary, height: 1.35);
    final Widget content;
    switch (search.status) {
      case PlaceSearchStatus.idle:
        return const SizedBox.shrink();
      case PlaceSearchStatus.loading:
        content = search.suggestions.isEmpty ? const Padding(padding: EdgeInsets.all(14), child: Text('Searching...', style: note)) : _list();
      case PlaceSearchStatus.results:
        content = _list();
      case PlaceSearchStatus.empty:
        content = Padding(padding: const EdgeInsets.all(14), child: Text('No matching places. $manualHint', style: note));
      case PlaceSearchStatus.unavailable:
        content = Padding(padding: const EdgeInsets.all(14), child: Text("Place search isn't available right now. $manualHint", style: note));
    }
    return Material(
      color: Colors.white,
      elevation: 6,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: content,
    );
  }

  Widget _list() => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final s in search.suggestions.take(5))
            ListTile(
              dense: true,
              leading: const Icon(Icons.place_outlined, color: AppColors.navy, size: 20),
              title: Text(s.main, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
              subtitle: s.secondary.isEmpty ? null : Text(s.secondary, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11.5)),
              onTap: () => onPick(s),
            ),
        ],
      );
}
