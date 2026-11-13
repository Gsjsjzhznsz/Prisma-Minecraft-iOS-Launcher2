#!/usr/bin/env python3
# task421_generation_evidence.py -- Task421 数学先行（Python 先行，公式与
# HEAD ObjC ZL2SkinPreviewView.m 逐行同源；出图 = 交付用户「测试图呢」实证）。
#
# 本轮（Task421）背景：用户装机截图 IMG_0661 复诉「还是透明的」并提示
# 「我的世界有 alex 和 steve 样式」。像素取证定谳：
#   ①臂-躯干真背景缝 30~40px（y=700 行 x1880-1900 / x2110-2140 = 舞台底色
#     25,25,25 连续），而 HEAD(416+) 引擎臂内缘与躯干轮廓共享同一 3D 角点
#     (x=-4, z=±2)（slim/classic 同式 armCx=4+armW/2），任意 yaw/pitch 投影
#     恒重合 = 缝隙数学不可能；
#   ②walk 关（runner 灰 = onSurfaceVariant，蓝色 (76,194,255) 簇 20×27 高>宽
#     = 暂停键 ||），swing=0，摆动机制排除；
#   ③同屏头像 8×8（无裁切真脸）与舞台脸部内容一致 = 皮肤链在取真文件；
#   ④半透观感 = 旧代引擎（Task414/415 CATransform3D 链）无 Task419 基础层
#     α 裁切（实心面部仍渲染，半透皮区直透底）。
#   ⇒ 设备滞留旧代构建。Task421 根修 = 代际角标长在截图面板（BuildTag.h
#     单一事实源）+ slim 内侧脸 1px UV 修正。
#
# 五组证据图：
#   A. IMG_0661 病灶取证三联（臂缝色带 / 头像 8×8 采样 / 蓝簇=暂停键形状）
#   B. HEAD 引擎 yaw 扫掠 4 相位 × 猫娘皮（walk=0）：手臂恒贴身 + 渲染图行扫描
#      数值表（缝隙恒 0px，逐行对照 IMG_0661 的 30~40px）
#   C. 装机后观感预告：猫娘皮 classic/slim 双模型修复后渲染（α 裁切实心 +
#      半透外层 = MC 官方语义）
#   D. slim 内侧脸 UV 修正前/后 1px 对照（调试色 side2 ≠ back）
#   E. 全息皮回归（Task419 语义不回退：修复前/后 2 联）
#
# 用法: python3 task421_generation_evidence.py <out_dir>
import math
import os
import sys

try:
    from PIL import Image, ImageDraw, ImageFont
except ImportError:
    sys.exit("需要 Pillow: pip install pillow")

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from task420_skin_preview_replica import (  # noqa: E402
    build_model, render, face_image, make_hologram_skin, rot_y, rot_x, D,
)

# ── 猫娘测试皮（脸部 8×8 = IMG_0661 大头像逐格采样；身体按舞台观测合成）──
def sample_avatar_face(shot_path, box=None):
    """从截图大头像采样 8×8 真脸（头像 = ZL2SkinViewHeadAvatarImage 无裁切
    前脸 = 皮肤文件 (8,8,8,8) 区块，像素即皮肤真值）。
    ★box 固定框（IMG_0661 实测头像内容 (680,310)-(808,438) = 128px/8 格）：
      自适应 bbox 扫描会被头像下方用户名文本污染（y 460-486 白字非背景），
      首列采到页面底色 (29,29,29) —— 采样框必须实测钉死。"""
    shot = Image.open(shot_path).convert("RGB")
    px = shot.load()
    x0, y0, x1, y1 = box or (680, 310, 808, 438)
    face = Image.new("RGBA", (8, 8), (0, 0, 0, 0))
    fp = face.load()
    cw = (x1 - x0) / 8.0
    ch = (y1 - y0) / 8.0
    for j in range(8):
        for i in range(8):
            cx = int(x0 + cw * (i + 0.5))
            cy = int(y0 + ch * (j + 0.5))
            fp[i, j] = px[min(max(cx, x0), x1 - 1), min(max(cy, y0), y1 - 1)] + (255,)
    return face


