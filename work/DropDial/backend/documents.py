from pathlib import Path
import io,json,re,sys,subprocess,os,zipfile,shutil
from PIL import Image,ImageDraw,ImageFont
import pypdfium2 as pdfium
from pypdf import PdfReader,PdfWriter
from common import *

def reader(path,params):
    doc=PdfReader(path)
    if doc.is_encrypted and not doc.decrypt(params.get('password','')): raise ValueError(T('This PDF needs the correct password'))
    return doc

def metadata(path):
    doc=PdfReader(path)
    return {'Pages':len(doc.pages),**{str(k).lstrip('/'):str(v) for k,v in (doc.metadata or {}).items()}}

def images_document(paths,fmt,params):
    images=[]
    for path in paths:
        image=open_image(path)
        if 'A' in image.getbands():
            white=Image.new('RGB',image.size,'white');white.paste(image,mask=image.getchannel('A'));image=white
        images.append(image.convert('RGB'))
    with output_file(paths[0],'combined' if len(paths)>1 else 'converted','.'+fmt) as state:
        if fmt=='pdf': images[0].save(state['temp'],format='PDF',save_all=True,append_images=images[1:],resolution=150)
        else:
            from docx import Document
            from docx.shared import Inches
            doc=Document()
            for i,image in enumerate(images):
                if i: doc.add_page_break()
                data=io.BytesIO(); image.save(data,format='PNG'); data.seek(0)
                doc.add_picture(data,width=Inches(6))
            doc.save(state['temp'])
    return state['output']

def render_page(page):
    # 300 DPI, reduced for oversized pages so the bitmap stays within the same 80 MP limit as images.
    width,height=page.get_size(); scale=min(300/72,.999*(80_000_000/max(1,width*height))**.5)
    return page.render(scale=scale).to_pil()

def render_pdf(path,fmt,params):
    doc=pdfium.PdfDocument(str(path),password=params.get('password') or None)
    if len(doc)==1:
        with output_file(path,'page-1','.'+fmt) as state:
            image=render_page(doc[0]); save_image(image,state['temp'],fmt,92)
    else:
        with output_folder(path,'pages-'+fmt) as state:
            for index in range(len(doc)):
                image=render_page(doc[index]); save_image(image,state['temp']/f'page-{index+1:04d}.{fmt}',fmt,92)
    doc.close(); return state['output']

def pdf_word(path,params):
    fitz = get_fitz()
    from pdftools import open_pdf
    doc=open_pdf(path,params)
    with output_file(path,'converted','.docx') as state:
        if any(page.get_text().strip() for page in doc):
            try:
                from pdf2docx import Converter
                converter=Converter(str(path),password=params.get('password',''))
                try: converter.convert(str(state['temp']),multi_processing=False)
                finally: converter.close()
            except Exception:
                from docx import Document
                from docx.shared import Inches
                word=Document()
                for i,page in enumerate(doc):
                    if i: word.add_page_break()
                    image=io.BytesIO(page.get_pixmap(matrix=fitz.Matrix(2,2)).tobytes('png')); word.add_picture(image,width=Inches(6))
                word.save(state['temp'])
        else:
            from docx import Document
            from docx.shared import Inches
            word=Document()
            for i,page in enumerate(doc):
                if i: word.add_page_break()
                image=io.BytesIO(page.get_pixmap(matrix=fitz.Matrix(2,2)).tobytes('png')); word.add_picture(image,width=Inches(6))
            word.save(state['temp'])
        # Post-process to remove duplicate bullet characters in list paragraphs
        if state['temp'].exists():
            try:
                from docx import Document
                word_doc = Document(str(state['temp']))
                modified = False
                for p in word_doc.paragraphs:
                    p_style = (p.style.name or '').lower() if p.style else ''
                    if 'list' in p_style or 'bullet' in p_style:
                        for run in p.runs:
                            if run.text:
                                new_text = re.sub(r'^\s*[•◦▪‣]\s*', '', run.text)
                                if new_text != run.text:
                                    run.text = new_text
                                    modified = True
                                    break
                if modified:
                    word_doc.save(str(state['temp']))
            except Exception: pass
    doc.close(); return state['output']

