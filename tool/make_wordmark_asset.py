"""Wordmark as an app asset (shared shot image): extracted like the app
icons, 600 px wide. Run from the project folder:
python3 tool/make_wordmark_asset.py"""
import os
import sys

from PIL import Image

sys.path.insert(0, os.path.dirname(__file__))
from make_app_icons import wordmark_rgba  # noqa: E402

WIDTH = 600

mark = wordmark_rgba()
height = round(mark.height * WIDTH / mark.width)
os.makedirs('assets/branding', exist_ok=True)
mark.resize((WIDTH, height), Image.LANCZOS).save('assets/branding/wordmark.png')
print('assets/branding/wordmark.png', WIDTH, 'x', height)
