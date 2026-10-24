#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
ame324_selfcheck.py — Task 324 防回退门

用户三问（IMG_0485 原版安装页布局 / 下载 UI 全面 ZL2 风格 / versions 隔离骨架）
+ 二代 worklog 跨仓库勘误镜像 的自检域：
  ① 布局根修：Addons 页滚动内容宽度锚定（挤左/死空间根）+ 头部行弹性链
    （field 首选 220@900 / 钮最小宽 96 / 标签内边距钳制 / 标题压缩阻力 950）
  ② 下载 UI 改道：三管理器 openDownloadPage → ZL2DownloadViewController
    （预选 2/3/4 轨）+ targetProfileName 透传链（Task265 语义保留）+
    旧 DVC 入口退役（三文件零 DownloadViewController alloc）
  ③ 隔离骨架：ame324 两方法在场 + 六目录清单 + (Default) 守卫 +
    ame271 收尾全量 pass + Addons 三安装成功分支即时补齐 + 桩 TU 同步
  ④ CRLF 纪律：ModService.h 字节级手术行尾保持
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


def read_bytes(rel):
    with open(os.path.join(ROOT, rel), "rb") as f:
        return f.read()


def check(name, cond, detail=""):
    if cond:
        PASSES.append(name)
        print("PASS %s" % name)
    else:
        FAILS.append((name, detail))
        print("FAIL %s  %s" % (name, detail))


