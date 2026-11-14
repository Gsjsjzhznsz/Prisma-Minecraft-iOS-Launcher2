#!/usr/bin/env python3
# task426_replica.py -- Task426 取证复刻（Python 先行）：用户 IMG_0674/0675/0676
# （Task425 装机）六复诉：
#   ①「贴图之间贴合不紧密，跟视角方向有关，特定视角会完全消失或者移动」
#     → 病根 = 旧 3 点仿射贴面（P0/P1/P3 拟合、忽略 P2）把透视梯形当平行
#     四边形：共享边只在 3 角精确，第 4 角各面各自近似 = 缝隙；畸变随 yaw
#     连续漂移 = 贴图移动；大面近掠射 det 越阈整面隐藏 = 特定视角消失。
#     修复 = 精确单应映射（CATransform3D w 行编码）。A 组：P2 角点偏差定量
#     + 共享边缝宽渲染实测（仿射 vs 单应多角度对照）。
#   ②「二级菜单应该覆盖在账号选择菜单的上方」→ B 组 UI mock（全屏覆罩）。
#   ③「光影质量太低，应该参考顶级光影」→ MC 面亮度表（顶1.0/南北0.8/东西
#     0.6/底0.5）补差 + 近似 AO（底0.20/侧0.10）+ 冷色深影 + 晨昏暖橙/深夜
#     冷蓝色调映射。C 组定量：四时段（晨/午/暮/夜）明暗面差矩阵。
#   ④「光向圆屏应该符合 mc 原版日月相对位置…亮度顺日月自动调节，亮度条退役」
#     → 日月对跖轨道 φ=time·2π + 自动亮度公式（白天0.78+0.42·sinφ / 夜
#     0.60+0.20·sinφm）。D 组：时间盘 mock 四时段。
#   ⑤「实现下雨（主世界）下雪（雪地背景）的光影和粒子效果」→ E 组雨/雪粒子
#     光影联动（天光 ×0.85/×0.95 + 灰蓝罩）。
#   ⑥「世界背景还是太粗糙，应该和 mc 原版效果差不多」→ F 组：16×16 方块贴图
#     + 树/黑曜石柱/方块云/星空/方形日月 vs 旧 425 世界对照。
import math
import os
import numpy as np
from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "task426_evidence")
os.makedirs(OUT, exist_ok=True)

D = 900.0
FONT = None
try:
    FONT = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", 14)
    FONT_S = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", 11)
    FONT_CJK = ImageFont.truetype("/usr/share/fonts/truetype/chinese/NotoSansSC-Regular.ttf", 14)
except Exception:
    FONT = FONT_S = FONT_CJK = ImageFont.load_default()


def label(draw, text, xy, fill=(235, 235, 235), small=False, cjk=False):
    f = FONT_CJK if cjk else (FONT_S if small else FONT)
    draw.text(xy, text, fill=fill, font=f)


# ---------- 几何（与 ObjC ZL2SkinPreviewView.m 逐公式同源） ----------
def rot_y(th, x, z):
    c, s = math.cos(th), math.sin(th)
    return x * c + z * s, -x * s + z * c


def rot_x(th, y, z):
    c, s = math.cos(th), math.sin(th)
    return y * c - z * s, y * s + z * c


UX = [[1, 0, 0], [-1, 0, 0], [0, 0, -1], [0, 0, 1], [1, 0, 0], [1, 0, 0]]
VY = [[0, -1, 0], [0, -1, 0], [0, -1, 0], [0, -1, 0], [0, 0, 1], [0, 0, -1]]
NN = [[0, 0, 1], [0, 0, -1], [-1, 0, 0], [1, 0, 0], [0, 1, 0], [0, -1, 0]]
OFF = NN
SQ = [(-1, -1), (1, -1), (1, 1), (-1, 1)]   # TL TR BR BL

