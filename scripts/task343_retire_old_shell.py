#!/usr/bin/env python3
# task343_retire_old_shell.py -- 旧壳家族物理退役（Task343 线A）
# 1) git rm 十一族 22 文件（Root/CardLayout/Help/HomeCustomize/News/
#    RightPanel/Menu/Split/VersionManager/Cleanup/ModTable）
# 2) CMakeLists.txt 字节级摘条目（保留 LauncherNavigationController /
#    ModsManagerViewController / DownloadViewController 等仍被旧页深链
#    消费的面），保 LF 行尾
import io, os, subprocess

os.chdir(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))

FAMILY = [
    "LauncherRootViewController", "LauncherCardLayoutViewController",
    "LauncherHelpViewController", "HomeCustomizeViewController",
    "LauncherNewsViewController", "LauncherRightPanelViewController",
    "LauncherMenuViewController", "LauncherSplitViewController",
    "VersionManagerViewController", "CleanupViewController",
    "ModTableViewController",
]

# --- 1) 物理删除 ---
for name in FAMILY:
    for ext in (".h", ".m"):
        p = f"Natives/{name}{ext}"
        if os.path.exists(p):
            subprocess.run(["git", "rm", "-q", p], check=True)
            print("git rm", p)
        else:
            print("skip (absent)", p)

# --- 2) CMakeLists 摘条目 ---
CM = "Natives/CMakeLists.txt"
with io.open(CM, "r", encoding="utf-8", newline="") as f:
    lines = f.readlines()

kill = {f"{n}.m" for n in FAMILY}
out, removed = [], []
for ln in lines:
    if ln.strip() in kill:
        removed.append(ln.strip())
        continue
    out.append(ln)

# 幂等：条目已摘除（前轮已跑）则跳过写入
if removed:
    assert len(removed) == len(FAMILY), f"expected {len(FAMILY)} entries, removed {len(removed)}: {removed}"
    with io.open(CM, "w", encoding="utf-8", newline="") as f:
        f.writelines(out)
    print(f"CMakeLists: removed {len(removed)} entries; {len(lines)} -> {len(out)} lines")
else:
    out = lines
    print("CMakeLists: entries already removed (idempotent pass)")

# --- 3) 自检：保留面仍在 CMake、退役面无编译条目 ---
body = "".join(out)
for keep in ("LauncherNavigationController.m", "ModsManagerViewController.m",
             "ProfileSettingsViewController.m", "DownloadViewController.m",
             "ModService.m", "ModTableViewCell.m"):
    assert keep in body, f"unexpectedly missing keep entry {keep}"
for n in FAMILY:
    # 编译条目 = 非注释行的缩进源文件项；注释提及（如 FCL 注）不算残留
    for ln in out:
        code = ln.split("#")[0].split("//")[0]
        assert n not in code, f"residual CMake code entry {n}: {ln.strip()[:70]}"
# 全库活代码引用终检（注释豁免）
for n in FAMILY:
    r = subprocess.run(["git", "grep", "-l", n, "--", "Natives/*.m", "Natives/*.h",
                        "Natives/Preview/*.m"],
                       capture_output=True, text=True).stdout.strip()
    hits = []
    for fpath in r.splitlines():
        with io.open(fpath, "r", encoding="utf-8", newline="") as f:
            for idx, ln in enumerate(f, 1):
                code_part = ln.split("//")[0]
                if n in code_part:
                    hits.append(f"{fpath}:{idx}:{ln.strip()[:70]}")
    if hits:
        print(f"!! LIVE REF {n}:")
        for h in hits[:8]:
            print("   ", h)
print("done")
