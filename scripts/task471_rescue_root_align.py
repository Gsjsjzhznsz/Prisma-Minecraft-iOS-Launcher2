#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Task471 —— NeoForge processor 保环盲区收口（mclo.gs/MnPXaJV 装机判例定谳闭环）。

病历（装机 9b3f4d4 = Task470 构建，iPad Air M4 / iPadOS 27.0.1 / LiveContainer guest）：
  [JavaLauncher] Task158: library gate clean (71 present, 69 skipped)
  → [ERROR] Failed to find required file
    .../instances/modrinth_9BACE99E-.../libraries/net/minecraft/client/26.3-1/client-26.3-1-srg.jar
  → Missing or unsupported mandatory dependencies（minecraft/neoforge 双 [MISSING]
    28 条依赖全灭）→ "Your NeoForge installation is corrupted." → JVM exit(1)。

根因双盲区：
  ① 双根脱节——ame158/ame467 门查 getenv("POJAV_GAME_DIR")（基础根，Task226
     pre-init 只对 default 实例重指），FML 查启动链解析 gameDir（ame275/ame225
     嗅探/ame428 CwdAlign/ame287 forge 收口之后的实例轴根 = JVM chdir 根）；
     且旧调用点在 gameDir 解析之前（Task179「调用点后移」同族错位）。
  ② 扫描面 child-only + URL 豁免——ame467_missingProcessorArtifacts 只看
     launchTarget[@"libraries"]（不走近 Task428 同款 inheritsFrom 链），并对带
     downloads URL 的三类 processor 产物整条跳过（官方 maven 从不发布 srg 类
     产物，URL 形同虚设；ame158 URL 补链 404 即黑洞）。

修法（单变量原则，只动保环面）：
  E1 ame158 门签名加 launchGameDir 显式传参；
  E2 库根优先 launchGameDir（POJAV_GAME_DIR 仅兜底）；
  E3 ame467_missingProcessorArtifacts 改收链合并库数组 + 撤销三类 classifier 的
     URL 豁免（processor 产物本地生成语义，URL 不可依赖）；
  E4 搁浅源补基础游戏根（旧门口径根 = 最可能的历史产物搁浅点）；
  E5 新增 ame471_versionChainFrom / ame471_mergedLibraries / ame471_collectMissing
     （Task428 同款链展开 + 父→子组覆盖合并 + rel 去重统一收集）；
  E6 保环主入口换 collect + launch-root 日志锚；
  E7 门调用点移至 gameDir 终解析之后（ame287 收口 → Task428 之间）并显式传根；
  E9 门尾保环调用换 launchGameDir 口径（Tier B mainGameDir 同根）。

