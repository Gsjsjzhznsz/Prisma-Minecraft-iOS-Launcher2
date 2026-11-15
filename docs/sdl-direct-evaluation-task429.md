# Task429 · PDF 第五版 §6.2「SDL 直连评估」落卷

- 工位：429-K（全局顺序 Task ID：2-e）
- 仓库：/home/z/my-project/work429，分支 task381（与 origin/main 同步，HEAD 12b8e6b）
- 日期：2026-11-15
- 性质：研究 + 文档，零生产代码改动（本任务仅新建本文件）
- 输入：PDF 第五版 §6.2 论断摘要 + 仓库现状逐条取证（所有行号为本仓 task381 分支实际行号，已在落卷前逐条 grep/Read 验证）

---

## 0. PDF 论断判定总表（先给结论，行号证据见后文各节）

| # | PDF 论断 | 判定 | 关键证据 |
|---|---------|------|---------|
| 1 | 我方手柄当前走 GLFW 兜底桥同构直通链路 | **证实（含精度修正）** | ControllerInput.m:75-129 → input_bridge_v3.m:2473-2556 双路派发；「兜底」仅对 ≤26.2 成立，26.3 会话实际走 B 链 SDL_PushEvent（见 §1.3） |
| 2 | SDL 直连未实现 | **证实** | 全仓 Natives/ 零 `SDL_Gamepad`/`SDL_GameController` 引用（grep 实证）；SDL_InitSubSystem 劫持已存在但只用于 hint 注入（sdl3_hook.m:2042-2071），无手柄子系统灌入 |
| 3 | Android 侧用 bytehook（PLT hook）劫持 SDL_InitSubSystem | **证实** | sdl3_hook.m:1-2 自述移植自 ZL2 Android 端 bytehook 版 sdl_hook.c |
| 4 | iOS 无 libhooker 级运行时 PLT hook 稳定公开方案 | **证实，但需补强** | 无公开框架属实；但本仓已有自研等价拦截栈（fishhook + Task132/134 Mach-O 间接符号槽重绑定 + dlsym 按名分发），SDL_InitSubSystem 在 iOS **已可稳定劫持**（见 §2、§4 修正项 K4） |
| 5 | 替代路径 = 改 LWJGL 打包源（SDLInit 回调改显式注册）或 dlopen 时机控制 | **证实（命名精度修正）** | JavaApp/src/lwjgl 源覆盖层 + GLFW.java:534 System.load 为 JNI_OnLoad 唯一触发器；main_hook.m:854+ hooked_dlopen 有 libSDL3 加载感知面。改的是 LWJGL 打包源加载块/SDL 绑定类，非「SDLInit 回调」本身（见 §3） |
| 6 | 收益：新版本 MC（26.3+）兼容 | **证实** | 双轨 LWJGL 333/341（Makefile:960-966）；26.3+ SDL3 通路为既成事实（README.md:65,142）；直连可消除 Task229 式曲线注册的结构债（input_bridge_v3.m:264-275） |
| 7 | 收益：SDL GameController 数据库即插即用 | **修正（部分成立）** | 前提是消费方读 SDL 手柄事件：vanilla MC 26.3 是否消费 SDL_Gamepad 事件本仓无法验证；controlify（26.1.2）走 libsdl4j 且其 SDL 事件过滤器被 Task131/135 拦截（sdl3_hook.m:2078-2124, scripts/patch_sdl3_eventfilter_guard.py）。需 spike 定案（§4） |
| 8 | 收益：陀螺仪经 SDL sensor 统一 | **修正（部分成立）** | SDL3 iOS sensor 后端与本仓 GyroInput 同源（都基于 CoreMotion）；统一消除双 CMMotionManager 并行，但 SDL sensor 无死域/平滑语义，GyroInput 的 ZL2 对标四参（死域/窗口）需在灌入侧重建；MC 消费面同样待 spike（§4） |
| 9 | 结论：可行但非紧急，P2；先以 Mapped 模式增强过渡（Task428 已交付手势可配置动作+陀螺仪四参） | **证实** | worklog.md:5179 P2 移交清单明列「6.2 SDL 直连评估（LWJGL 改包）」；Task428 手势/陀螺仪证据链完整（§5） |

---

## 1. 现状事实（仓库内证据，逐条文件+行号）

### 1.1 手柄事件链路（input/ 目录：GCController → 桥 → LWJGL/GLFW 路径）

**注册与断连（SurfaceViewController.m）**
- `Natives/SurfaceViewController.m:1628-1633`：`GCControllerDidConnectNotification` 观察者 → `[ControllerInput initKeycodeTable]` + `[ControllerInput registerControllerCallbacks:]`。
- `Natives/SurfaceViewController.m:1650-1654`：`GCControllerDidDisconnectNotification` → `unregisterControllerCallbacks:`。
- `Natives/SurfaceViewController.m:1657-1659`：启动时已连一台手柄的补注册兜底（`GCController.controllers.count == 1`）。
- `Natives/SurfaceViewController.m:1616`：`GCMouseDidDisconnectNotification`；`:4690-4715`：GCMouse 三键 + 滚轮 handler 直发 `CallbackBridge_nativeSendMouseButton/nativeSendScroll`（辅助键上限 5 个，`:4702-4706`）。

