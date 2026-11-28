#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Task468 自检门 —— MobileGL/Magma 引擎级性能旋钮层（抄 Witch-Launcher 渲染调优面）
+ 内置渲染器上游更新扫描轮。Task469 轮扩展：dylib 升代换装（Witch fork GIT@8df5508）
+ 幽灵三旋钮转正 + 16 旋钮面 + S10 升代产物代际锚。

门禁锚面（S 组）：
  S1  ame468 旋钮层在 JavaLauncher.m 落位（函数 + 12 个 MOBILEGL_* setenv 名）；
  S2  二进制反锚：每个被应用的 MOBILEGL_* 变量名必须真的存在于
      Natives/resources/Frameworks/libMobileGL.dylib 的字符串表（Task469 升代后 =
      Witch fork GIT@8df5508 构建，16 旋钮全支持）——上游 MobileGL main 26.11 线
      的更名/新增变量（FRAMES_IN_FLIGHT 新名 / SUBGROUP_EMULATION / ITRP_FIX /
      MAGMA_MAX_DRAWS_PER_COMMAND_BUFFER / MAGMA_DESCRIPTOR_TRIM_FRAMES /
      MAGMA_EXTRA_SWAPCHAIN_IMAGES / SERVER_FRAME_STATS / ESPRYT_YUV_DRIVER_CONVERSION）
      在本 dylib 不存在，必须源码零引入（幽灵变量防再犯，Task439 幽灵门同族判例）；
  S3  默认值字面量：三缓冲默认 3、异步着色器编译默认开（"1"）；
  S4  else 分支 unsetenv 对称清偿（每个 setenv 名都有 unsetenv 镜像）；
  S5  既有口径零回归：Task156 ESPRYT drawelements、Task158 DSA=@0、
      customGLVersion=@40、maxGlslCacheSize=@128 四行原样在场；
  S6  Task463 折叠面零污染：ZL2SettingCards.h/.m、ZL2SettingPages.m、
      ZL2Theme.h 工作树零 diff；
  S7  MVK 参数缓冲开关（moltenvk.use_metal_argument_buffers 偏好透传）+
      libMoltenVK.dylib 二进制反锚；
  S8  日志锚行（[JavaLauncher] Task468: MobileGL perf knobs applied）在场；
  S9  偏好归一化读取器 ame468_pref_string 定义于首个调用点之前（编译序防线，
      本轮 r0 复盘：初版 helper 定义在 init_loadDefaultEnv 之后即隐式声明雷）。
  S10 升代产物代际锚（Task469）：libMobileGL.dylib 尺寸 16447088 + sha256
      fd907f65… 前缀 + GIT@8df5508 在场 + 旧代 GIT@874b9e8 双消 +
      libMoltenVK.dylib 14769224/sha 3378bf8d… 前缀 + 出处档案互证。

--selftest 反向门：合成负样本验证本门真的会咬人（缺 setenv 的假源 / 二进制
  不存在的变量名 / 默认值被改的假源，三者都必须 FAIL 才算门活着）。
