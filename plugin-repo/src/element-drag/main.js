// Task364 官方示例插件：元素拖拽（element-drag）
// 演示：ame.views 视图操纵家族（ui.views，高危）四入口 ——
//   find（按 cls/text 找元素）/ apply（移动）/ on('pan')（拖拽手势）/
//   reset（还原）+ 贡献行（ui.rows）+ 私有存储（storage，布局重放）。
// 用法：
//   ①「切换拖拽目标」——每次点按接管当前界面上下一个大块元素（循环），
//     接管后直接按住该元素拖到顺手的位置；
//   ②「应用已存布局」——按 {cls,text} 签名把拖好的偏移重放回当前界面；
//   ③「全部复位」——撤销本插件全部改动并清除已存布局。
// 布局重放时机：插件装载（app.launch）+ 手动点行；界面元素重排后签名
// 命中的第一个元素生效，无文本的纯容器不参与持久化（签名不稳定）。
(function () {
  if (typeof ame === 'undefined') return;

  var targets = [];      // 本会话已接管拖拽的句柄
  var cursor = -1;       // 循环选择游标
  var START_AREA = 12000; // 可拖候选的面积下限（pt²），只挑"看得见的大块"

  function describe(n) {
    var t = n.text ? '「' + n.text + '」' : '';
    return n.cls + t;
  }

  // 收集当前界面可拖候选：可视 + 够大，按发现序取前 12
  function collect() {
    var all;
    try { all = ame.views.find({ limit: 64 }); } catch (e) { all = null; }
    if (!all || !all.length) return [];
    var out = [];
    for (var i = 0; i < all.length; i++) {
      var n = all[i];
      if (n.hidden || n.alpha < 0.05) continue;
      var w = n.frame.w, h = n.frame.h;
      if (w < 60 || h < 40 || (w * h) < START_AREA) continue;
      out.push(n);
      if (out.length >= 12) break;
    }
    return out;
  }

  // 给元素挂 pan：began 记起点，changed 跟手，ended 存签名偏移
  function attach(n) {
    var h = n.handle;
    if (targets.indexOf(h) >= 0) return;
    var start = null;
    ame.views.on(h, 'pan', function (ev) {
      if (ev.state === 'began') {
        start = { x: ev.frame.x, y: ev.frame.y };
      } else if (ev.state === 'changed' && start) {
        ame.views.apply(h, { x: start.x + ev.tx, y: start.y + ev.ty });
      } else if (ev.state === 'ended' && start) {
        if (n.text) {
          try {
            var map = ame.storage.get('offsets') || {};
            map[n.cls + '|' + n.text] = { cls: n.cls, text: n.text, dx: ev.tx, dy: ev.ty };
            ame.storage.set('offsets', map);
          } catch (e) { /* 存储满等异常不影响拖拽本身 */ }
        }
        start = null;
      }
    });
    targets.push(h);
  }

  // 重放已存偏移：find 命中签名 → 当前坐标 + 偏移
  function replay() {
    var map;
    try { map = ame.storage.get('offsets'); } catch (e) { map = null; }
    if (!map) return 0;
    var hit = 0;
    for (var k in map) {
      if (!Object.prototype.hasOwnProperty.call(map, k)) continue;
      var o = map[k];
      var found;
      try { found = ame.views.find({ cls: o.cls, text: o.text, limit: 1 }); } catch (e) { found = null; }
      if (found && found.length) {
        var f = found[0].frame;
        try {
          ame.views.apply(found[0].handle, { x: f.x + o.dx, y: f.y + o.dy });
          hit++;
        } catch (e) { /* 单个失败不拖垮整轮重放 */ }
      }
    }
    return hit;
  }

  ame.addLauncherRow(
    { id: 'pick', title: '拖拽：切换目标', subtitle: '每次点按接管下一个大块元素，接管后按住即可拖动' },
    function () {
      try {
        var list = collect();
        if (!list.length) { ame.toast('当前界面没有可拖的大块元素'); return; }
        cursor = (cursor + 1) % list.length;
        var n = list[cursor];
        attach(n);
        ame.toast('已接管 ' + describe(n) + '（' + (cursor + 1) + '/' + list.length + '），按住它拖动；再点本行换下一个');
      } catch (e) {
        ame.toast('ui.views 未授权：请在 插件管理 → 元素拖拽 详情页开启"界面元素操纵"');
      }
    });

  ame.addLauncherRow(
    { id: 'replay', title: '拖拽：应用已存布局', subtitle: '把之前拖好的偏移按元素签名重放到当前界面' },
    function () {
      try {
        var hit = replay();
        ame.toast(hit ? ('已重放 ' + hit + ' 个元素的布局') : '没有已存布局（先拖动带文字的元素）');
      } catch (e) {
        ame.toast('重放失败：' + e);
      }
    });

  ame.addLauncherRow(
    { id: 'reset', title: '拖拽：全部复位', subtitle: '撤销本插件全部界面改动并清除已存布局' },
    function () {
      try {
        for (var i = 0; i < targets.length; i++) ame.views.reset(targets[i]);
        targets = [];
        cursor = -1;
        try { ame.storage.set('offsets', {}); } catch (e) { }
        ame.toast('已全部复位');
      } catch (e) {
        ame.toast('复位失败：' + e);
      }
    });

  // 装载即重放一次（随启动生效的布局语义）
  ame.on('app.launch', function () { replay(); });
})();
