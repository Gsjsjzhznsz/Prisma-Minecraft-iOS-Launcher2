#!/usr/bin/env python3
# task420_skin_preview_replica.py -- Task420 数学先行（Python 先行，公式与
# HEAD ObjC ZL2SkinPreviewView.m 逐行同源；出图 = 交付用户「测试图呢」实证）。
#
# 本轮（Task420）三案：
#   A. 预览皮肤来源根修对照：陈旧缓存 Alex（病灶实况）vs 真皮（skinfull 白猫皮）
#      —— 缓存优先 + 账户级键 + 刷新失败不回退 = 头像猫娘/模型 Alex 自相矛盾。
#   B. 原版皮肤几何验证：walk=0 静态 Alex 在 yaw 扫掠下手臂是否贴身（用户
#      IMG_0655 实测手臂离位/缝隙疑云 = 「原版皮肤都有透明的问题」主诉面）。
#   C. alpha 语义回归：全息皮（Task419 harness 规格）基础层 α 裁切 + 外层
#      DoubleSide 修复前/后 2×2 对比（419 提交信息声称的对比图实际未入库，
#      本脚本补账入库）。
#
# 管线转写锚（与 .m 行号同源，改 ObjC 必同步改本脚本）：
#   UV 表 L128-167 / BuildPart L1275-1367（UX/VY/NN/OFF/SQ）/
#   updateModelTransform L1170-1243（摆动绕枢轴 RotX→RotY(yaw)→RotX(pitch)、
#   pf=D/(D−z)、sy=−y·pf、画家 zsum/4、剔除 nz≤0（外层豁免）、明暗
#   0.44+0.58·max(0,dot)、罩 opacity=(1−shade)·0.85）/ Cutout L200-235
#   （α≥26 解预乘强制不透明 / α<26 裁掉）/ FaceImage L175-191（y 同 x 标度）。
# 用法: python3 task420_skin_preview_replica.py <out_dir>
import math
import os
import sys

try:
    from PIL import Image, ImageDraw
except ImportError:
    sys.exit("需要 Pillow: pip install pillow")

D = 900.0
WALK_AMP = 0.50            # ObjC AME416_WALK_AMP（弧度摆幅，416 0.55 微收后）
LIGHT = (-0.45, 0.62, 0.65)  # ObjC AME416_LIGHT_X/Y/Z
CUTOUT_MIN = 26            # ObjC AME419_CUTOUT_MIN

# ── 六面序 = [前(+Z) 后(−Z) 右(−X) 左(+X) 上(+Y) 下(−Y)]（与 ObjC 同序）──
UV_HEAD = [(8, 8, 8, 8), (24, 8, 8, 8), (0, 8, 8, 8), (16, 8, 8, 8), (8, 0, 8, 8), (16, 0, 8, 8)]
UV_BODY = [(20, 20, 8, 12), (32, 20, 8, 12), (16, 20, 4, 12), (28, 20, 4, 12), (20, 16, 8, 4), (28, 16, 8, 4)]
UV_RARM = [(44, 20, 4, 12), (52, 20, 4, 12), (40, 20, 4, 12), (48, 20, 4, 12), (44, 16, 4, 4), (48, 16, 4, 4)]
UV_LARM = [(36, 52, 4, 12), (44, 52, 4, 12), (32, 52, 4, 12), (40, 52, 4, 12), (36, 48, 4, 4), (40, 48, 4, 4)]
UV_RLEG = [(4, 20, 4, 12), (12, 20, 4, 12), (0, 20, 4, 12), (8, 20, 4, 12), (4, 16, 4, 4), (8, 16, 4, 4)]
UV_LLEG = [(20, 52, 4, 12), (28, 52, 4, 12), (16, 52, 4, 12), (24, 52, 4, 12), (20, 48, 4, 4), (24, 48, 4, 4)]
# ★Task421 内侧脸 1px 修正（side2 = u+depth+width，skinview3d setUVs 同源；
#   旧 48/40/48/56 深入背区 1px，与 ObjC ZL2SkinPreviewView.m 四表同步）
UV_RARM_SLIM = [(44, 20, 3, 12), (51, 20, 3, 12), (40, 20, 4, 12), (47, 20, 4, 12), (44, 16, 3, 4), (47, 16, 3, 4)]
UV_LARM_SLIM = [(36, 52, 3, 12), (43, 52, 3, 12), (32, 52, 4, 12), (39, 52, 4, 12), (36, 48, 3, 4), (39, 48, 3, 4)]
UV_HAT = [(40, 8, 8, 8), (56, 8, 8, 8), (32, 8, 8, 8), (48, 8, 8, 8), (40, 0, 8, 8), (48, 0, 8, 8)]
UV_JACKET = [(20, 36, 8, 12), (32, 36, 8, 12), (16, 36, 4, 12), (28, 36, 4, 12), (20, 32, 8, 4), (28, 32, 8, 4)]
UV_RSLEEVE = [(44, 36, 4, 12), (52, 36, 4, 12), (40, 36, 4, 12), (48, 36, 4, 12), (44, 32, 4, 4), (48, 32, 4, 4)]
UV_LSLEEVE = [(52, 52, 4, 12), (60, 52, 4, 12), (48, 52, 4, 12), (56, 52, 4, 12), (52, 48, 4, 4), (56, 48, 4, 4)]
UV_RPANT = [(4, 36, 4, 12), (12, 36, 4, 12), (0, 36, 4, 12), (8, 36, 4, 12), (4, 32, 4, 4), (8, 32, 4, 4)]
UV_LPANT = [(4, 52, 4, 12), (12, 52, 4, 12), (0, 52, 4, 12), (8, 52, 4, 12), (4, 48, 4, 4), (8, 48, 4, 4)]
UV_RSLEEVE_SLIM = [(44, 36, 3, 12), (51, 36, 3, 12), (40, 36, 4, 12), (47, 36, 4, 12), (44, 32, 3, 4), (47, 32, 3, 4)]
UV_LSLEEVE_SLIM = [(52, 52, 3, 12), (59, 52, 3, 12), (48, 52, 4, 12), (55, 52, 4, 12), (52, 48, 3, 4), (55, 48, 3, 4)]

