from pathlib import Path
from contextlib import contextmanager
import io, json, os, re, shutil, subprocess, sys, tempfile, time, uuid
from functools import lru_cache

BASE=Path(__file__).resolve().parent.parent

_BIN_CACHE = {}
def _find_binary(name):
    if name in _BIN_CACHE:
        return _BIN_CACHE[name]
    ext = '.exe' if os.name == 'nt' else ''
    direct = BASE / f'runtime/ffmpeg/{name}{ext}'
    if direct.is_file():
        _BIN_CACHE[name] = direct
        return direct
    bin_cand = BASE / f'runtime/ffmpeg/bin/{name}{ext}'
    if bin_cand.is_file():
        _BIN_CACHE[name] = bin_cand
        return bin_cand
    found = shutil.which(name)
    res = Path(found) if found else direct
    _BIN_CACHE[name] = res
    return res

class _LazyBinary:
    __slots__ = ('_name', '_cached')
    def __init__(self, name):
        self._name = name
        self._cached = None
    def _resolve(self):
        if self._cached is None:
            self._cached = _find_binary(self._name)
        return self._cached
    def __str__(self):
        return str(self._resolve())
    def __fspath__(self):
        return str(self._resolve())
    def __repr__(self):
        return str(self)

FFMPEG = _LazyBinary('ffmpeg')
FFPROBE = _LazyBinary('ffprobe')

def get_fitz():
    try:
        import pymupdf as fitz
        return fitz
    except ImportError:
        pass
    try:
        import fitz
        return fitz
    except ImportError:
        pass

    # Search local runtime site-packages in parent directories if running embedded
    try:
        _base = Path(__file__).resolve().parent.parent
        for _cand in [
            _base / 'runtime' / 'python' / 'Lib' / 'site-packages',
            _base / 'runtime' / 'Lib' / 'site-packages',
            _base / 'runtime' / 'site-packages',
        ]:
            if _cand.exists() and str(_cand) not in sys.path:
                sys.path.insert(0, str(_cand))
                try:
                    import pymupdf as fitz
                    return fitz
                except ImportError:
                    pass
                try:
                    import fitz
                    return fitz
                except ImportError:
                    pass
    except Exception:
        pass

    raise ImportError(T('PyMuPDF is required for document and PDF operations. Run: pip install pymupdf'))

IMAGE_EXT={'.jpg','.jpeg','.png','.webp','.heic','.heif','.tif','.tiff','.svg','.avif','.bmp','.ico'}
VIDEO_EXT={'.mp4','.mov','.mkv','.webm','.avi','.wmv','.gif'}
AUDIO_EXT={'.mp3','.m4a','.wav','.flac','.ogg','.opus','.aiff','.aif','.wma','.aac'}
# Interface language for messages, chosen in the app and passed to each worker. Chinese strings double as keys.
from translations import EN
_LANG = os.environ.get('DROPDIAL_LANG', 'zh')
def T(text):
    return EN.get(text, text) if _LANG == 'en' else text

# Staged outputs carry the app's job id, so cancelling one job never removes another job's files.
JOB=re.sub(r'[^0-9A-Za-z]','',os.environ.get('DROPDIAL_JOB', ''))[:32]
TEMP_PREFIX='.dropdial-'+(JOB+'-' if JOB else '')
_FONTS=['C:/Windows/Fonts/msyh.ttc','C:/Windows/Fonts/arial.ttf','C:/Windows/Fonts/simsun.ttc'] if os.name=='nt' else [
    '/System/Library/Fonts/PingFang.ttc','/System/Library/Fonts/Supplemental/Arial.ttf','/Library/Fonts/Arial.ttf','/System/Library/Fonts/Helvetica.ttc']
FONT=next((Path(x) for x in _FONTS if Path(x).exists()),None)

# O(1) extension -> category lookup table (faster than repeated set-in checks)
_CATEGORY_MAP = {}
for _ext in IMAGE_EXT: _CATEGORY_MAP[_ext] = 'image'
for _ext in VIDEO_EXT: _CATEGORY_MAP[_ext] = 'video'
for _ext in AUDIO_EXT: _CATEGORY_MAP[_ext] = 'audio'
for _ext in ('.ppt','.pptx','.pptm','.pps','.ppsx','.odp','.doc','.docx','.docm','.rtf','.rtfd','.odt','.xls','.xlsx','.xlsm','.xlsb','.ods','.csv','.tsv','.pages','.key','.numbers'): _CATEGORY_MAP[_ext] = 'office'
for _ext in ('.pdf','.txt','.srt','.vtt','.md','.markdown','.epub'): _CATEGORY_MAP[_ext] = 'document'