**事件翻译（Natives/input/ControllerInput.m，325 行）**
- `:62-73` `initKeycodeTable`：从 `POJAV_HOME/controlmap/gamepads/<control.default_gamepad_ctrl>` 解析 JSON → `gameMap`/`menuMap` 两张「gamepad_button → keycode」映射表（目录由 `Natives/main.m:361-368` 启动期建好；出厂映射为 `controls/gamepads/gamepad_default.json`（16 条）与 `gamepad_switch.json`）。
- `:75-129` `sendKeyEvent:pressed:`：GCController 键（`GLFW_GAMEPAD_BUTTON_*` 位置语义常量，见 `Natives/glfw_keycodes.h:311` 起）经映射表查 keycode 后分发：
  - 键盘形 → `CallbackBridge_nativeSendKey`（`:104,:126`）；
  - 鼠标三键（SPECIALBTN_*，`Natives/utils.h:166` 起）→ `CallbackBridge_nativeSendMouseButton`（`:108,:111,:114`）；
  - 模拟滚轮 → `CallbackBridge_nativeSendScroll`（`:117,:120`，Task310 速度系数 `:48-56`）。
- `:131-248` `registerControllerCallbacks:`：extendedGamepad 全元素 pressedChangedHandler/valueChangedHandler → `sendKeyEvent:`（肩/扳机/背键/菜单/Home/ABXY/十字/双摇杆按压）。
- `:195-235` 左摇杆：非抓取态喂虚拟鼠标；抓取态八方向量化 → WASD 四键 `CallbackBridge_nativeSendKey`（Task223 上游同步：死区判定用「或」`:208`）。
- `:236-241,:253-275` 右摇杆 + `tick`：虚拟鼠标增量 → `[SurfaceViewController sendTouchPoint:withEvent:ACTION_MOVE_MOTION]`（`:269-272`），60Hz 归一 + 速度平方加速（`:259-267`）。
- `:37-46` Task310 任天堂布局 A↔B/X↔Y 交换（`control.nintendo_layout`，映射查询前生效）。
- `:277-297,:299-323` 断连全量释放（WASD/Shift/鼠标三键/滚轮/虚拟鼠标锁存）后摘 handler。

**关键定性**：手柄的全部输出都汇入 `CallbackBridge_nativeSend*` 三入口——与触屏键盘/鼠标输入**同构**。`GLFW_GAMEPAD_BUTTON_*` 在本仓只是映射表的位置语义标签，从不成为 GLFW gamepad API 调用；桥的另一侧也不存在 SDL gamepad 事件。

### 1.2 GameSurfaceView.m 与 SurfaceViewController.m 的 GLFW 桥事件路径

- `Natives/GameSurfaceView.m`（89 行）不承载输入：它是渲染表面宿主（layerClass 按 `ame_effective_renderer` 选 CAMetalLayer/CALayer，`:66-87`；Ame248FPSMetalLayer.nextDrawable 挂后台驻车闸 + Vulkan FPS 计数，`:28-47`）。输入事件面在 touchView/手势层。
- `Natives/SurfaceViewController.m:1456-1462`：`touchView`（含 surfaceView）+ `ctrlView` 兄弟层级——这正是 SDL 补丁嵌入时寻找的几何锚（见 §1.4）。
- `:1466-1519`：touchView 上的手势组（hover/tap/doubleTap/longPress/双指 longPress/双指 pan）；tap/longpress 的 Task428 分发见 §5。
- `:189-190`：CADisplayLink tick 中保留 `[GyroInput tick]` + `[ControllerInput tick]`（每帧虚拟鼠标/陀螺仪增量出口）。
- `:4025-4144` `sendTouchPoint:withEvent:`：几何换算族（Task255/330/267/277/333）后经虚拟鼠标或直发进入 `CallbackBridge_nativeSendCursorPos`（抓取态 delta 重锚 Task230，`Natives/input_bridge_v3.m:2222-2266`）。

**桥的双路派发（Natives/input_bridge_v3.m，2964 行）**——这是「GLFW 兜底桥同构直通链路」的准确形态：

