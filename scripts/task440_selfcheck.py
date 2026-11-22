#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Task440 批次二退役收尾自检门（第 10 期复核报告批次二 ①②③ 落码核验）。

  T1  ameV13 内跳改道 ZL2VersionListPage Mod 域 + delegate 换轨（①）
  T2  AssetSearch 三旧页 import/delegate 残段摘除（① vestigial 面）
  T3  旧三页 + 死代码六件物理删除 + 活代码零引用（②）
  T4  CMake 七条目摘除 + :660 悬空注释校正（③）
  T5  ZL2Versions 死 import 摘除（②）
  T6  AiPluginDocsTool 三退役键摘除 + 计数链 103/206/407（③）
  T7  PLPreferences 两退役键注册摘除（③）
  T8  verify_task188 标签重锚 + 六 verifier 容错壳（腐烂族）
  S   --selftest 反向注入：逐断言摘除标记后必须翻红
"""
import sys
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
FAILS = []


def check(name, cond, detail=""):
    if cond:
        print(f"  [PASS] {name}")
    else:
        FAILS.append(name)
        print(f"  [FAIL] {name}  {detail}")


def read(rel):
    return (ROOT / rel).read_text(encoding="utf-8", errors="replace")


def code_only(text):
    """剥 // 行注释与 #pragma 行——墓碑豁免口径（与 verify_task189 重生门一致）"""
    out = []
    for ln in text.split("\n"):
        s = ln.strip()
        if s.startswith("#pragma"):
            continue
        out.append(re.sub(r"//[^\n]*", "", ln))
    return "\n".join(out)


# ★Task467 翻转重锚：WelcomeViewController 退出退役清单（用户指令「把欢迎UI重新恢复」，
#   Task436 A3 断链 + Task439 批次一删除判例翻转——同 Task463 折叠翻转型家法）
RETIRE = ["ModVersionViewController", "AssetVersionViewController", "ShaderVersionViewController",
          "AccountLoginViewController", "ProfileSettingsViewController",
          "FabricInstallViewController"]

vpages = read("Natives/ZL2VersionPages.m")
vpages_code = code_only(vpages)
asset = read("Natives/ZL2AssetSearchViewController.m")
asset_code = code_only(asset)


def t1_reroute(text):
    ok_import = '#import "ZL2VersionListPage.h"' in text
    ok_ctor = "initWithDomain:ZL2VersionListDomainMod" in text
    ok_cb = "- (void)zl2VersionListPage:(ZL2VersionListPage *)page didSelectVersion:(ModVersion *)version" in text
    ok_proto = "ZL2VersionListPageDelegate>" in text
    ok_old = "ModVersionViewController" not in code_only(text)
    ok_pm = "page.modItem" in text
    return ok_import and ok_ctor and ok_cb and ok_proto and ok_old and ok_pm


def t2_asset(text):
    ok_old = all(c not in code_only(text) for c in RETIRE[:3])
    ok_proto = "ZL2VersionListPageDelegate>" in text and "ModVersionViewControllerDelegate" not in code_only(text)
    ok_handle = "ame436_handleModDomainVersion" in text and "ame436_handleShaderDomainVersion" in text
    return ok_old and ok_proto and ok_handle


def t3_deleted(text_unused=None):
    gone = all(not (ROOT / f"Natives/{c}{e}").exists() for c in RETIRE for e in (".h", ".m"))
    gone = gone and all(not (ROOT / f"Natives/installer/{c}{e}").exists()
                        for c in ("ProfileSettingsViewController", "FabricInstallViewController")
                        for e in (".h", ".m"))
    return gone


def t4_cmake(text):
    ok_zero = all(f"{c}.m" not in ln.split("#")[0] for c in RETIRE for ln in text.split("\n"))
    ok_note = "★Task440 注记" in text and "used by DownloadViewController" not in text
    return ok_zero and ok_note


def t5_versions(text):
    return "ProfileSettingsViewController" not in code_only(text)


