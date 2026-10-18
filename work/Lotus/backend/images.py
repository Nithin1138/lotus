from pathlib import Path
import json,math
from PIL import Image,ImageOps,ImageEnhance,ImageFilter,ImageDraw,ImageFont,ExifTags,ImageChops
from common import *
import imagetools

def convert(path,fmt,params):
    if fmt in ('pdf','docx'):
        from documents import images_document
        return images_document([path],fmt,params)
    image=open_image(path)
    with output_file(path,'converted','.'+fmt) as state:
        save_image(image,state['temp'],fmt,int(number(params,'quality',92)))
    return state['output']

def metadata(path):
    image=open_image(path)
    return {'Width':image.width,'Height':image.height,'Mode':image.mode,**{ExifTags.TAGS.get(k,str(k)):metadata_value(v) for k,v in image.getexif().items()}}

def metadata_value(value):
    if isinstance(value,bytes):return '0x'+value.hex()
    if isinstance(value,(list,tuple)):return [metadata_value(v) for v in value]
    if isinstance(value,(str,int,float)):return value
    if hasattr(value,'numerator') and hasattr(value,'denominator'):return float(value)
    return str(value)

def edit(image,params):
    import numpy as np,cv2
    alpha=image.getchannel('A') if 'A' in image.getbands() else None
    image=image.convert('RGB')
    image=ImageEnhance.Brightness(image).enhance(2**number(params,'exposure',0))
    image=ImageEnhance.Contrast(image).enhance(number(params,'contrast',1))
    image=ImageEnhance.Color(image).enhance(number(params,'saturation',1))
    arr=np.asarray(image).astype(np.float32)/255
    temperature=number(params,'temperature',0)/100
    arr[:,:,0]*=1+temperature*.25; arr[:,:,2]*=1-temperature*.25
    lum=arr.mean(axis=2,keepdims=True)
    arr+=number(params,'shadows',0)/100*(1-lum)**2*.4
    arr+=number(params,'highlights',0)/100*lum**2*.3
    haze=number(params,'dehaze',0)/100
    if haze:
        dark=cv2.erode(arr.min(axis=2),np.ones((15,15),np.uint8))
        transmission=np.maximum(.15,1-haze*dark)
        arr=(arr-1)/transmission[:,:,None]+1
    denoise=number(params,'denoise',0)
    if denoise: arr=cv2.fastNlMeansDenoisingColored((np.clip(arr,0,1)*255).astype(np.uint8),None,denoise,denoise,7,21)/255
    grain=number(params,'grain',0)/100
    if grain: arr+=np.random.default_rng(31).normal(0,grain*.1,arr.shape)
    image=Image.fromarray((np.clip(arr,0,1)*255).astype(np.uint8))
    clarity=number(params,'clarity',0)
    if clarity: image=image.filter(ImageFilter.UnsharpMask(radius=2,percent=int(clarity*2),threshold=3))
    if alpha: image.putalpha(alpha)
    annotations=params.get('annotations','').strip()
    if annotations:
        draw=ImageDraw.Draw(image)
        for item in json.loads(annotations):
            box=[int(v) for v in item.get('box',[0,0,100,100])]; color=item.get('color','#ff6500'); width=int(item.get('width',4))
            if item['type']=='text': draw.text((box[0],box[1]),item.get('text',''),fill=color,font=ImageFont.truetype(str(FONT),item.get('size',24)))
            elif item['type']=='ellipse': draw.ellipse(box,outline=color,width=width)
            elif item['type']=='line': draw.line(box,fill=color,width=width)
            else: draw.rectangle(box,outline=color,width=width)
    return image

def crop(image,params):
    ratio=params.get('ratio','free')
    raw_w=int(number(params,'width',0))
    raw_h=int(number(params,'height',0))
    if raw_w>0 and raw_h>0:
        w,h=raw_w,raw_h
    else:
        w,h=image.width,image.height
    if ratio not in ('','free',None):
        w,h=fit_ratio(w,h,ratio)
    align=params.get('alignment','center')
    if 'x' in params:
        x=int(number(params,'x',0))
    elif align in ('top_left','left'):
        x=0
    elif align in ('bottom_right','right'):
        x=image.width-w
    else:
        x=(image.width-w)//2
    if 'y' in params:
        y=int(number(params,'y',0))
    elif align in ('top_left','top'):
        y=0
    elif align in ('bottom_right','bottom'):
        y=image.height-h
    else:
        y=(image.height-h)//2
    x=max(0,min(x,image.width-1))
    y=max(0,min(y,image.height-1))
    w=max(1,min(w,image.width-x))
    h=max(1,min(h,image.height-y))
    return image.crop((x,y,x+w,y+h))