- **Path A（GLFW 回调，MC ≤26.2）**：LWJGL 的 `glfwSet*Callback`（Java 侧 `JavaApp/src/lwjgl/org/lwjgl/glfw/GLFW.java:578-588` native 声明）解析到启动器可执行文件导出的 `Java_org_lwjgl_glfw_GLFW_nglfwSet<Key>Callback`（`input_bridge_v3.m:1169-1187` ADD_CALLBACK_WWIN 宏），把 MC 的回调指针存进 `GLFW_invoke_*`（typedef `Natives/environ.h:49-58`，声明 `:86-97`）。输入就绪由 `pojavPumpEvents` 首泵置位（`input_bridge_v3.m:1195-1201`）。随后 `CallbackBridge_nativeSendKey` 走 `GLFW_invoke_Key((void*)showingWindow, ...)` 直调（`:2515-2530`）、鼠标 `:2558-2579`、光标 `:2268-2273`。
- **Path B（SDL3 事件，MC 26.3+）**：`!GLFW_invoke_Key && g_sdlWindow` 时改推 SDL3 事件（`:2532-2548`；鼠标 `:2575-2578`；光标 `:2286-2293`）。机制 = dlsym 取 `SDL_PushEvent/SDL_GetWindowID/SDL_GetKeyboardState/SDL_SetModState`（`:36-44,:198-210`，Task66 符号表实证），内联构造 SDL3 ABI 事件结构（常量 `:46-78`：0x300/0x301 键、0x400-0x403 鼠标、0x303 文本 Task82、0x207/0x206 窗口尺寸 Task83b/334）后 `SDL_PushEvent`（`pushSDLMouseMotion/MouseButton` `:319-356`，reserved=0xA1 启动器推送标记 Task325）。`g_sdlWindow` 由 `Amethyst_SetSDLWindow` 登记（`:260-279`），调用方是 SDL 补丁里的 UIKit_CreateWindow（见 §1.4）。
- **两路互斥条件**：A 链要求 `GLFW_invoke_Key && isInputReady`；B 链要求 `!GLFW_invoke_Key && g_sdlWindow`；都不满足 = 事件丢失（Task224 取证日志 `:2486-2495` 三态标注）。
- **26.3 会话 GLFW 永不加载的实证**：`input_bridge_v3.m:264-275`（Task229 注释）「MC 26.3 (LWJGL 341) never loads org.lwjgl.glfw.GLFW, whose static block does System.load(...) —— the ONLY trigger of this executable's JNI_OnLoad」。GLFW.java:526-576 static 块 + `:534` System.load 即该唯一触发器；26.3 不触发 → `JNI_OnLoad`（`:1147-1162`）不跑 → 26.3 注册缺失面靠 `Amethyst_SetSDLWindow → ame229_registerCTCOnce`（`:222-257`）曲线补齐（CTCDesktopPeer natives）。

### 1.3 SDL_InitSubSystem 在 iOS 的劫持现状（PDF 论断 2/4 的核心修正面）

`Natives/sdl3_hook.m`（2968 行）已是完整可用的 SDL3 兼容层：
- `:1-7` 头注：移植自 ZalithLauncher2 Android 端 bytehook 版 sdl_hook.c；「iOS 上没有 bytehook，等价机制是 main_hook.m 里 fishhook 住的 dlsym（hooked_dlsym）——LWJGL 通过 dlsym 取 SDL 函数指针后直接调用，不走 __la_symbol_ptr，所以必须在 dlsym 层拦」。
- **SDL_InitSubSystem 已被劫持**（两条解析路径全覆盖）：
  - LWJGL/FFM/dlsym 路径：`ame_maybeWrapWindowHook` 按名分发（`:563-567`）→ `ame_SDL_InitSubSystem`（`:2042-2071`）在调真函数前注 SDL hint（SDL_RETURN_KEY_HIDES_IME、SRGB、SDL_ENABLE_SCREEN_KEYBOARD——Task114/252）。
  - JNA 路径（controlify 的 libsdl4j）：Task132 对 libjnidispatch 的 `_dlsym` 间接符号槽做 Mach-O `__la_symbol_ptr/__got` 重绑定（`:2126-2168` 设计注释；`Natives/main_hook.m:1015` 调用点；Task134 看门狗重试），随后同样命中 `:2878-2882` 的 InitSubSystem 劫持。
- 同层还有 Task131 的 `SDL_SetEventFilter/SDL_AddEventWatch` no-op 守卫（`:2078-2124`），并在 Makefile 侧下沉为二进制机器码守卫（§1.5）。

**结论**：「SDL_InitSubSystem 直连」所需的劫持点在 iOS **已经存在且装机实证**；缺的不是 hook 技术，而是劫持体内尚未做 GCController→SDL_Gamepad 事件灌入（目前体内只有 hint 注入）。

### 1.4 patches/ 目录既有先例（逐个补丁的作用面）

