import 'package:flutter/material.dart';

import '../tokens/spacing.dart';

/// A labelled dropdown sized to sit in a filter row.
///
/// Lived inside the collection round as a private `_HeaderDropdown`. Customer
/// Management had its own pair of dropdowns with their own styling, so the two
/// screens filtered the same book through controls that did not match.
class ManaFilterDropdown<T> extends StatelessWidget {
  final String label;
  final T value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;

  const ManaFilterDropdown({
    super.key,
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return InputDecorator(
      decoration: InputDecoration(
        labelText: label,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
            horizontal: ManaSpacing.sm, vertical: ManaSpacing.xs),
        border: const OutlineInputBorder(),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          // Without this the button sizes to the selected item's intrinsic
          // width, and a long village name -- or a wider Telugu translation --
          // overflows the Row that DropdownButton lays its value and arrow out
          // in, since that Row has nothing constraining it.
          isExpanded: true,
          isDense: true,
          items: items,
          onChanged: onChanged,
        ),
      ),
    );
  }
}

/// The one row a book is filtered through: where, in what order, and which
/// of them.
///
/// The collection round and Customer Management are the same list of the same
/// people asked two different questions, and they had drifted into two
/// different shapes -- the round put village and frequency in the app bar with
/// the sort further down beside a date, while Customer Management put village
/// and status in the body under a search box with the sort as a line of grey
/// text nobody could change.
///
/// The proportions are deliberate and not a compromise. VILLAGE takes half,
/// because it is the only one of the three whose value is a name that varies
/// in length -- "Srikalahasti — Uranduru Colony" against "All" and "Due
/// Today" -- and it is the filter that actually gets changed, since a round is
/// walked one village at a time.
class ManaFilterRow extends StatelessWidget {
  /// Half the width. Pass a [ManaFilterDropdown].
  final Widget village;

  /// A quarter each.
  final Widget sort;

  /// The third control, which differs by screen: frequency on the round,
  /// status on the customer list. Same slot, because it answers the same kind
  /// of question -- which of these people am I looking at.
  final Widget third;

  const ManaFilterRow({
    super.key,
    required this.village,
    required this.sort,
    required this.third,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(flex: 2, child: village),
        const SizedBox(width: ManaSpacing.sm),
        Expanded(child: sort),
        const SizedBox(width: ManaSpacing.sm),
        Expanded(child: third),
      ],
    );
  }
}
