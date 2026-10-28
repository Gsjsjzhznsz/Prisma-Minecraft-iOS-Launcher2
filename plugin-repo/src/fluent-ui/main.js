// Task338 内置主题插件（fluent-ui）—— 用户点题"能不能依据 Fluent Apple
// 写一个 Fluent UI 启动器插件，放到仓库里面"。
// 定位：Fluent 2 / Apple 材质令牌的整套启动器换装（ZL2Theme 28 令牌全量）。
//   · fluent-light  ：Fluent 2 亮色 —— 品牌蓝 #0F6CBD + 中性分层（F5→EB）
//   · fluent-dark   ：Fluent 暗色   —— 品牌青 #4CC2FF + 暗面板分层（11→3B）
//   · fluent-apple  ：混融          —— Fluent 骨架 × Apple 系统色（#007AFF
//                                      + iOS systemGray6 分层）
// 交互纪律（主页整洁）：单行入口，点击循环 亮→暗→混融→恢复默认；首次点击
// 出说明对话框。持久化走 storage '__theme'（native 侧装载期自动重放）。
// 全部调用 try-catch 包裹 —— 权限/桥面单点故障不得炸掉整插件。
(function () {
  if (typeof ame === 'undefined') return;

  var MARK = 'Task338-fluent';

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
  function storageRemove(key) {
    try { return ame.storage.remove(key); } catch (e) { return false; }
  }

  function currentIndex() {
    var raw = storageGet('fluent.idx');
    var n = parseInt(raw, 10);
    return (isNaN(n) || n < 0 || n >= PALETTES.length) ? -1 : n;
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
    // '__theme' 为 native 装载期重放键（AmePluginRuntime：有 ui.theme 授权时
    // 读取并以 NSDictionary 应用）—— 持久化与即时应用双通道同源。
    storageSet('__theme', pal.tokens);
    storageSet('fluent.idx', String(idx));
    try { ame.toast('已应用：' + pal.name + '（新开页面/重启启动器全量生效）'); } catch (e) {}
    ame.log('[' + MARK + '] palette applied: ' + pal.key);
  }

  function restoreDefault() {
    try { ame.setThemeToken({}); } catch (e) {
      ame.log('[' + MARK + '] reset failed: ' + e);
    }
    storageRemove('__theme');
    storageSet('fluent.idx', '-1');
    try { ame.toast('已恢复默认主题（embermire）'); } catch (e) {}
    ame.log('[' + MARK + '] theme restored to default');
  }

  try {
    ame.addLauncherRow(
      { id: 'fluent-ui', title: 'Fluent UI 主题', subtitle: 'Fluent 2 × Apple 令牌换装（点击循环）' },
      function (rowId) {
        var announced = storageGet('fluent.announced') === 'yes';
        if (!announced) {
          storageSet('fluent.announced', 'yes');
          try {
            ame.dialog({
              title: 'Fluent UI 主题',
              body: '依据 Fluent 2 / Apple 材质令牌的整套换装：\n· Fluent 亮色 —— 品牌蓝 + 中性分层\n· Fluent 暗色 —— 暗面板分层\n· Fluent × Apple 混融 —— Apple 系统色\n点击本行循环切换，第 4 次恢复默认。令牌全量 28 项，主题在重放后跨启动保留。',
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

  ame.log('[' + MARK + '] fluent-ui loaded（主题行已注册：主页贡献行「Fluent UI 主题」，点击循环亮/暗/混融/默认）');
})();