**patches/sdl3-amethyst.patch（520 行，SDL3 uikit 后端源码补丁）**
| 补丁面 | 作用 |
|---|---|
| `src/video/uikit/SDL_uikitview.m`（补丁行 9-16） | `hitTest:withEvent:` 恒返回 nil——SDL 视图对命中测试隐身，触摸穿透到宿主 touchView，由 SurfaceViewController 手势系统处理后回灌 SDL（B 链） |
| `src/video/uikit/SDL_uikitviewcontroller.m`（补丁行 29-31, 42-52） | 键盘 textField 改 autoresizing 防 iOS 16+ NSISEngine 约束异常；重挂 textField 包 CATransaction + @try 防 Auto Layout 异常 |
| `src/video/uikit/SDL_uikitwindow.m`（补丁行 64-93, 96-208, 250-324, 344-365, 367-402, 405-457, 462-519） | ① 全部 UIKit 窗口操作经 CFRunLoop 派发真主线程（`Amethyst_OnMainThread`；SDL_RunOnMainThread 不可用——SDL 记录的「主线程」是 JVM 渲染线程，补丁行 66-72 注释）；② `Amethyst_EmbedSDLViewIntoHostWindow` 把 SDL 内容视图嵌进宿主 touchView（GLFW 几何位），盖住旧 GameSurfaceView，ControlLayout 控件层保持在上（补丁行 101-208）；③ 嵌入后经 `dlsym(RTLD_DEFAULT,"Amethyst_SetSDLWindow")` 回调启动器登记 SDL 窗口——补丁注释原文「register SDL window with the input bridge so SDL events can be injected directly when GLFW callbacks are unavailable (MC 26.3+)」（补丁行 303-317）④ ShowWindow 嵌入态改重钉 z 序、Hide/Destroy/Border 全部主线程化 |
| 应用方式 | **未被任何构建步骤引用**：全仓 grep 仅 README.md/README_EN.md/worklog-archive.md 提及。`Natives/resources/Frameworks/libSDL3.dylib` 以预补丁形态随仓发布（README.md:248「已打补丁」）。补丁文件承担源级溯源职责。 |
| 配套构建期二进制守卫 | `Makefile:780-794 dep_sdl3_guard` → `scripts/patch_sdl3_eventfilter_guard.py` 对 libSDL3.dylib 入口机器码打补丁（SDL_SetEventFilter/AddEventWatch 非空回调置空/拒绝，Task135，JNA 绕行链的链路无关兜底；字节不匹配响亮失败防 SDL3 版本漂移）；payload 目标挂载（`Makefile:914`）。 |

**patches/mesa-215-osmesa-virgl.patch（156 行，Mesa 25.0.7 构建期源码补丁）**
- 作用面：virgl 驱动 + vtest winsys 编入 osmesa 前端（无 libdrm 平台跳过 DRM winsys 的 meson 条件守卫，补丁行 1-34；osmesa 目标追加 driver_virgl + vl 桩 link_whole，补丁行 35-60；Task217 热修 10/11 归档注释）。
- 应用点：`Makefile:746-749`（dep_virgl_compile 链内 `patch -p1` + `.task215_patched` 幂等标记，下载重试 5 次 `:740-744`）。
- 工程范式：整链失败仅告警放行、渲染器表按 dylib 存在性自动隐藏选项（`Makefile:632-634, 620-621`）——「补丁可选、主构建不被裹挟」的先例。

**对 §6.2 的意义**：两个先例分别示范了「源码补丁（mesa：构建期应用）」与「源码补丁（sdl3：预补丁二进制 + 溯源文件 + 构建期二进制守卫）」两种工艺。SDL 直连若需动 SDL 源（如 uikit 后端 joystick/sensor 行为），工艺栈齐全。

---

## 2. Android bytehook 方案 vs iOS 两条替代路径对照表

前置事实：Android 侧 bytehook = ZL2 的 PLT hook 劫持 `SDL_InitSubSystem`（sdl3_hook.m:1-2 头注明示移植来源）；iOS 侧的本仓自研拦截栈 = fishhook（main 二进制 dlopen/dlsym 重绑定，`main_hook.m:21,:854-1015,:1978-1988`）+ Task132/134 对指定 image 的 `__la_symbol_ptr/__got` 槽位手写重绑定（sdl3_hook.m:2126-2168）+ `hooked_dlsym` 按名分发（sdl3_hook.m:487-569）。**PDF 论断「iOS 无 libhooker 级运行时 PLT hook 稳定公开方案」判定为证实，但「方案不可行」的推论不成立**——下表「自研 dlsym 栈」行即反例：劫持点已存在且已在生产使用。

