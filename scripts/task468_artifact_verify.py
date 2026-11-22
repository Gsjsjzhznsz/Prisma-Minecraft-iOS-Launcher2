#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Task468 四产物二进制验证（Task467 13/13 同族，对 dev run 构建判读）。
判例沿用：N+21（产物双层容器——ipa 内包内层 ipa / tipa 内包内层 tipa，按扩展名递归解包）
+ N+22（dSYM DWARF LC_UUID 与主二进制配对；Task466 无 UUID 记录系当轮 DWARF 精简形态）。
用法：python3 scripts/task468_artifact_verify.py <unpack_root>
  <unpack_root> 下应存在（CI artifact 下载解包后的形态）：
    x_com.prisma-devs.prisma-ios.ipa/com.prisma-devs.prisma-<ver>-ios.ipa
    x_com.prisma-devs.prisma-ios-trollstore.tipa/com.prisma-devs.prisma-<ver>-ios-trollstore.tipa
    x_AngelAuraAmethyst.dSYM/
"""
import glob
import hashlib
import os
import sys
import zipfile

ROOT = sys.argv[1] if len(sys.argv) > 1 else "/home/z/my-project/task468_dl"
WORK = os.path.join(ROOT, "inner")
os.makedirs(WORK, exist_ok=True)

fails, passed = [], 0
def check(name, ok, detail=''):
    global passed
    print(('PASS ' if ok else 'FAIL ') + name + (f' -- {detail}' if detail and not ok else ''))
    if ok:
        passed += 1
    else:
        fails.append(name)

def unpack_inner(outer_dir, suffix):
    zips = glob.glob(os.path.join(ROOT, outer_dir, f"*{suffix}"))
    if len(zips) != 1:
        return None
    out = os.path.join(WORK, outer_dir.replace("x_", ""))
    os.makedirs(out, exist_ok=True)
    with zipfile.ZipFile(zips[0]) as z:
        z.extractall(out)
    return out

def find_binary(app_dir):
    hits = glob.glob(os.path.join(app_dir, "Payload", "*.app", "*"))
    for h in hits:
        if os.path.isfile(h) and not h.endswith((".plist", ".strings", ".car", ".dylib")):
            with open(h, "rb") as f:
                if f.read(4) in (b"\xcf\xfa\xed\xfe", b"\xfe\xed\xfa\xcf", b"\xca\xfe\xba\xbe", b"\xbe\xba\xfe\xca"):
                    return h
    return None

def lc_uuid(path):
    """Mach-O LC_UUID 手解（Linux 沙箱无 dwarfdump；N+22 判例同义）。"""
    import struct as _s
    with open(path, "rb") as f:
        head = f.read(64)
    if len(head) < 32:
        return None
    magic = _s.unpack("<I", head[:4])[0]
    if magic == 0xFEEDFACF:
        fmt, base = "<", 32
    elif magic == 0xCFFAEDFE:
        fmt, base = ">", 32
    else:
        return None
    ncmds = _s.unpack(fmt + "I", head[16:20])[0]
    with open(path, "rb") as f:
        blob = f.read(base + 0x40000)
    off = base
    for _ in range(ncmds):
        if off + 8 > len(blob):
            break
        cmd, size = _s.unpack(fmt + "II", blob[off:off + 8])
        if cmd == 0x1B and size >= 24:   # LC_UUID
            raw = blob[off + 8:off + 24]
            h = raw.hex()
            return f"{h[0:8]}-{h[8:12]}-{h[12:16]}-{h[16:20]}-{h[20:32]}"
        if size == 0:
            break
        off += size
    return None

def utf16_le(s):
    return s.encode("utf-16-le")

def bin_has(path, needle_bytes):
    with open(path, "rb") as f:
        return needle_bytes in f.read()

ipa_app = unpack_inner("x_com.prisma-devs.prisma-ios.ipa", ".ipa")
tipa_app = unpack_inner("x_com.prisma-devs.prisma-ios-trollstore.tipa", ".tipa")
check('V1 内层 ipa/tipa 各恰一份且可解', ipa_app is not None and tipa_app is not None)
if not ipa_app:
    print("FAIL fatal: inner layers missing")
    sys.exit(1)

bin_ipa = find_binary(ipa_app)
bin_tipa = find_binary(tipa_app)
check('V2 主二进制定位（Mach-O 魔数）', bin_ipa is not None and bin_tipa is not None,
      f'{bin_ipa} / {bin_tipa}')
if not bin_ipa:
    sys.exit(1)

# ── Task468 新面：MobileGL 引擎性能旋钮层 ─────────────────────
check('V3 BuildTag Task468 · 2026-11-23 UTF-16LE 在场',
      bin_has(bin_ipa, utf16_le("Task468 · 2026-11-23")))
check('V4 旧代际归零（Task467/466 · 2026-11-22 UTF-16LE 双消）',
      not bin_has(bin_ipa, utf16_le("Task467 · 2026-11-22"))
      and not bin_has(bin_ipa, utf16_le("Task466 · 2026-11-22")))

KNOB_ENVS = [
    "MOBILEGL_MAGMA_FRAMESINFLIGHT",
    "MOBILEGL_ASYNC_SHADER_COMPILE",
    "MOBILEGL_COHERENT_AS_FLUSH",
    "MOBILEGL_DISABLE_TIMERQUERY",
    "MOBILEGL_ADVERTISE_FP64",
    "MOBILEGL_DISABLE_TEXTURE_VIEW",
    "MOBILEGL_ENABLE_SPIRV_VALIDATION",
    "MOBILEGL_DISABLE_LARGE_BUFFER_ADOPTION",
    "MOBILEGL_MAGMA_DISABLE_SUBGROUP",
    "MOBILEGL_MAGMA_MULTIDRAW_MODE",
    "MOBILEGL_ASYNC_SHADER_COMPILE_THREADS",
    "MOBILEGL_ASYNC_OPTIMISTIC_SHADER_STATUS",
]
check('V5 ame468 十二旋钮 setenv 字面量全场（UTF-8）',
      all(bin_has(bin_ipa, s.encode()) for s in KNOB_ENVS))
check('V6 旋钮层日志锚在场（[JavaLauncher] Task468: MobileGL perf knobs applied）',
      bin_has(bin_ipa, b"[JavaLauncher] Task468: MobileGL perf knobs applied"))
check('V7 MVK 参数缓冲开关双串（env 名 + 偏好键 moltenvk.use_metal_argument_buffers）',
      bin_has(bin_ipa, b"MVK_CONFIG_USE_METAL_ARGUMENT_BUFFERS")
      and bin_has(bin_ipa, b"moltenvk.use_metal_argument_buffers"))
check('V8 mobilegl.* 偏好键双串在场（frames_in_flight + async_shader_compile）',
      bin_has(bin_ipa, b"mobilegl.frames_in_flight")
      and bin_has(bin_ipa, b"mobilegl.async_shader_compile"))
check('V9 上游新变量幽灵零引入（VMA_BLOCK_SIZE_MB / LARGE_BUFFER_ADOPT_MB / ANGLE_BACKEND 双消，'
      '主二进制 + libMobileGL.dylib 双面）',
      all(not bin_has(bin_ipa, s.encode()) for s in (
          "MOBILEGL_MAGMA_VMA_BLOCK_SIZE_MB",
          "MOBILEGL_LARGE_BUFFER_ADOPT_MB",
          "MOBILEGL_ANGLE_BACKEND")))

mg_dylibs = glob.glob(os.path.join(ipa_app, "Payload", "*.app", "**", "libMobileGL.dylib"), recursive=True)
check('V10 libMobileGL.dylib 随包（app Frameworks 内恰一份）', len(mg_dylibs) == 1, str(mg_dylibs))
if mg_dylibs:
    check('V11 vendored dylib 反锚延续（12 旋钮名在其字符串表；幽灵名三消）',
          all(bin_has(mg_dylibs[0], s.encode()) for s in KNOB_ENVS)
          and not any(bin_has(mg_dylibs[0], s.encode()) for s in (
              "MOBILEGL_MAGMA_VMA_BLOCK_SIZE_MB",
              "MOBILEGL_LARGE_BUFFER_ADOPT_MB",
              "MOBILEGL_ANGLE_BACKEND")))

# ── 保留面回归锚 ─────────────────────────────────────────────
check('V12 Task465/156/158 保留面（折叠 selector + fold_overrides + DyldLV init + drawelements + DSA 键）',
      all(bin_has(bin_ipa, s.encode()) for s in (
          "ame_addGroup:title:key:defaultCollapsed:",
          "general.fold_overrides",
          "[DyldLVBypass] init",
          "drawelements",
          "enableExtDirectStateAccess")))

# ── 容器对一致 + UUID 新鲜度 ─────────────────────────────────
uuid_ipa, uuid_tipa = lc_uuid(bin_ipa), lc_uuid(bin_tipa)
check('V13 容器对同源构建（ipa/tipa LC_UUID 对拍一致；sha 差异 = 签名面，N+21 同族）',
      uuid_ipa is not None and uuid_ipa == uuid_tipa)

check('V14 主二进制 LC_UUID 可解析（本轮新鲜度登记）', uuid_ipa is not None, str(uuid_ipa))

dwarf = glob.glob(os.path.join(ROOT, "x_AngelAuraAmethyst.dSYM", "Contents", "Resources", "DWARF", "*"))
check('V15 dSYM DWARF LC_UUID 与主二进制配对（N+22 判例）',
      len(dwarf) == 1 and lc_uuid(dwarf[0]) == uuid_ipa and uuid_ipa is not None)

print()
if fails:
    print(f'FAIL {len(fails)}/{passed + len(fails)}: ' + ', '.join(fails))
    sys.exit(1)
print(f'ALL PASS {passed}/{passed}')
