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
        elif image.mode != 'RGB':
            image = image.convert('RGB')
        images.append(image)
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

def render_page(page, target_dpi=150):
    # Pre-compute the safe scale factor once.
    width,height=page.get_size()
    max_pixels = 80_000_000
    pixel_count = max(1, width * height)
    scale = target_dpi / 72.0
    # Clamp scale to stay within memory limits.
    if width * scale * height * scale > max_pixels:
        scale = min(scale, 0.999 * (max_pixels / pixel_count) ** 0.5)
    return page.render(scale=scale).to_pil()

def render_pdf(path,fmt,params):
    doc=pdfium.PdfDocument(str(path),password=params.get('password') or None)
    dpi = int(number(params, 'dpi', 200 if len(doc) <= 2 else 150))
    if len(doc)==1:
        with output_file(path,'page-1','.'+fmt) as state:
            image=render_page(doc[0], dpi); save_image(image,state['temp'],fmt,92)
    else:
        with output_folder(path,'pages-'+fmt) as state:
            for index in range(len(doc)):
                image=render_page(doc[index], dpi); save_image(image,state['temp']/f'page-{index+1:04d}.{fmt}',fmt,92)
    doc.close(); return state['output']

def _extract_page_tables(page, fitz):
    drawings = page.get_drawings()
    h_lines = []
    v_lines = []
    fills = []
    
    for d in drawings:
        r = fitz.Rect(d['rect'])
        t = d.get('type')
        if t in ('s', 'fs'):
            if r.width >= 60 and r.height <= 3.5:
                col = d.get('color')
                hex_col = '{:02X}{:02X}{:02X}'.format(int(col[0]*255), int(col[1]*255), int(col[2]*255)) if col else 'D0D5DD'
                h_lines.append({'rect': r, 'color': hex_col, 'y': (r.y0 + r.y1) / 2})
            elif r.height >= 20 and r.width <= 3.5:
                col = d.get('color')
                hex_col = '{:02X}{:02X}{:02X}'.format(int(col[0]*255), int(col[1]*255), int(col[2]*255)) if col else 'D0D5DD'
                v_lines.append({'rect': r, 'color': hex_col, 'x': (r.x0 + r.x1) / 2})
        elif t in ('f', 'fs'):
            fill = d.get('fill')
            if fill and not (fill[0] > 0.98 and fill[1] > 0.98 and fill[2] > 0.98) and r.width >= 15 and r.height >= 8:
                hex_col = '{:02X}{:02X}{:02X}'.format(int(fill[0]*255), int(fill[1]*255), int(fill[2]*255))
                fills.append({'rect': r, 'hex': hex_col})

    h_lines.sort(key=lambda l: l['y'])
    words = page.get_text('words')
    
    tables = []
    
    # 1. Grid tables from PyMuPDF
    try:
        tabs = page.find_tables()
        for t in tabs:
            if t.row_count >= 1 and t.col_count >= 1:
                tables.append({'bbox': fitz.Rect(t.bbox), 'grid_tab': t, 'type': 'grid'})
    except Exception: pass

    # 2. Horizontal bordered tables
    i = 0
    while i < len(h_lines):
        line = h_lines[i]
        group = [line]
        j = i + 1
        while j < len(h_lines):
            prev = group[-1]
            curr = h_lines[j]
            dy = curr['y'] - prev['y']
            same_x = abs(curr['rect'].x0 - prev['rect'].x0) <= 10 and abs(curr['rect'].x1 - prev['rect'].x1) <= 10
            if same_x and 12 <= dy <= 160:
                group.append(curr)
                j += 1
            else:
                break
        
        if len(group) >= 2:
            table_x0 = min(l['rect'].x0 for l in group)
            table_x1 = max(l['rect'].x1 for l in group)
            
            valid_rows = []
            for r_idx in range(len(group) - 1):
                r_top = group[r_idx]['y']
                r_bot = group[r_idx+1]['y']
                r_box = fitz.Rect(table_x0, r_top, table_x1, r_bot)
                r_fills = [f for f in fills if r_box.intersects(f['rect']) and (r_box & f['rect']).get_area() > 0.35 * f['rect'].get_area()]
                r_words = [w for w in words if r_top <= (w[1]+w[3])/2 <= r_bot and table_x0 - 4 <= w[0] <= table_x1 + 4]
                
                is_table_row = bool(r_fills)
                if not is_table_row and r_words:
                    xs = sorted([(w[0], w[2]) for w in r_words])
                    max_gap = 0
                    for k in range(len(xs) - 1):
                        gap = xs[k+1][0] - xs[k][1]
                        if gap > max_gap: max_gap = gap
                    if max_gap >= 22:
                        is_table_row = True
                
                if is_table_row:
                    valid_rows.append((r_top, r_bot, r_fills, r_words))

            if valid_rows:
                cur_t_rows = [valid_rows[0]]
                for vr in valid_rows[1:]:
                    if abs(vr[0] - cur_t_rows[-1][1]) <= 2.0:
                        cur_t_rows.append(vr)
                    else:
                        t_y0 = cur_t_rows[0][0]
                        t_y1 = cur_t_rows[-1][1]
                        tables.append({
                            'bbox': fitz.Rect(table_x0, t_y0, table_x1, t_y1),
                            'rows': cur_t_rows,
                            'border_color': group[0]['color'],
                            'type': 'h_rule'
                        })
                        cur_t_rows = [vr]
                if cur_t_rows:
                    t_y0 = cur_t_rows[0][0]
                    t_y1 = cur_t_rows[-1][1]
                    tables.append({
                        'bbox': fitz.Rect(table_x0, t_y0, table_x1, t_y1),
                        'rows': cur_t_rows,
                        'border_color': group[0]['color'],
                        'type': 'h_rule'
                    })
            i = j
        else:
            i += 1

    return tables

