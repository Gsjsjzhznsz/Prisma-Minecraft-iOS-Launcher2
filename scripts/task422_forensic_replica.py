#!/usr/bin/env python3
# task422_forensic_replica.py -- Task422 取证复刻（Python 先行）：
# 复刻用户 IMG_0667（Task421 装机）预览病灶：躯干两侧暗带（rgb≈19<背景25）
# + 外层盒 ghost 框 + 臂区雾蓝残条。公式与 HEAD ZL2SkinPreviewView.m 逐行同源
# （复用 task420_skin_preview_replica.py 转写表），输出：
#   1) 每面屏幕覆盖区间表（判暗带来源面）
#   2) 修复前(HEAD)/修复后(Task422) 对比图
import math
import os
import sys
import importlib.util

HERE = os.path.dirname(os.path.abspath(__file__))
_spec = importlib.util.spec_from_file_location(
    "rep420", os.path.join(HERE, "task420_skin_preview_replica.py"))
rep = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(rep)

from PIL import Image, ImageDraw

BG = (25, 25, 25)


# ── 用户型全息皮参数化重建（IMG_0667 头像/模型取色反推）──
def make_user_hologram(dust=0, dust_regions=("jacket", "sleeve", "pant", "hat")):
    """淡彩渐变基础层（α≈178=0.70，≥26 裁切后不透明）+ 饱和彩虹边框外层
    （α≈153=0.60）+ 可选微尘层（α=dust，模拟 faint glow）。"""
    img = Image.new("RGBA", (64, 64), (0, 0, 0, 0))
    px = img.load()

    def grad(x, y):
        # 淡青→粉对角渐变（头像取色：左上 (200,230,240) 右下 (240,200,230)）
        t = (x / 64.0 + y / 64.0) / 2.0
        r = int(200 + 40 * t); g = int(230 - 30 * t); b = int(240 - 10 * t)
        return (r, g, b)

    RAINBOW = [(255, 70, 70), (255, 160, 50), (250, 240, 60),
               (80, 220, 110), (70, 160, 255), (185, 90, 250)]

    def fill_base(x0, y0, w, h):
        for yy in range(y0, y0 + h):
            for xx in range(x0, x0 + w):
                c = grad(xx, yy)
                px[xx, yy] = (c[0], c[1], c[2], 178)

    def fill_overlay(rect, color, alpha=153):
        x0, y0, w, h = rect
        for yy in range(y0, y0 + h):
            for xx in range(x0, x0 + w):
                px[xx, yy] = (color[0], color[1], color[2], alpha)

    def border_overlay(rect, color, alpha=153, t=1):
        """区块边缘 t px 边框（彩虹边框风格）。"""
        x0, y0, w, h = rect
        for xx in range(x0, x0 + w):
            for d in range(t):
                px[xx, y0 + d] = (*color, alpha)
                px[xx, y0 + h - 1 - d] = (*color, alpha)
        for yy in range(y0, y0 + h):
            for d in range(t):
                px[x0 + d, yy] = (*color, alpha)
                px[x0 + w - 1 - d, yy] = (*color, alpha)

    # 基础层（淡彩，slim 臂 3 宽）
    fill_base(8, 8, 8, 8)        # 头前
    fill_base(0, 8, 8, 8); fill_base(16, 8, 8, 8); fill_base(24, 8, 8, 8)  # 头侧后
    fill_base(8, 0, 8, 8); fill_base(16, 0, 8, 8)                          # 头顶底
    fill_base(20, 20, 8, 12)     # 身前
    fill_base(32, 20, 8, 12); fill_base(16, 20, 4, 12); fill_base(28, 20, 4, 12)  # 身后侧
    fill_base(20, 16, 8, 4); fill_base(28, 16, 8, 4)
    fill_base(44, 20, 3, 12); fill_base(51, 20, 3, 12)                     # 右臂前/后 slim
    fill_base(40, 20, 4, 12); fill_base(47, 20, 4, 12)                     # 右臂侧×2
    fill_base(44, 16, 3, 4); fill_base(47, 16, 3, 4)                       # 右臂上下
    fill_base(36, 52, 3, 12); fill_base(43, 52, 3, 12)                     # 左臂前/后
    fill_base(32, 52, 4, 12); fill_base(39, 52, 4, 12)
    fill_base(36, 48, 3, 4); fill_base(39, 48, 3, 4)
    fill_base(4, 20, 4, 12); fill_base(12, 20, 4, 12)                      # 右腿
    fill_base(0, 20, 4, 12); fill_base(8, 20, 4, 12)
    fill_base(4, 16, 4, 4); fill_base(8, 16, 4, 4)
    fill_base(4, 52, 4, 12); fill_base(12, 52, 4, 12)                      # 左腿
    fill_base(0, 52, 4, 12); fill_base(8, 52, 4, 12)
    fill_base(4, 48, 4, 4); fill_base(8, 48, 4, 4)
    px[10, 11] = (40, 60, 255, 255)    # 眼（饱和蓝）
    px[13, 11] = (150, 30, 240, 255)   # 眼（饱和紫）
    # 故障条纹（glitch 风格；IMG_0667 定谳：臂前脸内缘 1 列 α=0 裁切 + 1 列
    # 深紫半透 → 带内透出半透外层罩背景压暗 = rgb19<25 暗带实拍病灶）
    for (fx0, fy0, fw_) in [(44, 20, 3), (36, 52, 3)]:
        for yy in range(fy0, fy0 + 12):
            px[fx0 + fw_ - 1, yy] = (0, 0, 0, 0)
            px[fx0 + fw_ - 2, yy] = (30, 24, 44, 90)
    # 内侧面暗列（IMG_0667 右侧 3pt 暗条复现）：内侧面掠射角 shade≈0.44 →
    # 罩力度最大 → 深紫半透列蒙罩压至 < 底色（before 19~23 / after ≥底）
    for (sx0, sy0) in [(48, 20), (32, 52)]:
        for yy in range(sy0, sy0 + 12):
            for xx in range(sx0, sx0 + 4):
                px[xx, yy] = (30, 24, 44, 90)

    # 外层：彩虹边框（帽/衣/袖/裤 6 区块）
    tables = [rep.UV_HAT, rep.UV_JACKET, rep.UV_RSLEEVE_SLIM, rep.UV_LSLEEVE_SLIM,
              rep.UV_RPANT, rep.UV_LPANT]
    names = ["hat", "jacket", "rsleeve", "lsleeve", "rpant", "lpant"]
    for i, (tbl, nm) in enumerate(zip(tables, names)):
        if dust > 0 and nm in dust_regions:
            for (x0, y0, w, h) in tbl:
                for yy in range(y0, y0 + h):
                    for xx in range(x0, x0 + w):
                        px[xx, yy] = (30, 24, 44, dust)   # 深紫暗辉光（故障风；IMG_0667 暗带 19<25 反推）
        for j, rect in enumerate(tbl):
            border_overlay(rect, RAINBOW[(i + j) % 6], 153, t=1)
    return img


