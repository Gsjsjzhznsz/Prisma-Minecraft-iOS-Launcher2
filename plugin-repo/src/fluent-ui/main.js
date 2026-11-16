// Task375 fluent-ui v2.4.0 —— 「两态开关 · 跟随系统明暗」版（用户指令：
// "flUI的开关能不能就2种状态，开和不开，浅色合深色跟随设置"）。
// ---------------------------------------------------------------------
// ★ v2.6.2（Task432 移交⑥：导航广播事件化）：壳侧根修 —— ZL2ShellViewController
//   showPageAtIndex 切页生效处现全量广播 ZL2ShellNavigateNotification（带 index
//   userInfo；此前侧边栏点按不广播，page.changed 事件面不完整）。本版订阅
//   page.changed（经 AmePluginRuntime 桥接）替代 200ms 轮询自愈主路径：
//     · 通道一（即时主路径，原有）：page.changed 双拍（260/900ms）—— 现已覆盖
//       全部切页（侧边栏点按/主页瓦片/程序化 openPage/返回主页）。
//     · 通道二（轮询退役）：200ms 周期自愈摘除，保留装载后一轮轻校验兜底
//       （2.2s 单拍，非循环）—— 覆盖装载期壳重建窗口与无事件面的旧引擎降级态。
//   蓝条纠偏本体（测量对差 + 幂等在位跳过）与 v2.6.1 一致，零语义变更。
// ---------------------------------------------------------------------
// ★ v2.6.1（fui-rail-fix）：NavigationView 选中指示条（蓝条）窗格底页错位
//   根修（插件侧最大能力版）。症状：蓝条随切页上下滑动正常，但驻「设置」
//   页时滑到「主页」旁（「文件」为瞬时动作不换选中，WinUI 语义本就保持
//   原选中行；其「错位」观感与设置页同源）。根因在原生壳
//   ZL2ShellViewController ame389_syncIndicatorYAnimated —— 共享蓝条驻主
//   列 paneStack，centerY 常量取 CGRectGetMidY(选中项.frame)；主列项 frame
//   是 paneStack 局部坐标 = 恒正确，而「设置」项驻窗格底部固定列
//   paneFooterStack（paneStack 的兄弟列），ame389 拿到的 frame 是
//   footerStack 局部坐标（行中点 ≈22pt）却被当 paneStack 坐标落约束 →
//   蓝条每次都滑到首行（主页）旁。另：侧边栏点按不广播
//   ZL2ShellNavigateNotification → page.changed 事件只覆盖主页瓦片/
//   程序化切页，事件面不完整（本版以周期自愈补齐）。
//   插件侧修复（ame.views 家族，manifest 增声明 ui.views；官方件装/更即
//   授权自愈）：
//     · 选中行判定零文案依赖（窗格项无 accessibilityIdentifier 可依）：
//       ame_setSelected 选中=不透明行底（describe.bg 7 位 #RRGGBB），
//       未选中=clearColor（9 位带 00）——本地化/色板/明暗全无关；兜底链
//       = page.changed index → 行内 UILabel 标题别名表（zh/en 实表）。
//     · 选中行为主列（parent == paneStack）→ 原生几何恒正确，零干预
//       （0.18s 蓝条滑动动画原样保留）。
//     · 选中行为 footer 列（设置）→ 测量纠偏：蓝条 centerY 应 = 选中行
//       中点在 paneStack 坐标系的位置 —— footerStack→paneWrap 与
//       paneStack→paneScroll→paneWrap 两条祖先链同基对差（链上全部取
//       superview 相对 frame，折叠 64/展开 280/窄屏抽屉全态成立），偏差
//       >1.5pt 时 ame.views.apply 纠 indicator frame.origin.y。
//     · 原生约束常量仍持旧值（桥面无改约束通道）→ 任何再布局（折叠/
//       旋转/主题重建/再切页）会把蓝条拉回错位处：200ms 周期自愈重校
//       + page.changed 双拍（260/900ms）即时通道 + 装载/手开/appearance
//       重建延迟校，全部幂等（在位即跳过，不重入不抖动）。
//   app 侧一行根治（本轮不动 Natives，仅留报告）：ame389 对选中项先
//     convertRect:toView:self.paneStack 再取 midY 即根治，插件纠偏可退役。
// ---------------------------------------------------------------------
// ★ v2.6.0（Task390）：用户可见文案去 ZL2 字样（对话框「非旧版主题换色」）；
//   版本随轮次演进 2.5.1 → 2.6.0。功能面与 v2.5.1 完全一致。
// ★ v2.5.1（Task380）：appearance 事件去重——Task346 根重建杠杆每次令牌
//   应用后整壳重建，新建壳 VC 的首次 trait 解析都会再发一次 appearance.changed
//   （dark 同值），旧实现无条件全量重应用令牌 → 重建 → 再发事件 = 无限反馈环
//   （装机 ~10 次/秒全界面拆建、完全不可点击实锤）。根修 = 事件处理器持
//   lastAppliedDark 进程态，同值事件直接跳过（不落任何令牌）；装载/手开
//   路径同步登记基线。与原生侧广播去重 + ZL2Theme 重建冷却构成三层防回环。
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

  // ★ v2.5.1（Task380）：已应用明暗基线（进程内变量，非持久化）——null = 尚未
  //   应用过。appearance 事件与装载路径共用：同值跳过 = 幂等，翻转才落令牌。
  var lastAppliedDark = null;
  function rememberAppliedDark(dark) { lastAppliedDark = !!dark; }

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
    var ame380_dark = systemIsDark();
    applyPalette(ame380_dark ? 1 : 0, silent);
    rememberAppliedDark(ame380_dark);   // ★ v2.5.1：手开路径登记基线（防后续同值事件重放）
    railScheduleSync(800);              // ★ v2.6.1：结构重建落定后蓝条自愈校准
    railScheduleSync(1600);
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
      if (isOn()) {
        var ame380_dark = systemIsDark();
        applyPalette(ame380_dark ? 1 : 0, true);
        rememberAppliedDark(ame380_dark);   // ★ v2.5.1：装载路径登记基线
        railScheduleSync(800);              // ★ v2.6.1：装载即校（壳若驻设置页/重建窗口期）
        railScheduleSync(1600);
      }
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
              body: 'Fluent 2 完整设计语言换装（真重排版，非旧版主题换色）：\n· 开关只有两态 —— 开 = 应用 Fluent；关 = 恢复默认主题\n· 色板实时跟随系统外观 —— 系统深色用 Fluent 暗，系统浅色用 Fluent 亮；会话中切换系统明暗即时生效，无需重启\n· 结构 —— 左侧 NavigationView 导航窗格（WinUI 选中指示条）+ 大标题内容区\n· 排版 —— 控件统一 32pt 线 / 卡片 4pt 栅格 / 胶囊 80×32\n· 形状/字阶 —— 4/8/12pt 圆角 · Fluent2 字阶七档\n每次切换全界面即时重建。',
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
        var ame380_dark = !!(payload && payload.dark);
        // ★ v2.5.1（Task380）：同值事件幂等跳过——新建壳 VC 首次 trait 解析
        //   与真实翻转在事件面上不可区分，只有值本身可信；同值落令牌即触发
        //   根重建再发同值事件的死环，故此处必须短路。
        if (lastAppliedDark !== null && ame380_dark === lastAppliedDark) {
          ame.log('[' + MARK + '] appearance.changed skipped (dark=' + ame380_dark + ' already applied)');
          return;
        }
        applyPalette(ame380_dark ? 1 : 0, true);
        rememberAppliedDark(ame380_dark);
        railScheduleSync(800);              // ★ v2.6.1：换板=根重建，新壳落定后蓝条自愈校准
        railScheduleSync(1600);
        ame.log('[' + MARK + '] appearance.changed -> palette ' + (ame380_dark ? 'fluent-dark' : 'fluent-light'));
      } catch (e2) {
        ame.log('[' + MARK + '] appearance.changed handler failed (non-fatal): ' + e2);
      }
    });
  } catch (e) {
    ame.log('[' + MARK + '] appearance.changed subscribe failed (old engine?): ' + e);
  }

  // ═══ v2.6.1 蓝条纠偏实施（ui.views 家族；全链 try-catch 包裹：权限缺失/
  //     非 fui 骨架/结构不识别一律静默跳过 = 零副作用降级）═══
  var RAIL_LAST_PAGE = -1;   // page.changed 最近页索引（标题别名兜底用）

  // page.changed index → 窗格项标题别名（zh/en 实表，对齐 resources
  // Localizable ame369.* / ame192.ai.title）。索引 3（账户内部宿主页）与
  // 文件（瞬时动作，不换选中也不发 page.changed）无窗格项 = 不入表。
  var RAIL_ALIASES = {
    0: ['主页', 'Home'],
    1: ['下载', 'Downloads'],
    2: ['版本', 'Versions'],
    4: ['设置', 'Settings'],
    5: ['多人联机', '联机', 'Multiplayer', 'Terracotta'],
    6: ['AI', '助手', 'Assistant']
  };

  // ui.views 可用性探测（声明+授权双闸，未过即抛 JS 异常）——只探一次，
  // 周期自愈不反复撞权限墙（每次被拒都会落审计日志）。
  var RAIL_VIEWS_OK = null;
  function railViewsAvailable() {
    if (RAIL_VIEWS_OK !== null) return RAIL_VIEWS_OK;
    try {
      ame.views.find({ limit: 1 });
      RAIL_VIEWS_OK = true;
    } catch (e) {
      RAIL_VIEWS_OK = false;
      ame.log('[' + MARK + '] ui.views unavailable（未声明或未授权，蓝条纠偏降级停用）: ' + e);
    }
    return RAIL_VIEWS_OK;
  }

  // 选中行判定：不透明行底（surfaceContainerHighest，动态色解析后 #RRGGBB
  // 7 位）= 选中；clearColor 解析 #RRGGBB00（9 位）= 未选中。
  function railIsOpaqueBg(bg) {
    return typeof bg === 'string' && bg.length === 7 && bg.charAt(0) === '#';
  }

  // parent 桥面只回 {handle,cls,text} 不带 frame → 从祖父的 children 里
  // 取回本节点（frame 为 superview 相对坐标，链上逐级累加即绝对坐标）。
  function railChildNode(parentHandle, handle) {
    var kids = null;
    try { kids = ame.views.children(parentHandle); } catch (e) { return null; }
    if (!kids) return null;
    for (var i = 0; i < kids.length; i++) {
      if (kids[i] && kids[i].handle === handle) return kids[i];
    }
    return null;
  }

  // 兜底链②：行内 UILabel 标题（窗格项本体非 UIButton，find 的 text 恒空）。
  function railItemTitle(itemHandle) {
    var kids = null;
    try { kids = ame.views.children(itemHandle); } catch (e) { return null; }
    if (!kids) return null;
    for (var i = 0; i < kids.length; i++) {
      if (kids[i] && kids[i].cls === 'UILabel' && kids[i].text) return kids[i].text;
    }
    return null;
  }

  function railAliasHit(itemHandle) {
    var set = RAIL_ALIASES[RAIL_LAST_PAGE];
    if (!set) return false;
    var t = railItemTitle(itemHandle);
    if (!t) return false;
    for (var i = 0; i < set.length; i++) {
      if (t === set[i] || t.indexOf(set[i]) >= 0) return true;
    }
    return false;
  }

  // 主列 paneStack 定位：持 ≥3 个窗格项的父栈（footerStack 只有 2 项，
  // 与列序无关地可分辨）。
  function railFindMainStack(items) {
    for (var i = 0; i < items.length && i < 6; i++) {
      var p = null, kids = null, n = 0;
      try { p = ame.views.parent(items[i].handle); } catch (e) { continue; }
      if (!p) continue;
      try { kids = ame.views.children(p.handle); } catch (e2) { continue; }
      if (!kids) continue;
      for (var k = 0; k < kids.length; k++) {
        if (kids[k] && kids[k].cls && kids[k].cls.indexOf('ZL2ShellNavItem') >= 0) n++;
      }
      if (n >= 3) return p;
    }
    return null;
  }

  // 单轮纠偏（幂等）：选中行判定 → 主列不干预 → footer 列测量对差 →
  // 偏差 >1.5pt 才落 views.apply（在位即跳过 = 不重入不抖动）。
  function railSyncOnce() {
    if (!isOn()) return;
    if (typeof ame.views === 'undefined' || !ame.views) return;
    if (!railViewsAvailable()) return;
    var items = null, i = 0;
    try { items = ame.views.find({ cls: 'ZL2ShellNavItem', limit: 12 }); } catch (e) { return; }
    if (!items || !items.length) return;                 // topbar 骨架/壳未建：无 rail 可修
    // ① 选中行：行底不透明判定（语言无关主判据）
    var sel = null;
    for (i = 0; i < items.length; i++) {
      var d = null;
      try { d = ame.views.describe(items[i].handle); } catch (e2) { d = null; }
      if (d && railIsOpaqueBg(d.bg)) { sel = items[i]; break; }
    }
    // ② 兜底：page.changed index → 标题别名表（bg 判读失效时）
    if (!sel && RAIL_LAST_PAGE >= 0) {
      for (i = 0; i < items.length; i++) {
        if (railAliasHit(items[i].handle)) { sel = items[i]; break; }
      }
    }
    if (!sel || !sel.frame) return;                      // 无选中（账户/瞬时页）= 原生自隐，不干预
    // ③ 主列项 = 原生几何恒正确（含 0.18s 滑动动画），零干预
    var paneStack = railFindMainStack(items);
    if (!paneStack) return;
    var selParent = null;
    try { selParent = ame.views.parent(sel.handle); } catch (e3) { return; }
    if (!selParent || selParent.handle === paneStack.handle) return;
    // ④ footer 列选中（设置）：paneWrap = 公共祖先（paneStack⊂paneScroll⊂paneWrap，
    //    footerStack⊂paneWrap），两条链同基对差 = 选中行中点在 paneStack 系的 Y
    var paneScroll = null, paneWrap = null;
    try { paneScroll = ame.views.parent(paneStack.handle); } catch (e4) { return; }
    if (!paneScroll) return;
    try { paneWrap = ame.views.parent(paneScroll.handle); } catch (e5) { return; }
    if (!paneWrap) return;
    var stackNode = railChildNode(paneScroll.handle, paneStack.handle);
    var scrollNode = railChildNode(paneWrap.handle, paneScroll.handle);
    var footNode = railChildNode(paneWrap.handle, selParent.handle);
    if (!stackNode || !scrollNode || !footNode ||
        !stackNode.frame || !scrollNode.frame || !footNode.frame) return;
    // ⑤ 共享蓝条 = paneStack 里唯一的 3×16 裸 UIView（行内占位指示条都在
    //    各项内部，不在此列）
    var kids = null, ind = null;
    try { kids = ame.views.children(paneStack.handle); } catch (e6) { return; }
    if (!kids) return;
    for (i = 0; i < kids.length; i++) {
      var k = kids[i];
      if (k && k.cls === 'UIView' && k.frame &&
          Math.abs(k.frame.w - 3) < 0.6 && Math.abs(k.frame.h - 16) < 0.8) { ind = k; break; }
    }
    if (!ind || !ind.frame) return;                      // 结构不识别（未来改版）：不盲动
    // ⑥ centerY 常量语义对齐原生（ame389_indicatorY = centerY 对 paneStack
    //    顶 + constant；frame.origin.y = constant − 半高）：
    //    目标 constant = 选中行中点（paneWrap 系）− paneStack 顶（paneWrap 系）
    var midAbs = sel.frame.y + sel.frame.h / 2 + footNode.frame.y;
    var stackTopAbs = stackNode.frame.y + scrollNode.frame.y;
    var targetY = midAbs - stackTopAbs - ind.frame.h / 2;
    if (Math.abs(ind.frame.y - targetY) <= 1.5) return;  // 已纠偏在位
    try { ame.views.apply(ind.handle, { y: targetY }); } catch (e7) {}
  }

  function railScheduleSync(delayMs) {
    try {
      setTimeout(function () { try { railSyncOnce(); } catch (e) {} }, delayMs || 50);
    } catch (e2) {}
  }

  // 通道一（即时主路径）：page.changed —— ★Task432 壳侧 showPageAtIndex 全量广播
  //   ZL2ShellNavigate 后，本事件已覆盖全部切页（侧边栏点按/主页瓦片/程序化切页/
  //   返回主页）；双拍 = 0.18s 指示条动画收拍后 + 重建二段确认。同页重复广播
  //   （幂等早退保护，不会重复发）由 railSyncOnce 在位即跳过拦住，零写面。
  try {
    ame.on('page.changed', function (_ev, payload) {
      try {
        var idx = payload && typeof payload.index === 'number' ? payload.index : -1;
        if (idx >= 0) RAIL_LAST_PAGE = idx;
        railScheduleSync(260);
        railScheduleSync(900);
      } catch (e) {}
    });
  } catch (e) {}
  // 通道二（轻校验兜底，★Task432 200ms 轮询退役）：壳侧全量广播补齐事件面后，
  //   周期轮询摘除；保留装载后一轮单拍（2.2s，非循环）——覆盖装载期壳重建
  //   落定窗口与旧引擎无事件面的降级态（在位即跳过 = 零写面）。
  railScheduleSync(2200);

  autoApply();

  ame.log('[' + MARK + '] fluent-ui v2.6.2 loaded（两态开关：开=NavigationView 全维度换装+色板实时跟随系统明暗，关=恢复默认；Task380 事件去重防回环；v2.6.1 蓝条 footer 页错位测量纠偏；v2.6.2 订阅 page.changed 替代 200ms 轮询，保留一轮轻校验兜底）');
})();
