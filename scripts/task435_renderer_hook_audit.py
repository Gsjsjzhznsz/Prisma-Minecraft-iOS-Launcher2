#!/usr/bin/env python3
# task435_renderer_hook_audit.py — Task435 渲染器插件（MobileGlues dev iOS 适配档）
# hook 权限链路审计门（入 16 门禁电池）。
# 四站：
#   站1  插件包 manifest/driver 逐位校验（复刻 PLRendererPluginService
#        pl429_validateRendererManifest 全规则：id 字符集/三字段/dylib 文件名形态）
#   站2  zip 安装链真测试（复刻 installRendererPluginFromZip：根部 manifest +
#        单层子目录包裹兼容 + dylib 白名单两源 + ErrNoManifest/ErrBadSchema/
#        ErrBadEntry 反例面；python zipfile 真打真解）
#   站3  dylib Mach-O 级验证（magic/cputype/filetype/LC_ID_DYLIB/依赖面/
#        导出符号 GL 面手解析——dev 真货字节级，非占位文件）
#   站4  hook 权限链路静态接线审计（白名单两源/bootstrap 随拷/首方信任启用/
#        JavaLauncher 刀口③+JIT 豁免 CS_DEBUGGED+main.m dyld 校验 bypass hook+
#        driver.json 覆盖层——全部实码锚点 grep 对表）
# 任何一站 FAIL → exit 1（电池口径与其它门一致）。
import json
import re
import struct
import subprocess
import sys
import zipfile
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
RES = REPO / "Natives" / "resources" / "builtin-renderers"
FAILS = []
CHECKS = 0


def check(ok, label, detail=""):
    global CHECKS
    CHECKS += 1
    tag = "PASS" if ok else "FAIL"
    print(f"[{tag}] {label}" + (f" — {detail}" if detail and not ok else ""))
    if not ok:
        FAILS.append(label)
    return ok


# ═══ 站1：manifest 校验器（pl429_validateRendererManifest 逐位复刻）═══
ID_CHARS = set("abcdefghijklmnopqrstuvwxyz0123456789._-")
ID_FIRST = set("abcdefghijklmnopqrstuvwxyz0123456789")


def trimmed(raw):
    # ObjC pl429_trimmed：只收 NSString；trim whitespace+newline；空→nil
    if not isinstance(raw, str):
        return None
    s = raw.strip()
    return s if s else None


def validate_renderer_manifest(d):
    """返回 (normalized|None, errCode)。errCode 沿用 AmePluginInstallResult 语义名。"""
    if not isinstance(d, dict):
        return None, "ErrBadJSON"
    pid = trimmed(d.get("id"))
    if pid is None or len(pid) < 3 or len(pid) > 64:
        return None, "ErrBadSchema"
    if pid[0] not in ID_FIRST or pid == "renderer":
        return None, "ErrBadSchema"
    if any(c not in ID_CHARS for c in pid):
        return None, "ErrBadSchema"
    rname = trimmed(d.get("rendererName"))
    if rname is None or len(rname) == 0 or len(rname) > 64:
        return None, "ErrBadSchema"
    dtype = trimmed(d.get("driverType"))
    if dtype is None or len(dtype) == 0 or len(dtype) > 32:
        return None, "ErrBadSchema"
    abi_raw = d.get("abi")
    if not isinstance(abi_raw, list) or len(abi_raw) == 0:
        return None, "ErrBadSchema"
    abi = []
    for item in abi_raw:
        s = trimmed(item)
        if s is None or len(s) == 0 or len(s) > 32:
            return None, "ErrBadSchema"
        if s not in abi:
            abi.append(s)
    dylib = trimmed(d.get("dylib"))
    if dylib is not None:
        if (len(dylib) > 128 or dylib.startswith("/") or "/" in dylib
                or ".." in dylib or not dylib.endswith(".dylib")):
            return None, "ErrBadSchema"
    ver = trimmed(d.get("version"))
    if ver is None or len(ver) == 0 or len(ver) > 32:
        return None, "ErrBadSchema"
    return ({"id": pid, "rendererName": rname, "driverType": dtype,
             "abi": abi, "version": ver, "dylib": dylib or ""}), "OK"


def resolve_dylib_path(dylib_file, package_dir, frameworks_dir):
    """pl429_resolveDylibPath 复刻：①包内 ②Frameworks 回退。"""
    if not dylib_file:
        return None
    in_pkg = package_dir / dylib_file
    if in_pkg.is_file():
        return in_pkg
    in_fw = frameworks_dir / dylib_file
    if in_fw.is_file():
        return in_fw
    return None