# ── 逐面投影区间表（判暗带来源）──
def face_spans(skin, slim, yaw, pitch, unit, cen, size, dark_veil=True):
    W, H = size
    faces = rep.build_model(slim, skin.size[0], skin.size[1])
    rows = []
    for f in faces:
        nx, ny, nz = f["normal"]
        nx, nz = rep.rot_y(nx, nz, yaw)
        ny, nz = rep.rot_x(ny, nz, pitch)
        backface = nz <= 0.0
        if backface and not f["overlay"]:
            continue
        sx = [0.0] * 4; sy = [0.0] * 4; zsum = 0.0
        for k in range(4):
            vx, vy, vz = f["corners"][k]
            vx, vz = rep.rot_y(vx, vz, yaw)
            vy, vz = rep.rot_x(vy, vz, pitch)
            vx *= unit; vy *= unit; vz *= unit
            pf = rep.D / (rep.D - vz)
            sx[k] = vx * pf; sy[k] = -vy * pf
            zsum += vz
        xs = [cen[0] + v for v in sx]
        ys = [cen[1] + v for v in sy]
        rows.append({
            "overlay": f["overlay"], "uv": f["uv"],
            "xmin": round(min(xs), 1), "xmax": round(max(xs), 1),
            "ymin": round(min(ys), 1), "ymax": round(max(ys), 1),
            "z": round(zsum / 4.0, 1), "backface": backface,
            "shaded": True,
        })
    rows.sort(key=lambda r: r["z"])
    return rows