def category(path):
    ext = Path(path).suffix.lower()
    return _CATEGORY_MAP.get(ext, 'archive')

def number(params,name,default=0):
    value=params.get(name,default)
    if value in ('',None): return float(default)
    if isinstance(value, (int, float)): return float(value)
    s=str(value).strip()
    if ':' in s:
        parts=s.split(':'); return sum(float(x)*60**i for i,x in enumerate(reversed(parts)))
    try:
        return float(s)
    except ValueError:
        m=re.search(r'[-+]?\d*\.?\d+', s)
        if m: return float(m.group(0))
        return float(default)

def truth(value): return str(value).lower() in ('true','1','yes','on')

def fit_ratio(width,height,ratio):
    if ratio in ('','free',None):return width,height
    import math
    try:
        a,b=map(float,str(ratio).split(':'))
        if not math.isfinite(a) or not math.isfinite(b) or min(a,b)<=0:raise ValueError()
    except (ValueError,TypeError):raise ValueError(T('Both sides of the crop ratio must be numbers greater than 0')) from None
    # A size that already has the ratio to within whole-pixel rounding is kept as it is. Without this a size the
    # crop frame shows (say 857x643 at 4:3) was shaved again on export, so the saved file differed from the frame.
    if abs(height-width*b/a)<=.5 or abs(width-height*a/b)<=.5:return width,height
    if width/height>a/b:width=int(height*a/b)
    else:height=int(width*b/a)
    if min(width,height)<1:raise ValueError(T('The selection is too small for this ratio; enlarge it or change the ratio'))
    return width,height

def process(args,timeout=1800,cwd=None):
    """Run a tool and return its stdout. The time limit counts only time the job was running:
    the app can pause a job by suspending this whole process tree, and that gap must not trigger a timeout."""
    proc=subprocess.Popen([str(x) for x in args],stdin=subprocess.DEVNULL,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True,encoding='utf8',errors='replace',cwd=cwd,creationflags=0x08000000 if os.name=='nt' else 0)
    active,last=0.0,time.monotonic()
    while True:
        try:
            stdout,stderr=proc.communicate(timeout=1)
            break
        except subprocess.TimeoutExpired:
            now=time.monotonic(); step=now-last; last=now
            if step<5: active+=step  # a longer gap means we were suspended (paused)
            if timeout is not None and active>timeout:
                proc.kill(); proc.communicate()
                raise RuntimeError(T('Processing timed out (over {0} seconds)').format(int(timeout)))
    if proc.returncode:
        message='\n'.join(stderr.strip().splitlines()[-8:]) or stdout.strip()[-1200:]
        raise RuntimeError(message or T('The processing engine exited with code {0}').format(proc.returncode))
    return stdout

# Encodes can legitimately run for hours; the app cancels jobs on request instead of using a fixed limit.
# -threads 0 ensures FFmpeg uses all CPU cores for decoders, encoders, and filters
def ffmpeg(args,cwd=None): return process([FFMPEG,'-hide_banner','-loglevel','error','-nostdin','-threads','0','-y',*args],timeout=None,cwd=cwd)
def probe(path): return json.loads(process([FFPROBE,'-v','error','-show_format','-show_streams','-show_chapters','-of','json',path]))
def video_stream(info): return next(x for x in info['streams'] if x['codec_type']=='video')
def has_audio(info): return any(s['codec_type']=='audio' for s in info['streams'])
def duration(info): return float(info['format'].get('duration') or next((x.get('duration') for x in info['streams'] if x.get('duration')),0))

def output_stem(path,suffix):
    name=Path(path).name
    name=re.sub(r'(?i)(\.tar\.gz|\.tgz|\.[^.]+)$','',name)
    return name+'-'+suffix