# ObjC BuildPart 常量表（L1285-1292）
UX = [(1, 0, 0), (-1, 0, 0), (0, 0, -1), (0, 0, 1), (1, 0, 0), (1, 0, 0)]
VY = [(0, -1, 0), (0, -1, 0), (0, -1, 0), (0, -1, 0), (0, 0, 1), (0, 0, -1)]
NN = [(0, 0, 1), (0, 0, -1), (-1, 0, 0), (1, 0, 0), (0, 1, 0), (0, -1, 0)]
OFF = [(0, 0, 1), (0, 0, -1), (-1, 0, 0), (1, 0, 0), (0, 1, 0), (0, -1, 0)]
SQ = [(-1, -1), (1, -1), (1, 1), (-1, 1)]  # TL TR BR BL


def rot_y(x, z, th):
    c, s = math.cos(th), math.sin(th)
    return x * c + z * s, -x * s + z * c


def rot_x(y, z, th):
    c, s = math.cos(th), math.sin(th)
    return y * c - z * s, y * s + z * c


def build_part_records(cx, cy, cz, w, h, d, pvx, pvy, pvz, swing_sign, uv_table, overlay):
    """逐行转写 ObjC ZL2SkinViewBuildPart（L1293-1356）：面记录 = 四角 + 枢轴 +
    法线 + UV 区块 + isOverlay。四角 y −16 居中（L1352）、枢轴 y −16（L1358）。"""
    out = []
    for i in range(6):
        fw = d if (i == 2 or i == 3) else w
        fh = d if (i >= 4) else h
        fcx = cx + OFF[i][0] * w / 2.0
        fcy = cy + OFF[i][1] * h / 2.0
        fcz = cz + OFF[i][2] * d / 2.0
        corners = []
        for k in range(4):
            s, t = SQ[k]
            corners.append([
                fcx + UX[i][0] * (s * fw / 2.0) + VY[i][0] * (t * fh / 2.0),
                fcy + UX[i][1] * (s * fw / 2.0) + VY[i][1] * (t * fh / 2.0) - 16.0,
                fcz + UX[i][2] * (s * fw / 2.0) + VY[i][2] * (t * fh / 2.0),
            ])
        out.append({
            "corners": corners,
            "pivot": (pvx, pvy - 16.0, pvz),
            "normal": NN[i],
            "uv": uv_table[i],
            "overlay": overlay,
            "swing_sign": swing_sign,
            "fw": fw, "fh": fh,
        })
    return out