def main():
    # ── ① 布局根修（ZL2GameAddonsViewController） ────────────────
    addons = read("Natives/ZL2GameAddonsViewController.m")
    check("layout:content-width-anchored",
          "stack.widthAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.widthAnchor" in addons,
          "滚动内容必须锚定 frame 宽（挤左1/4+右侧死空间根修）")
    check("layout:field-preferred-220-yields",
          "_nameField.widthAnchor constraintEqualToConstant:220].priority = 900" in addons,
          "nameField 固定 220 必须降级为首选 220@900（窄宽让位）")
    check("layout:field-floor-120",
          "_nameField.widthAnchor constraintGreaterThanOrEqualToConstant:120" in addons,
          "nameField 必须有 120 必醒下限")
    check("layout:field-lead-inequality-yields",
          ".priority = 999" in addons,
          "field 头部不等式必须降 999（让位钮最小宽）")
    check("layout:install-button-min-width",
          "_installButton.widthAnchor constraintGreaterThanOrEqualToConstant:96" in addons,
          "安装钮必须最小宽 96（截断根修）")
    check("layout:install-label-inset-clamped",
          "_installLabel.leadingAnchor constraintGreaterThanOrEqualToAnchor:_installButton.leadingAnchor" in addons
          and "_installLabel.trailingAnchor constraintLessThanOrEqualToAnchor:_installButton.trailingAnchor" in addons,
          "钮上标签必须内边距钳制（永不溢出截断）")
    check("layout:title-compression-950",
          "setContentCompressionResistancePriority:950" in addons,
          "标题压缩阻力 950（让位次序 field→标题→钮）")

    # ── ② 下载 UI 改道（三管理器 + ZL2 下载中心契约） ─────────────
    managers = [
        ("Natives/ModsManagerViewController.m", "vc.selectedIndex = 2;"),
        ("Natives/ResourcePacksManagerViewController.m", "downloadVC.selectedIndex = 3;"),
        ("Natives/WorldsManagerViewController.m", "downloadVC.selectedIndex = 4;"),
    ]
    for rel, sel in managers:
        src = read(rel)
        base = os.path.basename(rel)
        check("route:%s-zl2download" % base,
              "[[ZL2DownloadViewController alloc] init]" in src,
              "openDownloadPage 必须改道 ZL2 下载中心")
        check("route:%s-preset-rail" % base,
              sel in src,
              "必须预选对应资产轨（模组2/资源包3/存档4）")
        check("route:%s-legacy-dvc-retired" % base,
              "[[DownloadViewController alloc]" not in src,
              "旧 DVC 实例化必须退役（下载 UI 全面 ZL2 风格）")
        check("route:%s-target-profile" % base,
              "vc.targetProfileName = " in src or "downloadVC.targetProfileName = " in src,
              "目标实例透传必须保留（Task265 语义）")
    zl2dl_h = read("Natives/ZL2DownloadViewController.h")
    check("route:download-h-contract",
          "selectedIndex" in zl2dl_h and "targetProfileName" in zl2dl_h,
          "ZL2DownloadViewController.h 必须暴露预选+透传契约")
    zl2dl = read("Natives/ZL2DownloadViewController.m")
    check("route:download-child-passthrough",
          "((ZL2AssetSearchViewController *)vc).targetProfileName = self.targetProfileName" in zl2dl,
          "子页构建必须透传 targetProfileName")
    check("route:download-preset-honored",
          "ame_showCategory:(self.selectedIndex >= 0 ? self.selectedIndex : 0)" in zl2dl,
          "viewDidLoad 必须尊重预选轨")
    check("route:download-navbar-conditional",
          "ame324_isNavRoot" in zl2dl,
          "push 场景必须保留系统栏（返回钮可回管理页）")
    asset_h = read("Natives/ZL2AssetSearchViewController.h")
    asset_m = read("Natives/ZL2AssetSearchViewController.m")
    check("route:asset-search-target-prop",
          'targetProfileName' in asset_h and "self.targetProfileName.length > 0" in asset_m,
          "AssetSearch 必须接收透传并在快照时优先")

    # ── ③ 隔离骨架（ModService + 挂点 + 桩） ─────────────────────
    ms_h = read("Natives/ModService.h")
    check("skeleton:h-declarations",
          "+ (void)ame324_ensureIsolationSkeletonForVersionId:(NSString *)vid;" in ms_h
          and "+ (void)ame324_ensureIsolationSkeletonsAll;" in ms_h,
          "ModService.h 必须声明 ame324 两方法")
    ms = read("Natives/ModService.m")
    for d in ("@\"mods\"", "@\"saves\"", "@\"config\"", "@\"resourcepacks\"",
              "@\"shaderpacks\"", "@\"screenshots\""):
        check("skeleton:dir-%s" % d, d in ms, "六目录清单缺 %s" % d)
    check("skeleton:default-guard",
          '[vid isEqualToString:@"(Default)"]' in ms,
          "默认实例守卫必须在场（防与共享 mods 撞名）")
    check("skeleton:registry-judge",
          'versions/%@/game", vid]' in ms or "versions/%@/game" in ms,
          "隔离判据必须兼容平铺新口径与旧 game 叶子")
    check("skeleton:all-pass-json-gated",
          '%@.json", ame324_vd]' in ms,
          "全量 pass 必须以 <id>.json 限定真实版本实例")
    check("skeleton:ame271-tail-hook",
          "[ModService ame324_ensureIsolationSkeletonsAll];" in ms,
          "ame271 自愈链收尾必须挂全量 pass")
    check("skeleton:addons-three-hooks",
          addons.count("[ModService ame324_ensureIsolationSkeletonsAll];") >= 3,
          "Addons 三个安装成功分支必须即时补齐骨架")
    stub = read("Natives/Preview/ZL2PagesStub.m")
    check("skeleton:stub-synced",
          "+ (void)ame324_ensureIsolationSkeletonsAll { }" in stub,
          "smoke 桩 TU 必须同步 ame324（链接纪律）")

    # ── ④ CRLF 纪律（ModService.h 字节级手术不破行尾） ────────────
    raw = read_bytes("Natives/ModService.h")
    check("crlf:modservice-h-preserved",
          b"+ (void)ame324_ensureIsolationSkeletonsAll;\r\n" in raw,
          "ModService.h 插入行必须保持 CRLF")

    print("")
    print("ame324_selfcheck: %d PASS / %d FAIL" % (len(PASSES), len(FAILS)))
    if FAILS:
        for name, detail in FAILS:
            print("  FAIL %s  %s" % (name, detail))
        sys.exit(1)
    print("ALL GREEN")


if __name__ == "__main__":
    main()
