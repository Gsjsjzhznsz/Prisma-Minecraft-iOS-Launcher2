#!/usr/bin/env python3
# task424_light_pose_replica.py -- Task424 取证复刻（Python 先行）：
# 用户 IMG_0669/0670（Task423 装机）三复诉：
#   ①「还是有地方透明的，从一些地方看出来穿透了」→ 病灶 = 外层 DoubleSide
#     背面用未翻转法线算明暗 → dot≤0 → shade 0.44 → 罩 opacity 0.476·0.85
#     黑罩压在背面层上，透过半透外层前面露出 = 黑色弧带/内部黑洞（IMG_0669
#     头右侧 20×43px 等背景色洞实测定谳）。THREE.js DoubleSide 着色对背面
#     自动翻法线（gl_FrontFacing）= 背面按正面受光 → 修复 = 背面 nz<0 时
#     法线取反对 dot。
#   ②「光影系统：圆盘调节光影位置 + 亮度拖条」→ 光向方位角/仰角参数化
#     （默认 = AME416 光向 (−0.45,0.62,0.65) 的 az=−0.606rad/el=0.668rad）+
#     亮度系数 b：罩力度 ×clamp(2−b,0.25,1.8)。
#   ③「动作系统：蹲下/站立/跑步 + 自定义关节拖拽」→ 每部件 rotX/rotZ/rotY
#     关节角（枢轴不变 = ame416 pivot-swing 公式复用）；跑步 = 既有正弦摆
#     AME416_WALK_AMP·sin(phase)·sign；蹲下 = 躯干前倾+头后仰+臂前摆+腿前伸
#     +整体下沉；自定义 = 关节角直控。
# 公式与 HEAD ZL2SkinPreviewView.m / task420_skin_preview_replica.py 逐行同源。
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
spec2.loader.exec_module(rep422)   # 复用 make_user_hologram（淡彩基础+彩虹外层）

from PIL import Image, ImageDraw, ImageFont

OUT = os.path.join(HERE, "task424_evidence")
os.makedirs(OUT, exist_ok=True)

BG = (41, 41, 41)          # IMG_0669 舞台实测底（用户选深灰色板 0.16）
D = 900.0                  # AME416_CAMERA_D

LIGHT_X, LIGHT_Y, LIGHT_Z = -0.45, 0.62, 0.65   # AME416 基线光向
DEF_AZ = math.atan2(LIGHT_X, LIGHT_Z)           # −0.606 rad
DEF_EL = math.asin(LIGHT_Y / 1.0047)            # ≈0.668 rad

PART_NAMES = ["head", "body", "rarm", "larm", "rleg", "lleg"]


def light_vec(az, el):
    return (math.cos(el) * math.sin(az), math.sin(el), math.cos(el) * math.cos(az))


def rot_z(x, y, th):
    c, s = math.cos(th), math.sin(th)
    return x * c - y * s, x * s + y * c