# Output names say what was done in plain words (photo-rotated.jpg) instead of using the tool's internal id.
SUFFIX={'rotateImage':'rotated','rotateVideo':'rotated','cropImage':'cropped','cropVideo':'cropped','compress':'compressed','editImage':'edited','editVideo':'edited',
    'frameImage':'framed','redactImage':'redacted','redactVideo':'redacted','redactAudio':'beeped','removeMetadata':'clean','redactPDF':'redacted','muteVideo':'muted',
    'trimVideo':'trimmed','trimAudio':'trimmed','changeVideoSpeed':'speed','normalizeAudio':'normalized','audioChannels':'channels','audioToVideo':'visualizer',
    'resizeImage':'resized','watermark':'watermarked','makeIcon':'icons','annotateImage':'annotated','ocrImage':'text','ocrPDF':'text','videoToGif':'gif','videoSettings':'resized',
    'videoEffects':'effects','subtitlesAudio':'mixed','audioEffects':'adjusted','ringtone':'ringtone','pdfPassword':'protected','pdfNumbers':'numbered',
    'extractPdfImages':'images','packArchive':'packed','createAnimation':'animation','joinAudio':'joined','joinVideos':'joined','splitVideo':'clips',
    'videoSnapshots':'frames','extractArchive':'extracted','createCollage':'collage','createPDF':'combined','organizePDF':'organized'}

_WRITABLE_CACHE = {}
# Pre-resolve platform-specific restricted prefixes once at module load
_RESTRICTED_PREFIXES = []
if sys.platform == 'darwin':
    _home = str(Path.home().resolve())
    _RESTRICTED_PREFIXES = [('/System',), ('/Library',), ('/usr',), ('/bin',), ('/sbin',)]
    _RESTRICTED_LIB = os.path.join(_home, 'Library')
    _ALLOWED_LIB = os.path.join(_home, 'Library', 'Application Support', 'DropDial')
elif sys.platform == 'win32':
    _RESTRICTED_PREFIXES = [(os.environ.get(k, d).lower(),) for k, d in
        [('ProgramFiles', 'C:\\Program Files'), ('ProgramFiles(x86)', 'C:\\Program Files (x86)'), ('SystemRoot', 'C:\\Windows')]]

def is_dir_writable(dir_path):
    """Checks if a directory exists and can safely be written to by this process, cached for speed."""
    if not dir_path: return False
    try:
        p = Path(dir_path).resolve()
        p_str = str(p)
        cached = _WRITABLE_CACHE.get(p_str)
        if cached is not None: return cached
        if not p.is_dir():
            _WRITABLE_CACHE[p_str] = False
            return False
        # Avoid macOS sandboxed/system/TCC-restricted Library paths
        if sys.platform == 'darwin':
            if p_str.startswith(_RESTRICTED_LIB) and not p_str.startswith(_ALLOWED_LIB):
                _WRITABLE_CACHE[p_str] = False
                return False
            for prefix_tuple in _RESTRICTED_PREFIXES:
                if p_str.startswith(prefix_tuple[0]):
                    _WRITABLE_CACHE[p_str] = False
                    return False
        elif sys.platform == 'win32':
            p_lower = p_str.lower()
            for prefix_tuple in _RESTRICTED_PREFIXES:
                if p_lower.startswith(prefix_tuple[0]):
                    _WRITABLE_CACHE[p_str] = False
                    return False

        # Use os.access for a fast kernel-level permission check before the heavier touch+unlink
        if not os.access(p_str, os.W_OK):
            _WRITABLE_CACHE[p_str] = False
            return False
        # Attempt to create and delete a tiny test file to verify real write permission
        test = p / f".dd_write_test_{uuid.uuid4().hex[:12]}"
        try:
            test.touch()
            test.unlink()
            _WRITABLE_CACHE[p_str] = True
            return True
        except (PermissionError, OSError):
            _WRITABLE_CACHE[p_str] = False
            return False
    except Exception:
        return False

def get_safe_fallback_dir():
    """Returns a user-accessible directory guaranteed to have write permission."""
    for candidate in [Path.home() / 'Downloads', Path.home() / 'Desktop', Path(tempfile.gettempdir())]:
        try:
            if candidate.is_dir() and is_dir_writable(candidate):
                return candidate.resolve()
        except Exception:
            continue
    return Path(tempfile.gettempdir()).resolve()

