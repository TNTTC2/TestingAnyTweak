#import <UIKit/UIKit.h>
#import <CoreFoundation/CoreFoundation.h>
#import <AudioToolbox/AudioToolbox.h>

#define kPreferenceDomain CFSTR("com.tnhdev.fun.presshb")

// 私有宣告 (SpringBoard 系統介面)
@interface SpringBoard : UIApplication
- (void)_accessibilityHomeButtonClicked;
- (void)_accessibilitySiriRequested;
@end

@interface SBMainWorkspace : NSObject
+ (id)sharedInstance;
- (BOOL)isSwitcherWindowVisible;
@end

@interface SBLockScreenManager : NSObject
+ (id)sharedInstance;
- (BOOL)isUILocked;
@end

// 定義設定參數結構
typedef struct {
    BOOL enabled;
    NSInteger touchMode; // 0 = 3D Touch, 1 = Haptic Touch
    CGFloat idleOpacity; // 0.4 ~ 0.8
    NSInteger position;  // 0 = Bottom, 1 = Bottom Left, 2 = Bottom Right, 3 = Top, 4 = Top Left, 5 = Top Right
    BOOL allowSiri;
    BOOL allowLandscape;
    BOOL allowKeyboard;
    BOOL allowLockScreen;
} PressHBSettings;

static PressHBSettings gSettings;

static void loadPreferences() {
    CFPreferencesAppSynchronize(kPreferenceDomain);

    Boolean keyExists = false;
    gSettings.enabled = CFPreferencesGetAppBooleanValue(CFSTR("enabled"), kPreferenceDomain, &keyExists);

    CFNumberRef modeVal = (CFNumberRef)CFPreferencesCopyAppValue(CFSTR("touchMode"), kPreferenceDomain);
    if (modeVal) {
        NSInteger m = 1;
        CFNumberGetValue(modeVal, kCFNumberNSIntegerType, &m);
        gSettings.touchMode = m;
        CFRelease(modeVal);
    } else {
        gSettings.touchMode = 1;
    }

    CFNumberRef opacityVal = (CFNumberRef)CFPreferencesCopyAppValue(CFSTR("idleOpacity"), kPreferenceDomain);
    if (opacityVal) {
        float o = 0.4f;
        CFNumberGetValue(opacityVal, kCFNumberFloatType, &o);
        gSettings.idleOpacity = o;
        CFRelease(opacityVal);
    } else {
        gSettings.idleOpacity = 0.4f;
    }

    CFNumberRef posVal = (CFNumberRef)CFPreferencesCopyAppValue(CFSTR("position"), kPreferenceDomain);
    if (posVal) {
        NSInteger p = 0;
        CFNumberGetValue(posVal, kCFNumberNSIntegerType, &p);
        gSettings.position = p;
        CFRelease(posVal);
    } else {
        gSettings.position = 0;
    }

    gSettings.allowSiri = keyExists ? CFPreferencesGetAppBooleanValue(CFSTR("allowSiri"), kPreferenceDomain, NULL) : YES;
    gSettings.allowLandscape = keyExists ? CFPreferencesGetAppBooleanValue(CFSTR("allowLandscape"), kPreferenceDomain, NULL) : YES;
    gSettings.allowKeyboard = CFPreferencesGetAppBooleanValue(CFSTR("allowKeyboard"), kPreferenceDomain, NULL);
    gSettings.allowLockScreen = CFPreferencesGetAppBooleanValue(CFSTR("allowLockScreen"), kPreferenceDomain, NULL);
}

// 觸控按鈕自訂類別
@interface PressHBButton : UIView
@property (nonatomic, assign) BOOL isHiddenTemporarily;
@property (nonatomic, strong) NSTimer *hideTimer;

// 3D Touch 狀態
@property (nonatomic, assign) BOOL is3DDeepPressed;
@property (nonatomic, assign) NSInteger deepPressCount;
@property (nonatomic, strong) NSTimer *deepPressTimer;
@property (nonatomic, strong) NSTimer *resetDeepPressTimer;

