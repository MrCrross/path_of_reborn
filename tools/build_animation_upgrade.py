"""Build source-resolution animation candidates, retaining native RGB pixels.

Inputs/prompts/masters: art_working/animation_upgrade_2026_11_20/.
No per-frame resizing, palette reduction or low-resolution enlargement. Generated
opaque actors have their unwanted low-alpha glow removed; legacy sources retain
their alpha within their trimmed bounds. --promote is for reviewed candidates.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
import shutil
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
WORK = ROOT / 'art_working/animation_upgrade_2026_11_20'
MANIFEST = ROOT / 'assets/manifest.json'
REUSED = ['haruto_modern_push', 'yui_crosswalk_wait', 'yui_crosswalk_step',
          'mitsuki_offer', 'mitsuki_wing_glitch']


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def rgba_digest(image: Image.Image) -> str:
    return hashlib.sha256(image.convert('RGBA').tobytes()).hexdigest()


def dump(path: Path, value: object) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')


def family_geometry(name: str) -> tuple[tuple[int, int], tuple[int, int], float]:
    if name.startswith('mitsuki'):
        return (180, 320), (90, 160), 320.0
    if name.startswith('moss_slime'):
        return (64, 64), (32, 56), 32.0
    if name.startswith('goblin'):
        return (96, 96), (48, 84), 50.0
    return (112 if 'branch_attack' in name else 96, 128), (56 if 'branch_attack' in name else 48, 112), 82.0


def foot_anchor(image: Image.Image, threshold: int) -> tuple[float, float]:
    mask = image.getchannel('A').point(lambda a: 255 if a >= threshold else 0)
    bounds = mask.getbbox()
    if bounds is None:
        raise ValueError('Empty frame')
    # Registration uses the bottom foot/base band, never the weapon/cape extent.
    band_top = max(bounds[1], bounds[3] - max(4, round((bounds[3] - bounds[1]) * .07)))
    band = mask.crop((0, band_top, image.width, bounds[3])).getbbox()
    return ((band[0] + band[2]) / 2, float(bounds[3]))


def build() -> dict:
    existing = json.loads(MANIFEST.read_text(encoding='utf-8'))
    jobs = json.loads((WORK / 'generation_jobs.json').read_text(encoding='utf-8'))
    jobs += json.loads((WORK / 'goblin_generation_jobs.json').read_text(encoding='utf-8'))
    outputs = json.loads((WORK / 'generated_outputs.json').read_text(encoding='utf-8'))
    names = [j['name'] for j in jobs] + REUSED
    result = {'date': '2026-11-20', 'status': 'candidate', 'assets': []}
    for name in names:
        old = next(a for a in existing['assets'] if a['path'].endswith('/' + name + '_sheet.png'))
        full = name.startswith('mitsuki')
        job = next((j for j in jobs if j['name'] == name), None)
        images, sources = [], []
        if job:
            source = WORK / 'source' / (name + '_v01.png')
            source.parent.mkdir(parents=True, exist_ok=True)
            if not source.exists():
                shutil.copyfile(outputs[name], source)
            prompt = WORK / 'prompts' / (name + '_v01.txt')
            prompt.parent.mkdir(parents=True, exist_ok=True)
            prompt.write_text(job['prompt'] + '\n', encoding='utf-8')
            raw = Image.open(source).convert('RGBA')
            for index in range(job['count']):
                col, row = index % job['cols'], index // job['cols']
                rect = [col * raw.width // job['cols'], row * raw.height // job['rows'],
                        (col + 1) * raw.width // job['cols'], (row + 1) * raw.height // job['rows']]
                # Generated branch follow-through crosses the nominal central gutter.
                if name == 'haruto_exiled_branch_attack' and row == 1:
                    rect[0], rect[2] = (0, 552) if col == 0 else (552, raw.width)
                frame = raw.crop(rect)
                alpha = frame.getchannel('A')
                frame.putalpha(alpha.point(lambda a: a if a >= 224 else 0))
                mask = frame.getchannel('A').point(lambda a: 255 if a else 0)
                box = mask.getbbox()
                scan_y = (box[1] + box[3]) // 2
                scan = mask.crop((0, scan_y, mask.width, scan_y + 1)).tobytes()
                seed_x = min((x for x, value in enumerate(scan) if value),
                             key=lambda x: abs(x - (box[0] + box[2]) / 2))
                ImageDraw.floodfill(mask, (seed_x, scan_y), 128)
                connected = mask.point(lambda a: 255 if a == 128 else 0)
                frame.putalpha(ImageChops.multiply(frame.getchannel('A'), connected))
                images.append(frame)
                sources.append({'kind': 'ai_generated', 'tool': 'image_gen built-in',
                                'original': source.relative_to(ROOT).as_posix(),
                                'original_sha256': digest(source), 'source_region': rect,
                                'prompt': prompt.relative_to(ROOT).as_posix(),
                                'prompt_sha256': digest(prompt), 'reference': job['ref'],
                                'rights': 'AI-generated from project-owned AI reference; platform terms apply',
                                'processing': 'native RGB; discard alpha <224 glow and disconnected neighbour fragments; trim and atlas pack; no resampling'} )
        else:
            for index, frame in enumerate(old['frames']):
                src = frame['source']
                original = ROOT / src['original']
                source = WORK / 'source' / (name + f'_{index + 1:02}_original.png')
                source.parent.mkdir(parents=True, exist_ok=True)
                if not source.exists():
                    shutil.copyfile(original, source)
                if digest(source) != src['original_sha256']:
                    raise ValueError(f'Original source hash mismatch: {name}')
                images.append(Image.open(source).convert('RGBA'))
                sources.append({**src, 'kind': 'ai_generated_reused_original',
                                'archived_original': source.relative_to(ROOT).as_posix(),
                                'rights': 'Existing project AI-generated source; platform terms apply',
                                'processing': 'original RGBA retained inside alpha>=128 bounds plus 2px; no resampling'})
        threshold = 224 if job else 128
        bounds = [im.getchannel('A').point(lambda a: 255 if a >= threshold else 0).getbbox() for im in images]
        ref_index = 1 if name.endswith('_hit') else (5 if name == 'moss_slime_jump' else (2 if name == 'goblin_scout_retreat' else (3 if name == 'haruto_modern_push' else 0)))
        logical_size, logical_pivot, solid_height = family_geometry(name)
        reference_height = bounds[ref_index][3] - bounds[ref_index][1]
        # Yui wait and walk share exactly one family scale.
        if name.startswith('yui'):
            reference_height = 1286
        density = reference_height / solid_height
        if full:
            density = images[0].height / 320.0
        frame_size = [math.ceil(logical_size[0] * density), math.ceil(logical_size[1] * density)]
        pivot = [round(logical_pivot[0] * density), round(logical_pivot[1] * density)]
        crops, placements, metrics = [], [], []
        for index, (im, bound) in enumerate(zip(images, bounds)):
            crop_rect = (0, 0, im.width, im.height) if full else (max(0, bound[0]-2), max(0, bound[1]-2), min(im.width, bound[2]+2), min(im.height, bound[3]+2))
            crop = im.crop(crop_rect)
            anchor = (im.width / 2, im.height / 2) if full else foot_anchor(im, threshold)
            lift = 0.0
            if name == 'moss_slime_jump':
                lift = [0, 2, 14, 10, 0, 0][index] * density
            if name == 'goblin_scout_retreat' and index == 1:
                lift = 7 * density
            placement = [round(pivot[0] - (anchor[0] - crop_rect[0])),
                         round(pivot[1] - (anchor[1] - crop_rect[1]) - lift)]
            crops.append(crop)
            placements.append(placement)
            metrics.append({'source_size': list(im.size), 'source_crop': list(crop_rect),
                            'source_anchor': list(anchor), 'air_lift_logical': lift / density,
                            'solid_height_logical': (bound[3]-bound[1]) / density})
        # Enlarge the virtual canvas only when a limb extends beyond nominal bounds.
        left = min(0, min(p[0] for p in placements))
        top = min(0, min(p[1] for p in placements))
        right = max(frame_size[0], max(p[0]+im.width for p, im in zip(placements,crops)))
        bottom = max(frame_size[1], max(p[1]+im.height for p, im in zip(placements,crops)))
        frame_size = [right-left, bottom-top]
        pivot = [pivot[0]-left, pivot[1]-top]
        placements = [[p[0]-left,p[1]-top] for p in placements]
        cell_w, cell_h = max(im.width for im in crops)+4, max(im.height for im in crops)+4
        options = [(math.ceil(len(crops)/cols)*cell_h*cols*cell_w, cols)
                   for cols in range(1,len(crops)+1)
                   if cols*cell_w <= 4096 and math.ceil(len(crops)/cols)*cell_h <= 4096]
        if not options:
            raise ValueError('Atlas cannot fit 4096 texture limit: '+name)
        _, cols = min(options)
        rows = math.ceil(len(crops)/cols)
        atlas = Image.new('RGBA',(cols*cell_w,rows*cell_h))
        frames=[]
        for index,(crop,placement,src,metric) in enumerate(zip(crops,placements,sources,metrics)):
            x,y = (index%cols)*cell_w+2,(index//cols)*cell_h+2
            atlas.paste(crop,(x,y))
            region=[x,y,crop.width,crop.height]
            margin=[*placement,frame_size[0]-crop.width,frame_size[1]-crop.height]
            frames.append({'region':region,'margin':margin,'rgba_sha256':rgba_digest(crop),
                           'source':src,'registration':metric})
        target=WORK/'candidates'/old['path']
        target.parent.mkdir(parents=True,exist_ok=True)
        atlas.save(target)
        runtime={'frame':frame_size,'count':len(frames),'scale':1.0/density,
                 'offset':[frame_size[0]/2-pivot[0],frame_size[1]/2-pivot[1]],
                 'regions':[{'region':f['region'],'margin':f['margin']} for f in frames]}
        record={**old,'size':list(atlas.size),'sha256':digest(target),'rgba_sha256':rgba_digest(atlas),
                'frames':frames,'pivot':pivot,'runtime':runtime,'status':'candidate',
                'technical_checks_passed':False,'source_resolution_upgrade':True,
                'source':{'kind':'ai_generated' if job else 'ai_generated_reused_original',
                          'export':target.relative_to(ROOT).as_posix(),
                          'tool':'image_gen built-in' if job else 'existing project AI originals',
                          'rights':'Project AI-generated content; platform terms apply'},
                'review':{'date':'2026-11-20','by':'Codex','status':'pending in-engine review',
                          'strict_shared_pixel_grid':False,'per_frame_resampling':False},
                'rgba8_mib':atlas.width*atlas.height*4/1024**2}
        result['assets'].append(record)
        preview=Image.new('RGB',(len(crops)*190,260),(43,49,56));draw=ImageDraw.Draw(preview)
        for index,(crop,place) in enumerate(zip(crops,placements)):
            virtual=Image.new('RGBA',tuple(frame_size));virtual.paste(crop,tuple(place))
            virtual.thumbnail((186,232),Image.Resampling.NEAREST)
            preview.paste(virtual,(index*190+(190-virtual.width)//2,20),virtual)
        draw.text((4,3),name,fill='white')
        prev=WORK/'previews'/(name+'_contact.png');prev.parent.mkdir(exist_ok=True);preview.save(prev)
        print(f'{name}: {len(frames)} frames, atlas {atlas.size}, {record["rgba8_mib"]:.2f} MiB')
    dump(WORK/'manifest.json',result)
    return result


def promote(result: dict) -> None:
    qa=json.loads((ROOT/'docs/reviews/animation_upgrade_2026_11_20/qa_report.json').read_text(encoding='utf-8'))
    reviewed={entry['path']:entry['sha256'] for entry in qa['checks']}
    for record in result['assets']:
        if reviewed.get(record['path']) != record['sha256'] or digest(ROOT/record['source']['export']) != record['sha256']:
            raise ValueError('Candidate has no matching pixel/registration/GPU review: '+record['path'])
    backup=WORK/'backup'
    backup.mkdir(exist_ok=True)
    if not (backup/'manifest.json').exists():
        shutil.copyfile(MANIFEST,backup/'manifest.json')
    existing=json.loads(MANIFEST.read_text(encoding='utf-8'))
    for record in result['assets']:
        old=next(a for a in existing['assets'] if a['path']==record['path'])
        target=ROOT/'assets'/record['path']
        saved=backup/record['path'];saved.parent.mkdir(parents=True,exist_ok=True)
        if not saved.exists():
            shutil.copyfile(target,saved)
        if digest(target) not in [old['sha256'],record['sha256']]:
            raise ValueError('Asset changed since manifest, refusing overwrite: '+str(target))
        shutil.copyfile(ROOT/record['source']['export'],target)
        record['status']='approved'
        record['technical_checks_passed']=True
        record['review']['status']='approved for integration after technical and native-scale review'
        record['review']['authorization']='User requested implementation of currently used animation sprites on 2026-11-20; selection delegated to implementing agent'
        old.clear();old.update(record)
    dump(MANIFEST,existing)
    result['status']='integrated'
    dump(WORK/'manifest.json',result)


def stage(result: dict) -> None:
    """Stage candidates for main-project QA before approving canonical assets."""
    catalog={}
    for record in result['assets']:
        target=ROOT/'game/art'/record['path']
        saved=WORK/'backup/runtime'/record['path']
        saved.parent.mkdir(parents=True,exist_ok=True)
        if target.exists() and not saved.exists():
            shutil.copyfile(target,saved)
        target.parent.mkdir(parents=True,exist_ok=True)
        shutil.copyfile(ROOT/record['source']['export'],target)
        catalog[record['path']]=record['runtime']
    dump(ROOT/'game/art/animation_catalog.json',catalog)


if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--promote',action='store_true');parser.add_argument('--stage',action='store_true')
    args=parser.parse_args()
    if args.promote:
        promote(json.loads((WORK/'manifest.json').read_text(encoding='utf-8')))
    elif args.stage:
        stage(json.loads((WORK/'manifest.json').read_text(encoding='utf-8')))
    else:
        build()