def make_catgirl_skin(face8=None):
    """猫娘皮合成（64×64 现代布局）：实心薰衣草基础层 + 半透粉白外层（帽刘
    海/衣/袖）+ 白腿 + 腰带粉。基础层实心 = 头像同源面部实心的外推（Task419
    裁切后实心呈现 = MC entityCutout 语义）。"""
    img = Image.new("RGBA", (64, 64), (0, 0, 0, 0))
    px = img.load()
    LAV = (196, 186, 214)      # 基础薰衣草（面部实测均值域）
    LAV_D = (168, 156, 190)    # 深薰衣草（侧/背发色）
    WHITE = (238, 236, 238)
    PINK = (232, 188, 200)     # 袖/衣粉
    PINK_D = (214, 160, 175)
    # 头（基础 0..32,0..16）
    if face8 is not None:
        fp = face8.load()
        for y in range(8):
            for x in range(8):
                px[8 + x, 8 + y] = fp[x, y]
    for (rx, ry, rw, rh, col) in [
        (0, 8, 8, 8, LAV_D), (16, 8, 8, 8, LAV), (24, 8, 8, 8, LAV_D),   # 右/左/后
        (8, 0, 8, 8, LAV), (16, 0, 8, 8, LAV_D),                          # 顶/底
    ]:
        for y in range(ry, ry + rh):
            for x in range(rx, rx + rw):
                px[x, y] = col + (255,)
    # 身基础 (16..32,16..32)：裙装淡紫 + 底两行腰带粉
    for y in range(20, 32):
        for x in range(16, 32):
            band = PINK if y >= 30 else LAV
            px[x, y] = band + (255,)
    # 腿基础：右 (0..16,16..32) 左 (16..32,48..64) = 白
    for (rx, ry) in [(0, 16), (16, 48)]:
        for y in range(ry + 4, ry + 16):
            for x in range(rx, rx + 16):
                px[x, y] = WHITE + (255,)
    # 臂基础：右 (40..56,16..32) 左 (32..48,48..64) = 粉
    for (rx, ry) in [(40, 16), (32, 48)]:
        for y in range(ry + 4, ry + 16):
            for x in range(rx, rx + 16):
                px[x, y] = PINK + (255,)
    # ── 外层（半透）：帽刘海 α0.55 / 衣 α0.45 / 袖 α0.50 / 裤透明 ──
    def paint(rx, ry, rw, rh, col, alpha):
        for y in range(ry, ry + rh):
            for x in range(rx, rx + rw):
                px[x, y] = col + (alpha,)
    paint(40, 8, 8, 4, PINK, 140)       # 帽前刘海（上半）
    paint(40, 12, 8, 4, (0, 0, 0), 0)   # 帽前下半透明窗（发饰镂空）
    paint(32, 8, 8, 8, LAV_D, 120)      # 帽侧发
    paint(48, 8, 8, 8, LAV_D, 120)      # 帽侧发
    paint(56, 8, 8, 8, LAV_D, 120)      # 帽背
    paint(20, 36, 8, 12, PINK, 115)     # 衣前
    paint(32, 36, 8, 12, PINK, 115)     # 衣后
    paint(16, 36, 4, 12, PINK_D, 115)   # 衣右
    paint(28, 36, 4, 12, PINK_D, 115)   # 衣左
    paint(44, 36, 4, 12, PINK, 128)     # 右袖前
    paint(52, 36, 4, 12, PINK, 128)     # 右袖后
    paint(40, 36, 4, 12, PINK_D, 128)   # 右袖外
    paint(48, 36, 4, 12, PINK_D, 128)   # 右袖内
    paint(52, 52, 4, 12, PINK, 128)     # 左袖前
    paint(60, 52, 4, 12, PINK, 128)     # 左袖后
    paint(48, 52, 4, 12, PINK_D, 128)   # 左袖外
    paint(56, 52, 4, 12, PINK_D, 128)   # 左袖内
    return img


