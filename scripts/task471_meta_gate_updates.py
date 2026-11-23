#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Task471 元面：BuildTag 进代 + 十门代际重锚 + task467 R8/R14 适配 +
verify_task158 C3 适配 + 电池登记（50→52）+ task471_selfcheck.py 落地。"""
import sys
from pathlib import Path

ROOT = Path("/home/z/my-project/repo-l2")
OLD_TAG = "Task470 · 2026-11-23"
NEW_TAG = "Task473 · 2026-11-24"


def rd(p: Path) -> str:
    return p.read_text(encoding="utf-8")


def wr(p: Path, s: str) -> None:
    p.write_text(s, encoding="utf-8")


def swap(path: Path, min_expect: int) -> None:
    s = rd(path)
    if NEW_TAG in s and OLD_TAG not in s:
        print(f"  {path.name}: 已进代（幂等跳过）")
        return
    n = s.count(OLD_TAG)
    if n < min_expect:
        print(f"[FAIL] {path.name}: {OLD_TAG} 出现 {n} 次（下限 {min_expect}）")
        sys.exit(1)
    wr(path, s.replace(OLD_TAG, NEW_TAG))
    print(f"  {path.name}: {n} 处代际锚 → {NEW_TAG}")


def meta() -> None:
    # ── BuildTag 进代（幂等：已进代则跳过） ──
    bt = ROOT / "Natives" / "BuildTag.h"
    s = rd(bt)
    if f'ame415_buildTag = @"{NEW_TAG}"' in s:
        print("  BuildTag.h → 已进代（幂等跳过）")
    elif f'ame415_buildTag = @"{OLD_TAG}"' in s:
        wr(bt, s.replace(f'ame415_buildTag = @"{OLD_TAG}"', f'ame415_buildTag = @"{NEW_TAG}"'))
        print("  BuildTag.h → " + NEW_TAG)
    else:
        print("[FAIL] BuildTag.h 无现行代际锚")
        sys.exit(1)

    # ── 十门 + artifact verify 代际重锚 ──
    swap(ROOT / "scripts" / "task451_selfcheck.py", 2)
    swap(ROOT / "scripts" / "task452_selfcheck.py", 2)
    swap(ROOT / "scripts" / "task457_selfcheck.py", 2)
    swap(ROOT / "scripts" / "task461_selfcheck.py", 1)
    swap(ROOT / "scripts" / "task462_selfcheck.py", 1)
    swap(ROOT / "scripts" / "task464_selfcheck.py", 2)
    swap(ROOT / "scripts" / "task465_selfcheck.py", 2)
    swap(ROOT / "scripts" / "task466_selfcheck.py", 1)
    swap(ROOT / "scripts" / "task467_selfcheck.py", 2)
    swap(ROOT / "scripts" / "ame468_selfcheck.py", 0)  # 短前缀形态单独处理
    # ame468 短前缀形态
    p = ROOT / "scripts" / "ame468_selfcheck.py"
    s = rd(p)
    if "'ame415_buildTag = @\"Task470 · '" not in s:
        print("[FAIL] ame468 短前缀锚缺失")
        sys.exit(1)
    wr(p, s.replace("'ame415_buildTag = @\"Task470 · '", "'ame415_buildTag = @\"Task471 · '"))
    print("  ame468_selfcheck.py: 短前缀锚 → Task471 ·")
    swap(ROOT / "scripts" / "task470_artifact_verify.py", 2)

    # ── task467 R8 签名适配（幂等） ──
    p = ROOT / "scripts" / "task467_selfcheck.py"
    s = rd(p)
    old = "      'static BOOL ame158_repairMissingLibraries(NSDictionary *launchTarget) {' in jl"
    new = ("      'static BOOL ame158_repairMissingLibraries(NSDictionary *launchTarget, '\n"
           "          'NSString *launchGameDir) {' in jl")
    if old in s:
        if s.count(old) != 1:
            print("[FAIL] task467 R8 锚异常")
            sys.exit(1)
        s = s.replace(old, new, 1)

    # ── task467 R14 调用点适配（新形态 + 位置证明） ──
    old = (
        "check('R14 调用点中断语义（!gate → return 1，不进 JIT 等待）',\n"
        "      'if (!ame158_repairMissingLibraries(launchTarget)) {' in jl\n"
        "      and jl.find('if (!ame158_repairMissingLibraries(launchTarget)) {') < jl.find('ame158_repairMissingLibraries(launchTarget);') if 'ame158_repairMissingLibraries(launchTarget);' in jl else True,\n"
        "      '调用点仍为旧 void 调用')"
    )
    new = (
        "check('R14 调用点中断语义（!gate → return 1，Task471 gameDir 显式传根 + 终解析后位置）',\n"
        "      'if (!ame158_repairMissingLibraries(launchTarget, gameDir)) {' in jl\n"
        "      and jl.find('ame287_configureForgeUriSafeRoot(ame287_vid, gameDir);') < jl.find('if (!ame158_repairMissingLibraries(launchTarget, gameDir)) {')\n"
        "      and jl.find('if (!ame158_repairMissingLibraries(launchTarget, gameDir)) {') < jl.find('preLaunchCheckForCurrentProfile'),\n"
        "      '调用点形态/位置漂移（Task471 双根脱节回退）')"
    )
    if new in s:
        pass   # R14 已适配（幂等）
    elif s.count(old) == 1:
        s = s.replace(old, new, 1)
    else:
        print("[FAIL] task467 R14 锚异常")
        sys.exit(1)
    wr(p, s)
    print("  task467_selfcheck.py: R8/R14 适配完成")

    # ── verify_task158 C3 适配（幂等） ──
    p = ROOT / "scripts" / "verify_task158.py"
    s = rd(p)
    old = (
        '      "static void ame158_repairMissingLibraries(NSDictionary *launchTarget)" in jl\n'
        '      and "ame158_repairMissingLibraries(launchTarget);" in jl'
    )
    new = (
        '      "static BOOL ame158_repairMissingLibraries(NSDictionary *launchTarget, NSString *launchGameDir)" in jl\n'
        '      and "ame158_repairMissingLibraries(launchTarget, gameDir)" in jl'
    )
    if new in s:
        print("  verify_task158.py: C3 已适配（幂等跳过）")
    elif s.count(old) == 1:
        wr(p, s.replace(old, new, 1))
        print("  verify_task158.py: C3 适配完成")
    else:
        print("[FAIL] verify_task158 C3 锚异常")
        sys.exit(1)

    # ── 电池登记 50→52 ──
    p = ROOT / "scripts" / "task432_gate_battery.sh"
    s = rd(p)
    if "Task471 轮 = 52 门" not in s:
        old = "#     随包 + 全 Frameworks Mach-O 依赖闭包执法）\n"
        new = (
            "#     随包 + 全 Frameworks Mach-O 依赖闭包执法）\n"
            "#   Task471 轮 = 52 门（+task471 保环盲区收口门 + selftest 反向门——MnPXaJV\n"
            "#     判例：门查 POJAV_GAME_DIR 基础根 clean 而 FML 查实例轴根死于\n"
            "#     client-26.3-1-srg.jar 缺失 = 双根脱节 + child-only 扫描 + URL 豁免三盲；\n"
            "#     门调用移至 gameDir 终解析后显式传根 + inheritsFrom 链合并扫描 +\n"
            "#     processor 三类 URL 豁免撤销 + 搁浅源补基础根）\n"
        )
        if s.count(old) != 1:
            print("[FAIL] 电池头注锚异常")
            sys.exit(1)
        s = s.replace(old, new, 1)
    if "run_py task471     scripts/task471_selfcheck.py" in s:
        print("  task432_gate_battery.sh: 已登记（幂等跳过）")
        return
    old = (
        "run_py task470     scripts/task470_runtime_verify.py\n"
        "run_py task470_self scripts/task470_runtime_verify.py --selftest\n"
    )
    new = (
        "run_py task470     scripts/task470_runtime_verify.py\n"
        "run_py task470_self scripts/task470_runtime_verify.py --selftest\n"
        "\n"
        "# ★Task471 NeoForge processor 保环盲区收口（MnPXaJV 装机判例制度化）：\n"
        "#   双根脱节根修（门调用 gameDir 显式传根 + 终解析后位置执法）+\n"
        "#   链合并扫描 + URL 豁免撤销 + 搁浅源补基础根 + 链合并口径单一化\n"
        "run_py task471     scripts/task471_selfcheck.py\n"
        "run_py task471_self scripts/task471_selfcheck.py --selftest\n"
    )
    if s.count(old) != 1:
        print("[FAIL] 电池登记锚异常")
        sys.exit(1)
    s = s.replace(old, new, 1)
    wr(p, s)
    print("  task432_gate_battery.sh: 52 门登记完成")


if __name__ == "__main__":
    meta()