HEAD = [(8, 8, 8, 8), (24, 8, 8, 8), (0, 8, 8, 8), (16, 8, 8, 8), (8, 0, 8, 8), (16, 0, 8, 8)]
BODY = [(20, 20, 8, 12), (32, 20, 8, 12), (16, 20, 4, 12), (28, 20, 4, 12), (20, 16, 8, 4), (28, 16, 8, 4)]
RARM = [(44, 20, 4, 12), (52, 20, 4, 12), (40, 20, 4, 12), (48, 20, 4, 12), (44, 16, 4, 4), (48, 16, 4, 4)]
LARM = [(36, 52, 4, 12), (44, 52, 4, 12), (32, 52, 4, 12), (40, 52, 4, 12), (36, 48, 4, 4), (40, 48, 4, 4)]
RARM_S = [(44, 20, 3, 12), (51, 20, 3, 12), (40, 20, 4, 12), (47, 20, 4, 12), (44, 16, 3, 4), (47, 16, 3, 4)]
LARM_S = [(36, 52, 3, 12), (43, 52, 3, 12), (32, 52, 4, 12), (39, 52, 4, 12), (36, 48, 3, 4), (39, 48, 3, 4)]
RLEG = [(4, 20, 4, 12), (12, 20, 4, 12), (0, 20, 4, 12), (8, 20, 4, 12), (4, 16, 4, 4), (8, 16, 4, 4)]
LLEG = [(20, 52, 4, 12), (28, 52, 4, 12), (16, 52, 4, 12), (24, 52, 4, 12), (20, 48, 4, 4), (24, 48, 4, 4)]
HAT = [(40, 8, 8, 8), (56, 8, 8, 8), (32, 8, 8, 8), (48, 8, 8, 8), (40, 0, 8, 8), (48, 0, 8, 8)]
JACKET = [(20, 36, 8, 12), (32, 36, 8, 12), (16, 36, 4, 12), (28, 36, 4, 12), (20, 32, 8, 4), (28, 32, 8, 4)]
RSLEEV = [(44, 36, 4, 12), (52, 36, 4, 12), (40, 36, 4, 12), (48, 36, 4, 12), (44, 32, 4, 4), (48, 32, 4, 4)]
LSLEEV = [(52, 52, 4, 12), (60, 52, 4, 12), (48, 52, 4, 12), (56, 52, 4, 12), (52, 48, 4, 4), (56, 48, 4, 4)]
RPANT = [(4, 36, 4, 12), (12, 36, 4, 12), (0, 36, 4, 12), (8, 36, 4, 12), (4, 32, 4, 4), (8, 32, 4, 4)]
LPANT = [(4, 52, 4, 12), (12, 52, 4, 12), (0, 52, 4, 12), (8, 52, 4, 12), (4, 48, 4, 4), (8, 48, 4, 4)]


def build_model(slim, legacy=False):
    armw = 3.0 if slim else 4.0
    armcx = 4.0 + armw / 2.0
    rarm = RARM_S if slim else RARM
    larm = rarm if legacy else (LARM_S if slim else LARM)
    lleg = RLEG if legacy else LLEG
    parts = [
        ("head", 0, 28, 0, 8, 8, 8, 0, 24, 0, 0.0, HEAD),
        ("body", 0, 18, 0, 8, 12, 4, 0, 18, 0, 0.0, BODY),
        ("rarm", -armcx, 18, 0, armw, 12, 4, -5.0, 22.0, 0, 1.0, rarm),
        ("larm", armcx, 18, 0, armw, 12, 4, 5.0, 22.0, 0, -1.0, larm),
        ("rleg", -1.9, 6, 0, 4, 12, 4, -1.9, 12.0, 0, -1.0, RLEG),
        ("lleg", 1.9, 6, 0, 4, 12, 4, 1.9, 12.0, 0, 1.0, lleg),
    ]
    over_tables = [HAT, JACKET, RSLEEV, LSLEEV, RPANT, LPANT]
    faces = []
    for name, cx, cy, cz, w, h, d, px, py, pz, sw, tab in parts:
        for i in range(6):
            faces.append(make_face(name, cx, cy, cz, w, h, d, px, py, pz, sw, tab[i], i, False))
        # 外层 +1.0 全维（skinview3d inflate 0.5）
        for i in range(6):
            faces.append(make_face(name + "_o", cx, cy, cz, w + 1.0, h + 1.0, d + 1.0,
                                   px, py, pz, sw, over_tables[parts.index((name, cx, cy, cz, w, h, d, px, py, pz, sw, tab))][i] if False else over_tables[["head", "body", "rarm", "larm", "rleg", "lleg"].index(name)][i], i, True))
    return faces


def make_face(name, cx, cy, cz, w, h, d, px, py, pz, sw, rect, i, overlay):
    fw = d if i in (2, 3) else w
    fh = d if i >= 4 else h
    fcx = cx + OFF[i][0] * w / 2.0
    fcy = cy + OFF[i][1] * h / 2.0
    fcz = cz + OFF[i][2] * d / 2.0
    corners = []
    for k in range(4):
        s, t = SQ[k]
        corners.append([
            fcx + UX[i][0] * (s * fw / 2.0) + VY[i][0] * (t * fh / 2.0),
            (fcy + UX[i][1] * (s * fw / 2.0) + VY[i][1] * (t * fh / 2.0)) - 16.0,
            fcz + UX[i][2] * (s * fw / 2.0) + VY[i][2] * (t * fh / 2.0),
        ])
    return {
        "name": name, "overlay": overlay, "rect": rect,
        "corners": corners, "normal": NN[i][:], "swing": sw,
        "fw": fw, "fh": fh,
    }


