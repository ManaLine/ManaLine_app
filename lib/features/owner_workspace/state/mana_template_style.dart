/// Making a generated spreadsheet look like something a person can fill in.
///
/// The migration templates were correct and unreadable: a bare grid of
/// lower-case headers, dates wanted in yyyy-mm-dd, and no clue which columns
/// were compulsory or what a column would accept. An Owner who keeps a paper
/// book was expected to work all of that out from the Notes sheet.
///
/// Everything here is presentation over the same data the parsers already
/// read, with one exception that is not presentation: [withDropdowns] writes a
/// list validation that SUGGESTS and never enforces, so a village the Owner
/// has not set up yet can still be typed in and created later.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:excel/excel.dart';

/// The header row: dark ground, white bold text, tall enough to read.
CellStyle manaHeaderStyle() => CellStyle(
      bold: true,
      fontSize: 12,
      fontColorHex: ExcelColor.white,
      backgroundColorHex: ExcelColor.blue800,
      horizontalAlign: HorizontalAlign.Center,
      verticalAlign: VerticalAlign.Center,
      textWrapping: TextWrapping.WrapText,
    );

/// A column the Owner must fill. Same header, warmer ground, so "required"
/// is visible at a glance instead of hidden in an asterisk.
CellStyle manaRequiredHeaderStyle() => CellStyle(
      bold: true,
      fontSize: 12,
      fontColorHex: ExcelColor.white,
      backgroundColorHex: ExcelColor.red800,
      horizontalAlign: HorizontalAlign.Center,
      verticalAlign: VerticalAlign.Center,
      textWrapping: TextWrapping.WrapText,
    );

/// Cells the app filled in already — the Owner should not retype these.
CellStyle manaPrefilledStyle() => CellStyle(
      fontColorHex: ExcelColor.grey600,
      backgroundColorHex: ExcelColor.grey200,
    );

/// Dates, shown the way India writes them.
///
/// The cell is a real Excel date, so what is STORED is a day number and the
/// format below only decides how it is drawn. That is the whole point: a
/// stored day number cannot be misread as the wrong month, however the Owner's
/// copy of Excel happens to be set up. Text dates are what made 01/02 ambiguous.
CellStyle manaDateStyle() => CellStyle(
      numberFormat: const CustomDateTimeNumFormat(formatCode: 'dd/mm/yyyy'),
      horizontalAlign: HorizontalAlign.Center,
    );

/// Rupees, with a thousands separator and no paise — money columns are
/// numeric(_,0) and paise cannot be stored, so showing them would be a lie.
CellStyle manaMoneyStyle() => CellStyle(
      numberFormat: const CustomNumericNumFormat(formatCode: '#,##0'),
      horizontalAlign: HorizontalAlign.Right,
    );

/// One header cell, styled and sized.
void manaWriteHeader(
  Sheet sheet,
  List<String> headers, {
  Set<int> required = const {},
  List<double>? widths,
}) {
  for (var i = 0; i < headers.length; i++) {
    final cell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0));
    cell.value = TextCellValue(headers[i]);
    cell.cellStyle =
        required.contains(i) ? manaRequiredHeaderStyle() : manaHeaderStyle();
    sheet.setColumnWidth(i, widths != null && i < widths.length ? widths[i] : 18);
  }
  sheet.setRowHeight(0, 32);
}

/// A list validation on one column of one sheet, written straight into the
/// saved file.
///
/// The excel package cannot do this — there is no data validation anywhere in
/// 4.0.6 — so the .xlsx is unzipped, the XML injected and the file zipped
/// again. It is the only way to get a dropdown without changing library.
///
/// SUGGESTS, NEVER ENFORCES. `showErrorMessage="0"` means Excel offers the
/// list and accepts anything else in silence. A village the Owner has not set
/// up yet must still be typeable, and the import creates it; a dropdown that
/// refused it would stop the migration over the one thing the Owner is most
/// likely to be right about.
Uint8List withDropdowns(
  Uint8List bytes,
  List<ManaDropdown> dropdowns, {
  int lastRow = 500,
}) {
  if (dropdowns.isEmpty) return bytes;
  final archive = ZipDecoder().decodeBytes(bytes);
  final out = Archive();

  // Sheets are numbered in workbook order, which is the order they were
  // created in — the same order the caller names them.
  final bySheetFile = <String, List<ManaDropdown>>{};
  for (final d in dropdowns) {
    bySheetFile.putIfAbsent('xl/worksheets/sheet${d.sheetNumber}.xml', () => []).add(d);
  }

  for (final file in archive.files) {
    final targets = bySheetFile[file.name];
    if (targets == null || !file.isFile) {
      out.addFile(file);
      continue;
    }
    var xml = utf8.decode(file.content as List<int>);
    final buffer = StringBuffer('<dataValidations count="${targets.length}">');
    for (final d in targets) {
      final col = _columnLetter(d.columnIndex);
      buffer
        ..write('<dataValidation type="list" allowBlank="1" '
            'showInputMessage="1" showErrorMessage="0" '
            'sqref="${col}2:$col$lastRow">')
        ..write('<formula1>"${d.options.map(_escape).join(',')}"</formula1>')
        ..write('</dataValidation>');
    }
    buffer.write('</dataValidations>');

    // Schema order: dataValidations sits after sheetData.
    xml = xml.replaceFirst('</sheetData>', '</sheetData>${buffer.toString()}');
    final encoded = utf8.encode(xml);
    out.addFile(ArchiveFile(file.name, encoded.length, encoded));
  }
  return Uint8List.fromList(ZipEncoder().encode(out)!);
}

String _escape(String s) =>
    s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;').replaceAll('"', '&quot;');

String _columnLetter(int index) {
  var n = index + 1;
  var out = '';
  while (n > 0) {
    final rem = (n - 1) % 26;
    out = String.fromCharCode(65 + rem) + out;
    n = (n - 1) ~/ 26;
  }
  return out;
}

/// One column that offers a list.
class ManaDropdown {
  /// 1-based, in the order the sheets were created.
  final int sheetNumber;
  final int columnIndex;
  final List<String> options;
  const ManaDropdown({
    required this.sheetNumber,
    required this.columnIndex,
    required this.options,
  });
}
