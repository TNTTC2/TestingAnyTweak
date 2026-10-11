#import "AppBeforeXRootListController.h"
#import <objc/runtime.h>

@implementation AppBeforeXRootListController

- (NSArray *)specifiers {
    if (!_specifiers) {
        // 用 runtime 呼叫真正的 loadSpecifiersFromPlistName:
        NSArray *specs = ((NSArray *(*)(id, SEL, NSString *, id))objc_msgSend)(self, @selector(loadSpecifiersFromPlistName:target:), @"Root", self);
        _specifiers = [specs mutableCopy];
    }
    return _specifiers;
}

- (void)setPreferenceValue:(id)value specifier:(id)specifier {
    // 呼叫 super
    struct objc_super superInfo = {
        .receiver = self,
        .super_class = [self superclass]
    };
    ((void (*)(struct objc_super *, SEL, id, id))objc_msgSendSuper)(&superInfo, @selector(setPreferenceValue:specifier:), value, specifier);

    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                         CFSTR("com.tnhdev.fun.appbeforeX/preferences.changed"),
                                         NULL, NULL, YES);
}

@end