def build_model(slim, skin_w, skin_h):
    """逐行转写 ObjC ame413_applySkin 装配表（L1398-1456）。"""
    legacy = skin_h < skin_w
    r_arm_uv = UV_RARM_SLIM if slim else UV_RARM
    l_arm_uv = r_arm_uv if legacy else (UV_LARM_SLIM if slim else UV_LARM)
    l_leg_uv = UV_RLEG if legacy else UV_LLEG
    aw = 3.0 if slim else 4.0
    arm_cx = 4.0 + aw / 2.0   # 臂贴身（L1403：身半宽 4 + 臂半宽）
    parts = [
        (0, 28, 0, 8, 8, 8, 0, 24, 0, 0.0, UV_HEAD),
        (0, 18, 0, 8, 12, 4, 0, 18, 0, 0.0, UV_BODY),
        (-arm_cx, 18, 0, aw, 12, 4, -5.0, 22.0, 0, 1.0, r_arm_uv),
        (arm_cx, 18, 0, aw, 12, 4, 5.0, 22.0, 0, -1.0, l_arm_uv),
        (-1.9, 6, 0, 4, 12, 4, -1.9, 12.0, 0, -1.0, UV_RLEG),
        (1.9, 6, 0, 4, 12, 4, 1.9, 12.0, 0, 1.0, l_leg_uv),
    ]
    faces = []
    for (cx, cy, cz, w, h, d, pvx, pvy, pvz, sign, uv) in parts:
        faces += build_part_records(cx, cy, cz, w, h, d, pvx, pvy, pvz, sign, uv, False)
    overlay_tables = [UV_HAT, UV_JACKET,
                      UV_RSLEEVE_SLIM if slim else UV_RSLEEVE,
                      (UV_RSLEEVE_SLIM if slim else UV_RSLEEVE) if legacy
                      else (UV_LSLEEVE_SLIM if slim else UV_LSLEEVE),
                      UV_RPANT, (UV_RPANT if legacy else UV_LPANT)]
    overlay_parts = 1 if legacy else 6   # ★Task418 旧版诚实降级仅帽
    for idx in range(overlay_parts):
        (cx, cy, cz, w, h, d, pvx, pvy, pvz, sign, _uv) = parts[idx]
        faces += build_part_records(cx, cy, cz, w + 1.0, h + 1.0, d + 1.0,
                                    pvx, pvy, pvz, sign, overlay_tables[idx], True)
    return faces


def cutout_face(img):
    """逐行转写 ZL2SkinViewCutoutImage（直线 alpha 语义等效）：α≥26 → 不透明
    （CG 预乘→解预乘往返在直线 alpha 下恒等）；α<26 → 裁掉。"""
    px = img.load()
    w, h = img.size
    for y in range(h):
        for x in range(w):
            r, g, b, a = px[x, y]
            px[x, y] = (r, g, b, 255) if a >= CUTOUT_MIN else (0, 0, 0, 0)
    return img


def face_image(skin, rect, do_cutout):
    """逐行转写 ZL2SkinViewFaceImage（L175-191）：scaleX=scaleY=width/64。"""
    sw, sh = skin.size
    scale = sw / 64.0
    x0, y0, rw, rh = rect
    crop = (max(0, int(x0 * scale)), max(0, int(y0 * scale)),
            min(sw, int((x0 + rw) * scale)), min(sh, int((y0 + rh) * scale)))
    if crop[2] <= crop[0] or crop[3] <= crop[1]:
        return None
    img = skin.crop(crop).convert("RGBA")
    return cutout_face(img) if do_cutout else img


def sample_nearest(img, u, v):
    """最近邻（ObjC kCAFilterNearest 同源；u/v ∈ [0,1)）。"""
    w, h = img.size
    x = min(w - 1, max(0, int(u * w)))
    y = min(h - 1, max(0, int(v * h)))
    return img.getpixel((x, y))


