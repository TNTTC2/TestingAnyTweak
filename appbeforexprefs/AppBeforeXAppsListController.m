#import "AppBeforeXAppsListController.h"

@interface LSApplicationProxy : NSObject
@property (nonatomic, readonly) NSString *applicationIdentifier;
@property (nonatomic, readonly) NSString *localizedName;
+ (instancetype)applicationProxyForIdentifier:(NSString *)identifier;
@end

@interface LSApplicationWorkspace : NSObject
+ (instancetype)defaultWorkspace;
- (NSArray *)allApplications;
@end

@implementation AppBeforeXAppsListController

- (NSArray *)specifiers {
    if (!_specifiers) {
        NSMutableArray *specs = [NSMutableArray array];

        PSSpecifier *header = [PSSpecifier preferenceSpecifierNamed:@"Select Apps"
                                                              target:nil
                                                                 set:NULL
                                                                 get:NULL
                                                              detail:nil
                                                                cell:PSGroupCell
                                                                edit:nil];
        [header setProperty:@"Apps that have the switch ON will use the pre-iPhone X letterboxed look." forKey:@"footerText"];
        [specs addObject:header];

        LSApplicationWorkspace *workspace = [LSApplicationWorkspace defaultWorkspace];
        NSArray *apps = [workspace allApplications];

        NSMutableArray *userApps = [NSMutableArray array];
        for (LSApplicationProxy *app in apps) {
            NSString *bid = app.applicationIdentifier;
            if (!bid || [bid hasPrefix:@"com.apple."]) continue;
            if (!app.localizedName) continue;
            [userApps addObject:app];
        }

        [userApps sortUsingComparator:^NSComparisonResult(LSApplicationProxy *a, LSApplicationProxy *b) {
            return [a.localizedName localizedCaseInsensitiveCompare:b.localizedName];
        }];

        for (LSApplicationProxy *app in userApps) {
            PSSpecifier *spec = [PSSpecifier preferenceSpecifierNamed:app.localizedName
                                                               target:self
                                                                  set:@selector(setAppEnabled:specifier:)
                                                                  get:@selector(isAppEnabled:)
                                                               detail:nil
                                                                 cell:PSSwitchCell
                                                                 edit:nil];
            [spec setProperty:app.applicationIdentifier forKey:@"bundleID"];
            [spec setProperty:app.applicationIdentifier forKey:@"key"];
            [spec setProperty:@"com.tnhdev.fun.appbeforeX" forKey:@"defaults"];
            [spec setProperty:@"com.tnhdev.fun.appbeforeX/preferences.changed" forKey:@"PostNotification"];
            [spec setProperty:@YES forKey:@"default"];
            [specs addObject:spec];
        }

        _specifiers = [specs copy];
    }
    return _specifiers;
}

- (id)isAppEnabled:(PSSpecifier *)specifier {
    NSString *bundleID = [specifier propertyForKey:@"bundleID"];
    NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:@"com.tnhdev.fun.appbeforeX"];
    NSDictionary *apps = [defaults dictionaryForKey:@"EnabledApps"] ?: @{};
    id value = apps[bundleID];
    if (value == nil) return @YES;
    return value;
}

- (void)setAppEnabled:(id)value specifier:(PSSpecifier *)specifier {
    NSString *bundleID = [specifier propertyForKey:@"bundleID"];
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
