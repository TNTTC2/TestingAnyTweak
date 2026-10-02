#import <UIKit/UIKit.h>
#import <CoreFoundation/CoreFoundation.h>
#import <dlfcn.h>

#define kPreferenceDomain CFSTR("com.tnhdev.fun.screenmysaver")

// Private Interfaces
@interface LSApplicationWorkspace : NSObject
+ (id)defaultWorkspace;
- (BOOL)openApplicationWithBundleID:(NSString *)bundleID;
@end

@interface SBLockScreenManager : NSObject
+ (id)sharedInstance;
- (BOOL)isUILocked;
@end

@interface SpringBoard : UIApplication
- (NSString *)_accessibilityFrontMostApplicationDisplayIdentifier;
@end

// State Variables
static dispatch_source_t stage1Timer = nil;
static dispatch_source_t stage2Timer = nil;
static BOOL isInStage2 = NO;

// 安全讀取 Preference 數值（自動將 NSString 轉換為整數，並進行 >= 30 限制）
static void loadPrefs(BOOL *enabled, BOOL *allowLowPower, NSInteger *cooldown, NSInteger *wait, NSString **targetBundleID) {
    CFPreferencesAppSynchronize(kPreferenceDomain);

    Boolean keyExists = false;
    if (enabled) {
        *enabled = CFPreferencesGetAppBooleanValue(CFSTR("enabled"), kPreferenceDomain, &keyExists);
    }
    if (allowLowPower) {
        *allowLowPower = CFPreferencesGetAppBooleanValue(CFSTR("allowLowPowerMode"), kPreferenceDomain, &keyExists);
    }
    if (cooldown) {
        CFStringRef val = (CFStringRef)CFPreferencesCopyAppValue(CFSTR("cooldownTime"), kPreferenceDomain);
        if (val) {
            NSInteger c = [(__bridge_transfer NSString *)val integerValue];
            *cooldown = c >= 30 ? c : 30;
        } else {
            *cooldown = 300;
        }
    }
    if (wait) {
        CFStringRef val = (CFStringRef)CFPreferencesCopyAppValue(CFSTR("waitTime"), kPreferenceDomain);
        if (val) {
            NSInteger w = [(__bridge_transfer NSString *)val integerValue];
            *wait = w >= 30 ? w : 30;
        } else {
            *wait = 30;
        }
    }
    if (targetBundleID) {
        CFStringRef val = (CFStringRef)CFPreferencesCopyAppValue(CFSTR("targetBundleID"), kPreferenceDomain);
        *targetBundleID = (__bridge_transfer NSString *)val ?: @"";
    }
}

// 動態檢測 MediaRemote 是否有媒體正在播放
static BOOL isMediaPlaying() {
    BOOL (*MRMediaRemoteGetNowPlayingApplicationIsPlaying)(dispatch_queue_t queue, void (^completion)(BOOL isPlaying)) = NULL;
    void *handle = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_LAZY);
    if (handle) {
        MRMediaRemoteGetNowPlayingApplicationIsPlaying = dlsym(handle, "MRMediaRemoteGetNowPlayingApplicationIsPlaying");
    }

    __block BOOL playing = NO;
    if (MRMediaRemoteGetNowPlayingApplicationIsPlaying) {
        dispatch_semaphore_t sema = dispatch_semaphore_create(0);
        MRMediaRemoteGetNowPlayingApplicationIsPlaying(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^(BOOL isPlaying) {
            playing = isPlaying;
            dispatch_semaphore_signal(sema);
        });
        dispatch_semaphore_wait(sema, dispatch_time(DISPATCH_TIME_NOW, 100 * NSEC_PER_MSEC));
    }
    return playing;
}

static void cancelStage2AndReset() {
    if (stage2Timer) {
        dispatch_source_cancel(stage2Timer);
        stage2Timer = nil;
    }
    isInStage2 = NO;
}

// 開啟目標 App
static void launchTargetApp(NSString *bundleID) {
    if (!bundleID || [bundleID length] == 0) return;
    LSApplicationWorkspace *workspace = [NSClassFromString(@"LSApplicationWorkspace") defaultWorkspace];
    if ([workspace respondsToSelector:@selector(openApplicationWithBundleID:)]) {
        [workspace openApplicationWithBundleID:bundleID];
    }
}