def render424(skin, slim, yaw, pitch, out_path, unit=10.0, size=(560, 780),
              az=DEF_AZ, el=DEF_EL, brightness=1.15, two_sided=True,
              joints=None, phase=0.0, pose="stand", bg=BG, veil_cap=0.60):
    """Task424 渲染复刻：关节角 + 光向 az/el + 亮度 + 双面受光。
    亮度 b：floor = clamp(0.44+(b-1.0)*0.55, 0.12, 0.80)（b 越大背光面越亮），
    veilGain = clamp(2.0-b, 0.25, 1.8)，罩上限 AME424_VEIL_CAP=0.60
    （Task418 旧 0.85 = 全模型 murk 主源，设备实测侧面 ×0.524 → 新 ×0.756）；
    默认 b=1.15。joints = {part_name: (rotX, rotZ, rotY, yOff)} 覆盖；
    pose 预置见 pose_angles。"""
    faces = rep.build_model(slim, skin.size[0], skin.size[1])
    ang = pose_angles(pose, phase, joints)
    L = light_vec(az, el)
    floor = max(0.12, min(0.80, 0.44 + (brightness - 1.0) * 0.55))
    veil_gain = max(0.25, min(1.8, 2.0 - brightness))
    W, H = size
    canvas = Image.new("RGBA", (W, H), bg + (255,))
    cen = (W / 2.0, H / 2.0)
    recs = []
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
        sx = [0.0] * 4
        sy = [0.0] * 4
        zsum = 0.0
        for k in range(4):
            vx, vy, vz = f["corners"][k]
            vx += 0.0
            vy = vy + yoff   # 部件下沉（pivot 同步平移 = 纯位移）
            pv_dy = f["pivot"][1] + yoff
            if rx:
                dy = vy - pv_dy
                dz = vz - f["pivot"][2]
                vy = pv_dy + dy * math.cos(rx) - dz * math.sin(rx)
                vz = f["pivot"][2] + dy * math.sin(rx) + dz * math.cos(rx)
            if rz:
                dx = vx - f["pivot"][0]
                dy2 = vy - pv_dy
                vx = f["pivot"][0] + dx * math.cos(rz) - dy2 * math.sin(rz)
                vy = pv_dy + dx * math.sin(rz) + dy2 * math.cos(rz)
            if ry:
                vx, vz = rep.rot_y(vx - f["pivot"][0], vz - f["pivot"][2], ry)
                vx += f["pivot"][0]
                vz += f["pivot"][2]
            vx, vz = rep.rot_y(vx, vz, yaw)
            vy, vz = rep.rot_x(vy, vz, pitch)
            vx *= unit; vy *= unit; vz *= unit
            pf = D / (D - vz)
            sx[k] = vx * pf
            sy[k] = -vy * pf
            zsum += vz
        # ★Task424-a 双面受光：外层背面法线翻转（THREE.js gl_FrontFacing 同源）
        snx, sny, snz = nx, ny, nz
        if backface and two_sided and f["overlay"]:
            snx, sny, snz = -nx, -ny, -nz
        recs.append((zsum / 4.0, f, sx, sy, (snx, sny, snz), backface))
    recs.sort(key=lambda r: r[0])
    for zpos, f, sx, sy, (nx, ny, nz), backface in recs:
        img = rep.face_image(skin, f["uv"], do_cutout=not f["overlay"])
        if img is None:
            continue
        iw, ih = img.size
        xs = [cen[0] + v for v in sx]
        ys = [cen[1] + v for v in sy]
        quad_out = list(zip(xs, ys))
        x0, x1 = min(xs), max(xs)
        y0, y1 = min(ys), max(ys)
        if x1 - x0 < 1 or y1 - y0 < 1:
            continue
        rw_, rh_ = max(1, int(round(x1 - x0))), max(1, int(round(y1 - y0)))
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
        ln = math.sqrt(nx * nx + ny * ny + nz * nz) or 1.0
        dot = (nx * L[0] + ny * L[1] + nz * L[2]) / ln
        shade = floor + (1.0 - floor) * max(0.0, dot)
        if shade > 1.0:
            shade = 1.0
        dark = (1.0 - shade) * veil_cap * veil_gain
        if dark > 1.0:
            dark = 1.0
        if dark > 0.001:
            alpha_ch = warped.split()[3]
            if f["overlay"]:
                alpha_ch = alpha_ch.point(
                    lambda v: 255 if v >= 180 else 0)   # AME422 罩分级
            mask = alpha_ch.point(lambda v: int(v * dark))
            black = Image.new("RGBA", warped.size, (0, 0, 0, 255))
            warped = Image.composite(black, warped, mask)
        canvas.alpha_composite(warped, (int(round(x0)), int(round(y0))))
    canvas.convert("RGB").save(out_path)
    return out_path


