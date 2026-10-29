// Task343 fluent-ui v2.2.0 —— 「结构也 Fluent」版（用户四轮复诉：插件画面
// 还是 zl2 的，要重新设计整个画面，排版都要变化，跟 Fluent 应用对齐）。
// ---------------------------------------------------------------------
// ★ v2.2.0（Task347）：接入结构令牌承载面（ame.setThemeStructure）——
//   壳层导航骨架整体切换为 WinUI NavigationView 蓝图：左侧导航窗格
//  （宽屏常驻 / 窄屏抽屉，WinUI SelectionIndicator 选中指示条，设置驻
//   窗格底）+ 大标题内容区（WinUI Page Header）。这是排版级的实质变化：
//   导航从顶栏右侧图标组整体迁到左窗格，不再是同一蓝图上重铺几何。
//   v2.1.1 的即时重建杠杆（Task346 根重建）让换蓝图也即时生效。
// ---------------------------------------------------------------------
// v2.1.x 交付了布局/形状/字阶/色板四族令牌（控件 32pt 线、卡片 4pt 栅格、
// 五档圆角收紧 4/4/8/8/12、Fluent2 ramp 七档、三色板 28 色），v2.2.0 在
// 此之上补上第五族——结构：
//
//   · 结构（shellLayout = navigationview）：
//       左窗格 —— 应用名头 + 主导航（主页/下载/版本/账户/联机/AI）+
//       底部固定（设置/文件）；选中项 = 指示条 + 中性抬升行底。
//       内容区 —— 大标题页头 + 任务胶囊；宽屏常驻窗格，窄屏收抽屉。
//   · 布局（fluentui-apple 4pt 栅格 + WinUI 控件度量溯源）：
//       控件高度统一 32pt——动作胶囊 80×32、按钮 32、chip 32、搜索框 40；
//       卡片解剖走 4pt 栅格；对话框内边距 24（WinUI ContentDialog）。
//   · 形状/字阶/色板（fluentui-apple 溯源不变）：
//       形状 —— 控件 4pt / 卡片 8pt / 浮层 12pt；
//       字阶 —— Title2 28S / Title3 20S / Body1 17R (Strong 15SB) /
//               Body2 15R / Caption1 13R；
//       色板 —— fluent-light 品牌蓝 #0F6CBD / fluent-dark 品牌青 #4CC2FF /
//               fluent-apple 混融 #007AFF + systemGray6 分层。
//
// 交互纪律不变：单行入口，点击循环 亮→暗→混融→恢复默认；首次点击出
// 说明对话框。持久化走桥面 __theme/__shape/__layout/__structure 装载期
// 重放键。结构/布局链独立容错：setThemeStructure / setThemeLayout 失败
// （旧引擎/桥面异常）不阻塞其余族——五维度 → 布局+形色 → 形+色 → 仅色
// 四级平滑降级。全部调用 try-catch 包裹——权限/桥面单点故障不得炸整插件。
(function () {
  if (typeof ame === 'undefined') return;

  var MARK = 'Task343-fluent';

  // Fluent 2 形状/字阶：三套方案共用（Fluent 2 形态与色板无关；apple 混融
  // 也保持 Fluent 骨架，只换色）。fluentui-apple 溯源值，见文件头注释。
  var FLUENT_SHAPE = {
    radiusXS: 4, radiusS: 4, radiusM: 8, radiusL: 8, radiusXL: 12,
    fontHeadline:    { size: 28, weight: 'semibold' },
    fontTitleLarge:  { size: 20, weight: 'semibold' },
    fontTitleMedium: { size: 15, weight: 'semibold' },
    fontBodyLarge:   { size: 17, weight: 'regular' },
    fontBodyMedium:  { size: 15, weight: 'regular' },
    fontLabelLarge:  { size: 15, weight: 'semibold' },
    fontLabelMedium: { size: 13, weight: 'regular' }
  };

  // ★ Task343：Fluent 布局刻度（fluentui-apple 4pt 栅格 + WinUI 控件度量
  // 溯源；键名 = 引擎白名单中性 spacing/density 语义，见 ZL2Theme.h）。
  var FLUENT_LAYOUT = {
    searchBarHeight: 40,   // M3 44 → Fluent 紧凑搜索框
    chipHeight: 32,        // Fluent pill 控件线（与 M3 chip 同高，显式声明）
    cardMarginV: 4,        // 5 → 4pt 栅格
    cardMarginH: 16,       // 16（4pt 栅格，显式声明）
    cardInsetX: 16,        // 14 → 16（Fluent 卡片内边距）
    cardInsetTop: 12,      // 12（4pt 栅格，显式声明）
    cardInsetBottom: 12,   // 12（4pt 栅格，显式声明）
    cardContentGap: 6,     // 4 → 6（标题/副文呼吸感）
    pillMinWidth: 80,      // 56 → 80（Fluent 按钮最小宽度）
    pillHeight: 32,        // 28 → 32（Fluent 标准控件高度）
    pillGap: 12,           // 10 → 12（4pt 栅格）
    dialogInset: 24,       // 24（WinUI ContentDialog，显式声明）
    buttonHeight: 32       // 40 → 32（Fluent 标准控件高度）
  };

  // ★ Task347：Fluent 结构蓝图（WinUI NavigationView；键值 = 引擎白名单
  // 中性骨架语义，见 ZL2Theme.h ame347 注释）。
  var FLUENT_STRUCTURE = {
    shellLayout: 'navigationview'   // 左窗格 + 大标题内容区（宽屏常驻/窄屏抽屉）
  };

  var PALETTES = [
    {
      key: 'fluent-light',
      name: 'Fluent 亮色',
      tokens: {
        primary: '0F6CBD', onPrimary: 'FFFFFF',
        primaryContainer: 'C7E0F4', onPrimaryContainer: '0C2B45',
        secondary: '5D7A93', onSecondary: 'FFFFFF',
        secondaryContainer: 'E1EBF5', onSecondaryContainer: '0B1E2E',
        tertiary: '8764B8', onTertiary: 'FFFFFF',
        tertiaryContainer: 'E6DEF8', onTertiaryContainer: '221046',
        surface: 'F5F5F5', onSurface: '1B1B1B',
        onSurfaceVariant: '424242', surfaceVariant: 'EFF6FC',
        surfaceContainerLowest: 'FFFFFF', surfaceContainerLow: 'FAFAFA',
        surfaceContainer: 'F5F5F5', surfaceContainerHigh: 'F0F0F0',
        surfaceContainerHighest: 'EBEBEB', surfaceBright: 'FFFFFF',
        outline: 'CECECE', outlineVariant: 'E0E0E0',
        error: 'C50F1F', errorContainer: 'FDE7E9',
        success: '0E700E', warning: '9D5D00'
      }
    },
    {
      key: 'fluent-dark',
      name: 'Fluent 暗色',
      tokens: {
        primary: '4CC2FF', onPrimary: '00344E',
        primaryContainer: '004578', onPrimaryContainer: 'B4D6F7',
        secondary: '6FA8CC', onSecondary: '062033',
        secondaryContainer: '1A3A54', onSecondaryContainer: 'C7E0F4',
        tertiary: 'C1A7E8', onTertiary: '221046',
        tertiaryContainer: '5D2E8C', onTertiaryContainer: 'EAD9FF',
        surface: '1A1A1A', onSurface: 'F5F5F5',
        onSurfaceVariant: 'D4D4D4', surfaceVariant: '262626',
        surfaceContainerLowest: '111111', surfaceContainerLow: '1D1D1D',
        surfaceContainer: '222222', surfaceContainerHigh: '282828',
        surfaceContainerHighest: '2F2F2F', surfaceBright: '3B3B3B',
        outline: '6B6B6B', outlineVariant: '3D3D3D',
        error: 'FF99A4', errorContainer: '6E1122',
        success: '6CCB5F', warning: 'F7B26A'
      }
    },
    {
      key: 'fluent-apple',
      name: 'Fluent × Apple 混融',
      tokens: {
        primary: '007AFF', onPrimary: 'FFFFFF',
        primaryContainer: 'D6E9FF', onPrimaryContainer: '00284D',
        secondary: '5E5CE6', onSecondary: 'FFFFFF',
        secondaryContainer: 'E2E1F9', onSecondaryContainer: '12113B',
        tertiary: '30B0C7', onTertiary: 'FFFFFF',
        tertiaryContainer: 'C7F2FA', onTertiaryContainer: '063A44',
        surface: 'F2F2F7', onSurface: '1C1C1E',
        onSurfaceVariant: '5B5B60', surfaceVariant: 'E5E5EA',
        surfaceContainerLowest: 'FFFFFF', surfaceContainerLow: 'F7F7FA',
        surfaceContainer: 'F2F2F7', surfaceContainerHigh: 'ECECF2',
        surfaceContainerHighest: 'E4E4EC', surfaceBright: 'FFFFFF',
        outline: 'C6C6D0', outlineVariant: 'DDDDE5',
        error: 'FF3B30', errorContainer: 'FFDAD6',
        success: '34C759', warning: 'FF9500'
      }
    }
  ];

  function storageSet(key, value) {
    try { return ame.storage.set(key, value); } catch (e) { return false; }
  }
  function storageGet(key) {
    try { return ame.storage.get(key); } catch (e) { return null; }
  }

  function currentIndex() {
    var raw = storageGet('fluent.idx');
    var n = parseInt(raw, 10);
    return (isNaN(n) || n < 0 || n >= PALETTES.length) ? -1 : n;
  }

  // ★ Task347：结构链独立容错（最高族优先应用；失败不阻塞形色，
  // 退化为 v2.1 形态——同蓝图重铺几何，无左窗格）。
  function applyStructure() {
    try { ame.setThemeStructure(FLUENT_STRUCTURE); } catch (e) {
      ame.log('[' + MARK + '] setThemeStructure failed (old engine? v2.1 fallback): ' + e);
    }
  }

  // 形状链独立容错：setThemeShape 失败（旧引擎/桥面异常）不阻塞色板应用，
  // 退化为 v1 形态（仅换色）——全维度与仅换色之间平滑降级。
  function applyShape() {
    try { ame.setThemeShape(FLUENT_SHAPE); } catch (e) {
      ame.log('[' + MARK + '] setThemeShape failed (old engine? color-only fallback): ' + e);
    }
  }

  // ★ Task343：布局链独立容错（与形状链同纪律）：setThemeLayout 失败
  // 不阻塞色板/形状，退化为 v2.0 形态（形+色，排版仍 M3 刻度）。
  function applyLayout() {
    try { ame.setThemeLayout(FLUENT_LAYOUT); } catch (e) {
      ame.log('[' + MARK + '] setThemeLayout failed (old engine? v2.0 fallback): ' + e);
    }
  }

  function applyPalette(idx) {
    var pal = PALETTES[idx];
    try {
      ame.setThemeToken(pal.tokens);
    } catch (e) {
      ame.log('[' + MARK + '] setThemeToken failed: ' + e);
      try { ame.toast('主题应用失败（ui.theme 权限或桥面异常）'); } catch (e2) {}
      return;
    }
    applyStructure();
    applyShape();
    applyLayout();
    // '__theme'/'__shape'/'__layout'/'__structure' 由桥面 setThemeToken/
    // setThemeShape/setThemeLayout/setThemeStructure 落盘（装载期重放键）
    // ——插件侧只持久化循环态。
    storageSet('fluent.idx', String(idx));
    try { ame.toast('已应用：' + pal.name + '（NavigationView 左窗格结构 · 全维度 · 即时重建）'); } catch (e) {}
    ame.log('[' + MARK + '] palette applied: ' + pal.key + ' (structure+color+shape+layout)');
  }

  function restoreDefault() {
    try { ame.setThemeToken({}); } catch (e) {
      ame.log('[' + MARK + '] reset failed: ' + e);
    }
    try { ame.setThemeShape({}); } catch (e) {
      ame.log('[' + MARK + '] shape reset failed: ' + e);
    }
    try { ame.setThemeLayout({}); } catch (e) {
      ame.log('[' + MARK + '] layout reset failed: ' + e);
    }
    try { ame.setThemeStructure({}); } catch (e) {
      ame.log('[' + MARK + '] structure reset failed: ' + e);
    }
    storageSet('fluent.idx', '-1');
    try { ame.toast('已恢复默认主题（embermire · M3 刻度 · 顶栏骨架）'); } catch (e) {}
    ame.log('[' + MARK + '] theme restored to default');
  }

  try {
    ame.addLauncherRow(
      { id: 'fluent-ui', title: 'Fluent UI', subtitle: 'Fluent 2 全维度·左侧导航窗格（点击循环）' },
      function (rowId) {
        var announced = storageGet('fluent.announced') === 'yes';
        if (!announced) {
          storageSet('fluent.announced', 'yes');
          try {
            ame.dialog({
              title: 'Fluent UI',
              body: 'Fluent 2 完整设计语言换装（真重排版，非 ZL2 主题换色）：\n· 结构 —— 左侧 NavigationView 导航窗格（宽屏常驻/窄屏抽屉，WinUI 选中指示条，设置驻窗格底）+ 大标题内容区，导航整体离开顶栏（Task347 结构令牌）\n· 排版 —— 控件统一 32pt 线 / 卡片 4pt 栅格解剖 / 胶囊 80×32（Task343 布局令牌）\n· 形状 —— 控件 4pt / 卡片 8pt / 浮层 12pt（M3 大圆角整体收紧）\n· 字阶 —— Title 28S/20S · Body 17R/15R · Caption 13R（Fluent2 ramp）\n· 色板 —— Fluent 亮（品牌蓝）/ Fluent 暗（品牌青）/ Fluent × Apple 混融\n点击本行循环切换，第 4 次恢复默认；每次切换全界面即时重建（Task346 根重建杠杆），重启启动器后自动重放。',
              confirm: '应用 Fluent 亮色',
              cancel: '关闭'
            }, function (ok) {
              if (ok) applyPalette(0);
            });
          } catch (e) {
            // 对话框桥面异常时退化为直接循环
            applyPalette((currentIndex() + 1) % PALETTES.length);
          }
          return;
        }
        var next = currentIndex() + 1;
        if (next >= PALETTES.length) restoreDefault();
        else applyPalette(next);
      }
    );
  } catch (e) {
    ame.log('[' + MARK + '] addLauncherRow failed: ' + e);
    return;
  }

  ame.log('[' + MARK + '] fluent-ui v2.2.0 loaded（Fluent 2 全维度：结构 shellLayout=navigationview + 色28+形状5+字阶7+布局13；主页贡献行「Fluent UI」，点击循环亮/暗/混融/默认）');
})();
