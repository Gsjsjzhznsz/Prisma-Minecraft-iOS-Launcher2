#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
ame323_selfcheck.py — Task 323 防回退门

断链根修 + 下载中心三线改造的自检域：
  ① 启动续链：ZL2Home KVO 100% → profile 覆盖 → Task224 收口 → PLJITGate →
    UIKit_launchMinecraftSurfaceVC（防"下载完成静默终止"回退）
  ② PLJITGate 共享门禁：状态机要素（深链八选项/等待环/弃启回调）+ CMake 登记
  ③ 加载器筛选：模组/整合包字段 + FCL profile 自动预选 + 两平台 filters[@"loader"]
  ④ 数据包 tab：枚举/请求/详情/下载链/空态键全链
  ⑤ 下载中心十二项：数据包 + 控件/手柄/插件仓库三件（nav 宿主）
  ⑥ ZeroTier：目录自检 + 沉降重试 + 弹窗标题去"启动失败"误导（联机域）
  ⑦ 门禁清单扩充：task240 FILES 含 Task323 改动域
"""
import io
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

FAILS = []
PASSES = []


def read(rel):
    with io.open(os.path.join(ROOT, rel), encoding="utf-8") as f:
        return f.read()


def check(name, cond, detail=""):
    if cond:
        PASSES.append(name)
        print("PASS %s" % name)
    else:
        FAILS.append((name, detail))
        print("FAIL %s  %s" % (name, detail))


def main():
    # ── ① 启动续链 ──────────────────────────────────────────────
    home = read("Natives/ZL2HomeViewController.m")
    check("launch:kvo100-calls-continuation",
          "ame323_beginJITGatedLaunchForMetadata" in home,
          "KVO 100% 分支必须调用续链入口")
    check("launch:continuation-uses-gate",
          "[PLJITGate invokeAfterJITEnabledWithHandler:" in home,
          "续链必须走 PLJITGate 门禁")
    check("launch:continuation-swaps-surface",
          "UIKit_launchMinecraftSurfaceVC" in home,
          "JIT 就绪后必须换根 SurfaceViewController")
    check("launch:abandon-restores",
          home.count("ReloadProfileList") >= 3,
          "弃启路径必须 task=nil+恢复交互+ReloadProfileList")
    check("launch:profile-override-block",
          'setPrefString(@"video.graphics_api"' in home
          and 'setPrefString(@"java.java_version"' in home
          and 'setPrefInt(@"general.ram_allocation"' in home,
          "profile 覆盖三件必须随续链移植")
    check("launch:task224-dismiss-settle",
          "0.8 * NSEC_PER_SEC" in home and "closing presented stack" in home,
          "Task224 叠层收口 + 0.8s 沉降必须保留")
    check("launch:no-deadend",
          "ame323_metadata" in home and "self.task.metadata" in home,
          "metadata 缺失回退分支保留（异常收尾）")

    # ── ② PLJITGate 共享门禁 ────────────────────────────────────
    gate = read("Natives/PLJITGate.m")
    gateh = read("Natives/PLJITGate.h")
    check("gate:files-exist", bool(gate) and bool(gateh))
    check("gate:state-machine-essence",
          all(k in gate for k in [
              "isJITEnabled(false)",
              "ame322_stikjitBundleId()",
              "ame169_waitForJITCondition",
              "ame185_dispatchToMainSelfHealing",
              "debug.jit_enabler",
              "ame294_enableBuiltinJITWithCompletion",
              "onAbandon",
          ]),
          "状态机要素（快路径/深链/等待环/自愈派发/弃启回调）必须齐备")
    check("gate:task226-auto-retry",
          "AUTO-RETRY" in gate and "gPL323JITAutoRetried" in gate,
          "Task226 静默自动重拉必须保留")
    check("gate:reattach-helper",
          "ame323_reattachJIT26ThenLaunch" in gate and "JIT26IsLikelyDebuggerKeepAttached" in gate,
          "Task172 重挂助手必须保留")
    check("gate:cmake-registered",
          "PLJITGate.m" in read("Natives/CMakeLists.txt"),
          "CMakeLists 必须登记 PLJITGate.m")

    # ── ③ 加载器筛选 ────────────────────────────────────────────
    search = read("Natives/ZL2AssetSearchViewController.m")
    check("loader:filter-prop-and-send",
          'filters[@"loader"]' in search and "self.loaderFilter.length > 0" in search,
          "请求组装必须发 loader 键（两平台 API 既有消费端）")
    check("loader:mod-modpack-gate",
          "ZL2AssetSearchTypeMod || self.assetType == ZL2AssetSearchTypeModpack" in search,
          "loader 只在模组/整合包类型暴露与发送")
    check("loader:fcl-auto-preselect",
          "ame_profileLoader" in search and '_loaderFilter = profileLoader' in search,
          "FCL 语义 profile 加载器自动预选必须保留")
    check("loader:panel-field-and-sheet",
          "ame_loaderFieldTapped" in search and "ame_loaderOptionTapped" in search
          and "@[ @[@\"\", @\"全部\"]" in search,
          "右栏字段 + 弹层选择器（全部/Fabric/Forge/Quilt/NeoForge）必须齐备")
    check("loader:four-value-whitelist",
          'isEqualToString:@"neoforge"' in search,
          "仅透传四值（optifine/vanilla 不发）")

    # ── ④ 数据包 tab ────────────────────────────────────────────
    searchh = read("Natives/ZL2AssetSearchViewController.h")
    check("datapack:enum-case",
          "ZL2AssetSearchTypeDataPack = 5" in searchh)
    check("datapack:request-and-chain",
          'filters[@"projectType"] = @"datapack"' in search
          and "AssetVersionTypeDataPack" in search
          and "ame_startDownloadForDataPackItem" in search
          and 'downloadDataPack:item' in search.replace(" ", "")
          or 'downloadDataPack:item' in search,
          "请求/详情/下载链必须齐备")
    check("datapack:empty-state-key",
          'key = @"i18n_str_184"' in search,
          "空态复用既有暂无数据包键")
    check("datapack:imports",
          '#import "DataPackItem.h"' in search and '#import "DataPackService.h"' in search)

    # ── ⑤ 下载中心十二项 + 仓库三件 ─────────────────────────────
    dl = read("Natives/ZL2DownloadViewController.m")
    check("dl:rail-12-items",
          all(t in dl for t in ['@"游戏"', '@"整合包"', '@"模组"', '@"资源包"',
                                '@"存档"', '@"光影包"', '@"数据包"',
                                '@"按ID搜索"', '@"收藏"',
                                '@"控件仓库"', '@"手柄仓库"', '@"插件仓库"']),
          "左轨 12 项（Prisma1 八类 + 仓库三件）必须齐备")
    check("dl:repo-cases-nav-wrapped",
          "case 9:" in dl and "case 10:" in dl and "case 11:" in dl
          and "initialCategoryIndex = 2" in dl
          and dl.count("initWithRootViewController") >= 3,
          "仓库三件必须以 nav 宿主嵌入（控件仓库用 navigationItem 链）")
    check("dl:repo-imports",
          '#import "ControlRepoViewController.h"' in dl
          and '#import "ZL2PluginRepoViewController.h"' in dl)

    # ── ⑥ ZeroTier ──────────────────────────────────────────────
    ztb = read("Natives/ZeroTierBridge.m")
    check("zt:mkdir-and-retry",
          "pre-start mkdir" in ztb and "settle-retry once" in ztb,
          "目录自检 + 沉降重试必须保留")
    zh = read("Natives/resources/zh-CN.lproj/Localizable.strings")
    en = read("Natives/resources/en.lproj/Localizable.strings")
    check("zt:title-deconflicted",
          '"mp.node.start_failed_title" = "联机服务启动失败";' in zh
          and '"ame193.mp.4" = "联机服务启动失败";' in zh
          and "Online Service Start Failed" in en,
          "联机弹窗标题不得再与游戏启动混淆（防误判游戏故障）")

    # ── ⑦ 门禁清单扩充 ──────────────────────────────────────────
    gate240 = read("scripts/task240_syntax_gate.py")
    check("gate240:covers-task323-domain",
          all(f in gate240 for f in [
              "Natives/PLJITGate.m",
              "Natives/ZL2HomeViewController.m",
              "Natives/ZL2AssetSearchViewController.m",
              "Natives/ZL2DownloadViewController.m",
              "Natives/ZeroTierBridge.m",
          ]),
          "task240 硬编码清单必须覆盖 Task323 改动域（ZL2 域此前不在闸）")

    print("=" * 40)
    print("ame323_selfcheck: %d passed, %d failed" % (len(PASSES), len(FAILS)))
    if FAILS:
        for name, detail in FAILS:
            print("  FAIL %s  %s" % (name, detail))
        sys.exit(1)
    print("ALL GREEN")
    sys.exit(0)


if __name__ == "__main__":
    main()
