#import "AFNetworking.h"
#import "ModpackAPI.h"
#import "utils.h"

@implementation ModpackAPI

#pragma mark Interface methods

- (instancetype)initWithURL:(NSString *)url {
    self = [super init];
    self.baseURL = url;
    return self;
}

- (void)loadDetailsOfMod:(NSMutableDictionary *)item {
    [self doesNotRecognizeSelector:_cmd];
}

- (NSMutableArray *)searchModWithFilters:(NSDictionary<NSString *, NSString *> *)searchFilters previousPageResult:(NSMutableArray *)prevResult {
    [self doesNotRecognizeSelector:_cmd];
    return nil;
}

- (id)getEndpoint:(NSString *)endpoint params:(NSDictionary *)params {
    __block id result;
    dispatch_group_t group = dispatch_group_create();
    dispatch_group_enter(group);
    NSString *url = [self.baseURL stringByAppendingPathComponent:endpoint];
    AFHTTPSessionManager *manager = [AFHTTPSessionManager manager];
    manager.requestSerializer.timeoutInterval = 15.0;
    [manager GET:url parameters:params headers:nil progress:nil
    success:^(NSURLSessionTask *task, id obj) {
        result = obj;
        dispatch_group_leave(group);
    } failure:^(NSURLSessionTask *operation, NSError *error) {
        self.lastError = error;
        dispatch_group_leave(group);
    }];
    // Task263：DISPATCH_TIME_FOREVER → 20s 限时等待。原实现永久 park：
    // AFNetworking 的 completion 默认在主队列回调，任何【主线程】调用方
    // 一旦走到这里，回调永远排在被阻塞的主线程后面 → dispatch_group_leave
    // 永不执行 → 主线程死锁 → iOS watchdog 约 20s 强杀（闪退）；镜像源
    // 慢响应/挂起时后台调用方也会无限挂起。限时超时返回 nil，调用方走
    // lastError/空态展示路径（迟到的回调仅写已无人读的 result，无害）。
    if (dispatch_group_wait(group, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(20.0 * NSEC_PER_SEC))) != 0) {
        NSLog(@"[ModpackAPI] Task263: getEndpoint timed out (%@) -- returning nil", url);
        self.lastError = [NSError errorWithDomain:@"ModpackAPIError" code:-1001
                                         userInfo:@{NSLocalizedDescriptionKey: @"request timed out"}];
        return nil;
    }
    return result;
}

- (void)installModpackFromDetail:(NSDictionary *)modDetail atIndex:(NSUInteger)selectedVersion {
    // Pass details to LauncherNavigationController
    NSDictionary* userInfo = @{
        @"detail": modDetail,
        @"index": @(selectedVersion)
    };
    [NSNotificationCenter.defaultCenter 
        postNotificationName:@"InstallModpack" 
        object:self userInfo:userInfo];
}

@end
