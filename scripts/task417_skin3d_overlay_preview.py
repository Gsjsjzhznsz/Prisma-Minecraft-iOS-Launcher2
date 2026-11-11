#!/usr/bin/env python3
# task417_skin3d_overlay_preview.py -- skinview3d 数学同源复刻验证（Python 先行，
# 公式落 ObjC 前本地出图 = 不盲修纪律）。★Task417：在 Task416 CPU 投影引擎
# 口径上叠加第二层（OuterLayer：帽/衣/袖/裤，skinview3d 网名 hatLayer 等）：
#   · 装配表不变（头 (0,24..32) 8³ / 身 (0,12..24) 8×12×4 / 臂 ±(3.9..7.9,12..24)
#     pivot ±(5,22) / 腿 ±(1.9,0..12) pivot ±(1.9,12)；模型 y 0..32，居中 y=16）
#   · 外层盒 = 基础盒每边 +0.5（skinview3d inflate 0.5；帽 9³/衣 8.5×12.5×4.5）
#   · 外层 UV = 标准第二层区块（帽 = 头区块 x+32；衣 = 身区块 y+16；
#     右袖 = 右臂区块 y+16；左袖 = 左臂区块 x+16；右裤 = 右腿 y+16；
#     左裤 = (0,48) 独立区块；slim 前后/上下 3 宽同基础层口径）
#   · 管线与 ObjC 同帧同序：yaw→pitch 全局旋转 → 肢体摆动绕枢轴 → CPU 透视
#     （pf = D/(D−Z)，D=900）→ 画家算法（相机 z 大者前）→ 背面剔除（法线·视线
#     ≤0 隐藏）→ 法线明暗（左上前光向点积）→ 最近邻采样（像素风）
# 用法: python3 task417_skin3d_overlay_preview.py <out_dir>
import math
import os
import sys

try:
    from PIL import Image
except ImportError:
    sys.exit("需要 Pillow: pip install pillow")

D = 900.0
WALK_AMP = math.radians(31.0)

# ── 六面序 = [前(+Z) 后(−Z) 右(−X) 左(+X) 上(+Y) 下(−Y)]（与 ObjC buildBox 同序）──
# 基础层 UV（64×64 标准布局，与 ZL2SkinPreviewView.m 表逐值同源）
UV_HEAD = [(8, 8, 8, 8), (24, 8, 8, 8), (0, 8, 8, 8), (16, 8, 8, 8), (8, 0, 8, 8), (16, 0, 8, 8)]
UV_BODY = [(20, 20, 8, 12), (32, 20, 8, 12), (16, 20, 4, 12), (28, 20, 4, 12), (20, 16, 8, 4), (28, 16, 8, 4)]
UV_RARM = [(44, 20, 4, 12), (52, 20, 4, 12), (40, 20, 4, 12), (48, 20, 4, 12), (44, 16, 4, 4), (48, 16, 4, 4)]
UV_LARM = [(36, 52, 4, 12), (44, 52, 4, 12), (32, 52, 4, 12), (40, 52, 4, 12), (36, 48, 4, 4), (40, 48, 4, 4)]
UV_RLEG = [(4, 20, 4, 12), (12, 20, 4, 12), (0, 20, 4, 12), (8, 20, 4, 12), (4, 16, 4, 4), (8, 16, 4, 4)]
UV_LLEG = [(20, 52, 4, 12), (28, 52, 4, 12), (16, 52, 4, 12), (24, 52, 4, 12), (20, 48, 4, 4), (24, 48, 4, 4)]
UV_RARM_SLIM = [(44, 20, 3, 12), (51, 20, 3, 12), (40, 20, 4, 12), (48, 20, 4, 12), (44, 16, 3, 4), (47, 16, 3, 4)]
UV_LARM_SLIM = [(36, 52, 3, 12), (43, 52, 3, 12), (32, 52, 4, 12), (40, 52, 4, 12), (36, 48, 3, 4), (39, 48, 3, 4)]

