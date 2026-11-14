#!/usr/bin/env python3
# task425_replica.py -- Task425 取证复刻（Python 先行）：用户 IMG_0671（Task424
# 装机）六复诉：
#   ①「手臂3d凸起下面是透明的」→ 病根 = AME419_CUTOUT_MIN=26 比 skinview3d
#     基础层口径严 26 倍（model.ts 亲验：innerLayer = MeshStandardMaterial 仅
#     side:FrontSide，无 transparent 无 alphaTest = alphaTest 0 = α≥1 像素全部
#     保留且以不透明形式绘制；outerLayer 才 alphaTest 1e-5）。α∈[1,25] 的淡
#     像素（渐变边缘/柔和阴影/发梢）在 sv3d 是实心，在我们这里是透明洞 =
#     透过外层袖子凸起看到洞后背景。修复 = CUTOUT_MIN 26→1（α≥1 强制不透明，
#     α=0 真镂空保留）。
#   ②「按钮塞不下 → 二级菜单」③「调节器太小 → 单独二级菜单」④「不跟手」
#     → UI 面（ObjC 落码面），D 组 mock 设计稿。
#   ⑤「光影程度和质量太低」→ 旧公式面间罩差仅 ~0.20（floor0.5225+cap0.60+
#     gain0.85 = dot 正背差 0.2 opacity）= 看不出光影；新公式 = 对比度通道
#     depth=(1-lit)*0.85*(c/2) + highlight 白亮罩，c∈[0,2] 默认 1.4 → 面间差
#     ~0.5 = 显著立体。B 组定量矩阵。
#   ⑥「预设背景：草地/雪地/末地/地狱 3D 世界」→ C 组四联设计稿（天空渐变+
#     方块地面 CPU 投影+雾+太阳+脚影）。
import math
import os
import importlib.util

HERE = os.path.dirname(os.path.abspath(__file__))
_spec = importlib.util.spec_from_file_location(
    "rep420", os.path.join(HERE, "task420_skin_preview_replica.py"))
rep = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(rep)

spec2 = importlib.util.spec_from_file_location(
    "rep422", os.path.join(HERE, "task422_forensic_replica.py"))
rep422 = importlib.util.module_from_spec(spec2)
spec2.loader.exec_module(rep422)

from PIL import Image, ImageDraw, ImageFont, ImageFilter

OUT = os.path.join(HERE, "task425_evidence")
os.makedirs(OUT, exist_ok=True)

BG = (41, 41, 41)
D = 900.0
PART_NAMES = ["head", "body", "rarm", "larm", "rleg", "lleg"]
DEF_AZ, DEF_EL = -0.606, 0.668

FONT = None
try:
    FONT = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", 13)
    FONT_S = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", 11)
except Exception:
    FONT = ImageFont.load_default()


def label(draw, text, xy, fill=(230, 230, 230), small=False):
    draw.text(xy, text, fill=fill, font=FONT_S if small else FONT)


def light_vec(az, el):
    return (math.cos(el) * math.sin(az), math.sin(el), math.cos(el) * math.cos(az))


def rot_z(x, y, th):
    c, s = math.cos(th), math.sin(th)
    return x * c - y * s, x * s + y * c


# ---------- Task425 新着色模型（对齐将来 ObjC ame425 公式） ----------
def shade425(dot, contrast, brightness):
    """对比度双罩模型 v2：lit=(dot+1)/2；
    depth = clamp((1-lit)*1.30*(c/2), 0, 0.88) 黑影罩（c=1.4 → K=0.91，
    dot=-1 → 0.88 深黑 / dot=-0.5 → 0.46 / dot=0 → 0.23 微暗）；
    highlight = clamp((dot-0.45)/0.55,0,1)*0.30*(c/2) 白亮罩
    （dot=0.9 → 0.245 提亮，dot=0.64 → 0.073）；
    brightness b：黑影 ×clamp(2-b,0.25,1.8)，白亮 ×clamp(b,0.25,1.5)。"""
    lit = (dot + 1.0) / 2.0
    c = max(0.0, min(2.0, contrast))
    depth = (1.0 - lit) * 1.30 * (c / 2.0)
    if depth > 0.88:
        depth = 0.88
    hl = max(0.0, min(1.0, (dot - 0.45) / 0.55)) * 0.30 * (c / 2.0)
    dark = depth * max(0.25, min(1.8, 2.0 - brightness))
    white = hl * max(0.25, min(1.5, brightness))
    return dark, white


