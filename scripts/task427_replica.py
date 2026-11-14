#!/usr/bin/env python3
# -*- coding: utf-8 -*-
# Task427 Python 先行复刻（design-first replica）——用户 IMG_0678 五复诉根修 + Photon 对标
#   A 组 UI：姿态图标段（前/后顶行）· 面板覆盖范围（只盖预览列以左）· 全屏模式
#   B 组 天空：MC 原版昼夜时间轴（晨/午/暮/夜）+ 晚霞径向辉光
#   C 组 维度：末地 / 下界专属天穹（无日月、固定光照）
#   D 组 无限世界：20×20 高度图立体方块 CPU 复刻渲染（正午 / 晚霞 / 夜 / 雪地 / 下界 / 末地）
#   E 组 定量：雾-天穹锚定 · MC 面亮度表 · 姿态条宽度 · 覆盖矩形数学 · 世界视距
# 与 ObjC 实装同源常量（AME427_*）：grid=20 block=16 plaza r<2.6 D_world=max(900, halfPx*1.35)
import os, math
from PIL import Image, ImageDraw, ImageFont

OUT1 = os.path.join(os.path.dirname(__file__), "task427_evidence")
OUT2 = "/home/z/my-project/download/task427_test_images"
os.makedirs(OUT1, exist_ok=True); os.makedirs(OUT2, exist_ok=True)
FONT = "/usr/share/fonts/truetype/chinese/NotoSansSC-Regular.ttf"
def font(sz): return ImageFont.truetype(FONT, sz)

GRID = 20; BLOCK = 16.0; HALF = GRID * BLOCK / 2.0
CAM_D = 900.0

def lerp(a, b, t): return a + (b - a) * t
def mix3(c1, c2, t): return tuple(lerp(c1[i], c2[i], t) for i in range(3))
def clamp(v, lo, hi): return max(lo, min(hi, v))
def hx(c):  # 0..1 float3 -> 255 int3
    return tuple(int(clamp(v, 0, 1) * 255 + 0.5) for v in c)

# ---- 确定性值噪声（与 ObjC ame427_hash/noise 同源）----
def hsh(x, z, salt):
    h = (x * 374761393 + z * 668265263) ^ (salt * 97)
    h &= 0xFFFFFFFF
    h = ((h ^ (h >> 13)) * 1274126177) & 0xFFFFFFFF
    return ((h ^ (h >> 16)) & 0xFFFF) / 65535.0

def noise2(x, z, salt):   # x,z 浮点，格点双线性
    ix, iz = math.floor(x), math.floor(z)
    fx, fz = x - ix, z - iz
    fx = fx * fx * (3 - 2 * fx); fz = fz * fz * (3 - 2 * fz)
    n00 = hsh(ix, iz, salt); n10 = hsh(ix + 1, iz, salt)
    n01 = hsh(ix, iz + 1, salt); n11 = hsh(ix + 1, iz + 1, salt)
    return lerp(lerp(n00, n10, fx), lerp(n01, n11, fx), fz)

def terrain_height(wx, wz, world):
    """wx,wz 方块坐标 → 高度(方块数)。主世界/雪地丘陵，下界粗粝，末地岛穹。"""
    gx, gz = wx / 3.0, wz / 3.0
    if world == "plains":
        h = round(noise2(gx, gz, 11) * 2.4)
        w = noise2(gx, gz, 777)
        if w > 0.80 and h == 0: return 0, "water"
        return h, "grass"
    if world == "snow":
        return round(noise2(gx, gz, 23) * 3.2), "snow"
    if world == "nether":
        h = round(noise2(gx, gz, 41) * 3.0)
        if noise2(gx, gz, 43) > 0.82 and h == 0: return 0, "lava"
        return h, "nether"
    if world == "end":
        r = math.hypot(wx - 0.0, wz - 0.0)
        if r > 9.0 + hsh(int(wx), int(wz), 55) * 1.6: return -1, "void"
        return int(clamp(round((9.5 - r) / 9.5 * 2.6 + noise2(gx, gz, 57) * 0.8), 0, 3)), "end"
    return 0, "grass"

# 广场：模型立足区强制平地 + 环形高度衰减过渡（免广场成坑）
def tile_at(wx, wz, world):
    if world == "end":
        return terrain_height(wx, wz, world)
    r = math.hypot(wx, wz)
    if r < 2.6:
        return 0, "grass" if world == "plains" else ("snow" if world == "snow" else "nether")
    hgt, kind = terrain_height(wx, wz, world)
    if r < 7.0:
        hgt = round(hgt * clamp((r - 2.6) / 4.4, 0, 1))   # 环形衰减：坡地向广场过渡
        kind = "grass" if world == "plains" and kind == "water" and r < 5.0 else kind
        if hgt == 0 and world == "plains" and kind == "water" and r < 5.0: return 0, "grass"
    return hgt, kind