def text_image(text,width=1200):
    font=ImageFont.truetype(str(FONT),28)
    lines=[]
    for paragraph in text.splitlines() or ['']:
        current=''
        for char in paragraph:
            if font.getlength(current+char)>width-100:
                lines.append(current); current=char
            else: current+=char
        lines.append(current)
    height=max(180,100+len(lines)*42)
    if width*height>80_000_000: raise ValueError(T('The text is too long for a single image; choose PDF instead'))
    image=Image.new('RGB',(width,height),'white'); draw=ImageDraw.Draw(image)
    for i,line in enumerate(lines): draw.text((50,50+i*42),line,fill='#111111',font=font)
    return image

def text_pdf(path,text,params):
    fitz = get_fitz()
    doc=fitz.open(); font=fitz.Font(fontfile=str(FONT))
    margin=48; lines=[]
    for paragraph in text.splitlines() or ['']:
        current=''
        for char in paragraph:
            if font.text_length(current+char,fontsize=12)>499: lines.append(current); current=char
            else: current+=char
        lines.append(current)
    for start in range(0,len(lines),44):
        page=doc.new_page(width=595,height=842); page.insert_font(fontname='DocumentFont',fontfile=str(FONT))
        for index,line in enumerate(lines[start:start+44]): page.insert_text((margin,margin+18+index*16),line,fontname='DocumentFont',fontsize=12)
    with output_file(path,'converted','.pdf') as state: doc.save(state['temp'],garbage=4,deflate=True)
    doc.close(); return state['output']

def timestamp(seconds,vtt=False):
    milliseconds=round(float(seconds)*1000); hours,rest=divmod(milliseconds,3600000); minutes,rest=divmod(rest,60000); seconds,millis=divmod(rest,1000)
    return f'{hours:02}:{minutes:02}:{seconds:02}'+('.' if vtt else ',')+f'{millis:03}'

def subtitles(path,fmt,params):
    text=Path(path).read_text(encoding='utf-8-sig'); source=Path(path).suffix.lower(); cues=[]
    if source=='.txt':
        span=number(params,'cueSeconds',4)
        for i,line in enumerate(x for x in text.splitlines() if x.strip()): cues.append((timestamp(i*span),timestamp((i+1)*span),line))
    else:
        for block in re.split(r'\n\s*\n',text.replace('\r','')):
            lines=block.splitlines()
            timed=next((i for i,x in enumerate(lines) if '-->' in x),None)
            if timed is not None:
                start,end=lines[timed].split('-->',1); end=end.strip().split()[0]
                cues.append((start.strip(),end,'\n'.join(lines[timed+1:])))
    if fmt=='txt': output='\n\n'.join(cue[2] for cue in cues)
    else:
        output='WEBVTT\n\n' if fmt=='vtt' else ''
        for i,(start,end,content) in enumerate(cues):
            separator='.' if fmt=='vtt' else ','
            normalize=lambda s: ('00:'+s if len(s.split(':'))==2 else s).replace(',',separator).replace('.',separator)
            output+=(str(i+1)+'\n' if fmt=='srt' else '')+normalize(start)+' --> '+normalize(end)+'\n'+content+'\n\n'
    with output_file(path,'converted','.'+fmt) as state: state['temp'].write_text(output,encoding='utf8')
    return state['output']

