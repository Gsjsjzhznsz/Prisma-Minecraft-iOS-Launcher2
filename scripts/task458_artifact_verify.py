#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Task458 产物四重验证（铁律装机锚点，task456/457_artifact_verify 同构重锚）：
V1 zip 零错四件
V2 ipa 内嵌二进制 BuildTag UTF-16LE「Task458 · 2026-11-20」在场
V3 旧代际归零（Task457 · 2026-11-19 缺席）
V4 dSYM 新 UUID（异于既有退役族）+ Task458 修复面符号在场
   （-[ZL2ShellNavItem ame_setSelected:] 选中语义双族分流单点 /
    +[ZL2Theme ame347_shellLayoutPluginOverridden] 分流判据 API /
    -[ZL2ShellViewController ame389_syncIndicatorYAnimated:] 滑移条分流门）+
   ipa/dSYM __TEXT vmsize 产物对一致
"""
import struct, sys, zipfile, os, io, tempfile

D = "/home/z/my-project/download"
ARTS = [
    "AngelAuraAmethyst__Task458__44695329236.ipa",
    "AngelAuraAmethyst__Task458__44695329236.tipa",
    "AngelAuraAmethyst.dSYM__Task458__44695329236.zip",
    "ame-fluent-preview__Task458__44695329236.zip",
]
RETIRED_UUIDS = ("58f8b2d2-0b59-304b-aa5c-28157112a4fe",   # Task453 代码轮（设置闪退崩溃代际）
                 "88ad191b-d39f-3f64-917d-8a03627c930a",   # Task453 规范轮
                 "a2dc7f20-03c6-39bd-8d83-c0b5fb81df1a",   # Task455 规范轮
                 "bca7c538-33a5-3cb3-9c3c-3df15e8ffbb9")   # Task456 规范轮（占位形态，实测以脚本输出为准）

fails = []
def check(name, cond, detail=""):
    print(("PASS " if cond else "FAIL ") + name + (("  " + detail) if detail and not cond else ""))
    if not cond:
        fails.append(name)

def u16le(s):
    return s.encode("utf-16-le")

tmp = tempfile.mkdtemp(prefix="t458_")

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
bin_data = open(bin_path, "rb").read()
check("V2 BuildTag Task458 · 2026-11-20 在场（UTF-16LE）",
      bin_data.find(u16le("Task458 · 2026-11-20")) >= 0)
check("V3 旧代际 Task457 · 2026-11-19 归零（UTF-16LE）",
      bin_data.find(u16le("Task457 · 2026-11-19")) < 0)

# ipa 侧 __TEXT vmsize
def macho_parse(d):
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
    return uuid, (symtab_off, symtab_n, strtab_off), text_vm

uuid_b, symtab, text_vm_ipa = macho_parse(bin_data)

dsym_zip = zipfile.ZipFile(os.path.join(D, ARTS[2]))
dwarfs = [n for n in dsym_zip.namelist() if n.endswith("DWARF/AngelAuraAmethyst")]
check("V0 dSYM DWARF 在场", len(dwarfs) == 1)
dwarf_path = dsym_zip.extract(dwarfs[0], tmp)
d = open(dwarf_path, "rb").read()
uuid_d, symtab_d, text_vm_dsym = macho_parse(d)
u = uuid_d.hex()
uuid_str = f"{u[:8]}-{u[8:12]}-{u[12:16]}-{u[16:20]}-{u[20:32]}"
check("V4a dSYM UUID 新代际（异于 58f8b2d2 / 88ad191b / a2dc7f20 / bca7c538 退役族）", uuid_str not in RETIRED_UUIDS, uuid_str)

symtab_off, symtab_n, strtab_off = symtab_d
syms = []
for i in range(symtab_n):
    n_strx, n_type, n_sect, n_desc, n_value = struct.unpack_from("<IBBHQ", d, symtab_off + i*16)
    if n_sect and n_value and (n_type & 0x0e) == 0x0e:
        end = d.index(b"\0", strtab_off + n_strx)
        syms.append((n_value, d[strtab_off+n_strx:end].decode("utf-8", "replace")))
syms.sort()
names = {n for _, n in syms}
check("V4b 修复面符号①选中语义双族分流单点（-[ZL2ShellNavItem ame_setSelected:]）",
      "-[ZL2ShellNavItem ame_setSelected:]" in names)
check("V4c 修复面符号②分流判据 API（+[ZL2Theme ame347_shellLayoutPluginOverridden]）",
      "+[ZL2Theme ame347_shellLayoutPluginOverridden]" in names)
check("V4d 修复面符号③滑移条分流门在位（-[ZL2ShellViewController ame389_syncIndicatorYAnimated:]）",
      "-[ZL2ShellViewController ame389_syncIndicatorYAnimated:]" in names)
check("V4e __TEXT vmsize 产物对一致",
      text_vm_ipa == text_vm_dsym and text_vm_ipa is not None,
      f"ipa={text_vm_ipa} dsym={text_vm_dsym}")

print()
if fails:
    print(f"task458_artifact_verify FAIL {len(fails)}: " + ", ".join(fails))
    sys.exit(1)
print("task458_artifact_verify ALL PASS")