零污染断言：Task463 折叠面调用数不降、banned 面零引入、括号平衡（状态机审计）。
"""
import subprocess
import sys
from pathlib import Path

ROOT = Path("/home/z/my-project/repo-l2")
JL = ROOT / "Natives" / "JavaLauncher.m"


def rd(p: Path) -> str:
    return p.read_text(encoding="utf-8")


def must_unique(text: str, needle: str, what: str) -> None:
    n = text.count(needle)
    if n != 1:
        print(f"[FAIL] {what}: 锚点出现 {n} 次（期望恰 1）")
        sys.exit(1)


def surgery() -> None:
    jl = rd(JL)

    # ── E1 门签名 ──
    old = "static BOOL ame158_repairMissingLibraries(NSDictionary *launchTarget) {"
    new = ("static BOOL ame158_repairMissingLibraries(NSDictionary *launchTarget, "
           "NSString *launchGameDir) {")
    must_unique(jl, old, "E1 门签名锚")
    jl = jl.replace(old, new, 1)

    # ── E2 库根优先 launchGameDir ──
    old = (
        "    NSFileManager *ame158_fm = NSFileManager.defaultManager;\n"
        "    NSString *ame158_libRoot = [@(ame158_gameDir) stringByAppendingPathComponent:@\"libraries\"];"
    )
    new = (
        "    NSFileManager *ame158_fm = NSFileManager.defaultManager;\n"
        "    // ★Task471：库根对齐启动链——优先显式 launchGameDir（JVM chdir 同根，\n"
        "    //   MnPXaJV 判例：门查 POJAV_GAME_DIR 基础根 71 present 而 FML 查实例轴\n"
        "    //   根即死）；POJAV_GAME_DIR 仅兜底（无实例轴时与旧口径等价）。\n"
        "    NSString *ame158_libRoot = (launchGameDir.length > 0)\n"
        "        ? [launchGameDir stringByAppendingPathComponent:@\"libraries\"]\n"
        "        : [@(ame158_gameDir) stringByAppendingPathComponent:@\"libraries\"];"
    )
    must_unique(jl, old, "E2 库根锚")
    jl = jl.replace(old, new, 1)

    # ── E3a missingProcessorArtifacts 收链合并数组 ──
    old = (
        "static NSArray<NSDictionary *> *ame467_missingProcessorArtifacts(NSDictionary *launchTarget, NSString *libRoot) {\n"
        "    NSMutableArray *ame467_missing = [NSMutableArray array];\n"
        "    NSArray *ame467_libs = [launchTarget[@\"libraries\"] isKindOfClass:NSArray.class] ? launchTarget[@\"libraries\"] : nil;"
    )
    new = (
        "// ★Task471：入参换链合并库数组（Task428 同款 inheritsFrom 链合并，见\n"
        "//   ame471_mergedLibraries）——child-only 扫描对「条目落父辈 json」的\n"
        "//   Modrinth 导入形态天然漏报。\n"
        "static NSArray<NSDictionary *> *ame467_missingProcessorArtifacts(NSArray *libs, NSString *libRoot) {\n"
        "    NSMutableArray *ame467_missing = [NSMutableArray array];\n"
        "    NSArray *ame467_libs = [libs isKindOfClass:NSArray.class] ? libs : nil;"
    )
    must_unique(jl, old, "E3a 签名锚")
    jl = jl.replace(old, new, 1)

    # ── E3b 撤销三类 classifier 的 URL 豁免 ──
    old = (
        "        id ame467_dl = ame467_lib[@\"downloads\"];\n"
        "        if ([ame467_dl isKindOfClass:NSDictionary.class] &&\n"
        "            [ame467_dl[@\"artifact\"] isKindOfClass:NSDictionary.class] &&\n"
        "            [ame467_dl[@\"artifact\"][@\"url\"] isKindOfClass:NSString.class] &&\n"
        "            ((NSString *)ame467_dl[@\"artifact\"][@\"url\"]).length > 0) {\n"
        "            continue;   // 有 URL：一号门 URL 补链已覆盖，不属本环\n"
        "        }"
    )
    new = (
        "        // ★Task471：URL 豁免撤销——srg/client/extra 三类是 installer processor\n"
        "        //   本地生成产物（官方 maven 从不发布），json 携带的 URL 即便存在也\n"
        "        //   不可依赖（ame158 URL 补链 404 即黑洞；MnPXaJV 判例的 FML 需要\n"
        "        //   与 URL 有无无关，文件在场是唯一判据）。\n"
        "        (void)ame467_lib[@\"downloads\"];"
    )
    must_unique(jl, old, "E3b URL 豁免锚")
    jl = jl.replace(old, new, 1)

    # ── E4 搁浅源补基础游戏根 ──
    old = (
        "    NSMutableArray<NSString *> *ame467_roots = [NSMutableArray array];\n"
        "    [ame467_roots addObject:[ame467_home stringByAppendingPathComponent:@\"libraries\"]];"
    )
    new = (
        "    NSMutableArray<NSString *> *ame471_roots = [NSMutableArray array];\n"
        "    // ★Task471：基础游戏根（POJAV_GAME_DIR）列入搁浅源——旧门口径的查库根\n"
        "    //   正是它，历史安装产物最可能搁浅于此（MnPXaJV 判例：门 clean 71\n"
        "    //   present 与实例轴缺失并存的唯一自洽解释）。\n"
        "    const char *ame471_baseC = getenv(\"POJAV_GAME_DIR\");\n"
        "    if (ame471_baseC && *ame471_baseC) {\n"
        "        NSString *ame471_baseRoot = [@(ame471_baseC) stringByAppendingPathComponent:@\"libraries\"];\n"
        "        if (![ame471_roots containsObject:ame471_baseRoot]) [ame471_roots addObject:ame471_baseRoot];\n"
        "    }\n"
        "    [ame471_roots addObject:[ame467_home stringByAppendingPathComponent:@\"libraries\"]];"
    )
    must_unique(jl, old, "E4 搁浅源锚")
    jl = jl.replace(old, new, 1)
    # 同函数内旧变量名收口（roots → ame471_roots 两种引用各一处）
    old = "    for (NSString *ame467_root in ame467_roots) {"
    new = "    for (NSString *ame467_root in ame471_roots) {"
    must_unique(jl, old, "E4b 根遍历锚")
    jl = jl.replace(old, new, 1)
    old = "[ame467_roots addObject:"
    n = jl.count(old)
    if n != 2:
        print(f"[FAIL] E4c 旧根引用计数 {n}（期望 2）")
        sys.exit(1)
    jl = jl.replace(old, "[ame471_roots addObject:")
    if "ame467_roots" in jl:
        print("[FAIL] ame467_roots 残留")
        sys.exit(1)
    must_unique(jl, old, "E4b 根遍历锚")
    jl = jl.replace(old, new, 1)

    # ── E5 链合并三 helper 注入（保环主入口之前） ──
    anchor = (
        "// 保环主入口：YES = 产物齐备可继续启动；NO = 已弹窗收束（Tier B 重启链 /\n"
        "// Tier C 指引），调用方中断启动（return 1，不进 JIT 等待）\n"
        "static BOOL ame467_processorArtifactRescue(NSDictionary *launchTarget, NSString *libRoot, NSString *gameDir) {"
    )
    must_unique(jl, anchor, "E5 保环主入口锚")
    helpers = (
        "// ★Task471（R2 链展开）：inheritsFrom 链展开（chain = [子, 父, 祖父...]，\n"
        "//   Task428 PLGameIntegrityService 同款解析口径，根 = 启动链 gameDir/versions）。\n"
        "static NSArray<NSDictionary *> *ame471_versionChainFrom(NSDictionary *child, NSString *gameDir) {\n"
        "    NSMutableArray<NSDictionary *> *ame471_chain = [NSMutableArray array];\n"
        "    if (![child isKindOfClass:NSDictionary.class]) return ame471_chain;\n"
        "    [ame471_chain addObject:child];\n"
        "    NSString *ame471_versionsRoot = [gameDir stringByAppendingPathComponent:@\"versions\"];\n"
        "    NSString *ame471_cursor = [child[@\"inheritsFrom\"] isKindOfClass:NSString.class]\n"
        "        ? child[@\"inheritsFrom\"] : nil;\n"
        "    NSInteger ame471_guard = 0;\n"
        "    while (ame471_cursor.length > 0 && ame471_guard++ < 8) {\n"
        "        NSString *ame471_parentPath = [[ame471_versionsRoot stringByAppendingPathComponent:ame471_cursor]\n"
        "            stringByAppendingPathComponent:[NSString stringWithFormat:@\"%@.json\", ame471_cursor]];\n"
        "        NSDictionary *ame471_parent = [NSJSONSerialization JSONObjectWithData:\n"
        "            [NSData dataWithContentsOfFile:ame471_parentPath] options:0 error:nil];\n"
        "        if (![ame471_parent isKindOfClass:NSDictionary.class]) {\n"
        "            NSLog(@\"[JavaLauncher] Task471: inheritsFrom parent JSON unreadable (%@) -- chain truncated\", ame471_parentPath);\n"
        "            break;\n"
        "        }\n"
        "        [ame471_chain addObject:ame471_parent];\n"
        "        ame471_cursor = [ame471_parent[@\"inheritsFrom\"] isKindOfClass:NSString.class]\n"
        "            ? ame471_parent[@\"inheritsFrom\"] : nil;\n"
        "    }\n"
        "    return ame471_chain;\n"
        "}\n"
        "\n"
        "// ★Task471（R2 链合并）：从最父辈向子辈收敛，子辈同组覆盖（组键 = name 的\n"
        "//   最后冒号前段，Task428 库合并同语义，杜绝父辈同组条目遮蔽子辈覆盖）。\n"
        "static NSArray<NSDictionary *> *ame471_mergedLibraries(NSDictionary *launchTarget, NSString *gameDir) {\n"
        "    NSArray<NSDictionary *> *ame471_chain = ame471_versionChainFrom(launchTarget, gameDir);\n"
        "    NSMutableArray<NSDictionary *> *ame471_merged = [NSMutableArray array];\n"
        "    for (NSInteger ame471_i = (NSInteger)ame471_chain.count - 1; ame471_i >= 0; ame471_i--) {\n"
        "        NSArray *ame471_arr = [ame471_chain[ame471_i][@\"libraries\"] isKindOfClass:NSArray.class]\n"
        "            ? ame471_chain[ame471_i][@\"libraries\"] : nil;\n"
        "        for (NSDictionary *ame471_lib in ame471_arr) {\n"
        "            if (![ame471_lib isKindOfClass:NSDictionary.class]) continue;\n"
        "            NSString *ame471_name = [ame471_lib[@\"name\"] isKindOfClass:NSString.class]\n"
        "                ? ame471_lib[@\"name\"] : nil;\n"
        "            if (ame471_name.length == 0) continue;\n"
        "            NSRange ame471_colon = [ame471_name rangeOfString:@\":\" options:NSBackwardsSearch];\n"
        "            if (ame471_colon.location == NSNotFound || ame471_colon.location == 0) continue;\n"
        "            NSString *ame471_group = [ame471_name substringToIndex:ame471_colon.location];\n"
        "            BOOL ame471_replaced = NO;\n"
        "            for (NSUInteger ame471_j = 0; ame471_j < ame471_merged.count; ame471_j++) {\n"
        "                NSString *ame471_existing = [ame471_merged[ame471_j][@\"name\"] isKindOfClass:NSString.class]\n"
        "                    ? ame471_merged[ame471_j][@\"name\"] : nil;\n"
        "                NSRange ame471_eColon = [ame471_existing rangeOfString:@\":\" options:NSBackwardsSearch];\n"
        "                if (ame471_eColon.location != NSNotFound && ame471_eColon.location > 0 &&\n"
        "                    [[ame471_existing substringToIndex:ame471_eColon.location] isEqualToString:ame471_group]) {\n"
        "                    ame471_merged[ame471_j] = ame471_lib;   // 子辈覆盖父辈\n"
        "                    ame471_replaced = YES;\n"
        "                    break;\n"
        "                }\n"
        "            }\n"
        "            if (!ame471_replaced) [ame471_merged addObject:ame471_lib];\n"
        "        }\n"
        "    }\n"
        "    return ame471_merged;\n"
        "}\n"
        "\n"
        "// ★Task471：缺失收集统一入口（链合并扫描 + rel 去重）——保环主入口两次收集\n"
        "//   （初扫 + Tier A 回收后复扫）共用，口径单一。\n"
        "static NSArray<NSDictionary *> *ame471_collectMissing(NSDictionary *launchTarget, NSString *gameDir, NSString *libRoot) {\n"
        "    NSArray<NSDictionary *> *ame471_libs = ame471_mergedLibraries(launchTarget, gameDir);\n"
        "    NSArray<NSDictionary *> *ame471_jsonMissing = ame467_missingProcessorArtifacts(ame471_libs, libRoot);\n"
        "    NSMutableDictionary<NSString *, NSDictionary *> *ame471_index = [NSMutableDictionary dictionary];\n"
        "    for (NSDictionary *ame471_item in ame471_jsonMissing) {\n"
        "        ame471_index[ame471_item[@\"rel\"]] = ame471_item;\n"
        "    }\n"
        "    return ame471_index.allValues;\n"
        "}\n"
        "\n"
    )
    jl = jl.replace(anchor, helpers + anchor, 1)

    # ── E6 保环主入口换 collect + launch-root 日志锚 ──
    old = "    NSArray *ame467_missing = ame467_missingProcessorArtifacts(launchTarget, libRoot);"
    new = (
        "    NSArray *ame467_missing = ame471_collectMissing(launchTarget, gameDir, libRoot);\n"
        "    NSLog(@\"[JavaLauncher] Task471: rescue scan launch-root=%@ missing=%lu\",\n"
        "          libRoot, (unsigned long)ame467_missing.count);"
    )
    must_unique(jl, old, "E6 初扫锚")
    jl = jl.replace(old, new, 1)

    old = "    ame467_missing = ame467_missingProcessorArtifacts(launchTarget, libRoot);   // 重新收集"
    new = "    ame467_missing = ame471_collectMissing(launchTarget, gameDir, libRoot);   // 重新收集（Task471 链合并口径同初扫）"
    must_unique(jl, old, "E6b 复扫锚")
    jl = jl.replace(old, new, 1)

    # ── E7 旧调用点撤除（注释化） ──
    old = (
        "        // Task 158（Fix B）：启动前游戏库完整性自愈闸门——见上方\n"
        "        // ame158_repairMissingLibraries 病历（Forge text2speech CNFE 根修 +\n"
        "        // 未来任何缺库的静默黑洞自愈）。非阻断：失败只记日志点名。\n"
        "        // ★Task467：门 BOOL 化——NeoForge processor 产物保环中断路径\n"
        "        // （Tier B 重启链 / Tier C 指引弹窗已展示）直接 return 1，\n"
        "        // 不再进 JIT 等待烧进 FML 致命屏。\n"
        "        if (!ame158_repairMissingLibraries(launchTarget)) {\n"
        "            return 1;\n"
        "        }"
    )
    new = (
        "        // Task 158（Fix B）：启动前游戏库完整性自愈闸门——★Task471 调用点后移：\n"
        "        //   gameDir 解析（ame275/ame225/ame428 CwdAlign/ame287 forge 收口）完成\n"
        "        //   之后才查库（现调用点位于 Task428 之前），否则门查 POJAV_GAME_DIR\n"
        "        //   基础根、FML 查实例轴根 = 双根脱节（MnPXaJV 装机判例：门 clean\n"
        "        //   71 present 而 FML 死于实例轴 client-26.3-1-srg.jar 缺失）。\n"
        "        //   ★Task467 中端口径原样：Tier B 重启链 / Tier C 指引弹窗已展示即\n"
        "        //   return 1，不进 JVM。"
    )
    must_unique(jl, old, "E7 旧调用点锚")
    jl = jl.replace(old, new, 1)

    # ── E8 新调用点（Task428 之前、gameDir 终解析之后） ──
    anchor = "        // ★Task428（3.3 完整性检查重建）：开关语义纠正——general.check_sha 开启时，"
    must_unique(jl, anchor, "E8 Task428 注释锚")
    gate_call = (
        "        // ★Task471：ame158 门 + ame467 保环调用点（gameDir 终解析之后、Task428\n"
        "        //   完整性检查之前）——launchGameDir 显式传参，与 JVM chdir 同根；\n"
        "        //   中断语义 = Task467 口径（Tier B/C 已展示即 return 1，不进 JVM）。\n"
        "        if (!ame158_repairMissingLibraries(launchTarget, gameDir)) {\n"
        "            return 1;\n"
        "        }\n"
        "\n"
    )
    jl = jl.replace(anchor, gate_call + anchor, 1)

    # ── E9 门尾保环调用换 launchGameDir 口径 ──
    old = (
        "    // ★Task467：NeoForge processor 产物保环（SRG/PATCHED/EXTRA 无 URL 条目\n"
        "    // 是本门与 Task428 的共同盲区——三层保环见上方 ame467 块注释）。\n"
        "    return ame467_processorArtifactRescue(launchTarget,\n"
        "        [@(ame158_gameDir) stringByAppendingPathComponent:@\"libraries\"],\n"
        "        @(ame158_gameDir));"
    )
    new = (
        "    // ★Task467：NeoForge processor 产物保环（SRG/PATCHED/EXTRA 无 URL 条目\n"
        "    // 是本门与 Task428 的共同盲区——三层保环见上方 ame467 块注释）。\n"
        "    // ★Task471：libRoot/gameDir 全部换启动链解析根（launchGameDir）——\n"
        "    //   Tier B ForgeProcessorExecutor 的 mainGameDir 同根，自愈产物落位\n"
        "    //   FML 实际查找处（否则自愈成功也救不了实例轴）。\n"
        "    return ame467_processorArtifactRescue(launchTarget, ame158_libRoot,\n"
        "        launchGameDir.length > 0 ? launchGameDir : @(ame158_gameDir));"
    )
    must_unique(jl, old, "E9 保环调用锚")
    jl = jl.replace(old, new, 1)

    # ── 零污染断言（Task463 折叠面 = ZL2SettingCards/.h + ZL2SettingPages，
    #      本轮外科零触碰；计数锚 = HEAD 基线 Pages 40 / Cards 1 / Cards.h 1） ──
    fold_pages = rd(ROOT / "Natives" / "ZL2SettingPages.m").count("defaultCollapsed:")
    fold_cards = rd(ROOT / "Natives" / "ZL2SettingCards.m").count("defaultCollapsed:")
    fold_cards_h = rd(ROOT / "Natives" / "ZL2SettingCards.h").count("defaultCollapsed:")
    if (fold_pages, fold_cards, fold_cards_h) != (40, 1, 1):
        print(f"[FAIL] Task463 折叠面漂移：Pages {fold_pages}/Cards {fold_cards}/Cards.h {fold_cards_h}（基线 40/1/1）")
        sys.exit(1)
    for banned in ("MOBILEGL_FRAMES_IN_FLIGHT", "MOBILEGL_ESPRYT_MULTIDRAW_PLACEHOLDER"):
        if banned in jl:
            print(f"[FAIL] banned 引入：{banned}")
            sys.exit(1)

    JL.write_text(jl, encoding="utf-8")

    # ── 括号状态机审计（仓库门禁同款） ──
    audit = subprocess.run(
        ["python3", str(ROOT / "scripts" / "ame_bracket_audit.py"), "Natives/JavaLauncher.m"],
        cwd=ROOT, capture_output=True, text=True, timeout=120)
    tail = "\n".join(audit.stdout.strip().splitlines()[-3:])
    print(tail)
    if audit.returncode != 0:
        print("[FAIL] 括号审计红")
        sys.exit(1)

    print(f"Task471 surgery OK（折叠面保形 Pages {fold_pages}/Cards {fold_cards}/Cards.h {fold_cards_h}）")


if __name__ == "__main__":
    surgery()
