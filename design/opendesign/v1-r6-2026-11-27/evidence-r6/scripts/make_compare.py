"""Build before/after sheets: R4 baseline (#117) vs R6 polish."""
import os
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

HERE = Path(__file__).resolve().parent
PKG = HERE.parents[1]
# Inputs can be overridden; defaults use the committed R6 screens and a
# temporary R4 baseline capture directory.
R4 = Path(os.environ.get('R4_SHOTS', '/tmp/r4final'))
R6 = Path(os.environ.get('R6_SHOTS', str(PKG / 'evidence-r6' / 'screens')))
OUT = PKG / 'evidence-r6' / 'compare'
OUT.mkdir(parents=True, exist_ok=True)
FONT = '/System/Library/Fonts/Hiragino Sans GB.ttc'
f_title = ImageFont.truetype(FONT, 24)
f_label = ImageFont.truetype(FONT, 17)
f_note = ImageFont.truetype(FONT, 13)
BG = '#f4f4ee'
INK = '#191918'
MUTED = '#6a6a60'
RED = '#c92a1e'

PAIRS = [
    ('today-desktop', '今日 · 桌面 1440', 'd-today.png', 'd-today.png', 'v'),
    ('todos-desktop', '待办 · 桌面 1440', 'd-todos.png', 'd-todos.png', 'v'),
    ('month-desktop', '月历 · 桌面 1440', 'd-month.png', 'd-month.png', 'v'),
    ('week-desktop', '周历 · 桌面 1440', 'd-week.png', 'd-week.png', 'v'),
    ('settings-desktop', '设置 · 桌面 1440', 'd-settings.png', 'd-settings.png', 'v'),
    ('detail-desktop', '待办详情 · 桌面 1440', 'd-detail.png', 'd-detail.png', 'v'),
    ('today-mobile', '今日 · 手机 390', 'm-today.png', 'm-today.png', 'h'),
    ('calendar-mobile', '日历 · 手机 390', 'm-cal.png', 'm-cal.png', 'h'),
    ('settings-mobile', '设置 · 手机 390', 'm-settings.png', 'm-settings.png', 'h'),
    ('today-dark-desktop', '今日 · 深色 1440', 'd-dark-today.png', 'd-dark-today.png', 'v'),
    ('month-dark-desktop', '月历 · 深色 1440', 'd-dark-month.png', 'd-dark-month.png', 'v'),
    ('today-dark-mobile', '今日 · 深色 390', 'm-dark-today.png', 'm-dark-today.png', 'h'),
]


def load(p):
    return Image.open(p).convert('RGB')


def vertical(title, a, b):
    w = max(a.width, b.width)
    pad, bar, gap, head = 26, 34, 22, 58
    h = head + bar + a.height + gap + bar + b.height + pad
    im = Image.new('RGB', (w + pad * 2, h), BG)
    d = ImageDraw.Draw(im)
    d.text((pad, 16), title, font=f_title, fill=INK)
    d.text((pad + d.textlength(title, font=f_title) + 14, 25), '同一演示数据与视口；上为基线，下为 R6', font=f_note, fill=MUTED)
    y = head
    for label, img, accent in ((label_a := 'R4 基线（#117）', a, MUTED), ('R6 精修', b, RED)):
        d.rectangle([pad, y, pad + 4, y + bar - 8], fill=accent)
        d.text((pad + 12, y + 4), label, font=f_label, fill=INK if accent == RED else MUTED)
        y += bar
        im.paste(img, (pad, y))
        y += img.height + gap
    return im


def horizontal(title, a, b):
    pad, bar, gap, head = 26, 34, 18, 58
    w = a.width + b.width + gap + pad * 2
    h = head + bar + max(a.height, b.height) + pad
    im = Image.new('RGB', (w, h), BG)
    d = ImageDraw.Draw(im)
    d.text((pad, 16), title, font=f_title, fill=INK)
    d.text((pad + d.textlength(title, font=f_title) + 14, 25), '左为基线，右为 R6', font=f_note, fill=MUTED)
    x = pad
    for label, img, accent in (('R4 基线（#117）', a, MUTED), ('R6 精修', b, RED)):
        d.rectangle([x, head, x + 4, head + bar - 8], fill=accent)
        d.text((x + 12, head + 4), label, font=f_label, fill=INK if accent == RED else MUTED)
        im.paste(img, (x, head + bar))
        x += img.width + gap
    return im


for slug, title, fa, fb, mode in PAIRS:
    a = load(R4 / fa)
    b = load(R6 / fb)
    if a.size != b.size:
        print('WARN size mismatch', slug, a.size, b.size)
    img = vertical(title, a, b) if mode == 'v' else horizontal(title, a, b)
    img.save(OUT / f'compare-{slug}.png', optimize=True)
    print('wrote', slug, img.size)
