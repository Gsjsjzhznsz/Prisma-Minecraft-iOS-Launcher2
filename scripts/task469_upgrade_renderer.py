#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Task469 真正升级渲染器 —— libMobileGL.dylib 升代换装 + 幽灵三旋钮转正 + 门禁/代际重锚。

升代内容（用户钦定「继续优化和真正的升级渲染器」）：
  1. Natives/resources/Frameworks/libMobileGL.dylib:
       874b9e8@2026-09-05 (85757760B, Amethyst 线, e7a8043b…)
       → GIT@8df5508@2026-10-16 (16447088B, Witch fork Ynnyny/MobileGL-fix, fd907f65…)
     自带修复面: MC26.3 几何/UI 间歇损坏修复 + VMA 块尺寸配置 + iOS loader/EGL
     修复 + MetalANGLE GLES32 shim。
  2. libMoltenVK.dylib 配套对同轮换装（4904816B → 14769224B, Vulkan 1.4 SDK 面）。
  3. 幽灵三旋钮转正接线（fork 源码级实锚 QueryEnvUint32/Loader.cpp getenv）:
       MOBILEGL_MAGMA_VMA_BLOCK_SIZE_MB(默认32, 钳8..256)
       MOBILEGL_LARGE_BUFFER_ADOPT_MB(默认4, 钳1..64)
       MOBILEGL_ANGLE_BACKEND(tgles|vulkan)
     + Witch 现役第四旋钮 MOBILEGL_MAGMA_R11G11B10F_FALLBACK(默认关)。
  4. ame468 门禁: 16 旋钮反锚 + 幽灵清单翻转为 MobileGL-main-26.11 更名/新增面
     (fork@8df5508 不支持) + S10 升代产物代际锚(尺寸+sha256+GIT@ 标记+出处档案互证)。
  5. BuildTag Task469 · 2026-11-23 + 九门代际重锚。
  6. verify_task112_118 B1 尺寸锚跟进 + task469_artifact_verify 新产物验证门。
  7. 产物出处档案 libMobileGL.PROVENANCE.md。
"""
import hashlib
import re
import shutil
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
WITCH = Path("/home/z/my-project/repo-witch")
FW = ROOT / "Natives" / "resources" / "Frameworks"

SRC_MG = WITCH / "Natives/resources/Frameworks/libMobileGL.dylib"
SRC_MVK = WITCH / "Natives/resources/Frameworks/libMoltenVK.dylib"
DST_MG = FW / "libMobileGL.dylib"
DST_MVK = FW / "libMoltenVK.dylib"
PROV = FW / "libMobileGL.PROVENANCE.md"

# 期望的升代产物指纹（换装前强校验，杜绝拿错文件）
EXP_MG_SHA = "fd907f655061aaa9"
EXP_MG_SIZE = 16447088
EXP_MVK_SHA = "3378bf8d6fd1e5bd"
EXP_MVK_SIZE = 14769224

JL = ROOT / "Natives" / "JavaLauncher.m"

fails = []
def step(name, ok, detail=""):
    print(("PASS " if ok else "FAIL ") + name + (f" -- {detail}" if detail else ""))
    if not ok:
        fails.append(name)


def sha256_prefix(p, n=16):
    h = hashlib.sha256()
    with open(p, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()[:n]


def replace_once(text, old, new, label):
    cnt = text.count(old)
    if cnt != 1:
        step(f"replace {label}", False, f"anchor count={cnt} (期望 1)，中止该文件")
        return text, False
    return text.replace(old, new, 1), True


# ─────────────────────────────────────────────────────────────
# 1. dylib 换装（先验指纹）
# ─────────────────────────────────────────────────────────────
mg_sha = sha256_prefix(SRC_MG)
mvk_sha = sha256_prefix(SRC_MVK)
step("src libMobileGL.dylib 指纹", SRC_MG.stat().st_size == EXP_MG_SIZE and mg_sha == EXP_MG_SHA,
     f"{SRC_MG.stat().st_size}B {mg_sha}")
step("src libMoltenVK.dylib 指纹", SRC_MVK.stat().st_size == EXP_MVK_SIZE and mvk_sha == EXP_MVK_SHA,
     f"{SRC_MVK.stat().st_size}B {mvk_sha}")

mg_full = None
mvk_full = None
if not fails:
    h = hashlib.sha256(SRC_MG.read_bytes()).hexdigest(); mg_full = h
    shutil.copyfile(SRC_MG, DST_MG)
    DST_MG.chmod(0o644)
    h2 = hashlib.sha256(SRC_MVK.read_bytes()).hexdigest(); mvk_full = h2
    shutil.copyfile(SRC_MVK, DST_MVK)
    DST_MVK.chmod(0o644)
    step("dylib 换装落位", DST_MG.stat().st_size == EXP_MG_SIZE and DST_MVK.stat().st_size == EXP_MVK_SIZE)

# ─────────────────────────────────────────────────────────────
# 2. 出处档案
# ─────────────────────────────────────────────────────────────
if not fails:
    PROV.write_text(f"""# libMobileGL.dylib / libMoltenVK.dylib 产物出处档案（Task469）