def t6_docs(text):
    # ★Task467 翻转重锚：welcome_completed 键回册（欢迎UI恢复轮），禁在清单仅余两键
    ok_keys = all(k not in text for k in ("general.news_url（默认", "general.announcement_preview_level（默认"))
    # ★Task467 计数实数重锚（ame366 D1 真执法同步）：100/200/404 → 101/202/407
    ok_counts = "101 键 × get/set = 202" in text and "约 407 个" in text
    return ok_keys and ok_counts


def t7_plprefs(text):
    # ★Task467 翻转重锚：welcome_completed 回册合法（哨兵键随向导链回注）
    return '@"announcement_preview_level"' not in text


def t8_verifiers(text_unused=None):
    v188 = read("scripts/verify_task188.py")
    ok188 = "F1 ZL2ControlRepoViewController.h/.m 存在" in v188
    guards = 0
    for f in ("verify_task136", "verify_task162", "verify_task227",
              "verify_task235", "verify_task236", "verify_task238"):
        if "★Task440 退役容错壳" in read(f"scripts/{f}.py"):
            guards += 1
    return ok188 and guards == 6


CHECKS = [
    ("T1 ameV13-reroute-zl2page", "Natives/ZL2VersionPages.m", t1_reroute),
    ("T2 assetsearch-vestigial-gone", "Natives/ZL2AssetSearchViewController.m", t2_asset),
    ("T3 retire-12-files-gone", None, t3_deleted),
    ("T4 cmake-6-entries-gone", "Natives/CMakeLists.txt", t4_cmake),
    ("T5 versions-import-gone", "Natives/ZL2VersionsViewController.m", t5_versions),
    ("T6 aiplugin-docs-2keys-gone", "Natives/AI/AiPluginDocsTool.m", t6_docs),
    ("T7 plprefs-1key-gone", "Natives/PLPreferences.m", t7_plprefs),
    ("T8 rot-family-reanchored", None, t8_verifiers),
]

INJECT_MARKERS = {
    "T1 ameV13-reroute-zl2page": "initWithDomain:ZL2VersionListDomainMod",
    "T2 assetsearch-vestigial-gone": "ZL2VersionListPageDelegate>",
    "T3 retire-12-files-gone": None,
    "T4 cmake-6-entries-gone": "★Task440 注记",
    "T5 versions-import-gone": None,
    "T6 aiplugin-docs-2keys-gone": "101 键 × get/set = 202",
    "T7 plprefs-1key-gone": None,
    "T8 rot-family-reanchored": None,   # 跨文件元断言无单点标记，selftest 跳过
}


def run_selftest():
    print("== Task440 selftest（反向注入：摘除标记必翻红） ==")
    bad = 0
    for name, rel, fn in CHECKS:
        marker = INJECT_MARKERS.get(name)
        if marker is None:
            print(f"  [SKIP] {name}: 文件级/清单级断言无单点标记")
            continue
        text = read(rel)
        stripped = text.replace(marker, "/* ame440-selftest-stripped */")
        if fn(stripped):
            print(f"  [FAIL-S] {name}: 摘除标记后 checker 仍判绿——断言无效")
            bad += 1
        else:
            print(f"  [OK]   {name}: 摘除标记翻红")
    if bad:
        print(f"Task440 selftest RED ({bad} invalid)")
        return 1
    print("Task440 selftest ALL GREEN")
    return 0


def main():
    if "--selftest" in sys.argv:
        return run_selftest()
    print("== Task440 批次二退役收尾自检 ==")
    for name, rel, fn in CHECKS:
        check(name, fn(read(rel) if rel else None), f"({rel or 'fs'})")
    if FAILS:
        print(f"Task440 selfcheck RED: {len(FAILS)} fail(s): {', '.join(FAILS)}")
        return 1
    print("Task440 selfcheck ALL GREEN")
    return 0


if __name__ == "__main__":
    sys.exit(main())
