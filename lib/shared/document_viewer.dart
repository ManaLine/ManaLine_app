import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'widgets/confirm_delete_dialog.dart';
import 'soft_delete_service.dart';
import 'stored_file.dart';
import '../design/tokens/colors.dart';
import '../design/tokens/typography.dart';
import '../design/tokens/spacing.dart';
import '../design/components/mana_app_bar.dart';
import '../design/components/mana_text.dart';

/// One row from customer_documents/agent_documents — both tables share
/// the exact same shape (document_type/file_url/uploaded_at), just keyed
/// on a different owning id, so one model covers both.
class DocumentSummary {
  final String documentType;
  final String fileUrl;
  final DateTime uploadedAt;

  /// customer_documents.document_id, when this row came from there.
  ///
  /// Null for AGENT documents: agent_documents is not one of the
  /// soft-deletable tables, so there is no id to delete by and the delete
  /// action is not offered. Nullable rather than a second model because the
  /// only difference between the two sources is whether this exists.
  final String? documentId;

  DocumentSummary({
    required this.documentType,
    required this.fileUrl,
    required this.uploadedAt,
    this.documentId,
  });
}

/// Reusable "Documents" tab: shows one row per expected document type,
/// with a real uploaded file if one exists, and taps into a simple
/// full-screen viewer. Used by both OW-002 (Agent) and OW-004 (Customer)
/// Documents tabs — previously each was a static list of labels with
/// `onTap: () {}`, so tapping any row (even ones with a real uploaded
/// file sitting in Storage) did nothing.
class DocumentsListView extends ConsumerStatefulWidget {
  final List<String> expectedTypes;
  final Future<List<DocumentSummary>> Function() fetchDocuments;
  const DocumentsListView({super.key, required this.expectedTypes, required this.fetchDocuments});

  @override
  ConsumerState<DocumentsListView> createState() => _DocumentsListViewState();
}

class _DocumentsListViewState extends ConsumerState<DocumentsListView> {
  late Future<List<DocumentSummary>> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.fetchDocuments();
  }

  /// A document carries no money, so no balance moves. Reloads the future
  /// afterwards so the row falls back to "Not uploaded yet".
  Future<void> _deleteDocument(DocumentSummary doc, String label) async {
    final deleted = await ConfirmDeleteDialog.show(
      context,
      entity: DeletableEntity.customerDocument,
      recordId: doc.documentId!,
      description: '$label — uploaded ${doc.uploadedAt.toIso8601String().split('T').first}',
      affectsBalances: false,
    );
    if (deleted && mounted) {
      setState(() => _future = widget.fetchDocuments());
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<DocumentSummary>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(ManaSpacing.lg),
              child: ManaText.raw('Could not load documents.\n${snapshot.error}',
                  textAlign: TextAlign.center, style: ManaType.noteBad),
            ),
          );
        }
        final byType = <String, DocumentSummary>{};
        for (final d in snapshot.data ?? const <DocumentSummary>[]) {
          byType[d.documentType] = d; // most recent wins — fetch already orders by uploaded_at desc
        }
        return ListView(
          padding: const EdgeInsets.all(ManaSpacing.lg),
          children: widget.expectedTypes.map((label) {
            // 'Guarantor Documents'/'Other Documents' are display labels;
            // the real enum values are singular ('Guarantor Document',
            // 'Other') — matching on whichever form is present.
            final doc = byType[label] ?? byType[label.replaceFirst(RegExp(r's$'), '')];
            return Card(
              child: ListTile(
                leading: Icon(doc != null ? Icons.description : Icons.description_outlined,
                    color: doc != null ? ManaColors.brand : null),
                title: ManaText(label),
                subtitle: doc == null
                    ? ManaText.raw('Not uploaded yet', style: ManaType.note)
                    : null,
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Only customer documents carry an id, and only they are
                    // soft-deletable — an agent document has no delete path.
                    if (doc?.documentId != null)
                      IconButton(
                        icon: const Icon(Icons.delete_outline, size: 18),
                        color: ManaColors.statusBad,
                        tooltip: 'Delete',
                        onPressed: () => _deleteDocument(doc!, label),
                      ),
                    const Icon(Icons.chevron_right),
                  ],
                ),
                onTap: doc == null
                    ? null
                    : () => Navigator.of(context).push(
                          MaterialPageRoute(
                              builder: (_) => _DocumentViewerScreen(
                                  title: label, storedPath: doc.fileUrl)),
                        ),
              ),
            );
          }).toList(),
        );
      },
    );
  }
}

class _DocumentViewerScreen extends StatelessWidget {
  final String title;
  /// What `customer_documents.file_url` holds: an object path, or a legacy
  /// full signed URL. The link is minted when the document is opened and dies
  /// in minutes -- these are identity documents, and a year-long link to one
  /// sitting in a column was the whole problem.
  final String storedPath;
  const _DocumentViewerScreen({required this.title, required this.storedPath});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: ManaAppBar(title: title),
      backgroundColor: Colors.black,
      body: Center(
        child: FutureBuilder<String?>(
          future: ManaStoredFile.signedUrl(
              bucket: 'customer-documents', stored: storedPath),
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const CircularProgressIndicator(color: Colors.white);
            }
            final url = snapshot.data;
            if (url == null) {
              return const Padding(
                padding: EdgeInsets.all(ManaSpacing.lg),
                child: ManaText.raw(
                  "Couldn't open this document.",
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white),
                ),
              );
            }
            // PERF: cached — re-opening the same document (e.g. after backing
            // out of this viewer) previously re-downloaded it every time.
            return InteractiveViewer(
              child: CachedNetworkImage(
                imageUrl: url,
                fit: BoxFit.contain,
                progressIndicatorBuilder: (context, child, progress) =>
                    const Center(
                        child: CircularProgressIndicator(color: Colors.white)),
                // Deliberately does NOT print the URL any more. It is a signed
                // link to somebody's identity document, and putting it on
                // screen makes every screenshot of a failed preview a working
                // credential.
                errorWidget: (context, error, stackTrace) => const Padding(
                  padding: EdgeInsets.all(ManaSpacing.lg),
                  child: ManaText.raw(
                    "Couldn't preview this file — it may not be an image.",
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
