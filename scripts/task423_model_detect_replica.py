#!/usr/bin/env python3
# task423_model_detect_replica.py -- Task423 取证复刻（Python 先行）：
# 用户 IMG_0668（Task422 装机，代际角标 Task422·2026-11-14 上镜）复诉
# 「aelx都有问题」：3D 预览渲染默认 Alex 皮时双臂只剩 ~30px/46px 细条
# + 臂躯间 24~30px 纯背景缝，且账户头像（粉彩渐变脸）与舞台（橙发 Alex）
# 同屏矛盾。IMG_0668 像素取证（work416 会话实录）：
#   scale≈20px/px、yaw≈31°、俯仰≈23°（头 8px 立方 210px / 躯干 221px /
#   腿 224px 比例全对 = 几何无罪）；右臂细条 46px≈2.3px 模型列 =
#   经典背区 (52,20,4x12) ∩ slim 背区 (51,20,3x12) = 2 列实贴内容 +
#   2 列废弃透明（α=0 被基础层 α<26 裁切吃掉）像素级吻合。
# 毒源取证（本会话实抓，fixtures 入库）：
#   crafatar.com/skins/<任意合法格式未知 UUID> → 64×64 默认 Alex
#   （RArm-back(52,20,4x12) 平均 α=127 = slim 内容半区透明实锤）；
#   minotar.net/skin/<未知用户名> → 64×32 Steve；两源均不写 avatar/
#   skinfull（只写账户级缓存）→ mtime 仲裁被毒缓存压过真皮 → 舞台锁死
#   默认 Alex + 头像粉彩同屏矛盾闭环。
# 本脚本输出（与 HEAD ZL2SkinPreviewView.m 逐公式同源）：
#   E1 修复前后渲染对比：同一默认 Alex 皮 ①经典 UV 表（HEAD 现症 = 细臂）
#      ②slim UV 表（Task423 内容判定后 = 全臂）③Steve 经典皮回归对照
#   E2 内容级模型判定探针表：右臂 x54..55 / 左臂 x46..47 经典专属列
#      alpha 地图 + 判定输出（alex→slim / steve→classic）
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
OUT = os.path.join(HERE, "out423")
FIX = os.path.join(HERE, "fixtures")


def is_bg(p):
    return abs(p[0] - 25) <= 4 and abs(p[1] - 25) <= 4 and abs(p[2] - 25) <= 4


def measure_arms(img):
    """在复刻渲染图上按 IMG_0668 同款行扫描法量臂：返回 (行y, 细条宽列表, 缝宽列表)。"""
    W, H = img.size
    # 躯干中部行 = 模型高 40% 处
    ys = [int(H * 0.42), int(H * 0.46)]
    spans = []
    for y in ys:
        row = [img.getpixel((x, y))[:3] for x in range(W)]
        segs = []
        cur = None
        for i, p in enumerate(row):
            bgp = is_bg(p)
            if cur is None:
                cur = [bgp, i, i]
            elif bgp == cur[0]:
                cur[2] = i
            else:
                segs.append(cur)
                cur = [bgp, i, i]
        segs.append(cur)
        fg = [(s[1], s[2], s[2] - s[1] + 1) for s in segs if not s[0] and s[2] - s[1] > 2]
        gaps = [(s[1], s[2], s[2] - s[1] + 1) for s in segs if s[0] and s[2] - s[1] > 2
                and s[1] > min(x[1] for x in fg or [(0, 0, 0)])
                and s[2] < max(x[2] for x in fg or [(0, 0, W)])]
        spans.append((y, fg, gaps))
    return spans


def probe_zone_alpha(skin):
    """内容级模型判定探针（与 Task423 ObjC 同款）：经典展开带专属列 alpha。
    右臂 x54..55 y20..32（slim 展开带恒废弃透明 / 经典恒有内容）
    左臂 x46..47 y52..64（同理）。返回 (r_opaque, l_opaque, slim?)。"""
    W, H = skin.size
    px = skin.convert("RGBA").load()
    s = W / 64.0
    legacy = H < W
    if legacy:
        return -1, -1, False, True   # 64×32 旧版恒 classic（探针无意义）

    def zone_opaque(x0, y0, w, h):
        n = 0
        for y in range(int(y0 * s), min(int((y0 + h) * s), H)):
            for x in range(int(x0 * s), min(int((x0 + w) * s), W)):
                if px[x, y][3] >= 26:
                    n += 1
        return n

    r = zone_opaque(54, 20, 2, 12)
    l = zone_opaque(46, 52, 2, 12)
    slim = (r == 0) and (l == 0)
    return r, l, slim, legacy