# 第二层 UV（★Task417 新增，标准 64×64 外层区块）
UV_HAT = [(40, 8, 8, 8), (56, 8, 8, 8), (32, 8, 8, 8), (48, 8, 8, 8), (40, 0, 8, 8), (48, 0, 8, 8)]
UV_JACKET = [(20, 36, 8, 12), (32, 36, 8, 12), (16, 36, 4, 12), (28, 36, 4, 12), (20, 32, 8, 4), (28, 32, 8, 4)]
UV_RSLEEVE = [(44, 36, 4, 12), (52, 36, 4, 12), (40, 36, 4, 12), (48, 36, 4, 12), (44, 32, 4, 4), (48, 32, 4, 4)]
UV_LSLEEVE = [(52, 52, 4, 12), (60, 52, 4, 12), (48, 52, 4, 12), (56, 52, 4, 12), (52, 48, 4, 4), (56, 48, 4, 4)]
UV_RPANT = [(4, 36, 4, 12), (12, 36, 4, 12), (0, 36, 4, 12), (8, 36, 4, 12), (4, 32, 4, 4), (8, 32, 4, 4)]
UV_LPANT = [(4, 52, 4, 12), (12, 52, 4, 12), (0, 52, 4, 12), (8, 52, 4, 12), (4, 48, 4, 4), (8, 48, 4, 4)]
UV_RSLEEVE_SLIM = [(44, 36, 3, 12), (51, 36, 3, 12), (40, 36, 4, 12), (48, 36, 4, 12), (44, 32, 3, 4), (47, 32, 3, 4)]
UV_LSLEEVE_SLIM = [(52, 52, 3, 12), (59, 52, 3, 12), (48, 52, 4, 12), (56, 52, 4, 12), (52, 48, 3, 4), (55, 48, 3, 4)]

INFLATE = 0.5   # skinview3d 外层膨胀


def rot_y(x, z, th):
    c, s = math.cos(th), math.sin(th)
    return x * c + z * s, -x * s + z * c


def rot_x(y, z, th):
    c, s = math.cos(th), math.sin(th)
    return y * c - z * s, y * s + z * c


def box_faces(cx, cy, cz, hw, hh, hd):
    """返回六面四角（模型空间，y 向上）+ 外法线。面序同 UV 表。
    角点序（各面内）与 ObjC buildBox 投影序一致：四角绕面顺时针（从外看）。"""
    x0, x1 = cx - hw, cx + hw
    y0, y1 = cy - hh, cy + hh
    z0, z1 = cz - hd, cz + hd
    return [
        ((x0, y1, z1), (x1, y1, z1), (x1, y0, z1), (x0, y0, z1), (0, 0, 1)),    # 前 +Z
        ((x1, y1, z0), (x0, y1, z0), (x0, y0, z0), (x1, y0, z0), (0, 0, -1)),   # 后 −Z
        ((x1, y1, z1), (x1, y1, z0), (x1, y0, z0), (x1, y0, z1), (1, 0, 0)),    # 右 +X（模型右 = −X 屏侧由 yaw 决定）
        ((x0, y1, z0), (x0, y1, z1), (x0, y0, z1), (x0, y0, z0), (-1, 0, 0)),   # 左
        ((x0, y1, z0), (x1, y1, z0), (x1, y1, z1), (x0, y1, z1), (0, 1, 0)),    # 上
        ((x0, y0, z1), (x1, y0, z1), (x1, y0, z0), (x0, y0, z0), (0, -1, 0)),   # 下
    ]


def swing_x(p, pivot, th):
    """绕枢轴 RotX 摆动（肢体摆动 = ObjC T(−P)·R·T(+P) 同序）。"""
    px, py, pz = pivot
    x, y, z = p
    y, z = y - py, z - pz
    y, z = rot_x(y, z, th)
    return (x, y + py, z + pz)


