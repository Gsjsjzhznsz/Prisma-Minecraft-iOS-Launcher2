// Task318 内置示例插件：启动统计（launch-counter）
// 演示：事件订阅（ame.on，events）+ 私有存储（storage）+ 贡献行（ui.rows）
//      + 对话框（ui.dialog）。
// 事件面：game.starting（payload=nil）/ game.exited（payload=退出码 NSNumber）。
(function () {
  if (typeof ame === 'undefined') return;

  var KEY = 'stats';

  function stats() {
    var s = ame.storage.get(KEY);
    return (s && typeof s === 'object') ? s : { starts: 0, lastExit: null };
  }

  function save(s) { ame.storage.set(KEY, s); }

  ame.on('game.starting', function (ev, payload) {
    var s = stats();
    s.starts = (s.starts || 0) + 1;
    save(s);
    ame.log('launch-counter: start #' + s.starts);
  });

  ame.on('game.exited', function (ev, code) {
    var s = stats();
    s.lastExit = (code === undefined || code === null) ? null : code;
    save(s);
  });

  ame.addLauncherRow(
    { id: 'show', title: '启动统计', subtitle: '查看累计启动次数与上次退出码' },
    function (rowId) {
      var s = stats();
      var exitText = (s.lastExit === null || s.lastExit === undefined)
        ? '暂无记录'
        : String(s.lastExit) + (Number(s.lastExit) === 0 ? '（正常退出）' : '');
      ame.dialog({
        title: '启动统计',
        body: '累计启动：' + (s.starts || 0) + ' 次\n上次退出码：' + exitText,
        confirm: '好'
      }, function (ok) {});
    }
  );

  ame.log('launch-counter loaded');
})();
