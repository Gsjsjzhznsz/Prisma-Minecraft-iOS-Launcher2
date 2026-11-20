#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Task459 产物四重验证（铁律装机锚点，task456/457/458_artifact_verify 同构重锚）：
V1 zip 零错四件
V2 ipa 内嵌二进制 BuildTag UTF-16LE「Task459 · 2026-11-21」在场
V3 旧代际归零（Task458 · 2026-11-20 缺席）
V4 dSYM 新 UUID（异于既有退役族）+ Task459 修复面符号在场
   （-[ZL2HomeViewController ame414_relayoutVersionHeight] n≤5 avail 钳制收口 /
    -[ZL2HomeViewController ame456_setVersionCardFlowHeight:] chrome 单源写入点）+
   ipa/dSYM __TEXT vmsize 产物对一致
"""
import struct, sys, zipfile, os, io, tempfile

D = "/home/z/my-project/download"
ARTS = [
    "AngelAuraAmethyst__Task459__%RUN%.ipa",
    "AngelAuraAmethyst__Task459__%RUN%.tipa",
    "AngelAuraAmethyst.dSYM__Task459__%RUN%.zip",
    "ame-fluent-preview__Task459__%RUN%.zip",
]
RUN = None  # 由 --run 注入
RETIRED_UUIDS = ("58f8b2d2-0b59-304b-aa5c-28157112a4fe",   # Task453 代码轮（设置闪退崩溃代际）
                 "88ad191b-d39f-3f64-917d-8a03627c930a",   # Task453 规范轮
                 "a2dc7f20-03c6-39bd-8d83-c0b5fb81df1a",   # Task455 规范轮
                 "bca7c538-33a5-3cb3-9c3c-3df15e8ffbb9",   # Task456 规范轮
                 "f8f16c73")                                # Task458 规范轮（前缀判据）

fails = []
def check(name, cond, detail=""):
    print(("PASS " if cond else "FAIL ") + name + (("  " + detail) if detail and not cond else ""))
    if not cond:
        fails.append(name)

def u16le(s):
    return s.encode("utf-16-le")

tmp = tempfile.mkdtemp(prefix="t459_")

names_in_D = os.listdir(D)
arts = []
for a in ARTS:
    m = [n for n in names_in_D if n.startswith(a.split("__Task459__")[0]) and "Task459" in n and n.endswith(a.rsplit(".", 1)[-1]) and n.count("__") >= 1]
    cand = [n for n in m if n.startswith(a.split("__Task459__")[0] + "__Task459__")]
    if not cand:
        check("V0 产物在场 " + a.split("__Task459__")[0], False, "missing")
        arts.append(None)
        continue
    arts.append(os.path.join(D, sorted(cand)[0]))

if all(a is not None for a in arts):
    RUN = arts[0].split("__Task459__")[1].rsplit(".", 1)[0]
    print("archive run = " + RUN)
    for a, p in zip(ARTS, arts):
        z = zipfile.ZipFile(p)
        check(f"V1 zip零错 {os.path.basename(p)}", z.testzip() is None)

    # ★Task459 归档形态 = 直装 ipa 本体（zip 容器直含 Payload/<App>.app/主二进制；
    #   Task458 代际为「CI 产物 zip 内嵌 ipa」双层形态，本轮起单层直读）
    ipa_zip = zipfile.ZipFile(arts[0])
    cand = [n for n in ipa_zip.namelist() if n.endswith(".app/AngelAuraAmethyst")]
    check("V0 ipa 主二进制在场", len(cand) == 1)
    bin_path = ipa_zip.extract(cand[0], tmp)
    bin_data = open(bin_path, "rb").read()
    check("V2 BuildTag Task459 · 2026-11-21 在场（UTF-16LE）",
          bin_data.find(u16le("Task459 · 2026-11-21")) >= 0)
    check("V3 旧代际 Task458 · 2026-11-20 归零（UTF-16LE）",
          bin_data.find(u16le("Task458 · 2026-11-20")) < 0)

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

    dsym_zip = zipfile.ZipFile(arts[2])
    dwarfs = [n for n in dsym_zip.namelist() if n.endswith("DWARF/AngelAuraAmethyst")]
    check("V0 dSYM DWARF 在场", len(dwarfs) == 1)
    dwarf_path = dsym_zip.extract(dwarfs[0], tmp)
    d = open(dwarf_path, "rb").read()
    uuid_d, symtab_d, text_vm_dsym = macho_parse(d)
    u = uuid_d.hex()
    uuid_str = f"{u[:8]}-{u[8:12]}-{u[12:16]}-{u[16:20]}-{u[20:32]}"
    check("V4a dSYM UUID 新代际（异于退役族，含 f8f16c73=Task458）",
          uuid_str not in RETIRED_UUIDS and not uuid_str.startswith("f8f16c73"), uuid_str)

    symtab_off, symtab_n, strtab_off = symtab_d
    syms = []
    for i in range(symtab_n):
        n_strx, n_type, n_sect, n_desc, n_value = struct.unpack_from("<IBBHQ", d, symtab_off + i*16)
        if n_sect and n_value and (n_type & 0x0e) == 0x0e:
            end = d.index(b"\0", strtab_off + n_strx)
            syms.append((n_value, d[strtab_off+n_strx:end].decode("utf-8", "replace")))
    syms.sort()
    names = {n for _, n in syms}
    check("V4b 修复面符号①ame414 收口（-[ZL2HomeViewController ame414_relayoutVersionHeight]）",
          "-[ZL2HomeViewController ame414_relayoutVersionHeight]" in names)
    check("V4c 修复面符号②chrome 单源写入点（-[ZL2HomeViewController ame456_setVersionCardFlowHeight:]）",
          "-[ZL2HomeViewController ame456_setVersionCardFlowHeight:]" in names)
    check("V4d __TEXT vmsize 产物对一致",
          text_vm_ipa == text_vm_dsym and text_vm_ipa is not None,
          f"ipa={text_vm_ipa} dsym={text_vm_dsym}")

print()
if fails:
    print(f"task459_artifact_verify FAIL {len(fails)}: " + ", ".join(fails))
    sys.exit(1)
print("task459_artifact_verify ALL PASS")