def work_dir(path):
    """Where results are written: the folder chosen in the app, or next to the source file (with safe fallback)."""
    chosen = os.environ.get('DROPDIAL_OUTPUT_DIR', '').strip()
    if chosen and is_dir_writable(chosen):
        return Path(chosen).resolve()
    
    try:
        parent = Path(path).resolve().parent
        if is_dir_writable(parent):
            return parent
    except Exception:
        pass
    
    return get_safe_fallback_dir()

def commit(temp, path, suffix, extension):
    parent = work_dir(path)
    stem = output_stem(path, SUFFIX.get(suffix, suffix))
    
    candidate_dirs = [parent]
    fallback = get_safe_fallback_dir()
    if fallback != parent and fallback not in candidate_dirs:
        candidate_dirs.append(fallback)
        
    for target_dir in candidate_dirs:
        for i in range(10000):
            target = target_dir / (stem + (f'-{i}' if i else '') + extension)
            try:
                if target.exists(): continue
                # Instant atomic rename if on the same filesystem (0ms, zero disk copying)
                try:
                    os.replace(str(temp), str(target))
                    return str(target)
                except OSError:
                    # Cross-filesystem or permission restriction: fallback to shutil.move
                    shutil.move(str(temp), str(target))
                    return str(target)
            except FileExistsError:
                continue
            except (PermissionError, OSError):
                break
    raise OSError(T('Could not save output file due to permission restrictions'))

@contextmanager
def output_file(path, suffix, extension):
    # Staging temp file directly in the destination folder enables instant atomic rename
    dest_dir = work_dir(path)
    staging_dir = dest_dir if is_dir_writable(dest_dir) else Path(tempfile.gettempdir())
    temp = staging_dir / (f".dd_tmp_{uuid.uuid4().hex}{extension}")
    state = {'temp': temp, 'output': None}
    try:
        yield state
        if not temp.is_file() or temp.stat().st_size == 0:
            raise RuntimeError(T('The engine did not produce a valid output'))
        state['output'] = commit(temp, path, suffix, extension)
    finally:
        if temp.exists():
            try: temp.unlink()
            except Exception: pass

@contextmanager
def output_folder(path, suffix, allow_empty=False):
    # Staging folder is ALWAYS created in guaranteed-writable temp dir
    temp = Path(tempfile.mkdtemp(prefix=TEMP_PREFIX))
    state = {'temp': temp, 'output': None}
    try:
        yield state
        if not allow_empty and not any(temp.iterdir()):
            raise RuntimeError(T('Nothing was produced'))
        state['output'] = commit(temp, path, suffix, '')
    finally:
        if temp.exists():
            try: shutil.rmtree(temp)
            except Exception: pass

_heif_registered = False
_srgb_profile = None

def open_image(path,frame=None):
    from PIL import Image,ImageOps,ImageCms
    global _heif_registered, _srgb_profile
    if not _heif_registered:
        try:
            import pillow_heif
            pillow_heif.register_heif_opener()
        except Exception: pass
        _heif_registered = True
    if Path(path).suffix.lower()=='.svg':
        try:
            import resvg_py
            image=Image.open(io.BytesIO(resvg_py.svg_to_bytes(svg_path=str(path))))
        except Exception:
            try:
                import cairosvg
                image=Image.open(io.BytesIO(cairosvg.svg2png(url=str(path))))
            except Exception:
                if sys.platform=='darwin':
                    import subprocess, tempfile
                    with tempfile.TemporaryDirectory() as qldir:
                        res = subprocess.run(['qlmanage', '-t', '-s', '1000', '-o', qldir, str(path)], capture_output=True)
                        gen = Path(qldir) / (Path(path).name + '.png')
                        if gen.exists(): image = Image.open(gen).copy()
                        else: raise ValueError(T('SVG rendering failed on this system'))
                else: raise ValueError(T('SVG rendering requires resvg_py or cairosvg'))
    else: image=Image.open(path)
    frames=getattr(image,'n_frames',1)
    if frame is not None and int(frame)>=0:
        if int(frame)>=frames: raise ValueError(T('The selected image frame does not exist'))
        image.seek(int(frame))
    selected=image.tell()
    if image.width*image.height>80_000_000: raise ValueError(T('The image is larger than the 80-megapixel limit'))
    image=ImageOps.exif_transpose(image)
    profile=image.info.get('icc_profile')
    if profile:
        try:
            src_profile = ImageCms.ImageCmsProfile(io.BytesIO(profile))
            desc = ImageCms.getProfileDescription(src_profile).strip().lower()
            # Skip conversion if the embedded profile is already sRGB (common case)
            if 'srgb' not in desc:
                if _srgb_profile is None:
                    _srgb_profile = ImageCms.createProfile('sRGB')
                info={k:v for k,v in image.info.items() if k!='icc_profile'}
                image=ImageCms.profileToProfile(image,src_profile,_srgb_profile,outputMode='RGBA' if 'A' in image.getbands() else 'RGB')
                image.info={**info,**image.info}
        except (ValueError,OSError): pass
    image.load(); result=image.copy(); image.close()
    result.info['source_frames']=frames; result.info['source_frame']=selected
    return result

