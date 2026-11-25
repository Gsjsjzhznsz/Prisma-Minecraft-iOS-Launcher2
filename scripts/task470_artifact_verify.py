#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Task470 四产物二进制验证（Task469 16/16 同族升级版，对 dev run 构建判读）。
判例沿用：N+21（产物双层容器——ipa 内包内层 ipa / tipa 内包内层 tipa，按扩展名递归解包）
+ N+22（dSYM DWARF LC_UUID 与主二进制配对）+ N+25（打包 codesign 链对 dylib 尺寸
有形变——尺寸判据一律带域，不做字节级等号）。
Task470 新面：
  V3/V4 代际翻转（Task470 在场 + Task469/468 双消）；
  V6 装机日志锚换代（Task470 companion pair 自检 + WARNING 双行）；
  V17/V18/V19 C++ 运行时伴侣对随包执法（9gW8EeL 判例：Task469 升代 dylib 的
    @rpath/libc++_cxx23 + @rpath/libc++abi_cxx23 未随包 → dlopen「Loading
    library OpenGL」崩；本轮 = 伴侣对必须与 libMobileGL 同目录在场 + 带域尺寸
    + Mach-O 魔数 + 自身 @rpath 字面量自证 + 与 libMobileGL 同目录三依赖闭环）。
用法：python3 scripts/task470_artifact_verify.py <unpack_root>
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

ROOT = sys.argv[1] if len(sys.argv) > 1 else "/home/z/my-project/task470_dl"
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

def is_macho(path):
    with open(path, "rb") as f:
        m = f.read(4)
    return m in (b"\xcf\xfa\xed\xfe", b"\xfe\xed\xfa\xcf", b"\xca\xfe\xba\xbe", b"\xbe\xba\xfe\xca")

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

# ── 代际 + 旋钮 + 锚 ─────────────────────────────────────────
check('V3 BuildTag Task476 · 2026-11-25 UTF-16LE 在场',
      bin_has(bin_ipa, utf16_le("Task476 · 2026-11-25")))
check('V4 旧代际归零（Task474 · 2026-11-24 / Task473 · 2026-11-24 UTF-16LE 双消）',
      not bin_has(bin_ipa, utf16_le("Task474 · 2026-11-24"))
      and not bin_has(bin_ipa, utf16_le("Task473 · 2026-11-24")))

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
check('V6 Task470 companion pair 装机日志锚双行在场',
      bin_has(bin_ipa, b"[JavaLauncher] Task470: MobileGL C++ runtime companion pair")
      and bin_has(bin_ipa, b"Task470: WARNING companion pair incomplete"))
check('V7 MVK 参数缓冲开关双串（env 名 + 偏好键 moltenvk.use_metal_argument_buffers）',
      bin_has(bin_ipa, b"MVK_CONFIG_USE_METAL_ARGUMENT_BUFFERS")
      and bin_has(bin_ipa, b"moltenvk.use_metal_argument_buffers"))
check('V8 mobilegl.* 偏好键双串在场（frames_in_flight + vma_block_size）',
      bin_has(bin_ipa, b"mobilegl.frames_in_flight")
      and bin_has(bin_ipa, b"mobilegl.vma_block_size"))
check('V9 幽灵三旋钮转正（VMA/ADOPT/ANGLE 主二进制在场执法）',
      all(bin_has(bin_ipa, s.encode()) for s in (
          "MOBILEGL_MAGMA_VMA_BLOCK_SIZE_MB",
          "MOBILEGL_LARGE_BUFFER_ADOPT_MB",
          "MOBILEGL_ANGLE_BACKEND")))

# ★Task475 渲染器出包：vendored dylib/builtin-renderers 零随包；在线仓库
# 消费面（仓库页类符号 + renderer-repo 基址串 + 插件真装载日志锚）随包执法。
mg_dylibs = glob.glob(os.path.join(ipa_app, "Payload", "*.app", "**", "libMobileGL.dylib"), recursive=True)
builtin_dirs = glob.glob(os.path.join(ipa_app, "Payload", "*.app", "**", "builtin-renderers"), recursive=True)
check('V10 ★Task475 渲染器出包反锚（libMobileGL.dylib 零随包 + builtin-renderers 零随包）',
      len(mg_dylibs) == 0 and len(builtin_dirs) == 0, str(mg_dylibs + builtin_dirs))
check('V11 在线渲染器仓库消费面随包（ZL2RendererRepoViewController 类符号 + renderer-repo 基址串）',
      bin_has(bin_ipa, b"ZL2RendererRepoViewController")
      and bin_has(bin_ipa, b"renderer-repo"))
check('V12 Task475 插件真装载日志锚（egl_bridge Task475 preload 行）',
      bin_has(bin_ipa, b"[egl_bridge] Task475 renderer plugin dylib preload"))

# ── Task470 新面：C++ 运行时伴侣对随包执法 ────────────────────
cxx_dylibs = glob.glob(os.path.join(ipa_app, "Payload", "*.app", "**", "libc++_cxx23.dylib"), recursive=True)
cxxabi_dylibs = glob.glob(os.path.join(ipa_app, "Payload", "*.app", "**", "libc++abi_cxx23.dylib"), recursive=True)
check('V17 libc++_cxx23.dylib 随包（恰一份 + Mach-O 魔数 + 带域 0.9-1.4MB + 自身 @rpath 字面量）',
      len(cxx_dylibs) == 1 and is_macho(cxx_dylibs[0])
      and 900_000 <= os.path.getsize(cxx_dylibs[0]) <= 1_400_000
      and bin_has(cxx_dylibs[0], b"@rpath/libc++abi_cxx23.dylib"),
      str(cxx_dylibs) + f' size={os.path.getsize(cxx_dylibs[0]) if cxx_dylibs else "-"}')
check('V18 libc++abi_cxx23.dylib 随包（恰一份 + Mach-O 魔数 + 带域 0.25-0.5MB）',
      len(cxxabi_dylibs) == 1 and is_macho(cxxabi_dylibs[0])
      and 250_000 <= os.path.getsize(cxxabi_dylibs[0]) <= 500_000,
      str(cxxabi_dylibs) + f' size={os.path.getsize(cxxabi_dylibs[0]) if cxxabi_dylibs else "-"}')
if cxx_dylibs and cxxabi_dylibs:
    same_dir = os.path.dirname(cxx_dylibs[0]) == os.path.dirname(cxxabi_dylibs[0])
    mvk_nearby = os.path.isfile(os.path.join(os.path.dirname(cxx_dylibs[0]), "libMoltenVK.dylib"))
    check('V19 ★Task475 伴侣对同目录闭环（@rpath 解析目录一致 + libMoltenVK 同目录在场）',
          same_dir and mvk_nearby)
else:
    check('V19 伴侣对同目录闭环', False, "伴侣对缺失")

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