"""
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
JL = ROOT / "Natives" / "JavaLauncher.m"
DYLIB_MG = ROOT / "Natives" / "resources" / "Frameworks" / "libMobileGL.dylib"
DYLIB_MVK = ROOT / "Natives" / "resources" / "Frameworks" / "libMoltenVK.dylib"
BUILD_TAG = ROOT / "Natives" / "BuildTag.h"

# 被 Task468 应用的 MOBILEGL_* 变量（setenv 全集；MAGMA_* 仅 Vulkan 档，
# 但 strings 反锚不做档位区分——二进制层面全量在场即可）
APPLIED_ENVS = [
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

# Task469 幽灵清单翻转：VMA/ADOPT/ANGLE 三名已在 Witch fork GIT@8df5508 dylib
# strings 实证在场并转正接线（见 APPLIED_ENVS）。本清单改为看守「上游 MobileGL
# main 26.11 线的更名/新增变量」——fork@8df5508 构建（2026-10-16）不含它们，
# 下轮若做 MobileGL main 源码构建升代才可解禁；防再犯判例同 Task439 幽灵门。
GHOST_ENVS = [
    "MOBILEGL_FRAMES_IN_FLIGHT",
    "MOBILEGL_SUBGROUP_EMULATION",
    "MOBILEGL_ITRP_FIX",
    "MOBILEGL_MAGMA_MAX_DRAWS_PER_COMMAND_BUFFER",
    "MOBILEGL_MAGMA_DESCRIPTOR_TRIM_FRAMES",
    "MOBILEGL_MAGMA_EXTRA_SWAPCHAIN_IMAGES",
    "MOBILEGL_SERVER_FRAME_STATS",
    "MOBILEGL_ESPRYT_YUV_DRIVER_CONVERSION",
]

# Task463 折叠面四元组（零污染面）
FOLDING_SURFACE = [
    "Natives/ZL2SettingCards.h",
    "Natives/ZL2SettingCards.m",
    "Natives/ZL2SettingPages.m",
]


def dylib_strings(path):
    if not path.exists():
        return None
    data = path.read_bytes()
    # 提取可打印 ASCII 串（等价 strings(1) 语义，最小长度 6）
    out, cur = [], bytearray()
    for b in data:
        if 32 <= b < 127:
            cur.append(b)
        else:
            if len(cur) >= 6:
                out.append(cur.decode("ascii", "ignore"))
            cur = bytearray()
    if len(cur) >= 6:
        out.append(cur.decode("ascii", "ignore"))
    return out


def has_real_setenv(text, name):
    """真 setenv 匹配（unsetenv 以 setenv 结尾，负向环视排除——r0 复盘判例）"""
    return re.search(r'(?<!un)setenv\("' + re.escape(name) + '"', text) is not None


def has_real_getenv(text, name):
    return re.search(r'(?<![\w])getenv\("' + re.escape(name) + '"', text) is not None


def check_source(text, fails, prefix=""):
    """S1/S3/S4/S5/S8/S9 源码锚（抽出来给 --selftest 用）"""
    # S1 旋钮层函数注释锚
    if "Task468：MobileGL/Magma 引擎级性能旋钮层" not in text:
        fails.append(f"{prefix}S1 旋钮层注释锚缺失")
    if "Task469 渲染器真正升代" not in text:
        fails.append(f"{prefix}S1 Task469 升代注释锚缺失")
    for name in APPLIED_ENVS:
        if not has_real_setenv(text, name):
            fails.append(f"{prefix}S1 setenv 缺失: {name}")
    # S3 默认值字面量
    if "if (ame468_frames <= 0) ame468_frames = 3;" not in text:
        fails.append(f"{prefix}S3 三缓冲默认 3 缺失")
    if 'ame468_asyncOn ? "1" : "0"' not in text:
        fails.append(f"{prefix}S3 异步编译默认开缺失")
    if "if (ame468_vma <= 0) ame468_vma = 32;" not in text:
        fails.append(f"{prefix}S3 VMA 块默认 32 缺失")
    if "if (ame468_adopt <= 0) ame468_adopt = 4;" not in text:
        fails.append(f"{prefix}S3 收养阈值默认 4 缺失")
    if ']) ? "vulkan" : "tgles", 1)' not in text:
        fails.append(f"{prefix}S3 ANGLE 后端默认 tgles 缺失")
    if 'getPrefBool(@"mobilegl.r11g11b10f_fallback") ? "1" : "0"' not in text:
        fails.append(f"{prefix}S3 R11G11B10F 默认关缺失")
    # S4 unsetenv 对称
    for name in APPLIED_ENVS:
        if f'unsetenv("{name}")' not in text:
            fails.append(f"{prefix}S4 unsetenv 缺失: {name}")
    if 'unsetenv("MVK_CONFIG_USE_METAL_ARGUMENT_BUFFERS")' not in text:
        fails.append(f"{prefix}S4 unsetenv 缺失: MVK_CONFIG_USE_METAL_ARGUMENT_BUFFERS")
    # S5 既有口径零回归
    if 'config[@"enableExtDirectStateAccess"] = @0;' not in text:
        fails.append(f"{prefix}S5 Task158 DSA=@0 回归")
    if 'config[@"customGLVersion"] = @40;' not in text:
        fails.append(f"{prefix}S5 customGLVersion=@40 回归")
    if 'config[@"maxGlslCacheSize"] = @128;' not in text:
        fails.append(f"{prefix}S5 maxGlslCacheSize=@128 回归")
    if 'setenv("MOBILEGL_ESPRYT_MULTIDRAW_MODE", "drawelements", 1);' not in text:
        fails.append(f"{prefix}S5 Task156 drawelements 回归")
    # S8 日志锚
    if "[JavaLauncher] Task469: MobileGL perf knobs applied" not in text:
        fails.append(f"{prefix}S8 日志锚缺失")
    # S9 编译序：helper 定义必须在 init_loadDefaultEnv 定义之前
    helper_pos = text.find("static NSString *ame468_pref_string")
    caller_pos = text.find("void init_loadDefaultEnv()")
    if helper_pos < 0 or caller_pos < 0 or helper_pos > caller_pos:
        fails.append(f"{prefix}S9 ame468_pref_string 必须定义于 init_loadDefaultEnv 之前")
    # 幽灵变量零引入（限定实调用：setenv/getenv；注释里枚举上游新变量名是
    # 有意的教学面，不算引入——r0 假阳复盘）
    for name in GHOST_ENVS:
        if has_real_setenv(text, name) or has_real_getenv(text, name):
            fails.append(f"{prefix}S2 幽灵变量实调用引入: {name}（vendored dylib 不支持）")


def main():
    if "--selftest" in sys.argv:
        return selftest()
    fails = []
    text = JL.read_text(encoding="utf-8", errors="replace")

    # S1/S3/S4/S5/S8/S9
    check_source(text, fails)

    # S2 二进制反锚（★Task475 载体迁移：vendored dylib 出包，反锚载体 =
    # renderer-repo 在线插件包内 libmobileglues.dylib——同一 GIT@8df5508 构建）
    import zipfile as _zipfile
    ZIP_MG = ROOT / "renderer-repo" / "plugins" / "mobileglues-dev-1.0.0.zip"
    strs = None
    if not ZIP_MG.is_file():
        fails.append("S2 renderer-repo 插件包缺失")
    else:
        with _zipfile.ZipFile(ZIP_MG) as _z:
            if "libmobileglues.dylib" not in _z.namelist():
                fails.append("S2 插件包内 dylib 缺席")
            else:
                _probe = ROOT / "build" / "ame468_dylib_probe.dylib"
                _probe.parent.mkdir(exist_ok=True)
                _probe.write_bytes(_z.read("libmobileglues.dylib"))
                strs = dylib_strings(_probe)
                _probe.unlink(missing_ok=True)
        if strs is None:
            fails.append("S2 插件包 dylib 字符串表不可解析")
    if strs is not None:
        blob = "\n".join(strs)
        for name in APPLIED_ENVS:
            if name not in blob:
                fails.append(f"S2 二进制反锚失败（插件包 dylib 无此变量）: {name}")
        for name in GHOST_ENVS:
            if name in blob:
                # dylib 自己有的名字反而进 GHOST 清单 = 清单配置错（双保险反向校验）
                fails.append(f"S2 GHOST 清单配置矛盾（dylib 实际支持）: {name}")

    # S10 升代产物代际锚（★Task475 载体迁移：指纹沿袭执法对象 =
    # renderer-repo 插件包 dylib——vendored 出包后在线资产必须同源同指纹）
    import hashlib as _hashlib
    import zipfile as _zipfile2
    ZIP_MG2 = ROOT / "renderer-repo" / "plugins" / "mobileglues-dev-1.0.0.zip"
    if ZIP_MG2.is_file():
        _pkgdylib = ROOT / "build" / "ame468_s10_dylib_probe.dylib"
        _pkgdylib.parent.mkdir(exist_ok=True)
        with _zipfile2.ZipFile(ZIP_MG2) as _z2:
            _pkgdylib.write_bytes(_z2.read("libmobileglues.dylib"))
        _sz = _pkgdylib.stat().st_size
        if _sz != 16447088:
            fails.append(f"S10 插件包 dylib 尺寸漂移 {_sz} != 16447088")
        _sha = _hashlib.sha256(_pkgdylib.read_bytes()).hexdigest()
        if not _sha.startswith("fd907f655061aaa9"):
            fails.append(f"S10 插件包 dylib sha256 漂移 {_sha[:16]}…")
        _blob = "\n".join(dylib_strings(_pkgdylib) or [])
        if "GIT@8df5508" not in _blob:
            fails.append("S10 插件包 dylib 无 GIT@8df5508 标记（未换装？）")
        if "GIT@874b9e8" in _blob:
            fails.append("S10 旧代标记残留（GIT@874b9e8）")
        _pkgdylib.unlink(missing_ok=True)
    else:
        fails.append("S10 renderer-repo 插件包缺失")
    # ★Task479 回植翻转：vendored dylib/PROVENANCE 在场指纹（Task475 出包
    #   判例反悔——现代 MC 开箱基线；Task469 升代 Witch fork 8df5508 语义）
    if not DYLIB_MG.exists():
        fails.append("S10 vendored libMobileGL.dylib 应在场（Task479 回植）")
    elif DYLIB_MG.stat().st_size != 16447088:
        fails.append(f"S10 vendored 尺寸漂移 {DYLIB_MG.stat().st_size} != 16447088")
    _prov = ROOT / "Natives" / "resources" / "Frameworks" / "libMobileGL.PROVENANCE.md"
    if not _prov.exists():
        fails.append("S10 vendored PROVENANCE 应在场（Task479 回植）")
    if DYLIB_MVK.exists():
        if DYLIB_MVK.stat().st_size != 14769224:
            fails.append(f"S10 MoltenVK 尺寸漂移 {DYLIB_MVK.stat().st_size} != 14769224")
        _msha = _hashlib.sha256(DYLIB_MVK.read_bytes()).hexdigest()
        if not _msha.startswith("3378bf8d6fd1e5bd"):
            fails.append(f"S10 MoltenVK sha256 漂移 {_msha[:16]}…")

    # S7 MVK 反锚
    if not has_real_setenv(text, "MVK_CONFIG_USE_METAL_ARGUMENT_BUFFERS"):
        fails.append("S7 MVK 参数缓冲开关缺失")
    mvk_strs = dylib_strings(DYLIB_MVK)
    if mvk_strs is None:
        fails.append("S7 libMoltenVK.dylib 不存在，无法反锚")
    else:
        if "MVK_CONFIG_USE_METAL_ARGUMENT_BUFFERS" not in "\n".join(mvk_strs):
            fails.append("S7 MVK 二进制反锚失败")

    # S6 折叠面零污染（工作树零 diff）
    try:
        dirty = subprocess.run(
            ["git", "status", "--porcelain", "--"] + FOLDING_SURFACE,
            cwd=ROOT, capture_output=True, text=True, timeout=30).stdout.strip()
        if dirty:
            fails.append(f"S6 折叠面被触碰: {dirty.splitlines()}")
    except Exception as e:
        fails.append(f"S6 git status 失败: {e}")

    # S 代际锚（轻校验；完整执法在 task439_buildtag_anchor.py）
    tag = BUILD_TAG.read_text(encoding="utf-8", errors="replace")
    if 'ame415_buildTag = @"Task482 · ' not in tag:
        fails.append("S BuildTag 未进代 Task479")

    if fails:
        print(f"[FAIL] task468_selfcheck {len(fails)} 项:")
        for f in fails:
            print("  -", f)
        return 1
    print(f"[PASS] task468_selfcheck: S1-S10 全绿 "
          f"({len(APPLIED_ENVS)} 个 MOBILEGL_* setenv 反锚 + {len(GHOST_ENVS)} 幽灵变量零引入 + 折叠面零污染)")
    return 0


def selftest():
    """反向门：合成负样本必须全部被本门的判定函数抓住。"""
    good = JL.read_text(encoding="utf-8", errors="replace")

    # 负样本 1：剥掉真 setenv 的假源 → S1 必须红
    bad1 = re.sub(r'[ \t]*setenv\("MOBILEGL_MAGMA_FRAMESINFLIGHT", ame468_framesBuf, 1\);\n', "", good)
    f1 = []
    check_source(bad1, f1, prefix="n1/")
    assert any("S1 setenv 缺失: MOBILEGL_MAGMA_FRAMESINFLIGHT" in x for x in f1), "n1 未咬人"

    # 负样本 1b：幽灵变量实调用注入 → S2 必须红
    bad1b = good.replace('setenv("MOBILEGL_MAGMA_FRAMESINFLIGHT", ame468_framesBuf, 1);',
                         'setenv("MOBILEGL_MAGMA_FRAMESINFLIGHT", ame468_framesBuf, 1);\n                setenv("MOBILEGL_FRAMES_IN_FLIGHT", "3", 1);')
    f1b = []
    check_source(bad1b, f1b, prefix="n1b/")
    assert any("S2 幽灵变量实调用引入" in x for x in f1b), "n1b 未咬人"

    # 负样本 2：二进制里不存在的变量名 → S2 反锚必须红
    strs = dylib_strings(DYLIB_MG)
    blob = "\n".join(strs) if strs else ""
    assert "MOBILEGL_NOT_PRESENT_XYZ" not in blob, "n2 合成名居然在场"

    # 负样本 3：默认值被改的假源 → S3 必须红
    bad3 = good.replace("if (ame468_frames <= 0) ame468_frames = 3;",
                        "if (ame468_frames <= 0) ame468_frames = 2;")
    f3 = []
    check_source(bad3, f3, prefix="n3/")
    assert any("S3 三缓冲默认 3 缺失" in x for x in f3), "n3 未咬人"

    # 负样本 4：helper 挪到调用点之后 → S9 必须红
    helper_block_start = good.find("// Task468：mobilegl.* 偏好归一化读取器")
    helper_block_end = good.find("}\n", good.find("static NSString *ame468_pref_string")) + 2
    helper_block = good[helper_block_start:helper_block_end]
    bad4 = good.replace(helper_block, "", 1)
    f4 = []
    check_source(bad4, f4, prefix="n4/")
    assert any("S9" in x for x in f4), "n4 未咬人"

    print("[PASS] task468_selfcheck --selftest: 5 组合成负样本全部被咬（门活着）")
    return 0


if __name__ == "__main__":
    sys.exit(main())