// Haptic Touch 狀態
@property (nonatomic, assign) BOOL isHapticEngaged;
@property (nonatomic, assign) BOOL hasTriggeredVoice;
@property (nonatomic, assign) BOOL waitingForSecondTap;
@property (nonatomic, strong) NSTimer *hapticPressTimer;
@property (nonatomic, strong) NSTimer *hapticVoiceTimer;
@property (nonatomic, strong) NSTimer *hapticSwitchTimer;
@property (nonatomic, assign) NSTimeInterval touchBeganTime;
@end

@implementation PressHBButton

- (instancetype)initWithFrame:(CGRect)frame {
    if (self = [super initWithFrame:frame]) {
        self.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.15];
        self.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.8].CGColor;
        self.layer.borderWidth = 2.5;
        self.layer.cornerRadius = frame.size.width / 2.0;
        self.clipsToBounds = YES;
        self.alpha = gSettings.idleOpacity;
    }
    return self;
}

- (void)triggerFeedback {
    UIImpactFeedbackGenerator *generator = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium];
    [generator prepare];
    [generator impactOccurred];
}

- (void)triggerHome {
    SpringBoard *sb = (SpringBoard *)[UIApplication sharedApplication];
    if ([sb respondsToSelector:@selector(_accessibilityHomeButtonClicked)]) {
        [sb _accessibilityHomeButtonClicked];
    }
}

- (void)triggerSwitcher {
    SpringBoard *sb = (SpringBoard *)[UIApplication sharedApplication];
    if ([sb respondsToSelector:@selector(_accessibilityHomeButtonClicked)]) {
        [sb _accessibilityHomeButtonClicked];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.05 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [sb _accessibilityHomeButtonClicked];
        });
    }
}

- (void)triggerSiri {
    if (!gSettings.allowSiri) return;
    SpringBoard *sb = (SpringBoard *)[UIApplication sharedApplication];
    if ([sb respondsToSelector:@selector(_accessibilitySiriRequested)]) {
        [sb _accessibilitySiriRequested];
    }
}

- (void)fadeAndHideFor5Seconds {
    self.isHiddenTemporarily = YES;
    [UIView animateWithDuration:0.1 animations:^{
        self.alpha = 0.0;
    } completion:^(BOOL finished) {
        [self.hideTimer invalidate];
        self.hideTimer = [NSTimer scheduledTimerWithTimeInterval:5.0 repeats:NO block:^(NSTimer * _Nonnull timer) {
            [UIView animateWithDuration:0.2 animations:^{
                self.alpha = gSettings.idleOpacity;
            } completion:^(BOOL finished) {
                self.isHiddenTemporarily = NO;
            }];
        }];
    }];
}

// 觸控開始
- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    [super touchesBegan:touches withEvent:event];
    if (self.isHiddenTemporarily) return;

    UITouch *touch = [touches anyObject];
    self.touchBeganTime = [NSDate timeIntervalSinceReferenceDate];

    if (gSettings.touchMode == 0) { // 3D Touch 模式
        [self handle3DTouch:touch];
    } else { // Haptic Touch 模式
        [self handleHapticBegan];
    }
}

- (void)touchesMoved:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    [super touchesMoved:touches withEvent:event];
    if (gSettings.touchMode == 0 && !self.isHiddenTemporarily) {
        UITouch *touch = [touches anyObject];
        [self handle3DTouch:touch];
    }
}

- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    [super touchesEnded:touches withEvent:event];
    if (self.isHiddenTemporarily) return;

    NSTimeInterval duration = [NSDate timeIntervalSinceReferenceDate] - self.touchBeganTime;

    if (gSettings.touchMode == 0) { // 3D Touch
        if (self.is3DDeepPressed) {
            [self handle3DTouchLifted];
        } else if (duration < 0.3) {
            // 純輕碰 -> 0.1秒淡出隱藏 5 秒
            [self fadeAndHideFor5Seconds];
        }
    } else { // Haptic Touch
        [self handleHapticEndedWithDuration:duration];
    }
}

- (void)touchesCancelled:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    [super touchesCancelled:touches withEvent:event];
    self.alpha = gSettings.idleOpacity;
    self.is3DDeepPressed = NO;
    self.isHapticEngaged = NO;
}

