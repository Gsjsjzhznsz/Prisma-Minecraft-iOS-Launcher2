#!/usr/bin/env python3
# task418_3d_fix_preview.py -- Task418 3D 修复数学先行验证（修复前 vs 修复后
# 对比测试图 = 交付用户「测试图呢」的本地实证；公式已同步落 ObjC）。
# 复用 task417 装配表/投影/画家算法骨架，本轮对比三修：
#   ① Nearest 滤镜（after）vs 线性放大（before，CALayer 默认 = 真机雾化）
#   ② shade 罩层 alpha 掩膜（after）vs 全脸罩黑（before = 外层透明区幽灵暗盒）
#   ③ 64×32 旧版 y 同 x 标度 + 仅帽外层（after）vs height/64=0.5 全带压缩 +
#      六外层全建（before = 幽灵盒 + UV 错位）
# 用法: python3 task418_3d_fix_preview.py <out_dir>
import math
import os
import sys

try:
    from PIL import Image, ImageDraw, ImageFont
except ImportError:
    sys.exit("需要 Pillow: pip install pillow")

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import task417_skin3d_overlay_preview as t417   # 装配表/盒体/摆动/写实皮生成器复用

D = 900.0
FONT_REG = "/usr/share/fonts/truetype/chinese/NotoSansSC-Regular.ttf"
FONT_BOLD = "/usr/share/fonts/truetype/chinese/NotoSansSC-Bold.ttf"


def sample_nearest(px, sw, sh, su, sv):
    return px[min(int(su), sw - 1), min(int(sv), sh - 1)]


def sample_bilinear(px, sw, sh, su, sv):
    """双线性采样 = CALayer 默认线性放大（before 雾化源）的纹理侧等效。"""
    x0, y0 = int(math.floor(su)), int(math.floor(sv))
    fx, fy = su - x0, sv - y0
    x0c, y0c = min(x0, sw - 1), min(y0, sh - 1)
    x1c, y1c = min(x0 + 1, sw - 1), min(y0 + 1, sh - 1)
    c00, c10 = px[x0c, y0c], px[x1c, y0c]
    c01, c11 = px[x0c, y1c], px[x1c, y1c]
    out = []
    for i in range(4):
        top = c00[i] * (1 - fx) + c10[i] * fx
        bot = c01[i] * (1 - fx) + c11[i] * fx
        out.append(top * (1 - fy) + bot * fy)
    return tuple(out)