// 檢查系統當前是否處於可觸發屏保的閒置狀態
static BOOL isSystemIdle(NSString *targetBundleID, BOOL allowLowPower) {
    // 1. 低電量模式檢查
    if (!allowLowPower && [[NSProcessInfo processInfo] isLowPowerModeEnabled]) {
        return NO;
    }

    // 2. 鎖定畫面檢查
    SBLockScreenManager *lockManager = [NSClassFromString(@"SBLockScreenManager") sharedInstance];
    if ([lockManager isUILocked]) {
        return NO;
    }

    // 3. 影音播放檢查
    if (isMediaPlaying()) {
        return NO;
    }

    // 4. 前台 App 檢查（若當前前台已經是目標 App 則跳過）
    SpringBoard *sb = (SpringBoard *)[UIApplication sharedApplication];
    if ([sb respondsToSelector:@selector(_accessibilityFrontMostApplicationDisplayIdentifier)]) {
        NSString *currentApp = [sb _accessibilityFrontMostApplicationDisplayIdentifier];
        if ([currentApp isEqualToString:targetBundleID]) {
            return NO;
        }
    }

    return YES;
}

// 第二階段：等待倒數計時
static void startStage2Countdown(NSInteger waitTimeSeconds, NSString *targetBundleID) {
    cancelStage2AndReset();
    isInStage2 = YES;

    dispatch_queue_t queue = dispatch_get_main_queue();
    stage2Timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, queue);

    dispatch_source_set_timer(stage2Timer, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(waitTimeSeconds * NSEC_PER_SEC)), DISPATCH_TIME_FOREVER, 1 * NSEC_PER_SEC);
    dispatch_source_set_event_handler(stage2Timer, ^{
        isInStage2 = NO;
        stage2Timer = nil;

        BOOL enabled = NO;
        BOOL allowLowPower = NO;
        NSString *bundleID = @"";
        loadPrefs(&enabled, &allowLowPower, NULL, NULL, &bundleID);

        // 倒數結束，二次確認無誤後直接拉起 App
        if (enabled && isSystemIdle(bundleID, allowLowPower)) {
            launchTargetApp(bundleID);
        }
    });
    dispatch_resume(stage2Timer);
}

// 第一階段：冷卻檢查週期
static void startStage1Timer() {
    if (stage1Timer) {
        dispatch_source_cancel(stage1Timer);
        stage1Timer = nil;
    }
    cancelStage2AndReset();

    BOOL enabled = NO;
    BOOL allowLowPower = NO;
    NSInteger cooldown = 300;
    NSInteger wait = 30;
    NSString *bundleID = @"";
    loadPrefs(&enabled, &allowLowPower, &cooldown, &wait, &bundleID);

    if (!enabled || [bundleID length] == 0) return;

    dispatch_queue_t queue = dispatch_get_main_queue();
    stage1Timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, queue);

    dispatch_source_set_timer(stage1Timer, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(cooldown * NSEC_PER_SEC)), (uint64_t)cooldown * NSEC_PER_SEC, 1 * NSEC_PER_SEC);
    dispatch_source_set_event_handler(stage1Timer, ^{
        if (isInStage2) return;

        if (isSystemIdle(bundleID, allowLowPower)) {
            startStage2Countdown(wait, bundleID);
        }
    });
    dispatch_resume(stage1Timer);
}

// Hook SpringBoard 全域觸控事件：若在第二階段收到任何觸控，立即中斷倒數
%hook SpringBoard

- (void)sendEvent:(UIEvent *)event {
    %orig;
    if (event.type == UIEventTypeTouches) {
        NSSet *touches = [event allTouches];
        for (UITouch *touch in touches) {
            if (touch.phase == UITouchPhaseBegan || touch.phase == UITouchPhaseMoved) {
                if (isInStage2) {
                    cancelStage2AndReset();
                }
                break;
            }
        }
    }
}

%end

// 插件載入與 Preference 變更動態刷新
%ctor {
    @autoreleasepool {
        startStage1Timer();

        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            NULL,
            (CFNotificationCallback)startStage1Timer,
            CFSTR("com.tnhdev.fun.screenmysaver/ReloadPrefs"),
            NULL,
            CFNotificationSuspensionBehaviorDeliverImmediately
        );
    }
}