- 升级轮：Task469 · 2026-11-23（用户钦定「继续优化和真正的升级渲染器」）
- libMobileGL.dylib
  - sha256: `{mg_full}`
  - size: {EXP_MG_SIZE} B（旧代 e7a8043b… = 85757760 B 未剥离构建，同轮退役）
  - 构建: GIT@8df5508 · Timestamp 2026-10-16T06:50:27 · vulkan-sdk-1.4.321.0-49-g07244428 基线
  - 来源: Ynnyny/MobileGL-fix（Witch-Launcher 的 MobileGL fork）@ 8df55081
    「fix(ios): DirectGLES MetalANGLE GLES32 shim + loader/EGL iOS fixes」
    （上游 = MobileGL-Dev/MobileGL，Desktop OpenGL 4.6 over DirectVulkan/DirectGLES，
    Magma = Vulkan 后端 / Espryt = GLES 后端）
  - 自带修复面: MC 26.3 几何/UI 间歇性损坏修复（fff9d639 resident buffer ordering）+
    VMA 块尺寸配置（a5201690）+ iOS loader/EGL 修复 + MetalANGLE GLES32 shim（8df55081）
- libMoltenVK.dylib
  - sha256: `{mvk_full}`
  - size: {EXP_MVK_SIZE} B（旧代 73cb7379… = 4904816 B 同轮退役）
  - 与新 dylib 同仓配套（Vulkan 1.4 SDK 配套面），@rpath/libMoltenVK.dylib 运行时解析
- 幽灵旋钮转正: MOBILEGL_MAGMA_VMA_BLOCK_SIZE_MB（默认32，钳8..256）/
  MOBILEGL_LARGE_BUFFER_ADOPT_MB（默认4，钳1..64）/ MOBILEGL_ANGLE_BACKEND（tgles|vulkan）
  —— fork 源码级实锚（MobileGL/ConfigLoader.cpp + MG_Util/BackendLoaders/OpenGL/Loader.cpp）
- 门禁: scripts/ame468_selfcheck.py S10（尺寸 + sha256 + GIT@ 标记 + 本档案互证）；
  装机日志锚 [JavaLauncher] Task469: MobileGL perf knobs applied
- 旧代出处（留档）: Amethyst-iOS-MyRemastered vendor 线，sha256 e7a8043b…（85757760 B，
  GIT@874b9e8 · 2026-09-05T02:34:22）
