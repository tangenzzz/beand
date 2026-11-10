"""Google Play store graphics from the wordmark.

Run from the repository root: python3 tool/make_store_graphics.py OUT_DIR
Writes icon-512.png (32-bit PNG, opaque) and two feature graphics
(1024 x 500, 24-bit PNG): one with the wordmark only, one with a tagline.
"""
import os
import sys

from PIL import Image, ImageDraw, ImageFont

sys.path.insert(0, os.path.dirname(__file__))
from make_app_icons import BG, CREAM, fitted, on_dark, wordmark_rgba  # noqa: E402

TAGLINE = 'Espresso & pour-over journal'
# The website's first choice of font, so the graphic matches beand.app.
FONT = '/System/Library/Fonts/SFNS.ttf'
MUTED = (168, 162, 152)


def placed(mark, size, width_fraction, center_y):
    w = round(size[0] * width_fraction)
    h = round(mark.height * w / mark.width)
    layer = Image.new('RGBA', size, (0, 0, 0, 0))
    layer.paste(mark.resize((w, h), Image.LANCZOS),
                ((size[0] - w) // 2, round(center_y - h / 2)))
    return layer, h


def main(out):
    os.makedirs(out, exist_ok=True)
    mark = wordmark_rgba()

    # Play rounds the corners itself; same proportions as the iOS icon.
    on_dark(fitted(mark, 512, 0.78)).save(f'{out}/icon-512.png')

    size = (1024, 500)
    plain = Image.new('RGBA', size, (*BG, 255))
    layer, _ = placed(mark, size, 0.5, size[1] / 2)
    plain.alpha_composite(layer)
    plain.convert('RGB').save(f'{out}/feature-graphic-plain.png')

    tagged = Image.new('RGBA', size, (*BG, 255))
    layer, h = placed(mark, size, 0.46, size[1] / 2 - 28)
    tagged.alpha_composite(layer)
    draw = ImageDraw.Draw(tagged)
    font = ImageFont.truetype(FONT, 34)
    font.set_variation_by_name('Regular')
    tw = draw.textlength(TAGLINE, font=font)
    draw.text(((size[0] - tw) / 2, size[1] / 2 - 28 + h / 2 + 34), TAGLINE,
              font=font, fill=MUTED)
    tagged.convert('RGB').save(f'{out}/feature-graphic-tagline.png')
    print('written to', out)


if __name__ == '__main__':
    main(sys.argv[1] if len(sys.argv) > 1 else 'build/store/play')