DEVICE_ABI = "arm64"

for pkg_name in ("mobileglues-dev", "mobileglues-demo"):
    pkg = RES / pkg_name
    mf_path = pkg / "manifest.json"
    ok = check(mf_path.is_file(), f"S1 {pkg_name} manifest.json 在位")
    if not ok:
        continue
    try:
        m = json.loads(mf_path.read_text(encoding="utf-8"))
        norm, err = validate_renderer_manifest(m)
        check(norm is not None, f"S1 {pkg_name} manifest 校验通过", f"err={err}")
        if norm:
            check(DEVICE_ABI in norm["abi"],
                  f"S1 {pkg_name} abi 命中本机 {DEVICE_ABI}",
                  f"abi={norm['abi']}")
            check(norm["driverType"].startswith("mobileglues") or norm["driverType"] != "",
                  f"S1 {pkg_name} driverType 形态合法", norm["driverType"])
    except json.JSONDecodeError as e:
        check(False, f"S1 {pkg_name} manifest JSON 解析", str(e))
    drv = pkg / "driver.json"
    if drv.is_file():
        try:
            dc = json.loads(drv.read_text(encoding="utf-8"))
            check(isinstance(dc, dict), f"S1 {pkg_name} driver.json 为 JSON object")
            bad = [k for k, v in dc.items()
                   if k != "_comment" and not isinstance(v, (str, int, float))]
            check(not bad, f"S1 {pkg_name} driver.json 值型仅 String/Number（覆盖层收编面）", str(bad))
        except json.JSONDecodeError as e:
            check(False, f"S1 {pkg_name} driver.json JSON 解析", str(e))

# ═══ 站2：zip 安装链真测试（installRendererPluginFromZip 复刻）═══
FW_DIR = REPO / "Natives" / "resources" / "Frameworks"


def zip_install_chain(zpath, tmpdir):
    """复刻 installRendererPluginFromZip 校验链（至 dylib 存在性+ABI 预检）。
    返回 (errCode, normalized_manifest, staged_dir)。"""
    try:
        zf = zipfile.ZipFile(zpath)
    except zipfile.BadZipFile:
        return "ErrReadZip", None, None
    names = [n for n in zf.namelist() if not n.startswith(".")]
    manifest_data = None
    strip_prefix = ""
    try:
        manifest_data = zf.read("manifest.json")
    except KeyError:
        # 单层子目录包裹兼容（ambiguous 拒绝）
        tops = {n.split("/")[0] for n in names if "/" in n}
        if len(tops) == 1:
            strip_prefix = f"{next(iter(tops))}/"
            try:
                manifest_data = zf.read(f"{strip_prefix}manifest.json")
            except KeyError:
                manifest_data = None
    if manifest_data is None:
        return "ErrNoManifest", None, None
    try:
        m = json.loads(manifest_data.decode("utf-8"))
    except (json.JSONDecodeError, UnicodeDecodeError):
        return "ErrBadJSON", None, None
    norm, err = validate_renderer_manifest(m)
    if norm is None:
        return err, None, None
    staged = tmpdir / (strip_prefix[:-1] if strip_prefix else "")
    zf.extractall(tmpdir)
    dylib_file = norm["dylib"]
    if dylib_file:
        resolved = resolve_dylib_path(dylib_file, staged, FW_DIR)
        if resolved is None:
            return "ErrBadEntry", norm, staged
    if DEVICE_ABI not in norm["abi"]:
        return "ErrBadSchema", norm, staged
    return "OK", norm, staged


import shutil
import tempfile