def pose_angles(pose, phase=0.0, joints=None):
    """姿态→每部件 (rotX, rotZ, rotY, yOff)。正 rotX = 肢端向后（ame416 同向）。"""
    ang = {n: (0.0, 0.0, 0.0, 0.0) for n in PART_NAMES}
    if pose == "run":
        sw = 0.50 * math.sin(phase)   # AME416_WALK_AMP 口径
        ang["rarm"] = (sw * 1.0, 0.0, 0.0, 0.0)      # swing_sign +1
        ang["larm"] = (sw * -1.0, 0.0, 0.0, 0.0)     # −1
        ang["rleg"] = (sw * -1.0, 0.0, 0.0, 0.0)     # −1
        ang["lleg"] = (sw * 1.0, 0.0, 0.0, 0.0)      # +1
    elif pose == "sneak":
        sink = -2.2
        ang["head"] = (-0.42, 0.0, 0.0, sink)   # 头后仰补偿
        ang["body"] = (0.30, 0.0, 0.0, sink)    # 躯干前倾
        ang["rarm"] = (-0.15, 0.0, 0.0, sink)   # 臂微前
        ang["larm"] = (-0.15, 0.0, 0.0, sink)
        ang["rleg"] = (-0.35, 0.0, 0.0, sink)   # 腿前伸下蹲
        ang["lleg"] = (-0.35, 0.0, 0.0, sink)
    elif pose == "custom":
        ang["head"] = (0.0, 0.0, 0.5, 0.0)      # 头右转
        ang["rarm"] = (-0.9, -0.85, 0.0, 0.0)   # 右臂前抬+侧展
        ang["larm"] = (0.4, 0.7, 0.0, 0.0)      # 左臂后摆+侧展
        ang["rleg"] = (-0.3, 0.0, 0.0, 0.0)
        ang["lleg"] = (0.2, 0.0, 0.0, 0.0)
    if joints:
        for k, v in joints.items():
            ang[k] = v
    return ang


def label_cell(draw, text, xy):
    try:
        font = ImageFont.truetype(
            "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", 13)
    except Exception:
        font = ImageFont.load_default()
    draw.text(xy, text, fill=(230, 230, 230), font=font)


def group_a():
    """①穿透根修：Task423（floor0.44+背面不翻法线）vs Task424（双面受光+
    亮度默认 1.15）。IMG_0669 同族机位：yaw −0.60 / pitch +0.50（顶面在镜 =
    装机实拍俯视态）/ 跑步相位 0.9。"""
    skin = rep422.make_user_hologram()
    yaw, pitch, phase = -0.60, 0.50, 0.9
    p_before = render424(skin, True, yaw, pitch, os.path.join(OUT, "a1_before_task423.png"),
                         unit=13, two_sided=False, brightness=1.0, pose="run", phase=phase,
                         veil_cap=0.85)   # Task423 旧常量：floor0.44+cap0.85
    p_after = render424(skin, True, yaw, pitch, os.path.join(OUT, "a2_after_task424.png"),
                        unit=13, two_sided=True, brightness=1.15, pose="run", phase=phase)
    rep.compose_grid([(p_before, "Task423 BACK floor0.44+cap0.85+背面不翻"),
                      (p_after, "Task424 FIX 双面受光+b=1.15+cap0.60")],
                     os.path.join(OUT, "A_seethru_fix.png"),
                     "Task424-A two-sided lighting + brightness 1.15 + veil cap 0.60",
                     cell=560)
    p_max = render424(skin, True, yaw, pitch, os.path.join(OUT, "a3_bright_max.png"),
                      unit=13, two_sided=True, brightness=1.5, pose="run", phase=phase)
    rep.compose_grid([(p_before, "Task423 BACK floor0.44+cap0.85"),
                      (p_max, "Task424 亮度拖条最大 b=1.5（近 sv3d 平亮）")],
                     os.path.join(OUT, "A_brightness_range.png"),
                     "Task424-A brightness slider range", cell=560)
    # 定量：模型区（非背景）平均亮度 + murk 像素（亮度<85）占比
    import statistics
    for tag, p in (("before(Task423)", p_before), ("after(Task424)", p_after)):
        im = Image.open(p).convert("RGB")
        px = im.load()
        lums = []
        for y in range(im.height):
            for x in range(im.width):
                c = px[x, y]
                if not (abs(c[0] - 41) <= 3 and abs(c[1] - 41) <= 3 and abs(c[2] - 41) <= 3):
                    lums.append(0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2])
        murk = sum(1 for v in lums if v < 85)
        print(f"  A组 {tag}: 模型区均亮 {statistics.mean(lums):.1f} murk<85 {murk}/{len(lums)} = {100.0*murk/len(lums):.1f}%")
    print(f"  A组 -> {os.path.join(OUT, 'A_seethru_fix.png')}")


