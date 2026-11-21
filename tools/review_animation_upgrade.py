"""Validate native pixels/registration and publish review artifacts, not game saves."""
import json
import shutil
import subprocess
import sys
from pathlib import Path

from PIL import Image, ImageDraw

ROOT=Path(__file__).resolve().parents[1]
WORK=ROOT/'art_working/animation_upgrade_2026_11_20'
OUT=ROOT/'docs/reviews/animation_upgrade_2026_11_20'
OUT.mkdir(parents=True,exist_ok=True)
m=json.loads((WORK/'manifest.json').read_text(encoding='utf-8'))
checks=[]
for a in m['assets']:
    p=ROOT/a['source']['export']
    args=[sys.executable,str(ROOT/'.agents/skills/create-game-assets/scripts/asset_report.py'),str(p),
          '--expect-size',f'{a["size"][0]}x{a["size"][1]}','--json']
    if not 'mitsuki' in a['path']:
        args.append('--require-alpha')
    r=subprocess.run(args,capture_output=True,text=True,encoding='utf-8')
    if r.returncode:
        raise RuntimeError(r.stdout+r.stderr)
    atlas=Image.open(p).convert('RGBA')
    for f in a['frames']:
        x,y,w,h=f['region'];packed=atlas.crop((x,y,x+w,y+h))
        src=f['source'];raw=Image.open(ROOT/src['original']).convert('RGBA')
        if 'source_region' in src:
            raw=raw.crop(src['source_region'])
        raw=raw.crop(f['registration']['source_crop'])
        assert packed.convert('RGB').tobytes()==raw.convert('RGB').tobytes(),a['path']+' RGB changed'
        if src['kind']=='ai_generated_reused_original':
            assert packed.tobytes()==raw.tobytes(),a['path']+' original alpha changed'
        if not 'mitsuki' in a['path']:
            px,py=f['margin'][:2];rx,ry=f['registration']['source_anchor'];cx,cy=f['registration']['source_crop'][:2]
            delta_x=(px+rx-cx-a['pivot'][0])*a['runtime']['scale']
            delta_y=(py+ry-cy-a['pivot'][1])*a['runtime']['scale']+f['registration']['air_lift_logical']
            assert abs(delta_x)<.15 and abs(delta_y)<.15,(a['path'],delta_x,delta_y)
    checks.append({'path':a['path'],'sha256':a['sha256'],'frames':len(a['frames']),'asset_report':json.loads(r.stdout),
                   'native_rgb_preserved':True,'registration_passed':True,'rgba8_mib':a['rgba8_mib']})

gpu=WORK/'gpu'
for family,actions in [('hero',['haruto_exiled_idle','haruto_exiled_attack','haruto_exiled_idle','haruto_exiled_dodge','haruto_exiled_idle','haruto_exiled_hit']),
                       ('slime',['moss_slime_idle','moss_slime_attack','moss_slime_hit']),
                       ('goblin',['goblin_scout_idle','goblin_scout_attack','goblin_scout_retreat'])]:
    images=[];durations=[]
    for action in actions:
        for p in sorted(gpu.glob(action+'_[0-9][0-9].png')):
            im=Image.open(p).convert('RGB').resize((360,640),Image.Resampling.NEAREST)
            images.append(im);durations.append(400 if action.endswith('idle') else 120)
    images[0].save(OUT/(family+'_actions.gif'),save_all=True,append_images=images[1:],
                   duration=durations,loop=0,optimize=False)

canvas=Image.new('RGB',(1080,640),(24,30,39))
for col,name in enumerate(['world_720x1280','haruto_exiled_attack_01','goblin_scout_idle_720x1280']):
    im=Image.open(gpu/(name+'.png')).convert('RGB').resize((360,640),Image.Resampling.NEAREST)
    canvas.paste(im,(col*360,0))
canvas.save(OUT/'animation_overview.png')
for name in ['moss_slime_idle_360x640','moss_slime_idle_720x1280','moss_slime_idle_1080x1920',
             'goblin_scout_idle_1080x1920','prologue_offer_00','prologue_wait_00']:
    shutil.copyfile(gpu/(name+'.png'),OUT/(name+'.png'))

# Native-scale contact sheet for every frame and a light/dark alpha review.
all_rows=[]
for a in m['assets']:
    name=Path(a['path']).stem.removesuffix('_sheet')
    all_rows.append(Image.open(WORK/'previews'/(name+'_contact.png')).convert('RGB'))
contacts=Image.new('RGB',(1140,260*len(all_rows)),(43,49,56))
for row,im in enumerate(all_rows):
    contacts.paste(im,(0,row*260))
contacts.save(OUT/'all_frames_contact.png')
alpha=Image.new('RGB',(6*200,260*2),'white')
draw=ImageDraw.Draw(alpha)
for col,a in enumerate([m['assets'][i] for i in [0,1,3,4,7,8]]):
    sheet=Image.open(ROOT/a['source']['export']).convert('RGBA')
    f=a['frames'][0];x,y,w,h=f['region'];im=sheet.crop((x,y,x+w,y+h));im.thumbnail((190,230),Image.Resampling.NEAREST)
    for row,bg in enumerate(['#eeeeee','#171b24']):
        draw.rectangle((col*200,row*260,(col+1)*200,(row+1)*260),fill=bg)
        alpha.paste(im,(col*200+(200-im.width)//2,row*260+20),im)
alpha.save(OUT/'alpha_light_dark.png')
summary={'clips':len(checks),'frames':sum(c['frames'] for c in checks),'checks':checks,
         'gpu_captures':json.loads((gpu/'report.json').read_text(encoding='utf-8')),
         'memory_note':'RGBA8 arithmetic only; excludes driver, scene, other textures and copies; not Android profiling',
         'combat_slime_atlases_rgba8_mib':sum(c['rgba8_mib'] for c in checks if 'haruto_exiled' in c['path'] or 'moss_slime' in c['path']),
         'combat_goblin_atlases_rgba8_mib':sum(c['rgba8_mib'] for c in checks if 'haruto_exiled' in c['path'] or 'goblin_scout' in c['path']),
         'prologue_atlases_rgba8_mib':sum(c['rgba8_mib'] for c in checks if not any(n in c['path'] for n in ['haruto_exiled','moss_slime','goblin_scout']))}
(OUT/'qa_report.json').write_text(json.dumps(summary,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print('PASS',summary['clips'],'clips',summary['frames'],'frames; PNG reports, source pixels and anchors verified')
print('RGBA8 MiB slime/goblin/prologue',*[round(summary[k],2) for k in ['combat_slime_atlases_rgba8_mib','combat_goblin_atlases_rgba8_mib','prologue_atlases_rgba8_mib']])
