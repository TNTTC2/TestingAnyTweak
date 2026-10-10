#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>

static NSString * const kPrefsID = @"com.tnhdev.fun.appbeforeX";
static NSString * const kEnabledKey = @"Enabled";
static NSString * const kAppsKey = @"EnabledApps";   // Dictionary: BundleID -> BOOL

static BOOL tweakEnabled = YES;
static NSDictionary *enabledApps = nil;

static void loadPreferences() {
    NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:kPrefsID];
    [defaults registerDefaults:@{
        kEnabledKey: @YES,
        kAppsKey: @{}
    }];

    tweakEnabled = [defaults boolForKey:kEnabledKey];
    enabledApps = [defaults dictionaryForKey:kAppsKey] ?: @{};
}

static BOOL isAppEnabled(NSString *bundleID) {
    if (!tweakEnabled) return NO;
    if (!bundleID || [bundleID hasPrefix:@"com.apple."]) return NO;

    // 如果使用者從未設定過這個 App，預設啟用
    id value = enabledApps[bundleID];
    if (value == nil) return YES;
    return [value boolValue];
}

static BOOL shouldApply() {
    NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
    return isAppEnabled(bundleID);
}

static CGRect letterboxedBounds(CGRect original) {
    CGFloat targetAspect = 16.0 / 9.0;
    CGFloat currentAspect = original.size.width / original.size.height;

    if (currentAspect > targetAspect) {
        CGFloat newWidth = original.size.height * targetAspect;
        CGFloat x = (original.size.width - newWidth) / 2.0;
        return CGRectMake(x, 0, newWidth, original.size.height);
    } else {
        CGFloat newHeight = original.size.width / targetAspect;
        CGFloat y = (original.size.height - newHeight) / 2.0;
        return CGRectMake(0, y, original.size.width, newHeight);
    }
}

%hook UIScreen

- (CGRect)bounds {
    CGRect original = %orig;
    if (!shouldApply()) return original;
    return letterboxedBounds(original);
}

- (CGRect)nativeBounds {
    CGRect original = %orig;
    if (!shouldApply()) return original;

    CGFloat scale = self.scale;
    CGRect logical = letterboxedBounds(CGRectMake(0, 0, original.size.width / scale, original.size.height / scale));
    return CGRectMake(0, 0, logical.size.width * scale, logical.size.height * scale);
}

- (CGRect)applicationFrame {
    if (!shouldApply()) return %orig;
    return [self bounds];
}

%end

%hook UIWindow

- (void)setFrame:(CGRect)frame {
    if (shouldApply() && self == [UIApplication sharedApplication].keyWindow) {
        frame = [UIScreen mainScreen].bounds;
    }
    %orig(frame);
}

%end

static void preferencesChanged(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    loadPreferences();
}

%ctor {
    loadPreferences();

    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),
                                    NULL,
                                    preferencesChanged,
                                    CFSTR("com.tnhdev.fun.appbeforeX/preferences.changed"),
                                    NULL,
                                    CFNotificationSuspensionBehaviorDeliverImmediately);

    %init;
}
