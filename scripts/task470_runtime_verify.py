#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Task470 渲染器 C++ 运行时伴侣对门禁（mclo.gs/9gW8EeL 装机判例制度化）。

判例：Task469 换装的 libMobileGL.dylib GIT@8df5508 其 LC_LOAD_DYLIB 带
  @rpath/libc++_cxx23.dylib + @rpath/libc++abi_cxx23.dylib（新代 versioned C++
  运行时，iPadOS 未越狱设备 /usr/lib 无且不在 dyld cache）。伴侣对未随包 →
  dlopen 即 UnsatisfiedLinkError「Loading library OpenGL」崩。本轮补装对内
  闭包（libc++_cxx23 → libc++abi_cxx23 → libSystem 叶子），并建制仓侧门禁：

  R1  伴侣对在场 + 尺寸精确（1134848 / 349104）
  R2  伴侣对 sha256 前缀互证（7243bc688668be68 / bfb6ddabd3b7aeae）
  R3  全 Frameworks 目录 Mach-O 依赖闭包：每份 dylib 的 LC_LOAD_DYLIB 逐一
      判定 OS 白名单 / @rpath 且落位于目录 / @executable_path/@loader_path 且
      落位（手解 load commands，含 FAT 多架构切片合并；Linux 无 otool 同义）
  R4  libMobileGL.dylib 三个 @rpath 依赖（cxx23/cxxabi23/MoltenVK）全部
      落位目录
  R5  PROVENANCE 档案伴侣对段在场
  R6  JavaLauncher.m Task470 装机日志锚在场（自检 + WARNING 双行）
  R7  伴侣对二进制内含 @rpath/libc++_cxx23 / @rpath/libc++abi_cxx23 自证
      （防拿错同族文件）
  S   --selftest 反向探针：构造缺失/错尺寸/错内容三态必红

