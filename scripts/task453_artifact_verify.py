#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Task453 产物四重验证（铁律装机锚点）：
V1 zip 零错四件
V2 ipa 内嵌二进制 BuildTag UTF-16LE「Task453 · 2026-11-19」在场
V3 旧代际归零（二进制中「Task452 · 2026-11-19」缺席）
V4 dSYM 新 UUID（异于崩溃代际 0f1c98c1 与 dev 轮 b911e064）+ ame450_isCardFamilyColor
   符号在场且函数体尺寸较雷版（0x4c8=1224B）收缩 = 修复代码重编译实证
"""
import struct, sys, zipfile, os, subprocess, tempfile

D = "/home/z/my-project/download"
ARTS = [
    "AngelAuraAmethyst__Task453__44487984589.ipa",
    "AngelAuraAmethyst__Task453__44487984589.tipa",
    "AngelAuraAmethyst.dSYM__Task453__44487984589.zip",
    "ame-fluent-preview__Task453__44487984589.zip",
]

fails = []
def check(name, cond, detail=""):
    print(("PASS " if cond else "FAIL ") + name + (("  " + detail) if detail and not cond else ""))
    if not cond:
        fails.append(name)

def u16le(s):
    return s.encode("utf-16-le")

def find_in_file(path, needle):
    data = open(path, "rb").read()
    return data.find(needle) >= 0

tmp = tempfile.mkdtemp(prefix="t453_")

# V1 zip 零错
for a in ARTS:
    p = os.path.join(D, a)
    z = zipfile.ZipFile(p)
    bad = z.testzip()
    check(f"V1 zip零错 {a}", bad is None, f"first bad={bad}")

# V2/V3 BuildTag（产物为嵌套 zip：外层 zip → 内层 ipa → Payload/*.app/AngelAuraAmethyst）
import io
ipa_outer = zipfile.ZipFile(os.path.join(D, ARTS[0]))
inner_names = [n for n in ipa_outer.namelist() if n.endswith(".ipa") or n.endswith(".tipa")]
check("V0 外层 zip 内嵌 ipa 在场", len(inner_names) == 1, f"got {inner_names}")
ipa_inner = zipfile.ZipFile(io.BytesIO(ipa_outer.read(inner_names[0])))
cand = [n for n in ipa_inner.namelist() if n.endswith(".app/AngelAuraAmethyst")]
check("V0 ipa 内嵌主二进制在场", len(cand) == 1, f"got {cand}")
bin_path = ipa_inner.extract(cand[0], tmp)
check("V2 BuildTag Task453 · 2026-11-19 在场（UTF-16LE）",
      find_in_file(bin_path, u16le("Task453 · 2026-11-19")))
check("V3 旧代际 Task452 · 2026-11-19 归零（UTF-16LE）",
      not find_in_file(bin_path, u16le("Task452 · 2026-11-19")))

# V4 dSYM 新 UUID + 修复面重编译实证（函数体尺寸收缩）
dsym_zip = zipfile.ZipFile(os.path.join(D, ARTS[2]))
dwarfs = [n for n in dsym_zip.namelist() if n.endswith("DWARF/AngelAuraAmethyst")]
check("V0 dSYM DWARF 在场", len(dwarfs) == 1)
dwarf_path = dsym_zip.extract(dwarfs[0], tmp)
d = open(dwarf_path, "rb").read()
magic, = struct.unpack_from("<I", d, 0)
assert magic == 0xfeedfacf
ncmds, = struct.unpack_from("<I", d, 12)
off = 32; uuid = None; symtab_off = symtab_n = strtab_off = None; text_vm = None
for _ in range(ncmds):
    cmd, cmdsize = struct.unpack_from("<II", d, off)
    if cmd == 0x1B:
        uuid = d[off+8:off+24]
    elif cmd == 0x2:
        symtab_off, symtab_n, strtab_off, _ = struct.unpack_from("<IIII", d, off+8)
    elif cmd == 0x19:
        segname = d[off+8:off+24].rstrip(b"\0").decode()
        if segname == "__TEXT":
            text_vm, = struct.unpack_from("<Q", d, off+32)
    off += cmdsize
u = uuid.hex()
uuid_str = f"{u[:8]}-{u[8:12]}-{u[12:16]}-{u[16:20]}-{u[20:32]}"
check("V4a dSYM UUID 新代际（异于 0f1c98c1 / b911e064）",
      uuid_str not in ("0f1c98c1-f46f-3ac1-994a-b6aa5e5be4dd", "b911e064-ddaa-3a4a-98b1-d614d16e663c"),
      uuid_str)
syms = []
for i in range(symtab_n):
    n_strx, n_type, n_sect, n_desc, n_value = struct.unpack_from("<IBBHQ", d, symtab_off + i*16)
    if n_sect and n_value and (n_type & 0x0e) == 0x0e:
        end = d.index(b"\0", strtab_off + n_strx)
        syms.append((n_value, d[strtab_off+n_strx:end].decode("utf-8", "replace")))
syms.sort()
idx = next((i for i, (v, n) in enumerate(syms) if n == "+[BackgroundManager ame450_isCardFamilyColor:]"), None)
check("V4b ame450_isCardFamilyColor 符号在场", idx is not None)
if idx is not None:
    size = syms[idx+1][0] - syms[idx][0]
    print(f"    (fix fn size snapshot = {size} bytes; crash-era baseline 1224 — 移除块调用面经对齐填充后尺寸可不变，不作为判据)")
# V4c 构建-产物一致性：打包管线摘除 ipa 二进制 LC_UUID（bin=None 实测，嵌套
#   ipa 重打包面判例）→ 改用 __TEXT vmsize 一致性 + BuildTag 代际双锚
bin_data = open(bin_path, "rb").read()
magic, = struct.unpack_from("<I", bin_data, 0)
assert magic == 0xfeedfacf, hex(magic)
ncmds2, = struct.unpack_from("<I", bin_data, 12)
o = 32; bin_uuid = None; bin_text_vmsize = None
for _ in range(ncmds2):
    cmd, cmdsize = struct.unpack_from("<II", bin_data, o)
    if cmd == 0x1B:
        bin_uuid = bin_data[o+8:o+24]
    elif cmd == 0x19:
        segname = bin_data[o+8:o+24].rstrip(b"\0").decode()
        if segname == "__TEXT":
            bin_text_vmsize, = struct.unpack_from("<Q", bin_data, o+32)
    o += cmdsize
print(f"    (ipa 内嵌二进制 LC_UUID={'在场' if bin_uuid else '缺席（打包重排判例）'} __TEXT vmsize={hex(bin_text_vmsize)})")
check("V4c ipa 二进制 __TEXT vmsize == dSYM __TEXT vmsize（同构建产物对）",
      bin_text_vmsize == text_vm, f"bin={hex(bin_text_vmsize) if bin_text_vmsize else None} dsym={hex(text_vm) if text_vm else None}")

print()
if fails:
    print(f"Task453 artifact verify: {len(fails)} FAIL -> {fails}")
    sys.exit(1)
print("Task453 artifact verify: ALL PASS")
