**Round 8 status — JIT26ExecPreflight is shipped (build Task451+), and one scope clarification from today's owner-device forensics.**

**1. Preflight shipped (round-7 deliverable, builds Task451/452/453 · 2026-11-19)**

As promised in round 6, the Witch-style **JIT26ExecPreflight** is now in the launcher:

- At game launch, before the JVM enters, the launcher allocates a fresh 64 MB region shaped exactly like libjvm's mirror request (`brk #0xf00d / x16=1` → `JIT26PrepareRegion(NULL, 64MB)` → debugger `_M<len>,rx`) and runs a **zero-fetch execution probe** in it under signal guards: SIGILL = healthy grant (mapped + executable, all-zero UDF trap), SIGBUS/SEGV = fake-positive (alias-pool shell) → **refuse-to-launch with the four-step remediation dialog** instead of a SIGBUS black screen. 3 fresh-allocation retries; all indeterminate outcomes pass through (worst case = pre-Task451 behavior, your ame273/ame442 chain still catches it downstream).
- Conviction marker: `ame451_preflight_conviction.txt` in the app Documents folder (`verdict=conviction` = degraded channel detected at grant time; a PASS clears stale convictions).
- Escape hatch: `debug.jit26_preflight_disable=YES` restores the exact pre-Task451 behavior.

Your two-run evidence set is still exactly what we need to close this out: `latestlog.txt` showing `[Ame451] preflight attempt N PASSED` (or the conviction marker) against a degraded-channel session.

**2. Scope clarification — the "crash on open" family is NOT JIT26**

Today the owner hit a separate "launcher crashes immediately on open" bug (iPadOS 27.0.1, LiveContainer 3.8.10) and we root-caused it by symbolication of the on-device crash report against the shipped dSYM:

- Crash: PC=0 / `EXC_BAD_ACCESS` / `CODESIGNING Invalid Page`, ~320 ms after launch, main thread, inside `dispatch_once` on the shell `viewDidLoad` path.
- Root cause: an ObjC type confusion in the **wallpaper card-family color matching** introduced by the Task450② wallpaper-transparency round — a `UIColor` array was iterated with a block-typed loop variable and the color object was then *called as a block* (reading offset 16 of a UIColor as a block invoke pointer → jump to NULL). Wallpaper users only; invisible to CI (no wallpaper in the harness) and to the compiler. Fixed in Task453, plus a repo-wide static gate for the whole bug family (block-typed `for-in` loop variables + `dispatch_once` non-literal block arguments).

Why this matters here: we had suspected the launcher-UI crash shared the JIT26 empty-RX channel (and shipped a JSC-interpreter pinning for the plugin engine as a defensive measure in Task452 — kept, it's harmless). **That suspicion is retracted**: the launcher-UI crash was never JIT26-related. JIT26 in this issue remains exactly what your rounds 1–7 evidence convicted: the debugger-grant RX channel for the JVM at **game launch**. Your conviction chain and the preflight above are unchanged by this.

Keeping this open as agreed — please send the next two-run evidence set against build Task451 or newer (BuildTag is shown in Settings → About, and in the preview-card corner chip).