def render_v2(skin, faces, yaw_deg, pitch_deg, out_path,
              w=520, h=680, unit=13.0, nearest=True, mask_shade=True,
              legacy_scale=False):
    """Task418 渲染管线（t417.render 的参数化改造版）。
    nearest=False  → 双线性纹理采样（before：8×8 面纹理被放大 ~25× 的雾化等效）
    mask_shade=False → 明暗罩不区分透明区（before：外层透明区被罩黑 = 幽灵暗盒）
    legacy_scale=True → y 标度 = height/64（before：64×32 全 UV 压半错位）"""
    yaw, pitch = math.radians(yaw_deg), math.radians(pitch_deg)
    light = (-0.35, 0.75, 0.56)
    light_len = math.sqrt(sum(c * c for c in light))
    light = tuple(c / light_len for c in light)

    sw, sh = skin.size
    sx = sw / 64.0
    sy = sh / 64.0 if legacy_scale else sx   # ★修复③：y 同 x 标度
    px = skin.load()

    polys = []
    for quad, uv, n, overlay in faces:
        pts = []
        for (x, y, z) in quad:
            x, z = t417.rot_y(x, z, yaw)
            y, z = t417.rot_x(y, z, pitch)
            pts.append((x, y, z))
        nx, nz = t417.rot_y(n[0], n[2], yaw)
        ny, nz = t417.rot_x(n[1], nz, pitch)
        if nz <= 0.0:
            continue
        scr, camz = [], []
        for (x, y, z) in pts:
            pf = D / (D - z * unit)
            scr.append((w / 2.0 + x * unit * pf, h / 2.0 - (y - 16.0) * unit * pf))
            camz.append(z)
        cz = sum(camz) / 4.0
        dl = max(0.0, nx * light[0] + ny * light[1] + nz * light[2])
        shade = 0.45 + 0.55 * dl
        polys.append((cz, scr, uv, shade, overlay))

    polys.sort(key=lambda p: p[0])

    img = Image.new("RGB", (w, h), (26, 26, 26))
    pxi = img.load()
    sampler = sample_nearest if nearest else sample_bilinear

    def fill_quad(pts, uv, shade, overlay):
        (ux, uy, uw, uh) = uv
        min_x = max(0, int(min(p[0] for p in pts)))
        max_x = min(w - 1, int(max(p[0] for p in pts)) + 1)
        min_y = max(0, int(min(p[1] for p in pts)))
        max_y = min(h - 1, int(max(p[1] for p in pts)) + 1)
        (x0, y0), (x1, y1), (x2, y2), (x3, y3) = pts
        uv0, uv1, uv2, uv3 = (0.0, 0.0), (1.0, 0.0), (1.0, 1.0), (0.0, 1.0)

        def bary(bx, by, a, b, c):
            det = (b[1] - c[1]) * (a[0] - c[0]) + (c[0] - b[0]) * (a[1] - c[1])
            if abs(det) < 1e-9:
                return None
            l0 = ((b[1] - c[1]) * (bx - c[0]) + (c[0] - b[0]) * (by - c[1])) / det
            l1 = ((c[1] - a[1]) * (bx - c[0]) + (a[0] - c[0]) * (by - c[1])) / det
            return l0, l1, 1.0 - l0 - l1

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
                su_, sv_ = (ux + tu * uw) * sx, (uy + tv * uh) * sy
                r, g, b, a = sampler(px, sw, sh, su_, sv_)
                if a < 8:
                    if overlay and not mask_shade:
                        # before：罩层不区分透明区 → 黑罩漏染（幽灵暗盒）
                        br, bg, bb = pxi[xx, yy]
                        pxi[xx, yy] = (int(br * (1.0 - shade) * 0.85),
                                       int(bg * (1.0 - shade) * 0.85),
                                       int(bb * (1.0 - shade) * 0.85))
                    continue
                if overlay:
                    br, bg, bb = pxi[xx, yy]
                    af = a / 255.0
                    r = r * af + br * (1 - af)
                    g = g * af + bg * (1 - af)
                    b = b * af + bb * (1 - af)
                pxi[xx, yy] = (int(r * shade), int(g * shade), int(b * shade))

    for cz, scr, uv, shade, overlay in polys:
        fill_quad(scr, uv, shade, overlay)

    img.save(out_path)
    return out_path


# ── 64×32 旧版皮肤生成（legacy 布局：左臂/左腿由游戏镜像右区）──
def make_legacy_skin():
    im = Image.new("RGBA", (64, 32), (0, 0, 0, 0))
    p = im.load()

    def fill(uv, rgb, a=255):
        for (x, y, w, h) in uv:
            for yy in range(y, y + h):
                for xx in range(x, x + w):
                    p[xx, yy] = rgb + (a,)

    skin_t = (232, 190, 160)
    shirt = (90, 160, 90)
    pants = (95, 100, 110)
    hair = (60, 45, 35)
    fill(t417.UV_HEAD, skin_t)
    fill([t417.UV_HEAD[4]], hair)                      # 发顶
    fill([t417.UV_HEAD[1]], hair)                      # 后脑
    for (ex, ey) in [(10, 12), (14, 12)]:
        p[ex, ey] = (70, 130, 90, 255)
        p[ex + 1, ey] = (245, 245, 245, 255)
    fill(t417.UV_BODY, shirt)
    fill(t417.UV_RARM, shirt)
    fill([t417.UV_RARM[0]], skin_t)                    # 手
    fill(t417.UV_RLEG, pants)
    fill([t417.UV_HAT[4]], hair)                       # 帽层发顶（legacy 唯一真实外层）
    for (x, y, w, h) in [t417.UV_HAT[0]]:
        for yy in range(y, y + 3):
            for xx in range(x, x + w):
                p[xx, yy] = hair + (255,)              # 帽层刘海
    return im


