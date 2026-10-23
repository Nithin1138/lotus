from pathlib import Path
import io,json
from common import *

def open_pdf(path,params):
    fitz = get_fitz()
    doc=fitz.open(path)
    if doc.needs_pass and not doc.authenticate(params.get('password','')): raise ValueError(T('Wrong PDF password'))
    return doc

def password(path,params):
    fitz = get_fitz()
    locked=fitz.open(path).needs_pass; doc=open_pdf(path,params); mode=params.get('mode','add'); new=params.get('newPassword','')
    if mode=='add':
        if not new: raise ValueError(T('Enter the new password'))
        options={'encryption':fitz.PDF_ENCRYPT_AES_256,'user_pw':new,'owner_pw':new}; suffix='pdfPassword'
    else:
        if not locked: raise ValueError(T('This PDF has no password'))
        options={'encryption':fitz.PDF_ENCRYPT_NONE}; suffix='unlocked'
    with output_file(path,suffix,'.pdf') as state: doc.save(state['temp'],garbage=3,deflate=True,**options)
    doc.close(); return state['output']

def numbers(path,params):
    fitz = get_fitz()
    doc=open_pdf(path,params); size=number(params,'fontSize',10); start=int(number(params,'startAt',1)); header=params.get('header','').strip(); footer=params.get('footer','').strip()
    pattern=params.get('numberFormat','{n} / {total}').strip(); position=params.get('position','bottomRight')
    if not 6<=size<=48: raise ValueError(T('The font size must be between 6 and 48'))
    if not (pattern or header or footer): raise ValueError(T('Enter a page number format, a header or a footer'))
    def put(page,text,horizontal,vertical):
        if not text: return
        width=fitz.get_text_length(text,fontname='china-s',fontsize=size); rect=page.rect; margin=36
        x={'Left':margin,'Center':(rect.width-width)/2,'Right':rect.width-margin-width}[horizontal]; y=margin if vertical=='top' else rect.height-margin+size
        page.insert_text((x,y),text,fontname='china-s',fontsize=size,color=(.2,.2,.2))
    vertical='top' if position.startswith('top') else 'bottom'; horizontal=position[3:] if vertical=='top' else position[6:]
    for index,page in enumerate(doc):
        try: label=pattern.format(n=start+index,total=len(doc)+start-1) if pattern else ''
        except (KeyError,IndexError,ValueError): raise ValueError(T('The page number format is not valid; use {n} and {total}')) from None
        put(page,label,horizontal,vertical); put(page,header,'Center','top') if not (vertical=='top' and horizontal=='Center' and label) else None
        put(page,footer,'Center','bottom') if not (vertical=='bottom' and horizontal=='Center' and label) else None
    with output_file(path,'pdfNumbers','.pdf') as state: doc.save(state['temp'],garbage=3,deflate=True)
    doc.close(); return state['output']

def extract_images(path,params):
    doc=open_pdf(path,params); smallest=int(number(params,'minSize',64)); seen=set(); count=0
    with output_folder(path,'extractPdfImages',allow_empty=True) as state:
        for number_,page in enumerate(doc,1):
            for item in page.get_images(full=True):
                xref=item[0]
                if xref in seen: continue
                seen.add(xref); picture=doc.extract_image(xref)
                if min(picture['width'],picture['height'])<smallest: continue
                count+=1; (state['temp']/f'page{number_:03d}-image{count:03d}.{picture["ext"]}').write_bytes(picture['image'])
        if not count: raise ValueError(T('This PDF has no pictures to extract'))
    doc.close(); return state['output']

def watermark(path,params):
    import imagetools
    doc=open_pdf(path,params)
    for page in doc:
        # The mark is drawn at 1.5x the page size (sharp enough, much faster than 2x).
        layer=imagetools.watermark_layer((max(1,int(page.rect.width*1.5)),max(1,int(page.rect.height*1.5))),params); data=io.BytesIO(); layer.save(data,format='PNG')
        page.insert_image(page.rect,stream=data.getvalue(),overlay=True)
    with output_file(path,'watermark','.pdf') as state: doc.save(state['temp'],garbage=3,deflate=True)
    doc.close(); return state['output']

def redaction_marks(page,params):
    """Marks what to black out on one page: the boxes drawn on it (in the coordinates of the page as shown) and
    every place the given text appears. Returns how many were marked."""
    fitz = get_fitz()
    count=0
    regions = params.get('_parsed_regions') or json.loads(params.get('regions','') or '[]')
    for r in regions:
        if int(r.get('page',1))!=page.number+1: continue
        x,y,w,h=(float(r[k]) for k in ('x','y','width','height'))
        if w<=0 or h<=0: continue
        page.add_redact_annot((fitz.Rect(x,y,x+w,y+h)*page.derotation_matrix).normalize(),fill=(0,0,0)); count+=1
    text=params.get('findText','').strip()
    if text:
        for hit in page.search_for(text): page.add_redact_annot(hit,fill=(0,0,0)); count+=1
    return count