// 3D Touch 處理邏輯
- (void)handle3DTouch:(UITouch *)touch {
    CGFloat force = touch.force;
    CGFloat threshold = 1.5;

    if (force >= threshold && !self.is3DDeepPressed) {
        self.is3DDeepPressed = YES;
        self.alpha = 0.8;
        [self triggerFeedback];
        self.deepPressCount++;

        [self.deepPressTimer invalidate];
        self.deepPressTimer = [NSTimer scheduledTimerWithTimeInterval:1.0 repeats:NO block:^(NSTimer * _Nonnull timer) {
            [self triggerFeedback];
            [self triggerSiri];
            self.deepPressCount = 0;
        }];

    } else if (force < threshold - 0.3 && self.is3DDeepPressed) {
        [self handle3DTouchLifted];
    }
}

- (void)handle3DTouchLifted {
    self.is3DDeepPressed = NO;
    self.alpha = gSettings.idleOpacity;
    [self triggerFeedback];
    [self.deepPressTimer invalidate];

    if (self.deepPressCount == 1) {
        [self triggerHome];
        [self.resetDeepPressTimer invalidate];
        self.resetDeepPressTimer = [NSTimer scheduledTimerWithTimeInterval:0.5 repeats:NO block:^(NSTimer * _Nonnull timer) {
            self.deepPressCount = 0;
        }];
    } else if (self.deepPressCount >= 2) {
        [self triggerSwitcher];
        self.deepPressCount = 0;
        [self.resetDeepPressTimer invalidate];
    }
}

// Haptic Touch 處理邏輯
- (void)handleHapticBegan {
    if (self.waitingForSecondTap) {
        self.alpha = 0.8;
        [self triggerFeedback];
    } else {
        self.isHapticEngaged = NO;
        self.hasTriggeredVoice = NO;

        [self.hapticPressTimer invalidate];
        self.hapticPressTimer = [NSTimer scheduledTimerWithTimeInterval:0.5 repeats:NO block:^(NSTimer * _Nonnull timer) {
            self.isHapticEngaged = YES;
            self.alpha = 0.8;
            [self triggerFeedback];
        }];

        [self.hapticVoiceTimer invalidate];
        self.hapticVoiceTimer = [NSTimer scheduledTimerWithTimeInterval:2.0 repeats:NO block:^(NSTimer * _Nonnull timer) {
            if (self.isHapticEngaged) {
                self.hasTriggeredVoice = YES;
                [self triggerFeedback];
                [self triggerSiri];
            }
        }];
    }
}

- (void)handleHapticEndedWithDuration:(NSTimeInterval)duration {
    [self.hapticPressTimer invalidate];
    [self.hapticVoiceTimer invalidate];

    if (self.waitingForSecondTap) {
        [self triggerFeedback];
        [self triggerSwitcher];
        self.waitingForSecondTap = NO;
        [self.hapticSwitchTimer invalidate];
        self.alpha = gSettings.idleOpacity;
    } else {
        if (self.hasTriggeredVoice) {
            self.hasTriggeredVoice = NO;
            self.alpha = gSettings.idleOpacity;
        } else if (self.isHapticEngaged) {
            [self triggerFeedback];
            [self triggerHome];
            self.alpha = 0.8;

            self.waitingForSecondTap = YES;
            [self.hapticSwitchTimer invalidate];
            self.hapticSwitchTimer = [NSTimer scheduledTimerWithTimeInterval:0.5 repeats:NO block:^(NSTimer * _Nonnull timer) {
                self.waitingForSecondTap = NO;
                self.alpha = gSettings.idleOpacity;
            }];
        } else if (duration < 0.5) {
            // 少於 0.5 秒純輕碰 -> 淡出隱藏 5 秒
            [self fadeAndHideFor5Seconds];
        }
    }
    self.isHapticEngaged = NO;
}

@end

// 頂層懸浮 Window 管理
static UIWindow *gHBWindow = nil;
static PressHBButton *gHBButton = nil;

