"""Render the Markdown design report to self-contained HTML and printable PDF."""
from pathlib import Path
from html import escape
import base64
import json
import re
import posixpath
import xml.etree.ElementTree as ET

import markdown
import pymupdf
from reportlab.lib import colors
from reportlab.lib.enums import TA_CENTER
from reportlab.lib.pagesizes import A4
from reportlab.lib.styles import ParagraphStyle
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.platypus import (
    SimpleDocTemplate, Paragraph, Spacer, PageBreak, LongTable, TableStyle, Image, KeepTogether,
)
from reportlab.platypus.tableofcontents import TableOfContents

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'docs/design-report.md'
OUT = ROOT / 'output'
TMP = ROOT / 'build/report-render'
OUT.mkdir(exist_ok=True)
(OUT / 'pdf').mkdir(exist_ok=True)
TMP.mkdir(parents=True, exist_ok=True)
text = SOURCE.read_text(encoding='utf-8')
html = markdown.markdown(text, extensions=['tables', 'fenced_code', 'toc'], output_format='xhtml')
tree = ET.fromstring('<article>' + html + '</article>')
for image in tree.iter('img'):
    path = SOURCE.parent / image.attrib['src']
    encoded = base64.b64encode(path.read_bytes()).decode()
    image.set('src', 'data:image/svg+xml;base64,' + encoded)
for link in tree.iter('a'):
    href = link.attrib.get('href', '')
    if href and not re.match(r'^(?:[a-zA-Z]+:|#|/)', href):
        link.set('href', posixpath.normpath('../docs/' + href))
web_body = ET.tostring(tree, encoding='unicode', method='html')
css = '''
*{box-sizing:border-box}body{margin:0;background:#eceef0;color:#202124;font:17px/1.85 "SimSun","Noto Serif CJK SC",serif}
main{max-width:960px;margin:30px auto;padding:54px 72px;background:white;box-shadow:0 2px 12px #0001}
h1,h2,h3,h4{font-family:"Microsoft YaHei",sans-serif;line-height:1.45;color:#152b3d}h1{font-size:30px;margin:0 0 28px}h2{font-size:25px;margin-top:56px;border-bottom:1px solid #9faab5;padding-bottom:10px}h3{font-size:20px;margin-top:30px}h4{font-size:17px}
p{margin:13px 0}table{border-collapse:collapse;width:100%;margin:22px 0;font-size:14px;line-height:1.65;table-layout:auto}th,td{border:1px solid #c8cdd2;padding:8px 10px;text-align:left;vertical-align:top;overflow-wrap:anywhere}th{background:#edf1f4;font-weight:600}img{display:block;max-width:100%;height:auto;margin:25px auto}code{font:0.88em Consolas,monospace;overflow-wrap:anywhere}pre{background:#f4f5f6;padding:16px;overflow-x:auto;line-height:1.55}a{color:#24517a;text-decoration:none}a:hover{text-decoration:underline}
nav{border:1px solid #c8cdd2;padding:18px 25px;margin:28px 0}nav a{display:block}.note{font:13px/1.6 "Microsoft YaHei",sans-serif;color:#58616b}
@media(max-width:700px){main{margin:0;padding:25px}body{font-size:16px}table{font-size:12px}th,td{padding:6px}}
@media print{@page{size:A4;margin:18mm}body{background:white;font-size:10.5pt}main{margin:0;padding:0;max-width:none;box-shadow:none}h2{break-before:page}h2,h3,h4{break-after:avoid}p{orphans:3;widows:3}table,img,pre{break-inside:avoid}table{font-size:9pt}nav{break-after:page}}
'''
links = '\n'.join(f'<a href="#{h.attrib["id"]}">{escape("".join(h.itertext()))}</a>' for h in tree.findall('h2'))
web_body = web_body.replace('<h2 ', f'<nav aria-label="目录">{links}</nav><h2 ', 1)
(OUT / 'design-report.html').write_text(
    '<!doctype html><html lang="zh-CN"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">'
    '<title>五级 RISC-V 处理器与定长 SIMD 扩展设计报告</title><style>' + css + '</style></head><body><main>'
    + web_body + '</main></body></html>', encoding='utf-8')