def markdown_to_html(text):
    try:
        import markdown_it
        md = markdown_it.MarkdownIt().enable('table').enable('strikethrough')
        body = md.render(text)
    except Exception:
        import html
        body = f'<pre>{html.escape(text)}</pre>'
    
    return f'''<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<style>
  @page {{
    size: A4 portrait;
    margin: 20mm 18mm 20mm 18mm;
  }}
  body {{
    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
    font-size: 14px;
    line-height: 1.6;
    color: #1f2328;
    background-color: #ffffff;
    padding: 0;
    margin: 0;
    word-wrap: break-word;
  }}
  h1, h2, h3, h4, h5, h6 {{
    margin-top: 24px;
    margin-bottom: 16px;
    font-weight: 600;
    line-height: 1.25;
    color: #1f2328;
  }}
  h1 {{ font-size: 2em; padding-bottom: 0.3em; border-bottom: 1px solid #d8dee4; }}
  h2 {{ font-size: 1.5em; padding-bottom: 0.3em; border-bottom: 1px solid #d8dee4; }}
  h3 {{ font-size: 1.25em; }}
  p, blockquote, ul, ol, dl, table, pre {{
    margin-top: 0;
    margin-bottom: 16px;
  }}
  code {{
    padding: 0.2em 0.4em;
    margin: 0;
    font-size: 85%;
    background-color: #f6f8fa;
    border-radius: 4px;
    font-family: ui-monospace, SFMono-Regular, "SF Mono", Menlo, Consolas, "Liberation Mono", monospace;
  }}
  pre {{
    padding: 16px;
    overflow: auto;
    font-size: 85%;
    line-height: 1.45;
    background-color: #f6f8fa;
    border: 1px solid #d0d7de;
    border-radius: 6px;
  }}
  pre code {{
    background-color: transparent;
    padding: 0;
    border: none;
  }}
  blockquote {{
    padding: 0 1em;
    color: #57606a;
    border-left: 0.25em solid #d0d7de;
    margin: 0 0 16px 0;
  }}
  table {{
    border-spacing: 0;
    border-collapse: collapse;
    width: 100%;
    margin-bottom: 16px;
    page-break-inside: auto;
  }}
  tr {{ page-break-inside: avoid; page-break-after: auto; }}
  table th, table td {{
    padding: 8px 12px;
    border: 1px solid #d0d7de;
  }}
  table tr:nth-child(2n) {{
    background-color: #f6f8fa;
  }}
  table th {{
    font-weight: 600;
    background-color: #f0f2f5;
  }}
  hr {{
    height: 0.2em;
    padding: 0;
    margin: 24px 0;
    background-color: #d8dee4;
    border: 0;
  }}
  ul, ol {{
    padding-left: 2em;
  }}
  img {{
    max-width: 100%;
    box-sizing: border-box;
  }}
</style>
</head>
<body>
{body}
</body>
</html>'''

def convert_md(path, fmt, params):
    text = Path(path).read_text(encoding='utf-8-sig', errors='replace')
    if fmt == 'html':
        html_content = markdown_to_html(text)
        with output_file(path, 'converted', '.html') as state:
            state['temp'].write_text(html_content, encoding='utf8')
        return state['output']
    
    if fmt == 'txt':
        clean = re.sub(r'#+\s*', '', text)
        with output_file(path, 'converted', '.txt') as state:
            state['temp'].write_text(clean, encoding='utf8')
        return state['output']
        
    if fmt == 'pdf':
        html_content = markdown_to_html(text)
        with output_file(path, 'converted', '.pdf') as state:
            bin_candidates = [
                BASE / 'doc2pdf-mac',
                Path(__file__).parent / 'doc2pdf-mac',
                Path('/Applications/DropDial.app/Contents/backend/doc2pdf-mac')
            ]
            temp_html = state['temp'].parent / f".tmp_{state['temp'].stem}.html"
            temp_html.write_text(html_content, encoding='utf8')
            converted = False
            for bin_path in bin_candidates:
                if bin_path.exists() and os.access(str(bin_path), os.X_OK):
                    try:
                        res = subprocess.run([str(bin_path), str(temp_html), str(state['temp'])], capture_output=True, timeout=30)
                        if res.returncode == 0 and state['temp'].exists() and state['temp'].stat().st_size > 0:
                            converted = True
                            break
                    except Exception: pass
            if not converted:
                swift_script = Path(__file__).parent / 'doc2pdf-mac.swift'
                if swift_script.exists():
                    try:
                        res = subprocess.run(['swift', str(swift_script), str(temp_html), str(state['temp'])], capture_output=True, timeout=30)
                        if res.returncode == 0 and state['temp'].exists() and state['temp'].stat().st_size > 0:
                            converted = True
                    except Exception: pass
            temp_html.unlink(missing_ok=True)
            if not converted:
                return text_pdf(path, text, params)
        return state['output']
        
    if fmt in ('docx', 'doc'):
        temp_pdf_out = convert_md(path, 'pdf', params)
        if Path(temp_pdf_out).exists():
            try:
                res = pdf_word(temp_pdf_out, params)
                Path(temp_pdf_out).unlink(missing_ok=True)
                return res
            except Exception: pass
        from docx import Document
        word = Document()
        for line in text.splitlines():
            word.add_paragraph(line)
        with output_file(path, 'converted', '.docx') as state:
            word.save(state['temp'])
        return state['output']
        
    if fmt == 'epub':
        title = Path(path).stem
        with output_file(path, 'converted', '.epub') as state:
            create_epub(title, [text], state['temp'])
        return state['output']

