// Task332 内置勘测插件（plugin-survey）—— 用户点题"能不能搞个勘测插件功能"。
// 定位：插件系统的"体检仪"。与 native 侧三通道合围：
//   ① boot 期 bridge export self-check（AmePluginRuntime，桥面 JSExport 链）
//   ② 每件装载期 Task332 load census（facade/raw 双面 + rows + 异常）
//   ③ 本插件 = 用户主动触发的运行时全量勘测（方法面/权限面/异常面）
// 报告双出口：对话框首屏摘要 + ame.log 全量落 latestlog（grep Task332-survey）。
// 勘测纪律：一切探测 try-catch 包裹 —— 权限拒绝/桥面断链本身就是勘测数据，
// 任何单点故障不得中断整份报告。
(function () {
  if (typeof ame === 'undefined') return;

  var MARK = 'Task332-survey';

  function line(arr, s) { arr.push(s); }

  // 方法面清点：for-in（含原型链）枚举对象上全部键及其 typeof。
  // JSExport 导出方法在包装对象原型链上，for-in 可及；键数=0 是
  // "桥面未导出"的直接证据（与 native 自证 PASS/MISSING 联判）。
  function enumerate(label, obj, out) {
    if (typeof obj === 'undefined') { line(out, label + ': undefined'); return; }
    if (obj === null) { line(out, label + ': null'); return; }
    var keys = [];
    try {
      for (var k in obj) {
        var t = 'unknown';
        try { t = typeof obj[k]; } catch (e) { t = 'ERR:' + e; }
        keys.push(k + '(' + t + ')');
      }
    } catch (e) {
      line(out, label + ': enumerate failed -- ' + e);
      return;
    }
    line(out, label + ': ' + keys.length + ' key(s)');
    line(out, label + ' list: ' + (keys.length ? keys.join(', ') : '(empty)'));
  }

  // 权限执法面探测：声明权限内的 storage 走真调用（应通），
  // 未声明权限面（openPage 之外不乱触）只记录可达性，不实际执行。
  function probeStorage(out) {
    try {
      var probe = '__survey__' + String(Date.now());
      ame.storage.set(probe, 'ok');
      var back = ame.storage.get(probe);
      ame.storage.remove(probe);
      line(out, 'storage probe: ' + (back === 'ok' ? 'roundtrip OK' : 'roundtrip MISMATCH (' + back + ')'));
    } catch (e) {
      line(out, 'storage probe: DENIED/ERROR -- ' + e);
    }
  }

  function fullReport() {
    var out = [];
    line(out, '[' + MARK + '] plugin runtime survey begin');
    line(out, 'ame facade: ' + (typeof ame));
    enumerate('ame', ame, out);
    enumerate('ameRaw', (typeof ameRaw !== 'undefined') ? ameRaw : undefined, out);
    // 桥面代表方法直证（与 load census 口径一致）
    try { line(out, 'raw.log typeof: ' + typeof (typeof ameRaw !== 'undefined' ? ameRaw.log : undefined)); } catch (e) { line(out, 'raw.log probe ERR: ' + e); }
    try { line(out, 'raw.addLauncherRowHandler typeof: ' + typeof (typeof ameRaw !== 'undefined' ? ameRaw.addLauncherRowHandler : undefined)); } catch (e) { line(out, 'raw row probe ERR: ' + e); }
    line(out, 'ame.addLauncherRow typeof: ' + (ame && ame.addLauncherRow ? typeof ame.addLauncherRow : 'missing'));
    probeStorage(out);
    line(out, 'console bridge: ' + (typeof console) + ' / console.log: ' + (typeof console !== 'undefined' ? typeof console.log : 'n/a'));
    line(out, '[' + MARK + '] plugin runtime survey end');
    return out.join('\n');
  }

  function summary() {
    var ameT = typeof ame;
    var ameCount = 0;
    var rawT = (typeof ameRaw === 'undefined') ? 'undefined' : 'object';
    var rawCount = 0;
    try { for (var k in ame) ameCount++; } catch (e) {}
    try { for (var k2 in ameRaw) rawCount++; } catch (e) {}
    return 'ame=' + ameT + ' (' + ameCount + ' 方法)\n' +
           'ameRaw=' + rawT + ' (' + rawCount + ' 键)\n' +
           '行注册/日志/对话框可达。\n点「全量报告」落日志。';
  }

  ame.addLauncherRow(
    { id: 'survey', title: '插件勘测', subtitle: '体检 ame 门面 / ameRaw 桥面 / 权限执法面' },
    function (rowId) {
      var rep = fullReport();
      ame.dialog({
        title: '插件勘测',
        body: summary(),
        confirm: '全量报告',
        cancel: '关闭'
      }, function (ok) {
        if (!ok) return;
        // 全量报告分行走 ame.log → native NSLog → latestlog（grep Task332-survey）
        var lines = rep.split('\n');
        for (var i = 0; i < lines.length; i++) ame.log(lines[i]);
        ame.toast('勘测报告已落日志');
      });
    }
  );

  ame.log('plugin-survey loaded（勘测入口已注册：主页贡献行「插件勘测」）');
})();
