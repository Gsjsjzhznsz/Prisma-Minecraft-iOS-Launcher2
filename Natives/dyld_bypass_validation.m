// Based on: https://blog.xpnsec.com/restoring-dyld-memory-loading
// https://github.com/xpn/DyldDeNeuralyzer/blob/main/DyldDeNeuralyzer/DyldPatch/dyldpatch.m

#import <Foundation/Foundation.h>

#include <dlfcn.h>
#include <fcntl.h>
#include <sys/stat.h>
#include <sys/mman.h>
#include <unistd.h>
#include <errno.h>
#include <mach-o/loader.h>
#include <mach-o/nlist.h>
#include <mach-o/dyld.h>
#include <mach-o/dyld_images.h>
#include <sys/syscall.h>
#include <libkern/OSCacheControl.h>

#include "utils.h"

#define ASM(...) __asm__(#__VA_ARGS__)
// ldr x8, value; br x8; value: .ascii "\x41\x42\x43\x44\x45\x46\x47\x48"
char patch[] = {0x88,0x00,0x00,0x58,0x00,0x01,0x1f,0xd6,0x1f,0x20,0x03,0xd5,0x1f,0x20,0x03,0xd5,0x41,0x41,0x41,0x41,0x41,0x41,0x41,0x41};

// Signatures to search for
char mmapSig[] = {0xB0, 0x18, 0x80, 0xD2, 0x01, 0x10, 0x00, 0xD4};
char fcntlSig[] = {0x90, 0x0B, 0x80, 0xD2, 0x01, 0x10, 0x00, 0xD4};
char syscallSig[] = {0x01, 0x10, 0x00, 0xD4};
int (*orig_fcntl)(int fildes, int cmd, void *param) = 0;
bool (*redirectFunction)(char *name, void *patchAddr, void *target) = NULL;

extern void* __mmap(void *addr, size_t len, int prot, int flags, int fd, off_t offset);
extern int __fcntl(int fildes, int cmd, void* param);

// Since we're patching libsystem_kernel, we must avoid calling to its functions
static void builtin_memcpy(char *target, char *source, size_t size) {
    for (int i = 0; i < size; i++) {
        target[i] = source[i];
    }
}

kern_return_t builtin_vm_protect(mach_port_name_t task, mach_vm_address_t address, mach_vm_size_t size, boolean_t set_max, vm_prot_t new_prot);
// Originated from _kernelrpc_mach_vm_protect_trap
ASM(_builtin_vm_protect: \n
    mov x16, #-0xe       \n
    svc #0x80            \n
    ret
);