""", encoding="utf-8")
    step("产物出处档案", PROV.exists() and mg_full[:16] in PROV.read_text(encoding="utf-8"))

# ─────────────────────────────────────────────────────────────
# 3. JavaLauncher.m 手术（动态切片，防空白失配）
# ─────────────────────────────────────────────────────────────
if not fails:
    text = JL.read_text(encoding="utf-8", errors="replace")

    start_marker = "            // Task468：MobileGL/Magma 引擎级性能旋钮层（抄 Witch-Launcher 渲染调优面，"
    nslog_marker = 'NSLog(@"[JavaLauncher] Task468: MobileGL perf knobs applied'
    end_token = "backend);"
    i0 = text.find(start_marker)
    i1 = text.find(nslog_marker)
    ok = i0 >= 0 and i1 > i0
    i2 = text.find(end_token, i1) + len(end_token) if ok else -1
    step("JavaLauncher 切片定位", ok and i2 > i1)
    if ok:
        old_block = text[i0:i2]
        # 切片内容自证：12 个 setenv 名 + Task468 日志锚必须都在切片内
        names12 = ["MOBILEGL_MAGMA_FRAMESINFLIGHT", "MOBILEGL_ASYNC_SHADER_COMPILE",
                   "MOBILEGL_SHADER_CACHE", "MOBILEGL_COHERENT_AS_FLUSH",
                   "MOBILEGL_DISABLE_TIMERQUERY", "MOBILEGL_ADVERTISE_FP64",
                   "MOBILEGL_DISABLE_TEXTURE_VIEW", "MOBILEGL_ENABLE_SPIRV_VALIDATION",
                   "MOBILEGL_DISABLE_LARGE_BUFFER_ADOPTION", "MOBILEGL_MAGMA_DISABLE_SUBGROUP",
                   "MOBILEGL_MAGMA_MULTIDRAW_MODE", "MOBILEGL_ASYNC_SHADER_COMPILE_THREADS",
                   "MOBILEGL_ASYNC_OPTIMISTIC_SHADER_STATUS"]
        step("切片自证(13 setenv + Task468 锚)",
             all(f'setenv("{n}"' in old_block for n in names12) and "Task468: MobileGL perf knobs applied" in old_block)
        new_block = '''            // Task468：MobileGL/Magma 引擎级性能旋钮层（抄 Witch-Launcher 渲染调优面，
            // 用户钦定「渲染性能很好,赶紧抄点过来」）。Task469 渲染器真正升代（用户钦定
            // 「继续优化和真正的升级渲染器」）：libMobileGL.dylib 由 Amethyst 线
            // 874b9e8@2026-09-05（85757760B 未剥离）换装 Witch fork Ynnyny/MobileGL-fix
            // GIT@8df5508@2026-10-16 构建（16447088B，vulkan-sdk-1.4.321 基线，自带
            // MC26.3 几何/UI 间歇损坏修复 + VMA 块尺寸配置 + iOS loader/EGL 修复 +
            // MetalANGLE GLES32 shim），libMoltenVK.dylib 配套对同轮换装。升代后
            // 上游 26.11 才有的三变量在 fork dylib strings 实证在场，幽灵清单翻转
            // 转正接线：MOBILEGL_MAGMA_VMA_BLOCK_SIZE_MB（默认 32，钳 8..256）/
            // MOBILEGL_LARGE_BUFFER_ADOPT_MB（默认 4，钳 1..64）/ MOBILEGL_ANGLE_BACKEND
            // （tgles|vulkan，GLES+ANGLE 路径消费，Vulkan 档惰性）+ Witch 现役第四旋钮
            // MOBILEGL_MAGMA_R11G11B10F_FALLBACK（默认关）。对齐 Witch 现役
            // MobileGLConfig.m 姿态（fork 源码级实锚：ConfigLoader QueryEnvUint32 +
            // Loader.cpp getenv）。MAGMA_* 仅 Vulkan 直连档有意义；ES（DirectGLES）
            // 档引擎自动忽略。偏好全部 plist-only（mobilegl.* 分区，零 UI 行）。
            {
                BOOL ame468_vulkanTier = (strcmp(backend, "DirectVulkan") == 0);
                NSInteger ame468_frames = getPrefInt(@"mobilegl.frames_in_flight");
                if (ame468_frames <= 0) ame468_frames = 3;   // Witch 默认三缓冲
                char ame468_framesBuf[16];
                snprintf(ame468_framesBuf, sizeof(ame468_framesBuf), "%ld", (long)ame468_frames);
                setenv("MOBILEGL_MAGMA_FRAMESINFLIGHT", ame468_framesBuf, 1);
                // 异步着色器编译：fork dylib QueryEnvQuirkOverride truthy 解析兼容
                // 0/1（On/Off/Auto 三态是 Witch 上层语义），默认 1 = 广播
                // GL_KHR_parallel_shader_compile + 编译线程池，shaderpack/世界加载期
                // 重叠编译（对齐 Witch 姿态）；仅字符串 "0" 显式关。
                NSString *ame468_async = ame468_pref_string(@"mobilegl.async_shader_compile");
                BOOL ame468_asyncOn = !(ame468_async && [ame468_async isEqualToString:@"0"]);
                setenv("MOBILEGL_ASYNC_SHADER_COMPILE", ame468_asyncOn ? "1" : "0", 1);
                // 着色器缓存：无默认（引擎原生行为），仅用户显式偏好时透传。
                NSString *ame468_cache = ame468_pref_string(@"mobilegl.shader_cache");
                if (ame468_cache && [ame468_cache length]) {
                    setenv("MOBILEGL_SHADER_CACHE", ame468_cache.UTF8String, 1);
                }
                // host-coherent 直信（Apple 统一内存真连贯，省 flush 往返；Witch 姿态）
                setenv("MOBILEGL_COHERENT_AS_FLUSH",
                       getPrefBool(@"mobilegl.coherent_as_flush") ? "1" : "0", 1);
                setenv("MOBILEGL_DISABLE_TIMERQUERY",
                       getPrefBool(@"mobilegl.disable_timer_query") ? "1" : "0", 1);
                setenv("MOBILEGL_ADVERTISE_FP64",
                       getPrefBool(@"mobilegl.advertise_fp64") ? "1" : "0", 1);
                setenv("MOBILEGL_DISABLE_TEXTURE_VIEW",
                       getPrefBool(@"mobilegl.disable_texture_view") ? "1" : "0", 1);
                setenv("MOBILEGL_ENABLE_SPIRV_VALIDATION",
                       getPrefBool(@"mobilegl.enable_spirv_validation") ? "1" : "0", 1);
                setenv("MOBILEGL_DISABLE_LARGE_BUFFER_ADOPTION",
                       getPrefBool(@"mobilegl.disable_large_buffer_adoption") ? "1" : "0", 1);
                if (ame468_vulkanTier) {
                    setenv("MOBILEGL_MAGMA_DISABLE_SUBGROUP",
                           getPrefBool(@"mobilegl.disable_subgroup") ? "1" : "0", 1);
                    // Magma multidraw 档位仅显式偏好透传（Vulkan 档装机验证正常，
                    // Task156 口径不触碰 ES 档）。
                    NSString *ame468_mgMulti = ame468_pref_string(@"mobilegl.magma_multidraw_mode");
                    if (ame468_mgMulti && [ame468_mgMulti length]) {
                        setenv("MOBILEGL_MAGMA_MULTIDRAW_MODE", ame468_mgMulti.UTF8String, 1);
                    }
                }
                NSString *ame468_threads = ame468_pref_string(@"mobilegl.async_shader_compile_threads");
                if (ame468_threads && [ame468_threads intValue] > 0) {
                    char ame468_threadsBuf[16];
                    snprintf(ame468_threadsBuf, sizeof(ame468_threadsBuf), "%ld", (long)[ame468_threads intValue]);
                    setenv("MOBILEGL_ASYNC_SHADER_COMPILE_THREADS", ame468_threadsBuf, 1);
                }
                if (getPrefBool(@"mobilegl.async_optimistic_shader_status")) {
                    setenv("MOBILEGL_ASYNC_OPTIMISTIC_SHADER_STATUS", "1", 1);
                }
                // Task469：幽灵三旋钮转正 + Witch 现役第四旋钮（升代后 strings 反锚全场）
                NSInteger ame468_vma = getPrefInt(@"mobilegl.vma_block_size");
                if (ame468_vma <= 0) ame468_vma = 32;   // fork 默认 32MB VMA 大块堆
                char ame468_vmaBuf[16];
                snprintf(ame468_vmaBuf, sizeof(ame468_vmaBuf), "%ld", (long)ame468_vma);
                setenv("MOBILEGL_MAGMA_VMA_BLOCK_SIZE_MB", ame468_vmaBuf, 1);
                NSInteger ame468_adopt = getPrefInt(@"mobilegl.large_buffer_adopt_size");
                if (ame468_adopt <= 0) ame468_adopt = 4;   // fork 默认 4MB GPU 常驻收养阈值
                char ame468_adoptBuf[16];
                snprintf(ame468_adoptBuf, sizeof(ame468_adoptBuf), "%ld", (long)ame468_adopt);
                setenv("MOBILEGL_LARGE_BUFFER_ADOPT_MB", ame468_adoptBuf, 1);
                // ANGLE 后端（DirectGLES 档的 ANGLE 装载路径消费；默认 TGLES）
                NSString *ame468_angle = ame468_pref_string(@"mobilegl.angle_backend");
                setenv("MOBILEGL_ANGLE_BACKEND",
                       (ame468_angle && [ame468_angle isEqualToString:@"vulkan"]) ? "vulkan" : "tgles", 1);
                // Magma R11G11B10F 格式回退（Witch 现役姿态，默认关）
                setenv("MOBILEGL_MAGMA_R11G11B10F_FALLBACK",
                       getPrefBool(@"mobilegl.r11g11b10f_fallback") ? "1" : "0", 1);
                NSLog(@"[JavaLauncher] Task469: MobileGL perf knobs applied (Witch dylib GIT@8df5508): frames=%ld async=%d coherent=%d timerQ=%d fp64=%d texview=%d spirvV=%d lba=%d vma=%ld adopt=%ld angle=%s r11=%d tier=%s",
                      (long)ame468_frames, ame468_asyncOn ? 1 : 0,
                      getPrefBool(@"mobilegl.coherent_as_flush") ? 1 : 0,
                      getPrefBool(@"mobilegl.disable_timer_query") ? 1 : 0,
                      getPrefBool(@"mobilegl.advertise_fp64") ? 1 : 0,
                      getPrefBool(@"mobilegl.disable_texture_view") ? 1 : 0,
                      getPrefBool(@"mobilegl.enable_spirv_validation") ? 1 : 0,
                      getPrefBool(@"mobilegl.disable_large_buffer_adoption") ? 1 : 0,
                      (long)ame468_vma, (long)ame468_adopt,
                      getenv("MOBILEGL_ANGLE_BACKEND") ? getenv("MOBILEGL_ANGLE_BACKEND") : "tgles",
                      getPrefBool(@"mobilegl.r11g11b10f_fallback") ? 1 : 0,
                      backend);
            }'''
        text = text[:i0] + new_block + text[i2:]

    # unsetenv 对称清偿 +4
    mvk_line = '            unsetenv("MVK_CONFIG_USE_METAL_ARGUMENT_BUFFERS");'
    add4 = ('            unsetenv("MOBILEGL_MAGMA_VMA_BLOCK_SIZE_MB");\n'
            '            unsetenv("MOBILEGL_LARGE_BUFFER_ADOPT_MB");\n'
            '            unsetenv("MOBILEGL_ANGLE_BACKEND");\n'
            '            unsetenv("MOBILEGL_MAGMA_R11G11B10F_FALLBACK");\n')
    text, ok = replace_once(text, mvk_line, add4 + mvk_line, "unsetenv +4 插入")
    step("JavaLauncher unsetenv 对称", ok)

    if ok and not fails:
        JL.write_text(text, encoding="utf-8")
        step("JavaLauncher.m 回写", True)

# ─────────────────────────────────────────────────────────────
# 4. BuildTag + 九门代际重锚
# ─────────────────────────────────────────────────────────────
if not fails:
    GEN_FILES = ["task451", "task452", "task457", "task461", "task462",
                 "task464", "task465", "task466", "task467"]
    bt = ROOT / "Natives" / "BuildTag.h"
    t = bt.read_text(encoding="utf-8", errors="replace")
    t, ok = replace_once(t, 'ame415_buildTag = @"Task468 · 2026-11-23"',
                         'ame415_buildTag = @"Task469 · 2026-11-23"', "BuildTag 进代")
    step("BuildTag.h 回写", ok and bt.write_text(t, encoding="utf-8") is None)

    for name in GEN_FILES:
        p = ROOT / "scripts" / f"{name}_selfcheck.py"
        t = p.read_text(encoding="utf-8", errors="replace")
        n = t.count("Task468 · 2026-11-23")
        t = t.replace("Task468 · 2026-11-23", "Task469 · 2026-11-23")
        p.write_text(t, encoding="utf-8")
        step(f"代际重锚 {name} ({n} 处)", n >= 1)

print()
if fails:
    print(f"[ABORT] {len(fails)} 步失败: {fails}")
    sys.exit(1)
print("[PASS] Task469 升代手术全部落位（dylib×2 + 出处档案 + JavaLauncher + BuildTag + 九门重锚）")
