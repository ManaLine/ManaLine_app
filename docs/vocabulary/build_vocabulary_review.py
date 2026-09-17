# -*- coding: utf-8 -*-
"""Builds the app-vocabulary review workbook + document from the ui_translations dump.

Source of truth is the live `ui_translations` table (project vjhxssqgqlvyesndubor).
all.tsv was captured from it and verified row-for-row against per-row md5s taken
in the database; only `terms_body` differs, and only in how its two real newlines
are encoded here (as a literal \n) so the dump can stay one row per line.
"""
import csv, hashlib, re
from collections import OrderedDict

SRC = 'all.tsv'
OUT = '/home/user/ManaLine_app/docs/vocabulary/'

rows = []
for line in open(SRC, encoding='utf-8').read().split('\n'):
    if not line:
        continue
    k, en, te = line.split('~|~')
    rows.append((k, en, te))
assert len(rows) == 1692, len(rows)

# Group by the English string: the same wording used on six screens is one
# decision to make, not six. Where one English string has drifted into two
# different Telugu strings, both are shown — that drift is the point.
groups = OrderedDict()
for k, en, te in rows:
    g = groups.setdefault(en, {'keys': [], 'te': []})
    g['keys'].append(k)
    if te not in g['te']:
        g['te'].append(te)

WORDY = re.compile(r'[.!?]\s|\bthe\b|\band\b', re.I)

def bucket(en):
    n = len(en.split())
    if n <= 3:
        return 0            # A — words and labels
    if n <= 8 and not WORDY.search(en):
        return 1            # B — short phrases
    return 2                # C — messages and notes

SECTIONS = ['A. Words & Labels (buttons, headings, field names)',
            'B. Short Phrases',
            'C. Messages, Notes & Helper Text']

entries = []
for en, g in sorted(groups.items(), key=lambda kv: (bucket(kv[0]), kv[0].casefold())):
    te = g['te']
    te_cell = te[0] if len(te) == 1 else '\n'.join(
        '%d) %s' % (i + 1, t) for i, t in enumerate(te))
    entries.append({
        'section': bucket(en),
        'en': en,
        'te': te_cell,
        'uses': len(g['keys']),
        'keys': ' '.join(g['keys']),
        'conflict': len(te) > 1,
        'missing_te': not any(t.strip() for t in te),
    })

# ---- CSV: the machine-readable copy, so corrections can be applied back ----
with open(OUT + 'app_vocabulary.csv', 'w', encoding='utf-8-sig', newline='') as f:
    w = csv.writer(f)
    w.writerow(['S.No', 'In-use English', 'Changes in English',
                'In-use Telugu', 'Changes in Telugu',
                'Section', 'Times used', 'Translation keys'])
    for i, e in enumerate(entries, 1):
        w.writerow([i, e['en'], '', e['te'], '',
                    SECTIONS[e['section']][0], e['uses'], e['keys']])

# ---- XLSX ----
from openpyxl import Workbook
from openpyxl.styles import Font, Alignment, PatternFill
from openpyxl.utils import get_column_letter

wb = Workbook()
ws = wb.active
ws.title = 'Vocabulary'
head = ['S.No', 'In-use English', 'Changes in English', 'In-use Telugu',
        'Changes in Telugu', 'Sec', 'Uses', 'Keys']
ws.append(head)
hf = Font(bold=True, color='FFFFFF')
fill = PatternFill('solid', fgColor='1F4E5F')
for c in ws[1]:
    c.font, c.fill = hf, fill
    c.alignment = Alignment(vertical='center')
ws.freeze_panes = 'A2'

warn = PatternFill('solid', fgColor='FFF2CC')
for i, e in enumerate(entries, 1):
    ws.append([i, e['en'], '', e['te'], '', SECTIONS[e['section']][0],
               e['uses'], e['keys']])
    if e['conflict'] or e['missing_te']:
        for col in (4,):
            ws.cell(row=i + 1, column=col).fill = warn
for col, wd in zip('ABCDEFGH', (6, 52, 30, 52, 30, 5, 6, 40)):
    ws.column_dimensions[col].width = wd
for r in ws.iter_rows(min_row=2):
    for c in r:
        c.alignment = Alignment(wrap_text=True, vertical='top')
ws.auto_filter.ref = 'A1:H%d' % (len(entries) + 1)
wb.save(OUT + 'app_vocabulary.xlsx')

# ---- DOCX ----
from docx import Document
from docx.shared import Pt, Cm, RGBColor
from docx.enum.text import WD_ALIGN_PARAGRAPH
from docx.oxml.ns import qn

doc = Document()
st = doc.styles['Normal']
st.font.name = 'Calibri'
st.font.size = Pt(9)
st.element.rPr.rFonts.set(qn('w:cs'), 'Nirmala UI')

sec = doc.sections[0]
sec.left_margin = sec.right_margin = Cm(1.2)
sec.top_margin = sec.bottom_margin = Cm(1.2)

h = doc.add_heading('MANA LINE — App Vocabulary Review', level=0)
p = doc.add_paragraph()
p.add_run('Every distinct word, label and message the app shows, English and Telugu, '
          'taken from the live ui_translations table. ').italic = True
p.add_run('Fill in the two "Changes" columns only — leave a cell blank to keep the '
          'wording as it is.').bold = True

stats = doc.add_paragraph()
stats.add_run('%d distinct English strings across %d translation keys.  '
              '%d have more than one Telugu wording in use (shaded, numbered in the '
              'cell — pick one).  %d have no Telugu at all.'
              % (len(entries), len(rows),
                 sum(1 for e in entries if e['conflict']),
                 sum(1 for e in entries if e['missing_te'])))

cur = None
for i, e in enumerate(entries, 1):
    if e['section'] != cur:
        cur = e['section']
        doc.add_heading(SECTIONS[cur], level=1)
        t = doc.add_table(rows=1, cols=5)
        t.style = 'Table Grid'
        for cell, txt in zip(t.rows[0].cells,
                             ['#', 'In-use English', 'Changes in English',
                              'In-use Telugu', 'Changes in Telugu']):
            cell.text = ''
            r = cell.paragraphs[0].add_run(txt)
            r.bold = True
        widths = (Cm(1.1), Cm(5.6), Cm(3.6), Cm(5.6), Cm(3.6))
    row = t.add_row().cells
    row[0].text = str(i)
    row[1].text = e['en']
    row[2].text = ''
    row[3].text = e['te']
    row[4].text = ''
    for cell, w in zip(row, widths):
        cell.width = w
    if e['conflict'] or e['missing_te']:
        for par in row[3].paragraphs:
            for r in par.runs:
                r.font.color.rgb = RGBColor(0xB0, 0x00, 0x00)

doc.save(OUT + 'app_vocabulary.docx')
print('entries', len(entries), 'conflicts',
      sum(1 for e in entries if e['conflict']), 'missing',
      sum(1 for e in entries if e['missing_te']))
