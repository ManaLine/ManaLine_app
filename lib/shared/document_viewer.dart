import 'package:flutter/material.dart';
import '../design/tokens/colors.dart';
import '../design/tokens/spacing.dart';
import '../design/components/mana_text.dart';

/// One row from customer_documents/agent_documents — both tables share
/// the exact same shape (document_type/file_url/uploaded_at), just keyed
/// on a different owning id, so one model covers both.
class DocumentSummary {
  final String documentType;
  final String fileUrl;
  final DateTime uploadedAt;
  DocumentSummary({required this.documentType, required this.fileUrl, required this.uploadedAt});
}

/// Reusable "Documents" tab: shows one row per expected document type,
/// with a real uploaded file if one exists, and taps into a simple
/// full-screen viewer. Used by both OW-002 (Agent) and OW-004 (Customer)
/// Documents tabs — previously each was a static list of labels with
/// `onTap: () {}`, so tapping any row (even ones with a real uploaded
/// file sitting in Storage) did nothing.
class DocumentsListView extends StatefulWidget {
  final List<String> expectedTypes;
  final Future<List<DocumentSummary>> Function() fetchDocuments;
  const DocumentsListView({super.key, required this.expectedTypes, required this.fetchDocuments});

  @override
  State<DocumentsListView> createState() => _DocumentsListViewState();
}

class _DocumentsListViewState extends State<DocumentsListView> {
  late Future<List<DocumentSummary>> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.fetchDocuments();
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
                  textAlign: TextAlign.center, style: const TextStyle(color: ManaColors.statusBad, fontSize: 13)),
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
                    color: doc != null ? ManaColors.brass : null),
                title: ManaText(label),
                subtitle: doc == null
                    ? const ManaText.raw('Not uploaded yet', style: TextStyle(fontSize: 13, color: ManaColors.textSecondary))
                    : null,
                trailing: const Icon(Icons.chevron_right),
                onTap: doc == null
                    ? null
                    : () => Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => _DocumentViewerScreen(title: label, url: doc.fileUrl)),
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
  final String url;
  const _DocumentViewerScreen({required this.title, required this.url});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: ManaText.raw(title)),
      backgroundColor: Colors.black,
      body: Center(
        child: InteractiveViewer(
          child: Image.network(
            url,
            fit: BoxFit.contain,
            loadingBuilder: (context, child, progress) =>
                progress == null ? child : const Center(child: CircularProgressIndicator(color: Colors.white)),
            errorBuilder: (context, error, stackTrace) => Padding(
              padding: const EdgeInsets.all(ManaSpacing.lg),
              child: ManaText.raw(
                "Couldn't preview this file — it may not be an image. URL:\n$url",
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