def build_model(slim, walk_phase):
    """返回面记录列表 [(四角模型坐标, uv 区块, 外法线, is_overlay)]。
    装配表 = skinview3d BodyPart 逐值（模型 y 0..32，居中 y=16）。"""
    swing = WALK_AMP * math.sin(walk_phase) if walk_phase is not None else 0.0
    arm_cx = 5.75 if slim else 6.25   # 臂中心：体缘 4 + 臂半宽 1.5/2.0 + 0.25 缝隙（skinview3d 口径）

    faces = []

    def add_part(corners_uvs_norms, overlay=False, pivot=None, th=0.0):
        for quad, uv, n in corners_uvs_norms:
            if pivot is not None and th:
                quad = tuple(swing_x(p, pivot, th) for p in quad)
            faces.append((quad, uv, n, overlay))

    def part_faces(cx, cy, cz, w, h, d, uv_table):
        qn = []
        for quad, n, uv in zip(box_faces(cx, cy, cz, w / 2.0, h / 2.0, d / 2.0), uv_table, uv_table):
            qn.append((quad[0:4], uv, quad[4]))
        return qn

    # 头 (0, 28) 8³；身 (0,18) 8×12×4
    add_part(part_faces(0, 28, 0, 8, 8, 8, UV_HEAD))
    add_part(part_faces(0, 18, 0, 8, 12, 4, UV_BODY))
    # 臂 pivot (±(arm_cx), 22)；腿 pivot (±1.9, 12)
    aw = 3.0 if slim else 4.0
    add_part(part_faces(-(arm_cx), 18, 0, aw, 12, 4, UV_RARM_SLIM if slim else UV_RARM), pivot=(-arm_cx, 22, 0), th=swing)
    add_part(part_faces(arm_cx, 18, 0, aw, 12, 4, UV_LARM_SLIM if slim else UV_LARM), pivot=(arm_cx, 22, 0), th=-swing)
    add_part(part_faces(-1.9, 6, 0, 4, 12, 4, UV_RLEG), pivot=(-1.9, 12, 0), th=-swing)
    add_part(part_faces(1.9, 6, 0, 4, 12, 4, UV_LLEG), pivot=(1.9, 12, 0), th=swing)

    # ── 第二层（★Task417）：盒体 +0.5，同枢轴同摆动 ──
    add_part(part_faces(0, 28, 0, 8 + 2 * INFLATE, 8 + 2 * INFLATE, 8 + 2 * INFLATE, UV_HAT), overlay=True)
    add_part(part_faces(0, 18, 0, 8 + INFLATE, 12 + INFLATE, 4 + INFLATE, UV_JACKET), overlay=True)
    add_part(part_faces(-arm_cx, 18, 0, aw + INFLATE, 12 + INFLATE, 4 + INFLATE, UV_RSLEEVE_SLIM if slim else UV_RSLEEVE),
             overlay=True, pivot=(-arm_cx, 22, 0), th=swing)
    add_part(part_faces(arm_cx, 18, 0, aw + INFLATE, 12 + INFLATE, 4 + INFLATE, UV_LSLEEVE_SLIM if slim else UV_LSLEEVE),
             overlay=True, pivot=(arm_cx, 22, 0), th=-swing)
    add_part(part_faces(-1.9, 6, 0, 4 + INFLATE, 12 + INFLATE, 4 + INFLATE, UV_RPANT),
             overlay=True, pivot=(-1.9, 12, 0), th=-swing)
    add_part(part_faces(1.9, 6, 0, 4 + INFLATE, 12 + INFLATE, 4 + INFLATE, UV_LPANT),
             overlay=True, pivot=(1.9, 12, 0), th=swing)
    return faces


