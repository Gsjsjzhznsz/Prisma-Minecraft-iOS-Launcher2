#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Task469 门禁升代 —— ame468 自检门扩展（16 旋钮 + 幽灵清单翻转 + S10 升代产物代际锚）
+ verify_task112_118 B1 尺寸锚跟进 + 电池头注登记。

前置断言（写门之前先把物理事实钉死）：
  P1 新 dylib strings：16 个 APPLIED 名全在场；
  P2 新 dylib strings：8 个新幽灵名（MobileGL main 26.11 线更名/新增面）全不在场；
  P3 新 dylib 含 GIT@8df5508 且不含 GIT@874b9e8。
"""
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DY = ROOT / "Natives" / "resources" / "Frameworks" / "libMobileGL.dylib"

APPLIED = ["MOBILEGL_MAGMA_FRAMESINFLIGHT", "MOBILEGL_ASYNC_SHADER_COMPILE",
           "MOBILEGL_COHERENT_AS_FLUSH", "MOBILEGL_DISABLE_TIMERQUERY",
           "MOBILEGL_ADVERTISE_FP64", "MOBILEGL_DISABLE_TEXTURE_VIEW",
           "MOBILEGL_ENABLE_SPIRV_VALIDATION", "MOBILEGL_DISABLE_LARGE_BUFFER_ADOPTION",
           "MOBILEGL_MAGMA_DISABLE_SUBGROUP", "MOBILEGL_MAGMA_MULTIDRAW_MODE",
           "MOBILEGL_ASYNC_SHADER_COMPILE_THREADS", "MOBILEGL_ASYNC_OPTIMISTIC_SHADER_STATUS",
           "MOBILEGL_MAGMA_VMA_BLOCK_SIZE_MB", "MOBILEGL_LARGE_BUFFER_ADOPT_MB",
           "MOBILEGL_ANGLE_BACKEND", "MOBILEGL_MAGMA_R11G11B10F_FALLBACK"]
GHOST = ["MOBILEGL_FRAMES_IN_FLIGHT", "MOBILEGL_SUBGROUP_EMULATION", "MOBILEGL_ITRP_FIX",
         "MOBILEGL_MAGMA_MAX_DRAWS_PER_COMMAND_BUFFER", "MOBILEGL_MAGMA_DESCRIPTOR_TRIM_FRAMES",
         "MOBILEGL_MAGMA_EXTRA_SWAPCHAIN_IMAGES", "MOBILEGL_SERVER_FRAME_STATS",
         "MOBILEGL_ESPRYT_YUV_DRIVER_CONVERSION"]

fails = []
def step(name, ok, detail=""):
    print(("PASS " if ok else "FAIL ") + name + (f" -- {detail}" if detail else ""))
    if not ok:
        fails.append(name)


def replace_once(text, old, new, label):
    cnt = text.count(old)
    if cnt != 1:
        step(f"replace {label}", False, f"anchor count={cnt} (期望 1)")
        return text, False
    return text.replace(old, new, 1), True


def dylib_strings(path):
    out, cur = [], bytearray()
    for b in path.read_bytes():
        if 32 <= b < 127:
            cur.append(b)
        else:
            if len(cur) >= 6:
                out.append(cur.decode("ascii", "ignore"))
            cur = bytearray()
    if len(cur) >= 6:
        out.append(cur.decode("ascii", "ignore"))
    return out


# ── 前置物理断言 ─────────────────────────────────────────────
blob = "\n".join(dylib_strings(DY))
step("P1 16 APPLIED 名 dylib 全在场", all(n in blob for n in APPLIED),
     ", ".join(n for n in APPLIED if n not in blob))
step("P2 8 GHOST 名 dylib 全不在场", all(n not in blob for n in GHOST),
     ", ".join(n for n in GHOST if n in blob))
step("P3 GIT@ 代际标记", "GIT@8df5508" in blob and "GIT@874b9e8" not in blob)

# ── ame468_selfcheck.py 手术 ─────────────────────────────────
if not fails:
    G = ROOT / "scripts" / "ame468_selfcheck.py"
    t = G.read_text(encoding="utf-8", errors="replace")

    # docstring 头注
    t, ok = replace_once(
        t,
        "内置渲染器上游更新扫描轮。\n",
        "内置渲染器上游更新扫描轮。Task469 轮扩展：dylib 升代换装（Witch fork GIT@8df5508）\n"
        "+ 幽灵三旋钮转正 + 16 旋钮面 + S10 升代产物代际锚。\n",
        "docstring 头注")
    # docstring S2 段
    if ok:
        t, ok = replace_once(
            t,
            "  S2  二进制反锚：每个被应用的 MOBILEGL_* 变量名必须真的存在于\n"
            "      Natives/resources/Frameworks/libMobileGL.dylib 的字符串表——vendored\n"
            "      二进制不支持的变量（上游 26.11 才加的 VMA_BLOCK_SIZE_MB /\n"
            "      LARGE_BUFFER_ADOPT_MB / ANGLE_BACKEND）必须在源码零引入（幽灵变量防再犯，\n"
            "      Task439 幽灵门同族判例）；",
            "  S2  二进制反锚：每个被应用的 MOBILEGL_* 变量名必须真的存在于\n"
            "      Natives/resources/Frameworks/libMobileGL.dylib 的字符串表（Task469 升代后 =\n"
            "      Witch fork GIT@8df5508 构建，16 旋钮全支持）——上游 MobileGL main 26.11 线\n"
            "      的更名/新增变量（FRAMES_IN_FLIGHT 新名 / SUBGROUP_EMULATION / ITRP_FIX /\n"
            "      MAGMA_MAX_DRAWS_PER_COMMAND_BUFFER / MAGMA_DESCRIPTOR_TRIM_FRAMES /\n"
            "      MAGMA_EXTRA_SWAPCHAIN_IMAGES / SERVER_FRAME_STATS / ESPRYT_YUV_DRIVER_CONVERSION）\n"
            "      在本 dylib 不存在，必须源码零引入（幽灵变量防再犯，Task439 幽灵门同族判例）；",
            "docstring S2 段")
    # docstring S10 段
    if ok:
        t, ok = replace_once(
            t,
            "  S9  偏好归一化读取器 ame468_pref_string 定义于首个调用点之前（编译序防线，\n"
            "      本轮 r0 复盘：初版 helper 定义在 init_loadDefaultEnv 之后即隐式声明雷）。",
            "  S9  偏好归一化读取器 ame468_pref_string 定义于首个调用点之前（编译序防线，\n"
            "      本轮 r0 复盘：初版 helper 定义在 init_loadDefaultEnv 之后即隐式声明雷）。\n"
            "  S10 升代产物代际锚（Task469）：libMobileGL.dylib 尺寸 16447088 + sha256\n"
            "      fd907f65… 前缀 + GIT@8df5508 在场 + 旧代 GIT@874b9e8 双消 +\n"
            "      libMoltenVK.dylib 14769224/sha 3378bf8d… 前缀 + 出处档案互证。",
            "docstring S10 段")
    # APPLIED_ENVS 扩员
    if ok:
        t, ok = replace_once(
            t,
            '    "MOBILEGL_ASYNC_OPTIMISTIC_SHADER_STATUS",\n]',
            '    "MOBILEGL_ASYNC_OPTIMISTIC_SHADER_STATUS",\n'
            '    "MOBILEGL_MAGMA_VMA_BLOCK_SIZE_MB",\n'
            '    "MOBILEGL_LARGE_BUFFER_ADOPT_MB",\n'
            '    "MOBILEGL_ANGLE_BACKEND",\n'
            '    "MOBILEGL_MAGMA_R11G11B10F_FALLBACK",\n]',
            "APPLIED_ENVS 扩员")
    # GHOST_ENVS 翻转
    if ok:
        t, ok = replace_once(
            t,
            "# vendored libMobileGL.dylib（26.08-dev@874b9e8）不支持的上游新变量——源码零引入\n"
            "GHOST_ENVS = [\n"
            '    "MOBILEGL_MAGMA_VMA_BLOCK_SIZE_MB",\n'
            '    "MOBILEGL_LARGE_BUFFER_ADOPT_MB",\n'
            '    "MOBILEGL_ANGLE_BACKEND",\n'
            "]",
            "# Task469 幽灵清单翻转：VMA/ADOPT/ANGLE 三名已在 Witch fork GIT@8df5508 dylib\n"
            "# strings 实证在场并转正接线（见 APPLIED_ENVS）。本清单改为看守「上游 MobileGL\n"
            "# main 26.11 线的更名/新增变量」——fork@8df5508 构建（2026-10-16）不含它们，\n"
            "# 下轮若做 MobileGL main 源码构建升代才可解禁；防再犯判例同 Task439 幽灵门。\n"
            "GHOST_ENVS = [\n"
            '    "MOBILEGL_FRAMES_IN_FLIGHT",\n'
            '    "MOBILEGL_SUBGROUP_EMULATION",\n'
            '    "MOBILEGL_ITRP_FIX",\n'
            '    "MOBILEGL_MAGMA_MAX_DRAWS_PER_COMMAND_BUFFER",\n'
            '    "MOBILEGL_MAGMA_DESCRIPTOR_TRIM_FRAMES",\n'
            '    "MOBILEGL_MAGMA_EXTRA_SWAPCHAIN_IMAGES",\n'
            '    "MOBILEGL_SERVER_FRAME_STATS",\n'
            '    "MOBILEGL_ESPRYT_YUV_DRIVER_CONVERSION",\n'
            "]",
            "GHOST_ENVS 翻转")
    # check_source：S1 升代锚 + S3 四新默认 + S8 日志锚
    if ok:
        t, ok = replace_once(
            t,
            '    if "Task468：MobileGL/Magma 引擎级性能旋钮层" not in text:\n'
            '        fails.append(f"{prefix}S1 旋钮层注释锚缺失")',
            '    if "Task468：MobileGL/Magma 引擎级性能旋钮层" not in text:\n'
            '        fails.append(f"{prefix}S1 旋钮层注释锚缺失")\n'
            '    if "Task469 渲染器真正升代" not in text:\n'
            '        fails.append(f"{prefix}S1 Task469 升代注释锚缺失")',
            "S1 升代锚")
    if ok:
        t, ok = replace_once(
            t,
            "    if 'ame468_asyncOn ? \"1\" : \"0\"' not in text:\n"
            '        fails.append(f"{prefix}S3 异步编译默认开缺失")',
            "    if 'ame468_asyncOn ? \"1\" : \"0\"' not in text:\n"
            '        fails.append(f"{prefix}S3 异步编译默认开缺失")\n'
            '    if "if (ame468_vma <= 0) ame468_vma = 32;" not in text:\n'
            '        fails.append(f"{prefix}S3 VMA 块默认 32 缺失")\n'
            '    if "if (ame468_adopt <= 0) ame468_adopt = 4;" not in text:\n'
            '        fails.append(f"{prefix}S3 收养阈值默认 4 缺失")\n'
            '    if \'] ? "vulkan" : "tgles", 1)\' not in text:\n'
            '        fails.append(f"{prefix}S3 ANGLE 后端默认 tgles 缺失")\n'
            '    if \'getPrefBool(@"mobilegl.r11g11b10f_fallback") ? "1" : "0"\' not in text:\n'
            '        fails.append(f"{prefix}S3 R11G11B10F 默认关缺失")',
            "S3 四新默认")
    if ok:
        t, ok = replace_once(
            t,
            '    if "[JavaLauncher] Task468: MobileGL perf knobs applied" not in text:\n'
            '        fails.append(f"{prefix}S8 日志锚缺失")',
            '    if "[JavaLauncher] Task469: MobileGL perf knobs applied" not in text:\n'
            '        fails.append(f"{prefix}S8 日志锚缺失")',
            "S8 日志锚 Task469")
    # main() S10 块 + 代际锚
    if ok:
        t, ok = replace_once(
            t,
            "    # S7 MVK 反锚",
            "    # S10 升代产物代际锚（Task469：dylib 换装校验）\n"
            "    import hashlib as _hashlib\n"
            "    if DYLIB_MG.exists():\n"
            "        _sz = DYLIB_MG.stat().st_size\n"
            "        if _sz != 16447088:\n"
            '            fails.append(f"S10 dylib 尺寸漂移 {_sz} != 16447088")\n'
            "        _sha = _hashlib.sha256(DYLIB_MG.read_bytes()).hexdigest()\n"
            '        if not _sha.startswith("fd907f655061aaa9"):\n'
            '            fails.append(f"S10 dylib sha256 漂移 {_sha[:16]}…")\n'
            '        _blob = "\\n".join(dylib_strings(DYLIB_MG) or [])\n'
            '        if "GIT@8df5508" not in _blob:\n'
            '            fails.append("S10 dylib 无 GIT@8df5508 标记（未换装？）")\n'
            '        if "GIT@874b9e8" in _blob:\n'
            '            fails.append("S10 dylib 旧代标记残留（GIT@874b9e8）")\n'
            '        _prov = ROOT / "Natives" / "resources" / "Frameworks" / "libMobileGL.PROVENANCE.md"\n'
            "        if not _prov.exists():\n"
            '            fails.append("S10 产物出处档案缺失")\n'
            "        else:\n"
            '            _ptext = _prov.read_text(encoding="utf-8", errors="replace")\n'
            '            if "fd907f655061aaa9" not in _ptext or "3378bf8d6fd1e5bd" not in _ptext:\n'
            '                fails.append("S10 出处档案指纹不符")\n'
            "    else:\n"
            '        fails.append("S10 libMobileGL.dylib 不存在")\n'
            "    if DYLIB_MVK.exists():\n"
            "        if DYLIB_MVK.stat().st_size != 14769224:\n"
            '            fails.append(f"S10 MoltenVK 尺寸漂移 {DYLIB_MVK.stat().st_size} != 14769224")\n'
            "        _msha = _hashlib.sha256(DYLIB_MVK.read_bytes()).hexdigest()\n"
            '        if not _msha.startswith("3378bf8d6fd1e5bd"):\n'
            '            fails.append(f"S10 MoltenVK sha256 漂移 {_msha[:16]}…")\n'
            "\n"
            "    # S7 MVK 反锚",
            "S10 块插入")
    if ok:
        t, ok = replace_once(
            t,
            "    if 'ame415_buildTag = @\"Task468 · ' not in tag:\n"
            '        fails.append("S BuildTag 未进代 Task468")',
            "    if 'ame415_buildTag = @\"Task469 · ' not in tag:\n"
            '        fails.append("S BuildTag 未进代 Task469")',
            "S 代际锚 Task469")
    if ok:
        t, ok = replace_once(
            t,
            'print(f"[PASS] task468_selfcheck: S1-S9 全绿 "',
            'print(f"[PASS] task468_selfcheck: S1-S10 全绿 "',
            "PASS 消息")
    # selftest n1b 幽灵样本换靶（VMA 已转正，换 FRAMES_IN_FLIGHT 新名陷阱）
    if ok:
        t, ok = replace_once(
            t,
            "'setenv(\"MOBILEGL_MAGMA_FRAMESINFLIGHT\", ame468_framesBuf, 1);\\n                setenv(\"MOBILEGL_MAGMA_VMA_BLOCK_SIZE_MB\", \"32\", 1);')",
            "'setenv(\"MOBILEGL_MAGMA_FRAMESINFLIGHT\", ame468_framesBuf, 1);\\n                setenv(\"MOBILEGL_FRAMES_IN_FLIGHT\", \"3\", 1);')",
            "selftest n1b 换靶")
    if ok:
        G.write_text(t, encoding="utf-8")
        step("ame468_selfcheck.py 回写", True)

# ── verify_task112_118.py B1 尺寸锚 ──────────────────────────
if not fails:
    V = ROOT / "scripts" / "verify_task112_118.py"
    t = V.read_text(encoding="utf-8", errors="replace")
    t, ok = replace_once(
        t,
        'check("B1 libMobileGL.dylib 已 vendor（上游 caf6822 同款 85757760B）",\n'
        "      os.path.exists(dylib) and os.path.getsize(dylib) == 85757760)",
        'check("B1 libMobileGL.dylib 已 vendor（Task469 升代 Witch fork 8df5508 同款 16447088B）",\n'
        "      os.path.exists(dylib) and os.path.getsize(dylib) == 16447088)",
        "B1 尺寸锚")
    if ok:
        V.write_text(t, encoding="utf-8")
        step("verify_task112_118.py 回写", True)

# ── 电池头注登记 ─────────────────────────────────────────────
if not fails:
    B = ROOT / "scripts" / "task432_gate_battery.sh"
    t = B.read_text(encoding="utf-8", errors="replace")
    t, ok = replace_once(
        t,
        "#   Task468 轮 = 48 门（+ame468 MobileGL 旋钮门 + selftest 反向门）\n",
        "#   Task468 轮 = 48 门（+ame468 MobileGL 旋钮门 + selftest 反向门）\n"
        "#   Task469 轮 = 48 门（ame468 门内扩展：16 旋钮 + 幽灵清单翻转 + S10 升代产物代际锚；门数不变）\n",
        "电池头注")
    if ok:
        B.write_text(t, encoding="utf-8")
        step("task432_gate_battery.sh 回写", True)

print()
if fails:
    print(f"[ABORT] {len(fails)} 步失败: {fails}")
    sys.exit(1)
print("[PASS] Task469 门禁升代全部落位")
