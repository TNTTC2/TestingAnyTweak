#import "AppBeforeXAppsListController.h"
#import <objc/runtime.h>

@implementation AppBeforeXAppsListController

- (NSArray *)specifiers {
    if (!_specifiers) {
        NSMutableArray *specs = [NSMutableArray array];

        // 取得 PSSpecifier class
        Class PSSpecifierClass = objc_getClass("PSSpecifier");

        id header = ((id (*)(Class, SEL, NSString *, id, SEL, SEL, Class, NSInteger, Class))objc_msgSend)(
            PSSpecifierClass,
            @selector(preferenceSpecifierNamed:target:set:get:detail:cell:edit:),
            @"Select Apps",
            nil, NULL, NULL, nil, 0, nil
        );
        ((void (*)(id, SEL, id, NSString *))objc_msgSend)(header, @selector(setProperty:forKey:), @"Apps that have the switch ON will use the pre-iPhone X letterboxed look.", @"footerText");
        [specs addObject:header];

        // 取得 LSApplicationWorkspace
        Class LSApplicationWorkspaceClass = objc_getClass("LSApplicationWorkspace");
        id workspace = ((id (*)(Class, SEL))objc_msgSend)(LSApplicationWorkspaceClass, @selector(defaultWorkspace));
        NSArray *apps = ((NSArray *(*)(id, SEL))objc_msgSend)(workspace, @selector(allApplications));

        NSMutableArray *userApps = [NSMutableArray array];
        for (id app in apps) {
            NSString *bid = ((NSString *(*)(id, SEL))objc_msgSend)(app, @selector(applicationIdentifier));
            if (!bid || [bid hasPrefix:@"com.apple."]) continue;

            NSString *name = ((NSString *(*)(id, SEL))objc_msgSend)(app, @selector(localizedName));
            if (!name) continue;

            [userApps addObject:app];
        }

        [userApps sortUsingComparator:^NSComparisonResult(id a, id b) {
            NSString *nameA = ((NSString *(*)(id, SEL))objc_msgSend)(a, @selector(localizedName));
            NSString *nameB = ((NSString *(*)(id, SEL))objc_msgSend)(b, @selector(localizedName));
            return [nameA localizedCaseInsensitiveCompare:nameB];
        }];

        for (id app in userApps) {
            NSString *name = ((NSString *(*)(id, SEL))objc_msgSend)(app, @selector(localizedName));
            NSString *bid = ((NSString *(*)(id, SEL))objc_msgSend)(app, @selector(applicationIdentifier));

            id spec = ((id (*)(Class, SEL, NSString *, id, SEL, SEL, Class, NSInteger, Class))objc_msgSend)(
                PSSpecifierClass,
                @selector(preferenceSpecifierNamed:target:set:get:detail:cell:edit:),
                name,
                self,
                @selector(setAppEnabled:specifier:),
                @selector(isAppEnabled:),
                nil,
                5, // PSSwitchCell
                nil
            );

            ((void (*)(id, SEL, id, NSString *))objc_msgSend)(spec, @selector(setProperty:forKey:), bid, @"bundleID");
            ((void (*)(id, SEL, id, NSString *))objc_msgSend)(spec, @selector(setProperty:forKey:), bid, @"key");
            ((void (*)(id, SEL, id, NSString *))objc_msgSend)(spec, @selector(setProperty:forKey:), @"com.tnhdev.fun.appbeforeX", @"defaults");
            ((void (*)(id, SEL, id, NSString *))objc_msgSend)(spec, @selector(setProperty:forKey:), @"com.tnhdev.fun.appbeforeX/preferences.changed", @"PostNotification");
            ((void (*)(id, SEL, id, NSString *))objc_msgSend)(spec, @selector(setProperty:forKey:), @YES, @"default");

            [specs addObject:spec];
        }

        _specifiers = [specs copy];
    }
    return _specifiers;
}

- (id)isAppEnabled:(id)specifier {
    NSString *bundleID = ((id (*)(id, SEL, NSString *))objc_msgSend)(specifier, @selector(propertyForKey:), @"bundleID");
    NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:@"com.tnhdev.fun.appbeforeX"];
    NSDictionary *apps = [defaults dictionaryForKey:@"EnabledApps"] ?: @{};
    id value = apps[bundleID];
    if (value == nil) return @YES;
    return value;
}

- (void)setAppEnabled:(id)value specifier:(id)specifier {
    NSString *bundleID = ((id (*)(id, SEL, NSString *))objc_msgSend)(specifier, @selector(propertyForKey:), @"bundleID");
    NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:@"com.tnhdev.fun.appbeforeX"];
    NSMutableDictionary *apps = [[defaults dictionaryForKey:@"EnabledApps"] mutableCopy] ?: [NSMutableDictionary dictionary];
    apps[bundleID] = value;
    [defaults setObject:apps forKey:@"EnabledApps"];
    [defaults synchronize];

    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                         CFSTR("com.tnhdev.fun.appbeforeX/preferences.changed"),
                                         NULL, NULL, YES);
}

@end