def group_b():
    """②光影系统：方位角×亮度扫掠矩阵 + 圆盘 UI 设计稿。"""
    skin = rep422.make_user_hologram()
    yaw, pitch = -0.60, 0.40
    az_list = [-150, -90, -30, 30, 90, 150]
    b_list = [0.5, 1.0, 1.5]
    rows = []
    for b in b_list:
        row_cells = []
        for azd in az_list:
            p = os.path.join(OUT, f"b_az{azd}_b{int(b*10)}.png")
            render424(skin, True, yaw, pitch, p, unit=9,
                      az=math.radians(azd), el=math.radians(25), brightness=b)
            im = Image.open(p)
            cell = Image.new("RGB", (im.width, im.height + 24), (18, 18, 18))
            cell.paste(im, (0, 24))
            d = ImageDraw.Draw(cell)
            label_cell(d, f"az={azd}deg b={b}", (4, 4))
            row_cells.append(cell)
        rows.append(row_cells)
    wmax = max(c.width for r in rows for c in r)
    hmax = max(c.height for r in rows for c in r)
    grid = Image.new("RGB", (wmax * len(az_list), hmax * len(b_list) + 30), (10, 10, 10))
    dd = ImageDraw.Draw(grid)
    label_cell(dd, "Task424-B light disc: azimuth x brightness sweep", (6, 8))
    for r_i, row in enumerate(rows):
        for c_i, cell in enumerate(row):
            grid.paste(cell, (c_i * wmax, 30 + r_i * hmax))
    grid.save(os.path.join(OUT, "B_light_matrix.png"))
    # 圆盘 UI 设计稿（映射同 ObjC：knob(dx,dy) → az=atan2(dx,−dy), el=f(r)）
    dial = Image.new("RGB", (340, 200), (30, 30, 30))
    d = ImageDraw.Draw(dial)
    cx, cy, R = 100, 100, 78
    d.ellipse((cx - R, cy - R, cx + R, cy + R), outline=(120, 120, 130), width=2)
    d.ellipse((cx - R * 2 // 3, cy - R * 2 // 3, cx + R * 2 // 3, cy + R * 2 // 3),
              outline=(80, 80, 90), width=1)
    az_d, el_d = math.radians(-35), math.radians(38)
    rr = R * (1.0 - (el_d - math.radians(5)) / math.radians(75))
    kx = cx + rr * math.sin(az_d)
    ky = cy - rr * math.cos(az_d)
    d.line((cx, cy, kx, ky), fill=(255, 200, 80), width=2)
    d.ellipse((kx - 7, ky - 7, kx + 7, ky + 7), fill=(255, 200, 80))
    label_cell(d, "light disc (az=-35 el=38)", (170, 60))
    # 亮度拖条
    d.rounded_rectangle((180, 120, 320, 136), radius=8, fill=(70, 70, 75))
    d.rounded_rectangle((180, 120, 288, 136), radius=8, fill=(80, 160, 255))
    d.ellipse((278, 114, 292, 142), fill=(240, 240, 245))
    label_cell(d, "brightness slider (1.2x)", (180, 150))
    dial.save(os.path.join(OUT, "B_disc_ui_mock.png"))
    print(f"  B组 -> {os.path.join(OUT, 'B_light_matrix.png')} + B_disc_ui_mock.png")


def group_c():
    """③动作系统：站立/蹲下/跑步/自定义 四联。"""
    skin = rep422.make_user_hologram()
    yaw, pitch = -0.60, 0.35
    poses = [("stand", 0.0, "站立 stand"), ("sneak", 0.0, "蹲下 sneak"),
             ("run", 1.2, "跑步 run"), ("custom", 0.0, "自定义 custom joints")]
    cells = []
    for pose, phase, tag in poses:
        p = os.path.join(OUT, f"c_{pose}.png")
        render424(skin, True, yaw, pitch, p, unit=11, pose=pose, phase=phase)
        im = Image.open(p)
        cell = Image.new("RGB", (im.width, im.height + 26), (18, 18, 18))
        cell.paste(im, (0, 26))
        d = ImageDraw.Draw(cell)
        label_cell(d, tag, (6, 4))
        cells.append(cell)
    rep.compose_grid([(os.path.join(OUT, f"c_{p}.png") , t) for p, _, t in poses],
                     os.path.join(OUT, "C_pose_system.png"),
                     "Task424-C pose system: stand/sneak/run/custom", cell=400)
    print(f"  C组 -> {os.path.join(OUT, 'C_pose_system.png')}")


if __name__ == "__main__":
    print("Task424 replica evidence ->", OUT)
    group_a()
    group_b()
    group_c()
    print("done")