pdfmetrics.registerFont(TTFont('Song', 'C:/Windows/Fonts/simsun.ttc', subfontIndex=0))
pdfmetrics.registerFont(TTFont('Hei', 'C:/Windows/Fonts/simhei.ttf'))
styles = {
    'body': ParagraphStyle('body', fontName='Song', fontSize=10.5, leading=17.3, spaceAfter=8, wordWrap='CJK'),
    'h2': ParagraphStyle('h2', fontName='Hei', fontSize=17, leading=25, spaceAfter=17, keepWithNext=True),
    'h3': ParagraphStyle('h3', fontName='Hei', fontSize=12.5, leading=19, spaceBefore=12, spaceAfter=8, keepWithNext=True),
    'h4': ParagraphStyle('h4', fontName='Hei', fontSize=11, leading=18, spaceBefore=8, spaceAfter=6, keepWithNext=True),
    'cell': ParagraphStyle('cell', fontName='Song', fontSize=9, leading=14, wordWrap='CJK'),
    'code': ParagraphStyle('code', fontName='Courier', fontSize=8.5, leading=12.5, backColor=colors.HexColor('#f3f4f5'), borderPadding=9, spaceBefore=8, spaceAfter=12),
    'title': ParagraphStyle('title', fontName='Hei', fontSize=25, leading=39, alignment=TA_CENTER, spaceAfter=35, wordWrap='CJK'),
    'cover': ParagraphStyle('cover', fontName='Song', fontSize=13, leading=27, alignment=TA_CENTER),
}

def inline(node):
    result = escape(node.text or '')
    for child in node:
        content = inline(child)
        if child.tag == 'code':
            result += '<font name="Courier">' + content + '</font>'
        elif child.tag in ('strong', 'b'):
            result += '<font name="Hei">' + content + '</font>'
        elif child.tag == 'a' and child.attrib.get('href', '').startswith('http'):
            result += '<link href="' + escape(child.attrib['href'], quote=True) + '" color="#24517a">' + content + '</link>'
        elif child.tag == 'br':
            result += '<br/>'
        else:
            result += content
        result += escape(child.tail or '')
    return result

def footer(canvas, doc):
    if doc.page == 1:
        return
    canvas.saveState()
    canvas.setStrokeColor(colors.HexColor('#aab2bb'))
    canvas.line(50, 40, A4[0]-50, 40)
    canvas.setFont('Song', 8)
    canvas.drawString(50, 27, 'riscv-cpu-lab / 设计报告')
    canvas.drawRightString(A4[0]-50, 27, str(doc.page))
    canvas.restoreState()

class Report(SimpleDocTemplate):
    def afterFlowable(self, flowable):
        if getattr(flowable, 'is_chapter', False):
            key = 'chapter-' + str(self.page)
            self.canv.bookmarkPage(key)
            self.canv.addOutlineEntry(flowable.getPlainText(), key, 0)
            self.notify('TOCEntry', (0, flowable.getPlainText(), self.page, key))

pdf = OUT / 'pdf/design-report.pdf'
doc = Report(str(pdf), pagesize=A4, leftMargin=50, rightMargin=50,
             topMargin=48, bottomMargin=54, title='五级 RISC-V 处理器与定长 SIMD 扩展设计报告', author='riscv-cpu-lab')
story = [Spacer(1, 120), Paragraph('五级 RISC-V 处理器<br/>与定长 SIMD 扩展<br/>设计报告', styles['title']),
         Spacer(1, 30), Paragraph('riscv-cpu-lab<br/>SystemVerilog / RV32IM / Xsimd<br/><br/>2026 年 10 月 16 日', styles['cover']),
         PageBreak(), Paragraph('目录', styles['h2'])]
