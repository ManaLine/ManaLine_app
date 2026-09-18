import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../design/components/mana_app_bar.dart';
import '../design/components/mana_text.dart';
import '../design/tokens/colors.dart';
import '../design/tokens/spacing.dart';
import '../design/tokens/typography.dart';
import 'network_error_handler.dart';
import 'translation_service.dart';
import 'village_merge_state.dart';

/// Two entries for one village, made into one.
///
/// WHY THE OWNER ENDS UP HERE. A village gets typed before the directory has
/// it, or typed twice with two spellings, and its customers split across two
/// names: the round shows both, the village book shows both, and neither one
/// is the whole village. On this book it is 'Panagal' and 'Panagallu (Rural)',
/// same PIN, same mandal, 2 customers on one and 19 on the other.
///
/// WHAT IT PROMISES, in the Owner's words: "their loans, collections and
/// account history follow silently - just their address village name changes
/// to the new one, remaining all stays." That is checkable rather than
/// hopeful -- exactly three tables reference a village and none of them is
/// money -- and it is checked, in `village_merge_test.dart` and against the
/// live book before this shipped: 91 customers, 0 balances moved, 0 collecting
/// agents moved.
///
/// THE SCREEN'S ONE JOB IS THE DIRECTION. Which of the two names survives is
/// the only real decision here, and it is not obvious: the server suggests the
/// row more people already live on, and the Owner knows which name the village
/// is actually called by. So the two sides are shown as a pair with a Swap
/// between them, not as a from-and-to.
class ManaVillageMergeScreen extends ConsumerStatefulWidget {
  final String businessId;
  const ManaVillageMergeScreen({super.key, required this.businessId});

  @override
  ConsumerState<ManaVillageMergeScreen> createState() =>
      _ManaVillageMergeScreenState();
}