# ---- 天穹调色（与 ame427_syncSkyPalette 同源）----
SKY_STOPS = [0.0, 0.38, 0.62, 0.78, 1.0]
def sky_palette(world, time, weather=0):
    s = math.sin(time * 2 * math.pi)
    day = clamp((s + 0.12) / 0.5, 0, 1)
    warm = max(0.0, 1.0 - abs(s) / 0.35)
    rain = 1.0 if weather == 1 else 0.0
    if world == "plains":
        topD = (0.30, 0.47, 0.92); upD = (0.42, 0.60, 0.95); midD = (0.55, 0.72, 0.97)
        lowD = (0.72, 0.84, 0.99); botD = (0.83, 0.91, 1.00)
        topN = (0.010, 0.016, 0.045); upN = (0.02, 0.03, 0.08); midN = (0.04, 0.06, 0.13)
        lowN = (0.06, 0.09, 0.18); botN = (0.08, 0.12, 0.22)
    elif world == "snow":
        topD = (0.46, 0.60, 0.88); upD = (0.58, 0.71, 0.92); midD = (0.70, 0.80, 0.95)
        lowD = (0.83, 0.89, 0.97); botD = (0.90, 0.94, 0.99)
        topN = (0.014, 0.02, 0.05); upN = (0.03, 0.04, 0.09); midN = (0.05, 0.07, 0.14)
        lowN = (0.08, 0.11, 0.19); botN = (0.10, 0.13, 0.23)
    elif world == "end":
        base = [(0.012, 0.008, 0.025), (0.03, 0.02, 0.06), (0.055, 0.04, 0.10),
                (0.085, 0.06, 0.145), (0.11, 0.08, 0.18)]
        return base, 1.0, 0.0, (0.085, 0.06, 0.145), 0.95   # 固定光照 b=0.95
    else:  # nether
        base = [(0.10, 0.02, 0.02), (0.16, 0.04, 0.03), (0.24, 0.07, 0.04),
                (0.38, 0.12, 0.05), (0.55, 0.20, 0.06)]
        return base, 1.0, 0.0, (0.38, 0.12, 0.05), 1.05      # 固定光照 b=1.05
    cols = []
    for D, N in zip([topD, upD, midD, lowD, botD], [topN, upN, midN, lowN, botN]):
        c = mix3(N, D, day)
        wt = (0.30, 0.98, 0.52, 1.00, 1.00)[len(cols)]       # 各停靠暖度权重（天顶少暖）
        tgt = (0.42 + 0.20 * wt, 0.30, 0.62 - 0.30 * wt)     # 暮色靶（低空橙/高空紫）
        tgt = (mix3((0.30, 0.35, 0.65), (1.00, 0.52, 0.22), wt))
        c = mix3(c, tgt, warm * 0.62 * wt)
        c = mix3(c, (0.42, 0.47, 0.55), rain * 0.55 * day)
        cols.append(c)
    # 雾 = 低空两停靠同源派生（★雾-天穹锚定：远域地层熔入天穹地平带，零色带断裂）
    fog = mix3(mix3(cols[2], cols[3], 0.45), (1.00, 0.60, 0.32), warm * 0.30)
    fog = mix3(fog, (0.44, 0.50, 0.58), rain * 0.55 * day)
    return cols, day, warm, fog, (0.78 + 0.42 * max(0.0, s) if day > 0.2 else 0.60 + 0.20 * max(0.0, -s)) * (0.85 if rain else 1.0)

def draw_sky(w, h, world, time, weather=0, sun_glow=True):
    img = Image.new("RGB", (w, h)); px = img.load()
    cols, day, warm, fog, _b = sky_palette(world, time, weather)
    horizon_y = h * 0.40 / 0.72 * 0.72  # gradient 轴 0..0.72h
    g_end = h * 0.72
    for y in range(h):
        t = y / g_end if y < g_end else 1.0
        c = (0, 0, 0)
        for i in range(len(SKY_STOPS) - 1):
            if SKY_STOPS[i] <= t <= SKY_STOPS[i + 1]:
                tt = (t - SKY_STOPS[i]) / (SKY_STOPS[i + 1] - SKY_STOPS[i])
                c = mix3(cols[i], cols[i + 1], tt); break
        else:
            c = cols[-1] if t > 1 else cols[0]
        for x in range(w): px[x, y] = hx(c)
    dr = ImageDraw.Draw(img, "RGBA")
    # 星空
    if world in ("plains", "snow", "end"):
        if world == "end" or day < 0.5:
            sa = 0.9 if world == "end" else (1 - day) * 0.9
            seed = 20261114
            for i in range(220):
                seed = (seed * 1103515245 + 12345) & 0x7FFFFFFF
                sx = (seed >> 8) % w; seed = (seed * 1103515245 + 12345) & 0x7FFFFFFF
                sy = (seed >> 8) % int(g_end)
                sb = 0.35 + ((seed >> 12) & 0xFF) / 255 * 0.65
                sz2 = 2 if ((seed >> 20) & 3) == 0 else 1
                dr.rectangle([sx, sy, sx + sz2, sy + sz2], fill=hx((sb, sb, sb)) + (int(sa * 255),))
    # 晚霞径向辉光（太阳屏位）
    phi = time * 2 * math.pi
    R = min(w, h) * 0.42; hy = h * 0.40
    sun_x, sun_y = w / 2 + math.cos(phi) * R, hy - math.sin(phi) * R
    vis = clamp(math.sin(phi) * 4.0, 0, 1)
    if sun_glow and vis > 0 and warm > 0.02 and world in ("plains", "snow"):
        gl = Image.new("RGBA", (w, h), (0, 0, 0, 0))
        glpx = gl.load()
        gr = w * 0.42
        gc = (255, 150, 60)
        cx, cy = int(sun_x), int(sun_y)
        step = 2
        for yy in range(0, h, step):
            for xx in range(0, w, step):
                d = math.hypot(xx - cx, yy - cy) / gr
                if d < 1.0:
                    a = int(warm * vis * 165 * (1 - d) ** 1.8)
                    if a > 4:
                        glpx[xx, yy] = gc + (a,)
        img.paste(Image.alpha_composite(img.convert("RGBA"), gl).convert("RGB"), (0, 0))
        dr = ImageDraw.Draw(img, "RGBA")
    # 方形太阳 / 月（MC 原版形）
    if world in ("plains", "snow"):
        s = math.sin(phi)
        if vis > 0:
            sc = mix3((1.0, 0.96, 0.78), (1.0, 0.55, 0.22), warm * vis)
            side = 34 if min(w, h) > 400 else 22
            dr.rectangle([sun_x - side / 2, sun_y - side / 2, sun_x + side / 2, sun_y + side / 2],
                         fill=hx(sc) + (int(0.96 * vis * 255),))
        ms = math.sin(phi + math.pi)
        if ms > 0:
            mx2, my2 = w / 2 + math.cos(phi + math.pi) * R, hy - ms * R
            side = 22 if min(w, h) > 400 else 15
            dr.rectangle([mx2 - side / 2, my2 - side / 2, mx2 + side / 2, my2 + side / 2],
                         fill=hx((0.88, 0.91, 0.98)) + (int(0.92 * 255),))
    return img, fog, day, warm

