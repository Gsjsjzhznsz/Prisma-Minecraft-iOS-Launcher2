#!/usr/bin/env python3
# ame329_selfcheck.py -- Task329 门禁（版本轴统一三线断言制）
#   ① 数据搬家 pass（ModService ame329_unifyInstanceDataIntoVersionAxis）
#   ② 交互面守卫（ame327 物化版本轴形态守卫 / ame324 接线次序）
#   ③ 换装流对齐（ModpackImportService absoluteGameDirForModpackId profile 优先）
#   ④ CI r1 热修（SurfaceViewController.h 跨文件 selector 声明）
import io, os, sys

REPO = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
fails = []
passed = 0

def rd(p):
    with io.open(os.path.join(REPO, p), "r", encoding="utf-8") as f:
        return f.read()

def check(name, cond, detail=""):
    global passed
    if cond:
        passed += 1
        print(f"  ✓ {name}")
    else:
        fails.append(name)
        print(f"  ✗ {name} {detail}")

print("== ① 数据搬家 pass ==")
ms = rd("Natives/ModService.m")
check("ame329 pass 方法在位", "+ (void)ame329_unifyInstanceDataIntoVersionAxis" in ms)
check("递归并入助手在位", "static BOOL ame329_moveEntry" in ms)
check("实例根两层判据（防深层/自定义目录误伤）",
      "rangeOfString:@\"/\"].location != NSNotFound" in ms)
check("符号链接形态跳过（NSFileTypeSymbolicLink）",
      "ame329_attrs[NSFileType] isEqualToString:NSFileTypeSymbolicLink" in ms)
check("版本目录真身判据（marker json）",
      "ame329_marker" in ms and "fileExistsAtPath:ame329_marker" in ms)
check("共享层排除集（versions/assets/libraries）",
      '@"versions", @"assets", @"libraries"' in ms)
check("导入元数据排除（import_report.json/.ame269_backup/custom_gamedir）",
      '@"import_report.json", @".ame269_backup", @"custom_gamedir"' in ms)
check("隐藏条目跳过", "if ([ame329_item hasPrefix:@\".\"]) continue;" in ms)
check("冲突绝不覆盖（ame329-<ts> 改名并置）",
      "%@.ame329-%@" in ms)
check("搬空摘壳（left.count == 0 才 remove）",
      "left.count == 0) [fm removeItemAtPath:src error:nil]" in ms)
check("gameDir 重指走 applyChanges 锁内 API",
      "[PLProfiles.current applyChanges:^" in ms)
check("重指条件 = 搬移≥1 或 根净+版本目录有内容",
      "ame329_needRep = (ame329_moved > 0) || (ame329_pending.count == 0 && ame329_vdirHasData)" in ms)
check("日志锚点（unified into version axis）",
      "instance data unified into version axis" in ms)

print("== ② 交互面守卫 ==")
check("ame324 接线（统一先行）",
      "[ModService ame329_unifyInstanceDataIntoVersionAxis];" in ms)
check("接线位于 ame324 骨架循环之前（次序断言）",
      ms.index("ame329_unifyInstanceDataIntoVersionAxis];") <
      ms.index("ame324_ensureIsolationSkeletonForVersionId:ame324_vd];"))
check("ame327 物化版本轴形态守卫（嵌套 versions 垃圾排除）",
      "ame327_vIdx - 2" in ms and "ame327_comps indexOfObject:@\"versions\"" in ms)
check("ame328 清扫 pass 未被绕过（仍在 ame324 尾）",
      "[ModService ame328_pruneDecoyVersionSkeletons];" in ms)
check("ame325 实例轴 pass 未被绕过",
      "[ModService ame325_ensureInstanceAxisSkeletons];" in ms)

print("== ③ 换装流对齐 ==")
mpi = rd("Natives/ModpackImportService.m")
check("absoluteGameDirForModpackId profile 优先（ame329 注记）",
      "已有实例 profile 的 gameDir 优先" in mpi)
check("归属判据 = instances/<modpackId> 前缀",
      "ame329_rootPrefix" in mpi and "hasPrefix:ame329_rootPrefix" in mpi)
check("无命中回落旧口径（全新导入不变）",
      mpi.count("stringByAppendingPathComponent:modpackId]") == 2)
check("非绝对 gameDir 跳过（isAbsolutePath）",
      "![ame329_gd isAbsolutePath]") if False else check("非绝对 gameDir 跳过（isAbsolutePath）",
      "isAbsolutePath" in mpi)

print("== ④ CI r1 热修 ==")
svh = rd("Natives/SurfaceViewController.h")
check("ame328_applyResolutionInSession 声明在位",
      "- (BOOL)ame328_applyResolutionInSession:(CGFloat)ame328_res;" in svh)
sv = rd("Natives/SurfaceViewController.m")
check("实现与声明签名一致（返回 BOOL）",
      "- (BOOL)ame328_applyResolutionInSession:(CGFloat)ame328_res {" in sv)
nav = rd("Natives/SurfaceViewController+Navigation.m")
check("Navigation 跨文件调用点在位",
      "[self ame328_applyResolutionInSession:" in nav)

print(f"\n{passed} passed, {len(fails)} failed")
if fails:
    print("FAILED:", *fails, sep="\n  - ")
    sys.exit(1)
print("ALL GREEN")
