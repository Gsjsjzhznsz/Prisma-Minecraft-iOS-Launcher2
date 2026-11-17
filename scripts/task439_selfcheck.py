#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Task439 批次一热修自检门（第 10 期复核报告批次一 ①②④⑤ 落码核验）。

覆盖面：
  A1  ModpackImportService Modrinth parse 层 name 判类收窄（P0 候选 ①）
  A2  ModpackImportService CurseForge parse 层 name 判类收窄（同族喂入）
  A3  ZL2AssetSearchViewController :3744 消费侧判类兜底 + title 收窄
  A4  ModpackUtils ame439 取消旗标变体（E4 ④）：槽入口 + 双端点切换双检
  A5  ModpackExportService 改走 ame439 带取消块（服务层即查即退维持）
  A6  ZL2HomeViewController profileListDidChange Task337 式防御钳制（⑤）
  A7  电池幽灵门（②）：run_sh 已定义 + task158_base 声明在列
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


def t1_modrinth_name_narrow(text):
    ok_marker = 'ame439_rawName = indexDict[@"name"]' in text
    ok_guard = ("[ame439_rawName isKindOfClass:[NSString class]]" in text
                and "stringByDeletingPathExtension" in text)
    ok_version = 'ame439_rawVersion = indexDict[@"versionId"]' in text
    ok_no_raw = re.search(
        r'NSString \*name = indexDict\[@"name"\] \?:', text) is None
    return ok_marker and ok_guard and ok_version and ok_no_raw


def t2_curseforge_name_narrow(text):
    ok_marker = 'ame439_rawName = manifestDict[@"name"]' in text
    ok_guard = "[ame439_rawName isKindOfClass:[NSString class]]" in text
    ok_no_raw = re.search(
        r'NSString \*name = manifestDict\[@"name"\] \?:', text) is None
    return ok_marker and ok_guard and ok_no_raw


def t3_assetsearch_consumer(text):
    ok_val = "ame439_nameVal" in text and "ame439_titleVal" in text
    ok_guard = "![ame439_nameVal isKindOfClass:[NSString class]]" in text
    ok_no_raw = re.search(
        r'\[mutableInfo\[@"name"\] isEqualToString:', text) is None
    ok_title = ("[ame439_titleVal isKindOfClass:[NSString class]]" in text)
    return ok_val and ok_guard and ok_no_raw and ok_title


def t4_utils_cancel_variant(text):
    ok_decl = "ame439_modrinthDownloadURLsForFiles:" in text \
        and "isCancelledBlock:(BOOL (^)(void))isCancelled" in text
    ok_checks = text.count("if (isCancelled && isCancelled()) {") >= 2
    ok_delegate = re.search(
        r"ame439_modrinthDownloadURLsForFiles:[\s\S]{0,200}?isCancelledBlock:nil\]",
        text) is not None
    return ok_decl and ok_checks and ok_delegate


def t5_service_call(text):
    ok_call = "ame439_modrinthDownloadURLsForFiles:modFiles" in text
    ok_block = "isCancelledBlock:^BOOL{" in text
    ok_cancel = "checkCancelledWithError:NULL" in text
    ok_no_old = "ame428_modrinthDownloadURLsForFiles:modFiles" not in text
    return ok_call and ok_block and ok_cancel and ok_no_old


def t6_home_clamp(text):
    m = re.search(
        r"- \(void\)profileListDidChange \{([\s\S]*?)\n\}", text)
    if not m:
        return False
    body = m.group(1)
    return ("![NSThread isMainThread]" in body
            and "dispatch_async(dispatch_get_main_queue()" in body
            and "__weak typeof(self) weakSelf = self;" in body
            and "[weakSelf profileListDidChange]" in body)


def t7_battery_run_sh(text):
    ok_def = re.search(r"^run_sh\(\) \{", text, re.M) is not None
    ok_decl = "run_sh task158_base scripts/task158_baseline_compare.sh" in text
    ok_hdr = "run_sh 补定义" in text
    return ok_def and ok_decl and ok_hdr


CHECKS = [
    ("A1 modrinth-parse-name-narrow", "Natives/ModpackImportService.m", t1_modrinth_name_narrow),
    ("A2 curseforge-parse-name-narrow", "Natives/ModpackImportService.m", t2_curseforge_name_narrow),
    ("A3 assetsearch-consumer-guard", "Natives/ZL2AssetSearchViewController.m", t3_assetsearch_consumer),
    ("A4 utils-cancel-variant", "Natives/installer/modpack/ModpackUtils.m", t4_utils_cancel_variant),
    ("A5 service-calls-ame439", "Natives/ModpackExportService.m", t5_service_call),
    ("A6 home-observer-clamp", "Natives/ZL2HomeViewController.m", t6_home_clamp),
    ("A7 battery-run-sh-defined", "scripts/task432_gate_battery.sh", t7_battery_run_sh),
]

# S 反向注入：每条断言的「必在标记」，selftest 摘除后 checker 必须翻红
INJECT_MARKERS = {
    "A1 modrinth-parse-name-narrow": 'ame439_rawName = indexDict[@"name"]',
    "A2 curseforge-parse-name-narrow": 'ame439_rawName = manifestDict[@"name"]',
    "A3 assetsearch-consumer-guard": "ame439_nameVal",
    "A4 utils-cancel-variant": "ame439_modrinthDownloadURLsForFiles:",
    "A5 service-calls-ame439": "ame439_modrinthDownloadURLsForFiles:modFiles",
    "A6 home-observer-clamp": "![NSThread isMainThread]",
    "A7 battery-run-sh-defined": "run_sh task158_base scripts/task158_baseline_compare.sh",
}


def run_selftest():
    print("== Task439 selftest（反向注入：摘除标记必翻红） ==")
    bad = 0
    for name, rel, fn in CHECKS:
        text = read(rel)
        marker = INJECT_MARKERS.get(name)
        stripped = text.replace(marker, "/* ame439-selftest-stripped */")
        if fn(stripped):
            print(f"  [FAIL-S] {name}: 摘除标记后 checker 仍判绿——断言无效")
            bad += 1
        else:
            print(f"  [OK]   {name}: 摘除标记翻红")
    if bad:
        print(f"Task439 selftest RED ({bad} invalid)")
        return 1
    print("Task439 selftest ALL GREEN")
    return 0


def main():
    if "--selftest" in sys.argv:
        return run_selftest()
    print("== Task439 批次一热修自检 ==")
    for name, rel, fn in CHECKS:
        text = read(rel)
        check(name, fn(text), f"({rel})")
    if FAILS:
        print(f"Task439 selfcheck RED: {len(FAILS)} fail(s): {', '.join(FAILS)}")
        return 1
    print("Task439 selfcheck ALL GREEN")
    return 0


if __name__ == "__main__":
    sys.exit(main())
