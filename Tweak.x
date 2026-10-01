#import <UIKit/UIKit.h>

@interface SBLockScreenManager : NSObject
+ (id)sharedInstance;
- (BOOL)isUILocked;
@end

static NSTimer *traceTimer = nil;

// 讀取設定檔 (Preferences)
static NSDictionary *loadPreferences() {
    NSString *prefPath = @"/var/mobile/Library/Preferences/com.tnhdev.redstar.plist";
    return [NSDictionary dictionaryWithContentsOfFile:prefPath];
}

// 執行無聲隱藏截圖
static void captureAndSaveScreenshot() {
    @try {
        NSDictionary *prefs = loadPreferences();
        BOOL enabled = [prefs[@"enabled"] boolValue];
        if (!enabled) return;

        NSString *uuid = prefs[@"appUUID"];
        if (!uuid || [uuid length] == 0) return;

        // 拼接目標 App Library 資料夾路徑
        NSString *targetDir = [NSString stringWithFormat:@"/var/mobile/Containers/Data/Application/%@/Library", uuid];
        NSFileManager *fileManager = [NSFileManager defaultManager];

        BOOL isDir = NO;
        if (![fileManager fileExistsAtPath:targetDir isDirectory:&isDir] || !isDir) {
            return; // 目錄不存在直接安全跳過
        }

        // 取得主螢幕 Window 並渲染為圖片
        UIWindow *keyWindow = nil;
        for (UIWindow *window in [UIApplication sharedApplication].windows) {
            if (window.isKeyWindow) {
                keyWindow = window;
                break;
            }
        }
        if (!keyWindow) keyWindow = [[UIApplication sharedApplication].windows firstObject];
        if (!keyWindow) return;

        UIGraphicsBeginImageContextWithOptions(keyWindow.bounds.size, YES, 0.0);
        [keyWindow drawViewHierarchyInRect:keyWindow.bounds afterScreenUpdates:NO];
        UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
        UIGraphicsEndImageContext();

        if (!image) return;

        NSData *imageData = UIImagePNGRepresentation(image);
        if (!imageData) return;

        // 產生時間戳檔名：IMG_yyyyMMdd_HHmmss.png
        NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
        [formatter setDateFormat:@"yyyyMMdd_HHmmss"];
        NSString *timestamp = [formatter stringFromDate:[NSDate date]];
        NSString *fileName = [NSString stringWithFormat:@"IMG_%@.png", timestamp];
        NSString *filePath = [targetDir stringByAppendingPathComponent:fileName];

        // 寫入檔案
        [imageData writeToFile:filePath atomically:YES];
    } @catch (NSException *exception) {
        // 遇到任何錯誤靜默忽略，保證不進入 Safe Mode
    }
}

// 定時器管理
static void updateTimer() {
    @try {
        if (traceTimer) {
            [traceTimer invalidate];
            traceTimer = nil;
        }

        NSDictionary *prefs = loadPreferences();
        BOOL enabled = [prefs[@"enabled"] boolValue];
        NSInteger minutes = [prefs[@"intervalMinutes"] integerValue];

        if (minutes <= 0) minutes = 5; // 預設 5 分鐘

        if (enabled) {
            NSTimeInterval interval = minutes * 60.0;
            traceTimer = [NSTimer scheduledTimerWithTimeInterval:interval
                                                          repeats:YES
                                                            block:^(NSTimer * _Nonnull timer) {
                // 解鎖狀態下才截圖
                SBLockScreenManager *lockManager = (SBLockScreenManager *)[%c(SBLockScreenManager) sharedInstance];
                if (lockManager && ![lockManager isUILocked]) {
                    captureAndSaveScreenshot();
                }
            }];
        }
    } @catch (NSException *e) {}
}

%hook SpringBoard

- (void)applicationDidFinishLaunching:(id)application {
    %orig;
    updateTimer();
}

%end

// 監聽設定頁面變更
%ctor {
    CFNotificationCenterAddObserver(
        CFNotificationCenterGetDarwinNotifyCenter(),
        NULL,
        (CFNotificationCallback)updateTimer,
        CFSTR("com.tnhdev.redstar/ReloadPrefs"),
        NULL,
        CFNotificationSuspensionBehaviorDeliverImmediately
    );
}
