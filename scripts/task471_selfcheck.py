#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Task471 门：NeoForge processor 保环盲区收口（mclo.gs/MnPXaJV 装机判例制度化）。

病历：装机 9b3f4d4（Task470 构建）latestlog = mclo.gs/MnPXaJV——
  [JavaLauncher] Task158: library gate clean (71 present, 69 skipped)
  → FML 死于实例轴 instances/modrinth_9BACE99E.../libraries/net/minecraft/client/
    26.3-1/client-26.3-1-srg.jar 缺失 → minecraft/neoforge 双 [MISSING] 28 条依赖
  → "Your NeoForge installation is corrupted." → JVM exit(1)。

根因三盲：① 双根脱节（门查 POJAV_GAME_DIR 基础根、FML 查启动链解析 gameDir 实例轴根，
且旧调用点在 gameDir 解析之前）② child-only 扫描（不走近 Task428 同款 inheritsFrom 链）
③ processor 三类 classifier 的 URL 豁免（官方 maven 从不发布，URL 即黑洞）。

门面断言：
  A1 门签名 launchGameDir 显式传参；A2 旧单参调用归零；
  A3 调用点位于 ame287 收口之后、Task428 preLaunchCheck 之前（位置执法）；
  A4 库根优先 launchGameDir + POJAV_GAME_DIR 兜底；
  A5 链三件 statics（versionChainFrom/mergedLibraries/collectMissing）+ guard 8；
  A6 URL 豁免撤销（旧豁免 continue 字面量归零 + 本地生成语义注释在场）；
  A7 搁浅源补基础根（ame471_baseRoot）；
  A8 链合并 collect 恰两处（初扫 + Tier A 复扫）；
  A9 Tier B mainGameDir 换 launchGameDir 口径；
  A10 Task463 折叠面零污染（≥38 组）；A11 BuildTag Task480 · 2026-11-27；
  A12 括号平衡（ame_bracket_audit 状态机）。
selftest：负样本注入（签名回退单参 / collect 单处化）必须翻红。
"""
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
JL = ROOT / "Natives" / "JavaLauncher.m"
BT = ROOT / "Natives" / "BuildTag.h"


def run_checks(jl: str, tag: str) -> list:
    fails = []

    def check(name: str, cond, msg: str) -> None:
        if not cond:
            fails.append(f"{name}: {msg}")

    check("A1", "static BOOL ame158_repairMissingLibraries(NSDictionary *launchTarget, "
                "NSString *launchGameDir) {" in jl, "门签名缺 launchGameDir 显式传参")
    check("A2", "ame158_repairMissingLibraries(launchTarget)" not in jl.replace(
        "ame158_repairMissingLibraries(launchTarget, gameDir)", ""), "旧单参调用残留")
    call_idx = jl.find("if (!ame158_repairMissingLibraries(launchTarget, gameDir)) {")
    check("A3", call_idx != -1
          and call_idx > jl.find("ame287_configureForgeUriSafeRoot(ame287_vid, gameDir);")
          and call_idx < jl.find("preLaunchCheckForCurrentProfile"),
          "调用点位置漂移（须在 ame287 收口后、Task428 前）")
    check("A4", '[launchGameDir stringByAppendingPathComponent:@"libraries"]' in jl
          and '[@(ame158_gameDir) stringByAppendingPathComponent:@"libraries"]' in jl,
          "库根双口径缺失")
    check("A5", "ame471_versionChainFrom" in jl and "ame471_mergedLibraries" in jl
          and "ame471_collectMissing" in jl and "ame471_guard++ < 8" in jl,
          "链合并三件 statics 缺件")
    check("A6", "continue;   // 有 URL：一号门 URL 补链已覆盖，不属本环" not in jl
          and "本地生成产物（官方 maven 从不发布）" in jl,
          "URL 豁免未撤销或语义注释缺失")
    check("A7", "ame471_baseRoot" in jl and 'getenv("POJAV_GAME_DIR")' in jl, "搁浅源基础根缺失")
    check("A8", jl.count("ame471_collectMissing(launchTarget, gameDir, libRoot)") == 2,
          "链合并 collect 须恰两处（初扫+复扫）")
    check("A9", "launchGameDir.length > 0 ? launchGameDir : @(ame158_gameDir)" in jl,
          "Tier B mainGameDir 口径未换")
    fold = 0
    for ff in (ROOT / "Natives" / "ZL2SettingPages.m", ROOT / "Natives" / "ZL2SettingCards.m",
               ROOT / "Natives" / "ZL2SettingCards.h"):
        fold += ff.read_text(encoding="utf-8").count("defaultCollapsed:")
    check("A10", fold >= 41, f"Task463 折叠面污染（HEAD 基线 42 → ★Task472 重锚 -1 = 41，实测 {fold}）")
    check("A11", f'ame415_buildTag = @"Task480 · 2026-11-27"' in tag, "BuildTag 未进代 Task472")
    return fails


def main() -> int:
    jl = run_jl = (JL).read_text(encoding="utf-8")
    tag = BT.read_text(encoding="utf-8")

    if "--selftest" in sys.argv:
        # 负样本 1：签名回退单参（双根脱节回退形态）
        n1 = run_jl.replace(
            "static BOOL ame158_repairMissingLibraries(NSDictionary *launchTarget, "
            "NSString *launchGameDir) {",
            "static BOOL ame158_repairMissingLibraries(NSDictionary *launchTarget) {")
        f1 = run_checks(n1, tag)
        # 负样本 2：collect 单处化（复扫丢失）
        n2 = run_jl.replace(
            "ame471_collectMissing(launchTarget, gameDir, libRoot);   // 重新收集（Task471 链合并口径同初扫）",
            "ame467_missingProcessorArtifacts(launchTarget, libRoot);")
        f2 = run_checks(n2, tag)
        ok = ("A1" in "".join(f1)) and ("A8" in "".join(f2))
        print(f"selftest 负样本1 翻红={bool(f1)} 命中A1={'A1' in ''.join(f1)}；"
              f"负样本2 翻红={bool(f2)} 命中A8={'A8' in ''.join(f2)}")
        print("task471_selftest ALL GREEN" if ok else "task471_selftest RED")
        return 0 if ok else 1

    fails = run_checks(run_jl, tag)
    fold = sum(ff.read_text(encoding="utf-8").count("defaultCollapsed:")
               for ff in (ROOT / "Natives" / "ZL2SettingPages.m",
                          ROOT / "Natives" / "ZL2SettingCards.m",
                          ROOT / "Natives" / "ZL2SettingCards.h"))
    audit = subprocess.run(
        ["python3", str(ROOT / "scripts" / "ame_bracket_audit.py"), "Natives/JavaLauncher.m"],
        cwd=ROOT, capture_output=True, text=True, timeout=120)
    if audit.returncode != 0:
        fails.append("A12: 括号状态机审计红")
    if fails:
        for f in fails:
            print(f"[FAIL] {f}")
        print("task471_selfcheck RED")
        return 1
    print(f"task471_selfcheck ALL GREEN（A1-A11 + 括号审计；折叠面 {fold} 锚保形）")
    return 0


if __name__ == "__main__":
    sys.exit(main())