def render(skin, faces, yaw, pitch, out_path, unit=10.0, size=(560, 780),
           overlay_alpha_fix=True, bg=(26, 26, 26)):
    """逐行转写 ame413_updateModelTransform（L1170-1243）+ 画家算法合成。"""
    W, H = size
    canvas = Image.new("RGBA", (W, H), bg + (255,))
    cen = (W / 2.0, H / 2.0)
    recs = []
    for f in faces:
        nx, ny, nz = f["normal"]
        nx, nz = rot_y(nx, nz, yaw)
        ny, nz = rot_x(ny, nz, pitch)
        backface = nz <= 0.0
        if backface and not f["overlay"]:
            continue   # 背面剔除（外层 DoubleSide 豁免）
        sx = [0.0] * 4
        sy = [0.0] * 4
        zsum = 0.0
        ok = True
        for k in range(4):
            vx, vy, vz = f["corners"][k]
            vx, vz = rot_y(vx, vz, yaw)
            vy, vz = rot_x(vy, vz, pitch)
            vx *= unit; vy *= unit; vz *= unit
            pf = D / (D - vz)
            sx[k] = vx * pf
            sy[k] = -vy * pf
            zsum += vz
        if not ok:
            continue
        recs.append((zsum / 4.0, f, sx, sy, (nx, ny, nz)))
    recs.sort(key=lambda r: r[0])   # 画家序：远先近后
    for zpos, f, sx, sy, (nx, ny, nz) in recs:
        img = face_image(skin, f["uv"], do_cutout=not f["overlay"])
        if img is None:
            continue
        iw, ih = img.size
        # 仿射贴面：输出四边形 = 投影四角；纹理坐标 = 四角对应的 UV 角。
        # PIL transform 映射 OUTPUT→INPUT：对输出像素 (xo,yo) 求纹理 (xi,yi)。
        # 输出参考系 = 四角外接盒；局部 (px,py) 由四角双线性求逆。
        xs = [cen[0] + v for v in sx]
        ys = [cen[1] + v for v in sy]
        quad_out = list(zip(xs, ys))   # TL TR BR BL（画布绝对坐标）
        x0, x1 = min(xs), max(xs)
        y0, y1 = min(ys), max(ys)
        if x1 - x0 < 1 or y1 - y0 < 1:
            continue
        rw_, rh_ = max(1, int(round(x1 - x0))), max(1, int(round(y1 - y0)))
        # bbox 相对坐标下的三点仿射解（ObjC 同款对应 P0→UV(0,0) P1→(iw,0) P3→(0,ih)）：
        #   xi = a·xo + b·yo + c, yi = d·xo + e·yo + f （PIL output→input 约定）
        AX, AY = quad_out[0][0] - x0, quad_out[0][1] - y0
        BX, BY = quad_out[1][0] - x0, quad_out[1][1] - y0
        CX_, CY_ = quad_out[3][0] - x0, quad_out[3][1] - y0
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
        # 明暗罩（Task418 alpha 掩膜 = 面纹理 alpha；L1234-1240）
        ln = math.sqrt(nx * nx + ny * ny + nz * nz) or 1.0
        dot = (nx * LIGHT[0] + ny * LIGHT[1] + nz * LIGHT[2]) / ln
        shade = 0.44 + 0.58 * max(0.0, dot)
        if shade > 1.0:
            shade = 1.0
        dark = (1.0 - shade) * 0.85
        if dark > 0.001:
            mask = warped.split()[3].point(lambda v: int(v * dark))
            black = Image.new("RGBA", warped.size, (0, 0, 0, 255))
            warped = Image.composite(black, warped, mask)
        if not overlay_alpha_fix:
            # 修复前病灶模拟：外层透明像素区被黑罩漏染 = 幽灵暗盒（Task418 前）
            black_full = Image.new("RGBA", warped.size, (0, 0, 0, int(255 * dark)))
            warped = Image.alpha_composite(black_full, warped)
        canvas.alpha_composite(warped, (int(round(x0)), int(round(y0))))
    canvas.convert("RGB").save(out_path)
    return out_path


