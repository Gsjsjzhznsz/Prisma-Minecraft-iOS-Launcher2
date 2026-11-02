// Task375 fluent-ui v2.4.0 —— 「两态开关 · 跟随系统明暗」版（用户指令：
// "flUI的开关能不能就2种状态，开和不开，浅色合深色跟随设置"）。
// ---------------------------------------------------------------------
// ★ v2.5.0（Task379）：实时跟随系统明暗——订阅 appearance.changed 事件
//   （Task379 事件面第 12 事件，payload {dark}；原生侧壳层
//   traitCollectionDidChange 桥接，系统深浅切换与设置页外观偏好切换
//   均触发）。开态下换板 + 全维令牌重应用即时生效，无需重启；v2.4.0
//   的"会话中系统明暗切换暂不追踪"限制就此退役。另：Task379 原生侧
//   darkMode 读取根修（keyWindow trait）后，装载期选色也不再误判。
// ---------------------------------------------------------------------
// ★ v2.4.0（Task375）：交互模型从「四态循环 亮→暗→混融→默认」收敛为
//   「两态开关」：
//     · 开  —— 应用 Fluent 全维度换装（结构 navigationview + 形 + 字阶 +
//              布局 + 色板），色板【跟随系统外观】：系统深色 → Fluent 暗，
//              系统浅色 → Fluent 亮。系统明暗读取 = ame.info().darkMode
//              （Task366 app 元信息面，manifest 补 settings.read 权限）。
//     · 关  —— 恢复默认主题（embermire · M3 刻度 · 顶栏骨架），全部令牌
//              清空。不再有"循环第 4 次恢复默认"的隐藏状态机。
//   持久化：fluent.on = 'yes'/'no'（旧 fluent.idx/fluent.optout 启动期
//   一次性迁移：idx>=0 或未 optout → 开）。每次装载按当下系统明暗重选
//   色板 = 重启后跟随设置；★ v2.5.0 起会话中实时跟随（appearance.changed）。
//   混融色板（fluent-apple）按"就 2 种状态"口径退役。
// ---------------------------------------------------------------------
// ★ v2.3.0（Task348）：装载即自动应用持久化方案；v2.2.0（Task347）接入
//   结构令牌承载面（ame.setThemeStructure）——WinUI NavigationView 蓝图：
//   左侧导航窗格 + 大标题内容区；v2.1.x 交付布局/形状/字阶/色板四族令牌。
//   降级链不变：结构/布局/形状各链独立容错，失败不阻塞色板（全维度 →
//   布局+形色 → 形+色 → 仅色 平滑降级）。全部调用 try-catch 包裹。
(function () {
  if (typeof ame === 'undefined') return;

  var MARK = 'Task343-fluent';

  // Fluent 2 形状/字阶：两套方案共用（Fluent 2 形态与色板无关）。
  // fluentui-apple 溯源值，见文件头注释。
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

  // ★ Task375：两套色板（跟随系统明暗二选一）。混融（fluent-apple）退役。
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
    }
  ];

  function storageSet(key, value) {
    try { return ame.storage.set(key, value); } catch (e) { return false; }
  }
  function storageGet(key) {
    try { return ame.storage.get(key); } catch (e) { return null; }
  }

  // ★ Task375：两态状态 + 旧键一次性迁移。
  //   旧语义：fluent.idx（0..2 = 亮/暗/混融，-1 = 默认）+ fluent.optout。
  //   迁移：idx >= 0 或（optout 未设置）→ 开；idx < 0 且 optout=yes → 关。
  function migrateLegacyState() {
    if (storageGet('fluent.on') !== null) return;
    var idxRaw = storageGet('fluent.idx');
    var n = parseInt(idxRaw, 10);
    var wasOn = (!isNaN(n) && n >= 0) || storageGet('fluent.optout') !== 'yes';
    storageSet('fluent.on', wasOn ? 'yes' : 'no');
    ame.log('[' + MARK + '] v2.4.0 legacy state migrated: idx=' + idxRaw + ' -> on=' + (wasOn ? 'yes' : 'no'));
  }

  function isOn() {
    return storageGet('fluent.on') === 'yes';
  }

  // ★ Task375：系统明暗读取（ame.info().darkMode；桥面 ame366_isDarkMode）。
  //   读取失败（旧桥/权限缺失）按浅色兜底——不炸插件。
  function systemIsDark() {
    try {
      var info = ame.info();
      if (info && typeof info.darkMode === 'boolean') return info.darkMode;
    } catch (e) {}
    return false;
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

  // ★ Task343：布局链独立容错（与形状链同纪律）。
  function applyLayout() {
    try { ame.setThemeLayout(FLUENT_LAYOUT); } catch (e) {
      ame.log('[' + MARK + '] setThemeLayout failed (old engine? v2.0 fallback): ' + e);
    }
  }

  // silent=true：装载期自动应用不弹 toast（每次开机都弹=噪声），仅留日志。
  function applyPalette(idx, silent) {
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
    // ——插件侧只持久化开关态。
    if (!silent) try { ame.toast('已开启：' + pal.name + '（跟随系统明暗 · NavigationView 左窗格 · 即时重建）'); } catch (e) {}
    ame.log('[' + MARK + '] palette applied: ' + pal.key + ' (structure+color+shape+layout' + (silent ? ', auto' : '') + ')');
  }

  // ★ Task375：开 = 按当下系统明暗选色板应用。
  function turnOn(silent) {
    storageSet('fluent.on', 'yes');
    applyPalette(systemIsDark() ? 1 : 0, silent);
  }

  // ★ Task375：关 = 恢复默认主题（全部令牌清空），无任何隐藏循环态。
  function turnOff() {
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
    storageSet('fluent.on', 'no');
    try { ame.toast('已关闭 Fluent UI（恢复默认主题 · embermire · M3 刻度）'); } catch (e) {}
    ame.log('[' + MARK + '] theme restored to default (off)');
  }

  // ★ Task375（v2.4.0 装载即生效语义保留）：装载时若为开态，按当下系统
  //   明暗重选色板应用 —— 重启后自动跟随设置。
  function autoApply() {
    try {
      migrateLegacyState();
      if (isOn()) applyPalette(systemIsDark() ? 1 : 0, true);
      else ame.log('[' + MARK + '] auto-apply skipped (off)');
    } catch (e) {
      ame.log('[' + MARK + '] auto-apply failed (non-fatal): ' + e);
    }
  }

  try {
    ame.addLauncherRow(
      { id: 'fluent-ui', title: 'Fluent UI', subtitle: '两态开关 · 色板实时跟随系统明暗 · NavigationView 左窗格' },
      function (rowId) {
        migrateLegacyState();
        var announced = storageGet('fluent.announced') === 'yes';
        if (!announced) {
          storageSet('fluent.announced', 'yes');
          try {
            ame.dialog({
              title: 'Fluent UI',
              body: 'Fluent 2 完整设计语言换装（真重排版，非 ZL2 主题换色）：\n· 开关只有两态 —— 开 = 应用 Fluent；关 = 恢复默认主题\n· 色板实时跟随系统外观 —— 系统深色用 Fluent 暗，系统浅色用 Fluent 亮；会话中切换系统明暗即时生效，无需重启\n· 结构 —— 左侧 NavigationView 导航窗格（WinUI 选中指示条）+ 大标题内容区\n· 排版 —— 控件统一 32pt 线 / 卡片 4pt 栅格 / 胶囊 80×32\n· 形状/字阶 —— 4/8/12pt 圆角 · Fluent2 字阶七档\n每次切换全界面即时重建。',
              confirm: isOn() ? '保持开启' : '开启 Fluent',
              cancel: isOn() ? '关闭 Fluent' : '关闭'
            }, function (ok) {
              if (ok) turnOn(false);
              else turnOff();
            });
          } catch (e) {
            // 对话框桥面异常时退化为直接切换
            if (isOn()) turnOff(); else turnOn(false);
          }
          return;
        }
        if (isOn()) turnOff(); else turnOn(false);
      }
    );
  } catch (e) {
    ame.log('[' + MARK + '] addLauncherRow failed: ' + e);
    return;
  }

  // ★ v2.5.0（Task379）：实时跟随系统明暗——开态下 appearance.changed 即
  //   换板 + 全维令牌重应用（引擎侧 token 变更自带根重建杠杆）。旧引擎
  //   （无事件面/无此事件）静默降级 = 仅装载期选色（v2.4.0 行为）。
  try {
    ame.on('appearance.changed', function (_ev, payload) {
      try {
        if (!isOn()) return;
        var ame379_dark = !!(payload && payload.dark);
        applyPalette(ame379_dark ? 1 : 0, true);
        ame.log('[' + MARK + '] appearance.changed -> palette ' + (ame379_dark ? 'fluent-dark' : 'fluent-light'));
      } catch (e2) {
        ame.log('[' + MARK + '] appearance.changed handler failed (non-fatal): ' + e2);
      }
    });
  } catch (e) {
    ame.log('[' + MARK + '] appearance.changed subscribe failed (old engine?): ' + e);
  }

  autoApply();

  ame.log('[' + MARK + '] fluent-ui v2.5.0 loaded（两态开关：开=NavigationView 全维度换装+色板实时跟随系统明暗，关=恢复默认）');
})();
