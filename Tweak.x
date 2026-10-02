#import <UIKit/UIKit.h>
#import <CoreFoundation/CoreFoundation.h>

#define kPreferenceDomain CFSTR("com.tnhdev.fun.redstar")
static NSString *const kLogDir = @"/var/mobile/Library/Logs/RedStar";
static dispatch_source_t timerSource = nil;

// ====================================================
// 1. 日誌寫入 Helper
// ====================================================
static void appendTweakLog(NSString *text) {
    NSFileManager *fm = [NSFileManager defaultManager];
    if (![fm fileExistsAtPath:kLogDir]) {
        [fm createDirectoryAtPath:kLogDir withIntermediateDirectories:YES attributes:nil error:nil];
    }
    NSString *logPath = [kLogDir stringByAppendingPathComponent:@"tweak_log.txt"];
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    [formatter setDateFormat:@"yyyy-MM-dd HH:mm:ss"];
    NSString *logEntry = [NSString stringWithFormat:@"[%@] %@\n", [formatter stringFromDate:[NSDate date]], text];
    
    NSFileHandle *handle = [NSFileHandle fileHandleForWritingAtPath:logPath];
    if (!handle) {
        [logEntry writeToFile:logPath atomically:YES encoding:NSUTF8StringEncoding error:nil];
    } else {
        [handle seekToEndOfFile];
        [handle writeData:[logEntry dataUsingEncoding:NSUTF8StringEncoding]];
        [handle closeFile];
    }
}

// ====================================================
// 2. 設定讀取 Helper（安全轉換版）
// ====================================================
static void loadPreferences(BOOL *enabled, NSInteger *intervalMins, NSString **uuid) {
    CFPreferencesAppSynchronize(kPreferenceDomain);

    Boolean keyExists = false;
    if (enabled) {
        *enabled = CFPreferencesGetAppBooleanValue(CFSTR("enabled"), kPreferenceDomain, &keyExists);
    }
    if (intervalMins) {
        // PSEditTextCell 儲存的是文字 (例如 @"5")，需當作 String 讀取後轉為整數
        CFStringRef val = (CFStringRef)CFPreferencesCopyAppValue(CFSTR("intervalMinutes"), kPreferenceDomain);
        if (val) {
            NSString *strVal = (__bridge_transfer NSString *)val;
            NSInteger mins = [strVal integerValue];
            *intervalMins = mins > 0 ? mins : 5;
        } else {
            *intervalMins = 5;
        }
    }
    if (uuid) {
        CFStringRef val = (CFStringRef)CFPreferencesCopyAppValue(CFSTR("appUUID"), kPreferenceDomain);
        *uuid = (__bridge_transfer NSString *)val ?: @"";
    }
}


// ====================================================
// 3. 截圖與儲存邏輯
// ====================================================
static void captureAndSaveScreenshot() {
    @try {
        BOOL enabled = NO;
        NSString *uuid = @"";
        loadPreferences(&enabled, NULL, &uuid);

        if (!enabled) {
            appendTweakLog(@"Tweak disabled in settings.");
            return;
        }

        if (!uuid || [uuid length] == 0) {
            appendTweakLog(@"Execution skipped: appUUID is empty.");
            return;
        }

        NSString *targetDir = [NSString stringWithFormat:@"/var/mobile/Containers/Data/Application/%@/Library", uuid];
        NSFileManager *fileManager = [NSFileManager defaultManager];

        BOOL isDir = NO;
        if (![fileManager fileExistsAtPath:targetDir isDirectory:&isDir] || !isDir) {
            appendTweakLog([NSString stringWithFormat:@"Target directory not found: %@", targetDir]);
            return;
        }

        UIWindow *keyWindow = nil;
        for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
            if (scene.activationState == UISceneActivationStateForegroundActive && [scene isKindOfClass:[UIWindowScene class]]) {
                UIWindowScene *windowScene = (UIWindowScene *)scene;
                for (UIWindow *window in windowScene.windows) {
                    if (window.isKeyWindow) {
                        keyWindow = window;
                        break;
                    }
                }
            }
            if (keyWindow) break;
        }

        if (!keyWindow) {
            appendTweakLog(@"No active keyWindow found.");
            return;
        }

        UIGraphicsBeginImageContextWithOptions(keyWindow.bounds.size, YES, 0.0);
        [keyWindow drawViewHierarchyInRect:keyWindow.bounds afterScreenUpdates:NO];
        UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
        UIGraphicsEndImageContext();

        if (!image) {
            appendTweakLog(@"Image context rendering failed.");
            return;
        }

        NSData *imageData = UIImagePNGRepresentation(image);
        if (!imageData) {
            appendTweakLog(@"PNG representation failed.");
            return;
        }

        NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
        [formatter setDateFormat:@"yyyyMMdd_HHmmss"];
        NSString *timestamp = [formatter stringFromDate:[NSDate date]];
        NSString *fileName = [NSString stringWithFormat:@"IMG_%@.png", timestamp];
        NSString *filePath = [targetDir stringByAppendingPathComponent:fileName];

        NSError *error = nil;
        BOOL success = [imageData writeToFile:filePath options:NSDataWritingAtomic error:&error];
        if (success) {
            appendTweakLog([NSString stringWithFormat:@"Screenshot saved successfully to: %@", filePath]);
        } else {
            appendTweakLog([NSString stringWithFormat:@"Failed to write file: %@", error.localizedDescription]);
        }
    } @catch (NSException *exception) {
        appendTweakLog([NSString stringWithFormat:@"Exception: %@", exception.reason]);
    }
}

// ====================================================
// 4. 定時器設定
// ====================================================
static void setupTimer() {
    if (timerSource) {
        dispatch_source_cancel(timerSource);
        timerSource = nil;
    }

    BOOL enabled = NO;
    NSInteger intervalMins = 5;
    loadPreferences(&enabled, &intervalMins, NULL);

    if (!enabled) {
        appendTweakLog(@"Timer stopped (tweak disabled).");
        return;
    }

    uint64_t intervalSecs = (uint64_t)intervalMins * 60;

    dispatch_queue_t queue = dispatch_get_main_queue();
    timerSource = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, queue);
    
    dispatch_source_set_timer(timerSource, dispatch_time(DISPATCH_TIME_NOW, intervalSecs * NSEC_PER_SEC), intervalSecs * NSEC_PER_SEC, 1 * NSEC_PER_SEC);
    dispatch_source_set_event_handler(timerSource, ^{
        captureAndSaveScreenshot();
    });
    dispatch_resume(timerSource);

    appendTweakLog([NSString stringWithFormat:@"Timer initialized with interval: %ld minutes", (long)intervalMins]);
}

// ====================================================
// 5. 插件載入與監聽
// ====================================================
%ctor {
    @autoreleasepool {
        appendTweakLog(@"RedStar Tweak Loaded into SpringBoard.");
        setupTimer();

        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            NULL,
            (CFNotificationCallback)setupTimer,
            CFSTR("com.tnhdev.fun.redstar/ReloadPrefs"),
            NULL,
            CFNotificationSuspensionBehaviorDeliverImmediately
        );
    }
}