# ── 测试皮生成 ──
def make_hologram_skin():
    """Task419 harness 规格（AmePreviewWriteHologramSkin）：半透淡粉白基础层
    α0.70 + 彩虹外层 α0.60 + 胸口透明窗；64×64。"""
    img = Image.new("RGBA", (64, 64), (0, 0, 0, 0))
    px = img.load()
    for y in range(16, 32):        # 身 12×12（前 8 宽）
        for x in range(20, 28):
            hole = (24 <= x < 26 and 22 <= y < 27)   # 胸口透明窗
            a = 0 if hole else int(255 * 0.70)
            px[x, y] = (250, 235, 240, a)
    for x in range(8, 16):         # 头（淡粉白）
        for y in range(8, 16):
            px[x, y] = (250, 235, 240, int(255 * 0.70))
    for x in range(44, 47):        # slim 臂（右）
        for y in range(20, 32):
            px[x, y] = (250, 235, 240, int(255 * 0.70))
    for x in range(36, 39):
        for y in range(52, 64):
            px[x, y] = (250, 235, 240, int(255 * 0.70))
    for x in range(4, 8):
        for y in range(20, 32):
            px[x, y] = (250, 235, 240, int(255 * 0.70))
    for x in range(20, 24):
        for y in range(52, 64):
            px[x, y] = (250, 235, 240, int(255 * 0.70))
    rainbow = [(255, 80, 80), (255, 170, 60), (255, 240, 70),
               (90, 220, 120), (80, 170, 255), (190, 110, 255)]
    for i, (x0, y0, rw, rh) in enumerate(UV_HAT):
        c = rainbow[i % 6]
        for yy in range(y0, y0 + rh):
            for xx in range(x0, x0 + rw):
                px[xx, yy] = (c[0], c[1], c[2], int(255 * 0.60))
    for i, (x0, y0, rw, rh) in enumerate(UV_JACKET):
        c = rainbow[(i + 2) % 6]
        for yy in range(y0, y0 + rh):
            for xx in range(x0, x0 + rw):
                px[xx, yy] = (c[0], c[1], c[2], int(255 * 0.60))
    return img


def make_whitecat_skin():
    """用户真实皮肤近似复刻（IMG_0655 头像取样：白紫猫娘、粉耳、深紫眼；
    基础层全不透明 + 帽层发饰半透 = 现代写实皮口径）。"""
    img = Image.new("RGBA", (64, 64), (0, 0, 0, 0))
    px = img.load()
    WHITE = (245, 243, 248, 255)
    LAV = (222, 216, 235, 255)
    PINK = (247, 205, 205, 255)
    DEEP = (96, 84, 130, 255)
    def fill(x0, y0, w, h, c):
        for yy in range(y0, y0 + h):
            for xx in range(x0, x0 + w):
                px[xx, yy] = c
    fill(8, 8, 8, 8, WHITE)          # 头前
    fill(0, 8, 8, 8, LAV)            # 头右
    fill(16, 8, 8, 8, LAV)           # 头左
    fill(24, 8, 8, 8, LAV)           # 头后
    fill(8, 0, 8, 8, WHITE)          # 头顶
    fill(16, 0, 8, 8, WHITE)         # 头底
    px[10, 10] = DEEP; px[11, 10] = DEEP   # 眼
    px[13, 10] = DEEP; px[14, 10] = DEEP
    px[11, 12] = PINK; px[12, 12] = PINK; px[13, 12] = PINK  # 鼻
    fill(20, 20, 8, 12, LAV)         # 身前（衣裙白紫）
    fill(8, 12, 4, 4, PINK)          # 帽层耳朵（左右）
    fill(48, 8, 4, 4, PINK)
    fill(32, 20, 4, 12, WHITE); fill(28, 20, 4, 12, WHITE)   # 身侧
    fill(44, 20, 3, 12, WHITE); fill(36, 52, 3, 12, WHITE)   # slim 臂
    fill(4, 20, 4, 12, WHITE); fill(20, 52, 4, 12, WHITE)    # 腿
    fill(44, 16, 3, 4, PINK); fill(36, 48, 3, 4, PINK)       # 臂顶
    return img