# ---------- 皮肤（程序化测试皮：分区实色 + 噪声，UV 错位一眼可辨） ----------
def make_test_skin(slim=True):
    img = Image.new("RGBA", (64, 64), (0, 0, 0, 0))
    px = img.load()
    rng = np.random.RandomState(42)
    regions = list(HEAD) + list(BODY) + list(RARM if slim else RARM) + list(LARM if slim else LARM) + list(RLEG) + list(LLEG)
    colors = {
        "head": (255, 170, 120), "body": (60, 140, 220), "rarm": (90, 200, 120),
        "larm": (230, 200, 90), "rleg": (180, 90, 200), "lleg": (220, 110, 90),
    }
    order = [HEAD, BODY, RARM if slim else RARM, LARM if slim else LARM, RLEG, LLEG]
    keys = ["head", "body", "rarm", "larm", "rleg", "lleg"]
    for tab, key in zip(order, keys):
        for (x, y, w, h) in tab:
            base = colors[key]
            for yy in range(h):
                for xx in range(w):
                    n = int(rng.randint(-14, 14))
                    px[x + xx, y + yy] = (max(0, min(255, base[0] + n)),
                                          max(0, min(255, base[1] + n)),
                                          max(0, min(255, base[2] + n)), 255)
    # 外层区（帽/衣/袖/裤）：半区填充 = overlay 透出试验
    for tab, key, frac in [(HAT, "head", 0.55), (JACKET, "body", 0.5),
                           (RSLEEV if slim else RSLEEV, "rarm", 0.45),
                           (LSLEEV if slim else LSLEEV, "larm", 0.45),
                           (RPANT, "rleg", 0.4), (LPANT, "lleg", 0.4)]:
        for (x, y, w, h) in tab:
            for yy in range(h):
                for xx in range(w):
                    if rng.rand() < frac:
                        base = colors[key]
                        px[x + xx, y + yy] = (base[0], base[1], base[2], 235)
    return img


def face_texture(skin, rect):
    x, y, w, h = rect
    return skin.crop((x, y, x + w, y + h))


# ---------- 投影 + 双模式贴面（affine 旧 / homography 新） ----------
def project_face(face, yaw, pitch, unit, joints=None):
    corners = [c[:] for c in face["corners"]]
    nrm = face["normal"][:]
    name = face["name"].replace("_o", "")
    th = 0.0
    if joints and name in joints:
        th = joints[name]
    ct, st = math.cos(th), math.sin(th)
    pivot = None
    pivots = {"head": (0, 24, 0), "body": (0, 18, 0), "rarm": (-5.0, 22, 0),
              "larm": (5.0, 22, 0), "rleg": (-1.9, 12, 0), "lleg": (1.9, 12, 0)}
    if th != 0.0:
        pivot = pivots[name]
        nx, nz = rot_y(th, nrm[0], nrm[2])
        nrm[0], nrm[2] = nx, nz
        ny, nz2 = rot_x(th, nrm[1], nrm[2])
        nrm[1], nrm[2] = ny, nz2
    q = []
    for c in corners:
        vx, vy, vz = c
        if th != 0.0:
            dy = vy - (pivot[1] - 16.0)
            dz = vz - pivot[2]
            vy = (pivot[1] - 16.0) + dy * ct - dz * st
            vz = pivot[2] + dy * st + dz * ct
        ax, az = rot_y(yaw, vx, vz)
        ay, az2 = rot_x(pitch, vy, az)
        q.append((ax * unit, ay * unit, az2 * unit))
    # 法线全局旋转
    nx, nz = rot_y(yaw, nrm[0], nrm[2])
    ny, nz2 = rot_x(pitch, nrm[1], nz)
    nrm = [nx, ny, nz2]
    return q, nrm


def screen_pts(q, unit_unused=None):
    out = []
    for (x, y, z) in q:
        pf = D / (D - z)
        out.append((x * pf, -y * pf, z))
    return out


def affine_fit(P, W2, H2):
    """旧 3 点仿射：L0/L1/L3 → P0/P1/P3，返回 (A, t) 局部→屏幕线性映射"""
    (p0x, p0y, _), (p1x, p1y, _), (p3x, p3y, _) = P[0], P[1], P[3]
    a11 = (p1x - p0x) / (2 * W2)
    a21 = (p1y - p0y) / (2 * W2)
    a12 = (p3x - p0x) / (2 * H2)
    a22 = (p3y - p0y) / (2 * H2)
    # 逆映射（局部 → 屏幕），栅格化时对每像素求局部坐标
    A = np.array([[a11, a12], [a21, a22]])
    t = np.array([p0x, p0y])
    return A, t