def _build_structured_docx_from_pdf(doc, out_path, fitz, has_text):
    from docx import Document
    from docx.shared import Inches, Pt, RGBColor
    from docx.enum.text import WD_ALIGN_PARAGRAPH
    from docx.enum.table import WD_TABLE_ALIGNMENT, WD_ALIGN_VERTICAL
    from docx.oxml import parse_xml, OxmlElement
    from docx.oxml.ns import nsdecls, qn

    def set_cell_margins(cell, top=100, bottom=100, left=140, right=140):
        tcPr = cell._tc.get_or_add_tcPr()
        tcMar = OxmlElement('w:tcMar')
        for m, val in [('top', top), ('bottom', bottom), ('left', left), ('right', right)]:
            node = OxmlElement(f'w:{m}')
            node.set(qn('w:w'), str(val))
            node.set(qn('w:type'), 'dxa')
            tcMar.append(node)
        tcPr.append(tcMar)

    def set_cell_shading(cell, color_hex):
        shd = parse_xml(f'<w:shd {nsdecls("w")} w:fill="{color_hex}"/>')
        cell._tc.get_or_add_tcPr().append(shd)

    def set_table_borders(table, color_hex='E3D6B8'):
        tblPr = table._tbl.tblPr
        borders = parse_xml(f'''
            <w:tblBorders {nsdecls("w")}>
                <w:top w:val="single" w:sz="6" w:space="0" w:color="{color_hex}"/>
                <w:bottom w:val="single" w:sz="6" w:space="0" w:color="{color_hex}"/>
                <w:insideH w:val="single" w:sz="6" w:space="0" w:color="{color_hex}"/>
                <w:left w:val="none"/>
                <w:right w:val="none"/>
                <w:insideV w:val="none"/>
            </w:tblBorders>
        ''')
        tblPr.append(borders)

    word = Document()
    for section in word.sections:
        section.top_margin = Inches(0.7)
        section.bottom_margin = Inches(0.7)
        section.left_margin = Inches(0.75)
        section.right_margin = Inches(0.75)

    if not has_text:
        for i, page in enumerate(doc):
            if i > 0: word.add_page_break()
            pix = page.get_pixmap(dpi=200)
            word.add_picture(io.BytesIO(pix.tobytes('png')), width=Inches(6.5))
        word.save(str(out_path))
        return

    for page_idx, page in enumerate(doc):
        if page_idx > 0:
            word.add_page_break()

        tables = _extract_page_tables(page, fitz)
        occupied_table_rects = [t['bbox'] for t in tables]

        # Collect vector bullet dots (small circles, dots, squares drawn as paths)
        bullet_dots = [d['rect'] for d in page.get_drawings() if (d['rect'].x1 - d['rect'].x0) < 14 and (d['rect'].y1 - d['rect'].y0) < 14 and d.get('type') in ('f', 'fs', 's')]

        # Collect page elements in reading order
        elements = []
        for t in tables:
            elements.append(('table', t['bbox'].y0, t))

        page_dict = page.get_text('dict')
        for b in page_dict.get('blocks', []):
            b_rect = fitz.Rect(b['bbox'])
            inside = any(b_rect.intersects(ob) and (b_rect & ob).get_area() > 0.4 * b_rect.get_area() for ob in occupied_table_rects)
            if not inside:
                if b.get('type') == 0: # text block
                    elements.append(('block', b_rect.y0, b))
                elif b.get('type') == 1 and b.get('image'): # image block
                    elements.append(('image', b_rect.y0, b))

        elements.sort(key=lambda x: x[1])

        for el_type, y_pos, el_data in elements:
            if el_type == 'image':
                try:
                    img_data = el_data.get('image')
                    if img_data:
                        w_pt = el_data['bbox'][2] - el_data['bbox'][0]
                        w_in = min(max(w_pt / 72.0, 1.0), 6.5)
                        word.add_picture(io.BytesIO(img_data), width=Inches(w_in))
                except Exception: pass

            elif el_type == 'block':
                lines = el_data.get('lines', [])
                if not lines: continue
                full_text = '\n'.join(''.join(s.get('text', '') for s in l.get('spans', [])) for l in lines).strip()
                if not full_text: continue
                
                full_text = full_text.replace('\u200b', '').replace('\ufeff', '')
                
                b_rect = fitz.Rect(el_data['bbox'])
                first_line_top = lines[0]['bbox'][1] if lines else b_rect.y0
                matched_dots = [dot for dot in bullet_dots if abs(dot.y0 - first_line_top) < 16 and dot.x1 <= b_rect.x0 + 8]
                has_vector_dot = bool(matched_dots)
                is_char_bullet = bool(re.match(r'^[•◦▪‣\-\*\u25a1\u25a0□]\s*', full_text))
                is_bullet = has_vector_dot or is_char_bullet
                is_nested = is_bullet and (has_vector_dot and (matched_dots[0].x0 > 68 or b_rect.x0 > 72))
                is_num_list = bool(re.match(r'^(\d+|[a-zA-Z])[\.\)\]]\s+', full_text))
                
                first_span = lines[0]['spans'][0] if (lines and lines[0].get('spans')) else {}
                span_font = (first_span.get('font') or '').lower()
                is_bold = bool(first_span.get('flags', 0) & 16 or 'bold' in span_font)
                span_size = first_span.get('size', 10.5)
                span_color = first_span.get('color', 0)
                
                is_heading = (not is_bullet and not is_num_list and len(lines) <= 2 and (
                    span_size >= 14.0 or
                    full_text.isupper() or
                    (len(full_text) < 55 and is_bold and not full_text.endswith('.'))
                ))

                if is_bullet:
                    p = word.add_paragraph(style='List Bullet')
                    if is_nested:
                        p.paragraph_format.left_indent = Inches(0.5)
                    p.paragraph_format.space_after = Pt(3.5)
                    p.paragraph_format.line_spacing = 1.15
                    
                    first_run = True
                    for l_idx, line in enumerate(lines):
                        if l_idx > 0 and not full_text.endswith('-'):
                            p.add_run(' ')
                        spans = line.get('spans', [])
                        for s_idx, span in enumerate(spans):
                            txt = span.get('text', '').replace('\u200b', '').replace('\ufeff', '')
                            if not txt: continue
                            
                            # Check gap between spans to avoid squished words
                            if s_idx > 0:
                                prev_s = spans[s_idx - 1]
                                gap = span.get('bbox', [0,0,0,0])[0] - prev_s.get('bbox', [0,0,0,0])[2]
                                prev_txt = prev_s.get('text', '')
                                if gap >= 2.0 and not prev_txt.endswith(' ') and not txt.startswith(' '):
                                    p.add_run(' ')
                                    
                            if first_run:
                                txt = re.sub(r'^[•◦▪‣\-\*\u25a1\u25a0□]\s*', '', txt)
                                if not txt.strip(): continue
                                
                            r = p.add_run(txt)
                            f_name = (span.get('font') or '').lower()
                            r.bold = bool(span.get('flags', 0) & 16 or 'bold' in f_name)
                            r.italic = bool(span.get('flags', 0) & 2 or 'italic' in f_name)
                            r.font.size = Pt(min(max(span.get('size', 10.0), 8.5), 13.0))
                            sc = span.get('color', 0)
                            if sc and sc != 0 and sc != 0xFFFFFF:
                                r.font.color.rgb = RGBColor((sc >> 16) & 0xFF, (sc >> 8) & 0xFF, sc & 0xFF)
                            if txt.strip():
                                first_run = False

                elif is_num_list:
                    p = word.add_paragraph(style='List Number')
                    p.paragraph_format.space_after = Pt(3.5)
                    p.paragraph_format.line_spacing = 1.15
                    clean_text = re.sub(r'^(\d+|[a-zA-Z])[\.\)\]]\s+', '', full_text).strip()
                    r = p.add_run(clean_text)
                    r.font.size = Pt(min(max(span_size, 9.0), 12.0))

                elif is_heading:
                    p = word.add_paragraph()
                    p.paragraph_format.space_before = Pt(11)
                    p.paragraph_format.space_after = Pt(4)
                    p.paragraph_format.keep_with_next = True
                    r = p.add_run(full_text)
                    r.bold = True
                    r.font.size = Pt(max(span_size, 11.5))
                    if span_color and span_color != 0 and span_color != 0xFFFFFF:
                        r.font.color.rgb = RGBColor((span_color >> 16) & 0xFF, (span_color >> 8) & 0xFF, span_color & 0xFF)
                    else:
                        r.font.color.rgb = RGBColor(0x1F, 0x2A, 0x37)

                else:
                    p = word.add_paragraph()
                    p.paragraph_format.space_after = Pt(5)
                    p.paragraph_format.line_spacing = 1.15
                    for l_idx, line in enumerate(lines):
                        if l_idx > 0 and not full_text.endswith('-'):
                            p.add_run(' ')
                        spans = line.get('spans', [])
                        for s_idx, span in enumerate(spans):
                            txt = span.get('text', '').replace('\u200b', '').replace('\ufeff', '')
                            if not txt: continue
                            
                            # Check gap between spans to avoid squished words
                            if s_idx > 0:
                                prev_s = spans[s_idx - 1]
                                gap = span.get('bbox', [0,0,0,0])[0] - prev_s.get('bbox', [0,0,0,0])[2]
                                prev_txt = prev_s.get('text', '')
                                if gap >= 2.0 and not prev_txt.endswith(' ') and not txt.startswith(' '):
                                    p.add_run(' ')

                            r = p.add_run(txt)
                            f_name = (span.get('font') or '').lower()
                            r.bold = bool(span.get('flags', 0) & 16 or 'bold' in f_name)
                            r.italic = bool(span.get('flags', 0) & 2 or 'italic' in f_name)
                            r.font.size = Pt(min(max(span.get('size', 10.0), 8.5), 14.0))
                            sc = span.get('color', 0)
                            if sc and sc != 0 and sc != 0xFFFFFF:
                                r.font.color.rgb = RGBColor((sc >> 16) & 0xFF, (sc >> 8) & 0xFF, sc & 0xFF)

            elif el_type == 'table':
                t_info = el_data
                if t_info.get('type') == 'grid':
                    grid_tab = t_info['grid_tab']
                    extracted = grid_tab.extract()
                    if not extracted: continue
                    r_cnt = len(extracted)
                    c_cnt = max(len(r) for r in extracted) if r_cnt > 0 else 0
                    if r_cnt == 0 or c_cnt == 0: continue
                    tbl = word.add_table(rows=r_cnt, cols=c_cnt)
                    tbl.alignment = WD_TABLE_ALIGNMENT.CENTER
                    set_table_borders(tbl, 'D0D5DD')
                    for r_idx, r_data in enumerate(extracted):
                        for c_idx, val in enumerate(r_data):
                            if c_idx < c_cnt:
                                cell = tbl.cell(r_idx, c_idx)
                                cell.text = (val or '').strip().replace('\u200b', '').replace('\ufeff', '')
                                set_cell_margins(cell)
                                if r_idx == 0:
                                    set_cell_shading(cell, 'F2F4F7')
                                    for p in cell.paragraphs:
                                        for run in p.runs: run.bold = True
                    p_sp = word.add_paragraph()
                    p_sp.paragraph_format.space_after = Pt(6)

                elif t_info.get('type') == 'h_rule':
                    rows_data = t_info['rows']
                    r_cnt = len(rows_data)
                    if r_cnt == 0: continue
                    
                    # Determine column splits dynamically (supports 2, 3, 4, N columns)
                    col_x_bounds = set()
                    col_x_bounds.add(t_info['bbox'].x0)
                    col_x_bounds.add(t_info['bbox'].x1)
                    
                    for _, _, r_fills, _ in rows_data:
                        for f in r_fills:
                            col_x_bounds.add(f['rect'].x0)
                            col_x_bounds.add(f['rect'].x1)
                    
                    all_r_words = [w for _, _, _, r_words in rows_data for w in r_words]
                    if len(col_x_bounds) <= 2 and all_r_words:
                        x_intervals = sorted([(w[0], w[2]) for w in all_r_words], key=lambda x: x[0])
                        merged = []
                        for start, end in x_intervals:
                            if not merged or start > merged[-1][1] + 12:
                                merged.append([start, end])
                            else:
                                merged[-1][1] = max(merged[-1][1], end)
                        if len(merged) > 1:
                            for k in range(len(merged) - 1):
                                col_x_bounds.add((merged[k][1] + merged[k+1][0]) / 2.0)
                    
                    sorted_splits = sorted(col_x_bounds)
                    clean_splits = [sorted_splits[0]]
                    for s in sorted_splits[1:]:
                        if s - clean_splits[-1] >= 25:
                            clean_splits.append(s)
                    if len(clean_splits) < 2:
                        clean_splits = [t_info['bbox'].x0, t_info['bbox'].x1]
                    
                    c_cnt = len(clean_splits) - 1
                    if c_cnt <= 0: c_cnt = 1
                    
                    tbl = word.add_table(rows=r_cnt, cols=c_cnt)
                    tbl.alignment = WD_TABLE_ALIGNMENT.CENTER
                    set_table_borders(tbl, t_info.get('border_color', 'E3D6B8'))

                    for r_idx, (r_top, r_bot, r_fills, r_words) in enumerate(rows_data):
                        for c_idx in range(c_cnt):
                            x_left = clean_splits[c_idx]
                            x_right = clean_splits[c_idx+1]
                            col_w_in = (x_right - x_left) / 72.0
                            
                            c_words = [w for w in r_words if x_left - 4 <= (w[0]+w[2])/2 < x_right + 4]
                            
                            def words_to_lines(ws):
                                lines_dict = {}
                                for w in ws:
                                    l_key = (w[5], w[6])
                                    lines_dict.setdefault(l_key, []).append(w)
                                sorted_lines = sorted(lines_dict.values(), key=lambda line_ws: line_ws[0][1])
                                return [' '.join(w[4] for w in l).replace('\u200b', '').replace('\ufeff', '') for l in sorted_lines]

                            cell_text = '\n'.join(words_to_lines(c_words)).strip()
                            cell = tbl.cell(r_idx, c_idx)
                            cell.width = Inches(col_w_in)
                            set_cell_margins(cell, top=90, bottom=90, left=120, right=120)

                            cell_box = fitz.Rect(x_left, r_top, x_right, r_bot)
                            c_fill = [f for f in r_fills if cell_box.intersects(f['rect']) and (cell_box & f['rect']).get_area() > 0.3 * cell_box.get_area()]
                            if c_fill:
                                set_cell_shading(cell, c_fill[0]['hex'])

                            cell.text = cell_text
                            for p in cell.paragraphs:
                                p.paragraph_format.space_after = Pt(2)
                                p.paragraph_format.line_spacing = 1.15
                                for run in p.runs:
                                    run.font.size = Pt(10)
                                    if c_idx == 0 or r_idx == 0:
                                        run.bold = True

                    p_sp = word.add_paragraph()
                    p_sp.paragraph_format.space_after = Pt(6)

    word.save(str(out_path))

