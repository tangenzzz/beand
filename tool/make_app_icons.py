from PIL import Image
import json, os

SRC = 'tool/assets/wordmark-archivo.png'
BG = (27, 25, 23)
CREAM = (243, 238, 228)
TEAL = (41, 199, 176)
BOX = (518, 432, 2359, 1005)   # Wortmarke, eng beschnitten

def wordmark_rgba():
    """Wortmarke freistellen: Hintergrund transparent, Kanten sauber."""
    im = Image.open(SRC).convert('RGB').crop(BOX)
    w, h = im.size
    out = Image.new('RGBA', (w, h), (0, 0, 0, 0))
    src, dst = im.load(), out.load()
    for y in range(h):
        for x in range(w):
            c = src[x, y]
            d = [c[i] - BG[i] for i in range(3)]
            if abs(d[0]) + abs(d[1]) + abs(d[2]) < 12:
                continue
            best, alpha = None, 0.0
            for f in (CREAM, TEAL):
                u = [f[i] - BG[i] for i in range(3)]
                nu = sum(v * v for v in u)
                a = sum(d[i] * u[i] for i in range(3)) / nu
                # How well does the pixel point towards this color?
                res = sum((d[i] - a * u[i]) ** 2 for i in range(3))
                if best is None or res < best[0]:
                    best, alpha = (res, f), a
            dst[x, y] = (*best[1], max(0, min(255, round(alpha * 255))))
    return out

def fitted(mark, canvas, width_fraction):
    """Wordmark centered on a transparent canvas, scaled to a width fraction."""
    target_w = round(canvas * width_fraction)
    target_h = round(mark.height * target_w / mark.width)
    layer = Image.new('RGBA', (canvas, canvas), (0, 0, 0, 0))
    layer.paste(
        mark.resize((target_w, target_h), Image.LANCZOS),
        ((canvas - target_w) // 2, (canvas - target_h) // 2),
    )
    return layer

def on_dark(layer):
    base = Image.new('RGBA', layer.size, (*BG, 255))
    base.alpha_composite(layer)
    return base

def main():
    mark = wordmark_rgba()
    print('Wordmark extracted:', mark.size)

    # --- Android ---------------------------------------------------------------
    # Adaptive icon: 108dp canvas, only the inner 66dp circle is guaranteed
    # visible. The wordmark (ratio ~3.2:1) fits in it up to ~58% width.
    ADAPTIVE = {'mdpi': 108, 'hdpi': 162, 'xhdpi': 216, 'xxhdpi': 324, 'xxxhdpi': 432}
    LEGACY = {'mdpi': 48, 'hdpi': 72, 'xhdpi': 96, 'xxhdpi': 144, 'xxxhdpi': 192}
    for dpi, px in ADAPTIVE.items():
        d = f'android/app/src/main/res/mipmap-{dpi}'
        os.makedirs(d, exist_ok=True)
        fitted(mark, px, 0.54).save(f'{d}/ic_launcher_foreground.png')
    for dpi, px in LEGACY.items():
        d = f'android/app/src/main/res/mipmap-{dpi}'
        on_dark(fitted(mark, px, 0.76)).convert('RGB').save(f'{d}/ic_launcher.png')
    print('Android icons written')

    # --- iOS -------------------------------------------------------------------
    # Square, opaque icons; iOS rounds the corners itself.
    ios_dir = 'ios/Runner/Assets.xcassets/AppIcon.appiconset'
    seen = set()
    for entry in json.load(open(f'{ios_dir}/Contents.json'))['images']:
        name = entry['filename']
        if name in seen:
            continue
        seen.add(name)
        side = float(entry['size'].split('x')[0]) * float(entry['scale'].rstrip('x'))
        px = round(side)
        on_dark(fitted(mark, px, 0.78)).convert('RGB').save(f'{ios_dir}/{name}')
    print('iOS-Icons geschrieben:', len(seen))


if __name__ == '__main__':
    main()