# ── 彩虹渐变皮（对勘用户 IMG_0619：渐变底 + 外层帽/衣真实内容）──
def make_rainbow_skin():
    im = Image.new("RGBA", (64, 64), (0, 0, 0, 0))
    p = im.load()
    all_regions = (t417.UV_HEAD + t417.UV_BODY + t417.UV_RARM + t417.UV_LARM
                   + t417.UV_RLEG + t417.UV_LLEG)
    for (x, y, w, h) in all_regions:
        for yy in range(y, y + h):
            for xx in range(x, x + w):
                hue = (xx * 4 + yy * 6) % 256
                r, g, b = hsv_rgb(hue / 255.0, 0.55, 0.92)
                p[xx, yy] = (r, g, b, 255)
    # 眼
    for (ex, ey) in [(10, 12), (14, 12)]:
        p[ex, ey] = (30, 40, 80, 255)
        p[ex + 1, ey] = (240, 240, 255, 255)
    # 外层：帽层发 + 衣领/袖口（有 3D 图层的皮肤）
    hair = (240, 90, 160)
    for (x, y, w, h) in [t417.UV_HAT[4], t417.UV_HAT[1]]:
        for yy in range(y, y + h):
            for xx in range(x, x + w):
                p[xx, yy] = hair + (255,)
    fx, fy, fw, fh = t417.UV_HAT[0]
    for yy in range(fy, fy + 3):
        for xx in range(fx, fx + fw):
            p[xx, yy] = hair + (255,)
    for sq in [t417.UV_HAT[2], t417.UV_HAT[3]]:
        sx_, sy_, sw_, sh_ = sq
        for yy in range(sy_, sy_ + 5):
            p[sx_ + 1, yy] = hair + (255,)
            p[sx_ + 6, yy] = hair + (255,)
    jx, jy, jw, jh = t417.UV_JACKET[0]
    for xx in range(jx, jx + jw):
        p[xx, jy] = (255, 255, 255, 235)
    return im


def hsv_rgb(h, s, v):
    i = int(h * 6.0) % 6
    f = h * 6.0 - int(h * 6.0)
    pp = v * (1 - s)
    q = v * (1 - f * s)
    t = v * (1 - (1 - f) * s)
    r, g, b = [(v, t, pp), (q, v, pp), (pp, v, t), (pp, q, v), (t, pp, v), (v, pp, q)][i]
    return int(r * 255), int(g * 255), int(b * 255)


def build_model_64x64(slim):
    return t417.build_model(slim=slim, walk_phase=None)


def build_model_legacy():
    """64×32 旧版装配：左臂/左腿镜像右区（ObjC legacy 分支同口径）；
    外层仅帽（★修复④；before 版外层六件全建 = 幽灵盒对照）。"""
    faces = []

    def part(cx, cy, cz, w, h, d, uv_table, overlay=False, pivot=None, th=0.0):
        qn = []
        boxes = t417.box_faces(cx, cy, cz, w / 2.0, h / 2.0, d / 2.0)
        for box, uv in zip(boxes, uv_table):
            quad, n = box[0:4], box[4]
            qn.append((quad, uv, n))
        for quad, uv, n in qn:
            if pivot is not None and th:
                quad = tuple(t417.swing_x(pp, pivot, th) for pp in quad)
            faces.append((quad, uv, n, overlay))

    aw, arm_cx = 4.0, 6.0
    part(0, 28, 0, 8, 8, 8, t417.UV_HEAD)
    part(0, 18, 0, 8, 12, 4, t417.UV_BODY)
    part(-arm_cx, 18, 0, aw, 12, 4, t417.UV_RARM, pivot=(-arm_cx, 22, 0))
    part(arm_cx, 18, 0, aw, 12, 4, t417.UV_RARM, pivot=(arm_cx, 22, 0))    # 左=镜像右（legacy）
    part(-1.9, 6, 0, 4, 12, 4, t417.UV_RLEG, pivot=(-1.9, 12, 0))
    part(1.9, 6, 0, 4, 12, 4, t417.UV_RLEG, pivot=(1.9, 12, 0))
    return faces


def build_model_legacy_before():
    """before 版 legacy：外层六件全建（旧 ObjC 行为，衣/袖/裤区块经 0.5 压缩
    读到基础层像素 = 幽灵盒）。"""
    faces = build_model_legacy()
    aw, arm_cx = 4.0, 6.0

    def add_overlay(cx, cy, cz, w, h, d, uv_table, pivot=None):
        boxes = t417.box_faces(cx, cy, cz, w / 2.0, h / 2.0, d / 2.0)
        for box, uv in zip(boxes, uv_table):
            quad, n = box[0:4], box[4]
            faces.append((quad, uv, n, True))

    add_overlay(0, 28, 0, 9, 9, 9, t417.UV_HAT)
    add_overlay(0, 18, 0, 9, 13, 5, t417.UV_JACKET)
    add_overlay(-arm_cx, 18, 0, 5, 13, 5, t417.UV_RSLEEVE, pivot=(-arm_cx, 22, 0))
    add_overlay(arm_cx, 18, 0, 5, 13, 5, t417.UV_RSLEEVE, pivot=(arm_cx, 22, 0))
    add_overlay(-1.9, 6, 0, 5, 13, 5, t417.UV_RPANT, pivot=(-1.9, 12, 0))
    add_overlay(1.9, 6, 0, 5, 13, 5, t417.UV_RPANT, pivot=(1.9, 12, 0))
    return faces


