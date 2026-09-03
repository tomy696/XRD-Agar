#import <Foundation/Foundation.h>

__attribute__((constructor))
static void xrd_init(void) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        Class cls = NSClassFromString(@"XRDMod.XRDLoader");
        if (cls) {
            SEL sel = NSSelectorFromString(@"activate");
            if ([cls respondsToSelector:sel]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
                [cls performSelector:sel];
#pragma clang diagnostic pop
            }
        }
    });
}