// redirectFunction for iOS 18 and below
bool redirectFunctionDirect(char *name, void *patchAddr, void *target) {
    kern_return_t kret = builtin_vm_protect(mach_task_self(), (vm_address_t)patchAddr, sizeof(patch), false, PROT_READ | PROT_WRITE | VM_PROT_COPY);
    if (kret != KERN_SUCCESS) {
        NSDebugLog(@"[DyldLVBypass] vm_protect(RW) fails at line %d", __LINE__);
        return FALSE;
    }
    
    builtin_memcpy((char *)patchAddr, patch, sizeof(patch));
    *(void **)((char*)patchAddr + 16) = target;
    sys_icache_invalidate((void*)patchAddr, sizeof(patch));
    
    kret = builtin_vm_protect(mach_task_self(), (vm_address_t)patchAddr, sizeof(patch), false, PROT_READ | PROT_EXEC);
    if (kret != KERN_SUCCESS) {
        NSDebugLog(@"[DyldLVBypass] vm_protect(RX) fails at line %d", __LINE__);
        return FALSE;
    }
    
    NSDebugLog(@"[DyldLVBypass] hook %s succeed!", name);
    return TRUE;
}
// redirectFunction for iOS 26+ (TXM)
// ★ Task457 三重防线：①op4 超调用改走 Safe 护栏（装机 .ips 实锤：无应答
//   brk 61453 SIGTRAP 致死；无调试器/死端口 → 返回 NO 弃钩，不闪退）；
//   ②vm_protect(mirror RW) 返回值检查（旧代码吞返回值：TXM 拒改保护时
//   memcpy 经只读别名写 → SIGBUS 黑屏族）；③写回校验（镜像与目标页共享
//   物理页，补丁未穿透时目标页保持原字节 —— SIGBUS 被 init 阶段 SIG_IGN
//   吞掉的静默半写形态由此检出），任一失败均弃钩，不带残缺钩子发射 JVM。
bool redirectFunctionMirrored(char *name, void *patchAddr, void *target) {
    if (DeviceHasJITFlags(JIT_FLAG_FORCE_MIRRORED | JIT_FLAG_HAS_TXM)) {
        if (!JIT26PrepareRegionForPatchingSafe(patchAddr, sizeof(patch))) {
            NSDebugLog(@"[DyldLVBypass] ame457: JIT26PrepareRegionForPatching unserved (no debugger answer for brk op4) -- hook %s aborted before vm_remap", name);
            return FALSE;
        }
    }
    // mirror `addr` (rx, JIT applied) to `mirrored` (rw)
    vm_address_t mirrored = 0;
    vm_prot_t cur_prot, max_prot;
    kern_return_t ret = vm_remap(mach_task_self(), &mirrored, sizeof(patch), 0, VM_FLAGS_ANYWHERE, mach_task_self(), (vm_address_t)patchAddr, false, &cur_prot, &max_prot, VM_INHERIT_SHARE);
    if (ret != KERN_SUCCESS) {
        NSDebugLog(@"[DyldLVBypass] vm_remap() fails at line %d", __LINE__);
        return FALSE;
    }
    
    mirrored += (vm_address_t)patchAddr & PAGE_MASK;
    kern_return_t ame457_prot = vm_protect(mach_task_self(), mirrored, sizeof(patch), NO,
               VM_PROT_READ | VM_PROT_WRITE);
    if (ame457_prot != KERN_SUCCESS) {
        NSDebugLog(@"[DyldLVBypass] ame457: vm_protect(mirror RW) fails (%d) at line %d -- TXM refused; hook %s aborted without writing", ame457_prot, __LINE__, name);
        vm_deallocate(mach_task_self(), mirrored, sizeof(patch));
        return FALSE;
    }
    builtin_memcpy((char *)mirrored, patch, sizeof(patch));
    *(void **)((char*)mirrored + 16) = target;
    if (memcmp((const void *)patchAddr, patch, 16) != 0 ||
        *(void **)((char *)patchAddr + 16) != target) {
        NSDebugLog(@"[DyldLVBypass] ame457: patch write-back verify fails for hook %s -- mirrored write did not land; aborting hook", name);
        vm_deallocate(mach_task_self(), mirrored, sizeof(patch));
        return FALSE;
    }
    sys_icache_invalidate((void*)patchAddr, sizeof(patch));
    
    NSDebugLog(@"[DyldLVBypass] hook %s succeed!", name);
    
    vm_deallocate(mach_task_self(), mirrored, sizeof(patch));
    return TRUE;
}
// redirectFunction for iOS 26+ (non-TXM)
bool redirectFunctionHWBreakpoint(char *name, void *patchAddr, void *target) {
    for(int i = 0; i < 6; i++) {
        if(hwRedirectOrig[i] == (uint64_t)patchAddr) {
            NSDebugLog(@"[DyldLVBypass] hook %s already exists!", name);
            return TRUE;
        } else if(!hwRedirectOrig[i]) {
            hwRedirectOrig[i] = (uint64_t)patchAddr;
            hwRedirectTarget[i] = (uint64_t)target;
            NSDebugLog(@"[DyldLVBypass] hook %s succeed!", name);
            return TRUE;
        }
    }
    NSDebugLog(@"[DyldLVBypass] no slot for hook %s", name);
    NSDebugLog(@"[DyldLVBypass] hook %s fails line %d", name, __LINE__);
    return FALSE;
}

bool searchAndPatch(char *name, char *base, char *signature, int length, void *target) {
    char *patchAddr = NULL;
    for(int i=0; i < 0x80000; i+=4) {
        if (base[i] == signature[0] && memcmp(base+i, signature, length) == 0) {
            patchAddr = base + i;
            break;
        }
    }
    
    if (patchAddr == NULL) {
        NSDebugLog(@"[DyldLVBypass] hook %s fails line %d", name, __LINE__);
        return FALSE;
    }
    
    NSDebugLog(@"[DyldLVBypass] found %s at %p", name, patchAddr);
    return redirectFunction(name, patchAddr, target);
}

void *getDyldBase(void) {
    struct task_dyld_info dyld_info;
    mach_vm_address_t image_infos;
    struct dyld_all_image_infos *infos;
    
    mach_msg_type_number_t count = TASK_DYLD_INFO_COUNT;
    kern_return_t ret;
    
    ret = task_info(mach_task_self_,
                    TASK_DYLD_INFO,
                    (task_info_t)&dyld_info,
                    &count);
    
    if (ret != KERN_SUCCESS) {
        return NULL;
    }
    
    image_infos = dyld_info.all_image_info_addr;
    
    infos = (struct dyld_all_image_infos *)image_infos;
    return (void *)infos->dyldImageLoadAddress;
}

