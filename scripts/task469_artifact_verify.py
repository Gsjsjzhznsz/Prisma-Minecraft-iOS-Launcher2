#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Task469 四产物二进制验证（Task468 15/15 同族升级版，对 dev run 构建判读）。
判例沿用：N+21（产物双层容器——ipa 内包内层 ipa / tipa 内包内层 tipa，按扩展名递归解包）
+ N+22（dSYM DWARF LC_UUID 与主二进制配对）。
Task469 新面：
  V3/V4 代际翻转（Task469 在场 + Task468/467 双消）；
  V5 十六旋钮（+VMA/ADOPT/ANGLE/R11G11B10F 四新员）；
  V9 幽灵三旋钮转正 = 主二进制在场执法（Task468 时代的双消判据翻转）；
  V11 dylib 换装反锚（GIT@8df5508 在场 + 旧代 GIT@874b9e8 双消 + 尺寸代际）。
用法：python3 scripts/task469_artifact_verify.py <unpack_root>
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

ROOT = sys.argv[1] if len(sys.argv) > 1 else "/home/z/my-project/task469_dl"
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

# ── Task469 新面：渲染器升代 + 旋钮层扩展 ─────────────────────
check('V3 BuildTag Task469 · 2026-11-23 UTF-16LE 在场',
      bin_has(bin_ipa, utf16_le("Task469 · 2026-11-23")))
check('V4 旧代际归零（Task468 · 2026-11-23 / Task467 · 2026-11-22 UTF-16LE 双消）',
      not bin_has(bin_ipa, utf16_le("Task468 · 2026-11-23"))
      and not bin_has(bin_ipa, utf16_le("Task467 · 2026-11-22")))

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
    "MOBILEGL_MAGMA_VMA_BLOCK_SIZE_MB",
    "MOBILEGL_LARGE_BUFFER_ADOPT_MB",
    "MOBILEGL_ANGLE_BACKEND",
    "MOBILEGL_MAGMA_R11G11B10F_FALLBACK",
]
check('V5 ame468 十六旋钮 setenv 字面量全场（UTF-8）',
      all(bin_has(bin_ipa, s.encode()) for s in KNOB_ENVS))
check('V6 旋钮层日志锚在场（[JavaLauncher] Task469: MobileGL perf knobs applied）',
      bin_has(bin_ipa, b"[JavaLauncher] Task469: MobileGL perf knobs applied"))
check('V7 MVK 参数缓冲开关双串（env 名 + 偏好键 moltenvk.use_metal_argument_buffers）',
      bin_has(bin_ipa, b"MVK_CONFIG_USE_METAL_ARGUMENT_BUFFERS")
      and bin_has(bin_ipa, b"moltenvk.use_metal_argument_buffers"))
check('V8 mobilegl.* 偏好键双串在场（frames_in_flight + vma_block_size）',
      bin_has(bin_ipa, b"mobilegl.frames_in_flight")
      and bin_has(bin_ipa, b"mobilegl.vma_block_size"))
check('V9 幽灵三旋钮转正（VMA/ADOPT/ANGLE 主二进制在场执法——Task468 双消判据翻转）',
      all(bin_has(bin_ipa, s.encode()) for s in (
          "MOBILEGL_MAGMA_VMA_BLOCK_SIZE_MB",
          "MOBILEGL_LARGE_BUFFER_ADOPT_MB",
          "MOBILEGL_ANGLE_BACKEND")))

mg_dylibs = glob.glob(os.path.join(ipa_app, "Payload", "*.app", "**", "libMobileGL.dylib"), recursive=True)
check('V10 libMobileGL.dylib 随包（app Frameworks 内恰一份）', len(mg_dylibs) == 1, str(mg_dylibs))
if mg_dylibs:
    d = mg_dylibs[0]
    sz = os.path.getsize(d)
    # 打包链 codesign/签名摘除会形变体积（仓库侧未剥离母本 16447088 → 随包 12266784
    # 实测，-4.18MB 签名面），尺寸判据用带域防旧代（旧代 85757760B 远超上界）：
    check('V11 dylib 换装代际反锚（GIT@8df5508 在场 + 旧代 GIT@874b9e8 双消 + 带域 10-20MB）',
          bin_has(d, b"GIT@8df5508")
          and not bin_has(d, b"GIT@874b9e8")
          and 10_000_000 <= sz <= 20_000_000,
          f"size={sz}")
    check('V12 vendored dylib 反锚延续（16 旋钮名在其字符串表）',
          all(bin_has(d, s.encode()) for s in KNOB_ENVS))
else:
    check('V11 dylib 换装代际反锚', False, "dylib 缺失")
    check('V12 vendored dylib 反锚延续', False, "dylib 缺失")

# ── 保留面回归锚 ─────────────────────────────────────────────
check('V13 Task465/156/158 保留面（折叠 selector + fold_overrides + DyldLV init + drawelements + DSA 键）',
      all(bin_has(bin_ipa, s.encode()) for s in (
          "ame_addGroup:title:key:defaultCollapsed:",
          "general.fold_overrides",
          "[DyldLVBypass] init",
          "drawelements",
          "enableExtDirectStateAccess")))

# ── 容器对一致 + UUID 新鲜度 ─────────────────────────────────
uuid_ipa, uuid_tipa = lc_uuid(bin_ipa), lc_uuid(bin_tipa)
check('V14 容器对同源构建（ipa/tipa LC_UUID 对拍一致；sha 差异 = 签名面，N+21 同族）',
      uuid_ipa is not None and uuid_ipa == uuid_tipa)

check('V15 主二进制 LC_UUID 可解析（本轮新鲜度登记）', uuid_ipa is not None, str(uuid_ipa))

dwarf = glob.glob(os.path.join(ROOT, "x_AngelAuraAmethyst.dSYM", "Contents", "Resources", "DWARF", "*"))
check('V16 dSYM DWARF LC_UUID 与主二进制配对（N+22 判例）',
      len(dwarf) == 1 and lc_uuid(dwarf[0]) == uuid_ipa and uuid_ipa is not None)

print()
if fails:
    print(f'FAIL {len(fails)}/{passed + len(fails)}: ' + ', '.join(fails))
    sys.exit(1)
print(f'ALL PASS {passed}/{passed}')