def create_epub(title, pages_text, target_path):
    with zipfile.ZipFile(target_path, 'w') as z:
        z.writestr('mimetype', 'application/epub+zip', compress_type=zipfile.ZIP_STORED)
        container_xml = '''<?xml version="1.0" encoding="UTF-8"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
    <rootfiles>
        <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>
    </rootfiles>
</container>'''
        z.writestr('META-INF/container.xml', container_xml, compress_type=zipfile.ZIP_DEFLATED)
        manifest_items = []
        spine_items = []
        for i, text in enumerate(pages_text):
            pid = f'page_{i+1}'
            fn = f'OEBPS/{pid}.xhtml'
            escaped = (text or '').replace('&', '&amp;').replace('<', '&lt;').replace('>', '&gt;')
            paragraphs = ''.join(f'<p>{p.strip()}</p>' for p in escaped.split('\n\n') if p.strip())
            xhtml = f'''<?xml version="1.0" encoding="utf-8"?>
<!DOCTYPE html>
<html xmlns="http://www.w3.org/1999/xhtml">
<head><title>{title} - Page {i+1}</title></head>
<body><h2>Page {i+1}</h2>{paragraphs}</body>
</html>'''
            z.writestr(fn, xhtml, compress_type=zipfile.ZIP_DEFLATED)
            manifest_items.append(f'<item id="{pid}" href="{pid}.xhtml" media-type="application/xhtml+xml"/>')
            spine_items.append(f'<itemref idref="{pid}"/>')
        content_opf = f'''<?xml version="1.0" encoding="utf-8"?>
<package xmlns="http://www.idpf.org/2007/opf" unique-identifier="BookId" version="2.0">
    <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
        <dc:title>{title}</dc:title>
        <dc:language>en</dc:language>
        <dc:identifier id="BookId">urn:uuid:dropdial-{abs(hash(title))}</dc:identifier>
    </metadata>
    <manifest>
        <item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/>
        {''.join(manifest_items)}
    </manifest>
    <spine toc="ncx">
        {''.join(spine_items)}
    </spine>
</package>'''
        z.writestr('OEBPS/content.opf', content_opf, compress_type=zipfile.ZIP_DEFLATED)
        toc_ncx = f'''<?xml version="1.0" encoding="UTF-8"?>
<ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1">
    <head><meta name="dtb:uid" content="urn:uuid:dropdial-{abs(hash(title))}"/></head>
    <docTitle><text>{title}</text></docTitle>
    <navMap>
        <navPoint id="navPoint-1" playOrder="1">
            <navLabel><text>Start</text></navLabel>
            <content src="page_1.xhtml"/>
        </navPoint>
    </navMap>
</ncx>'''
        z.writestr('OEBPS/toc.ncx', toc_ncx, compress_type=zipfile.ZIP_DEFLATED)

