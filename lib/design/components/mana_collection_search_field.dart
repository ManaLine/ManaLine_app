import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/translation_service.dart';
import '../tokens/spacing.dart';

/// The search box that drops out of a collection screen's app bar.
///
/// Shared by OW-006 and AG-002 rather than written twice: the two screens
/// render the same rows from the same model, and a search that behaved
/// differently depending on whether an Owner or an Agent opened it would be a
/// bug waiting to be reported as one.
///
/// It implements PreferredSizeWidget so it can sit in `AppBar.bottom`, which
/// is what pins it under the title while the list scrolls beneath.
class ManaCollectionSearchField extends ConsumerStatefulWidget
    implements PreferredSizeWidget {
  final ValueChanged<String> onChanged;

  const ManaCollectionSearchField({super.key, required this.onChanged});

  @override
  Size get preferredSize => const Size.fromHeight(64);

  @override
  ConsumerState<ManaCollectionSearchField> createState() =>
      _ManaCollectionSearchFieldState();
}

class _ManaCollectionSearchFieldState
    extends ConsumerState<ManaCollectionSearchField> {
  final _controller = TextEditingController();
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    // The box only exists because someone tapped the search icon, so the
    // keyboard should already be up by the time they look down at it.
    WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          ManaSpacing.lg, 0, ManaSpacing.lg, ManaSpacing.sm),
      child: TextField(
        controller: _controller,
        focusNode: _focus,
        textInputAction: TextInputAction.search,
        // Filters as you type. The list is already in memory — the day's due
        // rows were loaded before this box existed — so there is no round trip
        // to debounce and no reason to make anyone press a button.
        onChanged: widget.onChanged,
        decoration: InputDecoration(
          hintText: ref.t('search_by_name_mlid_phone'),
          isDense: true,
          filled: true,
          prefixIcon: const Icon(Icons.search),
          suffixIcon: ValueListenableBuilder<TextEditingValue>(
            valueListenable: _controller,
            builder: (context, value, _) => value.text.isEmpty
                ? const SizedBox.shrink()
                : IconButton(
                    icon: const Icon(Icons.clear),
                    tooltip: ref.t('clear_all'),
                    onPressed: () {
                      _controller.clear();
                      widget.onChanged('');
                    },
                  ),
          ),
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }
}