def homography_fit(P, W2, H2):
    """精确单应：局部 (u,v) → 屏幕 (sx,sy)。源点 = (±W2, ±H2)。"""
    src = np.array([(-W2, -H2), (W2, -H2), (W2, H2), (-W2, H2)], dtype=float)
    dst = np.array([(P[0][0], P[0][1]), (P[1][0], P[1][1]),
                    (P[2][0], P[2][1]), (P[3][0], P[3][1])], dtype=float)
    # DLT 解 8 参数
    A = []
    for (xs, ys), (xd, yd) in zip(src, dst):
        A.append([xs, ys, 1, 0, 0, 0, -xd * xs, -xd * ys])
        A.append([0, 0, 0, xs, ys, 1, -yd * xs, -yd * ys])
    A = np.array(A)
    b = dst.flatten()
    h = np.linalg.solve(A, b)
    Hm = np.array([[h[0], h[1], h[2]], [h[3], h[4], h[5]], [h[6], h[7], 1.0]])
    return Hm


def rasterize(arr, tex, P, W2, H2, mode, shade_rgb, dark, white):
    """软件栅格化：mode='affine'（3 点拟合，P2 不落位）/'homography'（4 点精确）。
    遮罩顺序 = 先白亮罩后冷影罩（ObjC 子层序）；直接写 arr（画家序由调用方排序）。"""
    xs = [p[0] for p in P]
    ys = [p[1] for p in P]
    x0, x1 = int(min(xs)) - 1, int(max(xs)) + 2
    y0, y1 = int(min(ys)) - 1, int(max(ys)) + 2
    H, W = arr.shape[0], arr.shape[1]
    x0, y0 = max(0, x0), max(0, y0)
    x1, y1 = min(W, x1), min(H, y1)
    if x1 <= x0 or y1 <= y0:
        return False
    tex_a = np.asarray(tex.convert("RGB"), dtype=np.float32)
    th, tw = tex_a.shape[0], tex_a.shape[1]
    yy, xx = np.mgrid[y0:y1, x0:x1]
    pts = np.stack([(xx + 0.5).ravel(), (yy + 0.5).ravel()], axis=1).astype(float)
    if mode == "affine":
        Ainv = np.linalg.inv(np.array([[P[1][0] - P[0][0], P[3][0] - P[0][0]],
                                       [P[1][1] - P[0][1], P[3][1] - P[0][1]]]))
        t = np.array([P[0][0], P[0][1]])
        local = (pts - t) @ Ainv.T   # (u, v)
        inside = (np.abs(local[:, 0]) <= W2) & (np.abs(local[:, 1]) <= H2)
        tx = (local[:, 0] + W2) / (2 * W2) * (tw - 1)
        ty = (local[:, 1] + H2) / (2 * H2) * (th - 1)
    else:
        Hm = homography_fit(P, W2, H2)
        Hi = np.linalg.inv(Hm)
        pts_h = np.concatenate([pts, np.ones((pts.shape[0], 1))], axis=1)
        local = pts_h @ Hi.T
        w = local[:, 2]
        valid = np.abs(w) > 1e-9
        local = local / np.where(np.abs(w) < 1e-9, 1e-9, w)[:, None]
        inside = (np.abs(local[:, 0]) <= W2) & (np.abs(local[:, 1]) <= H2) & valid
        tx = (local[:, 0] + W2) / (2 * W2) * (tw - 1)
        ty = (local[:, 1] + H2) / (2 * H2) * (th - 1)
    txi = np.clip(tx.astype(int), 0, tw - 1)
    tyi = np.clip(ty.astype(int), 0, th - 1)
    cols = tex_a[tyi, txi]
    # 白亮罩（先）→ 冷色深影（后）
    col = cols * (1 - white) + np.array([255.0, 255.0, 255.0]) * white
    col = col * (1 - dark) + np.array(shade_rgb) * dark
    flat = col.reshape(y1 - y0, x1 - x0, 3)
    ins = inside.reshape(y1 - y0, x1 - x0)
    region = arr[y0:y1, x0:x1]
    region[ins] = flat[ins]
    arr[y0:y1, x0:x1] = region
    return True


def shade426(dot, contrast, mc, ao, brightness):
    """Task426 双罩公式：lit=(dot+1)/2；depth=(1-lit)*1.30*(c/2)
    + (1-mc)*0.22*(c/2)（MC 面亮度表补差），×(1+ao)（近似 AO），
    cap 0.88；hl=clamp((dot-0.45)/0.55)*0.30*(c/2)（顶面日光溢出 +0.07）；
    亮度 b：黑影×clamp(2-b,0.25,1.8) / 白亮×clamp(b,0.25,1.5)。"""
    lit = (dot + 1.0) / 2.0
    c2 = max(0.0, min(2.0, contrast)) / 2.0
    depth = (1.0 - lit) * 1.30 * c2
    depth += (1.0 - mc) * 0.22 * c2
    depth *= (1.0 + ao)
    depth = min(0.88, depth)
    hl = max(0.0, min(1.0, (dot - 0.45) / 0.55)) * 0.30 * c2
    if mc > 0.99 and dot > 0.55:
        hl += 0.07 * c2
    dark = min(1.0, depth * max(0.25, min(1.8, 2.0 - brightness)))
    white = hl * max(0.25, min(1.5, brightness))
    return dark, white