static void updateWindowPosition() {
    if (!gHBWindow || !gHBButton) return;

    // 取得 Portrait 基準解析度（以電源接口方向為 Bottom，不受橫向影響）
    CGRect screenBounds = [UIScreen mainScreen].bounds;
    CGFloat width = MIN(screenBounds.size.width, screenBounds.size.height);
    CGFloat height = MAX(screenBounds.size.width, screenBounds.size.height);

    CGFloat btnSize = 64.0; // 經典蘋果 Home 鍵比例尺寸
    CGFloat marginX = 25.0;
    CGFloat marginY = 40.0;

    CGFloat x = (width - btnSize) / 2.0;
    CGFloat y = height - btnSize - marginY;

    switch (gSettings.position) {
        case 0: // Bottom
            x = (width - btnSize) / 2.0;
            y = height - btnSize - marginY;
            break;
        case 1: // Bottom Left
            x = marginX;
            y = height - btnSize - marginY;
            break;
        case 2: // Bottom Right
            x = width - btnSize - marginX;
            y = height - btnSize - marginY;
            break;
        case 3: // Top
            x = (width - btnSize) / 2.0;
            y = marginY + 20.0;
            break;
        case 4: // Top Left
            x = marginX;
            y = marginY + 20.0;
            break;
        case 5: // Top Right
            x = width - btnSize - marginX;
            y = marginY + 20.0;
            break;
    }

    gHBWindow.frame = CGRectMake(x, y, btnSize, btnSize);
    gHBButton.frame = CGRectMake(0, 0, btnSize, btnSize);
    gHBButton.layer.cornerRadius = btnSize / 2.0;
}

static void reloadTweakState() {
    loadPreferences();

    if (!gSettings.enabled) {
        if (gHBWindow) {
            gHBWindow.hidden = YES;
        }
        return;
    }

    if (!gHBWindow) {
        gHBWindow = [[UIWindow alloc] initWithFrame:CGRectZero];
        gHBWindow.windowLevel = UIWindowLevelStatusBar + 100;
        gHBWindow.backgroundColor = [UIColor clearColor];

        UIViewController *vc = [[UIViewController alloc] init];
        vc.view.backgroundColor = [UIColor clearColor];
        gHBWindow.rootViewController = vc;

        gHBButton = [[PressHBButton alloc] initWithFrame:CGRectZero];
        [vc.view addSubview:gHBButton];
    }

    updateWindowPosition();
    gHBButton.alpha = gSettings.idleOpacity;
    gHBWindow.hidden = NO;
}

// Hook SpringBoard 以監聽鍵盤、鎖定畫面與橫向狀態過濾
%hook SpringBoard

- (void)applicationDidFinishLaunching:(id)application {
    %orig;
    reloadTweakState();

    // 監聽鍵盤彈出
    [[NSNotificationCenter defaultCenter] addObserverForName:UIKeyboardWillShowNotification object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification * _Nonnull note) {
        if (!gSettings.allowKeyboard && gHBWindow) {
            gHBWindow.hidden = YES;
        }
    }];

    [[NSNotificationCenter defaultCenter] addObserverForName:UIKeyboardWillHideNotification object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification * _Nonnull note) {
        if (gSettings.enabled && gHBWindow) {
            gHBWindow.hidden = NO;
        }
    }];
}

%end

// 監聽轉向與鎖定畫面狀態
%hook SBLockScreenManager

- (void)lockUIFromSource:(int)arg1 withOptions:(id)arg2 {
    %orig;
    if (!gSettings.allowLockScreen && gHBWindow) {
        gHBWindow.hidden = YES;
    }
}

- (void)unlockUIFromSource:(int)arg1 {
    %orig;
    if (gSettings.enabled && gHBWindow) {
        gHBWindow.hidden = NO;
    }
}

%end

%ctor {
    @autoreleasepool {
        reloadTweakState();

        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            NULL,
            (CFNotificationCallback)reloadTweakState,
            CFSTR("com.tnhdev.fun.presshb/ReloadPrefs"),
            NULL,
            CFNotificationSuspensionBehaviorDeliverImmediately
        );
    }
}
