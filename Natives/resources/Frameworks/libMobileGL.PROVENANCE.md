# libMobileGL.dylib / libMoltenVK.dylib 产物出处档案（Task469）

- 升级轮：Task469 · 2026-11-23（用户钦定「继续优化和真正的升级渲染器」）
- libMobileGL.dylib
  - sha256: `fd907f655061aaa919970e372d3514924423cb8213ea6692a11749bd0db68c60`
  - size: 16447088 B（旧代 e7a8043b… = 85757760 B 未剥离构建，同轮退役）
  - 构建: GIT@8df5508 · Timestamp 2026-10-16T06:50:27 · vulkan-sdk-1.4.321.0-49-g07244428 基线
  - 来源: Ynnyny/MobileGL-fix（Witch-Launcher 的 MobileGL fork）@ 8df55081
    「fix(ios): DirectGLES MetalANGLE GLES32 shim + loader/EGL iOS fixes」
    （上游 = MobileGL-Dev/MobileGL，Desktop OpenGL 4.6 over DirectVulkan/DirectGLES，
    Magma = Vulkan 后端 / Espryt = GLES 后端）
  - 自带修复面: MC 26.3 几何/UI 间歇性损坏修复（fff9d639 resident buffer ordering）+
    VMA 块尺寸配置（a5201690）+ iOS loader/EGL 修复 + MetalANGLE GLES32 shim（8df55081）
- libMoltenVK.dylib
  - sha256: `3378bf8d6fd1e5bdc9bb4ae5b6c8157e3f0f9529c0c3719d483d610d2cdceba1`
  - size: 14769224 B（旧代 73cb7379… = 4904816 B 同轮退役）
  - 与新 dylib 同仓配套（Vulkan 1.4 SDK 配套面），@rpath/libMoltenVK.dylib 运行时解析
- 幽灵旋钮转正: MOBILEGL_MAGMA_VMA_BLOCK_SIZE_MB（默认32，钳8..256）/
  MOBILEGL_LARGE_BUFFER_ADOPT_MB（默认4，钳1..64）/ MOBILEGL_ANGLE_BACKEND（tgles|vulkan）
  —— fork 源码级实锚（MobileGL/ConfigLoader.cpp + MG_Util/BackendLoaders/OpenGL/Loader.cpp）
- 门禁: scripts/ame468_selfcheck.py S10（尺寸 + sha256 + GIT@ 标记 + 本档案互证）；
  装机日志锚 [JavaLauncher] Task469: MobileGL perf knobs applied
- 旧代出处（留档）: Amethyst-iOS-MyRemastered vendor 线，sha256 e7a8043b…（85757760 B，
  GIT@874b9e8 · 2026-09-05T02:34:22）

## C++ 运行时伴侣对（Task470 补装）

- 补装轮：Task470 · 2026-11-23（装机判例 mclo.gs/9gW8EeL——Task469 换装后首启
  「Loading library OpenGL」UnsatisfiedLinkError 定谳：dylib 升代了，运行时没跟上）
- libc++_cxx23.dylib
  - sha256: `7243bc688668be68...`（size: 1134848 B）
  - 来源: Witch-Launcher/Witch_launcher@main `Natives/resources/Frameworks/`
    （同仓同构建环境 = fork dylib 的 ABI 伴生面，原仓库按惯例随包）
  - 依赖闭包（Mach-O 手解）: @rpath/libc++abi_cxx23.dylib（伴侣对内闭环）+
    /usr/lib/libSystem.B.dylib（OS）
- libc++abi_cxx23.dylib
  - sha256: `bfb6ddabd3b7aeae...`（size: 349104 B）
  - 来源: 同上
  - 依赖闭包: /usr/lib/libSystem.B.dylib（OS）= 叶子
- 解析链: 主执行档 @executable_path/Frameworks rpath → app Frameworks 目录
  （9gW8EeL 装机日志 dyld tried 列表同族路径实证在场）；libMobileGL.dylib 的
  LC_RPATH `/Volumes/project/...`（构建机残留路径）设备上恒 miss，无害冗余，
  留档不改二进制（签名面稳定性优先）
- 全 Frameworks 目录 Mach-O 依赖闭包门: scripts/task470_runtime_verify.py
  （R3 段——全部 dylib 的 LC_LOAD_DYLIB 逐一判定 OS/bundled/rpath-bundled）
- 装机日志锚: [JavaLauncher] Task470: MobileGL C++ runtime companion pair:
  libc++_cxx23=1 libc++abi_cxx23=1（缺失时附 WARNING + UnsatisfiedLinkError 签名）