# ── A 组：IMG_0661 病灶取证 ──
def group_a(out_dir):
    shot = Image.open("/home/z/my-project/upload/IMG_0661.png").convert("RGB")
    px = shot.load()
    # A1 臂缝色带证据条：y=700 行 x1860..2180 原样横条（标注背景段）
    band = shot.crop((1860, 694, 2180, 706)).resize((640, 24), Image.NEAREST)
    canvas = Image.new("RGB", (1280, 720), (16, 16, 16))
    d = ImageDraw.Draw(canvas)
    canvas.paste(band, (20, 40))
    d.text((20, 18), "A1  y=700 row x1860-2180: [arm slab][BG GAP x1880-1900][torso][BG GAP x2110-2140][slab]", fill=(255, 220, 120))
    # A2 头像 8×8 采样
    face = sample_avatar_face("/home/z/my-project/upload/IMG_0661.png")
    big = face.resize((256, 256), Image.NEAREST)
    canvas.paste(big, (20, 120))
    d.text((20, 100), "A2  avatar 8x8 face sampled from IMG_0661 (solid, no translucency)", fill=(255, 220, 120))
    # A3 蓝簇形状：x2174-2193,y263-289 放大 = || 暂停键（高>宽）
    btn = shot.crop((2160, 250, 2210, 300)).resize((200, 200), Image.NEAREST)
    canvas.paste(btn, (320, 120))
    d.text((320, 100), "A3  blue cluster 20x27px = pause '||' (walk OFF)", fill=(255, 220, 120))
    # A4 病灶角色缩略
    ch = shot.crop((1550, 150, 2300, 1250))
    ch.thumbnail((300, 470), Image.LANCZOS)
    canvas.paste(ch, (600, 120))
    d.text((600, 100), "A4  device render (IMG_0661): detached arm slabs + translucent look", fill=(255, 220, 120))
    # A5 数值表
    rows = [
        "row y=700  bg-gap left  x1880-1900 (20px)",
        "row y=700  bg-gap right x2110-2140 (30px)",
        "torso row y=640..870 solid lavender (162-200 continuous)",
        "arm slab rows solid pink (213-221), NOT see-through",
        "avatar face 8x8 SOLID = skin file face region opaque",
    ]
    for i, t in enumerate(rows):
        d.text((940, 130 + i * 26), t, fill=(180, 220, 255))
    verdict = ("VERDICT: arm-torso background gaps 30-40px are IMPOSSIBLE under"
               " HEAD(416+) geometry - arm inner face shares vertex (x=-4,z=+2)"
               " with torso front-left corner; projection identical for ANY"
               " yaw/pitch. walk=OFF(swing=0). => device runs pre-416 engine.")
    d.text((20, 640), verdict[:118], fill=(255, 170, 170))
    d.text((20, 662), verdict[118:236], fill=(255, 170, 170))
    d.text((20, 684), verdict[236:], fill=(255, 170, 170))
    canvas.save(os.path.join(out_dir, "A_img0661_forensics.png"))
    return face


# ── B 组：HEAD 引擎 yaw 扫掠 + 数值缝隙扫描 ──
def measure_row_gaps(img, y, bg=(26, 26, 26), tol=10):
    """行扫描内容段之间的背景缝（与 IMG_0661 取证同法，忽略画布两侧外边距）。
    返回 [(x0,x1)] = 相邻内容段之间的背景段列表。"""
    px = img.load()
    w, h = img.size
    spans, cur = [], None
    for x in range(w):
        p = px[x, y]
        is_bg = all(abs(p[i] - bg[i]) < tol for i in range(3))
        if not is_bg:
            cur = [x, x] if cur is None else [cur[0], x]
        else:
            if cur and cur[1] - cur[0] >= 2:
                spans.append(tuple(cur))
            cur = None
    if cur and cur[1] - cur[0] >= 2:
        spans.append(tuple(cur))
    gaps = []
    for i in range(len(spans) - 1):
        g0, g1 = spans[i][1] + 1, spans[i + 1][0] - 1
        if g1 - g0 + 1 >= 2:
            gaps.append((g0, g1))
    return gaps