class _ManaVillageMergeScreenState
    extends ConsumerState<ManaVillageMergeScreen> {
  List<ManaVillageDuplicate> _pairs = const [];
  bool _loading = true;
  String? _busyId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final rows = await NetworkErrorHandler.run(
      context,
      () => ref.read(villageMergeApiServiceProvider).candidates(widget.businessId),
    );
    if (!mounted) return;
    setState(() {
      _pairs = rows ?? const [];
      _loading = false;
    });
  }

  /// Turn the pair around and ask the server again.
  ///
  /// The refusal is per direction, so a swapped pair carries no answer until
  /// one is fetched -- showing the old reason against the new direction would
  /// be quoting a sentence about the wrong villages.
  Future<void> _swap(int i) async {
    final before = _pairs[i];
    final swapped = before.swapped();
    setState(() {
      _pairs = [..._pairs]..[i] = swapped;
      _busyId = swapped.dropId;
    });
    final reason = await NetworkErrorHandler.run(
      context,
      () => ref.read(villageMergeApiServiceProvider).blockedReason(
            businessId: widget.businessId,
            loserId: swapped.dropId,
            survivorId: swapped.keepId,
          ),
    );
    if (!mounted) return;

    // THE SWAP IS UNDONE WHEN THE CHECK COULD NOT BE MADE. A null here means
    // the call failed -- the handler has already said so -- and the screen
    // must not be left showing a direction whose answer it never got, because
    // a pair with no reason against it draws the Merge button.
    if (reason == null) {
      setState(() {
        _busyId = null;
        _pairs = [..._pairs]..[i] = before;
      });
      return;
    }

    setState(() {
      _busyId = null;
      _pairs = [..._pairs]
        ..[i] = ManaVillageDuplicate(
          keepId: swapped.keepId,
          keepName: swapped.keepName,
          keepMandal: swapped.keepMandal,
          keepDistrict: swapped.keepDistrict,
          keepPeople: swapped.keepPeople,
          dropId: swapped.dropId,
          dropName: swapped.dropName,
          dropMandal: swapped.dropMandal,
          dropDistrict: swapped.dropDistrict,
          dropPeople: swapped.dropPeople,
          pinCode: swapped.pinCode,
          blockedReason: reason.isEmpty ? null : reason,
        );
    });
  }

  Future<void> _merge(ManaVillageDuplicate p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: ManaText.raw(ref.t('merge_confirm_question')),
        content: ManaText.raw(ref
            .t('merge_confirm_note')
            .replaceAll('{count}', '${p.dropPeople}')
            .replaceAll('{from}', p.dropName)
            .replaceAll('{to}', p.keepName)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(c).pop(false),
            child: ManaText.raw(ref.t('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(c).pop(true),
            child: ManaText.raw(ref.t('merge_villages')),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() => _busyId = p.dropId);
    final result = await NetworkErrorHandler.run(
      context,
      () => ref.read(villageMergeApiServiceProvider).merge(
            businessId: widget.businessId,
            loserId: p.dropId,
            survivorId: p.keepId,
          ),
    );
    if (!mounted) return;
    setState(() => _busyId = null);
    if (result == null) return;

    // The server's own count, not the one this screen was showing. It is what
    // actually moved, and it includes past addresses the list never counted.
    final moved = (result['addresses_moved'] as num?)?.toInt() ?? 0;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: ManaText.raw(ref
          .t('merged_note')
          .replaceAll('{count}', '$moved')
          .replaceAll('{to}', '${result['kept']}')),
    ));
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: ManaAppBar(title: ref.t('merge_villages')),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(ManaSpacing.lg),
                children: [
                  ManaText.raw(ref.t('merge_villages_note'),
                      style: ManaType.note),
                  const SizedBox(height: ManaSpacing.md),
                  if (_pairs.isEmpty)
                    ManaText.raw(ref.t('no_duplicate_villages'),
                        style: ManaType.secondary)
                  else
                    ...List.generate(
                        _pairs.length, (i) => _pairCard(_pairs[i], i)),
                ],
              ),
      ),
    );
  }

  Widget _pairCard(ManaVillageDuplicate p, int i) {
    final busy = _busyId == p.dropId;
    return Card(
      margin: const EdgeInsets.only(bottom: ManaSpacing.md),
      child: Padding(
        padding: const EdgeInsets.all(ManaSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _side(ref.t('merge_keeps'), p.keepName, p.keepMandal,
                p.keepDistrict, p.keepPeople),
            const SizedBox(height: ManaSpacing.sm),
            // Wrap, not Row: two Telugu labels and a button do not share a
            // 360dp line at a 2.0x text scale.
            Wrap(
              spacing: ManaSpacing.sm,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Icon(Icons.arrow_downward,
                    size: 18, color: ManaColors.textSecondary),
                TextButton.icon(
                  onPressed: busy ? null : () => _swap(i),
                  icon: const Icon(Icons.swap_vert, size: 18),
                  label: ManaText.raw(ref.t('merge_swap')),
                ),
              ],
            ),
            const SizedBox(height: ManaSpacing.sm),
            _side(ref.t('merge_drops'), p.dropName, p.dropMandal,
                p.dropDistrict, p.dropPeople),
            const SizedBox(height: ManaSpacing.md),
            if (p.isBlocked) ...[
              // SAID IN FULL, not reduced to a disabled button. The refusal is
              // something the Owner can act on -- put both villages in the
              // same area -- and a greyed-out control with no sentence beside
              // it reads as a broken screen.
              ManaText.raw(ref.t('merge_blocked'),
                  style: ManaType.smallStrong),
              const SizedBox(height: 2),
              ManaText.raw(p.blockedReason!, style: ManaType.note),
            ] else
              FilledButton(
                onPressed: busy ? null : () => _merge(p),
                child: busy
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : ManaText.raw(ref.t('merge_villages')),
              ),
          ],
        ),
      ),
    );
  }

  Widget _side(String label, String name, String mandal, String district,
          int people) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ManaText.raw(label, style: ManaType.fine),
          ManaText.raw(name, style: ManaType.smallStrong),
          ManaText.raw(
            [mandal, district].where((s) => s.isNotEmpty).join(', '),
            style: ManaType.fine,
          ),
          ManaText.raw(
            ref.t('people_here').replaceAll('{count}', '$people'),
            style: ManaType.note,
          ),
        ],
      );
}