def pdf_to_pptx(path, params):
    fitz = get_fitz()
    import pptx
    from pptx.util import Pt
    doc = fitz.open(path)
    if len(doc) == 0:
        doc.close()
        raise ValueError(T('PDF has no pages'))
    prs = pptx.Presentation()
    blank_layout = prs.slide_layouts[6]
    for page in doc:
        prs.slide_width = Pt(page.rect.width)
        prs.slide_height = Pt(page.rect.height)
        slide = prs.slides.add_slide(blank_layout)
        pix = page.get_pixmap(dpi=150)
        img_bytes = pix.tobytes('png')
        slide.shapes.add_picture(io.BytesIO(img_bytes), 0, 0, width=Pt(page.rect.width), height=Pt(page.rect.height))
    doc.close()
    with output_file(path, 'converted', '.pptx') as state:
        prs.save(state['temp'])
    return state['output']

def pdf_to_excel(path, fmt, params):
    fitz = get_fitz()
    import openpyxl, csv
    doc = fitz.open(path)
    if len(doc) == 0:
        doc.close()
        raise ValueError(T('PDF has no pages'))
    all_rows = []
    for page in doc:
        tables = page.find_tables()
        found = False
        for tab in tables:
            found = True
            for r in tab.extract():
                all_rows.append([c if c is not None else '' for c in r])
        if not found:
            text = page.get_text()
            for line in text.splitlines():
                if not line.strip(): continue
                parts = line.split('\t') if '\t' in line else [p.strip() for p in re.split(r'\s{2,}', line.strip())]
                all_rows.append(parts)
    doc.close()
    if not all_rows:
        raise ValueError(T('This PDF has no selectable text; scanned documents need OCR first'))
    if fmt == 'csv':
        with output_file(path, 'converted', '.csv') as state:
            with open(state['temp'], 'w', encoding='utf-8-sig', newline='') as f:
                writer = csv.writer(f)
                writer.writerows(all_rows)
        return state['output']
    wb = openpyxl.Workbook()
    ws = wb.active
    ws.title = 'Sheet1'
    for row in all_rows:
        ws.append(row)
    with output_file(path, 'converted', '.xlsx') as state:
        wb.save(state['temp'])
    return state['output']

def pdf_to_epub(path, params):
    fitz = get_fitz()
    doc = fitz.open(path)
    if len(doc) == 0:
        doc.close()
        raise ValueError(T('PDF has no pages'))
    title = Path(path).stem
    pages_text = [page.get_text() for page in doc]
    doc.close()
    if not any(t.strip() for t in pages_text):
        raise ValueError(T('This PDF has no selectable text; scanned documents need OCR first'))
    with output_file(path, 'converted', '.epub') as state:
        create_epub(title, pages_text, state['temp'])
    return state['output']

def pdf_to_pages(path, params):
    docx_out = pdf_word(path, params)
    err = None
    with output_file(path, 'converted', '.pages') as state:
        if sys.platform == 'darwin':
            subprocess.run(['open', '-g', '-j', '-a', 'Pages'], capture_output=True)
            as_code = f'''
tell application "Pages"
    open (POSIX file "{docx_out}")
    delay 0.5
    save front document in (POSIX file "{state['temp']}")
    close front document saving no
end tell
'''
            try:
                res = subprocess.run(['osascript', '-e', as_code], capture_output=True, timeout=45)
                if not (res.returncode == 0 and state['temp'].exists() and state['temp'].stat().st_size > 0):
                    err = True
            except Exception:
                err = True
        else:
            err = True
    Path(docx_out).unlink(missing_ok=True)
    if err or not state.get('output'):
        raise ValueError(T('Apple Pages export requires macOS with the Pages app installed'))
    return state['output']