def save_image(image,path,fmt,quality=90,metadata=None):
    from PIL import Image
    # Metadata is written only when given: some encoders (HEIF) would otherwise copy the source's EXIF and XMP.
    for key in ('exif','xmp','XML:com.adobe.xmp'): image.info.pop(key,None)
    fmt=fmt.lower()
    mode={'jpg':'JPEG','jpeg':'JPEG','png':'PNG','webp':'WEBP','heic':'HEIF','tiff':'TIFF','tif':'TIFF','avif':'AVIF','bmp':'BMP','ico':'ICO'}.get(fmt, fmt.upper())
    if mode in ('JPEG','BMP'):
        if 'A' in image.getbands():
            background=Image.new('RGB',image.size,'white'); background.paste(image,mask=image.getchannel('A')); image=background
        else: image=image.convert('RGB')
    elif mode == 'ICO':
        if image.width > 256 or image.height > 256:
            factor = 256 / max(image.width, image.height)
            image = image.resize((max(1, round(image.width * factor)), max(1, round(image.height * factor))), Image.Resampling.LANCZOS)
        if image.mode not in ('RGBA', 'RGB'):
            image = image.convert('RGBA')
    options={'quality':int(quality)} if mode in ('JPEG','WEBP','HEIF','AVIF') else {}
    if mode=='JPEG': options['subsampling'] = 1
    if mode=='WEBP': options['method'] = 3
    if mode=='PNG': options={'compress_level': 6}
    if mode=='TIFF': options={'compression':'tiff_deflate'}
    if mode=='HEIF': options['exif']=None  # pillow_heif would otherwise copy the EXIF Pillow has cached for the image
    if mode=='ICO': options['sizes']=[(s,s) for s in (16,24,32,48,64,128,256)]
    if metadata:
        if mode in ('JPEG','WEBP','PNG','HEIF','TIFF','AVIF'): options['exif']=metadata.tobytes()
    image.save(path,format=mode,**options)

def orientation(params,required=True):
    """The clockwise angle (0 to 360 degrees) and the mirroring picked in the rotate tools; a preview may leave both unchanged."""
    angle=number(params,'angle',0); flip=params.get('flip','none') or 'none'
    if not 0<=angle<=360 or flip not in ('none','horizontal','vertical'): raise ValueError(T('The angle must be between 0 and 360 degrees, and the flip setting must be valid'))
    angle%=360
    if required and angle==0 and flip=='none': raise ValueError(T('Choose a rotation or a flip first'))
    return angle,flip

def fill_colour(params,default=''):
    """The colour that fills the corners a tilted picture leaves empty, as an RGB tuple; None means transparent."""
    from PIL import ImageColor
    value=(params.get('background') or default).strip()
    if not value: return None
    try: return ImageColor.getrgb(value)[:3]
    except ValueError: raise ValueError(T('The fill colour is not valid'))

def rects(params,width,height):
    raw=params.get('regions','').strip()
    if raw:
        result=json.loads(raw)
        if not isinstance(result,list): raise ValueError(T('Regions must be a JSON array'))
    else:
        result=[{'x':number(params,'x',0),'y':number(params,'y',0),'width':number(params,'width',width/2),'height':number(params,'height',height/2),'start':number(params,'start',0),'end':number(params,'end',0),'style':params.get('style','solid')}]
    for r in result:
        r['x']=max(0,int(r.get('x',0))); r['y']=max(0,int(r.get('y',0)))
        r['width']=min(int(r.get('width',width/2)),width-r['x']); r['height']=min(int(r.get('height',height/2)),height-r['y'])
        if r['width']<=0 or r['height']<=0: raise ValueError(T('A region is outside the picture'))
    return result
