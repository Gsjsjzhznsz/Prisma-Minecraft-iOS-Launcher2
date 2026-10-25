// Task330 冒烟：忠实模拟 AmePluginBridge 权限闸 + addLauncherRow 注册链，
// 验证四个内置插件 JS 在"已授权"前提下能否注册贡献行（gen-2 仓内置件）。
const fs = require('fs');
const path = require('path');

const root = require('path').join(__dirname, '..', 'Natives', 'resources', 'builtin-plugins');
const dirs = fs.readdirSync(root).filter(d => !d.startsWith('.'));

for (const dir of dirs) {
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
  };

  const ame = {
    addLauncherRow: (s, c) => ameRaw.addLauncherRowHandler(s, c),
    toast: (t) => ameRaw.toastHandler(t),
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