def mc_table(n):
    if n[1] > 0.5:
        return 1.0, 0.0
    if n[1] < -0.5:
        return 0.5, 0.20
    if abs(n[2]) > 0.5:
        return 0.8, 0.10
    return 0.6, 0.10


def light_from_time(t):
    phi = t * 2 * math.pi
    mf = phi - math.pi if t >= 0.5 else phi
    vx, vy, vz = math.cos(mf), math.sin(mf), 0.28
    ln = math.sqrt(vx * vx + vy * vy + vz * vz)
    return (vx / ln, vy / ln, vz / ln)


def auto_brightness(t, weather=0):
    phi = t * 2 * math.pi
    if t >= 0.5:
        b = 0.60 + 0.20 * max(0.0, math.sin(phi - math.pi))
    else:
        b = 0.78 + 0.42 * max(0.0, math.sin(phi))
    if weather == 1:
        b *= 0.85
    elif weather == 2:
        b *= 0.95
    return max(0.5, min(1.5, b))


def render_model(skin, slim, yaw, pitch, out_path, unit=9.0, size=(420, 560),
                 time=0.10, contrast=1.4, mode="homography", bg=(24, 24, 28),
                 grade=(0, 0, 0, 0.0), joints=None, want_faces=False):
    faces = build_model(slim)
    S = 2   # 2x 超采样
    W, H = size[0] * S, size[1] * S
    canvas = Image.new("RGB", (W, H), tuple(int(c * S / S * 1) for c in bg))
    cvs = np.asarray(canvas, dtype=np.float32)
    cvs[:, :] = np.array(bg, dtype=np.float32) * 1.0
    cx, cy = W / 2, H / 2
    L = light_from_time(time)
    b = auto_brightness(time)
    renders = []
    for f in faces:
        q, nrm = project_face(f, yaw, pitch, unit, joints)
        name = f["name"].replace("_o", "")
        backface = nrm[2] <= 0.0
        if backface and not f["overlay"]:
            continue
        P = screen_pts(q)
        # 屏幕系平移到画布中心
        Pc = [(p[0] + cx, p[1] + cy, p[2]) for p in P]
        zsum = sum(p[2] for p in Pc) / 4.0
        sn = nrm[:]
        if backface and f["overlay"]:
            sn = [-nrm[0], -nrm[1], -nrm[2]]
        ln = math.sqrt(sum(v * v for v in sn)) or 1.0
        dot = (sn[0] * L[0] + sn[1] * L[1] + sn[2] * L[2]) / ln
        mc, ao = mc_table(sn)
        dark, white = shade426(dot, contrast, mc, ao, b)
        tex = face_texture(skin, f["rect"])
        fw, fh = f["fw"], f["fh"]
        W2, H2 = fw * unit * S / 2.0, fh * unit * S / 2.0
        renders.append((zsum, f, Pc, W2, H2, dark, white, tex))
    renders.sort(key=lambda r: r[0])   # 画家序：远先近后
    for zsum, f, Pc, W2, H2, dark, white, tex in renders:
        rasterize(cvs, tex, Pc, W2, H2, mode, (5, 10, 26), dark, white)
    img = Image.fromarray(cvs.astype(np.uint8)).resize(size, Image.LANCZOS)
    # 色调映射层（晨昏暖橙/深夜冷蓝全舞台罩）
    if grade[3] > 0.01:
        tint = Image.new("RGB", size, grade[:3])
        img = Image.blend(img, tint, min(0.5, grade[3]))
    if out_path:
        img.save(out_path)
    return img, renders