| 维度 | Android bytehook（上游参照） | iOS 路径甲：LWJGL 打包源显式注册 | iOS 路径乙：dlopen 时机控制（含现状 dlsym 劫持扩展） |
|---|---|---|---|
| 技术形态 | PLT/GOT 运行时 hook，劫持 `SDL_InitSubSystem` 等符号 | 改 `JavaApp/src/lwjgl` 源覆盖层（lwjgl-341 的 lwjgl-sdl 绑定类或加载块），在 SDL 初始化路径显式调用启动器注册入口；经 `JavaApp/Makefile` 重建 lwjgl-341.jar（Makefile:960-966 双轨打包） | 扩展 `hooked_dlopen`（main_hook.m:854+，已感知 libjnidispatch/libOSMesa/libSDL3 类加载）在 libSDL3.dylib 加载后挂启动器注册；或扩展既有 `ame_SDL_InitSubSystem`（sdl3_hook.m:2042-2071，劫持点已在生产） |
| 侵入面 | 系统级，对所有经过 PLT 的调用生效 | Java 层侵入：只影响 LWJGL 341 轨；26.2（333 轨）零触碰。改动在自有打包源内 = 全量可控 | Native 层侵入：主二进制已有 hook 面，新增为劫持体内代码块；不触 jar |
| 稳定性 | 上游生产验证（ZL2） | 高——Java 层确定性调用，无符号解析竞态；风险在 LWJGL 3.4.1 上游漂移时 overlay 合并冲突（lwjgl-341/lwjgl-sdl.jar 为上游 jar，overlay 需逐版本对齐；classpath 字典序陷阱见 JavaApp/Makefile:12-16 注释） | 高——Task131/132/134/135 四轮装机实证的同一栈；B 链 `Amethyst_SetSDLWindow` 已是「SDL 侧主动登记」先例（patches/sdl3-amethyst.patch:303-317）。风险：dlopen 链新增成员（JNA tmp 解包）时序竞态（Task132 病历族已有看门狗兜底） |
| 维护成本 | 不适用（iOS 无 bytehook） | 中——每次 LWJGL 341 升级需重验 overlay；双 jar（333/341）构建产物各 +1 校验 | 低——劫持体内新增 ~几十行；SDL3 版本漂移由 dep_sdl3_guard 字节守卫 + dlsym 按名分发的双保险吸收 |
| 回滚难度 | 不适用 | 中——jar 回滚 = 重打/换回旧 lwjgl-341.jar（Makefile 产物命名链重锚） | 低——劫持体内加环境变量/偏好开关即关（sdl3_hook.m 既有范式：AMETHYST_SDL_GLES_COMPAT/AMETHYST_SDL_REUSE_WINDOW 全部可 env 关闭，sdl3_hook.m:25-28） |
| 对「26.3 不跑 JNI_OnLoad」缺口的结构性修复 | — | **根治**：GLFW.java:534 的 System.load 是 JNI_OnLoad 唯一触发器，26.3 永不触发；把注册挪进 SDL 轨加载块 = 顺带消灭 Task229 曲线注册（input_bridge_v3.m:222-257）及其前提假设 | 缓解（现状 Task229 已曲线补齐 CTC 一半缺口；直连事件泵可完全挂在 Amethyst_SetSDLWindow 之后，无需动 JNI_OnLoad） |
| 与既有 Task 链的耦合 | — | 低（Java 层独立） | 中——必须与 Task131/135 守卫、Task325 0xA1 标记、Task224/227 取证日志共存，回归面在 native |
| 结论 | 参照系 | **结构最正**，作为 P2.1 spike 先行 | **落地最快**，P2.2 主选：在 `ame_SDL_InitSubSystem` 劫持体内挂手柄事件泵，回滚面最小 |

---

## 3. iOS GameController→SDL iOS backend 灌入方案技术细节

### 3.1 SDL3 iOS 后端对 GCController 的原生支持面

- SDL3 的手柄支持在 `src/joystick/iphoneos/SDL_mfijoystick.m`（GCController→SDL_Gamepad 抽象，含热插拔观察、GUID 派生、SDL GameController DB 匹配），sensor 在 `src/sensor/coremotion/SDL_coremotionsensor.m`（CMMotionManager→SDL_SENSOR_* 事件）。**两者均不在本仓补丁作用面内**：patches/sdl3-amethyst.patch 只动 `video/uikit/*` 三文件（§1.4 表），libSDL3.dylib 的 joystick/sensor 后端保持上游原样 → SDL 侧 GCController 原生支持面理论上是完整的。
- 但**本仓构建产物未验证 joystick 后端实况**（无 Task66 式符号表/装机日志取证 joystick 子系统）。且现有嵌入架构刻意让 SDL 视图对触摸隐身（hitTest nil，补丁行 9-16）、输入全部由启动器手势层回灌（B 链）——SDL 自己的 uikit 触摸/键盘链被有意旁路；joystick 链是否也随之旁路（GCController 连接观察挂在 UIApplication 级，理论上不受视图嵌入影响）需要 P2.1 spike 首项定案。
- 已知耦合风险：controlify（26.1.2）经 libsdl4j→JNA 加载同一 libSDL3.dylib 并构造 `SDLControllerManager`；其 JNA 闭包事件过滤器被 Task131/135 拦截，热插拔事件仍经 `SDL_PollEvent` 送达（sdl3_hook.m:2098-2102 注释原文）。直连方案若在 SDL 内部注册自己的事件过滤器/EventWatch，会与该守卫冲突——**直连必须用 SDL_PushEvent 注入 SDL_GAMEPAD_BUTTON/AXIS 事件（复用 B 链工艺），不得注册事件过滤器**。

