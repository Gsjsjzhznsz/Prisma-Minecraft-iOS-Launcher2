// Task318 内置示例插件：渲染器快切（renderer-quickswitch）
// 演示：ame.getRenderer（renderer.read）+ ame.setRenderer（renderer.write，高危）
//      + 贡献行（ui.rows）+ 对话框（ui.dialog）+ 私有存储（storage）。
// 切换写的是当前实例 profile 的 renderer 键（PLProfiles applyChanges 锁内），
// 下次启动游戏生效；后端层白名单由启动器执法，非法值会抛 invalid_value。
(function () {
  if (typeof ame === 'undefined') return;

  function rendererInfoText() {
    var info = ame.getRenderer();
    var list = (info && info.available) ? info.available : [];
    return {
      info: info,
      text: '当前：' + ((info && info.renderer) || '未知') +
            '\n后端：' + ((info && info.backend) || '默认') +
            '\n生效：' + ((info && info.effective) || '未知') +
            '\n可选：' + (list.length ? list.join(', ') : '未知')
    };
  }

  ame.addLauncherRow(
    { id: 'switch', title: '切换渲染器', subtitle: '在已安装渲染器之间循环切换（下次启动生效）' },
    function (rowId) {
      try {
        var info = ame.getRenderer();
        var list = (info && info.available) ? info.available : [];
        if (list.length < 2) {
          ame.toast('可用渲染器不足，无法切换');
          return;
        }
        var cur = info.renderer;
        var idx = list.indexOf(cur);
        var next = list[(idx + 1) % list.length];
        try {
          ame.setRenderer({ renderer: next });
          ame.storage.set('lastRenderer', next);
          ame.toast('渲染器已切换：' + next + '（下次启动生效）');
        } catch (e2) {
          // renderer.write 属高危权限，默认拒绝（fail-closed）
          ame.toast('切换被拒：请在 插件详情页 授予渲染器写入权限');
        }
      } catch (e) {
        ame.toast('读取渲染器信息失败');
      }
    }
  );

  ame.addLauncherRow(
    { id: 'info', title: '渲染器信息', subtitle: '查看当前渲染器/后端与全部可选值' },
    function (rowId) {
      try {
        var r = rendererInfoText();
        ame.dialog({ title: '渲染器信息', body: r.text, confirm: '好' }, function (ok) {});
      } catch (e) {
        ame.toast('读取渲染器信息失败');
      }
    }
  );

  ame.log('renderer-quickswitch loaded');
})();