def main():
    out_dir = sys.argv[1] if len(sys.argv) > 1 else "/tmp/task422_forensic"
    os.makedirs(out_dir, exist_ok=True)

    skin = make_user_hologram(dust=140)
    skin.save(os.path.join(out_dir, "skin_user_hologram_recon.png"))

    # 相机：IMG_0667 实测 unit≈24.6px(@2x)，网格搜 yaw/pitch 匹配臂带跨度
    size = (1180, 820)          # @1x pt 口径（截图/2）；span 表按此坐标系
    cen = (1008, 391)           # 模型中心（躯干中心 2015/2, 纵中心 782/2）
    unit = 12.3
    yaw = math.radians(17)
    pitch = math.radians(-20)

    rows = face_spans(skin, True, yaw, pitch, unit, cen, size)
    print("== y=350(pt,=700@2x) 横向各面覆盖区间（pt）==")
    target_y = 350.0
    for r in rows:
        if r["ymin"] <= target_y <= r["ymax"]:
            print(f"  z={r['z']:7.1f} {'OVL' if r['overlay'] else 'BSE'}"
                  f"{' BF' if r['backface'] else '   '} uv={r['uv']} "
                  f"x=[{r['xmin']:7.1f},{r['xmax']:7.1f}] "
                  f"y=[{r['ymin']:6.1f},{r['ymax']:6.1f}]")
    print("实测@2x折算pt: 左臂亮[914,940] 暗[940,950.5] 主[951,1064] "
          "暗[1064,1067] 雾蓝[1067.5,1081.5]")

    # 渲染修复前（HEAD 语义：暗罩蒙合成）与修复后（外层罩仅近不透明像素）
    faces = rep.build_model(True, 64, 64)
    p_before = os.path.join(out_dir, "E2_before_head_semantics.png")
    rep.render(skin, faces, yaw, pitch, p_before, unit=unit, size=(400, 640),
               bg=BG)
    p_after = os.path.join(out_dir, "E2_after_task422_semantics.png")
    rep.render(skin, faces, yaw, pitch, p_after, unit=unit, size=(400, 640),
               bg=BG, overlay_veil_opaque_only=True)

    # 修复前/后 缝隙区暗带定量（IMG_0667 实测 rgb19<25 对照）
    for tag, path in (("before", p_before), ("after", p_after)):
        im = Image.open(path).convert("RGB")
        vals = []
        for x in range(137, 158):
            for y in range(300, 440, 3):
                vals.append(im.getpixel((x, y)))
        mn = min(vals, key=lambda v: v[0])
        print(f"E2 {tag} 左缝区 R 最小值 = {mn[0]}（实测设备 19，底 25）")

    # ── E3: 四象限 原版/全息 × Alex/Steve（修复后语义渲染）──
    def fetch_skin(name):
        for cand in (f"/tmp/{name}.png",):
            if os.path.exists(cand):
                return Image.open(cand).convert("RGBA")
        return None

    alex = fetch_skin("mhf_alex")
    steve = fetch_skin("mhf_steve")
    quad = []
    if alex is not None:
        p = os.path.join(out_dir, "E3_quad_vanilla_alex.png")
        rep.render(alex, rep.build_model(True, 64, 64), yaw, pitch, p,
                   unit=unit, size=(400, 640), bg=BG,
                   overlay_veil_opaque_only=True)
        quad.append((p, "原版 MHF_Alex · slim（修复后语义）"))
    if steve is not None:
        p = os.path.join(out_dir, "E3_quad_vanilla_steve.png")
        rep.render(steve, rep.build_model(False, 64, 64), yaw, pitch, p,
                   unit=unit, size=(400, 640), bg=BG,
                   overlay_veil_opaque_only=True)
        quad.append((p, "原版 MHF_Steve · classic（修复后语义）"))
    p = os.path.join(out_dir, "E3_quad_hologram_alex.png")
    rep.render(skin, rep.build_model(True, 64, 64), yaw, pitch, p,
               unit=unit, size=(400, 640), bg=BG, overlay_veil_opaque_only=True)
    quad.append((p, "用户型全息皮 · slim（修复后语义）"))
    p = os.path.join(out_dir, "E3_quad_hologram_steve.png")
    rep.render(make_hologram_classic(), rep.build_model(False, 64, 64),
               yaw, pitch, p, unit=unit, size=(400, 640), bg=BG,
               overlay_veil_opaque_only=True)
    quad.append((p, "用户型全息皮 · classic（修复后语义）"))

    # ── E4: harness 全息皮暗罩回归（Task419 规格 α0.60 彩虹）──
    holo = rep.make_hologram_skin()
    holo.save(os.path.join(out_dir, "skin_harness_hologram.png"))
    p_hb = os.path.join(out_dir, "E4_harness_before.png")
    rep.render(holo, rep.build_model(True, 64, 64), yaw, pitch, p_hb,
               unit=unit, size=(400, 640), bg=BG)
    p_ha = os.path.join(out_dir, "E4_harness_after.png")
    rep.render(holo, rep.build_model(True, 64, 64), yaw, pitch, p_ha,
               unit=unit, size=(400, 640), bg=BG, overlay_veil_opaque_only=True)

    # ── E5: 证据拼板 ──
    board = os.path.join(out_dir, "E5_task422_evidence_board.png")
    compose_evidence_board(quad, p_before, p_after, p_hb, p_ha, board)
    print("evidence board:", board)