### 3.2 灌入方案（推荐形态：劫持体内事件泵，零新 hook）

1. **挂载点**：`ame_SDL_InitSubSystem`（sdl3_hook.m:2042-2071）在真初始化成功后检查 `flags & SDL_INIT_GAMEPAD`，武装 GCController 桥；对称地，`Amethyst_SetSDLWindow`（input_bridge_v3.m:260-279）继续负责窗口 ID 供给（`getSDLWindowID` `:281-286`）。
2. **事件源**：GCController 注册沿用 `ControllerInput registerControllerCallbacks`（ControllerInput.m:131-248）——但产出物从「GLFW 键码查表」改为双写：保留现链（Mapped 兜底，兼容 MC 26.2 与映射表用户），旁路新增「GCExtendedGamepad 元素 → SDL_GamepadButtonEvent/SDL_GamepadAxisEvent 结构 → `pSDL_PushEvent`」（复用 SDL3_MouseButtonEvent 同款 ABI 手写工艺，input_bridge_v3.m:98-110）。
3. **ID/映射语义**：SDL_GamepadEvent 需要 `which`（JoystickID）。上游 GCController GUID 由 SDL_mfijoystick 分配——启动器侧不经 SDL joystick 后端而直接 Push 手柄事件时，`which` 必须用 SDL 侧已存在设备的 ID（需 `SDL_GetJoysticks`/`SDL_GetJoystickID` dlsym 探测， Joystick 未被 SDL 枚举时 events 会被 MC 丢弃）→ **这是 P2.1 spike 的第二定案点：SDL_mfijoystick 是否已在 26.3 会话枚举出手柄**。若已枚举，直连零注册成本；若未枚举（嵌入式会话 GCController 被 SDL 视图旁路影响），则需回填 `SDL_VideoInit/SDL_JoystickInit` 时机或退回路径甲。
4. **陀螺仪统一**：SDL sensor 事件（SDL_EVENT_GAMEPAD_UPDATE_COMPLETE 之外的 SDL_EVENT_SENSOR_UPDATE）灌入同理挂 CMMotionManager——但 SDL3 iOS sensor 后端内部已自持一个 CMMotionManager；统一的第一步是「停掉启动器侧 GyroInput 的采样、改读 SDL sensor 状态」而非双实例并行（对照 §4 修正项 K8）。
5. **开关与回滚**：偏好键 + 环境变量双闸（依 sdl3_hook.m:25-28 范式）；回滚 = 关闸回落 Mapped 兜底，运行时零风险切换。

---

## 4. 收益逐项验证

### K6（PDF 论断 6）MC 26.3+ 兼容 —— 证实
- 双轨既成事实：`Makefile:960-966` lwjgl-333/lwjgl-341 双 jar 按版本装载（注释「26.x+ -> 341，其余 -> 333」）；README.md:142「26.2 走 LWJGL/GLFW 通路，26.3+ 走 SDL3 通路」。
- 直连的结构性收益实证于缺口本身：`input_bridge_v3.m:264-275` Task229 记录 26.3 会话 JNI_OnLoad 永不触发导致 CTCDesktopPeer natives 注册缺失（装机 e24a60a9 日志实锤），现靠 `Amethyst_SetSDLWindow` 曲线补齐（`:222-257`）。手柄事件泵若挂 SDL 轨，同类「注册时机悬空」问题被结构性消灭，后续 26.x 新 native 注册项不必再打补丁。
- **附加修正**：26.3 的键鼠输入已经走 SDL_PushEvent（B 链）——「SDL 兼容」并非未开始，未完成的只有手柄形事件与 SDL 子系统级联动。

### K7（PDF 论断 7）SDL GameController DB 即插即用 —— 修正（部分成立，收益条件化）
- 成立的部分：SDL GameController DB（SDL_gamecontroller_db.h）+ SDL_mfijoystick 的 GUID 匹配确实免除人工映射表——对「新上市手柄」比 `controls/gamepads/*.json` 两文件（gamepad_default.json 16 条 + gamepad_switch.json）覆盖面广，且任天堂布局交换（ControllerInput.m:37-46）这类位置语义修正 DB 已内置。
- 需修正的部分：「即插即用」的前提是 MC 消费 SDL 手柄事件。本仓无法验证 vanilla MC 26.3 的手柄消费面（26.3 整合包不含 controlify，worklog Task131 病历：26.1.2 才含 controlify 3.0.1；vanilla 26.3 是否轮询 SDL_GAMEPAD_* 事件未取证）。若 vanilla 不消费，直连收益退化为「为 controlify/mod 生态铺轨」——仍是收益，但「即插即用」应降格为「DB 覆盖面优势，待 spike 定消费面」。