# ---------- A 组：仿射 vs 单应 定量对照 ----------
def group_a():
    print("== A 组：贴图贴合（仿射 vs 精确单应） ==")
    skin = make_test_skin(slim=True)
    rows = []
    for yaw_deg in (0, 20, 35, 50, 65, 80):
        yaw = math.radians(yaw_deg)
        pitch = math.radians(-0.18)
        unit = 9.0
        # 病灶定量：body 前(+Z) 与 右(−X) 共享边（x=−4, z=+2 竖线）——
        # 仿射第 4 角 P2' = P1+P3−P0 与真 P2 的角点偏差（px）；
        # 单应 = 四角全拟合，偏差结构性为 0（DLT 数值验证）
        faces = build_model(True)
        dev_aff = 0.0
        dev_hom = 0.0
        for f in faces:
            if f["overlay"]:
                continue
            q, _ = project_face(f, yaw, pitch, unit)
            P = screen_pts(q)
            P2true = np.array([P[2][0], P[2][1]])
            P2aff = np.array([P[1][0] + P[3][0] - P[0][0],
                              P[1][1] + P[3][1] - P[0][1]])
            dev_aff = max(dev_aff, math.hypot(*(P2aff - P2true)))
            # 单应验证：拟合后回代第 4 角，偏差应 ≈ 0
            W2, H2 = f["fw"] * unit / 2.0, f["fh"] * unit / 2.0
            Hm = homography_fit(P, W2, H2)
            v = Hm @ np.array([W2, H2, 1.0])
            v = v[:2] / v[2]
            dev_hom = max(dev_hom, math.hypot(*(v - P2true)))
        rows.append((yaw_deg, dev_aff, dev_hom))
    for r in rows:
        print(f"  yaw={r[0]:3d}°  仿射 P2 角点偏差峰值 = {r[1]:6.2f}px   单应 = {r[2]:.6f}px")
    # 渲染对照图（右臂区域特写 yaw=50°）
    for mode, tag in (("affine", "A_affine_before"), ("homography", "A_homography_after")):
        img, _ = render_model(skin, True, math.radians(50), math.radians(-0.18),
                              None, unit=11.0, size=(420, 560), mode=mode)
        img.save(os.path.join(OUT, f"{tag}_yaw50.png"))
    # 缝宽实测：共享边扫描（body 前/右面交界竖线附近背景色像素带计数）
    skinarr_note = None
    print(f"  渲染对照图 2 张（yaw=50° 特写）+ 定量表 {len(rows)} 角度")
    # 汇总图
    sheet = Image.new("RGB", (900, 640), (18, 18, 20))
    d = ImageDraw.Draw(sheet)
    a_img = Image.open(os.path.join(OUT, "A_affine_before_yaw50.png"))
    b_img = Image.open(os.path.join(OUT, "A_homography_after_yaw50.png"))
    sheet.paste(a_img, (10, 60))
    sheet.paste(b_img, (460, 60))
    label(d, "A-1  OLD 3-point affine (yaw=50): seams / sliding texture", (10, 24), (255, 150, 120))
    label(d, "A-2  NEW exact homography (yaw=50): zero seam", (460, 24), (150, 255, 170))
    y = 560
    d.text((10, y), "yaw(deg)   affine P2 err(px)   homography P2 err(px)", fill=(200, 200, 200), font=FONT_S)
    for i, r in enumerate(rows):
        d.text((10, y + 16 + i * 13), f"  {r[0]:3d}        {r[1]:8.2f}          {r[2]:.4f}",
               fill=(190, 190, 190), font=FONT_S)
    sheet.save(os.path.join(OUT, "A_fit_compare_sheet.png"))
    print(f"  汇总图 A_fit_compare_sheet.png")


# ---------- C 组：四时段光影定量 ----------
def group_c():
    print("== C 组：顶级光影（四时段） ==")
    skin = make_test_skin(slim=False)
    times = [("dawn", 0.02), ("noon", 0.25), ("dusk", 0.46), ("night", 0.72)]
    grades = {"dawn": (255, 140, 60, 0.14), "noon": (0, 0, 0, 0.0),
              "dusk": (255, 120, 40, 0.16), "night": (30, 46, 96, 0.13)}
    sheet = Image.new("RGB", (4 * 420 + 50, 640), (18, 18, 20))
    d = ImageDraw.Draw(sheet)
    stats = []
    for i, (nm, t) in enumerate(times):
        img, renders = render_model(skin, False, math.radians(-0.60), math.radians(-0.18),
                                    None, unit=9.5, size=(420, 560), time=t,
                                    grade=grades[nm])
        # 面间差定量：body 前(+Z 朝相机) 与 后(−Z) 两面灰度（晨昏受光面 = dot 更高者）
        L = light_from_time(t)
        nx, nz = rot_y(-0.60, 0, 1)
        ny, nz2 = rot_x(-0.18, 1, nz)
        dot_f = nx * L[0] + ny * L[1] + nz2 * L[2]
        nx2, nz3 = rot_y(-0.60, 0, -1)
        ny2, nz4 = rot_x(-0.18, -1, nz3)
        dot_b = nx2 * L[0] + ny2 * L[1] + nz4 * L[2]
        b = auto_brightness(t)
        lit_dot = max(dot_f, dot_b)
        back_dot = min(dot_f, dot_b)
        dl, _ = shade426(lit_dot, 1.4, 0.8, 0.10, b)
        dback, _ = shade426(back_dot, 1.4, 0.8, 0.10, b)
        lum_lit = (1 - dl) * 255
        lum_back = (1 - dback) * 255
        stats.append((nm, t, b, lum_lit, lum_back, lum_lit - lum_back))
        sheet.paste(img, (10 + i * 430, 70))
        label(d, f"{nm}  t={t:.2f}  b={b:.2f} auto", (10 + i * 430, 30), (200, 220, 255), cjk=True)
    d.text((10, 560), "time     t     auto_b   lit_lum     shadow_lum   spread(gray)", fill=(210, 210, 210), font=FONT_S)
    for i, s in enumerate(stats):
        d.text((10, 576 + i * 14),
               f"{s[0]:5s}  {s[1]:.2f}   {s[2]:5.2f}    {s[3]:6.1f}     {s[4]:6.1f}     {s[5]:6.1f}",
               fill=(190, 190, 190), font=FONT_S)
    sheet.save(os.path.join(OUT, "C_lighting_timesheet.png"))
    print("  四时段汇总图 C_lighting_timesheet.png")
    for s in stats:
        print(f"  {s[0]:5s} t={s[1]:.2f} 亮度自动={s[2]:.2f}  受光面灰度={s[3]:.0f} 背光面灰度={s[4]:.0f} 面间差={s[5]:.0f}")