def _clean_docx_list_markers(file_path):
    try:
        from docx import Document
        word_doc = Document(str(file_path))
        modified = False

        def clean_text_str(s):
            return s.replace('\u200b', '').replace('\ufeff', '')

        for p in word_doc.paragraphs:
            p_style = (p.style.name or '').lower() if p.style else ''
            is_list = 'list' in p_style or 'bullet' in p_style
            first_run = True
            for run in p.runs:
                if run.text:
                    orig = run.text
                    clean = clean_text_str(orig)
                    if is_list and first_run:
                        clean = re.sub(r'^\s*[•◦▪‣\-\*\u25a1\u25a0□]\s*', '', clean)
                    if clean != orig:
                        run.text = clean
                        modified = True
                    if clean.strip():
                        first_run = False

        for table in word_doc.tables:
            for row in table.rows:
                for cell in row.cells:
                    for p in cell.paragraphs:
                        for run in p.runs:
                            if run.text:
                                orig = run.text
                                clean = clean_text_str(orig)
                                if clean != orig:
                                    run.text = clean
                                    modified = True

        if modified:
            word_doc.save(str(file_path))
    except Exception: pass

def pdf_word(path,params):
    fitz = get_fitz()
    from pdftools import open_pdf
    doc=open_pdf(path,params)
    with output_file(path,'converted','.docx') as state:
        has_text = any(page.get_text().strip() for page in doc)
        converted = False

        # 1. Primary Engine: Structured PyMuPDF Engine (100% fidelity on tables, bullets, headings, and spaces)
        if has_text:
            try:
                _build_structured_docx_from_pdf(doc, state['temp'], fitz, has_text)
                if state['temp'].exists() and state['temp'].stat().st_size > 0:
                    converted = True
            except Exception:
                pass

        # 2. General Fallback: pdf2docx with safe table settings
        if not converted and has_text:
            try:
                from pdf2docx import Converter
                converter=Converter(str(path),password=params.get('password',''))
                try:
                    converter.convert(
                        str(state['temp']),
                        multi_processing=False,
                        extract_stream_table=False,
                        delete_end_line_hyphen=True,
                        parse_lattice_table=True,
                        parse_stream_table=False
                    )
                    if state['temp'].exists() and state['temp'].stat().st_size > 0:
                        converted = True
                finally:
                    converter.close()
            except Exception:
                pass

        # 3. Final Fallback: structured image generator if all else failed
        if not converted:
            _build_structured_docx_from_pdf(doc, state['temp'], fitz, has_text)

        # 4. Post-process to remove duplicate bullet characters and zero-width spaces
        if state['temp'].exists():
            _clean_docx_list_markers(state['temp'])

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
    page_w, page_h = 595, 842
    margin = 54
    max_w = page_w - (margin * 2)
    font_size = 11
    line_h = 16
    para_space = 8

    # Word-boundary wrapping to prevent awkward character splits
    wrapped_lines = []
    paragraphs = text.splitlines() or ['']
    for para in paragraphs:
        para_clean = para.strip()
        if not para_clean:
            wrapped_lines.append(('', True))
            continue
        words = para_clean.split(' ')
        curr_line = ''
        for w in words:
            test = f"{curr_line} {w}".strip() if curr_line else w
            if font.text_length(test, fontsize=font_size) <= max_w:
                curr_line = test
            else:
                if curr_line:
                    wrapped_lines.append((curr_line, False))
                if font.text_length(w, fontsize=font_size) > max_w:
                    sub = ''
                    for ch in w:
                        if font.text_length(sub + ch, fontsize=font_size) > max_w:
                            wrapped_lines.append((sub, False))
                            sub = ch
                        else:
                            sub += ch
                    curr_line = sub
                else:
                    curr_line = w
        if curr_line:
            wrapped_lines.append((curr_line, True))

    y = margin
    page = doc.new_page(width=page_w, height=page_h)
    page.insert_font(fontname='DocumentFont', fontfile=str(FONT))
    page_num = 1

    for line_text, is_para_end in wrapped_lines:
        if y + line_h > page_h - margin - 20:
            page.insert_text((page_w - margin - 30, page_h - margin + 10), str(page_num), fontname='DocumentFont', fontsize=9, color=(0.4, 0.4, 0.4))
            page = doc.new_page(width=page_w, height=page_h)
            page.insert_font(fontname='DocumentFont', fontfile=str(FONT))
            page_num += 1
            y = margin

        if line_text:
            page.insert_text((margin, y + font_size), line_text, fontname='DocumentFont', fontsize=font_size)
            y += line_h
        if is_para_end:
            y += para_space

    page.insert_text((page_w - margin - 30, page_h - margin + 10), str(page_num), fontname='DocumentFont', fontsize=9, color=(0.4, 0.4, 0.4))

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

    # Set slide dimensions once based on dominant page dimensions
    first_page = doc[0]
    slide_w = Pt(first_page.rect.width)
    slide_h = Pt(first_page.rect.height)

    prs = pptx.Presentation()
    prs.slide_width = slide_w
    prs.slide_height = slide_h
    blank_layout = prs.slide_layouts[6]

    for page in doc:
        slide = prs.slides.add_slide(blank_layout)
        # Use crisp 200 DPI for presentation sharpness
        pix = page.get_pixmap(dpi=200)
        img_bytes = pix.tobytes('png')
        slide.shapes.add_picture(
            io.BytesIO(img_bytes),
            0,
            0,
            width=Pt(page.rect.width),
            height=Pt(page.rect.height)
        )
    doc.close()
    with output_file(path, 'converted', '.pptx') as state:
        prs.save(state['temp'])
    return state['output']