def make_hologram_classic(dust=0):
    """classic（Steve 4 宽臂）版用户型全息皮：slim 臂区清空重画 4 宽彩虹。"""
    img = make_user_hologram(dust=dust)
    px = img.load()
    for (x0, y0, w, h) in [(44, 20, 3, 12), (51, 20, 3, 12), (40, 20, 4, 12),
                           (47, 20, 4, 12), (44, 16, 3, 4), (47, 16, 3, 4),
                           (36, 52, 3, 12), (43, 52, 3, 12), (32, 52, 4, 12),
                           (39, 52, 4, 12), (36, 48, 3, 4), (39, 48, 3, 4)]:
        for yy in range(y0, y0 + h):
            for xx in range(x0, x0 + w):
                px[xx, yy] = (0, 0, 0, 0)
    RAINBOW = [(255, 70, 70), (255, 160, 50), (250, 240, 60),
               (80, 220, 110), (70, 160, 255), (185, 90, 250)]
    tables = [(44, 20, 4, 12), (52, 20, 4, 12), (40, 20, 4, 12), (48, 20, 4, 12),
              (44, 16, 4, 4), (48, 16, 4, 4),
              (36, 52, 4, 12), (44, 52, 4, 12), (32, 52, 4, 12), (40, 52, 4, 12),
              (36, 48, 4, 4), (40, 48, 4, 4),
              (44, 36, 4, 12), (52, 36, 4, 12), (40, 36, 4, 12), (48, 36, 4, 12),
              (44, 32, 4, 4), (48, 32, 4, 4),
              (52, 52, 4, 12), (60, 52, 4, 12), (48, 52, 4, 12), (56, 52, 4, 12),
              (52, 48, 4, 4), (56, 48, 4, 4)]
    for i, (x0, y0, w, h) in enumerate(tables):
        for yy in range(y0, y0 + h):
            for xx in range(x0, x0 + w):
                c = RAINBOW[(i // 6) % 6]
                px[xx, yy] = (c[0], c[1], c[2], 178)
    return img


def compose_evidence_board(quad, p_before, p_after, p_hb, p_ha, out_path):
    """2×4 证据板：四象限（修复后语义）+ 用户病灶 before/after + harness 回归。"""
    import glob
    from PIL import ImageDraw, ImageFont
    cell_w, cell_h, cap_h = 400, 640, 40
    cols = 4
    W = cols * cell_w + (cols + 1) * 10
    H = 2 * (cell_h + cap_h) + 70
    board = Image.new("RGB", (W, H), (16, 16, 18))
    dr = ImageDraw.Draw(board)
    fp = glob.glob("/usr/share/fonts/truetype/chinese/NotoSansSC-Regular.ttf")
    font = ImageFont.truetype(fp[0], 22) if fp else ImageFont.load_default()
    font_s = ImageFont.truetype(fp[0], 16) if fp else ImageFont.load_default()
    dr.text((W // 2 - 300, 18),
            "Task422 · 预览渲染取证（Python 复刻 = 与 ObjC 逐公式同源）",
            fill=(235, 235, 235), font=font)
    cells = list(quad)
    cells += [(p_before, "修复前（HEAD 语义）：半透外层蒙黑罩 = 暗带/暗环"),
              (p_after, "修复后（Task422）：罩仅近不透明像素 = 半透区全亮"),
              (p_hb, "harness 全息皮 · 修复前"),
              (p_ha, "harness 全息皮 · 修复后")]
    for i, (p, cap) in enumerate(cells):
        r, c = divmod(i, cols)
        x = 10 + c * (cell_w + 10)
        y = 70 + r * (cell_h + cap_h)
        board.paste(Image.open(p).convert("RGB"), (x, y))
        dr.text((x + 4, y + cell_h + 6), cap, fill=(190, 195, 205), font=font_s)
        dr.rectangle([x, y, x + cell_w, y + cell_h], outline=(70, 70, 76), width=1)
    board.save(out_path)


if __name__ == "__main__":
    main()
