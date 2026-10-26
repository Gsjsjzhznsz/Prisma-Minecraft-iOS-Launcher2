// Task318 内置示例插件：Modrinth 热门榜（modrinth-hot）
// 演示：ame.fetch（net，高危；30s 超时，回调回主线程）+ 贡献行（ui.rows）
//      + 对话框（ui.dialog）。
// 回调签名：cb(err, resp)——err 为字符串或 null；resp = { status, body }。
(function () {
  if (typeof ame === 'undefined') return;

  var API = 'https://api.modrinth.com/v2/search?limit=5&index=downloads';

  function showDialog(msg) {
    ame.dialog({ title: 'Modrinth 热门榜', body: msg, confirm: '好' }, function (ok) {});
  }

  ame.addLauncherRow(
    { id: 'top5', title: 'Modrinth 热门榜', subtitle: '拉取下载量前五的模组（需联网权限）' },
    function (rowId) {
      try {
        ame.fetch(API, function (err, resp) {
          if (err) {
            showDialog('拉取失败：' + err);
            return;
          }
          if (!resp || resp.status !== 200) {
            showDialog('拉取失败：HTTP ' + ((resp && resp.status) || '无响应'));
            return;
          }
          try {
            var data = JSON.parse(resp.body);
            var hits = (data && data.hits) ? data.hits : [];
            var lines = [];
            for (var i = 0; i < hits.length && i < 5; i++) {
              var h = hits[i];
              var dl = (typeof h.downloads === 'number') ? h.downloads : 0;
              lines.push((i + 1) + '. ' + (h.title || h.slug || '未知') +
                         '（' + dl + ' 次下载）');
            }
            showDialog(lines.length ? lines.join('\n') : '暂无数据');
          } catch (e) {
            showDialog('解析失败：返回数据不是有效 JSON');
          }
        });
      } catch (e) {
        // net 属高危权限，默认拒绝（fail-closed）时桥接抛 denied 异常
        showDialog('需要联网权限：请在 插件详情页 授权后重试');
      }
    }
  );

  ame.log('modrinth-hot loaded');
})();
