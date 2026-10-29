// Task330 冒烟：忠实模拟 AmePluginBridge 权限闸 + addLauncherRow 注册链，
// 验证内置件 JS 在"已授权"前提下能否注册贡献行。
// ★ Task333：扫描面 = bundle builtin-plugins + plugin-repo/src（上仓迁移
//   后四件演示件的源码位），rows 总数口径不变（survey 1 + modrinth-hot 1
//   + launch-counter 1 + quickswitch 2 + sunset 2 = 7）。
const fs = require('fs');
const path = require('path');

const roots = [
  path.join(__dirname, '..', 'Natives', 'resources', 'builtin-plugins'),
  path.join(__dirname, '..', 'plugin-repo', 'src'),
];
const seen = new Set();
for (const root of roots) {
  if (!fs.existsSync(root)) continue;
  const dirs = fs.readdirSync(root).filter(d => !d.startsWith('.'));

  for (const dir of dirs) {
    if (seen.has(dir)) continue;   // bundle 与 repo 源同 id 只跑一次
    seen.add(dir);
    const manifest = JSON.parse(fs.readFileSync(path.join(root, dir, 'manifest.json'), 'utf8'));
    const source = fs.readFileSync(path.join(root, dir, 'main.js'), 'utf8');
  const declared = new Set(manifest.permissions || []);
  const granted = new Set(manifest.permissions || []); // Task326 首方信任：全量授
  const rows = [];
  const events = {};
  const calls = [];

  const requirePerm = (perm) => {
    const ok = declared.has(perm) && granted.has(perm);
    if (!ok) calls.push('DENIED:' + perm);
    return ok;
  };

  const ameRaw = {
    addLauncherRowHandler: (spec, cb) => {
      if (!requirePerm('ui.rows')) return;
      if (!spec || !spec.id || typeof cb !== 'function') return;
      rows.push({ id: manifest.id + '.' + spec.id, title: spec.title });
    },
    toastHandler: (t) => { if (requirePerm('ui.dialog')) calls.push('toast:' + t); },
    dialogHandler: (spec, cb) => { if (requirePerm('ui.dialog')) calls.push('dialog:' + (spec && spec.title)); },
    onHandler: (ev, cb) => { if (requirePerm('events')) (events[ev] = events[ev] || []).push(cb); },
    logHandler: (m) => calls.push('log:' + m),
    getRendererHandler: () => { requirePerm('renderer.read'); return { renderer: 'hindl', backend: 'auto', effective: 'hindl', available: ['hindl', 'mg'] }; },
    setRendererHandler: (o) => { if (!requirePerm('renderer.write')) throw new Error('denied'); return true; },
    storageSetHandler: (k, v) => { if (!requirePerm('storage')) throw new Error('denied'); },
    storageGetHandler: (k) => { if (!requirePerm('storage')) throw new Error('denied'); return undefined; },
    // ★ Task341：色/形状令牌桩（fluent-ui v2 全维度链覆盖：色28+形状5+字阶7）
    setThemeTokenHandler: (t) => { if (!requirePerm('ui.theme')) throw new Error('denied'); calls.push('token:' + Object.keys(t || {}).length); return true; },
    setThemeShapeHandler: (t) => { if (!requirePerm('ui.theme')) throw new Error('denied'); calls.push('shape:' + Object.keys(t || {}).length); return true; },
    setThemeLayoutHandler: (t) => { if (!requirePerm('ui.theme')) throw new Error('denied'); calls.push('layout:' + Object.keys(t || {}).length); return true; },
  };

  const ame = {
    addLauncherRow: (s, c) => ameRaw.addLauncherRowHandler(s, c),
    toast: (t) => ameRaw.toastHandler(t),
    setThemeToken: (t) => ameRaw.setThemeTokenHandler(t),
    setThemeShape: (t) => ameRaw.setThemeShapeHandler(t),
    setThemeLayout: (t) => ameRaw.setThemeLayoutHandler(t),
    dialog: (s, c) => ameRaw.dialogHandler(s, c),
    on: (e, c) => ameRaw.onHandler(e, c),
    log: (m) => ameRaw.logHandler(m),
    getRenderer: () => ameRaw.getRendererHandler(),
    setRenderer: (o) => ameRaw.setRendererHandler(o),
    storage: { set: (k, v) => ameRaw.storageSetHandler(k, v), get: (k) => ameRaw.storageGetHandler(k) },
  };

  try {
    new Function('ame', source)(ame);
    console.log(`[${manifest.id}] rows=${rows.length} events=${Object.keys(events).join(',') || '-'} calls=${calls.length ? calls.slice(0, 4).join(' | ') : '-'}`);
    rows.forEach(r => console.log(`   row: ${r.id} -- ${r.title}`));
  } catch (e) {
    console.log(`[${manifest.id}] JS EXCEPTION: ${e.message}`);
  }
  }
}
console.log(`smoke total plugins=${seen.size} rows=7 expected`);
