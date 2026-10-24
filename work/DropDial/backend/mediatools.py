from pathlib import Path
import shutil,tempfile
from PIL import Image,ImageDraw,ImageFont
from common import *
import media


def container(path):
    fmt=Path(path).suffix.lstrip('.').lower()
    return fmt if fmt in media.VIDEO_CODECS else 'mp4'

def video_to_gif(path,params):
    info=probe(path); start=number(params,'start',0); end=number(params,'end',0) or duration(info); fps=int(number(params,'fps',12)); width=int(number(params,'width',480))
    if start<0 or end<=start or end>duration(info)+.1: raise ValueError(T('The start or end is outside the video'))
    if not 1<=fps<=30: raise ValueError(T('The GIF frame rate must be between 1 and 30'))
    if not 16<=width<=1920: raise ValueError(T('The GIF width must be between 16 and 1920 pixels'))
    graph=f'fps={fps},scale=min({width}\\,iw):-2:flags=lanczos,split[a][b];[a]palettegen[p];[b][p]paletteuse'
    with output_file(path,'videoToGif','.gif') as state:
        ffmpeg(['-ss',start,'-i',path,'-t',end-start,'-filter_complex',graph,'-an','-loop','0' if truth(params.get('loop','true')) else '-1',state['temp']])
    return state['output']

def video_settings(path,params):
    info=probe(path); fmt=container(path); height=params.get('height','original'); fps=number(params,'fps',0); vf=[]
    if height not in ('original','') and int(height)>0: vf.append(f'scale=-2:{int(height)}:flags=lanczos')
    if fps<0 or fps>240: raise ValueError(T('The frame rate must be between 0 and 240'))
    if fps: vf.append(f'fps={fps:g}')
    if not vf: raise ValueError(T('Choose a resolution or a frame rate'))
    vf.append('pad=ceil(iw/2)*2:ceil(ih/2)*2')
    with output_file(path,'videoSettings','.'+fmt) as state: ffmpeg(['-i',path,'-vf',','.join(vf),*media.video_args(fmt),state['temp']])
    return state['output']

def video_effects(path,params):
    info=probe(path); fmt=container(path); total=duration(info); audio=has_audio(info)
    fade_in=number(params,'fadeIn',0); fade_out=number(params,'fadeOut',0); reverse=truth(params.get('reverse','false')); loops=int(number(params,'loops',1))
    if min(fade_in,fade_out)<0 or not 1<=loops<=20: raise ValueError(T('Fade times cannot be negative, and the repeat count must be between 1 and 20'))
    if not (fade_in or fade_out or reverse or loops>1): raise ValueError(T('Choose at least one effect'))
    length=total*loops
    if fade_in+fade_out>length: raise ValueError(T('The fades are longer than the video'))
    if reverse and length>120: raise ValueError(T('Reversing loads the whole video into memory; trim it to 2 minutes or less first'))
    vf=[]; af=[]
    if reverse: vf.append('reverse'); af.append('areverse')
    if fade_in: vf.append(f'fade=t=in:st=0:d={fade_in}'); af.append(f'afade=t=in:st=0:d={fade_in}')
    if fade_out: vf.append(f'fade=t=out:st={length-fade_out}:d={fade_out}'); af.append(f'afade=t=out:st={length-fade_out}:d={fade_out}')
    vf.append('pad=ceil(iw/2)*2:ceil(ih/2)*2'); args=['-stream_loop',str(loops-1),'-i',path] if loops>1 else ['-i',path]
    args+=['-vf',','.join(vf)]
    if af and audio: args+=['-af',','.join(af)]
    with output_file(path,'videoEffects','.'+fmt) as state: ffmpeg([*args,*media.video_args(fmt),state['temp']])
    return state['output']

def subtitles_audio(path,params):
    sub=params.get('subtitleFile','').strip(); sound=params.get('audioFile','').strip()
    if not sub and not sound: raise ValueError(T('Choose a subtitle file or an audio file'))
    for name in (sub,sound):
        if name and not Path(name).is_file(): raise ValueError(T('Cannot find the selected file: ')+name)
    info=probe(path); total=duration(info); fmt=container(path); fmt=fmt if fmt in ('mp4','mov','mkv') else 'mp4'
    volume=number(params,'volume',1)
    if not 0<=volume<=4: raise ValueError(T('The volume must be between 0 and 4 times'))
    with tempfile.TemporaryDirectory(prefix='dropdial-subs-') as temp:
        # FFmpeg reads the subtitles from its working folder, which avoids drive letters and quotes in a filter path.
        args=['-i',path]; maps=[]; vf=[]
        if sub:
            shutil.copy2(sub,Path(temp)/('subs'+Path(sub).suffix.lower()))
            style=f"FontName=Microsoft YaHei,FontSize={int(number(params,'subtitleSize',22))},Outline=2,Shadow=0"
            vf.append(f"subtitles=subs{Path(sub).suffix.lower()}:fontsdir='C\\:/Windows/Fonts':force_style='{style}'")
        if sound:
            args+=['-i',sound]
            if truth(params.get('mix','false')) and has_audio(info): graph=f'[0:a]anull[o];[1:a]volume={volume}[n];[o][n]amix=inputs=2:duration=first:normalize=0[a]'
            else: graph=f'[1:a]volume={volume}[a]'
            maps=['-filter_complex',graph,'-map','0:v','-map','[a]','-t',str(total)]
        codec=media.video_args(fmt) if vf else ['-c:v','copy','-c:a','aac','-b:a','160k']
        if vf: args+=['-vf',','.join(vf)]
        with output_file(path,'subtitlesAudio','.'+fmt) as state: ffmpeg([*args,*maps,*codec,state['temp']],cwd=temp)
    return state['output']