def redact(path,params):
    """Removes the marked text, pictures and drawings from the PDF (not just covers them) and puts black boxes there."""
    fitz = get_fitz()
    doc=open_pdf(path,params); total=0
    # Pre-parse the regions JSON once instead of per-page.
    regions_json = params.get('regions','') or '[]'
    parsed_regions = json.loads(regions_json) if isinstance(regions_json, str) else regions_json
    params_with_parsed = {**params, '_parsed_regions': parsed_regions}
    for page in doc:
        if redaction_marks(page,params_with_parsed):
            total+=1; page.apply_redactions(images=fitz.PDF_REDACT_IMAGE_PIXELS)
    if not total: raise ValueError(T('Nothing to redact: mark an area on a page, or type text that appears in the document'))
    with output_file(path,'redactPDF','.pdf') as state: doc.save(state['temp'],garbage=4,deflate=True,clean=True)
    doc.close(); return state['output']

def redaction_preview(path,params,folder):
    """One page as it is now and as it will look, plus its size in points (as shown) for placing boxes."""
    fitz = get_fitz()
    doc=open_pdf(path,params); index=max(0,min(len(doc)-1,int(number(params,'pageNumber',1))-1)); page=doc[index]; zoom=fitz.Matrix(1.3,1.3)
    source=Path(folder)/'source-page.png'; target=Path(folder)/'live-preview.png'
    page.get_pixmap(matrix=zoom).save(source)
    if redaction_marks(page,params): page.apply_redactions(images=fitz.PDF_REDACT_IMAGE_PIXELS)
    page.get_pixmap(matrix=zoom).save(target)
    result={'Preview':str(target),'SourcePreview':str(source),'PageWidth':page.rect.width,'PageHeight':page.rect.height,'Page':index+1,'Pages':len(doc)}
    doc.close(); return result

def organize(path, params):
    """Reorders, rotates, or extracts pages from a PDF."""
    fitz = get_fitz()
    doc = open_pdf(path, params)
    action = params.get('action', 'Reverse All Pages')
    total = len(doc)
    if total == 0:
        doc.close()
        raise ValueError(T('PDF has no pages'))
    
    page_order = params.get('pageOrder', '').strip()
    rotations_raw = params.get('rotations', '{}')
    rotations = json.loads(rotations_raw) if isinstance(rotations_raw, str) else (rotations_raw or {})
    rot = int(number(params, 'rotation', 0))

    if page_order:
        indexes = [int(x.strip()) - 1 for x in page_order.split(',') if x.strip()]
        for idx in indexes:
            if idx < 0 or idx >= total:
                raise ValueError(T('A page number is outside the document'))
        doc.select(indexes)
        if rot or rotations:
            for i, page in enumerate(doc):
                angle = int(rotations.get(str(i + 1), rot))
                if angle:
                    page.set_rotation((page.rotation + angle) % 360)
    else:
        if action == 'Reverse All Pages':
            doc.select(list(range(total - 1, -1, -1)))
        elif 'Rotate All 90' in action:
            for page in doc:
                page.set_rotation((page.rotation + 90) % 360)
        elif 'Rotate All 180' in action:
            for page in doc:
                page.set_rotation((page.rotation + 180) % 360)
        elif 'Rotate All 270' in action:
            for page in doc:
                page.set_rotation((page.rotation + 270) % 360)
        elif action == 'Extract Even Pages':
            even = [i for i in range(total) if (i + 1) % 2 == 0]
            if not even: raise ValueError(T('No even pages found'))
            doc.select(even)
        elif action == 'Extract Odd Pages':
            odd = [i for i in range(total) if (i + 1) % 2 != 0]
            if not odd: raise ValueError(T('No even pages found'))
            doc.select(odd)
        elif action == 'Delete First Page':
            if total <= 1: raise ValueError(T('Cannot delete the only page'))
            doc.delete_page(0)
        elif action == 'Delete Last Page':
            if total <= 1: raise ValueError(T('Cannot delete the only page'))
            doc.delete_page(total - 1)
        elif rot or rotations:
            for i, page in enumerate(doc):
                angle = int(rotations.get(str(i + 1), rot))
                if angle:
                    page.set_rotation((page.rotation + angle) % 360)
    
    with output_file(path, 'organized', '.pdf') as state:
        doc.save(state['temp'], garbage=3, deflate=True)
    doc.close()
    return state['output']

ACTIONS={'redactPDF':redact,'pdfPassword':password,'pdfNumbers':numbers,'extractPdfImages':extract_images,'watermark':watermark,'organizePDF':organize}
