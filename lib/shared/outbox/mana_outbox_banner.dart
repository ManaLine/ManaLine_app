import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../design/components/mana_text.dart';
import '../../design/tokens/colors.dart';
import '../../design/tokens/spacing.dart';
import '../../design/tokens/typography.dart';
import '../translation_service.dart';
import 'mana_outbox.dart';
import 'mana_outbox_provider.dart';

/// Says, on the collection round itself, that something has not gone yet.
///
/// The way in to /outbox. A queue with no entry point is a queue nobody opens,
/// and an agent who cannot see that four collections are still on the phone
/// has no reason to go looking.
///
/// PLACED ON THE SHARED ROUND VIEW, so the Owner's OW-006 and the Agent's
/// AG-002 both get it from one widget. Two copies of this would drift, and the
/// thing they would drift about is whether somebody's money has been recorded.
///
/// ABSENT WHEN THE QUEUE IS EMPTY, which is nearly always. A permanent "0
/// waiting" chip is noise on a screen an agent uses at a doorstep in the sun.
class ManaOutboxBanner extends ConsumerStatefulWidget {
  const ManaOutboxBanner({super.key});

  @override
  ConsumerState<ManaOutboxBanner> createState() => _ManaOutboxBannerState();
}

class _ManaOutboxBannerState extends ConsumerState<ManaOutboxBanner> {
  List<ManaOutboxEntry> _pending = const [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    try {
      final pending = await ref.read(manaOutboxProvider).pending();
      if (mounted) setState(() => _pending = pending);
    } catch (_) {
      // The outbox may have failed to open -- see manaOpenOutbox, which is
      // deliberately non-fatal. A banner is the last thing that should take a
      // collection screen down with it.
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_pending.isEmpty) return const SizedBox.shrink();

    // A refusal needs a person; waiting does not. The two must not look the
    // same, or the one that needs attention gets none.
    final refused =
        _pending.where((e) => e.state == ManaOutboxState.refused).length;
    final bad = refused > 0;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
          ManaSpacing.lg, ManaSpacing.sm, ManaSpacing.lg, 0),
      child: Material(
        color: bad
            ? ManaColors.statusBad.withValues(alpha: 0.10)
            : ManaColors.statusWarn.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => context.push('/outbox').then((_) => _load()),
          child: Padding(
            padding: const EdgeInsets.all(ManaSpacing.md),
            child: Row(
              children: [
                Icon(bad ? Icons.error_outline : Icons.schedule,
                    size: 18,
                    color:
                        bad ? ManaColors.statusBad : ManaColors.statusWarn),
                const SizedBox(width: ManaSpacing.sm),
                Expanded(
                  child: ManaText.raw(
                    ref
                        .t(bad
                            ? 'outbox_banner_refused_note'
                            : 'outbox_banner_waiting_note')
                        .replaceAll('{count}', '${bad ? refused : _pending.length}'),
                    style: ManaType.small,
                  ),
                ),
                const Icon(Icons.chevron_right, size: 18),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
