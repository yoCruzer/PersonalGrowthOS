"""Recalculate original PNG solid icon/background samples (Python 3 + Pillow)."""
from pathlib import Path
from PIL import Image
import hashlib
import json

ROOT = Path(__file__).resolve().parent


def luminance(rgb):
    components = [v / 255 for v in rgb]
    linear = [v / 12.92 if v <= .04045 else ((v + .055) / 1.055) ** 2.4 for v in components]
    return sum(w * v for w, v in zip((.2126, .7152, .0722), linear))


def ratio(a, b):
    a, b = luminance(a), luminance(b)
    return (max(a, b) + .05) / (min(a, b) + .05)


results = []
for sample in json.loads((ROOT / 'samples.json').read_text()):
    path = ROOT / sample['file']
    with Image.open(path) as original:
        assert 'srgb' in original.info, (path, 'sRGB metadata required')
        im = original.convert('RGB')
        foreground = im.getpixel(tuple(sample['foregroundPixel']))
        background = im.getpixel(tuple(sample['backgroundPixel']))
        assert list(foreground) == sample['foreground'], (path, foreground)
        assert list(background) == sample['background'], (path, background)
        contrast = ratio(foreground, background)
        assert contrast >= 3, (path, contrast)
        results.append(sample | dict(contrast=contrast, sha256=hashlib.sha256(path.read_bytes()).hexdigest(),
                                     dimensions=list(im.size), colorSpace='sRGB'))
old = []
for name in ['final-light-default.png', 'final-light-XXXL.png']:
    path = ROOT.parent / 'UI20261020' / name
    with Image.open(path) as im:
        assert 'srgb' in im.info
        pixels = im.convert('RGB')
        points = {str(color): next((x, y) for y in range(im.height) for x in range(im.width)
                                  if pixels.getpixel((x, y)) == color)
                  for color in [(0, 136, 255), (209, 209, 209)]}
    old.append(dict(file=str(path.relative_to(ROOT.parent)), sha256=hashlib.sha256(path.read_bytes()).hexdigest(),
                    points=points, foreground=[0, 136, 255], background=[209, 209, 209],
                    contrast=ratio((0, 136, 255), (209, 209, 209))))
report = dict(formula='WCAG sRGB linearization; (lighter relative luminance + .05)/(darker + .05)',
              scope='Enabled non-text icons; solid pixels only; disabled zero-count decrement excluded',
              originals=old, samples=results, minimumEnabledContrast=min(x['contrast'] for x in results))
(ROOT / 'contrast-results.json').write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n')
print(json.dumps(dict(samples=len(results), minimumEnabledContrast=report['minimumEnabledContrast'],
                      oldContrast=old[0]['contrast']), ensure_ascii=False))