def convert_epub(path, fmt, params):
    fitz = get_fitz()
    doc = fitz.open(path)
    if fmt == 'txt':
        text = "\n\n".join(page.get_text() for page in doc)
        with output_file(path, 'converted', '.txt') as state:
            state['temp'].write_text(text, encoding='utf8')
        doc.close()
        return state['output']
    if fmt == 'pdf':
        pdf_bytes = doc.convert_to_pdf()
        pdf_doc = fitz.open("pdf", pdf_bytes)
        with output_file(path, 'converted', '.pdf') as state:
            pdf_doc.save(str(state['temp']), garbage=4, deflate=True)
        pdf_doc.close()
        doc.close()
        return state['output']
    if fmt in ('docx', 'doc'):
        pdf_out = convert_epub(path, 'pdf', params)
        res = pdf_word(pdf_out, params)
        Path(pdf_out).unlink(missing_ok=True)
        doc.close()
        return res
    if fmt == 'pages':
        pdf_out = convert_epub(path, 'pdf', params)
        res = pdf_to_pages(pdf_out, params)
        Path(pdf_out).unlink(missing_ok=True)
        doc.close()
        return res
    if fmt == 'md':
        text = "\n\n".join(page.get_text() for page in doc)
        with output_file(path, 'converted', '.md') as state:
            state['temp'].write_text(text, encoding='utf8')
        doc.close()
        return state['output']
    if fmt == 'html':
        text = "\n\n".join(page.get_text() for page in doc)
        html_content = markdown_to_html(text)
        with output_file(path, 'converted', '.html') as state:
            state['temp'].write_text(html_content, encoding='utf8')
        doc.close()
        return state['output']
    doc.close()
    raise ValueError(T('This document conversion is not supported'))

def convert(path,fmt,params):
    source=Path(path).suffix.lower()
    if source == '.epub':
        return convert_epub(path, fmt, params)
    if source in ('.srt','.vtt') or fmt in ('srt','vtt'): return subtitles(path,fmt,params)
    if source in ('.md', '.markdown'):
        return convert_md(path, fmt, params)
    if source=='.pdf':
        if fmt in ('jpg','png'): return render_pdf(path,fmt,params)
        if fmt=='docx': return pdf_word(path,params)
        if fmt=='pages': return pdf_to_pages(path,params)
        if fmt=='pptx': return pdf_to_pptx(path,params)
        if fmt in ('xlsx','csv'): return pdf_to_excel(path,fmt,params)
        if fmt=='epub': return pdf_to_epub(path,params)
        if fmt=='txt':
            doc=reader(path,params); text='\n\n'.join(page.extract_text() or '' for page in doc.pages)
            if not text.strip(): raise ValueError(T('This PDF has no selectable text; scanned documents need OCR first'))
            with output_file(path,'converted','.txt') as state: state['temp'].write_text(text,encoding='utf8')
            return state['output']
        if fmt=='md':
            fitz = get_fitz()
            doc=fitz.open(path)
            text='\n\n'.join(page.get_text() for page in doc)
            doc.close()
            if not text.strip(): raise ValueError(T('This PDF has no selectable text; scanned documents need OCR first'))
            with output_file(path,'converted','.md') as state: state['temp'].write_text(text,encoding='utf8')
            return state['output']
        if fmt=='html':
            fitz = get_fitz()
            doc=fitz.open(path)
            text='\n\n'.join(page.get_text() for page in doc)
            doc.close()
            if not text.strip(): raise ValueError(T('This PDF has no selectable text; scanned documents need OCR first'))
            html_content = markdown_to_html(text)
            with output_file(path,'converted','.html') as state: state['temp'].write_text(html_content,encoding='utf8')
            return state['output']
    if source=='.txt':
        text=Path(path).read_text(encoding='utf-8-sig', errors='replace')
        if fmt=='md':
            with output_file(path,'converted','.md') as state:
                state['temp'].write_text(text, encoding='utf8')
            return state['output']
        if fmt=='pdf': return text_pdf(path,text,params)
        if fmt=='epub':
            with output_file(path, 'converted', '.epub') as state:
                create_epub(Path(path).stem, [text], state['temp'])
            return state['output']
        if fmt in ('docx', 'pages'):
            from docx import Document
            doc=Document()
            for line in text.splitlines():
                doc.add_paragraph(line)
            if fmt == 'docx':
                with output_file(path,'converted','.docx') as state:
                    doc.save(state['temp'])
                return state['output']
            else:
                with tempfile.NamedTemporaryFile(suffix='.docx', delete=False) as tf:
                    doc.save(tf.name)
                    tmp_docx = tf.name
                err = None
                with output_file(path, 'converted', '.pages') as state:
                    if sys.platform == 'darwin':
                        subprocess.run(['open', '-g', '-j', '-a', 'Pages'], capture_output=True)
                        as_code = f'''
tell application "Pages"
    open (POSIX file "{tmp_docx}")
    delay 0.5
    save front document in (POSIX file "{state['temp']}")
    close front document saving no
end tell
'''
                        try:
                            res = subprocess.run(['osascript', '-e', as_code], capture_output=True, timeout=45)
                            if not (res.returncode == 0 and state['temp'].exists() and state['temp'].stat().st_size > 0):
                                err = True
                        except Exception:
                            err = True
                    else:
                        err = True
                Path(tmp_docx).unlink(missing_ok=True)
                if err or not state.get('output'):
                    raise ValueError(T('Apple Pages export requires macOS with the Pages app installed'))
                return state['output']
        if fmt in ('srt', 'vtt'):
            return subtitles(path, fmt, params)
        with output_file(path,'converted','.'+fmt) as state: save_image(text_image(text),state['temp'],fmt)
        return state['output']
    raise ValueError(T('This document conversion is not supported'))