def render425(skin, slim, yaw, pitch, out_path, unit=10.0, size=(460, 640),
              az=DEF_AZ, el=DEF_EL, brightness=1.15, contrast=1.4,
              cutout=1, pose="stand", phase=0.0, joints=None, bg=BG,
              world=None, hide_model=False, want_stats=False):
    """Task425 渲染复刻：cutout 阈值参数化（26 旧 / 1 新）+ 对比度双罩 +
    世界背景（world dict: sky_top/sky_bot/fog/block/tint太阳等）。"""
    faces = rep.build_model(slim, skin.size[0], skin.size[1])
    ang = {n: (0.0, 0.0, 0.0, 0.0) for n in PART_NAMES}
    if pose == "run":
        sw = 0.50 * math.sin(phase)
        ang["rarm"] = (sw, 0, 0, 0); ang["larm"] = (-sw, 0, 0, 0)
        ang["rleg"] = (-sw, 0, 0, 0); ang["lleg"] = (sw, 0, 0, 0)
    elif pose == "sneak":
        sink = -2.2
        ang["head"] = (-0.42, 0, 0, sink); ang["body"] = (0.30, 0, 0, sink)
        ang["rarm"] = (-0.15, 0, 0, sink); ang["larm"] = (-0.15, 0, 0, sink)
        ang["rleg"] = (-0.35, 0, 0, sink); ang["lleg"] = (-0.35, 0, 0, sink)
    elif pose == "custom":
        ang["head"] = (0, 0, 0.5, 0); ang["rarm"] = (-0.9, -0.85, 0, 0)
        ang["larm"] = (0.4, 0.7, 0, 0); ang["rleg"] = (-0.3, 0, 0, 0)
        ang["lleg"] = (0.2, 0, 0, 0)
    if joints:
        for k, v in joints.items():
            ang[k] = v
    L = light_vec(az, el)
    W, H = size
    if world:
        # 天空渐变（垂直两停）
        grad = Image.new("RGB", (1, H))
        for y in range(H):
            t = y / (H - 1.0)
            grad.putpixel((0, y), tuple(
                int(world["sky_top"][i] * (1 - t) + world["sky_bot"][i] * t)
                for i in range(3)))
        canvas = grad.resize((W, H)).convert("RGBA")
    else:
        canvas = Image.new("RGBA", (W, H), bg + (255,))
    cen = (W / 2.0, H * 0.52)
    recs = []

    # ——世界地面：8×8 方块顶面（y=-16 平面，16 单位方块，CPU 投影同管线）——
    ground_recs = []
    if world:
        GN, GS = 8, 16.0
        for gi in range(GN):
            for gj in range(GN):
                x0 = (gi - GN / 2.0) * GS
                x1 = x0 + GS
                z0 = (gj - GN / 2.0) * GS
                z1 = z0 + GS
                corners = [(x0, -16.0, z0), (x1, -16.0, z0),
                           (x1, -16.0, z1), (x0, -16.0, z1)]
                sx = [0.0] * 4; sy = [0.0] * 4; zsum = 0.0
                ok = True
                for k, (vx, vy, vz) in enumerate(corners):
                    vx, vz = rep.rot_y(vx, vz, yaw)
                    vy, vz = rep.rot_x(vy, vz, pitch)
                    vx *= unit; vy *= unit; vz *= unit
                    pf = D / (D - vz)
                    sx[k] = vx * pf; sy[k] = -vy * pf
                    zsum += vz
                # 顶面法线 (0,1,0) 随 pitch
                ny, nz = rep.rot_x(1.0, 0.0, pitch)
                nx, nzz = 0.0, nz
                nx, nzz = rep.rot_y(0.0, nz, yaw)
                if ny > 0.02:   # 顶面朝上可见
                    ground_recs.append((zsum / 4.0, gi, gj, sx, sy, (nx, ny, nzz)))
        ground_recs.sort(key=lambda r: r[0])
        # 远缘雾基准 = 地面块中心距
        for zpos, gi, gj, sx, sy, nrm in ground_recs:
            shade_dot = (nrm[0] * L[0] + nrm[1] * L[1] + nrm[2] * L[2])
            lit = (shade_dot + 1.0) / 2.0
            depth = (1.0 - lit) * 1.30 * (max(0.0, min(2.0, contrast)) / 2.0) * 0.55
            base = world["block"]
            bb = tuple(int(v * (1.0 - depth)) for v in base)
            # per-block 明度微差（MC 噪点观感）
            jitter = ((gi * 7 + gj * 13) % 5) * 5 - 10
            bb = tuple(max(0, min(255, v + jitter)) for v in bb)
            poly = [(cen[0] + sx[k], cen[1] + sy[k]) for k in range(4)]
            fog_t = math.hypot(gi - 3.5, gj - 3.5) / 5.6
            fog_t = max(0.0, min(1.0, fog_t ** 1.6))
            col = tuple(int(bb[i] * (1 - fog_t) + world["fog"][i] * fog_t)
                        for i in range(3))
            ImageDraw.Draw(canvas).polygon(poly, fill=col + (255,))
        # 脚影（椭圆径向渐变，光向反方向偏移）
        if not hide_model:
            foot = (0.0, -16.0, 0.0)
            fx, fz = rep.rot_y(foot[0] + L[0] * 6.0, foot[2] + L[2] * 6.0, yaw)
            fy, fzz = rep.rot_x(foot[1], fz, pitch)
            pf = D / (D - fzz * unit)
            scx, scy = cen[0] + fx * unit * pf, cen[1] - fy * unit * pf
            sh = Image.new("RGBA", (int(unit * 30), int(unit * 30)), (0, 0, 0, 0))
            sd = ImageDraw.Draw(sh)
            sw2 = int(unit * 9)
            sd.ellipse((sw2 * 2 - sw2, sw2 * 3 - sw2 // 2, sw2 * 2 + sw2,
                        sw2 * 3 + sw2 // 2), fill=(0, 0, 0, int(110 * min(1.5, contrast))))
            sh = sh.filter(ImageFilter.GaussianBlur(unit * 1.4))
            canvas.alpha_composite(sh, (int(scx - unit * 15), int(scy - unit * 15)))

    for fi, f in enumerate(faces):
        part = fi // 6 if fi < 36 else (fi - 36) // 6
        rx, rz, ry, yoff = ang[PART_NAMES[part]]
        nx, ny, nz = f["normal"]
        if ry:
            nx, nz = rep.rot_y(nx, nz, ry)
        if rx:
            ny, nz = rep.rot_x(ny, nz, rx)
        if rz:
            nx, ny = rot_z(nx, ny, rz)
        nx, nz = rep.rot_y(nx, nz, yaw)
        ny, nz = rep.rot_x(ny, nz, pitch)
        backface = nz <= 0.0
        if backface and not f["overlay"]:
            continue
        sx = [0.0] * 4; sy = [0.0] * 4; zsum = 0.0
        for k in range(4):
            vx, vy, vz = f["corners"][k]
            vy = vy + yoff
            pv_dy = f["pivot"][1] + yoff
            if rx:
                dy = vy - pv_dy; dz = vz - f["pivot"][2]
                vy = pv_dy + dy * math.cos(rx) - dz * math.sin(rx)
                vz = f["pivot"][2] + dy * math.sin(rx) + dz * math.cos(rx)
            if rz:
                dx = vx - f["pivot"][0]; dy2 = vy - pv_dy
                vx = f["pivot"][0] + dx * math.cos(rz) - dy2 * math.sin(rz)
                vy = pv_dy + dx * math.sin(rz) + dy2 * math.cos(rz)
            if ry:
                vx, vz = rep.rot_y(vx - f["pivot"][0], vz - f["pivot"][2], ry)
                vx += f["pivot"][0]; vz += f["pivot"][2]
            vx, vz = rep.rot_y(vx, vz, yaw)
            vy, vz = rep.rot_x(vy, vz, pitch)
            vx *= unit; vy *= unit; vz *= unit
            pf = D / (D - vz)
            sx[k] = vx * pf; sy[k] = -vy * pf
            zsum += vz
        snx, sny, snz = nx, ny, nz
        if backface and f["overlay"]:
            snx, sny, snz = -nx, -ny, -nz
        recs.append((zsum / 4.0, f, sx, sy, (snx, sny, snz)))
    recs.sort(key=lambda r: r[0])
    stats = []
    if not hide_model:
        for zpos, f, sx, sy, (nx, ny, nz) in recs:
            rep.CUTOUT_MIN = cutout   # ★Task425 阈值参数化（26 旧 / 1 新）
            img = rep.face_image(skin, f["uv"], do_cutout=not f["overlay"])
            if img is None:
                continue
            iw, ih = img.size
            xs = [cen[0] + v for v in sx]
            ys = [cen[1] + v for v in sy]
            quad = list(zip(xs, ys))
            x0, x1 = min(xs), max(xs)
            y0, y1 = min(ys), max(ys)
            if x1 - x0 < 1 or y1 - y0 < 1:
                continue
            rw_, rh_ = max(1, int(round(x1 - x0))), max(1, int(round(y1 - y0)))
            AX, AY = quad[0][0] - x0, quad[0][1] - y0
            BX, BY = quad[1][0] - x0, quad[1][1] - y0
            CX_, CY_ = quad[3][0] - x0, quad[3][1] - y0
            det = (BX - AX) * (CY_ - AY) - (CX_ - AX) * (BY - AY)
            if abs(det) < 1e-6:
                continue
            a = iw * (CY_ - AY) / det
            b = -iw * (CX_ - AX) / det
            c = iw * ((CX_ - AX) * AY - (CY_ - AY) * AX) / det
            dd = -ih * (BY - AY) / det
            e = ih * (BX - AX) / det
            ff = ih * ((BY - AY) * AX - (BX - AX) * AY) / det
            warped = img.transform((rw_, rh_), Image.AFFINE, (a, b, c, dd, e, ff),
                                   resample=Image.NEAREST)
            ln = math.sqrt(nx * nx + ny * ny + nz * nz) or 1.0
            dot = (nx * L[0] + ny * L[1] + nz * L[2]) / ln
            dark, white = shade425(dot, contrast, brightness)
            if white > 0.004:
                wm = warped.split()[3].point(lambda v: int(v * min(1.0, white)))
                wl = Image.new("RGBA", warped.size, (255, 255, 255, 255))
                warped = Image.composite(wl, warped, wm)
            if dark > 0.004:
                am = warped.split()[3]
                if f["overlay"]:
                    am = am.point(lambda v: 255 if v >= 180 else 0)
                dm = am.point(lambda v: int(v * min(1.0, dark)))
                bl = Image.new("RGBA", warped.size, (0, 0, 0, 255))
                warped = Image.composite(bl, warped, dm)
            canvas.alpha_composite(warped, (int(round(x0)), int(round(y0))))
            if want_stats:
                wim = warped.convert("RGB")
                wpx = wim.load()
                vals = [0.2126 * wpx[x, y][0] + 0.7152 * wpx[x, y][1] + 0.0722 * wpx[x, y][2]
                        for y in range(wim.height) for x in range(wim.width)]
                stats.append((fi, f["overlay"], dot, sum(vals) / max(1, len(vals))))
    # 太阳（草地/雪地：az/el 同旋钮公式，放大半径挂天空）
    if world and world.get("sun"):
        sr = min(W, H) * 0.42
        sxp = cen[0] + math.sin(az) * sr * (1.0 - el / 1.5708)
        syp = cen[1] - math.cos(az) * sr * (1.0 - el / 1.5708) - H * 0.10
        sd = ImageDraw.Draw(canvas)
        r = world["sun"][1]
        sd.ellipse((sxp - r * 1.9, syp - r * 1.9, sxp + r * 1.9, syp + r * 1.9),
                   fill=world["sun"][0] + (70,))
        sd.ellipse((sxp - r, syp - r, sxp + r, syp + r), fill=world["sun"][0] + (235,))
    canvas.convert("RGB").save(out_path)
    if want_stats:
        return out_path, stats
    return out_path


def part_bbox(yaw, pitch, unit, part, cen):
    """部件屏幕 bbox（classic 右臂 x∈[-6,-2] 等；投影同管线 + 画布中心偏移
    与渲染一致 cen=(W/2, H*0.52)）——穿透统计口径。"""
    boxes = {
        0: (-4, 4, 24, 32, -4, 4), 1: (-4, 4, 12, 24, -2, 2),
        2: (-6, -2, 12, 24, -2, 2), 3: (2, 6, 12, 24, -2, 2),
        4: (-3.9, 0.1, 0, 12, -2, 2), 5: (-0.1, 3.9, 0, 12, -2, 2)}
    x0, x1, y0, y1, z0, z1 = boxes[part]
    pts = [(x0, y0, z0), (x1, y0, z0), (x1, y1, z0), (x0, y1, z0),
           (x0, y0, z1), (x1, y0, z1), (x1, y1, z1), (x0, y1, z1)]
    sx, sy = [], []
    for vx, vy, vz in pts:
        vx, vz = rep.rot_y(vx, vz, yaw)
        vy, vz = rep.rot_x(vy - 16.0, vz, pitch)
        vx *= unit; vy *= unit; vz *= unit
        pf = D / (D - vz)
        sx.append(cen[0] + vx * pf); sy.append(cen[1] - vy * pf)
    return min(sx), max(sx), min(sy), max(sy)


def hole_in_bbox(path, bbox, bg):
    """指定屏幕 bbox 内纯背景像素计数（病灶区口径）。"""
    im = Image.open(path).convert("RGB")
    px = im.load()
    W, H = im.size
    x0 = max(0, int(bbox[0])); x1 = min(W - 1, int(bbox[1]))
    y0 = max(0, int(bbox[2])); y1 = min(H - 1, int(bbox[3]))
    hole = 0; area = 0
    for y in range(y0, y1 + 1):
        for x in range(x0, x1 + 1):
            c = px[x, y]
            area += 1
            if abs(c[0] - bg[0]) <= 3 and abs(c[1] - bg[1]) <= 3 and abs(c[2] - bg[2]) <= 3:
                hole += 1
    return hole, area


# ---------- 合成淡边皮肤（病灶皮肤：α∈[1,25] 渐变边缘带） ----------
def make_fade_edge_skin():
    """基础层实心衣身 + 边缘 α 渐变带（4..24）+ 手臂整块淡区（α≈14）；
    外层帽/衣袖边框实心（凸起语义）。64×64 classic。"""
    img = Image.new("RGBA", (64, 64), (0, 0, 0, 0))
    px = img.load()

    def fill(x0, y0, w, h, rgb, a=255):
        for y in range(y0, y0 + h):
            for x in range(x0, x0 + w):
                if 0 <= x < 64 and 0 <= y < 64:
                    px[x, y] = rgb + (a,)

    # 头（含脸）
    fill(8, 8, 8, 8, (225, 170, 130))
    fill(10, 11, 2, 2, (60, 50, 90))    # 眼
    fill(14, 11, 1, 2, (60, 50, 90))
    fill(24, 8, 8, 8, (200, 140, 100))
    fill(0, 8, 8, 8, (150, 100, 70))
    fill(16, 8, 8, 8, (170, 120, 90))
    fill(8, 0, 8, 8, (90, 60, 40))
    fill(16, 0, 8, 8, (80, 55, 38))
    # 身（青蓝衫）
    fill(20, 20, 8, 12, (40, 120, 190))
    fill(32, 20, 8, 12, (30, 95, 160))
    fill(16, 20, 4, 12, (35, 105, 175))
    fill(28, 20, 4, 12, (35, 105, 175))
    fill(20, 16, 8, 4, (45, 130, 200))
    fill(28, 16, 8, 4, (38, 110, 180))
    # 右臂 classic：★病灶区 = 前脸整块 α=14（淡到旧阈值 26 之下 = 洞）
    fill(44, 20, 4, 12, (255, 200, 90), 14)
    fill(52, 20, 4, 12, (230, 175, 75), 20)
    fill(40, 20, 4, 12, (240, 185, 82), 18)
    fill(48, 20, 4, 12, (245, 190, 85), 16)
    fill(44, 16, 4, 4, (250, 195, 88), 12)
    fill(48, 16, 4, 4, (235, 180, 78), 10)
    # 左臂 classic：边缘渐变带（α 4..24 逐列爬升）
    for i in range(4):
        fill(36 + i, 52, 1, 12, (40, 120, 190), 5 + i * 6)
        fill(32 + i, 52, 1, 12, (35, 105, 175), 6 + i * 6)
        fill(44 + i, 52, 1, 12, (30, 95, 160), 7 + i * 6)
        fill(40 + i, 52, 1, 12, (38, 112, 182), 4 + i * 5)
    fill(36, 48, 4, 4, (45, 130, 200), 9)
    fill(40, 48, 4, 4, (42, 118, 188), 8)
    # 腿（深蓝牛仔裤，底缘渐隐带）
    fill(4, 20, 4, 12, (55, 60, 130))
    fill(12, 20, 4, 12, (45, 50, 115))
    fill(0, 20, 4, 12, (50, 55, 122))
    fill(8, 20, 4, 12, (48, 52, 118))
    fill(4, 16, 4, 4, (60, 66, 140))
    fill(8, 16, 4, 4, (55, 60, 132))
    fill(4, 30, 4, 2, (45, 50, 115), 12)   # 裤脚渐隐
    fill(12, 30, 4, 2, (42, 46, 108), 10)
    # 外层：帽（发）+ 衣袖边框（凸起实心）
    fill(40, 8, 8, 8, (120, 70, 40))
    fill(56, 8, 8, 8, (100, 58, 33))
    fill(32, 8, 8, 8, (110, 64, 37))
    fill(48, 8, 8, 8, (105, 61, 35))
    fill(40, 0, 8, 8, (95, 55, 32))
    fill(48, 0, 8, 8, (90, 52, 30))
    fill(44, 36, 4, 3, (255, 220, 130))    # 右袖口
    fill(36, 52, 4, 3, (70, 150, 220))     # 左袖口
    return img


# ---------- 合成实心皮肤（B 组着色定量专用：全 α=255 排除半透混合噪声） ----------
def make_solid_skin():
    img = Image.new("RGBA", (64, 64), (0, 0, 0, 0))
    px = img.load()

    def fill(x0, y0, w, h, rgb):
        for y in range(y0, y0 + h):
            for x in range(x0, x0 + w):
                if 0 <= x < 64 and 0 <= y < 64:
                    px[x, y] = rgb + (255,)

    fill(8, 8, 8, 8, (225, 170, 130)); fill(24, 8, 8, 8, (200, 140, 100))
    fill(0, 8, 8, 8, (150, 100, 70)); fill(16, 8, 8, 8, (170, 120, 90))
    fill(8, 0, 8, 8, (90, 60, 40)); fill(16, 0, 8, 8, (80, 55, 38))
    fill(20, 20, 8, 12, (40, 120, 190)); fill(32, 20, 8, 12, (30, 95, 160))
    fill(16, 20, 4, 12, (35, 105, 175)); fill(28, 20, 4, 12, (35, 105, 175))
    fill(20, 16, 8, 4, (45, 130, 200)); fill(28, 16, 8, 4, (38, 110, 180))
    fill(44, 20, 4, 12, (255, 170, 60)); fill(52, 20, 4, 12, (230, 150, 50))
    fill(40, 20, 4, 12, (240, 160, 55)); fill(48, 20, 4, 12, (245, 165, 58))
    fill(44, 16, 4, 4, (250, 175, 62)); fill(48, 16, 4, 4, (235, 155, 52))
    fill(36, 52, 4, 12, (60, 150, 220)); fill(44, 52, 4, 12, (50, 130, 195))
    fill(32, 52, 4, 12, (55, 140, 208)); fill(40, 52, 4, 12, (52, 135, 200))
    fill(36, 48, 4, 4, (65, 155, 225)); fill(40, 48, 4, 4, (58, 140, 210))
    fill(4, 20, 4, 12, (55, 60, 130)); fill(12, 20, 4, 12, (45, 50, 115))
    fill(0, 20, 4, 12, (50, 55, 122)); fill(8, 20, 4, 12, (48, 52, 118))
    fill(4, 16, 4, 4, (60, 66, 140)); fill(8, 16, 4, 4, (55, 60, 132))
    fill(20, 52, 4, 12, (58, 63, 135)); fill(28, 52, 4, 12, (48, 53, 118))
    fill(16, 52, 4, 12, (53, 58, 125)); fill(24, 52, 4, 12, (50, 55, 120))
    fill(20, 48, 4, 4, (63, 68, 142)); fill(24, 48, 4, 4, (57, 62, 130))
    return img


# ---------- 合成纯灰模型（B 组着色定量专用：本色一致 → 差值=纯着色贡献） ----------
def make_flat_skin():
    img = Image.new("RGBA", (64, 64), (128, 128, 128, 255))
    return img


WORLDS = {
    "plains": {"sky_top": (96, 160, 235), "sky_bot": (185, 220, 250),
               "fog": (185, 220, 250), "block": (95, 158, 68),
               "sun": ((255, 238, 170), 14)},
    "snow": {"sky_top": (150, 185, 225), "sky_bot": (225, 236, 248),
             "fog": (228, 238, 248), "block": (232, 238, 245),
             "sun": ((255, 250, 235), 12)},
    "end": {"sky_top": (8, 6, 14), "sky_bot": (24, 18, 34),
            "fog": (30, 24, 44), "block": (221, 223, 165),
            "sun": None},
    "nether": {"sky_top": (38, 8, 8), "sky_bot": (82, 22, 14),
               "fog": (95, 30, 18), "block": (110, 46, 40),
               "sun": None},
}


def seethru_count(path, bg):
    """模型 bbox 内穿透像素计数（= 纯背景色像素）。"""
    im = Image.open(path).convert("RGB")
    px = im.load()
    xs, ys = [], []
    for y in range(im.height):
        for x in range(im.width):
            c = px[x, y]
            if abs(c[0] - bg[0]) > 4 or abs(c[1] - bg[1]) > 4 or abs(c[2] - bg[2]) > 4:
                xs.append(x); ys.append(y)
    if not xs:
        return 0, 0
    x0, x1, y0, y1 = min(xs), max(xs), min(ys), max(ys)
    hole = 0
    area = 0
    for y in range(y0, y1 + 1):
        for x in range(x0, x1 + 1):
            c = px[x, y]
            if abs(c[0] - bg[0]) <= 3 and abs(c[1] - bg[1]) <= 3 and abs(c[2] - bg[2]) <= 3:
                hole += 1
            area += 1
    return hole, area


def group_a():
    """①穿透根修：CUTOUT 26（旧）vs 1（新 = skinview3d alphaTest0 对齐），
    8 角度扫描穿透像素定量。"""
    skin = make_fade_edge_skin()
    rows = []
    maxhole = 0
    for deg in (0, 45, 90, 135, 180, 225, 270, 315):
        yaw = math.radians(deg)
        pb = os.path.join(OUT, f"a_old26_y{deg}.png")
        pa = os.path.join(OUT, f"a_new1_y{deg}.png")
        render425(skin, False, yaw, 0.18, pb, unit=11, cutout=26)
        render425(skin, False, yaw, 0.18, pa, unit=11, cutout=1)
        bb = part_bbox(yaw, 0.18, 11, 2, (460 / 2.0, 640 * 0.52))   # 右臂病灶区（前脸 α=14 整块）
        hb, ab_ = hole_in_bbox(pb, bb, BG)
        ha, aa_ = hole_in_bbox(pa, bb, BG)
        maxhole = max(maxhole, hb)
        rows.append((deg, hb, ha, ab_, aa_))
        print(f"  A组 yaw={deg:3d}°  右臂bbox CUTOUT26 穿透 {hb:5d}/{ab_:5d}="
              f"{100.0*hb/max(1,ab_):4.1f}%   CUTOUT1 {ha:5d}/{aa_:5d}="
              f"{100.0*ha/max(1,aa_):4.1f}%")
    # 拼板：病灶角（180° 背面视角）前后对比 + 315°
    cells = []
    for deg, tag in ((180, "BEFORE cutout26: arm pixels a14<26 = holes"),
                     (315, "BEFORE cutout26")):
        cells.append((os.path.join(OUT, f"a_old26_y{deg}.png"), tag))
    cells.append((os.path.join(OUT, "a_new1_y180.png"),
                  "AFTER cutout1 (sv3d alphaTest0 parity)"))
    cells.append((os.path.join(OUT, "a_new1_y315.png"), "AFTER cutout1"))
    rep.compose_grid(cells, os.path.join(OUT, "A_cutout_seethru_fix.png"),
                     "Task425-A CUTOUT_MIN 26->1 (skinview3d innerLayer has NO alphaTest)",
                     cell=460)
    print(f"  A组 峰值穿透 {maxhole}px -> A_cutout_seethru_fix.png")
    # 全息皮回归（四象限不回潮：淡彩基础层 α178 在两阈值下都实心）
    hol = rep422.make_user_hologram()
    pb = os.path.join(OUT, "a_holo_old26.png")
    pa = os.path.join(OUT, "a_holo_new1.png")
    render425(hol, True, -0.60, 0.30, pb, unit=11, cutout=26)
    render425(hol, True, -0.60, 0.30, pa, unit=11, cutout=1)
    rep.compose_grid([(pb, "hologram cutout26 (Task424)"),
                      (pa, "hologram cutout1 (Task425) no regression")],
                     os.path.join(OUT, "A_holo_regression.png"),
                     "Task425-A hologram regression", cell=460)


def group_b():
    """⑤光影对比增强：旧公式（424 floor/gain 单黑罩）vs 新对比度双罩矩阵。
    着色定量用实心皮（α=255）排除半透混合噪声。"""
    skin = make_solid_skin()
    yaw, pitch = -0.60, 0.28
    az_list = (-150, -90, -30, 30, 90, 150)
    c_list = (0.0, 0.7, 1.4, 2.0)
    rows = []
    for c in c_list:
        row = []
        for azd in az_list:
            p = os.path.join(OUT, f"b_c{int(c*10)}_az{azd}.png")
            render425(skin, False, yaw, pitch, p, unit=9,
                      az=math.radians(azd), el=math.radians(30), contrast=c)
            im = Image.open(p)
            cell = Image.new("RGB", (im.width, im.height + 22), (18, 18, 18))
            cell.paste(im, (0, 22))
            d = ImageDraw.Draw(cell)
            label(d, f"az={azd} c={c}", (4, 3), small=True)
            row.append(cell)
        rows.append(row)
    wmax = max(cl.width for r in rows for cl in r)
    hmax = max(cl.height for r in rows for cl in r)
    grid = Image.new("RGB", (wmax * len(az_list), hmax * len(c_list) + 28), (10, 10, 10))
    dd = ImageDraw.Draw(grid)
    label(dd, "Task425-B contrast sweep (c=0 flat .. c=2 dramatic)", (6, 6))
    for ri, row in enumerate(rows):
        for ci, cell in enumerate(row):
            grid.paste(cell, (ci * wmax, 28 + ri * hmax))
    grid.save(os.path.join(OUT, "B_contrast_matrix.png"))
    # 定量：纯灰模型面级亮度（本色 128 → 差值=纯着色贡献）
    _, st1 = render425(make_flat_skin(), False, yaw, pitch,
                       os.path.join(OUT, "b_flat_ref.png"),
                       unit=11, az=math.radians(90), el=math.radians(30),
                       contrast=1.4, want_stats=True)
    base1 = [s for s in st1 if not s[1]]
    hi1 = max(base1, key=lambda s: s[2])
    lo1 = min(base1, key=lambda s: s[2])
    # 旧公式（Task424：floor0.5225@b1.15 + cap0.60 + gain0.85 单黑罩）数学对照
    old_lit = 128.0
    old_dark = 128.0 * (1.0 - (1.0 - 0.5225) * 0.60 * 0.85)
    print(f"  B组 纯灰模型定量 az=90: 新 c=1.4 受光面 {hi1[3]:.0f} / 背光面 {lo1[3]:.0f} "
          f"= 面间差 {hi1[3]-lo1[3]:.0f} 灰阶")
    print(f"  B组 旧公式 Task424 数学对照: 受光 {old_lit:.0f} / 背光 {old_dark:.0f} "
          f"= 面间差 {old_lit-old_dark:.0f} 灰阶（“看不出光影”实锤）")
    _, st0 = render425(make_flat_skin(), False, yaw, pitch,
                       os.path.join(OUT, "b_flat_c0.png"),
                       unit=11, az=math.radians(90), el=math.radians(30),
                       contrast=0.0, want_stats=True)
    base0 = [s for s in st0 if not s[1]]
    hi0 = max(base0, key=lambda s: s[2]); lo0 = min(base0, key=lambda s: s[2])
    print(f"  B组 新 c=0(光影关端点): 差 {hi0[3]-lo0[3]:.0f} 灰阶")
    print(f"  B组 -> B_contrast_matrix.png")


def group_c():
    """⑥世界背景四联：草地/雪地/末地/地狱（天空渐变+方块地面+雾+太阳+脚影）。"""
    skin = make_solid_skin()
    cells = []
    for wname in ("plains", "snow", "end", "nether"):
        p = os.path.join(OUT, f"c_world_{wname}.png")
        render425(skin, False, -0.60, 0.30, p, unit=10, size=(460, 560),
                  az=math.radians(-35), el=math.radians(42), contrast=1.4,
                  world=WORLDS[wname])
        im = Image.open(p)
        cell = Image.new("RGB", (im.width, im.height + 24), (18, 18, 18))
        cell.paste(im, (0, 24))
        d = ImageDraw.Draw(cell)
        label(d, {"plains": "草地 plains", "snow": "雪地 snow",
                  "end": "末地 the end", "nether": "地狱 nether"}[wname], (6, 4))
        cells.append((p, wname))
    rep.compose_grid(cells, os.path.join(OUT, "C_world_backdrops.png"),
                     "Task425-C world backdrops: sky+block ground+fog+sun+shadow",
                     cell=460)
    print(f"  C组 -> C_world_backdrops.png")


def group_d():
    """②③④ 二级菜单 mock：齿轮入口 + 底部面板（光影区大圆盘/亮度/光强+
    背景区 7 钮+缩放拖条）。"""
    W, H = 460, 700
    panel = Image.new("RGB", (W, H), (24, 24, 26))
    d = ImageDraw.Draw(panel)
    # 舞台残影（上方）
    d.rectangle((0, 0, W, 300), fill=(41, 41, 41))
    d.rectangle((150, 80, 300, 260), outline=(90, 90, 95), width=2)
    # 面板
    d.rounded_rectangle((8, 316, W - 8, H - 10), radius=18, fill=(34, 34, 38))
    label(d, "显示与光影  (gear secondary panel)", (28, 332))
    d.line((28, 356, W - 28, 356), fill=(70, 70, 76), width=1)
    # 光影区：大圆盘
    cx, cy, R = 96, 452, 58
    d.ellipse((cx - R, cy - R, cx + R, cy + R), outline=(110, 110, 118), width=2)
    azd, eld = math.radians(-35), math.radians(42)
    rr = R * (1.0 - eld / 1.5708)
    kx, ky = cx + rr * math.sin(azd), cy - rr * math.cos(azd)
    d.line((cx, cy, kx, ky), fill=(255, 200, 80), width=2)
    d.ellipse((kx - 8, ky - 8, kx + 8, ky + 8), fill=(255, 200, 80))
    label(d, "光位圆盘 140pt", (170, 400))
    # 亮度拖条
    d.rounded_rectangle((170, 430, 430, 448), radius=9, fill=(58, 58, 64))
    d.rounded_rectangle((170, 430, 340, 448), radius=9, fill=(80, 160, 255))
    d.ellipse((330, 424, 350, 454), fill=(240, 240, 245))
    label(d, "亮度 115%   [−][+]", (170, 456), small=True)
    # 光强拖条
    d.rounded_rectangle((170, 490, 430, 508), radius=9, fill=(58, 58, 64))
    d.rounded_rectangle((170, 490, 380, 508), radius=9, fill=(255, 170, 60))
    d.ellipse((370, 484, 390, 514), fill=(240, 240, 245))
    label(d, "光影强度 140%   [−][+]", (170, 516), small=True)
    # 背景区 7 钮
    label(d, "背景：", (28, 556))
    cols = [(0, 0, 0), (41, 41, 41), (140, 140, 140),
            WORLDS["plains"]["block"], WORLDS["snow"]["block"],
            WORLDS["end"]["block"], WORLDS["nether"]["block"]]
    for i, cc in enumerate(cols):
        bx = 90 + i * 46
        d.ellipse((bx, 548, bx + 34, 582), outline=(120, 120, 126), width=2,
                  fill=cc)
    label(d, "黑 灰 浅灰 草地 雪地 末地 地狱", (90, 588), small=True)
    # 缩放
    d.rounded_rectangle((28, 616, 430, 634), radius=9, fill=(58, 58, 64))
    d.rounded_rectangle((28, 616, 300, 634), radius=9, fill=(120, 190, 120))
    d.ellipse((290, 610, 310, 640), fill=(240, 240, 245))
    label(d, "模型大小 150%", (28, 642), small=True)
    d.rounded_rectangle((180, 664, 280, 686), radius=11, fill=(80, 160, 255))
    label(d, "完成", (218, 668))
    panel.save(os.path.join(OUT, "D_secondary_panel_mock.png"))
    print(f"  D组 -> D_secondary_panel_mock.png")


if __name__ == "__main__":
    print("Task425 replica evidence ->", OUT)
    group_a()
    group_b()
    group_c()
    group_d()
    print("done")