def compose_grid(cells, out_path, title, cell=560):
    """cells = [(img_path, caption)] 两列网格拼图 + 标题。"""
    rows = (len(cells) + 1) // 2
    cap_h = 34
    W = cell * 2 + 30
    H = rows * (780 + cap_h) + 70
    board = Image.new("RGB", (W, H), (18, 18, 20))
    dr = ImageDraw.Draw(board)
    try:
        import glob
        fp = glob.glob("/usr/share/fonts/truetype/chinese/NotoSansSC-Regular.ttf")
        from PIL import ImageFont
        font = ImageFont.truetype(fp[0], 22) if fp else ImageFont.load_default()
        font_s = ImageFont.truetype(fp[0], 17) if fp else ImageFont.load_default()
    except Exception:
        font = ImageFont.load_default()
        font_s = font
    dr.text((W // 2 - len(title) * 11, 20), title, fill=(235, 235, 235), font=font)
    for i, (p, cap) in enumerate(cells):
        r, cidx = divmod(i, 2)
        x = 10 + cidx * (cell + 10)
        y = 70 + r * (780 + cap_h)
        board.paste(Image.open(p), (x, y))
        dr.text((x + 8, y + 780 + 6), cap, fill=(200, 205, 215), font=font_s)
        dr.rectangle([x, y, x + cell, y + 780], outline=(70, 70, 76), width=1)
    board.save(out_path)


def main():
    out_dir = sys.argv[1] if len(sys.argv) > 1 else "/tmp/task420_preview"
    os.makedirs(out_dir, exist_ok=True)

    alex_path = None
    for cand in ("/tmp/mhf_alex.png", os.path.join(out_dir, "alex.png")):
        if os.path.exists(cand):
            alex_path = cand
            break
    if alex_path is None:
        sys.exit("缺少 Alex 皮（先 curl minotar.net/skin/MHF_Alex）")
    alex = Image.open(alex_path).convert("RGBA")
    steve32 = Image.open("/tmp/minotar_test.png").convert("RGBA") \
        if os.path.exists("/tmp/minotar_test.png") else None
    holo = make_hologram_skin()
    holo.save(os.path.join(out_dir, "skin_hologram.png"))
    cat = make_whitecat_skin()
    cat.save(os.path.join(out_dir, "skin_whitecat.png"))

    faces_alex = build_model(True, alex.size[0], alex.size[1])
    faces_holo = build_model(True, 64, 64)
    faces_cat = build_model(True, 64, 64)
    faces_steve = build_model(False, steve32.size[0], steve32.size[1]) if steve32 else []

    # ── B: 原版 Alex walk=0 yaw 扫掠（手臂贴身几何验证 = IMG_0655 主诉面）──
    sweep = []
    for i, yaw_deg in enumerate([-34, 30, 90, 150, 210, 270]):
        yaw = math.radians(yaw_deg)
        p = os.path.join(out_dir, "alex_yaw%03d.png" % (yaw_deg % 360))
        render(alex, faces_alex, yaw, math.radians(-0.18), p, unit=13.0)
        sweep.append((p, "原版Alex walk=0 yaw=%d° pitch=-10°" % (yaw_deg % 360)))
    compose_grid(sweep[:4], os.path.join(out_dir, "B_alex_static_sweep.png"),
                 "B｜原版皮肤静态几何验证（walk=0）——手臂应恒贴身无缝隙")
    if len(sweep) > 4:
        compose_grid(sweep[4:], os.path.join(out_dir, "B2_alex_static_sweep2.png"),
                     "B2｜原版皮肤静态几何验证（续）")

    # ── C: 全息皮 alpha 语义修复前/后 2×2 ──
    cells = []
    p = os.path.join(out_dir, "C_holo_before.png")
    render(holo, faces_holo, math.radians(-34), math.radians(-10), p,
           unit=13.0, overlay_alpha_fix=False)
    cells.append((p, "修复前：外层透明区黑罩漏染（幽灵暗盒）"))
    p = os.path.join(out_dir, "C_holo_after.png")
    render(holo, faces_holo, math.radians(-34), math.radians(-10), p, unit=13.0)
    cells.append((p, "修复后：α 裁切 + 掩膜罩 + DoubleSide"))
    p = os.path.join(out_dir, "C_cat_cache_alex.png")
    render(alex, faces_alex, math.radians(-34), math.radians(-10), p, unit=13.0)
    cells.append((p, "病灶实况：缓存残留 Alex（头像却是猫娘）"))
    p = os.path.join(out_dir, "C_cat_after.png")
    render(cat, faces_cat, math.radians(-34), math.radians(-10), p, unit=13.0)
    cells.append((p, "根修后：skinfull 真皮白猫（与头像一致）"))
    compose_grid(cells, os.path.join(out_dir, "C_alpha_and_source_fix.png"),
                 "C｜透明语义 + 皮肤来源修复前/后对照（Task420 测试图）")

    # ── legacy 64×32 Steve 回归 ──
    if faces_steve:
        p = os.path.join(out_dir, "D_steve_legacy.png")
        render(steve32, faces_steve, math.radians(-34), math.radians(-10), p, unit=13.0)
        print("legacy Steve 回归:", p)

    print("A/B/C/D 全部产出 →", out_dir)
    for f in sorted(os.listdir(out_dir)):
        print("  ", f)


if __name__ == "__main__":
    main()