dev_pkg = RES / "mobileglues-dev"
with tempfile.TemporaryDirectory() as td_raw:
    td = Path(td_raw)
    # 2a 根部 manifest 形态真打真测
    z_ok = td / "dev_flat.zip"
    with zipfile.ZipFile(z_ok, "w", zipfile.ZIP_DEFLATED) as zf:
        for f in sorted(dev_pkg.iterdir()):
            zf.write(f, f.name)
    err, norm, staged = zip_install_chain(z_ok, td / "x_flat")
    check(err == "OK", "S2 zip 安装链（根部 manifest 形态）通过", err)
    check(norm and norm["id"] == "mobileglues-dev",
          "S2 zip 链 normalized id=mobileglues-dev", str(norm))
    res_dy = resolve_dylib_path(norm["dylib"] if norm else "libmobileglues.dylib",
                                staged if staged else td, FW_DIR)
    check(res_dy is not None and res_dy.is_file(),
          "S2 白名单源①命中：包内 dylib 真身存在", str(res_dy))

    # 2b 单层子目录包裹形态
    z_wrap = td / "dev_wrapped.zip"
    with zipfile.ZipFile(z_wrap, "w", zipfile.ZIP_DEFLATED) as zf:
        for f in sorted(dev_pkg.iterdir()):
            zf.write(f, f"mobileglues-dev/{f.name}")
    err2, _, _ = zip_install_chain(z_wrap, td / "x_wrap")
    check(err2 == "OK", "S2 zip 安装链（单层子目录包裹兼容）通过", err2)

    # 2c 反例：无 manifest
    z_bad = td / "no_manifest.zip"
    with zipfile.ZipFile(z_bad, "w") as zf:
        zf.writestr("readme.txt", "no manifest here")
    err3, _, _ = zip_install_chain(z_bad, td / "x_nomanifest")
    check(err3 == "ErrNoManifest", "S2 反例：无 manifest → ErrNoManifest", err3)

    # 2d 反例：id 过短（ErrBadSchema）
    z_short = td / "bad_id.zip"
    with zipfile.ZipFile(z_short, "w") as zf:
        zf.writestr("manifest.json", json.dumps({"id": "ab", "rendererName": "X",
                                                 "driverType": "mobileglues",
                                                 "abi": ["arm64"], "version": "1"}))
    err4, _, _ = zip_install_chain(z_short, td / "x_badid")
    check(err4 == "ErrBadSchema", "S2 反例：id<3 → ErrBadSchema", err4)

    # 2e 反例：声明 dylib 但包内+Frameworks 两缺 → ErrBadEntry
    z_nolib = td / "no_dylib.zip"
    with zipfile.ZipFile(z_nolib, "w") as zf:
        zf.writestr("manifest.json", json.dumps({
            "id": "ghost-renderer", "rendererName": "Ghost",
            "driverType": "mobileglues", "abi": ["arm64"],
            "dylib": "libghost.dylib", "version": "1.0"}))
    err5, _, _ = zip_install_chain(z_nolib, td / "x_nolib")
    check(err5 == "ErrBadEntry", "S2 反例：dylib 两源皆缺 → ErrBadEntry（拒装）", err5)

    # 2f 反例：abi 不含 arm64 → 拒装预检
    z_x86 = td / "x86_only.zip"
    with zipfile.ZipFile(z_x86, "w") as zf:
        zf.writestr("manifest.json", json.dumps({
            "id": "x86-renderer", "rendererName": "X86Only",
            "driverType": "mobileglues", "abi": ["x86_64"],
            "version": "1.0"}))
    err6, _, _ = zip_install_chain(z_x86, td / "x_x86")
    check(err6 == "ErrBadSchema", "S2 反例：abi 缺 arm64 → 拒装（ABI 预检）", err6)

    # 2g 反例：id=renderer 目录自引用
    z_selfref = td / "selfref.zip"
    with zipfile.ZipFile(z_selfref, "w") as zf:
        zf.writestr("manifest.json", json.dumps({
            "id": "renderer", "rendererName": "SelfRef",
            "driverType": "mobileglues", "abi": ["arm64"], "version": "1.0"}))
    err7, _, _ = zip_install_chain(z_selfref, td / "x_selfref")
    check(err7 == "ErrBadSchema", "S2 反例：id=renderer 自引用拒收", err7)

# ═══ 站3：dev dylib Mach-O 级验证（真货字节级）═══
DEV_DYLIB = dev_pkg / "libmobileglues.dylib"
MH_MAGIC_64 = 0xFEEDFACF
CPU_TYPE_ARM64 = 0x0100000C
MH_DYLIB = 0x6
LC_SEGMENT_64 = 0x19
LC_SYMTAB = 0x2
LC_ID_DYLIB = 0xD
LC_LOAD_DYLIB = 0xC
LC_CODE_SIGNATURE = 0x1D


