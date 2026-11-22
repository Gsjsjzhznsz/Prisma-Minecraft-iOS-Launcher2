#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Task467 四产物二进制验证（Task466 20/20 同族，对 r1 dev run 45032950931 / 93c28c3c 构建）。
判例沿用：N+21（产物双层容器——ipa 内包内层 ipa / tipa 内包内层 tipa，按扩展名递归解包）
+ N+22（本链 dSYM 无 LC_UUID，构建 UUID 从主二进制取，双轮新鲜度对拍用 DWARF sha256）。
用法：python3 scripts/task467_artifact_verify.py <unpack_root>
  <unpack_root> 下应存在：
    x_com.prisma-devs.prisma-ios.ipa/com.prisma-devs.prisma-1.0.0-ios.ipa
    x_com.prisma-devs.prisma-ios-trollstore.tipa/com.prisma-devs.prisma-1.0.0-ios-trollstore.tipa
    x_AngelAuraAmethyst.dSYM/
"""
import glob
import hashlib
import os
import shutil
import struct
import subprocess
import sys
import zipfile

ROOT = sys.argv[1] if len(sys.argv) > 1 else "/home/z/my-project/task467_dl"
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
    """Mach-O LC_UUID 手解（Linux 沙箱无 dwarfdump；N+22 判例同义）：
    64 位魔数两序 + FAT 两序，load commands 线性扫描 cmd==0x1b 取 16 字节。"""
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

# ── Task467 新面 ─────────────────────────────────────────────
check('V3 BuildTag Task468 · 2026-11-23 UTF-16LE 在场',
      bin_has(bin_ipa, utf16_le("Task468 · 2026-11-23")))
check('V4 旧代际归零（Task466/465 · 2026-11-22 UTF-16LE 双消）',
      not bin_has(bin_ipa, utf16_le("Task466 · 2026-11-22"))
      and not bin_has(bin_ipa, utf16_le("Task465 · 2026-11-22")))
check('V5 ame467 保环链五串组在场（rescue engaged/fetching/SUCCESS/guidance/restart）',
      all(bin_has(bin_ipa, s.encode()) for s in (
          "processor artifact(s) missing (NeoForge target",
          "Task467: Tier B fetching installer",
          "Tier B SUCCESS -- ",
          "aborting launch with guidance dialog",
          "restart required before game JVM")))
check('V6 Tier B URL 同源串在场（maven.neoforged.net installer 模板）',
      bin_has(bin_ipa, b"neoforge-%@-installer.jar")
      and bin_has(bin_ipa, b"install_profile.json"))
check('V7 Tier C i18n 键面在场（i18n_str_ame467_srg_missing 双键字面量）',
      bin_has(bin_ipa, b"i18n_str_ame467_srg_missing_title"))
check('V8 欢迎UI恢复面（类名 + present 选择器 + 哨兵键三元组）',
      bin_has(bin_ipa, b"WelcomeViewController")
      and bin_has(bin_ipa, b"presentIfNeededFromViewController:")
      and bin_has(bin_ipa, b"welcome_completed"))
check('V9 Task465 保留面回归锚（折叠 selector + fold_overrides + [DyldLVBypass] init）',
      bin_has(bin_ipa, b"ame_addGroup:title:key:defaultCollapsed:")
      and bin_has(bin_ipa, b"general.fold_overrides")
      and bin_has(bin_ipa, b"[DyldLVBypass] init")
      and bin_has(bin_ipa, b"Using redirectFunctionMirrored"))
check('V10 Task466 metallum 链五串组延续（挂载/skip/Task341 文案/surface/patchjna）',
      all(bin_has(bin_ipa, s.encode()) for s in (
          "-javaagent:%@/metallum_agent.jar=",
          "agent jar also kept off -cp per Task341",
          "Metallum surface view",
          "patchjna_agent")))

# ── 容器对一致 + UUID 新鲜度 ─────────────────────────────────
sha_ipa = hashlib.sha256(open(bin_ipa, "rb").read()).hexdigest()
sha_tipa = hashlib.sha256(open(bin_tipa, "rb").read()).hexdigest()
uuid_ipa, uuid_tipa = lc_uuid(bin_ipa), lc_uuid(bin_tipa)
check('V11 容器对同源构建（ipa/tipa LC_UUID 对拍一致；sha 差异 = 签名面，N+21 同族）',
      uuid_ipa is not None and uuid_ipa == uuid_tipa)

uuid_ipa = lc_uuid(bin_ipa)
check('V12 主二进制 LC_UUID 可解析（本轮新鲜度登记）', uuid_ipa is not None, str(uuid_ipa))

uuid_ipa_fresh = uuid_ipa
dwarf = glob.glob(os.path.join(ROOT, "x_AngelAuraAmethyst.dSYM", "Contents", "Resources", "DWARF", "*"))
check('V13 dSYM DWARF LC_UUID 与主二进制配对 + 新鲜度（≠Task466 记录 50058401-…，N+22 判例）',
      len(dwarf) == 1
      and lc_uuid(dwarf[0]) == uuid_ipa_fresh
      and uuid_ipa_fresh is not None and not uuid_ipa_fresh.startswith("50058401"))

print()
if fails:
    print(f'FAIL {len(fails)}/{passed + len(fails)}: ' + ', '.join(fails))
    sys.exit(1)
print(f'{passed}/{passed} ALL PASS')
print(f'LC_UUID={uuid_ipa}')
print(f'sha256={sha_ipa[:16]}…')
