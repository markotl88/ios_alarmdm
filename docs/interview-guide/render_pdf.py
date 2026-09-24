#!/usr/bin/env python3
"""Portable PDF builder for this guide (ReportLab, with embedded Unicode fonts).

Usage: python3 render_pdf.py [--output path] [--font-dir directory]
The established pandoc/XeLaTeX builder remains available in build.sh.
"""
from pathlib import Path
import argparse
import html
import os
import re
import textwrap
from reportlab.pdfgen import canvas
from reportlab.platypus import (
    BaseDocTemplate, PageTemplate, Frame, Paragraph, Spacer, PageBreak,
    Preformatted, LongTable, TableStyle,
)
from reportlab.platypus.tableofcontents import TableOfContents
from reportlab.lib.styles import ParagraphStyle
from reportlab.lib import colors
from reportlab.lib.pagesizes import A4
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont

ROOT = Path(__file__).resolve().parent
BLUE = colors.HexColor('#277990')
INK = colors.HexColor('#24303A')
W, H = A4
MARGIN = 49
WIDTH = W - 2 * MARGIN


def fonts(directory=None):
    candidates = [Path(directory)] if directory else []
    candidates += [Path('/usr/share/fonts/truetype/dejavu'), Path.home() / '.cache/codex-runtimes/codex-primary-runtime/dependencies/native/libreoffice-headless/libreoffice/LibreOfficeDev.app/Contents/Resources/fonts/truetype']
    directory = next((p for p in candidates if (p / 'DejaVuSans.ttf').exists()), None)
    if not directory:
        raise SystemExit('Pass --font-dir containing DejaVu Sans and DejaVu Sans Mono TTF files.')
    for name, file in [('Body','DejaVuSans.ttf'), ('Bold','DejaVuSans-Bold.ttf'), ('Italic','DejaVuSans-Oblique.ttf'), ('BoldItalic','DejaVuSans-BoldOblique.ttf'), ('Code','DejaVuSansMono.ttf')]:
        pdfmetrics.registerFont(TTFont(name, str(directory / file)))
    pdfmetrics.registerFontFamily('Body', normal='Body', bold='Bold', italic='Italic', boldItalic='BoldItalic')


def inline(text):
    code = []
    def hold(m):
        code.append('<font face="Code" size="8">' + html.escape(m[1]) + '</font>')
        return f'CODETOKEN{len(code)-1}END'
    text = re.sub(r'`([^`]+)`', hold, text)
    text = html.escape(text)
    text = re.sub(r'\*\*(.+?)\*\*', r'<b>\1</b>', text)
    text = re.sub(r'(?<!\*)\*([^*]+)\*(?!\*)', r'<i>\1</i>', text)
    text = re.sub(r'\[([^\]]+)\]\((https?://[^)]+)\)', r'<link href="\2" color="#277990">\1</link>', text)
    for i, value in enumerate(code):
        text = text.replace(f'CODETOKEN{i}END', value)
    return text


STYLES = {}

def styles():
    STYLES['body'] = ParagraphStyle('BodyText', fontName='Body', fontSize=9.2, leading=13.2, textColor=INK, spaceAfter=6)
    STYLES['quote'] = ParagraphStyle('Quote', parent=STYLES['body'], leftIndent=13, borderPadding=7, backColor=colors.HexColor('#EEF5F7'))
    STYLES['list'] = ParagraphStyle('List', parent=STYLES['body'], leftIndent=12, firstLineIndent=-9, spaceAfter=4)
    STYLES['table'] = ParagraphStyle('Table', parent=STYLES['body'], fontSize=8, leading=11, spaceAfter=0)
    for level, size in [(1,22),(2,16),(3,11.3)]:
        STYLES[f'h{level}'] = ParagraphStyle(f'H{level}', fontName='Bold', fontSize=size, leading=size*1.23, textColor=BLUE, spaceBefore=14, spaceAfter=9, keepWithNext=True)
    STYLES['code'] = ParagraphStyle('Code', fontName='Code', fontSize=7.2, leading=9.8, backColor=colors.HexColor('#F3F5F7'), borderPadding=7, spaceBefore=4, spaceAfter=9)


def page_frame(c, doc):
    if doc.page == 1:
        return
    c.saveState()
    c.setFont('Body', 8)
    c.setFillColor(BLUE)
    c.drawString(MARGIN, H-30, 'Senior iOS Interview Guide / AlarmDM 3.1')
    c.drawRightString(W-MARGIN, H-30, str(doc.page))
    c.setStrokeColor(colors.HexColor('#D7E2E7'))
    c.line(MARGIN, H-36, W-MARGIN, H-36)
    c.restoreState()


class GuideDoc(BaseDocTemplate):
    def __init__(self, path):
        super().__init__(str(path), pagesize=A4, title='Senior iOS Interview Guide', author='Marko Stajić', leftMargin=MARGIN, rightMargin=MARGIN, topMargin=52, bottomMargin=43)
        self.addPageTemplates(PageTemplate(id='guide', frames=[Frame(MARGIN,43,WIDTH,H-95,id='body',leftPadding=0,rightPadding=0,topPadding=0,bottomPadding=0)],onPage=page_frame))
    def beforeDocument(self):
        self.heading_counter = 0
    def afterFlowable(self, f):
        if isinstance(f, Paragraph) and f.style.name in ('H1','H2') and f.getPlainText() != 'Contents':
            self.heading_counter += 1
            key = f'h{self.heading_counter}'
            title = f.getPlainText()
            level = 0 if f.style.name == 'H1' else 1
            self.canv.bookmarkPage(key)
            self.canv.addOutlineEntry(title,key,level=level,closed=False)
            self.notify('TOCEntry',(level,title,self.page,key))