def rotate(image,params,required=True):
    angle,flip=orientation(params,required); turn=Image.Transpose
    if angle%90==0:
        if angle: image=image.transpose({90:turn.ROTATE_270,180:turn.ROTATE_180,270:turn.ROTATE_90}[int(angle)])
    else:
        canvas=params.get('expand','crop')
        if canvas not in ('crop','expand','keep'): raise ValueError('Invalid rotation canvas mode')
        source_width,source_height=image.size
        colour=None if canvas=='crop' else fill_colour(params)
        if colour is None: image=image.convert('RGBA'); colour=(0,0,0,0)
        elif image.mode not in ('RGB','RGBA'): image=image.convert('RGBA' if 'A' in image.getbands() else 'RGB')
        image=image.rotate(-angle,Image.Resampling.BICUBIC,expand=canvas!='keep',fillcolor=colour)
        if canvas=='crop':
            radians=math.radians(angle); cosine,sine=abs(math.cos(radians)),abs(math.sin(radians))
            inset=min(2,min(source_width,source_height)/8)
            scale=min((source_width-2*inset)/(source_width*cosine+source_height*sine),
                      (source_height-2*inset)/(source_width*sine+source_height*cosine))
            width=max(1,math.floor(source_width*scale)); height=max(1,math.floor(source_height*scale))
            x=(image.width-width)//2; y=(image.height-height)//2
            image=image.crop((x,y,x+width,y+height))
    if flip!='none': image=image.transpose(turn.FLIP_LEFT_RIGHT if flip=='horizontal' else turn.FLIP_TOP_BOTTOM)
    return image