def render(skin, faces, yaw_deg, pitch_deg, out_path, w=560, h=720, unit=13.0):
    yaw, pitch = math.radians(yaw_deg), math.radians(pitch_deg)
    light = (-0.35, 0.75, 0.56)   # 左上前光向（与 ObjC 同值）
    light_len = math.sqrt(sum(c * c for c in light))
    light = tuple(c / light_len for c in light)

    sw, sh = skin.size
    sx, sy = sw / 64.0, sh / 64.0
    px = skin.load()

    polys = []
    for quad, uv, n, overlay in faces:
        # 全局旋转 yaw 先 pitch 后（与 ObjC 同帧同序）
        pts = []
        for (x, y, z) in quad:
            x, z = rot_y(x, z, yaw)
            y, z = rot_x(y, z, pitch)
            pts.append((x, y, z))
        # 法线同旋转
        nx, nz = rot_y(n[0], n[2], yaw)
        ny, nz = rot_x(n[1], nz, pitch)
        # 背面剔除（视线 = −Z 相机看 +Z）
        if nz <= 0.0:
            continue
        # CPU 透视 + 屏幕投影（y 翻转为屏幕向下）
        scr = []
        camz = []
        for (x, y, z) in pts:
            pf = D / (D - z * unit)
            sxp = w / 2.0 + x * unit * pf
            syp = h / 2.0 - (y - 16.0) * unit * pf
            scr.append((sxp, syp))
            camz.append(z)
        # 画家序键 = 面中心相机 z
        cz = sum(camz) / 4.0
        # 明暗（法线·光向，0.45 底 + 0.55 峰）
        dl = max(0.0, nx * light[0] + ny * light[1] + nz * light[2])
        shade = 0.45 + 0.55 * dl
        polys.append((cz, scr, uv, shade, overlay))

    polys.sort(key=lambda p: p[0])   # 画家算法：z 小（远）先画

    img = Image.new("RGB", (w, h), (26, 26, 26))
    pxi = img.load()

    def fill_quad(pts, uv, shade, overlay):
        (ux, uy, uw, uh) = uv
        # 屏幕空间四边形光栅化：两三角重心坐标 → UV（重心插值，D=900 近仿射足够验证）
        min_x = max(0, int(min(p[0] for p in pts)))
        max_x = min(w - 1, int(max(p[0] for p in pts)) + 1)
        min_y = max(0, int(min(p[1] for p in pts)))
        max_y = min(h - 1, int(max(p[1] for p in pts)) + 1)
        (x0, y0), (x1, y1), (x2, y2), (x3, y3) = pts
        # UV 角点：p0=(0,0) p1=(1,0) p2=(1,1) p3=(0,1)
        uv0, uv1, uv2, uv3 = (0.0, 0.0), (1.0, 0.0), (1.0, 1.0), (0.0, 1.0)

        def bary(px_, py_, a, b, c):
            det = (b[1] - c[1]) * (a[0] - c[0]) + (c[0] - b[0]) * (a[1] - c[1])
            if abs(det) < 1e-9:
                return None
            l0 = ((b[1] - c[1]) * (px_ - c[0]) + (c[0] - b[0]) * (py_ - c[1])) / det
            l1 = ((c[1] - a[1]) * (px_ - c[0]) + (a[0] - c[0]) * (py_ - c[1])) / det
            l2 = 1.0 - l0 - l1
            return l0, l1, l2

        for yy in range(min_y, max_y + 1):
            for xx in range(min_x, max_x + 1):
                w012 = bary(xx, yy, (x0, y0), (x1, y1), (x2, y2))
                if w012 is not None and min(w012) >= -1e-9:
                    l0, l1, l2 = w012
                    tu = l0 * uv0[0] + l1 * uv1[0] + l2 * uv2[0]
                    tv = l0 * uv0[1] + l1 * uv1[1] + l2 * uv2[1]
                else:
                    w023 = bary(xx, yy, (x0, y0), (x2, y2), (x3, y3))
                    if w023 is None or min(w023) < -1e-9:
                        continue
                    l0, l2, l3 = w023
                    tu = l0 * uv0[0] + l2 * uv2[0] + l3 * uv3[0]
                    tv = l0 * uv0[1] + l2 * uv2[1] + l3 * uv3[1]
                su = (ux + tu * uw) * sx
                sv = (uy + tv * uh) * sy
                r, g, b, a = px[min(int(su), sw - 1), min(int(sv), sh - 1)]
                if a < 8:      # 透明像素跳过（帽层镂空）
                    continue
                if overlay:
                    # 外层与底色混合（alpha 合成；底 = 当前像素）
                    br, bg, bb = pxi[xx, yy]
                    af = a / 255.0
                    r = int(r * af + br * (1 - af))
                    g = int(g * af + bg * (1 - af))
                    b = int(b * af + bb * (1 - af))
                pxi[xx, yy] = (int(r * shade), int(g * shade), int(b * shade))

    for cz, scr, uv, shade, overlay in polys:
        fill_quad(scr, uv, shade, overlay)

    img.save(out_path)
    return out_path