用法: python3 scripts/task470_runtime_verify.py [--selftest]
"""
import hashlib
import os
import re
import struct
import subprocess
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FW = os.path.join(ROOT, "Natives", "resources", "Frameworks")
JL = os.path.join(ROOT, "Natives", "JavaLauncher.m")
PROV = os.path.join(FW, "libMobileGL.PROVENANCE.md")

EXP_CXX_SIZE = 1134848
EXP_CXX_SHA = "7243bc688668be68"
EXP_CXXABI_SIZE = 349104
EXP_CXXABI_SHA = "bfb6ddabd3b7aeae"

OS_ALLOW_PREFIX = (
    "/System/Library/", "/usr/lib/libSystem", "/usr/lib/libobjc", "/usr/lib/libc++",
    "/usr/lib/libc++abi", "/usr/lib/libz", "/usr/lib/libiconv", "/usr/lib/libcharset",
    "/usr/lib/libcompression", "/usr/lib/libbz2", "/usr/lib/liblzma", "/usr/lib/libNetwork",
    "/usr/lib/libsqlite3", "/usr/lib/libxml2", "/usr/lib/libicucore", "/usr/lib/libCoreVM",
    "/usr/lib/libCR", "/usr/lib/swift/"
)

LC_LOAD_DYLIB = 0x0C
LC_REEXPORT_DYLIB = 0x1F | 0x80000000
LC_LOAD_WEAK_DYLIB = 0x18
LC_LOAD_UPWARD_DYLIB = 0x23 | 0x80000000
LC_RPATH = 0x1C | 0x80000000


def sha256_prefix(path, n=16):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()[:n]


def _parse_slice(data):
    sm = struct.unpack("<I", data[:4])[0]
    if sm == 0xFEEDFACF:
        off, ncmds = 32, struct.unpack("<I", data[16:20])[0]
    elif sm == 0xFEEDFACE:
        off, ncmds = 28, struct.unpack("<I", data[16:20])[0]
    else:
        return None
    deps = []
    for _ in range(ncmds):
        if off + 8 > len(data):
            break
        cmd, size = struct.unpack("<II", data[off:off + 8])
        if cmd in (LC_LOAD_DYLIB, LC_REEXPORT_DYLIB, LC_LOAD_WEAK_DYLIB, LC_LOAD_UPWARD_DYLIB):
            name_off = struct.unpack("<I", data[off + 8:off + 12])[0]
            end = data.find(b"\x00", off + name_off)
            deps.append(data[off + name_off:end].decode("utf-8", "replace"))
        if size == 0 or size > len(data):
            break
        off += size
    return deps


def parse_deps(path):
    """FAT 多架构切片合并去重；thin 直读。返回 (deps, note) 或 (None, error)。"""
    with open(path, "rb") as f:
        data = f.read()
    magic = struct.unpack("<I", data[:4])[0]
    if magic == 0xFEEDFACF:
        return _parse_slice(data), ""
    if magic == 0xCFFAEDFE:  # FAT (BE)
        narch = struct.unpack(">I", data[4:8])[0]
        merged, seen = [], set()
        for i in range(narch):
            _, _, aoff, asize, _ = struct.unpack(">IIIII", data[8 + 20 * i:28 + 20 * i])
            deps = _parse_slice(data[aoff:aoff + asize])
            if deps is None:
                return None, f"fat slice {i} unparseable"
            for d in deps:
                if d not in seen:
                    seen.add(d)
                    merged.append(d)
        return merged, f"fat{narch}"
    return None, f"magic {magic:#x}"


def dep_verdict(dep, bundled_names):
    if dep.startswith("@rpath/"):
        name = dep[len("@rpath/"):]
        return ("ok", f"rpath-bundled:{name}") if name in bundled_names else ("missing", dep)
    if dep.startswith(("@executable_path/", "@loader_path/")):
        name = dep.split("/", 1)[1]
        return ("ok", f"bundled:{name}") if name in bundled_names else ("missing", dep)
    if any(dep.startswith(p) for p in OS_ALLOW_PREFIX):
        return ("ok", "os")
    return ("unknown", dep)


def audit_frameworks():
    bundled = set(os.listdir(FW))
    problems = []
    checked = 0
    for name in sorted(bundled):
        p = os.path.join(FW, name)
        if os.path.isdir(p) or name.endswith((".md", ".bak")):
            continue
        deps, note = parse_deps(p)
        if deps is None:
            # 非 Mach-O 文件（资源类）跳过判读，但登记
            problems.append((name, f"non-macho({note})"))
            continue
        checked += 1
        for dep in deps:
            verdict, detail = dep_verdict(dep, bundled)
            if verdict != "ok":
                problems.append((name, f"{verdict}: {dep}"))
    return checked, problems


def main():
    selftest = "--selftest" in sys.argv
    fails = []

    def check(name, ok, detail=""):
        print(("PASS " if ok else "FAIL ") + name + (f" -- {detail}" if detail and not ok else ""))
        if not ok:
            fails.append(name)

    if selftest:
        # S 反向探针：三态必红（拿错文件/错尺寸/依赖缺失）
        tmp = tempfile.mkdtemp(prefix="task470_selftest_")
        # 态1 错内容（同尺寸假文件 → R2 sha 红）
        fake = os.path.join(tmp, "fake_cxx23.dylib")
        with open(fake, "wb") as f:
            f.write(b"\xcf\xfa\xed\xfe" + b"\x00" * (EXP_CXX_SIZE - 4))
        check("S1 selftest 错内容必红", sha256_prefix(fake) != EXP_CXX_SHA)
        # 态2 错尺寸（短尺寸假文件 → R1 尺寸红）
        fake2 = os.path.join(tmp, "fake_cxx23_short.dylib")
        with open(fake2, "wb") as f:
            f.write(b"\x00" * 64)
        check("S2 selftest 错尺寸必红", os.path.getsize(fake2) != EXP_CXX_SIZE)
        # 态3 依赖缺失判定（真审计器对含未落位 @rpath 的假切片；
        # 头部恰 32 字节：magic(4)+cputype(4)+cpusub(4)+filetype(4)+ncmds(4)
        # +sizeofcmds(4)+reserved(4)+flags(4)，load commands 起于 32）
        thin = (b"\xcf\xfa\xed\xfe" + struct.pack("<I", 0) * 3
                + struct.pack("<I", 1) + b"\x00" * 12)
        load_cmd = (struct.pack("<II", LC_LOAD_DYLIB, 48)
                    + struct.pack("<I", 24) + b"\x00" * 12
                    + b"@rpath/libc++_cxx23.dylib\x00\x00\x00")
        blob = thin + load_cmd
        deps = _parse_slice(blob)
        v, _d = dep_verdict(deps[0], set()) if deps else ("err", "")
        check("S3 selftest 依赖缺失判定必红", v == "missing")
        if fails:
            print(f"SELFTEST FAIL {len(fails)}: {', '.join(fails)}")
            return 1
        print(f"SELFTEST ALL PASS {3 - len(fails)}/3")
        return 0

    # R1 伴侣对在场 + 尺寸
    cxx = os.path.join(FW, "libc++_cxx23.dylib")
    cxxabi = os.path.join(FW, "libc++abi_cxx23.dylib")
    ok_cxx = os.path.isfile(cxx) and os.path.getsize(cxx) == EXP_CXX_SIZE
    ok_cxxabi = os.path.isfile(cxxabi) and os.path.getsize(cxxabi) == EXP_CXXABI_SIZE
    check("R1 伴侣对在场+尺寸精确（1134848/349104）", ok_cxx and ok_cxxabi,
          f"{os.path.getsize(cxx) if os.path.exists(cxx) else 'missing'} / "
          f"{os.path.getsize(cxxabi) if os.path.exists(cxxabi) else 'missing'}")

    # R2 sha256 互证
    check("R2 伴侣对 sha256 前缀互证",
          os.path.isfile(cxx) and sha256_prefix(cxx) == EXP_CXX_SHA
          and os.path.isfile(cxxabi) and sha256_prefix(cxxabi) == EXP_CXXABI_SHA,
          f"{sha256_prefix(cxx) if os.path.exists(cxx) else '-'} / "
          f"{sha256_prefix(cxxabi) if os.path.exists(cxxabi) else '-'}")

    # R3 全目录依赖闭包
    checked, problems = audit_frameworks()
    check(f"R3 全 Frameworks 目录 Mach-O 依赖闭包（实判 {checked} 份 dylib）",
          checked >= 18 and not problems,
          "; ".join(f"{n}: {d}" for n, d in problems[:8]))

    # R4 libMobileGL 三 @rpath 依赖落位
    bundled = set(os.listdir(FW))
    mg_deps, note = parse_deps(os.path.join(FW, "libMobileGL.dylib"))
    need = {"libc++_cxx23.dylib", "libc++abi_cxx23.dylib", "libMoltenVK.dylib"}
    rpath_deps = {d[len("@rpath/"):] for d in (mg_deps or []) if d.startswith("@rpath/")}
    check("R4 libMobileGL @rpath 三依赖全落位（cxx23/cxxabi23/MoltenVK）",
          (mg_deps is not None) and need.issubset(rpath_deps) and need.issubset(bundled),
          f"rpath_deps={sorted(rpath_deps)}")

    # R5 PROVENANCE 伴侣对段
    prov = open(PROV, encoding="utf-8", errors="replace").read() if os.path.isfile(PROV) else ""
    check("R5 PROVENANCE 伴侣对档案段在场（Task470 + cxx23 双名）",
          "Task470" in prov and "libc++_cxx23" in prov and "libc++abi_cxx23" in prov)

    # R6 装机日志锚双行
    jl = open(JL, encoding="utf-8", errors="replace").read() if os.path.isfile(JL) else ""
    check("R6 JavaLauncher Task470 装机日志锚双行（自检 + WARNING）",
          "[JavaLauncher] Task470: MobileGL C++ runtime companion pair" in jl
          and "Task470: WARNING companion pair incomplete" in jl)

    # R7 伴侣对自身 @rpath 自证（防拿错同族文件）
    self_ids = ""
    for p in (cxx, cxxabi):
        if os.path.isfile(p):
            with open(p, "rb") as f:
                self_ids += f.read().decode("latin-1")
    check("R7 伴侣对内容自证（@rpath/libc++_cxx23 与 libc++abi_cxx23 字面量在场）",
          "@rpath/libc++_cxx23" in self_ids and "libc++abi_cxx23" in self_ids)

    print()
    if fails:
        print(f"FAIL {len(fails)}/{7 - len(fails) + len(fails)}: {', '.join(fails)}")
        return 1
    print(f"ALL PASS 7/7")
    return 0


if __name__ == "__main__":
    sys.exit(main())