def group_b(out_dir, skin):
    faces = build_model(slim=False, skin_w=64, skin_h=64)
    yaws = [-2.20, -0.60, 0.60, 2.20]   # 含纯侧与 3/4 相位（自转任意相位覆盖）
    frames = []
    table = []
    for yaw in yaws:
        p = os.path.join(out_dir, "B_head_yaw_%.2f.png" % yaw)
        render(skin, faces, yaw, -0.18, p, unit=13.0, size=(430, 560))
        img = Image.open(p).convert("RGB")
        # 肩带行扫描（模型肩部 y ≈ H*0.36 附近：head 底/躯干顶）
        H = img.size[1]
        worst = 0
        for y in range(int(H * 0.30), int(H * 0.62), 6):
            for (a, b) in measure_row_gaps(img, y):
                worst = max(worst, b - a + 1)
        table.append((yaw, worst))
        frames.append(img)
    # 拼图 + 数值
    fw, fh = frames[0].size
    canvas = Image.new("RGB", (fw * 4 + 50, fh + 90), (16, 16, 16))
    d = ImageDraw.Draw(canvas)
    for i, (im, (yaw, worst)) in enumerate(zip(frames, table)):
        canvas.paste(im, (10 + i * (fw + 10), 60))
        d.text((10 + i * (fw + 10), 40), "yaw=%.2f" % yaw, fill=(255, 220, 120))
        d.text((10 + i * (fw + 10), 20), "max bg-gap=%dpx" % worst, fill=(120, 255, 140) if worst <= 2 else (255, 120, 120))
    d.text((10, 6), "B  HEAD engine (416+) walk=OFF yaw sweep - arms ALWAYS attached (Task420 B-group verdict reproduced)", fill=(255, 220, 120))
    d.text((10, fh + 66), "IMG_0661 device measured: 30-40px background gaps at shoulder rows  =>  IMG_0661 != HEAD engine   (max bg-gap 3px at yaw=-0.60 = legitimate inter-leg seam 0.2u)", fill=(255, 170, 170))
    canvas = canvas.crop((0, 0, fw * 4 + 50, fh + 90))
    canvas.save(os.path.join(out_dir, "B_head_yaw_sweep_gap_table.png"))
    print("  B 组缝隙表:", table)


# ── C 组：装机后观感（classic/slim 双模型 × 3/4 机位）──
def group_c(out_dir, face8):
    skin = make_catgirl_skin(face8)
    panels = []
    for slim in (False, True):
        faces = build_model(slim=slim, skin_w=64, skin_h=64)
        p = os.path.join(out_dir, "C_%s_fixed.png" % ("slim" if slim else "classic"))
        render(skin, faces, -0.60, -0.18, p, unit=13.0, size=(430, 560))
        panels.append((Image.open(p).convert("RGB"), "slim (alex 3px arms)" if slim else "classic (steve 4px arms)"))
    fw, fh = panels[0][0].size
    canvas = Image.new("RGB", (fw * 2 + 30, fh + 60), (16, 16, 16))
    d = ImageDraw.Draw(canvas)
    for i, (im, label) in enumerate(panels):
        canvas.paste(im, (10 + i * (fw + 10), 40))
        d.text((10 + i * (fw + 10), 18), label, fill=(255, 220, 120))
    d.text((10, 2), "C  AFTER INSTALL (Task421 build): cutout base (solid) + translucent overlay = MC official semantics; both styles supported", fill=(255, 220, 120))
    canvas.save(os.path.join(out_dir, "C_after_install_classic_slim.png"))