def compose_pair(before_path, after_path, title, note_before, note_after, out_path):
    """并排对比面板（标签中文）。"""
    bi = Image.open(before_path)
    ai = Image.open(after_path)
    pad, head, cap = 24, 64, 56
    W = pad + bi.width + pad + ai.width + pad
    H = head + max(bi.height, ai.height) + cap + pad
    panel = Image.new("RGB", (W, H), (16, 16, 16))
    d = ImageDraw.Draw(panel)
    f_t = ImageFont.truetype(FONT_BOLD, 30)
    f_s = ImageFont.truetype(FONT_REG, 20)
    d.text((pad, 16), title, font=f_t, fill=(240, 240, 240))
    panel.paste(bi, (pad, head))
    panel.paste(ai, (pad + bi.width + pad, head))
    cx1 = pad + bi.width // 2
    cx2 = pad + bi.width + pad + ai.width // 2
    d.text((cx1 - len(note_before) * 5 - 40, head + bi.height + 12), note_before,
           font=f_s, fill=(255, 130, 130))
    d.text((cx2 - len(note_after) * 5 - 40, head + ai.height + 12), note_after,
           font=f_s, fill=(130, 230, 150))
    panel.save(out_path)
    return out_path


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else "/tmp/task418_3d"
    os.makedirs(out, exist_ok=True)
    made = []
    yaw, pitch = -34.4, -10.3   # 3/4 机位（Task416-r3 皮肤站惯例起步值）

    # ① 写实皮 64×64：before（线性放大+罩黑）vs after（Nearest+掩膜）
    real = t417.make_realistic_skin()
    faces64 = build_model_64x64(slim=True)
    render_v2(real, faces64, yaw, pitch, f"{out}/b_real.png", nearest=False, mask_shade=False)
    render_v2(real, faces64, yaw, pitch, f"{out}/a_real.png", nearest=True, mask_shade=True)
    made.append(compose_pair(f"{out}/b_real.png", f"{out}/a_real.png",
                             "写实皮 64×64（帽层头发/衣领）——修复前 vs 修复后",
                             "修复前：线性放大雾化 + 外层透明区漏黑",
                             "修复后：Nearest 锐利 + 掩膜外层",
                             f"{out}/cmp_real_64x64.png"))

    # ② 彩虹渐变皮（用户 IMG_0619 同型）：同口径对比
    rb = make_rainbow_skin()
    render_v2(rb, faces64, yaw, pitch, f"{out}/b_rainbow.png", nearest=False, mask_shade=False)
    render_v2(rb, faces64, yaw, pitch, f"{out}/a_rainbow.png", nearest=True, mask_shade=True)
    made.append(compose_pair(f"{out}/b_rainbow.png", f"{out}/a_rainbow.png",
                             "彩虹渐变皮（用户皮肤同型，有 3D 图层）——修复前 vs 修复后",
                             "修复前：模型雾糊 + 每部位幽灵暗盒",
                             "修复后：像素锐利 + 外层随 alpha 显隐",
                             f"{out}/cmp_rainbow_64x64.png"))

    # ③ legacy 64×32：before（y 压半 + 六外层全建）vs after（y 同 x + 仅帽外层）
    leg = make_legacy_skin()
    faces_leg_before = build_model_legacy_before()
    # after 版外层 = 仅帽（帽 9³ 盒 + 帽 UV；★修复④）
    faces_leg_after = list(build_model_legacy())
    hat_boxes = t417.box_faces(0, 28, 0, 4.5, 4.5, 4.5)
    for box, uv in zip(hat_boxes, t417.UV_HAT):
        faces_leg_after.append((box[0:4], uv, box[4], True))
    render_v2(leg, faces_leg_before, yaw, pitch, f"{out}/b_legacy.png",
              nearest=True, mask_shade=True, legacy_scale=True)
    render_v2(leg, faces_leg_after, yaw, pitch, f"{out}/a_legacy.png",
              nearest=True, mask_shade=True, legacy_scale=False)
    made.append(compose_pair(f"{out}/b_legacy.png", f"{out}/a_legacy.png",
                             "旧版皮 64×32——修复前 vs 修复后",
                             "修复前：y 压半 UV 全错位 + 六外层幽灵盒",
                             "修复后：y 同 x 标度 + 仅帽外层",
                             f"{out}/cmp_legacy_64x32.png"))

    print("OK ->", len(made), "组对比图")
    for m in made:
        print("  ", m)


if __name__ == "__main__":
    main()
