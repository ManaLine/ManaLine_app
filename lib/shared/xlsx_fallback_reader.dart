import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

/// A minimal .xlsx reader used only when the `excel` package refuses a file.
///
/// WHY THIS EXISTS: `Excel.decodeBytes` throws
/// "Null check operator used on a null value" on any workbook that stores its
/// text as INLINE strings (`<c t="inlineStr"><is><t>…</t></is></c>`) instead of
/// a shared-strings table. openpyxl writes that shape, and so do several
/// exporters, so an Owner who prepared the sheet in anything other than Excel
/// itself was told "this file could not be read as a spreadsheet" — the app
/// blaming their file for its own crash. Found on the live test with a real
/// 55-row identity sheet.
///
/// Deliberately NOT a general xlsx implementation. It reads what this app's
/// importers need — a grid of strings per sheet — and nothing else: no styles,
/// no formulas, no dates beyond the serial number, no merged cells.
class XlsxFallbackReader {
  /// Sheet name -> rows -> cells, in column order with gaps preserved.
  final Map<String, List<List<String>>> sheets;

  const XlsxFallbackReader(this.sheets);

  static XlsxFallbackReader decode(Uint8List bytes) {
    final zip = ZipDecoder().decodeBytes(bytes);

    ArchiveFile? file(String name) {
      for (final f in zip.files) {
        if (f.name == name) return f;
      }
      return null;
    }

    String? text(String name) {
      final f = file(name);
      if (f == null) return null;
      return String.fromCharCodes(f.content as List<int>);
    }

    // Shared strings, when the workbook has them at all.
    final shared = <String>[];
    final sharedXml = text('xl/sharedStrings.xml');
    if (sharedXml != null) {
      for (final si in XmlDocument.parse(sharedXml).findAllElements('si')) {
        // A run-formatted cell is several <t> nodes; joining them is what the
        // spreadsheet shows.
        shared.add(si.findAllElements('t').map((t) => t.innerText).join());
      }
    }

    // Sheet name -> target path, via the workbook's relationships.
    final relsXml = text('xl/_rels/workbook.xml.rels');
    final relTargets = <String, String>{};
    if (relsXml != null) {
      for (final rel in XmlDocument.parse(relsXml).findAllElements('Relationship')) {
        final id = rel.getAttribute('Id');
        final target = rel.getAttribute('Target');
        if (id != null && target != null) relTargets[id] = target;
      }
    }

    final out = <String, List<List<String>>>{};
    final workbookXml = text('xl/workbook.xml');
    if (workbookXml == null) return const XlsxFallbackReader({});

    var fallbackIndex = 0;
    for (final sheet in XmlDocument.parse(workbookXml).findAllElements('sheet')) {
      final name = sheet.getAttribute('name');
      if (name == null) continue;
      fallbackIndex++;

      final rid = sheet.getAttribute('r:id') ?? sheet.getAttribute('id');
      var target = rid == null ? null : relTargets[rid];
      target ??= 'worksheets/sheet$fallbackIndex.xml';
      final path = target.startsWith('/')
          ? target.substring(1)
          : (target.startsWith('xl/') ? target : 'xl/$target');

      final sheetXml = text(path);
      if (sheetXml == null) continue;
      out[name] = _rows(XmlDocument.parse(sheetXml), shared);
    }

    return XlsxFallbackReader(out);
  }

  static List<List<String>> _rows(XmlDocument doc, List<String> shared) {
    final rows = <List<String>>[];
    for (final row in doc.findAllElements('row')) {
      final cells = <String>[];
      for (final c in row.findElements('c')) {
        // "B7" -> column index 1. Gaps matter: the importers read some columns
        // positionally, so a skipped empty cell must not shift the rest left.
        final ref = c.getAttribute('r') ?? '';
        final letters = ref.replaceAll(RegExp(r'[0-9]'), '');
        var col = 0;
        for (final ch in letters.toUpperCase().codeUnits) {
          col = col * 26 + (ch - 64);
        }
        col = col > 0 ? col - 1 : cells.length;
        while (cells.length < col) {
          cells.add('');
        }

        final type = c.getAttribute('t');
        String value;
        if (type == 'inlineStr') {
          value = c.findElements('is').expand((is_) => is_.findAllElements('t'))
              .map((t) => t.innerText).join();
        } else if (type == 's') {
          final idx = int.tryParse(c.findElements('v').map((v) => v.innerText).join());
          value = (idx != null && idx >= 0 && idx < shared.length) ? shared[idx] : '';
        } else {
          value = c.findElements('v').map((v) => v.innerText).join();
        }
        cells.add(value.trim());
      }
      rows.add(cells);
    }
    return rows;
  }
}