### K8（PDF 论断 8）陀螺仪经 SDL sensor 统一 —— 修正（部分成立，语义有损面）
- 本仓陀螺仪现状（`Natives/input/GyroInput.m`，177 行）：
  - 自持 CMMotionManager（`:23,:73-75`），`deviceMotionUpdateInterval = 1/rate`（`:86`，Task428 四参之一 5-50Hz）；
  - ZL2 GyroscopeReader 对标四参：`general.gyro_invert_y`（`:80,:139-140`）、`general.gyro_sample_rate`（`:47-53,:81-86`）、`general.gyro_smoothing`（滑动均值窗口 1+smoothing/10，`:87-95,:151-167`）、微增量死域 0.02（`:11-15,:142-149`）；
  - 界面旋转轴交换/反转（`:33-40`）；抓取态门控 + 静止沿清缓冲（`:104-117`）；出口与手柄右摇杆同构：`sendTouchPoint:ACTION_MOVE_MOTION`（`:169-172`）。
- SDL sensor 统一的收益 = 消除双 CMMotionManager 并行采样（SDL 内部一个 + GyroInput 一个），事件源单一。
- 语义有损面：SDL sensor 只给原始 rotationRate，**死域/平滑/采样率/轴反转四参全部要重挂灌入侧**——即 Task428 刚落的 ZL2 对标质量层不能因统一而丢失。统一方案的工程约束由此从「接 SDL」变为「接 SDL 且保四参」，工作量按 §6 P2.3 估。
- 且统一方向建议反转：与其「启动器读 SDL sensor」（SDL sensor 在 26.3 会话是否被 MC 打开同样未取证），不如维持 GyroInput 直采 + 直连手柄轨另灌——sensor 统一降为可选收尾（P2.3），非收益主轴。

---

## 5. Task428 Mapped 模式增强与 §6.3 的差距闭环结论

### 5.1 已落（对照 PDF §6.3 要求项）

| 要求项 | 落地证据 |
|---|---|
| tap 动作三态（左/右/无） | `SurfaceViewController.m:4729-4739`（读键+越界回落）、`:4743-4745`（动作→GLFW 键）、`:4773-4784`（tap 分发：down→33ms→up 同键，退役旧 `isGrabbing?右:左` 硬编码） |
| longpress 动作三态 + 按下/抬起同键收尾 | `:4857-4869`（Began 分发）、`:4875-4879`（Ended/Cancelled 同键 UP） |
| 长按延迟可配置（含旧键回退） | `:4747-4760` `ame428_longPressDelay`（新键 `general.gesture_longpress_delay` 0.2-1.0s 优先，旧键 `control.press_duration` 毫秒回退）；创建处 `:1495-1500`；热应用 `:2647-2650`（applyInGamePreferenceChanges） |
| 陀螺仪四参（反转 Y/采样率/平滑/死域） | GyroInput.m（§4 K8 引用链）；旧签名兼容垫片 `:46-66` 零调用方改动 |
| 偏好键注册（防 Setter 静默丢弃族） | `PLPreferences.m:34-37` general 节注册 gesture_tap_action/gesture_longpress_action/gesture_longpress_delay（另 5 键同批，worklog.md:5175） |
| 设置 UI | `ZL2SettingPages.m:961-1010`（点击/长按动作行 + 延迟滑条；键名契约注释 `:43-50`） |

### 5.2 仍缺（§6.3 差距闭环清单）

1. **游戏内快捷开关**（PDF §6.3 明示项）：游戏内 ⚙ 菜单（GameMenuOverlayView）现只有 FPS/内存开关（`GameMenuOverlayView.m:694-703` toggleStatsLabel）——无陀螺仪启停/手势动作快切。玩家仍需退到设置页改 `applyInGamePreferenceChanges` 链。
2. **手势动作域收窄**：tap/longpress 动作域仅鼠标三态（0/1/2）——无键盘动作/滚轮动作槽位（对照手柄映射表的表达力）。若 §6.3 原意含「可配置动作 = 任意动作」，则尚差动作值域扩展。
3. **陀螺仪与 SDL/motion 源的会话级一致性**：四参是会话级热应用（`applyInGamePreferenceChanges` `:2622-2625`），无游戏内切换；与 5.1 项同根。
4. **TouchController（模组轨）与 Mapped 手势层的陀螺仪通道未打通**：TouchController 通道（mod_touch_mode 三态，ZL2SettingPages.m:33-42）驱动游戏内虚拟按键，其视角手势与 GyroInput 增量双轨并行（moveViewPanGesture `SurfaceViewController.m:1521-1529` vs GyroInput），无互斥/叠加策略声明。
5. **设置落地页退役**：ZL2SettingPages.m:51-52 自注「落地页退役属后续任务」。

**闭环判定**：§6.3 的「Mapped 模式增强过渡」主体已完成，缺口集中在「游戏内可达性」（快捷开关）与「动作域扩展」；两项均为小工作量（各 ≤0.5 人日），不构成直连工程的阻塞项——过渡态判定为**可接受，维持 P2 不升级**。

---

## 6. 风险与工作量评估

### 6.1 风险登记

