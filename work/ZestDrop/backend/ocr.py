from pathlib import Path
import json,re,tempfile,shutil
from PIL import Image
from common import *

SCRIPT=Path(__file__).with_name('ocr.ps1')
MAC_OCR=Path(__file__).with_name('ocr-mac')
CJK=re.compile(r'(?<=[　-〿㐀-鿿＀-￯])\s+(?=[　-〿㐀-鿿＀-￯])')
LIMIT=8000

def recognise(files,language):
    """Read text from image or PDF files. Returns one entry per page with width, height, and recognized lines."""
    with tempfile.TemporaryDirectory(prefix='lotus-ocr-') as temp:
        out=Path(temp)/'result.json'
        if os.name != 'nt' and MAC_OCR.is_file():
            process([str(MAC_OCR),'-Out',str(out),'-Language',language or 'en',*files],timeout=900)
            data=json.loads(out.read_text(encoding='utf-8'))
        else:
            process(['powershell.exe','-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',SCRIPT,'-Language',language or 'en','-Out',out,*files],timeout=900)
            data=json.loads(out.read_text(encoding='utf-8-sig'))
    if isinstance(data,dict) and data.get('error')=='noengine': raise ValueError(T('Windows 没有可用的文字识别语言。请在“设置 → 时间和语言 → 语言和区域”中为所需语言安装“光学字符识别”。'))
    for page in data:
        for line in page['lines']: line['text']=CJK.sub('',line['text'])
    return data

def prepared(image,folder,name):
    """Pictures are saved as JPEG for fast loading if needed on Windows."""
    if max(image.size)>LIMIT: image=image.copy(); image.thumbnail((LIMIT,LIMIT))
    target=Path(folder)/name; image.convert('RGB').save(target,format='JPEG',quality=95); return target,image.size

def page_text(page): return '\n'.join(line['text'] for line in page['lines'])

def create_text_pdf(pages,target,keep_background=False,source_images=None):
    """Creates a PDF. By default: pure white background with visible, crisp vector text."""
    import pymupdf as fitz
    doc=fitz.open()
    font_name='DocFont' if FONT and FONT.exists() else 'helv'
    for idx,p in enumerate(pages):
        pw=p['width']*0.75; ph=p['height']*0.75
        page=doc.new_page(width=pw,height=ph)
        if font_name=='DocFont':
            page.insert_font(fontname='DocFont',fontfile=str(FONT))
        if keep_background and source_images and idx<len(source_images):
            page.insert_image(page.rect,filename=str(source_images[idx]))
            for line in p['lines']:
                text=line['text'].strip()
                if not text or line['h']<=0: continue
                size=max(4,line['h']*0.75*0.8)
                page.insert_text((line['x']*0.75,(line['y']+line['h'])*0.75-line['h']*0.75*0.15),text,fontname=font_name,fontsize=size,render_mode=3)
        else:
            # Default: ONLY TEXT, WHITE BACKGROUND
            for line in p['lines']:
                text=line['text'].strip()
                if not text: continue
                size=max(7,line['h']*0.75*0.85)
                x=line['x']*0.75
                y=line['y']*0.75+size*0.85
                page.insert_text((x,y),text,fontname=font_name,fontsize=size,color=(0.07,0.07,0.07))
    doc.save(str(target),garbage=3,deflate=True)
    doc.close()

def run(path,action,params):
    language=params.get('language','en').strip()
    output=params.get('output','pdf').strip().lower()
    keep_bg=truth(params.get('keepBackground','false'))

    # Fast direct path on macOS using native Vision OCR
    if os.name != 'nt' and MAC_OCR.is_file():
        pages=recognise([str(path)],language)
        text='\n\n'.join(page_text(p) for p in pages)
        if not text.strip(): raise ValueError(T('没有识别到文字'))
        if output=='pdf':
            with output_file(path,action,'.pdf') as state:
                create_text_pdf(pages,state['temp'],keep_background=keep_bg)
            return state['output']
        with output_file(path,action,'.txt') as state:
            state['temp'].write_text(text,encoding='utf8')
        return state['output']

    # Windows fallback
    with tempfile.TemporaryDirectory(prefix='lotus-ocr-input-') as temp:
        if action=='ocrImage':
            images=[prepared(open_image(path,params.get('imageFrame')),temp,'page-1.jpg')]
            pages=recognise([str(images[0][0])],language)
            text=page_text(pages[0])
            if output=='pdf':
                with output_file(path,'ocrImage','.pdf') as state:
                    create_text_pdf(pages,state['temp'],keep_background=keep_bg,source_images=[images[0][0]])
                return state['output']
        else:
            import pypdfium2 as pdfium
            source=pdfium.PdfDocument(str(path),password=params.get('password') or None); count=len(source)
            if count>200: raise ValueError(T('一次最多识别 200 页'))
            files=[]; sizes=[]
            for index in range(count):
                image=source[index].render(scale=150/72).to_pil(); target,size=prepared(image,temp,f'page-{index+1}.jpg'); files.append(str(target)); sizes.append(size)
            source.close(); pages=recognise(files,language); text='\n\n'.join(page_text(page) for page in pages)
            if output=='pdf':
                with output_file(path,'ocrPDF','.pdf') as state:
                    create_text_pdf(pages,state['temp'],keep_background=keep_bg,source_images=files)
                return state['output']
    if not text.strip(): raise ValueError(T('没有识别到文字'))
    with output_file(path,action,'.txt') as state: state['temp'].write_text(text,encoding='utf8')
    return state['output']