void* hooked_mmap(void *addr, size_t len, int prot, int flags, int fd, off_t offset) {
    // this is to avoid a legacy codepath checking if process is allowed to map RWX which never worked properly
    if (flags & MAP_JIT) {
        errno = EINVAL;
        return MAP_FAILED;
    }
    
    void *map = __mmap(addr, len, prot, flags, fd, offset);
    if (fd == -1 || (prot & PROT_EXEC) == 0) {
        return map;
    }
    
    // Handle some cases where it will still map but without executable permission
    if (mprotect(map, len, prot) == -1) {
        munmap(map, len);
        map = MAP_FAILED;
    }
    if (map == MAP_FAILED) {
        //printf("[DyldLVBypass] mmap(prot=%d, flags=%d, fd=%d)\n", prot, flags, fd);
        map = __mmap(addr, len, prot, flags | MAP_PRIVATE | MAP_ANON, 0, 0);
        if (DeviceHasJITFlags(JIT_FLAG_FORCE_MIRRORED | JIT_FLAG_HAS_TXM)) {
            // ★ Task457：op1 超调用同族 Safe 化（无应答 → 干净 MAP_FAILED，
            //   dlopen 报错收敛到 JVM 既有失败路径，不再裸 SIGTRAP 致死）
            if (!JIT26PrepareRegionSafe(map, len)) {
                NSDebugLog(@"[DyldLVBypass] ame457: JIT26PrepareRegion unserved (no debugger answer for brk op1) -- returning MAP_FAILED instead of hollow region");
                munmap(map, len);
                errno = EINVAL;
                return MAP_FAILED;
            }
        }
        
        void *memoryLoadedFile = __mmap(NULL, len, PROT_READ, MAP_PRIVATE, fd, offset);
        if (redirectFunction == redirectFunctionDirect) {
            mprotect(map, len, PROT_READ | PROT_WRITE);
            memcpy(map, memoryLoadedFile, len);
            mprotect(map, len, prot);
        } else {
            // mirror `addr` (rx, JIT applied) to `mirrored` (rw)
            vm_address_t mirrored = 0;
            vm_prot_t cur_prot, max_prot;
            kern_return_t ret = vm_remap(mach_task_self(), &mirrored, len, 0, VM_FLAGS_ANYWHERE, mach_task_self(), (vm_address_t)map, false, &cur_prot, &max_prot, VM_INHERIT_SHARE);
            if(ret == KERN_SUCCESS) {
                vm_protect(mach_task_self(), mirrored, len, NO,
                           VM_PROT_READ | VM_PROT_WRITE);
                memcpy((void*)mirrored, memoryLoadedFile, len);
                vm_deallocate(mach_task_self(), mirrored, len);
            }
        }
        munmap(memoryLoadedFile, len);
    }
    return map;
}

int hooked___fcntl(int fildes, int cmd, void *param) {
    if (cmd == F_ADDFILESIGS_RETURN) {
#if !(TARGET_OS_MACCATALYST || TARGET_OS_SIMULATOR)
        // attempt to attach code signature on iOS only as the binaries may have been signed
        // on macOS, attaching on unsigned binaries without CS_DEBUGGED will crash
        // ignoreFcntl is a special case for vphone or dev unit with TXM JIT enforcement disabled
        BOOL ignoreFcntl = DeviceHasJITFlags(JIT_FLAG_IS_IOS_26 | JIT_FLAG_HAS_TXM) && !DeviceHasJITFlags(JIT_FLAG_FORCE_MIRRORED);
        if (!ignoreFcntl) {
            orig_fcntl(fildes, cmd, param);
        }
#endif
        fsignatures_t *fsig = (fsignatures_t*)param;
        // called to check that cert covers file.. so we'll make it cover everything ;)
        fsig->fs_file_start = 0xFFFFFFFF;
        return 0;
    }

    // Signature sanity check by dyld
    else if (cmd == F_CHECK_LV) {
        //orig_fcntl(fildes, cmd, param);
        // Just say everything is fine
        return 0;
    }
    
    // If for another command or file, we pass through
    return orig_fcntl(fildes, cmd, param);
}