| 风险 | 等级 | 依据/缓解 |
|---|---|---|
| vanilla MC 26.3 消费 SDL 手柄事件与否未定案 | 高（对收益定性） | P2.1 spike 首项：SDL_mfijoystick 枚举 + SDL_GetJoysticks dlsym 探测 + Push 一发 SDL_GAMEPAD_BUTTON 事件装机验证 |
| 直连事件与 Task131/135 守卫冲突（事件过滤器禁用约束） | 中 | 方案约束已内建：只走 SDL_PushEvent，不注册过滤器（§3.1） |
| JoystickID 语义（which 字段）错配 → 事件被 MC 丢弃 | 中 | §3.2 第 3 点；Task64 丢弃计数器（input_bridge_v3.m:2538-2547）可平移作取证 |
| LWJGL 341 上游漂移（overlay 合并） | 中（仅路径甲） | 双轨打包 Makefile:960-966；overlay 冲突时退路径乙 |
| SDL3 dylib 版本漂移 | 低 | dep_sdl3_guard 字节守卫响亮失败（Makefile:790-793）+ dlsym 按名分发与版本无关 |
| 回归面扩大（Mapped 兜底链与直连并存） | 中 | 双写开关化；回归矩阵见 §6.2 |
| 陀螺仪统一有损四参质量层 | 低 | P2.3 前置于直连之后，四参灌入侧重建（§4 K8） |

### 6.2 人日表

| 阶段 | 工作项 | 人日 | 前置 |
|---|---|---|---|
| P2.1 | LWJGL 改包 spike：① SDL_mfijoystick/joystick 子系统在 26.3 嵌入会话的枚举取证；② lwjgl-sdl 绑定类加载块显式注册探针（overlay + 重建 lwjgl-341.jar + 装机日志验证）；③ vanilla 26.3 SDL_Gamepad 消费面定案 | 2-3 | 无 |
| P2.2 | SDL_InitSubSystem 直连落地：GCController→SDL_Gamepad 事件泵（劫持体内挂载 + ControllerInput 双写 + JoystickID 供给 + 开关/回滚闸 + Task64 式丢弃取证） | 4-6 | P2.1 结论 |
| P2.3 | sensor 统一收尾：GyroInput 四参挂 SDL sensor 轨（或维持直采 + 停 SDL 双采样），死域/平滑语义保真 | 2-3 | P2.2 |
| 回归 | 26.2 GLFW 轨（映射表/布局交换/滚轮速度）+ 26.3 B 链（键鼠/文本/窗口尺寸对）+ controlify 守卫链（Task131/135）+ Task428 手势/陀螺仪四参 + 小窗坐标族（Task267/277/333） | 1-2 | 随各阶段 |
| **合计** | | **9-14** | |

---

## 7. 分阶段落地建议

- **P2.0（本交付）**：本评估落卷；§4 修正项回写 PDF 第六版 §6.2 候选；§5.2 缺口移交任务池（游戏内快捷开关可并入任一输入向 Task）。
- **P2.1 LWJGL 改包 spike（2-3 人日）**：三个定案点一次装机出结论——joystick 枚举实况、vanilla 消费面、注册时机根治收益实测。产物 = 判定备忘 +（可选）lwjgl-341 overlay 探针分支。**失败出口**：三定案点任一为否 → 直连收益重估，P2 降级冻结，Mapped 兜底为终态。
- **P2.2 SDL_InitSubSystem 直连（4-6 人日）**：按 §3.2 形态落地；开关默认关（shadow 模式先跑日志一版），装机对照后翻默认；双写期保留 Mapped 兜底直至回归矩阵全绿。
- **P2.3 sensor 统一（2-3 人日）**：四参语义保真前提下收编双 CMMotionManager；非收益主轴，可独立排期。
- 里程碑判据：P2.2 装机锚点 = 「直连开关 ON：SDL_GAMEPAD_* 事件消费计数 > 0 且 Mapped 链零回归；OFF：行为与现版逐字节一致」。

---

## 附：本卷引用文件清单（均在 task381 分支 HEAD 12b8e6b 验证）

Natives/input/ControllerInput.m · Natives/input/GyroInput.m · Natives/input_bridge_v3.m · Natives/sdl3_hook.m · Natives/main_hook.m · Natives/environ.h · Natives/glfw_keycodes.h · Natives/utils.h · Natives/SurfaceViewController.m · Natives/GameSurfaceView.m · Natives/main.m · Natives/GameMenuOverlayView.m · Natives/ZL2SettingPages.m · Natives/PLPreferences.m · patches/sdl3-amethyst.patch · patches/mesa-215-osmesa-virgl.patch · scripts/patch_sdl3_eventfilter_guard.py · Makefile · JavaApp/src/lwjgl/org/lwjgl/glfw/GLFW.java · JavaApp/Makefile · JavaApp/libs/lwjgl-341/ · controls/gamepads/*.json · README.md · worklog.md