def redact(image,params):
    image=image.copy()
    for r in rects(params,*image.size):
        box=(r['x'],r['y'],r['x']+r['width'],r['y']+r['height']); region=image.crop(box)
        style=r.get('style',params.get('style','solid'))
        if style=='blur': region=region.filter(ImageFilter.GaussianBlur(max(8,min(region.size)/12)))
        elif style=='pixelate':
            block=int(float(r.get('blockSize',params.get('blockSize',18))))
            if not 2<=block<=100: raise ValueError(T('Pixel block size must be 2–100 px'))
            region=region.resize((max(1,region.width//block),max(1,region.height//block)),Image.Resampling.BOX).resize(region.size,Image.Resampling.NEAREST)
        else: region=Image.new(image.mode,region.size,params.get('color','#000000'))
        image.paste(region,box[:2])
    return image

def framed(image,params):
    w=int(number(params,'canvasWidth',1400)); h=int(number(params,'canvasHeight',1000))
    if w<1 or h<1 or w*h>40_000_000: raise ValueError(T('The canvas size is invalid or too large'))
    background=params.get('backgroundImage','')
    if background: canvas=ImageOps.fit(open_image(background).convert('RGB'),(w,h)).convert('RGBA')
    else:
        first=params.get('background','#f0ebff'); second=params.get('gradient','')
        canvas=Image.new('RGBA',(w,h),first)
        if second:
            other=Image.new('RGBA',(w,h),second); mask=Image.linear_gradient('L').resize((w,h)); canvas=Image.composite(other,canvas,mask)
    if number(params,'backgroundBlur',0): canvas=canvas.filter(ImageFilter.GaussianBlur(number(params,'backgroundBlur',0)))
    padding=int(number(params,'padding',80)); inner=(w-2*padding,h-2*padding)
    if min(inner)<1: raise ValueError(T('The padding is larger than the canvas'))
    image=ImageOps.contain(image.convert('RGBA'),inner)
    radius=int(number(params,'radius',24)); mask=Image.new('L',image.size,0)
    ImageDraw.Draw(mask).rounded_rectangle((0,0,image.width,image.height),radius=radius,fill=255)
    mask=ImageChops.multiply(mask,image.getchannel('A'))
    image.putalpha(mask)
    x=(w-image.width)//2; y=(h-image.height)//2
    shadow=number(params,'shadow',20)
    if shadow:
        shade=Image.new('RGBA',canvas.size,(0,0,0,0)); block=Image.new('RGBA',image.size,(0,0,0,110)); block.putalpha(mask.point(lambda a:int(a*.35)))
        shade.alpha_composite(block,(x,y+int(shadow/2))); canvas=Image.alpha_composite(canvas,shade.filter(ImageFilter.GaussianBlur(shadow)))
    canvas.alpha_composite(image,(x,y)); return canvas

def collage(paths,params,preview=False):
    w=int(number(params,'canvasWidth',1600)); h=int(number(params,'canvasHeight',1200)); gap=int(number(params,'gap',16)); layout=params.get('layout','grid')
    if w*h>40_000_000 or min(w,h)<1: raise ValueError(T('The collage canvas size is invalid'))
    canvas=Image.new('RGBA',(w,h),params.get('background','#ffffff'))
    n=len(paths); cols=n if layout=='row' else 1 if layout=='column' else int(number(params,'columns',0)) or math.ceil(math.sqrt(n))
    cols=max(1,cols); rows=math.ceil(n/cols)
    if layout=='featured' and n>1:
        boxes=[(gap,gap,w//2-gap,h-gap)]+[(w//2+gap,gap+i*(h-gap)//(n-1),w-gap,gap+(i+1)*(h-gap)//(n-1)-gap) for i in range(n-1)]
    else:
        cw=(w-gap*(cols+1))//cols; ch=(h-gap*(rows+1))//rows
        if min(cw,ch)<1: raise ValueError(T('Too many images or the gap is too large'))
        boxes=[(gap+(i%cols)*(cw+gap),gap+(i//cols)*(ch+gap),gap+(i%cols)*(cw+gap)+cw,gap+(i//cols)*(ch+gap)+ch) for i in range(n)]
    for path,box in zip(paths,boxes):
        image=ImageOps.fit(open_image(path).convert('RGBA'),(box[2]-box[0],box[3]-box[1]))
        mask=Image.new('L',image.size,0); ImageDraw.Draw(mask).rounded_rectangle((0,0,*image.size),radius=int(number(params,'radius',0)),fill=255); image.putalpha(mask)
        canvas.alpha_composite(image,box[:2])
    if preview:return canvas
    with output_file(paths[0],'collage','.png') as state: canvas.save(state['temp'])
    return state['output']

def annotate(image, params):
    image = image.convert('RGBA')
    draw = ImageDraw.Draw(image)
    text = str(params.get('text', 'APPROVED') or 'APPROVED').strip()
    color = params.get('color', '#ff6500')
    font_size = max(20, min(image.width, image.height) // 20)
    pos_name = params.get('position', 'bottom_right')
    try:
        font = ImageFont.truetype(str(FONT), font_size) if FONT else ImageFont.load_default()
    except Exception:
        font = ImageFont.load_default()
    bbox = draw.textbbox((0, 0), text, font=font)
    tw = bbox[2] - bbox[0]
    th = bbox[3] - bbox[1]
    pad = max(16, int(font_size * 0.5))
    if pos_name == 'top_left': x, y = pad, pad
    elif pos_name == 'top_right': x, y = image.width - tw - pad, pad
    elif pos_name == 'bottom_left': x, y = pad, image.height - th - pad
    elif pos_name == 'center': x, y = (image.width - tw) // 2, (image.height - th) // 2
    else: x, y = image.width - tw - pad, image.height - th - pad
    badge = [x - 12, y - 8, x + tw + 12, y + th + 8]
    draw.rounded_rectangle(badge, radius=8, fill=(0, 0, 0, 180) if color != '#000000' else (255, 255, 255, 200))
    draw.text((x, y), text, fill=color, font=font)
    return image

def tool(path,action,params):
    if action=='makeIcon': return imagetools.make_icon(path,params)
    image=open_image(path,params.get('imageFrame'))
    fmt=Path(path).suffix.lstrip('.').lower()
    if fmt in ('svg','heif'): fmt='png'
    if fmt=='jpeg': fmt='jpg'
    if fmt=='tif': fmt='tiff'
    if action=='cropImage': image=crop(image,params)
    elif action=='redactImage': image=redact(image,params)
    elif action=='rotateImage': image=rotate(image,params)
    elif action=='resizeImage': image=imagetools.resize(image,params)
    elif action=='watermark': image=Image.alpha_composite(image.convert('RGBA'),imagetools.watermark_layer(image.size,params))
    elif action=='editImage': image=edit(image,params)
    elif action=='frameImage': image=framed(image,params); fmt='png'
    elif action=='annotateImage': image=annotate(image,params)
    elif action=='compress':
        max_edge=int(number(params,'maxEdge',0))
        if max_edge>0: image.thumbnail((max_edge,max_edge),Image.Resampling.LANCZOS)
    elif action=='removeMetadata': pass
    else: raise ValueError(T('Unknown image tool'))
    exif=None
    if action=='removeMetadata' and not truth(params.get('remove','true')):
        exif=image.getexif()
        fields=json.loads(params.get('metadata','{}')); names={v:k for k,v in ExifTags.TAGS.items()}
        for k,v in fields.items():
            key=names.get(k,int(k) if str(k).isdigit() else None)
            if key is None: continue
            if v is None or v=='': exif.pop(key,None)
            else:
                old=exif.get(key)
                if metadata_value(old)==v:continue
                if isinstance(old,bytes) and isinstance(v,str) and v.startswith('0x'):v=bytes.fromhex(v[2:])
                elif isinstance(old,int) and isinstance(v,str):v=int(v)
                elif hasattr(old,'numerator') and isinstance(v,str):v=float(v)
                exif[key]=v
    quality=int(number(params,'quality',75 if action=='compress' else 92))
    target=int(number(params,'targetKB',0)*1024)
    with output_file(path,action,'.'+fmt) as state:
        if action=='compress' and target:
            for attempt in range(10):
                best=None
                for q in range(quality,9,-5):
                    save_image(image,state['temp'],fmt,q)
                    if state['temp'].stat().st_size<=target: best=q; break
                if best is not None: break
                image=image.resize((max(1,int(image.width*.8)),max(1,int(image.height*.8))),Image.Resampling.LANCZOS)
            else: raise ValueError(T('Cannot reach the target file size; raise the target or reduce the dimensions'))
        else: save_image(image,state['temp'],fmt,quality,exif)
    return state['output']