BOOL init_bypassDyldLibValidation(void) {
    static BOOL bypassed;
    if (bypassed) return TRUE;
    bypassed = YES;

    NSDebugLog(@"[DyldLVBypass] init");
    
    // The original switch used exact bitmask matching, so a device with
    // IS_IOS_26 + HAS_TXM (no FORCE_MIRRORED) — i.e. a normal iPhone 17 on
    // iOS 26 with StikDebug-provided JIT — fell through to redirectFunction
    // Direct, whose vm_protect(RX) call iOS 26 blocks. The half-applied
    // patch left dyld code pages RW with modified bytes, then dyld faulted
    // executing non-X memory on the next mmap call → SIGBUS ignored → hang
    // at dlopen(libjli). Use bitmask checks so iOS 26 + TXM correctly picks
    // the mirrored variant.
    if (DeviceHasJITFlags(JIT_FLAG_HAS_TXM) &&
        (DeviceHasJITFlags(JIT_FLAG_IS_IOS_26) || DeviceHasJITFlags(JIT_FLAG_FORCE_MIRRORED))) {
        NSDebugLog(@"[DyldLVBypass] Using redirectFunctionMirrored");
        redirectFunction = redirectFunctionMirrored;
    } else if (DeviceHasJITFlags(JIT_FLAG_FORCE_MIRRORED)) {
        // Special special case for non-TXM iOS 26+. We can JIT without
        // script, but we cannot modify existing code in dsc without it.
        // Use hardware breakpoint to avoid patching dsc code at all.
        NSDebugLog(@"[DyldLVBypass] Using redirectFunctionHWBreakpoint");
        redirectFunction = redirectFunctionHWBreakpoint;
    } else {
        NSDebugLog(@"[DyldLVBypass] Using redirectFunctionDirect");
        redirectFunction = redirectFunctionDirect;
    }
    
    // Modifying exec page during execution may cause SIGBUS, so ignore it now
    // Before calling JLI_Launch, this will be set back to SIG_DFL
    signal(SIGBUS, SIG_IGN);
    
    orig_fcntl = __fcntl;
    char *dyldBase = getDyldBase();
    // ★ Task457 op4 通道金丝雀：Mirrored 路径下 op4 是 dyld 钩子的前置超调用，
    //   无应答即闪退（装机 .ips 实锤：launchMinecraft block 内
    //   JIT26PrepareRegionForPatching+4 brk 61453）。先对匿名 RW 探针页做一次
    //   Safe op4：NO = 通道死（无调试器/死端口）→ 弃钩优雅返回 FALSE（调用方
    //   弹 ame457 诊断窗），不再带裸 brk 冲向 dyld 文本页。
    if (redirectFunction == redirectFunctionMirrored) {
        BOOL ame457_op4Alive = FALSE;
        void *ame457_scratch = mmap(NULL, getpagesize(), PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANON, -1, 0);
        if (ame457_scratch == MAP_FAILED) {
            NSDebugLog(@"[DyldLVBypass] ame457: op4 canary scratch mmap failed (errno=%d) -- assuming channel dead", errno);
        } else {
            ame457_op4Alive = JIT26PrepareRegionForPatchingSafe(ame457_scratch, 16);
            munmap(ame457_scratch, getpagesize());
            NSDebugLog(@"[DyldLVBypass] Task457: op4 canary verdict=%d (scratch-page round-trip)", ame457_op4Alive);
        }
        if (!ame457_op4Alive) {
            NSDebugLog(@"[DyldLVBypass] ame457: JIT26 op4 channel dead -- dyld hooks would crash; aborting bypass gracefully");
            return FALSE;
        }
    }
    //redirectFunction("mmap", mmap, hooked_mmap);
    //redirectFunction("fcntl", fcntl, hooked_fcntl);
    bool ame457_mmapHookOK = searchAndPatch("dyld_mmap", dyldBase, mmapSig, sizeof(mmapSig), hooked_mmap);
    bool fcntlPatchSuccess = searchAndPatch("dyld_fcntl", dyldBase, fcntlSig, sizeof(fcntlSig), hooked___fcntl);
    
    // https://github.com/LiveContainer/LiveContainer/commit/c978e62
    // dopamine already hooked it, try to find its hook instead
    if(!fcntlPatchSuccess) {
        char* fcntlAddr = 0;
        // search all syscalls and see if the the instruction before it is a branch instruction
        for(int i=0; i < 0x80000; i+=4) {
            if (dyldBase[i] == syscallSig[0] && memcmp(dyldBase+i, syscallSig, 4) == 0) {
                char* syscallAddr = dyldBase + i;
                uint32_t* prev = (uint32_t*)(syscallAddr - 4);
                if(*prev >> 26 == 0x5) {
                    fcntlAddr = (char*)prev;
                    break;
                }
            }
        }
        
        if(fcntlAddr) {
            uint32_t* inst = (uint32_t*)fcntlAddr;
            int32_t offset = ((int32_t)((*inst)<<6))>>4;
            NSLog(@"[DyldLVBypass] Dopamine hook offset = %x", offset);
            orig_fcntl = (void*)((char*)fcntlAddr + offset);
            fcntlPatchSuccess = redirectFunction("dyld_fcntl (Dopamine)", fcntlAddr, hooked___fcntl);
        } else {
            NSLog(@"[DyldLVBypass] Dopamine hook not found");
        }
    }
    
    // ★ Task457：两钩落位判定（mmap 钩管可执行映射，fcntl 钩管签名旁路，
    //   任一残缺 = JVM 发射必炸）→ 调用方弹 ame457 诊断窗优雅退出
    NSDebugLog(@"[DyldLVBypass] Task457: bypass complete mmapHook=%d fcntlHook=%d", ame457_mmapHookOK, fcntlPatchSuccess);
    return ame457_mmapHookOK && fcntlPatchSuccess;
}
