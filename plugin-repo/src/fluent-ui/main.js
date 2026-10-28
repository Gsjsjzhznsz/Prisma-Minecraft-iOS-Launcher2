// Task341 fluent-ui v2.0.0 —— 「完全重新设计 UI」版（用户点题：Fluent 插件
// 要完全重新设计 UI，而不是依旧使用 zl2 样式）。
// ---------------------------------------------------------------------
// v1.0.0 的形态本质 = 三套调色板 × 28 色令牌换色：UI 结构/形状/字体仍是
// Material 3（ZL2 出厂刻度），用户观感「依旧 zl2 样式」。v2 依托引擎新增
// 的形状/字体覆盖面（ZL2Theme ame341：五档圆角 + 七档字阶，ZL2 页面
// 71 处圆角 + 144 处字体全部经 getter 消费）交付完整 Fluent 2 设计语言：
//
//   · 形状（fluentui-apple Corner Radius 溯源）：控件统一 4pt 小圆角、
//     卡片 8pt、浮层/大容器 12pt —— M3 的 12/16/28 大圆角体系整体收紧，
//     这是 Fluent 与 M3 观感差异最大的形状签名。
//   · 字阶（fluentui-apple Fluent2 Typography ramp 溯源）：Title2 28S /
//     Title3 20S / Body1 17R (Strong 15SB) / Body2 15R / Caption1 13R ——
//     与 M3 刻度（22R 标题 / 14M 标签）完全不同的字重分布。
//   · 色板（fluentui-apple Brand/Neutral 溯源，v1 延续）：
//       fluent-light：品牌蓝 #0F6CBD + 中性分层（F5→EB）
//       fluent-dark ：品牌青 #4CC2FF + 暗面板分层（11→3B）
//       fluent-apple：混融 —— Fluent 骨架（形/字）× Apple 系统色（#007AFF
//                     + iOS systemGray6 分层）
//
// 交互纪律（主页整洁）不变：单行入口，点击循环 亮→暗→混融→恢复默认；
// 首次点击出说明对话框。持久化走桥面 __theme/__shape 装载期重放键。
// 全部调用 try-catch 包裹 —— 权限/桥面单点故障不得炸掉整插件。
(function () {
  if (typeof ame === 'undefined') return;

  var MARK = 'Task341-fluent';

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

  // 形状链独立容错：setThemeShape 失败（旧引擎/桥面异常）不阻塞色板应用，
  // 退化为 v1 形态（仅换色）——全维度与仅换色之间平滑降级。
  function applyShape() {
    try { ame.setThemeShape(FLUENT_SHAPE); } catch (e) {
      ame.log('[' + MARK + '] setThemeShape failed (old engine? color-only fallback): ' + e);
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
    applyShape();
    // '__theme'/'__shape' 由桥面 setThemeToken/setThemeShape 落盘（装载期
    // 重放键）——插件侧只持久化循环态。
    storageSet('fluent.idx', String(idx));
    try { ame.toast('已应用：' + pal.name + '（Fluent 2 全维度 · 新开页面/重启启动器全量生效）'); } catch (e) {}
    ame.log('[' + MARK + '] palette applied: ' + pal.key + ' (color+shape)');
  }

  function restoreDefault() {
    try { ame.setThemeToken({}); } catch (e) {
      ame.log('[' + MARK + '] reset failed: ' + e);
    }
    try { ame.setThemeShape({}); } catch (e) {
      ame.log('[' + MARK + '] shape reset failed: ' + e);
    }
    storageSet('fluent.idx', '-1');
    try { ame.toast('已恢复默认主题（embermire · M3 刻度）'); } catch (e) {}
    ame.log('[' + MARK + '] theme restored to default');
  }

  try {
    ame.addLauncherRow(
      { id: 'fluent-ui', title: 'Fluent UI', subtitle: 'Fluent 2 完整设计语言（点击循环）' },
      function (rowId) {
        var announced = storageGet('fluent.announced') === 'yes';
        if (!announced) {
          storageSet('fluent.announced', 'yes');
          try {
            ame.dialog({
              title: 'Fluent UI',
              body: 'Fluent 2 完整设计语言换装（非 ZL2 主题换色）：\n· 形状 —— 控件 4pt / 卡片 8pt / 浮层 12pt（M3 大圆角整体收紧）\n· 字阶 —— Title 28S/20S · Body 17R/15R · Caption 13R（Fluent2 ramp）\n· 色板 —— Fluent 亮（品牌蓝）/ Fluent 暗（品牌青）/ Fluent × Apple 混融\n点击本行循环切换，第 4 次恢复默认。重启启动器后自动重放。',
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

  ame.log('[' + MARK + '] fluent-ui v2 loaded（Fluent 2 全维度：色28+形状5+字阶7；主页贡献行「Fluent UI」，点击循环亮/暗/混融/默认）');
})();