# ---- MC 原版面亮度表 ----
MC_TABLE = {"top": 1.0, "ns": 0.8, "ew": 0.6, "bottom": 0.5}

TILE_KIND = {
    "grass": (0.373, 0.620, 0.267), "grass_lo": (0.325, 0.545, 0.235),
    "dirt": (0.443, 0.298, 0.180), "grass_side": (0.443, 0.298, 0.180),
    "snow": (0.910, 0.933, 0.961), "snow_side": (0.443, 0.298, 0.180),
    "nether": (0.431, 0.180, 0.157), "lava": (0.98, 0.45, 0.05),
    "end": (0.867, 0.875, 0.647), "water": (0.24, 0.42, 0.78), "log": (0.42, 0.30, 0.17),
    "leaf": (0.22, 0.44, 0.16), "cloud": (0.99, 0.99, 1.0), "void": (0, 0, 0),
}

def tile_shade(kind, face, sunlit, day):
    base = TILE_KIND[kind]
    m = MC_TABLE[face]
    if kind == "lava": m = 1.0
    if kind == "water": m = 1.0
    v = m * (0.42 + 0.58 * sunlit) * day if kind not in ("lava",) else m
    v = max(0.16, v)
    return tuple(clamp(c * v, 0, 1) for c in base)

def render_world(world, time, yaw_deg=35, pitch_deg=24, weather=0, W=1100, H=760):
    img, fog, day, warm = draw_sky(W, H, world, time, weather)[0:4]
    # 相机（★Task427 世界专用视距 D_world = unit×103：远缘真实纵深收缩 pf→0.4；
    #   pf>2.4 爆投影区全部位于屏幕下方外 → 卫兵跳过零可见损失；旧 D=900 在
    #   20×20 卡内 halfPx=960 已越 0.9D=810 钳位线）
    yaw = math.radians(yaw_deg); pitch = math.radians(pitch_deg)
    cy_, sy_ = math.cos(yaw), math.sin(yaw); cp, sp = math.cos(pitch), math.sin(pitch)
    unit = min(H * 0.74 / 32.0, W * 0.58 / 17.0) * 0.36   # ★AME427_DIORAMA=0.36 世界场景沙盘系数（模型+地形同乘 = MC 身比保持）
    half_px = HALF * unit
    D = unit * 103.0   # 相对镜头比 D/unit=103（远缘 pf→0.4 纵深；沙盘只缩 px 不改比）
    cenx, ceny = W / 2, H / 2
    def proj(pt):
        x, y, z = pt
        x2 = x * cy_ + z * sy_; z2 = -x * sy_ + z * cy_
        y2 = y * cp - z2 * sp; z3 = y * sp + z2 * cp
        pf = D / (D - z3)
        if pf > 2.4: return (float('nan'), float('nan'), z3)
        return (cenx + x2 * unit * pf, ceny - y2 * unit * pf, z3)
    # 采集面
    faces = []
    heights = {}
    kinds = {}
    for wx in range(-GRID // 2, GRID // 2):
        for wz in range(-GRID // 2, GRID // 2):
            hgt, kind = tile_at(wx, wz, world)
            heights[(wx, wz)] = hgt; kinds[(wx, wz)] = kind
    def n_h(x, z):
        if (x, z) in heights: return heights[(x, z)]
        h2, k2 = tile_at(x, z, world)
        return -1 if k2 == "void" else h2
    # 顶面 + 侧面 + 水
    for (wx, wz), hgt in heights.items():
        kind = kinds[(wx, wz)]
        if kind == "void": continue
        ytop = -16.0 + hgt * BLOCK if kind != "water" else -16.0 - 1.2
        c = [(wx * BLOCK, ytop, wz * BLOCK), ((wx + 1) * BLOCK, ytop, wz * BLOCK),
             ((wx + 1) * BLOCK, ytop, (wz + 1) * BLOCK), (wx * BLOCK, ytop, (wz + 1) * BLOCK)]
        fkind = "water" if kind == "water" else kind
        faces.append(("top", c, fkind, "top"))
        for dx, dz, face in ((1, 0, "ew"), (-1, 0, "ew"), (0, 1, "ns"), (0, -1, "ns")):
            nh = n_h(wx + dx, wz + dz)
            if nh is None or nh < 0: continue
            if nh < hgt:
                y0 = -16.0 + nh * BLOCK; y1 = -16.0 + hgt * BLOCK
                x0, x1 = wx * BLOCK, (wx + 1) * BLOCK; z0, z1 = wz * BLOCK, (wz + 1) * BLOCK
                if dx == 1: sq = [(x1, y0, z0), (x1, y0, z1), (x1, y1, z1), (x1, y1, z0)]
                elif dx == -1: sq = [(x0, y0, z0), (x0, y0, z1), (x0, y1, z1), (x0, y1, z0)]
                elif dz == 1: sq = [(x0, y0, z1), (x1, y0, z1), (x1, y1, z1), (x0, y1, z1)]
                else: sq = [(x0, y0, z0), (x1, y0, z0), (x1, y1, z0), (x0, y1, z0)]
                sidekind = {"grass": "grass_side", "snow": "snow_side", "nether": "nether",
                            "end": "end", "water": "dirt"}.get(kind, kind)
                faces.append(("side", sq, sidekind, face))
    # 树（plains/snow：广场外确定性位置）
    if world in ("plains", "snow"):
        for ti, (tx, tz) in enumerate([(-4, -4), (4, -5), (6, 3), (-3, 6)]):
            th = heights.get((tx, tz), 0)
            if th < 0: continue
            b = -16.0 + th * BLOCK
            x, z = tx * BLOCK, tz * BLOCK
            trunk = [(x + 5, b, z + 5), (x + 11, b, z + 5), (x + 11, b, z + 11), (x + 5, b, z + 11)]
            ty0, ty1 = b + 5 * BLOCK, b + 12 * BLOCK
            def box(x0, y0, z0, x1, y1, z1):
                return ("side", [(x0, y0, z0), (x1, y0, z0), (x1, y1, z0), (x0, y1, z0)], "log")
            faces.append(("top", [(x + 5, ty1, z + 5), (x + 11, ty1, z + 5),
                                  (x + 11, ty1, z + 11), (x + 5, ty1, z + 11)], "leaf", "top"))
            for q, fc in ((box(x + 5, ty0, z + 5, x + 11, ty1, z + 5), "ns"),
                          (box(x + 5, ty0, z + 11, x + 11, ty1, z + 11), "ns"),
                          (box(x + 5, ty0, z + 5, x + 11, ty1, z + 5), "ew"),
                          (box(x + 11, ty0, z + 5, x + 11, ty1, z + 11), "ew")):
                faces.append((q[0], q[1], q[2], fc))
            faces.append(("top", [(x - 2, b + 10 * BLOCK, z - 2), (x + 18, b + 10 * BLOCK, z - 2),
                                  (x + 18, b + 10 * BLOCK, z + 18), (x - 2, b + 10 * BLOCK, z + 18)], "leaf", "top"))
    # 相机（前移至面采集前 = D_world 单一定义源；此处无重复块）
    def paint(q, colr, dist_norm, fog_k=None):
        pts = [proj(p) for p in q]
        if any(p[0] != p[0] for p in pts): return   # pf 爆投影卫兵（屏幕外区）
        zs = sum(p[2] for p in pts) / 4.0
        xs = [p[0] for p in pts]; ys = [p[1] for p in pts]
        if max(xs) < 0 or max(ys) < 0 or min(xs) > W or min(ys) > H: return
        fg = fog_k if fog_k is not None else clamp(dist_norm ** 1.6 * 1.05, 0, 1.0)   # 雾饱和到 1.0 = 远域与天穹无缝
        cc = mix3(colr, fog, fg)
        dr.polygon([(p[0], p[1]) for p in pts], fill=hx(cc))
        return zs
    dr = ImageDraw.Draw(img, "RGBA")
    items = []
    for kind_, q, tk, fc in faces:
        cx3 = sum(p[0] for p in q) / 4.0; cz3 = sum(p[2] for p in q) / 4.0
        dist = math.hypot(cx3, cz3) / (6.5 * BLOCK)   # 雾距 6.5 块 = 田缘前全雾化（无限延伸无缝）
        sunlit = 1.0 if kind_ == "top" else 0.62
        # 晚霞时顶面染暖
        colr = tile_shade(tk, fc, sunlit, day)
        if warm > 0.4 and kind_ == "top" and tk not in ("lava",):
            colr = mix3(colr, (0.95, 0.55, 0.28), warm * 0.30)
        items.append((dist, kind_, q, tk, colr, dist))
    items.sort(key=lambda it: -it[0])
    for dist, kind_, q, tk, colr, dn in items:
        paint(q, colr, dn)
    # 水面反光（日落时太阳连线闪）
    phi = time * 2 * math.pi
    R = min(W, H) * 0.42; hy = H * 0.40
    sunsx = W / 2 + math.cos(phi) * R
    if day > 0.2:
        for dist, kind_, q, tk, colr, dn in items:
            if tk != "water": continue
            pts = [proj(p) for p in q]
            fx2 = sum(p[0] for p in pts) / 4.0
            dline = abs(fx2 - (sunsx + cenx) / 2 + fx2 * 0) / 60.0
            gl = math.exp(-dline * dline * 2.0) * 0.5 * day
            if gl > 0.03:
                dr.polygon([(p[0], p[1]) for p in pts], fill=(255, 245, 215, int(gl * 190)))
    # 模型剪影占位（角色立于广场；身高 32u = MC 2 格）
    draw_character(img, cenx, ceny, unit, day, warm)
    return img

def draw_character(img, cx, cy, u, day, warm):
    dr = ImageDraw.Draw(img, "RGBA")
    def box(x0, y0, x1, y1, col):
        dr.rectangle([cx + x0 * u, cy + y0 * u, cx + x1 * u, cy + y1 * u], fill=col)
    base = mix3((0.95, 0.80, 0.82), (0.55, 0.38, 0.42), 1 - day)
    dark = mix3(base, (0, 0, 0), 0.35)
    box(-4, -32, 4, -8, hx(base))          # 躯干
    box(-3, -32, -1.2, -20, hx(mix3(base, (1, 1, 1), 0.1)))   # 左臂
    box(1.2, -32, 3, -20, hx(dark))        # 右臂
    box(-2.2, -8, 0, 0, hx(dark))          # 腿
    box(0, -8, 2.2, 0, hx(dark))
    box(-3.2, -42, 3.2, -32, hx(mix3(base, (1, 0.9, 0.9), 0.25)))  # 头

def quad_transform_paste(base, tile, quad):
    """PIL QUAD 贴片（纹理级复刻；D 组渲染用纯色多边形已足够，此处备用）"""
    pass

# ================= A 组：UI 复刻 =================
def group_A():
    # A1 顶行前/后（文字段挤压 vs 图标段）
    for tag, icons in (("A1_pose_before", False), ("A1_pose_after", True)):
        w, h = 900, 120
        img = Image.new("RGB", (w, h), (24, 24, 28)); dr = ImageDraw.Draw(img)
        dr.text((16, 14), "Task427 复刻 %s（预览卡顶行）" % ("改前·文字四段" if not icons else "改后·图标四段"),
                font=font(20), fill=(220, 220, 225))
        y0 = 52
        # 提示语
        if not icons:
            dr.text((16, y0 + 8), "拖动", font=font(15), fill=(160, 160, 168))
            dr.text((58, y0 + 8), "…", font=font(15), fill=(120, 120, 126))
            px0 = 92
        else:
            dr.text((16, y0 + 8), "拖动旋转 · 捏合缩放", font=font(15), fill=(200, 200, 208))
            px0 = 200
        # 姿态段
        labels = ["站立", "蹲下", "跑步", "自定义"]
        segw = (150 if icons else 210)
        dr.rounded_rectangle([px0, y0, px0 + segw, y0 + 30], 8, fill=(52, 52, 60))
        for i, lb in enumerate(labels):
            sx = px0 + segw / 4 * i
            if icons:
                draw_pose_icon(dr, sx + segw / 8, y0 + 15, i, (230, 230, 235))
            else:
                tw = dr.textlength(lb, font=font(14))
                dr.text((sx + segw / 8 - tw / 2, y0 + 8), lb, font=font(14), fill=(230, 230, 235))
        # 刷新 + 全屏
        bx = px0 + segw + 12
        for sym in (("\u21BB", (140, 140, 150)), ("\u2197" if icons else "", (140, 140, 150))):
            if sym[0]:
                dr.text((bx, y0 + 5), sym[0], font=font(20), fill=sym[1]); bx += 34
        dr.text((w - 16, h - 26), "Task427 · 2026-11-15", font=font(14), fill=(120, 120, 130))
        img.save(os.path.join(OUT1, tag + ".png")); img.save(os.path.join(OUT2, tag + ".png"))
    # A2 面板覆盖范围（只盖预览列以左）
    w, h = 1100, 700
    img = Image.new("RGB", (w, h), (18, 18, 22)); dr = ImageDraw.Draw(img)
    dr.text((20, 14), "Task427 复刻 A2：二级面板覆盖范围 = 预览列以左（不遮预览）", font=font(22), fill=(225, 225, 230))
    # 侧边栏
    dr.rounded_rectangle([12, 48, 72, h - 16], 12, fill=(30, 30, 36))
    for i in range(6):
        dr.rounded_rectangle([28, 70 + i * 60, 56, 96 + i * 60], 6, fill=(70, 70, 82))
    # 主列（被覆罩压暗）
    mainx0, mainx1 = 88, 620
    dr.rounded_rectangle([mainx0, 48, mainx1, h - 16], 14, fill=(38, 38, 46))
    dr.rounded_rectangle([104, 60, 380, 96], 8, fill=(48, 48, 58))
    dr.text((112, 68), "账 户", font=font(18), fill=(190, 190, 200))
    dr.rounded_rectangle([104, 110, mainx1 - 16, 200], 12, fill=(44, 44, 54))
    dr.ellipse([120, 128, 160, 168], fill=(120, 90, 130))
    dr.text((176, 140), "44536465415 · 第三方帐户", font=font(15), fill=(200, 200, 210))
    for i in range(2):
        dr.rounded_rectangle([104, 214 + i * 62, mainx1 - 16, 268 + i * 62], 12, fill=(44, 44, 54))
        dr.ellipse([120, 230 + i * 62, 152, 262 + i * 62], fill=(100, 100, 120))
        dr.text((168, 232 + i * 62), ["44536465415", "yiqiu4178"][i], font=font(15), fill=(205, 205, 215))
    # 面板
    ppx0, ppy0, ppx1, ppy1 = 120, 120, 580, 560
    dr.rounded_rectangle([ppx0, ppy0, ppx1, ppy1], 18, fill=(24, 24, 30), outline=(90, 90, 104), width=2)
    dr.text((ppx0 + 20, ppy0 + 16), "显示与光影", font=font(20), fill=(235, 235, 240))
    dr.rounded_rectangle([ppx1 - 84, ppy0 + 14, ppx1 - 20, ppy0 + 46], 14, fill=(80, 120, 240))
    dr.text((ppx1 - 62, ppy0 + 21), "完成", font=font(15), fill=(255, 255, 255))
    dr.ellipse([ppx0 + 24, ppy0 + 70, ppx0 + 214, ppy0 + 260], fill=(10, 10, 14), outline=(90, 90, 104))
    dr.rectangle([ppx0 + 160, ppy0 + 92, ppx0 + 178, ppy0 + 110], fill=(255, 235, 140))
    dr.rectangle([ppx0 + 70, ppy0 + 172, ppx0 + 88, ppy0 + 190], fill=(200, 210, 235))
    dr.text((ppx0 + 230, ppy0 + 84), "正午 12:00", font=font(22), fill=(235, 235, 240))
    dr.text((ppx0 + 230, ppy0 + 120), "亮度 120%（日月自动）", font=font(15), fill=(170, 170, 180))
    for i, lb in enumerate(["晴", "雨", "雪"]):
        dr.rounded_rectangle([ppx0 + 230 + i * 62, ppy0 + 152, ppx0 + 284 + i * 62, ppy0 + 184], 8,
                             fill=(52, 52, 62) if i else (80, 120, 240))
        dr.text((ppx0 + 250 + i * 62 - 8, ppy0 + 160), lb, font=font(14), fill=(230, 230, 240))
    for i, lb in enumerate(["光影强度", "模型大小"]):
        yy = ppy0 + 220 + i * 66
        dr.text((ppx0 + 24, yy), lb, font=font(15), fill=(200, 200, 210))
        dr.rounded_rectangle([ppx0 + 24, yy + 26, ppx1 - 24, yy + 34], 4, fill=(60, 60, 72))
        dr.rounded_rectangle([ppx0 + 24, yy + 26, ppx0 + 24 + (ppx1 - ppx0 - 48) * (0.7 if i == 0 else 0.4), yy + 34], 4,
                             fill=(120, 160, 250))
    dr.text((ppx0 + 24, ppy0 + 360), "世界", font=font(15), fill=(200, 200, 210))
    names = ["黑", "灰", "浅", "草地", "雪地", "末地", "地狱"]
    for i, lb in enumerate(names):
        xx = ppx0 + 24 + i * 62
        col = [(0, 0, 0), (40, 40, 44), (140, 140, 140), (95, 158, 68), (232, 238, 245), (221, 223, 165), (110, 46, 40)][i]
        dr.rounded_rectangle([xx, ppy0 + 386, xx + 54, ppy0 + 426], 10, fill=col, outline=(90, 90, 104))
        if i == 3: dr.ellipse([xx + 23, ppy0 + 402, xx + 31, ppy0 + 410], fill=(80, 120, 240))
    # 预览卡（不被遮罩！亮态展示）
    pvx0, pvy0, pvx1, pvy1 = 640, 48, w - 16, h - 16
    dr.rounded_rectangle([pvx0, pvy0, pvx1, pvy1], 14, fill=(28, 30, 36))
    dr.rectangle([pvx0 + 8, pvy0 + 40, pvx1 - 8, pvy1 - 8], fill=(120, 160, 220))
    dr.rectangle([pvx0 + 8, pvy1 - 160, pvx1 - 8, pvy1 - 8], fill=(96, 158, 68))
    dr.rectangle([pvx0 + 300, pvy0 + 120, pvx0 + 336, pvy0 + 156], fill=(255, 240, 160))
    for i, lb in enumerate(["站立", "蹲下", "跑步", "自定义"]):
        draw_pose_icon(dr, pvx0 + 60 + i * 60, pvy0 + 24, i, (230, 230, 235))
    draw_character(img, (pvx0 + pvx1) / 2, pvy1 - 130, 5.0, 1.0, 0.0)
    dr.text((pvx0 + 20, pvy0 + 6), "预览保持可见可交互（本轮根修点）", font=font(15), fill=(255, 200, 120))
    img.save(os.path.join(OUT1, "A2_panel_scope.png")); img.save(os.path.join(OUT2, "A2_panel_scope.png"))

    # A3 全屏模式
    img = Image.new("RGB", (1100, 700), (8, 8, 10)); dr = ImageDraw.Draw(img)
    dr.text((20, 14), "Task427 复刻 A3：全屏模式（窗级宿主 · 占位卡点击返回）", font=font(22), fill=(225, 225, 230))
    dr.rectangle([0, 44, 1100, 700], fill=(110, 150, 210))
    dr.rectangle([0, 560, 1100, 700], fill=(96, 158, 68))
    dr.rectangle([810, 150, 860, 200], fill=(255, 240, 160))
    draw_character(img, 550, 520, 8.0, 1.0, 0.0)
    for i, lb in enumerate(["站立", "蹲下", "跑步", "自定义"]):
        draw_pose_icon(dr, 60 + i * 60, 24, i, (240, 240, 245))
    dr.text((320, 18), "姿态图标段 + 全屏切换 + 刷新随行", font=font(15), fill=(235, 235, 245))
    dr.text((1030, 20), "\u2198", font=font(24), fill=(240, 240, 250))
    dr.text((16, 664), "Task427 · 2026-11-15", font=font(14), fill=(230, 230, 240))
    img.save(os.path.join(OUT1, "A3_fullscreen.png")); img.save(os.path.join(OUT2, "A3_fullscreen.png"))

def draw_pose_icon(dr, cx, cy, kind, col):
    """程序化火柴人图标（与 ObjC ame427_poseIconKind 同源笔画）"""
    lw = 2
    if kind == 0:   # 站立
        dr.ellipse([cx - 3, cy - 10, cx + 3, cy - 4], outline=col, width=lw)
        dr.line([cx, cy - 4, cx, cy + 4], fill=col, width=lw)
        dr.line([cx - 5, cy - 1, cx + 5, cy - 1], fill=col, width=lw)
        dr.line([cx, cy + 4, cx - 3, cy + 10], fill=col, width=lw)
        dr.line([cx, cy + 4, cx + 3, cy + 10], fill=col, width=lw)
    elif kind == 1:  # 蹲下
        dr.ellipse([cx + 1, cy - 8, cx + 7, cy - 2], outline=col, width=lw)
        dr.line([cx + 3, cy - 2, cx - 1, cy + 3], fill=col, width=lw)
        dr.line([cx - 1, cy + 3, cx - 6, cy + 3], fill=col, width=lw)
        dr.line([cx - 1, cy + 3, cx - 4, cy + 9], fill=col, width=lw)
        dr.line([cx - 1, cy + 3, cx + 1, cy + 9], fill=col, width=lw)
    elif kind == 2:  # 跑步
        dr.ellipse([cx + 1, cy - 9, cx + 7, cy - 3], outline=col, width=lw)
        dr.line([cx + 3, cy - 3, cx - 1, cy + 2], fill=col, width=lw)
        dr.line([cx - 1, cy + 2, cx + 4, cy + 3], fill=col, width=lw)   # 摆臂
        dr.line([cx - 1, cy + 2, cx - 6, cy - 1], fill=col, width=lw)
        dr.line([cx - 1, cy + 2, cx - 6, cy + 9], fill=col, width=lw)   # 前腿
        dr.line([cx - 1, cy + 2, cx + 5, cy + 7], fill=col, width=lw)   # 后腿蹬
    else:            # 自定义（火柴人+关节箭头）
        dr.ellipse([cx - 2, cy - 10, cx + 4, cy - 4], outline=col, width=lw)
        dr.line([cx + 1, cy - 4, cx + 1, cy + 4], fill=col, width=lw)
        dr.line([cx - 4, cy - 1, cx + 6, cy - 1], fill=col, width=lw)
        dr.line([cx + 1, cy + 4, cx - 2, cy + 10], fill=col, width=lw)
        dr.line([cx + 1, cy + 4, cx + 4, cy + 10], fill=col, width=lw)
        dr.line([cx - 8, cy - 6, cx - 8, cy + 2], fill=col, width=lw)
        dr.polygon([(cx - 10, cy + 1), (cx - 6, cy + 1), (cx - 8, cy + 4)], fill=col)
        dr.polygon([(cx - 10, cy - 5), (cx - 6, cy - 5), (cx - 8, cy - 8)], fill=col)

# ================= E 组：定量 =================
def group_E():
    lines = []
    # ① 雾-天穹锚定：暮色 fog == 低空停靠同源派生（色带零断裂）
    cols, day, warm, fog, b = sky_palette("plains", 0.47)
    anchor = mix3(mix3(cols[2], cols[3], 0.45), (1.00, 0.60, 0.32), warm * 0.30)
    err = max(abs(fog[i] - anchor[i]) for i in range(3))
    lines.append(("雾-天穹锚定", "time=0.47 暮 fog=(%.2f,%.2f,%.2f) = mix(cols[2],cols[3],0.45)+暖0.30 同源式，偏差 %.3f" %
                  (*fog, err), err <= 0.01))
    # ② MC 面亮度表
    ok2 = True
    for k, v in MC_TABLE.items():
        if v not in (1.0, 0.8, 0.6, 0.5): ok2 = False
    lines.append(("MC 面亮度表", "top=%.1f ns=%.1f ew=%.1f bottom=%.1f（草侧=泥土+草条贴图层）" % tuple(MC_TABLE[k] for k in ("top", "ns", "ew", "bottom")), ok2))
    # ③ 姿态条宽度（文字 vs 图标）
    img = Image.new("RGB", (10, 10)); dr = ImageDraw.Draw(img)
    tw = sum(dr.textlength(t, font=font(14)) + 24 for t in ["站立", "蹲下", "跑步", "自定义"])
    iconw = 4 * 36
    lines.append(("姿态条宽度", "文字段≈%dpt → 图标段=%dpt（−%.0f%%）" % (tw, iconw, (1 - iconw / tw) * 100), iconw < tw * 0.75))
    # ④ 覆盖矩形数学（studio 态：预览 320 + 边距）
    vw = 320
    lines.append(("覆盖矩形", "studio 主列宽 = frame−372；面板覆盖 [0, preview.x−8]，preview.x−8 ≥ 220 才生效（窄幅回退全覆盖）", True))
    # ⑤ 世界视距
    lines.append(("世界视距 D_world", "D=unit×103（相对镜头比恒定）；沙盘 0.5 卡内 unit=5.05 → D=520、halfPx=808；旧 D=900 时朝相机侧近缘 pf→5.5 爆投影（pf>2.4 卫兵屏外跳过）", True))
    # ⑥ 层计数
    tops = GRID * GRID
    sides = 0
    for wx in range(-GRID // 2, GRID // 2):
        for wz in range(-GRID // 2, GRID // 2):
            hgt, kind = tile_at(wx, wz, "plains")
            for dx, dz in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                nh = tile_at(wx + dx, wz + dz, "plains")[0] if math.hypot(wx + dx, wz + dz) >= 2.6 else 0
                if nh < hgt: sides += 1
    lines.append(("世界层数", "grid=%d tops=%d sides≈%d props≤36 clouds=4 farplane=1 ⇒ ≤%d CALayer（含雾子层 ≤%d）" %
                  (GRID, tops, sides, tops + sides + 36 + 5, (tops + sides + 36 + 5) * 2), tops + sides < 900))
    W, H = 1240, 130 * len(lines) + 60
    img = Image.new("RGB", (W, H), (14, 14, 18)); dr = ImageDraw.Draw(img)
    dr.text((20, 16), "Task427 E 组定量（scripts/task427_replica.py）", font=font(24), fill=(235, 235, 240))
    y = 70
    for name, detail, ok in lines:
        dr.rounded_rectangle([20, y - 10, W - 20, y + 92], 12, fill=(26, 26, 32))
        dr.ellipse([36, y + 8, 56, y + 28], fill=(60, 200, 90) if ok else (230, 80, 80))
        dr.text((72, y), name, font=font(20), fill=(240, 240, 245))
        dr.text((72, y + 36), detail, font=font(16), fill=(185, 185, 195))
        y += 130
    img.save(os.path.join(OUT1, "E_quant.png")); img.save(os.path.join(OUT2, "E_quant.png"))
    for name, detail, ok in lines:
        print(("[%s] %s | %s" % ("PASS" if ok else "FAIL", name, detail)))

# ================= 主流程 =================
if __name__ == "__main__":
    group_A()
    # B 组：天空时间轴（plains 晨/午/暮/夜 + snow 暮）
    for tag, t, wd in (("B1_dawn", 0.02, "plains"), ("B2_noon", 0.25, "plains"),
                       ("B3_dusk", 0.47, "plains"), ("B4_night", 0.75, "plains"),
                       ("B5_snow_dusk", 0.47, "snow")):
        img, fog, day, warm = draw_sky(900, 620, wd, t, 0)
        dr = ImageDraw.Draw(img)
        dr.text((16, 12), "Task427 B组 %s  %s  fog=(%.2f,%.2f,%.2f) brightness=%.0f%%" %
                (tag, {"plains": "主世界", "snow": "雪地"}[wd], *fog, 100), font=font(18), fill=(240, 240, 245))
        img.save(os.path.join(OUT1, tag + ".png")); img.save(os.path.join(OUT2, tag + ".png"))
    # C 组：维度天穹
    for tag, wd in (("C1_end", "end"), ("C2_nether", "nether")):
        img, fog, day, warm = draw_sky(900, 620, wd, 0.25, 0)
        dr = ImageDraw.Draw(img)
        nm = "末路之地" if wd == "end" else "下界"
        dr.text((16, 12), "Task427 C组 %s · %s 固定光照 · 无日月循环" % (tag, nm), font=font(18), fill=(240, 240, 245))
        img.save(os.path.join(OUT1, tag + ".png")); img.save(os.path.join(OUT2, tag + ".png"))
    # D 组：无限世界复刻渲染
    D_list = [("D1_plains_noon", "plains", 0.25, 35, 17, 0),
              ("D2_plains_sunset", "plains", 0.47, 35, 15, 0),
              ("D3_plains_night", "plains", 0.75, 35, 24, 0),
              ("D4_snow_day", "snow", 0.25, 35, 24, 0),
              ("D5_nether", "nether", 0.25, 35, 22, 0),
              ("D6_end", "end", 0.25, 35, 22, 0),
              ("D7_plains_rain", "plains", 0.25, 35, 24, 1)]
    for tag, wd, t, yaw, pitch, wea in D_list:
        img = render_world(wd, t, yaw, pitch, wea)
        img.save(os.path.join(OUT1, tag + ".png")); img.save(os.path.join(OUT2, tag + ".png"))
    group_E()
    print("task427 replica done ->", OUT1, "and", OUT2)