def pdf_to_excel(path, fmt, params):
    fitz = get_fitz()
    import openpyxl, csv
    from openpyxl.styles import Font, PatternFill, Alignment, Border, Side
    from openpyxl.utils import get_column_letter

    doc = fitz.open(path)
    if len(doc) == 0:
        doc.close()
        raise ValueError(T('PDF has no pages'))
    all_rows = []
    for page in doc:
        tabs = _extract_page_tables(page, fitz)
        found = False
        for t in tabs:
            found = True
            if t.get('type') == 'grid':
                for r in t['grid_tab'].extract():
                    all_rows.append([c if c is not None else '' for c in r])
            elif t.get('type') == 'h_rule':
                split_x = None
                for _, _, r_fills, _ in t['rows']:
                    if r_fills:
                        split_x = r_fills[0]['rect'].x1
                        break
                if split_x is None:
                    split_x = t['bbox'].x0 + (t['bbox'].x1 - t['bbox'].x0) * 0.35
                for _, _, _, r_words in t['rows']:
                    col1_words = [w for w in r_words if (w[0]+w[2])/2 < split_x]
                    col2_words = [w for w in r_words if (w[0]+w[2])/2 >= split_x]
                    def words_to_str(ws):
                        lines_dict = {}
                        for w in ws:
                            lines_dict.setdefault((w[5], w[6]), []).append(w)
                        sorted_lines = sorted(lines_dict.values(), key=lambda lw: lw[0][1])
                        return ' '.join(' '.join(w[4] for w in l) for l in sorted_lines).replace('\u200b', '').strip()
                    c1 = words_to_str(col1_words)
                    c2 = words_to_str(col2_words)
                    all_rows.append([c1, c2])
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
    ws.views.sheetView[0].showGridLines = True

    header_fill = PatternFill(start_color="F2F4F7", end_color="F2F4F7", fill_type="solid")
    header_font = Font(name="Segoe UI", size=11, bold=True, color="1F2328")
    regular_font = Font(name="Segoe UI", size=10, color="1F2328")
    thin_border = Border(
        left=Side(style='thin', color='E1E4EA'),
        right=Side(style='thin', color='E1E4EA'),
        top=Side(style='thin', color='E1E4EA'),
        bottom=Side(style='thin', color='E1E4EA')
    )

    for r_idx, row in enumerate(all_rows, start=1):
        parsed_row = []
        for val in row:
            v_str = str(val).strip()
            # Try to convert numeric strings so Excel treats them as numbers
            if (v_str.replace(',', '').replace('.', '', 1).isdigit() and not v_str.startswith('0')) or v_str == '0':
                try:
                    clean_num = v_str.replace(',', '')
                    parsed_row.append(float(clean_num) if '.' in clean_num else int(clean_num))
                    continue
                except ValueError: pass
            parsed_row.append(v_str)

        ws.append(parsed_row)

        for c_idx in range(1, len(parsed_row) + 1):
            cell = ws.cell(row=r_idx, column=c_idx)
            cell.border = thin_border
            if r_idx == 1:
                cell.fill = header_fill
                cell.font = header_font
                cell.alignment = Alignment(vertical="center", horizontal="left")
            else:
                cell.font = regular_font
                if isinstance(cell.value, (int, float)):
                    cell.alignment = Alignment(vertical="center", horizontal="right")
                else:
                    cell.alignment = Alignment(vertical="center", horizontal="left")

    for col in ws.columns:
        col_letter = get_column_letter(col[0].column)
        max_len = 0
        for cell in col:
            val_len = len(str(cell.value or ''))
            if val_len > max_len: max_len = val_len
        ws.column_dimensions[col_letter].width = max(max_len + 4, 12)

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
    try
        set myDoc to open (POSIX file "{docx_out}")
        delay 0.5
        save myDoc in (POSIX file "{state['temp']}")
        close myDoc saving no
    end try
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
                    raw_img = Image.open(io.BytesIO(extracted['image']))
                    if 'A' in raw_img.getbands():
                        bg = Image.new('RGB', raw_img.size, (255, 255, 255))
                        if raw_img.mode != 'RGBA':
                            raw_img = raw_img.convert('RGBA')
                        bg.paste(raw_img, mask=raw_img.getchannel('A'))
                        image = bg
                    else:
                        image = raw_img.convert('RGB')
                    image.thumbnail((edge, edge), Image.Resampling.LANCZOS)
                    data = io.BytesIO()
                    image.save(data, format='JPEG', quality=quality)
                    if len(data.getvalue()) < len(extracted['image']):
                        page.replace_image(xref, stream=data.getvalue())
                except (OSError, ValueError): pass
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