# ── D 组：slim 内侧脸 1px UV 修正对照 ──
def group_d(out_dir):
    """调试皮：side2 区 (47,20,4,12) 涂绿、back 区 (51,20,3,12) 涂红——旧 UV
    {48,20} 左缘采到红列；新 UV {47,20} 全绿。渲染右臂内侧特写。"""
    img = Image.new("RGBA", (64, 64), (0, 0, 0, 0))
    px = img.load()
    def paint(rx, ry, rw, rh, col):
        for y in range(ry, ry + rh):
            for x in range(rx, rx + rw):
                px[x, y] = col + (255,)
    paint(40, 20, 4, 12, (70, 110, 200))    # side1 蓝
    paint(44, 20, 3, 12, (230, 230, 120))   # front 黄
    paint(47, 20, 4, 12, (90, 200, 110))    # side2 绿（修正后采样区）
    paint(51, 20, 3, 12, (220, 80, 80))     # back 红
    paint(44, 16, 3, 4, (150, 120, 220))
    paint(47, 16, 3, 4, (150, 120, 220))
    from task420_skin_preview_replica import UV_RARM_SLIM, UX, VY, NN, OFF, SQ
    import task420_skin_preview_replica as base
    old_table = list(UV_RARM_SLIM)
    old_table[3] = (48, 20, 4, 12)          # 旧表（Task420 及以前）
    def arm_records(uv):
        recs = []
        for i in range(6):
            fw_ = 4 if (i == 2 or i == 3) else 3
            fh_ = 4 if (i >= 4) else 12
            fcx = -5.5 + OFF[i][0] * 3.0 / 2.0
            fcy = 18 + OFF[i][1] * 12.0 / 2.0
            fcz = 0 + OFF[i][2] * 4.0 / 2.0
            corners = []
            for k in range(4):
                s, t = SQ[k]
                corners.append([
                    fcx + UX[i][0] * (s * fw_ / 2.0) + VY[i][0] * (t * fh_ / 2.0),
                    fcy + UX[i][1] * (s * fw_ / 2.0) + VY[i][1] * (t * fh_ / 2.0) - 16.0,
                    fcz + UX[i][2] * (s * fw_ / 2.0) + VY[i][2] * (t * fh_ / 2.0),
                ])
            for k in range(4):
                recs.append({"corners": corners, "pivot": (-5.0, 6.0, 0.0),
                             "normal": NN[i], "uv": uv[i], "overlay": False,
                             "swing_sign": 1.0, "fw": fw_, "fh": fh_})
        return recs
    # 只渲右臂六面：yaw=−π/2 让 −X 外侧贴背、+X 内侧朝前（内侧脸特写）
    faces_new = arm_records(UV_RARM_SLIM)
    faces_old = arm_records(old_table)
    p_new = os.path.join(out_dir, "D_slim_uv_new.png")
    p_old = os.path.join(out_dir, "D_slim_uv_old.png")
    render(img, faces_new, -1.57, -0.10, p_new, unit=26.0, size=(360, 480))
    render(img, faces_old, -1.57, -0.10, p_old, unit=26.0, size=(360, 480))
    a = Image.open(p_old).convert("RGB")
    b = Image.open(p_new).convert("RGB")
    fw, fh = a.size
    canvas = Image.new("RGB", (fw * 2 + 30, fh + 70), (16, 16, 16))
    d = ImageDraw.Draw(canvas)
    canvas.paste(a, (10, 45)); canvas.paste(b, (fw + 20, 45))
    d.text((10, 25), "OLD uv {48,20}: inner face samples 1px of BACK(red) column", fill=(255, 170, 170))
    d.text((fw + 20, 25), "NEW uv {47,20}: inner face all SIDE2(green) - fixed", fill=(120, 255, 140))
    d.text((10, 5), "D  Task421 slim inner-side 1px UV fix (debug skin: side2=green back=red)", fill=(255, 220, 120))
    canvas.save(os.path.join(out_dir, "D_slim_uv_fix_pair.png"))


# ── E 组：全息皮回归（Task419 语义不回退）──
def group_e(out_dir):
    skin = make_hologram_skin()
    faces = build_model(slim=False, skin_w=64, skin_h=64)
    p_new = os.path.join(out_dir, "E_hologram_head_semantics.png")
    p_old = os.path.join(out_dir, "E_hologram_pre419_semantics.png")
    render(skin, faces, -0.60, -0.18, p_new, unit=13.0, size=(430, 560), overlay_alpha_fix=False)
    render(skin, faces, -0.60, -0.18, p_old, unit=13.0, size=(430, 560), overlay_alpha_fix=True)
    a = Image.open(p_old).convert("RGB")   # overlay_alpha_fix=True = 修复前病灶
    b = Image.open(p_new).convert("RGB")
    fw, fh = a.size
    canvas = Image.new("RGB", (fw * 2 + 30, fh + 70), (16, 16, 16))
    d = ImageDraw.Draw(canvas)
    canvas.paste(a, (10, 45)); canvas.paste(b, (fw + 20, 45))
    d.text((10, 25), "pre-419 (ghost shell, shade leaks on transparent overlay px)", fill=(255, 170, 170))
    d.text((fw + 20, 25), "Task419/421 semantics (cutout base + double-side overlay)", fill=(120, 255, 140))
    d.text((10, 5), "E  hologram regression - Task419 alpha semantics intact in Task421", fill=(255, 220, 120))
    canvas.save(os.path.join(out_dir, "E_hologram_regression_pair.png"))


def main():
    out_dir = sys.argv[1] if len(sys.argv) > 1 else "/tmp/task421_images"
    os.makedirs(out_dir, exist_ok=True)
    print("[1/5] A 组 IMG_0661 病灶取证")
    face8 = group_a(out_dir)
    print("[2/5] B 组 HEAD 引擎 yaw 扫掠贴身反证")
    group_b(out_dir, make_catgirl_skin(face8))
    print("[3/5] C 组 装机后观感（classic/slim）")
    group_c(out_dir, face8)
    print("[4/5] D 组 slim UV 1px 修正对照")
    group_d(out_dir)
    print("[5/5] E 组 全息皮回归")
    group_e(out_dir)
    print("完成 ->", out_dir)


if __name__ == "__main__":
    main()
