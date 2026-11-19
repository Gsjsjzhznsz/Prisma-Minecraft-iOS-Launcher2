# Issue #3 round comment — Task457 (450076f44)

The `LiveContainer-2026-11-19-232437.ips` you attached is a **new, third crash signature** — and this time it is not the hollow-RX mapping family (Ame437/Task438) nor a preflight conviction case (Ame451). Decoded from the log:

**Crash chain (symbolicated against build `bca7c538` = the Task456 build you are running):**

```
[SnowbbQOS background thread]
___40-[SurfaceViewController launchMinecraft]_block_invoke +2860
  → _launchJVM +3400
  → _init_bypassDyldLibValidation +472
  → _searchAndPatch("dyld_mmap") +372
  → _JIT26PrepareRegionForPatching +4   ← brk #0xF00D (EXC_BREAKPOINT brk 61453)
```

**What that means.** The dyld library-validation bypass on TXM devices patches `dyld_mmap`/`dyld_fcntl` inside the dyld shared cache. Before writing the patch, the launcher must ask the JIT debugger to "prepare the page for patching" via a `brk #0xf00d` hypercall with opcode 4. Your debugger's script (`UniversalJIT26.js` `commands[4]`) is supposed to catch that trap; in your 23:24:35 session nobody answered it (note: the op1 channel was still alive seconds earlier — the Ame451 64MB preflight passed right before `found dyld_mmap`), so the naked trap killed the process instantly.

**Task457 turns this crash into a graceful, actionable failure:**

1. **Safe wrappers** for the whole `brk #0xf00d` family used by the launcher (op1/op4): Task91-style SIGTRAP signal net (no-debugger case) + Task301-style 20 s bounded watchdog (dead-port hang case). Unanswered trap → diagnostic, not death.
2. **op4 channel canary**: before touching any dyld text page, the launcher round-trips one op4 on a scratch page. Dead channel → the bypass aborts cleanly with a dialog.
3. **Write-back verification**: after patching, the patched bytes are read back; "answered but not effective" cases now abort the hook instead of launching a JVM with a half-applied patch (this also closes the silent-SIGBUS half-write family).
4. **Actionable dialog** (`i18n_str_ame457_dyldhook`, 54 locales) with the same 4-step ladder as the Ame451 preflight: fully restart the debugger app → re-assign `UniversalJIT26.js` → delete the per-app JIT entry and re-enable → update/switch the JIT enabler.

**Zero-regression note:** when the debugger is healthy, every op1/op4 round-trip behaves byte-identical to before (the signal net never fires on the Mach path) — the logs will show `op4 canary verdict=1` + `hook dyld_mmap succeed!`. The guard only changes the outcome in the two failure shapes (no debugger / dead port) that previously crashed or hung.

Side note from your screenshots (IMG_0730/0731): the Task455/456 launcher-UI fixes are in their verified-good state on your iPad Air (ZL2 sidebar expanded/collapsed, gear present, full-bleed layout), so this round's scope is exactly the game-launch crash above. If a future crash still lands at `JIT26PrepareRegionForPatching+4`, that is the remaining un-guardable shape (debugger present but its op4 handler passes the exception through) — please attach the log and we will treat it as debugger-side script-defect evidence.