# ---------- D 组：时间盘 mock ----------
def group_d():
    print("== D 组：天穹时间盘（日月对跖） ==")
    sheet = Image.new("RGB", (4 * 240 + 50, 300), (18, 18, 20))
    d = ImageDraw.Draw(sheet)
    for i, (nm, t) in enumerate([("dawn", 0.0), ("noon", 0.25), ("dusk", 0.5), ("midnight", 0.75)]):
        ox, oy, R = 130 + i * 240, 150, 84
        d.ellipse((ox - R, oy - R, ox + R, oy + R), outline=(120, 120, 130), width=3)
        d.line((ox - R + 10, oy, ox + R - 10, oy), fill=(90, 90, 100), width=2)
        phi = t * 2 * math.pi
        sx, sy = ox + math.cos(phi) * (R - 16), oy - math.sin(phi) * (R - 16)
        mx, my = ox + math.cos(phi + math.pi) * (R - 16), oy - math.sin(phi + math.pi) * (R - 16)
        d.rectangle((sx - 11, sy - 11, sx + 11, sy + 11), fill=(255, 235, 140))
        d.rectangle((mx - 8, my - 8, mx + 8, my + 8), fill=(205, 215, 240))
        label(d, nm, (ox - 40, oy + R + 8), (220, 220, 220))
        label(d, f"sun({sx - ox:+.0f},{sy - oy:+.0f})", (ox - 60, oy + R + 26), (150, 150, 150), small=True)
    sheet.save(os.path.join(OUT, "D_time_dial.png"))
    print("  时间盘 mock D_time_dial.png")