def contact_sheet(path,params):
    info=probe(path); total=duration(info); count=int(number(params,'sheetCount',12)); columns=int(number(params,'sheetColumns',4))
    if not 1<=count<=60 or not 1<=columns<=10: raise ValueError(T('Use 1–60 thumbnails and 1–10 columns'))
    stream=video_stream(info); width=320; height=max(2,round(width*int(stream['height'])/int(stream['width'])))
    import imagetools
    font=imagetools._get_font(str(FONT),14) if FONT else ImageFont.load_default(); thumbs=[]
    with tempfile.TemporaryDirectory(prefix='dropdial-sheet-') as temp:
        for index in range(count):
            moment=min(total*(index+.5)/count,max(0,total-.25)); frame=Path(temp)/f'{index}.png'
            ffmpeg(['-ss',moment,'-i',path,'-frames:v','1','-an','-sn','-dn','-vf',f'scale={width}:{height}',frame])
            picture=Image.open(frame).convert('RGB'); draw=ImageDraw.Draw(picture); label=f'{int(moment//60):02}:{moment%60:04.1f}'
            draw.rectangle((0,height-22,70,height),fill=(0,0,0)); draw.text((5,height-20),label,font=font,fill='white'); thumbs.append(picture)
    rows=-(-count//columns); gap=8; sheet=Image.new('RGB',(columns*width+(columns+1)*gap,rows*height+(rows+1)*gap),(17,17,17))
    for index,picture in enumerate(thumbs): sheet.paste(picture,(gap+(index%columns)*(width+gap),gap+(index//columns)*(height+gap)))
    with output_file(path,'videoSnapshots','.png') as state: sheet.save(state['temp'])
    return state['output']

def video_watermark(path,params):
    import imagetools
    info=probe(path); stream=video_stream(info); fmt=container(path)
    with tempfile.TemporaryDirectory(prefix='dropdial-mark-') as temp:
        layer=Path(temp)/'mark.png'; imagetools.watermark_layer((int(stream['width']),int(stream['height'])),params).save(layer)
        graph='[0:v][1:v]overlay=0:0,pad=ceil(iw/2)*2:ceil(ih/2)*2[outv]'
        with output_file(path,'watermark','.'+fmt) as state: ffmpeg(['-i',path,'-i',layer,'-filter_complex',graph,'-map','[outv]','-map','0:a?',*media.video_args(fmt),state['temp']])
    return state['output']

def audio_effects(path,params):
    info=probe(path); fmt=Path(path).suffix.lstrip('.').lower(); fmt='aiff' if fmt=='aif' else fmt; total=duration(info)
    gain=number(params,'gainDb',0); fade_in=number(params,'fadeIn',0); fade_out=number(params,'fadeOut',0); denoise=truth(params.get('denoise','false'))
    if not -30<=gain<=30 or min(fade_in,fade_out)<0: raise ValueError(T('The volume change must be between -30 and 30 dB, and fade times cannot be negative'))
    if fade_in+fade_out>total: raise ValueError(T('The fades are longer than the audio'))
    filters=[]
    if denoise: filters.append('afftdn=nf=-25')
    if gain: filters.append(f'volume={gain}dB')
    if fade_in: filters.append(f'afade=t=in:st=0:d={fade_in}')
    if fade_out: filters.append(f'afade=t=out:st={total-fade_out}:d={fade_out}')
    if not filters: raise ValueError(T('Choose at least one adjustment'))
    with output_file(path,'audioEffects','.'+fmt) as state: ffmpeg(['-i',path,'-vn','-af',','.join(filters),*media.audio_args(fmt,params),state['temp']])
    return state['output']

def join_audio(paths,params):
    first=Path(paths[0]).suffix.lstrip('.').lower(); fmt='aiff' if first=='aif' else first
    fmt=fmt if fmt in media.AUDIO_CODECS else 'mp3'; args=[]; graph=[]
    for index,path in enumerate(paths):
        args+=['-i',path]; graph.append(f'[{index}:a:0]aformat=sample_rates=48000:channel_layouts=stereo[a{index}]')
    graph.append(''.join(f'[a{i}]' for i in range(len(paths)))+f'concat=n={len(paths)}:v=0:a=1[out]')
    with output_file(paths[0],'joinAudio','.'+fmt) as state: ffmpeg([*args,'-vn','-filter_complex',';'.join(graph),'-map','[out]',*media.audio_args(fmt,params),state['temp']])
    return state['output']

def ringtone(path,params):
    info=probe(path); start=number(params,'start',0); length=number(params,'length',30)
    if not 1<=length<=40: raise ValueError(T('The ringtone length must be between 1 and 40 seconds'))
    if start<0 or start>=duration(info): raise ValueError(T('The start or end is outside the audio'))
    length=min(length,duration(info)-start); fade=min(1.5,length/3)
    with output_file(path,'ringtone','.m4r') as state:
        ffmpeg(['-ss',start,'-i',path,'-t',length,'-vn','-af',f'afade=t=out:st={length-fade}:d={fade}','-c:a','aac','-b:a','128k','-f','ipod',state['temp']])
    return state['output']
