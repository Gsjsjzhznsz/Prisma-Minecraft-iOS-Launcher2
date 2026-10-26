// Task318 内置示例插件：日落主题包（theme-sunset）
// 演示：ame.setThemeToken（ui.theme，高危）+ 贡献行（ui.rows）+ 私有存储（storage）。
// 全部主题令牌覆盖由启动器原生重放（storage.__theme 快照），无需插件监听启动事件。
(function () {
  if (typeof ame === 'undefined') return;

  var palettes = [
    {
      name: '日落',
      tokens: {
        primary: '#E8683C', onPrimary: '#FFFFFF',
        primaryContainer: '#FFD9CC', onPrimaryContainer: '#3E1505',
        secondary: '#D9A38C', onSecondary: '#3A1E10',
        secondaryContainer: '#5C3A28', onSecondaryContainer: '#FFD9CC',
        tertiary: '#C79B56', onTertiary: '#3D2A05',
        tertiaryContainer: '#5B4118', onTertiaryContainer: '#FFDDB4',
        surface: '#1A120D', onSurface: '#F1DFD5',
        onSurfaceVariant: '#D3B5A6', surfaceVariant: '#52443C',
        surfaceContainerLowest: '#140D09', surfaceContainerLow: '#221811',
        surfaceContainer: '#261C15', surfaceContainerHigh: '#31261E',
        surfaceContainerHighest: '#3C3028', surfaceBright: '#3C3028',
        outline: '#9C8172', outlineVariant: '#52443C',
        error: '#FFB4A5', errorContainer: '#93000A',
        success: '#8FD694', warning: '#FFB959'
      }
    },
    {
      name: '森林',
      tokens: {
        primary: '#7CB86A', onPrimary: '#0E2B06',
        primaryContainer: '#254D17', onPrimaryContainer: '#B4F0A0',
        secondary: '#9DBE8F', onSecondary: '#17290F',
        secondaryContainer: '#2E4024', onSecondaryContainer: '#C9E7BB',
        tertiary: '#7EB7A5', onTertiary: '#0A2B23',
        tertiaryContainer: '#264339', onTertiaryContainer: '#B8EEDC',
        surface: '#12170F', onSurface: '#E0E4D9',
        onSurfaceVariant: '#C2C9B8', surfaceVariant: '#43483D',
        surfaceContainerLowest: '#0C110A', surfaceContainerLow: '#1A1F16',
        surfaceContainer: '#1E231A', surfaceContainerHigh: '#282D23',
        surfaceContainerHighest: '#33382D', surfaceBright: '#33382D',
        outline: '#8C9383', outlineVariant: '#43483D',
        error: '#FFB4A5', errorContainer: '#93000A',
        success: '#8FD694', warning: '#FFB959'
      }
    },
    {
      name: '海洋',
      tokens: {
        primary: '#7EB9E8', onPrimary: '#003251',
        primaryContainer: '#1A4B70', onPrimaryContainer: '#C8E6FF',
        secondary: '#8FBEDE', onSecondary: '#0D2A3B',
        secondaryContainer: '#2A4A5E', onSecondaryContainer: '#C8E6FF',
        tertiary: '#96AFC9', onTertiary: '#132B42',
        tertiaryContainer: '#2C4761', onTertiaryContainer: '#D5E3FF',
        surface: '#0F151A', onSurface: '#DFE3E8',
        onSurfaceVariant: '#C0C8CE', surfaceVariant: '#3F4850',
        surfaceContainerLowest: '#0A0F14', surfaceContainerLow: '#171D22',
        surfaceContainer: '#1B2127', surfaceContainerHigh: '#252B31',
        surfaceContainerHighest: '#30363C', surfaceBright: '#30363C',
        outline: '#8A9298', outlineVariant: '#3F4850',
        error: '#FFB4A5', errorContainer: '#93000A',
        success: '#8FD694', warning: '#FFB959'
      }
    },
    {
      name: '玫瑰',
      tokens: {
        primary: '#E87BA4', onPrimary: '#40102A',
        primaryContainer: '#5D2C44', onPrimaryContainer: '#FFD9E6',
        secondary: '#DCA9BE', onSecondary: '#3B1C2C',
        secondaryContainer: '#533243', onSecondaryContainer: '#FFD9E6',
        tertiary: '#C9A0C4', onTertiary: '#3B1340',
        tertiaryContainer: '#532A57', onTertiaryContainer: '#FFD7FB',
        surface: '#1A1116', onSurface: '#F0DEE7',
        onSurfaceVariant: '#D5B8C6', surfaceVariant: '#51434B',
        surfaceContainerLowest: '#140B10', surfaceContainerLow: '#22161C',
        surfaceContainer: '#261A20', surfaceContainerHigh: '#31242A',
        surfaceContainerHighest: '#3C2E35', surfaceBright: '#3C2E35',
        outline: '#99828F', outlineVariant: '#51434B',
        error: '#FFB4A5', errorContainer: '#93000A',
        success: '#8FD694', warning: '#FFB959'
      }
    }
  ];

  var KEY = 'paletteIndex';

  function currentIdx() {
    var v = ame.storage.get(KEY);
    return (typeof v === 'number' && v >= 0 && v < palettes.length) ? v : -1;
  }

  // idx = -1 表示清除全部覆盖（恢复启动器默认主题）
  function applyPalette(idx) {
    try {
      ame.setThemeToken(idx < 0 ? null : palettes[idx].tokens);
      ame.storage.set(KEY, idx);
      return true;
    } catch (e) {
      // 高危权限默认拒绝（fail-closed）：引导用户去详情页授权
      try { ame.toast('需要主题权限：请在 插件详情页 授权后重试'); } catch (e2) {}
      return false;
    }
  }

  ame.addLauncherRow(
    { id: 'cycle', title: '切换配色', subtitle: '循环四套精选主题（日落/森林/海洋/玫瑰）' },
    function (rowId) {
      var idx = currentIdx();
      var next = (idx + 1 + 1) % (palettes.length + 1) - 1; // -1(默认)→0→1→2→3→-1
      if (applyPalette(next)) {
        ame.toast(next < 0 ? '已恢复默认主题' : '已切换：' + palettes[next].name);
      }
    }
  );

  ame.addLauncherRow(
    { id: 'reset', title: '恢复默认主题', subtitle: '清除本插件全部颜色覆盖' },
    function (rowId) {
      if (applyPalette(-1)) ame.toast('已恢复默认主题');
    }
  );

  ame.log('theme-sunset loaded, palettes=' + palettes.length);
})();