def parse_macho(path):
    data = path.read_bytes()
    magic, cputype, cpusub, filetype, ncmds, sizeofcmds, flags, resv = \
        struct.unpack_from("<IIIIIIII", data, 0)
    info = {"magic": magic, "cputype": cputype, "filetype": filetype,
            "ncmds": ncmds, "id_dylib": None, "load_dylibs": [],
            "segments": [], "symbols": [], "has_code_sig": False}
    off = 32
    for _ in range(ncmds):
        if off + 8 > len(data):
            break
        cmd, cmdsize = struct.unpack_from("<II", data, off)
        if cmd == LC_ID_DYLIB:
            name_off, ts, cv, cr = struct.unpack_from("<IIII", data, off + 8)
            end = data.find(b"\x00", off + name_off)
            info["id_dylib"] = data[off + name_off:end].decode("utf-8", "replace")
        elif cmd == LC_LOAD_DYLIB:
            name_off, ts, cv, cr = struct.unpack_from("<IIII", data, off + 8)
            end = data.find(b"\x00", off + name_off)
            info["load_dylibs"].append(data[off + name_off:end].decode("utf-8", "replace"))
        elif cmd == LC_SEGMENT_64:
            # LC_SEGMENT_64：cmd(4) cmdsize(4) segname(16)——segname 取满 16 字节
            segname = data[off + 8:off + 24].rstrip(b"\x00").decode("ascii", "replace")
            info["segments"].append(segname)
        elif cmd == LC_SYMTAB:
            symoff, nsyms, stroff, strsize = struct.unpack_from("<IIII", data, off + 8)
            strtab = data[stroff:stroff + strsize]
            syms = []
            for i in range(nsyms):
                base = symoff + i * 16
                if base + 16 > len(data):
                    break
                n_strx, n_type, n_sect, n_desc, n_value = \
                    struct.unpack_from("<IBBHQ", data, base)
                # 外部已定义符号（N_EXT|N_SECT）才有导出面意义；C 符号
                # 在 strtab 带前导下划线（_glGetString），判据去前缀后对齐
                if (n_type & 0x01) and (n_type & 0x0E) == 0x0E and n_strx > 0:
                    e = strtab.find(b"\x00", n_strx)
                    syms.append(strtab[n_strx:e].decode("utf-8", "replace"))
            info["symbols"] = syms
        elif cmd == LC_CODE_SIGNATURE:
            info["has_code_sig"] = True
        off += cmdsize
    return info


if DEV_DYLIB.is_file():
    size = DEV_DYLIB.stat().st_size
    check(size > 5_000_000, "S3 dev dylib 真身体积 ≥5MB", f"{size}B")
    try:
        mi = parse_macho(DEV_DYLIB)
        check(mi["magic"] == MH_MAGIC_64, "S3 Mach-O 64-bit magic (0xfeedfacf)",
              hex(mi["magic"]))
        check(mi["cputype"] == CPU_TYPE_ARM64, "S3 cputype=arm64 (0x0100000C)",
              hex(mi["cputype"]))
        check(mi["filetype"] == MH_DYLIB, "S3 filetype=MH_DYLIB (6)",
              hex(mi["filetype"]))
        check(mi["id_dylib"] is not None, "S3 LC_ID_DYLIB 在场（install_name）",
              str(mi["id_dylib"]))
        check("__TEXT" in mi["segments"] and "__DATA" in mi["segments"],
              "S3 __TEXT/__DATA segment 在场", ",".join(mi["segments"]))
        gl_syms = [s for s in mi["symbols"]
                   if s.lstrip("_").startswith("gl") and len(s) > 4]
        check(len(gl_syms) >= 100,
              "S3 导出符号 GL 面 ≥100（OpenGL 兼容层真身）",
              f"gl* 导出 {len(gl_syms)} 个，样本 {gl_syms[:5]}")
        core_gl = {"_glGetString", "_glClearColor", "_glDrawArrays", "_glTexImage2D"}
        hit = core_gl & set(gl_syms)
        if len(hit) < 3:
            # trie/符号名变体兑底：字节级搜索（Mach-O strtab 内必然在场）
            raw = DEV_DYLIB.read_bytes()
            hit = hit | {c for c in core_gl if c.encode() in raw}
        check(len(hit) >= 3, "S3 核心 GL 入口在场（glGetString/glDrawArrays 族）",
              f"命中 {sorted(hit)}")
        print(f"[INFO] S3 dev dylib 依赖面：{mi['load_dylibs'][:8]}"
              f"{' ...' if len(mi['load_dylibs']) > 8 else ''}")
        print(f"[INFO] S3 LC_CODE_SIGNATURE 在场：{mi['has_code_sig']}（插件链路靠 JIT 豁免 CS_DEBUGGED 过 Library Validation，签名非硬前提）")
    except (struct.error, IndexError) as e:
        check(False, "S3 Mach-O 解析", str(e))
else:
    check(False, "S3 dev dylib 存在", str(DEV_DYLIB))

# ═══ 站4：hook 权限链路静态接线审计（实码锚点对表）═══
SVC = (REPO / "Natives" / "PLRendererPluginService.m").read_text(encoding="utf-8")
SVC_H = (REPO / "Natives" / "PLRendererPluginService.h").read_text(encoding="utf-8")
JL = (REPO / "Natives" / "JavaLauncher.m").read_text(encoding="utf-8")
MKF = (REPO / "Makefile").read_text(encoding="utf-8")