def render_cell(skin, slim, out_name):
    """IMG_0668 同视角 = 背面（设备截图无脸可见，yaw≈31°@背 = front-yaw≈π−0.60）。"""
    w, h = skin.size
    faces = rep.build_model(slim, w, h)
    out_path = os.path.join(OUT, out_name)
    rep.render(skin, faces, yaw=math.pi - 0.60, pitch=-0.18,
               out_path=out_path, overlay_veil_opaque_only=True)
    return Image.open(out_path).convert("RGB")


def label_cell(d, text, xy=(8, 6)):
    d.text(xy, text, fill=(240, 240, 240))


def main():
    os.makedirs(OUT, exist_ok=True)
    alex = Image.open(os.path.join(FIX, "task423_alex_minotar.png")).convert("RGBA")
    steve_fix = os.path.join(FIX, "task423_steve_minotar.png")
    # crafatar 未知 UUID = alex 内容；minotar 未知用户名 = 64x32 Steve
    steve = (Image.open(steve_fix).convert("RGBA") if os.path.exists(steve_fix)
             else Image.open(os.path.join(FIX, "task423_minotar_unknown_name.png")).convert("RGBA"))

    # ── E2 探针表（先行：判定正确性）──
    probe_lines = []
    for name, sk in (("minotar-Alex(64x64)", alex), ("minotar-Steve(64x32)", steve)):
        r, l, slim, legacy = probe_zone_alpha(sk)
        probe_lines.append("%s: R(54-55,20-32)opaque=%d L(46-47,52-64)opaque=%d -> %s" % (
            name, r, l, "legacy-64x32-classic" if legacy else ("SLIM" if slim else "CLASSIC")))
    print("\n".join(probe_lines))

    # ── E1 渲染对比 ──
    cell = 560
    cells = []
    m1 = render_cell(alex, slim=False, out_name="task423_e1a_alex_bug_classic.png")     # HEAD 现症：经典 UV 读 slim 内容
    m2 = render_cell(alex, slim=True, out_name="task423_e1b_alex_fix_slim.png")         # Task423：内容判定 → slim UV
    m3 = render_cell(steve, slim=False, out_name="task423_e1c_steve_regression.png")    # 回归对照：经典皮经典表不变
    imgs = [m1, m2, m3]
    tags = ["E1-a BUG: alex@classicUV (HEAD现症)",
            "E1-b FIX: alex@slimUV (Task423判定)",
            "E1-c STEVE@classicUV (回归对照)"]
    for im, tag in zip(imgs, tags):
        d = ImageDraw.Draw(im)
        label_cell(d, tag)
        cells.append(im)

    # ── 探针表面板（560×780 与渲染格同幅）──
    panel = Image.new("RGB", (cell, 780), BG)
    d = ImageDraw.Draw(panel)
    for i, ln in enumerate(probe_lines):
        d.text((10, 40 + i * 22), ln, fill=(230, 230, 230))
    d.text((10, 8), "E2 model probe (Task423 content detection)", fill=(240, 240, 240))
    # 毒源取证摘要
    src = [
        "poison chain: 3rd-party profileId -> crafatar/skins/<uuid>",
        "  unknown uuid -> default ALEX 64x64 (fixture)",
        "  RArm-back(52,20,4x12) avg alpha=127 (half-empty)",
        "  -> cache only (no avatar/skinfull write)",
        "  -> mtime arbitration beats real skinfull -> locked",
        "fix: probe-based slim detect + provenance sidecar",
        "     (fallback cache never outranks valid skinfull)",
    ]
    for i, ln in enumerate(src):
        d.text((10, 120 + i * 20), ln, fill=(180, 200, 180))
    panel_path = os.path.join(OUT, "task423_e2_probe_forensics.png")
    panel.save(panel_path)

    titles = ["E1-a BUG alex@classic", "E1-b FIX alex@slim", "E1-c STEVE classic", "E2+E4 forensics"]
    paths = ["task423_e1a_alex_bug_classic.png", "task423_e1b_alex_fix_slim.png",
             "task423_e1c_steve_regression.png", "task423_e2_probe_forensics.png"]
    grid = rep.compose_grid([(os.path.join(OUT, p), t) for p, t in zip(paths, titles)],
                            os.path.join(OUT, "task423_evidence_grid.png"),
                            "Task423 slim content-detect + cache provenance (IMG_0668)", cell=cell)

    # 量化表输出（IMG_0668 实测对照）
    print("\n[IMG_0668 device measured] right sliver 46px(~2.3col) left 30px(~1.5col), gaps 24~30px")
    for name, im in (("BUG alex@classic", m1), ("FIX alex@slim", m2), ("STEVE@classic", m3)):
        sp = measure_arms(im)
        for (y, fg, gaps) in sp:
            print("  %-16s y=%d fg=%s gaps=%s" % (name, y,
                  [w for _, _, w in fg], [w for _, _, w in gaps]))
    print("\nout423/task423_evidence_grid.png saved")
    return 0


if __name__ == "__main__":
    sys.exit(main())