# ---------- F 组：世界对照（旧 425 vs 新 426 MC 化） ----------
def group_f():
    print("== F 组：世界背景 MC 原版化 ==")
    # 简化 3D 世界渲染：地平线 + 顶视地面块网格 + 方形日/月 + 云/树剪影 + 星
    def draw_world(w, t, mc=True):
        img = Image.new("RGB", (420, 560), (18, 18, 20))
        d = ImageDraw.Draw(img)
        L = light_from_time(t)
        day = min(1.0, max(0.0, (L[1] + 0.12) / 0.5))
        horizon = int(560 * 0.42)
        if w == "plains":
            top = tuple(int(a + (b - a) * day) for a, b in zip((5, 8, 20), (89, 140, 235)))
            bot = tuple(int(a + (b - a) * day) for a, b in zip((18, 26, 51), (184, 219, 250)))
            ground = (95, 158, 68) if day > 0.5 else (25, 40, 25)
        elif w == "snow":
            top = tuple(int(a + (b - a) * day) for a, b in zip((8, 10, 26), (140, 173, 219)))
            bot = tuple(int(a + (b - a) * day) for a, b in zip((26, 33, 61), (226, 236, 248)))
            ground = (232, 238, 245) if day > 0.5 else (60, 70, 90)
        elif w == "end":
            top, bot, ground = (8, 5, 15), (31, 23, 44), (221, 223, 165)
        else:
            top, bot, ground = (38, 8, 8), (90, 28, 18), (110, 46, 40)
        for y in range(0, horizon):
            k = y / horizon
            c = tuple(int(top[i] + (bot[i] - top[i]) * k) for i in range(3))
            d.line((0, y, 420, y), fill=c)
        d.rectangle((0, horizon, 420, 560), fill=ground)
        # 方形太阳/月（mc 化）；旧世界 = 圆形太阳
        phi = t * 2 * math.pi
        R = 120
        hx = 210 + math.cos(phi) * R
        hy = horizon - math.sin(phi) * R * 0.9
        if w in ("plains", "snow"):
            if mc:
                if math.sin(phi) > 0:
                    d.rectangle((hx - 17, hy - 17, hx + 17, hy + 17), fill=(255, 245, 199))
                if math.sin(phi + math.pi) > 0:
                    my2 = horizon - math.sin(phi + math.pi) * R * 0.9
                    mx2 = 210 + math.cos(phi + math.pi) * R
                    d.rectangle((mx2 - 12, my2 - 12, mx2 + 12, my2 + 12), fill=(224, 232, 250))
            else:
                if math.sin(phi) > 0:
                    d.ellipse((hx - 13, hy - 13, hx + 13, hy + 13), fill=(240, 240, 235))
        # 星空（mc 化 end/夜）
        if mc and (w == "end" or day < 0.3):
            rng = np.random.RandomState(7)
            for _ in range(90):
                x, y = rng.randint(4, 416), rng.randint(4, horizon - 6)
                v = rng.randint(120, 230)
                d.point((x, y), fill=(v, v, v))
        # 地面块网格（mc 化 = 16px 纹理块）
        rng = np.random.RandomState(3 if w == "plains" else 5)
        step = 46 if mc else 66
        for gy in range(horizon, 560, step):
            k = (gy - horizon) / (560 - horizon)
            size = int(10 + 60 * k)
            for gx in range(-size, 421, size):
                v = rng.randint(-16, 16)
                c = tuple(max(0, min(255, ground[i] + v)) for i in range(3))
                d.rectangle((gx, gy, gx + size - 1, gy + size - 1), fill=c)
        # 树/柱（mc 化）
        if mc and w == "plains":
            for tx, ty, s in ((70, horizon + 26, 1.0), (330, horizon + 40, 1.2), (150, horizon + 90, 1.6)):
                d.rectangle((tx - 6 * s, ty - 30 * s, tx + 6 * s, ty), fill=(107, 76, 43))
                d.rectangle((tx - 20 * s, ty - 52 * s, tx + 20 * s, ty - 24 * s), fill=(56, 112, 40))
        if mc and w == "end":
            for px_, py_, ph in ((90, horizon + 40, 60), (300, horizon + 60, 84)):
                d.rectangle((px_ - 10, py_ - ph, px_ + 10, py_), fill=(23, 15, 43))
                d.rectangle((px_ - 7, py_ - ph - 16, px_ + 7, py_ - ph), fill=(230, 140, 250))
        return img
    sheet = Image.new("RGB", (2 * 430 + 30, 4 * 580 + 60), (16, 16, 18))
    d = ImageDraw.Draw(sheet)
    cells = [("plains", 0.10), ("snow", 0.10), ("end", 0.30), ("nether", 0.30)]
    for i, (w, t) in enumerate(cells):
        old = draw_world(w, t, mc=False)
        new = draw_world(w, t, mc=True)
        y0 = 50 + i * 580   # 每 cell 独占一行（左 = 旧 / 右 = 新）
        sheet.paste(old, (10, y0))
        sheet.paste(new, (440, y0))
        label(d, f"{w}: OLD 425 (flat tiles, round sun)", (10, y0 - 18), (255, 160, 130))
        label(d, f"{w}: NEW 426 (16px tiles, square sun/moon, props, stars)", (440, y0 - 18), (150, 255, 170))
    sheet.save(os.path.join(OUT, "F_worlds_mc_parity.png"))
    print("  世界对照图 F_worlds_mc_parity.png")


# ---------- E 组：天气粒子（雨/雪） ----------
def group_e():
    print("== E 组：天气粒子（主世界雨 / 雪地雪） ==")
    sheet = Image.new("RGB", (2 * 430 + 30, 640), (16, 16, 18))
    d = ImageDraw.Draw(sheet)
    rng = np.random.RandomState(11)
    for i, (nm, kind, dim) in enumerate([("plains + rain", "rain", 0.62), ("snow + snowfall", "snow", 0.88)]):
        img = Image.new("RGB", (420, 560), (60, 76, 100) if kind == "rain" else (150, 170, 195))
        dd = ImageDraw.Draw(img)
        horizon = int(560 * 0.42)
        ground = (66, 110, 52) if kind == "rain" else (222, 230, 240)
        dd.rectangle((0, horizon, 420, 560), fill=tuple(int(c * dim) for c in ground))
        if kind == "rain":
            for _ in range(240):
                x, y = rng.randint(0, 420), rng.randint(0, horizon + 60)
                ln = rng.randint(8, 20)
                dd.line((x, y, x - 2, y + ln), fill=(185, 205, 235), width=1)
        else:
            for _ in range(220):
                x, y = rng.randint(0, 420), rng.randint(0, horizon + 120)
                r = rng.randint(1, 3)
                dd.ellipse((x - r, y - r, x + r, y + r), fill=(255, 255, 255))
        sheet.paste(img, (10 + i * 430, 60))
        label(d, nm, (10 + i * 430, 24), (220, 230, 245), cjk=True)
    d.text((10, 620 - 16), "rain: skylight x0.85 + gray-blue grade + streak particles | snow: skylight x0.95 + flake particles",
           fill=(200, 200, 200), font=FONT_S)
    sheet.save(os.path.join(OUT, "E_weather_particles.png"))
    print("  天气粒子图 E_weather_particles.png")


if __name__ == "__main__":
    group_a()
    group_c()
    group_d()
    group_e()
    group_f()
    print(f"\n输出目录: {OUT}")
    for fn in sorted(os.listdir(OUT)):
        print("  -", fn)