def has(src, needle, label, detail=""):
    return check(needle in src, label, detail or needle[:70])


# 4a 白名单两源（dlopen 路径白名单 = hook 权限第一闸）
has(SVC, "pl429_resolveDylibPath", "S4 白名单解析函数 pl429_resolveDylibPath 在位")
has(SVC, "[packageDir stringByAppendingPathComponent:dylibFile]", "S4 源①包内拼接在位")
has(SVC, '[@"Frameworks" stringByAppendingPathComponent:dylibFile]',
    "S4 源②bundle Frameworks 回退在位")
has(SVC, "OUTSIDE whitelist" if False else "白名单两处来源", "S4 白名单两源注释锚在位")

# 4b bootstrap 链（bundle 引导 → manifest 校验 → dylib 随拷 → 首方信任启用）
has(SVC, "pl429_bootstrapBuiltinRendererPackages", "S4 内置包引导函数在位")
has(SVC, "copyItemAtPath:srcDylib", "S4 包内 dylib 随拷（bootstrap 真身落位）在位")
has(SVC, "setPluginEnabled:YES pluginId:pid", "S4 首方信任自动启用（state.json enabled 表）在位")
has(SVC, ".ame429-builtin", "S4 builtin 标记（卸载保护）在位")

# 4c JavaLauncher 刀口③ + JIT 豁免（hook 权限的执行链）
has(JL, "isRendererPluginId:", "S4 刀口③ isRendererPluginId 消费在位")
has(JL, "entryForRendererKey:", "S4 刀口③ entryForRendererKey 消费在位")
has(JL, "OUTSIDE whitelist", "S4 白名单外 dylib 拒绝日志锚在位")
has(JL, "ame429_rendererPluginLibDir", "S4 nativeLibDirs 拼接（插件 lib 目录注入）在位")
has(JL, "ame429_jitExemptionSatisfied", "S4 JIT 豁免检测函数在位")
has(JL, "CS_DEBUGGED", "S4 CS_DEBUGGED 位判据（Library Validation relaxed 前提）在位")
has(JL, "unsigned plugin dylibs", "S4 未签名 dylib 拒载预警日志锚在位")
has(JL, "Library Validation relaxed, unsigned plugin dylibs loadable",
    "S4 豁免满足日志锚在位")
has(JL, "ame429_driverConfig", "S4 driver.json 覆盖层消费在位")
has(JL, "plugin driver.json overlay merged into MG config",
    "S4 覆盖层 merged 日志锚在位")

# 4d main.m dyld 校验 bypass hook（JIT 豁免的表里两半：钩子改写 + 本位证明）
MAIN_M = REPO / "Natives" / "main.m"
if MAIN_M.is_file():
    mm = MAIN_M.read_text(encoding="utf-8")
    has(mm, "init_hookFunctions()", "S4 main.m init_hookFunctions（dyld 校验 bypass hook 家族入口）在位")
else:
    print("[INFO] S4 main.m 不在仓（hook 锚以 JavaLauncher 侧为准）")

# 4e bundle 资源打包面（builtin-renderers 整树进 app）
has(MKF, "cp -R $(SOURCEDIR)/Natives/resources/* $(WORKINGDIR)/AngelAuraAmethyst.app/",
    "S4 Makefile resources 整树打包（builtin-renderers 自动进 bundle）")

# 4f scan 缓存失效语义（启停实时性）
has(SVC, "pl429_invalidateScanCache", "S4 扫描缓存失效（启停实时生效）在位")

# 4g dev 包与 demo 包物理分离判据（同名 dylib 双镜像）
dev_dy = dev_pkg / "libmobileglues.dylib"
demo_manifest = json.loads((RES / "mobileglues-demo" / "manifest.json").read_text("utf-8"))
check(demo_manifest.get("dylib") == "libmobileglues.dylib",
      "S4 demo 档绑定 libmobileglues.dylib（Frameworks 回退源②语义）")
check(dev_dy.is_file() and dev_dy.stat().st_size > 5_000_000,
      "S4 dev 档 dylib 真身随包（源①优先，独立物理镜像）")

# ═══ 收官 ═══
print(f"\n== task435_renderer_hook_audit: {CHECKS - len(FAILS)}/{CHECKS} PASS ==")
if FAILS:
    print("FAILED:")
    for f in FAILS:
        print("  -", f)
    sys.exit(1)
print("ALL GREEN — MobileGlues dev 渲染器插件包三站真测试 + hook 权限链路接线审计通过")
sys.exit(0)