def parse(text):
    text = re.sub(r'^---\n.*?\n---\n', '', text, count=1, flags=re.S)
    # Standardize prose dashes while keeping source code untouched below.
    lines = text.splitlines()
    story = []
    i = 0
    while i < len(lines):
        line = lines[i].strip()
        if not line:
            i += 1
            continue
        if line.startswith('```'):
            i += 1
            block = []
            while i < len(lines) and not lines[i].strip().startswith('```'):
                raw = lines[i].expandtabs(4)
                # Deterministic wrapping; never truncate a source excerpt.
                wrapped = textwrap.wrap(raw, width=106, expand_tabs=False, replace_whitespace=False, drop_whitespace=False, break_long_words=True, break_on_hyphens=False) or ['']
                block.extend(wrapped)
                i += 1
            story.append(Preformatted('\n'.join(block), STYLES['code']))
            i += 1
            continue
        if line == r'\newpage':
            if story and not isinstance(story[-1], PageBreak):
                story.append(PageBreak())
            i += 1
            continue
        heading = re.match(r'^(#{1,3}) (.+)', line)
        if heading:
            level = len(heading[1])
            if level == 1 and story and not isinstance(story[-1], PageBreak):
                story.append(PageBreak())
            story.append(Paragraph(inline(heading[2]), STYLES[f'h{level}']))
            i += 1
            continue
        if line.startswith('|'):
            rows = []
            while i < len(lines) and lines[i].strip().startswith('|'):
                cells = lines[i].strip().strip('|').split('|')
                if not all(re.fullmatch(r'\s*:?-+:?\s*', cell) for cell in cells):
                    rows.append([Paragraph(inline(c.strip()), STYLES['table']) for c in cells])
                i += 1
            if rows:
                n = len(rows[0])
                widths = [WIDTH/n]*n
                if n == 2: widths = [WIDTH*.32,WIDTH*.68]
                table = LongTable(rows,colWidths=widths,repeatRows=1,hAlign='LEFT')
                table.setStyle(TableStyle([('BACKGROUND',(0,0),(-1,0),colors.HexColor('#E3EEF2')),('VALIGN',(0,0),(-1,-1),'TOP'),('LINEBELOW',(0,0),(-1,0),.5,BLUE),('LINEBELOW',(0,1),(-1,-1),.25,colors.HexColor('#D7E2E7')),('LEFTPADDING',(0,0),(-1,-1),6),('RIGHTPADDING',(0,0),(-1,-1),6),('TOPPADDING',(0,0),(-1,-1),6),('BOTTOMPADDING',(0,0),(-1,-1),6)]))
                story.extend([table,Spacer(1,9)])
            continue
        kind = 'quote' if line.startswith('>') else 'list' if re.match(r'^(?:- |\d+\. )',line) else 'body'
        chunks = [line.lstrip('> ').strip() if kind=='quote' else line]
        i += 1
        while i < len(lines) and lines[i].strip() and not re.match(r'^(?:#{1,3} |```|\||\\newpage|- |\d+\. )',lines[i].strip()):
            following = lines[i].strip()
            if following.startswith('>') != (kind == 'quote'): break
            chunks.append(following.lstrip('> ').strip() if kind=='quote' else following)
            i += 1
        prose = ' '.join(chunks).replace('\u2011','-').replace('—','-').replace('–','-')
        story.append(Paragraph(inline(prose),STYLES[kind]))
    return story


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--output',type=Path,default=ROOT/'Senior_iOS_Interview_Guide.pdf')
    parser.add_argument('--font-dir')
    parser.add_argument('--source', type=Path, default=ROOT/'guide.md')
    args = parser.parse_args()
    fonts(args.font_dir)
    styles()
    story = [Spacer(1,120), Paragraph('Senior iOS<br/>Interview Guide',ParagraphStyle('Title',fontName='Bold',fontSize=34,leading=42,textColor=BLUE)),Spacer(1,24),Paragraph('Worked from AlarmDM 3.1<br/>SwiftUI, concurrency and architecture',ParagraphStyle('Subtitle',parent=STYLES['h2'])),Spacer(1,40),Paragraph('Marko Stajić<br/>Reviewed September 2026',STYLES['body']),PageBreak(),Paragraph('Contents',STYLES['h1'])]
    toc = TableOfContents()
    toc.levelStyles = [ParagraphStyle('toc0',fontName='Bold',fontSize=10,leading=15,spaceBefore=7),ParagraphStyle('toc1',fontName='Body',fontSize=9,leading=13,leftIndent=12)]
    story.extend([toc,PageBreak()])
    source = args.source.read_text()
    supplement = (ROOT/'modern-swift.md').read_text()
    # Walkthrough and cheat sheet close the guide, after historical appendices.
    story.extend(parse(source))
    story.extend(parse(supplement))
    args.output.parent.mkdir(parents=True,exist_ok=True)
    GuideDoc(args.output).multiBuild(story)
    print(args.output)

if __name__ == '__main__':
    main()