# ── 测试皮肤生成 ──
def make_debug_skin():
    """六部位六面调试色 36 区块（Task415 口径）+ 白点眼。"""
    im = Image.new("RGBA", (64, 64), (0, 0, 0, 0))
    p = im.load()
    colors = {
        "head": (30, 60, 220), "body": (40, 170, 70), "rarm": (45, 200, 180),
        "larm": (60, 110, 230), "rleg": (245, 150, 30), "lleg": (140, 95, 55),
    }
    regions = {
        "head": UV_HEAD, "body": UV_BODY, "rarm": UV_RARM, "larm": UV_LARM,
        "rleg": UV_RLEG, "lleg": UV_LLEG,
    }
    for name, uv in regions.items():
        for (x, y, w, h) in uv:
            for yy in range(y, y + h):
                for xx in range(x, x + w):
                    p[xx, yy] = colors[name] + (255,)
    for i in range(2):
        for j in range(2):
            p[10 + i, 12 + j] = (255, 255, 255, 255)
            p[14 + i, 12 + j] = (255, 255, 255, 255)
    return im


def make_realistic_skin(slim=False):
    """写实风测试皮肤（程序化，零仓库二进制）：Alex 型（橙发/绿衣/灰裤），
    ★帽层头发（含发顶蓬松 + 刘海镂空边缘）= 第二层可视觉验证。"""
    im = Image.new("RGBA", (64, 64), (0, 0, 0, 0))
    p = im.load()

    def fill(uv, rgb, a=255):
        for (x, y, w, h) in uv:
            for yy in range(y, y + h):
                for xx in range(x, x + w):
                    p[xx, yy] = rgb + (a,)

    skin_tone = (232, 190, 160)
    hair = (200, 110, 40)
    shirt = (90, 160, 90)
    shirt_dk = (70, 135, 72)
    pants = (95, 100, 110)
    shoe = (70, 70, 75)

    # 头基础层：脸 + 发顶/后/侧
    fill([UV_HEAD[0]], skin_tone)          # 脸
    fill([UV_HEAD[1]], hair)               # 后脑
    fill([UV_HEAD[2], UV_HEAD[3]], hair)   # 左右（被发覆盖）
    fill([UV_HEAD[4]], hair)               # 顶
    fill([UV_HEAD[5]], skin_tone)          # 底（下巴）
    # 五官：眼/嘴
    for (ex, ey) in [(10, 12), (14, 12)]:
        p[ex, ey] = (70, 130, 90, 255)
        p[ex + 1, ey] = (245, 245, 245, 255)
    p[12, 14] = (200, 130, 120, 255)
    # 身（绿衣）
    fill([UV_BODY[0], UV_BODY[1]], shirt)
    fill([UV_BODY[2], UV_BODY[3]], shirt_dk)
    fill([UV_BODY[4], UV_BODY[5]], shirt)
    # 臂（绿袖 + 肤手）
    arm_uv = UV_RARM_SLIM if slim else UV_RARM
    larm_uv = UV_LARM_SLIM if slim else UV_LARM
    fill([arm_uv[0], arm_uv[1], arm_uv[4], arm_uv[5]], shirt)
    fill([arm_uv[2], arm_uv[3]], shirt_dk)
    for (x, y, w, h) in [arm_uv[0]]:
        for yy in range(y + 8, y + h):
            for xx in range(x, x + w):
                p[xx, yy] = skin_tone + (255,)
    fill([larm_uv[0], larm_uv[1], larm_uv[4], larm_uv[5]], shirt)
    fill([larm_uv[2], larm_uv[3]], shirt_dk)
    for (x, y, w, h) in [larm_uv[0]]:
        for yy in range(y + 8, y + h):
            for xx in range(x, x + w):
                p[xx, yy] = skin_tone + (255,)
    # 腿（裤 + 鞋）
    fill([UV_RLEG[0], UV_RLEG[1], UV_RLEG[4], UV_RLEG[5]], pants)
    fill([UV_RLEG[2], UV_RLEG[3]], (80, 85, 95))
    fill([UV_LLEG[0], UV_LLEG[1], UV_LLEG[4], UV_LLEG[5]], pants)
    fill([UV_LLEG[2], UV_LLEG[3]], (80, 85, 95))
    for uv in (UV_RLEG, UV_LLEG):
        x, y, w, h = uv[0]
        for xx in range(x, x + w):
            for yy in range(y + 9, y + h):
                p[xx, yy] = shoe + (255,)

    # ★ 帽层：发（蓬松轮廓 + 刘海）+ 衣领 + 袖口
    hat = UV_HAT
    fill([hat[4]], hair)                                   # 发顶
    fill([hat[1]], hair)                                   # 后
    fill([hat[2], hat[3]], hair)                           # 两侧
    # 前发 = 刘海：上半实心 + 下缘锯齿（alpha 镂空）
    fx, fy, fw, fh = hat[0]
    for yy in range(fy, fy + 4):
        for xx in range(fx, fx + fw):
            p[xx, yy] = hair + (255,)
    for xx in range(fx, fx + fw):
        drop = (xx - fx) % 3
        for yy in range(fy + 4, fy + 4 + drop + 1):
            p[xx, yy] = hair + (255,)
    # 侧发下缘（垂发两撮）
    for sq in [hat[2], hat[3]]:
        sx_, sy_, sw_, sh_ = sq
        for yy in range(sy_, sy_ + 6):
            p[sx_ + 1, yy] = hair + (255,)
            p[sx_ + 6, yy] = hair + (255,)
    # 衣领（帽层衣前上沿）
    jx, jy, jw, jh = UV_JACKET[0]
    for xx in range(jx, jx + jw):
        p[xx, jy] = shirt_dk + (255,)
        p[xx, jy + 1] = shirt_dk + (220,)
    return im


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else "/tmp/task417_3d"
    os.makedirs(out, exist_ok=True)
    made = []

    # ① 调试色皮肤（对勘 416 CI 图）
    dbg = make_debug_skin()
    faces = build_model(slim=False, walk_phase=None)
    for yaw, pitch, tag in [(0, 0, "front"), (-34.4, -10.3, "three_quarter"), (90, 0, "side"), (0, -35, "top_down")]:
        made.append(render(dbg, faces, yaw, pitch, os.path.join(out, f"debug_{tag}.png")))

    # ② 写实皮肤（帽层生效验证）：3/4 视角 + 正面
    real = make_realistic_skin()
    for yaw, pitch, tag in [(-34.4, -10.3, "three_quarter"), (0, 0, "front"), (30, -8, "other_side")]:
        made.append(render(real, build_model(slim=True, walk_phase=None), yaw, pitch,
                           os.path.join(out, f"real_slim_{tag}.png")))
    # 帽层关闭对勘（同视角）
    made.append(render(real, build_model_nohat(), -34.4, -10.3, os.path.join(out, "real_slim_nohat.png")))

    # ③ 跑步三相位（帽层 + 摆动同帧）
    for ph, tag in [(0.0, "walk0"), (1.2, "walk1"), (2.4, "walk2")]:
        made.append(render(real, build_model(slim=True, walk_phase=ph), -34.4, -10.3,
                           os.path.join(out, f"real_slim_{tag}.png")))

    print("OK ->", len(made), "张")
    for m in made:
        print("  ", m)


def build_model_nohat():
    """帽层关闭对照：仅基础 36 面（对勘帽层贡献）。"""
    faces = build_model(slim=True, walk_phase=None)
    return [f for f in faces if not f[3]]


if __name__ == "__main__":
    main()
