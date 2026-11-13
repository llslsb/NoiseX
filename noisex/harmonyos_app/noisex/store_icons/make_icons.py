# NoiseX 应用图标生成 —— 依据《NoiseX 产品详细设计文档》
# 附录：App图标 = 模糊的雷达波纹 + 一个沙漏轮廓，颜色为暗橙+黑
# 风格 §3.3：深色背景 + 微弱噪点纹理；主色荧光橙（脉冲信号）；辅助色暗灰、白
#
# 输出（脚本位于 DevEco 工程根 store_icons/ 下，直接写工程媒体资源）：
#   ../AppScope/resources/base/media/{background,foreground}.png   应用分层图标
#   ../entry/src/main/resources/base/media/{background,foreground}.png  entry 分层图标
#   ../entry/src/main/resources/base/media/startIcon.png           启动图标的 144 圆角版
#   ./noisex_store_1024.png / noisex_store_216.png                 AGC 商店直角图标（= 两层合成）
#   ./preview.png                                                  预览对比
# 用法: python make_icons.py
from PIL import Image, ImageDraw, ImageFilter, ImageChops
import math, os

S = 2048                    # 主画布（2x 超采样，最终降采样到 1024）
K = S / 1024.0
HERE = os.path.dirname(os.path.abspath(__file__))
PROJ = os.path.dirname(HERE)  # DevEco 工程根（AppScope/ 与 entry/ 所在）

# ---- 调色板 ----
BG_CENTER = (19, 18, 23)
BG_EDGE   = (6, 6, 9)
O_HI  = (255, 159, 28)      # 荧光橙（沙/脉冲/回声点）
O_MID = (222, 122, 34)
O_LOW = (168, 84, 30)
GLASS = (238, 232, 222)     # 沙漏轮廓（辅助色·白，微暖）

# ---- 几何（1024 空间，中心为原点；前景主体对角半径 279 < 341，满足中心 2/3 安全区）----
HG_H = 225; HG_W = 165; NECK = 38; STROKE = 34
RING_R = (225, 330, 430)
RING_W = (22, 16, 12)
RING_C = ((O_HI, 235), (O_MID, 150), (O_LOW, 90))
PING_AT = (330, -55)
MOUND = dict(base=210, peak=150, half=100)
STREAM = ((0, 12), (0, 140), 32)

def bez(p0, p1, p2, p3, n=48):
    pts = []
    for i in range(n + 1):
        t = i / n; u = 1 - t
        pts.append((u*u*u*p0[0] + 3*u*u*t*p1[0] + 3*u*t*t*p2[0] + t*t*t*p3[0],
                    u*u*u*p0[1] + 3*u*u*t*p1[1] + 3*u*t*t*p2[1] + t*t*t*p3[1]))
    return pts

def W(pt):
    return ((pt[0] + 512) * K, (pt[1] + 512) * K)

def layer():
    return Image.new('RGBA', (S, S), (0, 0, 0, 0))

def add_glow(base, lyr, blur, fade=1.0):
    g = lyr.filter(ImageFilter.GaussianBlur(blur))
    if fade < 1.0:
        g.putalpha(g.getchannel('A').point(lambda v: int(v * fade)))
    return Image.alpha_composite(base, g)

# ---------- 背景层：深色 + 噪点 + 雷达波纹 ----------
grad = Image.radial_gradient('L').resize((S, S))
bg = Image.composite(Image.new('RGB', (S, S), BG_EDGE),
                     Image.new('RGB', (S, S), BG_CENTER), grad).convert('RGBA')
