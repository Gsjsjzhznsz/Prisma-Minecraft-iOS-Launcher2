#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Task455 产物四重验证（铁律装机锚点，task454_artifact_verify 同构重锚）：
V1 zip 零错四件
V2 ipa 内嵌二进制 BuildTag UTF-16LE「Task455 · 2026-11-19」在场
V3 旧代际归零（Task454 · 2026-11-19 缺席）
V4 dSYM 新 UUID + Task455 修复面符号在场（ame455_consumeStartupRebuild /
   ame455_hydrateFromManifestCacheAllowStale:）+ ipa/dSYM __TEXT vmsize 产物对一致
"""
import struct, sys, zipfile, os, io, tempfile

D = "/home/z/my-project/download"
ARTS = [
    "AngelAuraAmethyst__Task455__44525987308.ipa",
    "AngelAuraAmethyst__Task455__44525987308.tipa",
    "AngelAuraAmethyst.dSYM__Task455__44525987308.zip",
    "ame-fluent-preview__Task455__44525987308.zip",
]
RETIRED_UUIDS = ("58f8b2d2-0b59-304b-aa5c-28157112a4fe",   # Task453 代码轮（设置闪退崩溃代际）
                 "88ad191b-d39f-3f64-917d-8a03627c930a",   # Task453 规范轮
                 "e852431e")                              # docs 提交占位（不参与 UUID 判据）

fails = []
def check(name, cond, detail=""):
    print(("PASS " if cond else "FAIL ") + name + (("  " + detail) if detail and not cond else ""))
    if not cond:
        fails.append(name)

def u16le(s):
    return s.encode("utf-16-le")

tmp = tempfile.mkdtemp(prefix="t455_")

for a in ARTS:
    z = zipfile.ZipFile(os.path.join(D, a))
    check(f"V1 zip零错 {a}", z.testzip() is None)

ipa_outer = zipfile.ZipFile(os.path.join(D, ARTS[0]))
inner_names = [n for n in ipa_outer.namelist() if n.endswith(".ipa") or n.endswith(".tipa")]
check("V0 外层 zip 内嵌 ipa 在场", len(inner_names) == 1)
ipa_inner = zipfile.ZipFile(io.BytesIO(ipa_outer.read(inner_names[0])))
cand = [n for n in ipa_inner.namelist() if n.endswith(".app/AngelAuraAmethyst")]
check("V0 ipa 内嵌主二进制在场", len(cand) == 1)
bin_path = ipa_inner.extract(cand[0], tmp)
check("V2 BuildTag Task455 · 2026-11-19 在场（UTF-16LE）",
      open(bin_path, "rb").read().find(u16le("Task455 · 2026-11-19")) >= 0)
check("V3 旧代际 Task454 · 2026-11-19 归零（UTF-16LE）",
      open(bin_path, "rb").read().find(u16le("Task454 · 2026-11-19")) < 0)

dsym_zip = zipfile.ZipFile(os.path.join(D, ARTS[2]))
dwarfs = [n for n in dsym_zip.namelist() if n.endswith("DWARF/AngelAuraAmethyst")]
check("V0 dSYM DWARF 在场", len(dwarfs) == 1)
dwarf_path = dsym_zip.extract(dwarfs[0], tmp)
d = open(dwarf_path, "rb").read()
assert struct.unpack_from("<I", d, 0)[0] == 0xfeedfacf
ncmds, = struct.unpack_from("<I", d, 12)
off = 32; uuid = None; symtab_off = symtab_n = strtab_off = None; text_vm = None
for _ in range(ncmds):
    cmd, cmdsize = struct.unpack_from("<II", d, off)
    if cmd == 0x1B:
        uuid = d[off+8:off+24]
    elif cmd == 0x2:
        symtab_off, symtab_n, strtab_off, _ = struct.unpack_from("<IIII", d, off+8)
    elif cmd == 0x19:
        if d[off+8:off+24].rstrip(b"\0").decode() == "__TEXT":
            text_vm, = struct.unpack_from("<Q", d, off+32)
    off += cmdsize
u = uuid.hex()
uuid_str = f"{u[:8]}-{u[8:12]}-{u[12:16]}-{u[16:20]}-{u[20:32]}"
check("V4a dSYM UUID 新代际（异于 58f8b2d2 / 88ad191b）", uuid_str not in RETIRED_UUIDS, uuid_str)

syms = []
for i in range(symtab_n):
    n_strx, n_type, n_sect, n_desc, n_value = struct.unpack_from("<IBBHQ", d, symtab_off + i*16)
    if n_sect and n_value and (n_type & 0x0e) == 0x0e:
        end = d.index(b"\0", strtab_off + n_strx)
        syms.append((n_value, d[strtab_off+n_strx:end].decode("utf-8", "replace")))
syms.sort()
names = {n for _, n in syms}
check("V4b 修复面符号①启动合并（+[ZL2Theme ame455_consumeStartupRebuild]）",
      "+[ZL2Theme ame455_consumeStartupRebuild]" in names)
check("V4b 修复面符号②清单缓存（-[ZL2VersionIndex ame455_hydrateFromManifestCacheAllowStale:]）",
      "-[ZL2VersionIndex ame455_hydrateFromManifestCacheAllowStale:]" in names)
check("V4b 修复面符号③裸键根修消费点在链接单元（Task255 autoCheck 链保留）",
      any("autoCheckControlUpdatesOnce" in n for n in names))

bin_data = open(bin_path, "rb").read()
ncmds2, = struct.unpack_from("<I", bin_data, 12)
o = 32; bin_text_vmsize = None
for _ in range(ncmds2):
    cmd, cmdsize = struct.unpack_from("<II", bin_data, o)
    if cmd == 0x19 and bin_data[o+8:o+24].rstrip(b"\0").decode() == "__TEXT":
        bin_text_vmsize, = struct.unpack_from("<Q", bin_data, o+32)
    o += cmdsize
check("V4c ipa 二进制 __TEXT vmsize == dSYM __TEXT vmsize（同构建产物对）",
      bin_text_vmsize == text_vm, f"bin={hex(bin_text_vmsize or 0)} dsym={hex(text_vm or 0)}")

print()
if fails:
    print(f"Task455 artifact verify: {len(fails)} FAIL -> {fails}")
    sys.exit(1)
print("Task455 artifact verify: ALL PASS")
