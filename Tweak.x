#import <UIKit/UIKit.h>

static NSString *const kPrefPath = @"/var/mobile/Library/Preferences/com.tnhdev.fun.redstar.plist";
static NSString *const kLogDir = @"/var/jb/RedStar";
static dispatch_source_t timerSource = nil;

// 寫入背景日誌
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

static void captureAndSaveScreenshot() {
    @try {
        NSDictionary *prefs = [NSDictionary dictionaryWithContentsOfFile:kPrefPath];
        BOOL enabled = [prefs[@"enabled"] boolValue];
        if (!enabled) {
            appendTweakLog(@"Tweak disabled in settings.");
            return;
        }

        NSString *uuid = prefs[@"appUUID"];
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

// 重新設定定時器
static void setupTimer() {
    if (timerSource) {
        dispatch_source_cancel(timerSource);
        timerSource = nil;
    }

    NSDictionary *prefs = [NSDictionary dictionaryWithContentsOfFile:kPrefPath];
    BOOL enabled = [prefs[@"enabled"] boolValue];
    if (!enabled) return;

    NSInteger intervalMins = [prefs[@"intervalMinutes"] integerValue];
    if (intervalMins <= 0) intervalMins = 5; // 預設 5 分鐘

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

%ctor {
    @autoreleasepool {
        appendTweakLog(@"RedStar Tweak Loaded into SpringBoard.");
        setupTimer();

        // 監聽 Preference 變更通知
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