noise = Image.effect_noise((S // 2, S // 2), 30).resize((S, S), Image.NEAREST)
pos = ImageChops.subtract(noise, Image.new('L', (S, S), 128))
neg = ImageChops.subtract(Image.new('L', (S, S), 128), noise)
for npart, tint in ((pos, 255), (neg, 0)):
    l = layer()
    l.putalpha(npart.point(lambda v: min(26, v * 2)))
    solid = Image.new('RGBA', (S, S), (tint, tint, tint, 0))
    solid.putalpha(l.getchannel('A'))
    bg = Image.alpha_composite(bg, solid)

glow_src = Image.new('L', (256, 256), 0)
ImageDraw.Draw(glow_src).ellipse([56, 56, 200, 200], fill=44)
glow_src = glow_src.filter(ImageFilter.GaussianBlur(30)).resize((S, S))
warm = Image.new('RGBA', (S, S), O_HI + (0,)); warm.putalpha(glow_src)
bg = Image.alpha_composite(bg, warm)

rings = layer()
rd = ImageDraw.Draw(rings)
for r, w, (col, alpha) in zip(RING_R, RING_W, RING_C):
    bb = [W((-r, -r))[0], W((-r, -r))[1], W((r, r))[0], W((r, r))[1]]
    rd.arc(bb, 0, 360, fill=col + (alpha,), width=int(w * K))
bg = add_glow(bg, rings, int(46 * K), 0.9)
bg = add_glow(bg, rings, int(12 * K), 1.0)

pr, pang = PING_AT
pp = (pr * math.cos(math.radians(pang)), pr * math.sin(math.radians(pang)))
ping = layer()
pd = ImageDraw.Draw(ping)
pd.ellipse([W((pp[0]-14, pp[1]-14))[0], W((pp[0]-14, pp[1]-14))[1],
            W((pp[0]+14, pp[1]+14))[0], W((pp[0]+14, pp[1]+14))[1]],
           fill=(255, 205, 110, 255))
bg = add_glow(bg, ping, int(26 * K), 1.0)
bg = Image.alpha_composite(bg, ping)

# ---------- 前景层：白色沙漏轮廓 + 荧光橙沙 ----------
fg = layer()
gd = ImageDraw.Draw(fg)
wpx = int(STROKE * K)
side_r = bez((HG_W, -HG_H), (HG_W, -100), (NECK, -90), (NECK, 0)) + \
         bez((NECK, 0), (NECK, 90), (HG_W, 100), (HG_W, HG_H))[1:]
for side in (side_r, [( -x, y) for x, y in side_r]):
    gd.line([W(p) for p in side], fill=GLASS + (255,), width=wpx, joint='curve')
for (cx, cy) in [(-HG_W, -HG_H), (HG_W, -HG_H), (-HG_W, HG_H), (HG_W, HG_H)]:
    gd.ellipse(list(W((cx - STROKE/2, cy - STROKE/2)) + W((cx + STROKE/2, cy + STROKE/2))),
               fill=GLASS + (255,))
gd.line([W((-HG_W, -HG_H)), W((HG_W, -HG_H))], fill=GLASS + (255,), width=wpx)
gd.line([W((-HG_W, HG_H)), W((HG_W, HG_H))], fill=GLASS + (255,), width=wpx)
fg = add_glow(fg, fg, int(26 * K), 0.5)

sand = layer()
sd = ImageDraw.Draw(sand)
peak_y, base_y, half = MOUND['peak'], MOUND['base'], MOUND['half']
poly = [W((-half, base_y))]
for i in range(41):
    t = i / 40
    poly.append(W((-half + 2 * half * t,
                   base_y - (base_y - peak_y) * (1 - (2 * t - 1) ** 2))))
poly.append(W((half, base_y)))
sd.polygon(poly, fill=O_HI + (255,))
sx0, sy0 = W((STREAM[0][0] - STREAM[2]/2, STREAM[0][1]))
sx1, sy1 = W((STREAM[1][0] + STREAM[2]/2, STREAM[1][1]))
sd.rounded_rectangle([sx0, sy0, sx1, sy1], radius=int(STREAM[2]/2 * K), fill=O_HI + (255,))
fg_glow = add_glow(fg, sand, int(22 * K), 0.75)
fg = Image.alpha_composite(fg_glow, sand)

# ---------- 导出 ----------
bg1024 = bg.resize((1024, 1024), Image.LANCZOS)
fg1024 = fg.resize((1024, 1024), Image.LANCZOS)
composed = Image.alpha_composite(bg1024, fg1024)

def save(im, path, size=None):
    if size: im = im.resize((size, size), Image.LANCZOS)
    im.save(path, optimize=True)
    print(os.path.relpath(path, PROJ), im.size, round(os.path.getsize(path)/1024, 1), 'KB')

# 工程分层图标（AppScope + entry 同一份新设计）
for mdir in ('AppScope/resources/base/media', 'entry/src/main/resources/base/media'):
    save(bg1024, os.path.join(PROJ, mdir, 'background.png'))
    save(fg1024, os.path.join(PROJ, mdir, 'foreground.png'))
# 启动图标：合成图 144 圆角
mk144 = Image.new('L', (1024, 1024), 0)
ImageDraw.Draw(mk144).rounded_rectangle([0, 0, 1023, 1023], radius=int(26/114*1024), fill=255)
start = composed.copy(); start.putalpha(mk144)
save(start, os.path.join(PROJ, 'entry/src/main/resources/base/media/startIcon.png'), 144)
# AGC 商店直角图标 = 两层原样合成
save(composed, os.path.join(HERE, 'noisex_store_1024.png'))
save(composed, os.path.join(HERE, 'noisex_store_216.png'), 216)

# 预览：合成 | AGC蒙层 | 仅前景(深底) | 仅背景
p1 = composed.resize((342, 342), Image.LANCZOS)
p2 = p1.copy()
mk = Image.new('L', (342, 342), 0)
ImageDraw.Draw(mk).rounded_rectangle([0, 0, 341, 341], radius=77, fill=255)
p2.putalpha(mk)
fgh = fg1024.resize((342, 342), Image.LANCZOS)
fgh_bg = Image.new('RGBA', (342, 342), (10, 10, 12, 255)); fgh_bg.alpha_composite(fgh)
bgh = bg1024.resize((342, 342), Image.LANCZOS)
prev = Image.new('RGBA', (342 * 4 + 50, 392), (245, 245, 245, 255))
for i, img in enumerate([p1, p2, fgh_bg, bgh]):
    prev.paste(img, (10 + i * 352, 40), img)
dd = ImageDraw.Draw(prev)
for i, t in enumerate(['composed 1024', 'AGC mask preview', 'foreground layer', 'background layer']):
    dd.text((10 + i * 352, 12), t, fill=(60, 60, 60, 255))
prev.save(os.path.join(HERE, 'preview.png'))
print('preview ok')