def merge(paths,params):
    writer=PdfWriter()
    for path in paths: writer.append(reader(path,params))
    with output_file(paths[0],'merged','.pdf') as state:
        with open(state['temp'],'wb') as stream: writer.write(stream)
    writer.close(); return state['output']

def tool(path,action,params):
    import pdftools
    if action in pdftools.ACTIONS: return pdftools.ACTIONS[action](path,params)
    if action=='compress':
        doc=pdftools.open_pdf(path,params)
        quality=int(number(params,'quality',75)); edge=int(number(params,'maxEdge',2000)); target=int(number(params,'targetKB',0)*1024)
        seen=set()
        for page in doc:
            for item in page.get_images(full=True):
                xref=item[0]
                if xref in seen: continue
                seen.add(xref)
                extracted=doc.extract_image(xref)
                try:
                    image=Image.open(io.BytesIO(extracted['image'])).convert('RGB'); image.thumbnail((edge,edge))
                    data=io.BytesIO(); image.save(data,format='JPEG',quality=quality)
                    if len(data.getvalue())<len(extracted['image']): page.replace_image(xref,stream=data.getvalue())
                except (OSError,ValueError): pass
        with output_file(path,'compressed','.pdf') as state:
            doc.save(state['temp'],garbage=4,deflate=True)
            if target and state['temp'].stat().st_size>target: raise ValueError(T('Cannot reach the target size with these settings; lower the quality or size'))
        doc.close(); return state['output']
    doc=reader(path,params)
    if action=='splitPDF':
        group=int(number(params,'pagesPerFile',1))
        if group<1: raise ValueError(T('Pages per file must be greater than zero'))
        with output_folder(path,'split') as state:
            for start in range(0,len(doc.pages),group):
                writer=PdfWriter()
                for page in doc.pages[start:start+group]: writer.add_page(page)
                with open(state['temp']/f'pages-{start+1:04d}-{min(len(doc.pages),start+group):04d}.pdf','wb') as stream: writer.write(stream)
                writer.close()
        return state['output']
    writer=PdfWriter()
    order=params.get('pageOrder','').strip()
    indexes=[int(x.strip())-1 for x in order.split(',')] if order else list(range(len(doc.pages)))
    rotations=json.loads(params.get('rotations','{}'))
    for index in indexes:
        if index<0 or index>=len(doc.pages): raise ValueError(T('A page number is outside the document'))
        page=writer.add_page(doc.pages[index])
        angle=int(rotations.get(str(index+1),number(params,'rotation',0)))
        if angle: page.rotate(angle)
    if action=='removeMetadata':
        if not truth(params.get('remove','true')): writer.add_metadata({'/'+str(k).lstrip('/'):str(v) for k,v in json.loads(params.get('metadata','{}')).items() if v is not None})
        if '/Metadata' in writer._root_object: del writer._root_object['/Metadata']
    else: writer.add_metadata({str(k):str(v) for k,v in (doc.metadata or {}).items()})
    with output_file(path,action,'.pdf') as state:
        with open(state['temp'],'wb') as stream: writer.write(stream)
    writer.close(); return state['output']