toc = TableOfContents()
toc.levelStyles = [ParagraphStyle('toc', fontName='Song', fontSize=12, leading=27, leftIndent=0)]
story += [toc, PageBreak()]
started = False
chapters = 0
for node in tree:
    tag = node.tag
    if tag == 'h2':
        if started:
            story.append(PageBreak())
        started = True
        chapters += 1
        heading = Paragraph(inline(node), styles['h2'])
        heading.is_chapter = True
        story.append(heading)
    elif not started:
        continue
    elif tag in ('h3', 'h4'):
        story.append(Paragraph(inline(node), styles[tag]))
    elif tag == 'p':
        img = node.find('img')
        if img is not None:
            raw = base64.b64decode(img.attrib['src'].split(',', 1)[1])
            svg = pymupdf.open(stream=raw, filetype='svg')
            pix = svg[0].get_pixmap(matrix=pymupdf.Matrix(1.5,1.5))
            name = TMP / f'figure-{len(story)}.png'
            pix.save(name)
            width = doc.width
            story += [Image(str(name), width=width, height=width*pix.height/pix.width), Spacer(1,8)]
        else:
            story.append(Paragraph(inline(node), styles['body']))
    elif tag == 'table':
        rows = node.findall('.//tr')
        data = [[Paragraph(inline(cell), styles['cell']) for cell in row] for row in rows]
        n = len(data[0])
        ratios = {2:[0.35,0.65],3:[0.23,0.41,0.36],4:[0.17,0.18,0.31,0.34],6:[0.16,0.1,0.16,0.2,0.2,0.18]}.get(n,[1/n]*n)
        if n == 2 and ''.join(rows[0][0].itertext()) == '文件':
            ratios = [0.49, 0.51]
        if n == 4 and ''.join(rows[0][0].itertext()) == '资源':
            ratios = [0.35, 0.2, 0.25, 0.2]
        table = LongTable(data, colWidths=[doc.width*r for r in ratios], repeatRows=1, hAlign='LEFT')
        table.setStyle(TableStyle([
            ('BACKGROUND',(0,0),(-1,0),colors.HexColor('#edf1f4')),
            ('GRID',(0,0),(-1,-1),0.4,colors.HexColor('#b8c0c8')),
            ('VALIGN',(0,0),(-1,-1),'TOP'),
            ('LEFTPADDING',(0,0),(-1,-1),6),('RIGHTPADDING',(0,0),(-1,-1),6),
            ('TOPPADDING',(0,0),(-1,-1),6),('BOTTOMPADDING',(0,0),(-1,-1),6),
        ]))
        story += [KeepTogether([table]) if len(rows) <= 8 else table, Spacer(1,11)]
    elif tag == 'pre':
        source = ''.join(node.itertext()).strip()
        story.append(Paragraph(escape(source).replace('\n','<br/>').replace(' ','&#160;'), styles['code']))
    elif tag in ('ol','ul'):
        for i, item in enumerate(node.findall('li'),1):
            prefix = f'{i}. ' if tag == 'ol' else '- '
            story.append(Paragraph(prefix+inline(item),styles['body']))
doc.multiBuild(story, onFirstPage=footer, onLaterPages=footer)
rendered = pymupdf.open(pdf)
for i, page in enumerate(rendered):
    page.get_pixmap(matrix=pymupdf.Matrix(1.1,1.1)).save(TMP / f'page-{i+1:02d}.png')
audit = {'source':str(SOURCE), 'chapters':chapters, 'pages':len(rendered), 'characters':len(text),
         'pdf':str(pdf), 'html':str(OUT/'design-report.html')}
(TMP/'audit.json').write_text(json.dumps(audit,ensure_ascii=False,indent=2),encoding='utf-8')
print(json.dumps(audit,ensure_ascii=False))
