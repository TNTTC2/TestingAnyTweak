#import <UIKit/UIKit.h>
#import <CoreFoundation/CoreFoundation.h>
#import <AudioToolbox/AudioToolbox.h>
#import <mach/mach_time.h>
#import <dlfcn.h>

#define kPreferenceDomain CFSTR("com.tnhdev.fun.presshb")

// IOHIDEvent 底層宣告
typedef struct __IOHIDEvent *IOHIDEventRef;
typedef IOHIDEventRef (*IOHIDEventCreateKeyboardEventFunc)(CFAllocatorRef allocator, uint64_t timeStamp, uint16_t usagePage, uint16_t usage, Boolean down, uint32_t flags);

// 私有宣告 (SpringBoard 系統介面)
@interface SpringBoard : UIApplication
- (void)_accessibilitySiriRequested;
- (void)_handleHIDEvent:(IOHIDEventRef)event;
@end

typedef struct {
    BOOL enabled;
    NSInteger touchMode; // 0 = 3D Touch, 1 = Haptic Touch
    CGFloat idleOpacity; // 0.4 ~ 0.8
    NSInteger position;  // 0=Bottom, 1=Bottom Left, 2=Bottom Right, 3=Top, 4=Top Left, 5=Top Right
    BOOL allowSiri;
    BOOL allowLandscape;
    BOOL allowKeyboard;
    BOOL allowLockScreen;
} PressHBSettings;

static PressHBSettings gSettings;
static BOOL gIsAppLaunched = NO;

// 向系統發送實時的 Home 鍵 Down/Up HID 訊號
static void sendHomeButtonHIDEvent(BOOL isDown) {
    dispatch_async(dispatch_get_main_queue(), ^{
        uint64_t time = mach_absolute_time();
        static IOHIDEventCreateKeyboardEventFunc createKeyboardEvent = NULL;
        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{
            createKeyboardEvent = (IOHIDEventCreateKeyboardEventFunc)dlsym(RTLD_DEFAULT, "IOHIDEventCreateKeyboardEvent");
        });

        if (createKeyboardEvent) {
            // Consumer Page = 0x0C, Menu / Home Button = 0x40
            IOHIDEventRef event = createKeyboardEvent(kCFAllocatorDefault, time, 0x0C, 0x40, isDown, 0);
            if (event) {
                SpringBoard *sb = (SpringBoard *)[UIApplication sharedApplication];
                if ([sb respondsToSelector:@selector(_handleHIDEvent:)]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
                    [sb performSelector:@selector(_handleHIDEvent:) withObject:(__bridge id)event];
#pragma clang diagnostic pop
                }
                CFRelease(event);
            }
        }
    });
}

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

// 自訂 Window，避開焦點搶奪
@interface PressHBWindow : UIWindow
@end

@implementation PressHBWindow
- (BOOL)_canBecomeKeyWindow {
    return NO;
}
@end

// 自訂 RootViewController，鎖定直立旋轉（以充電孔為底部）
@interface PressHBRootViewController : UIViewController
@end

@implementation PressHBRootViewController
- (BOOL)shouldAutorotate {
    return NO;
}
- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
    return UIInterfaceOrientationMaskPortrait;
}
@end

// 懸浮 Home 按鈕類別
@interface PressHBButton : UIView
@property (nonatomic, assign) BOOL isHiddenTemporarily;
@property (nonatomic, strong) NSTimer *hideTimer;

// 3D Touch 狀態
@property (nonatomic, assign) BOOL is3DDeepPressed;
@property (nonatomic, strong) NSTimer *deepPressTimer;

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

- (void)triggerSiri {
    if (!gSettings.allowSiri) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        SpringBoard *sb = (SpringBoard *)[UIApplication sharedApplication];
        if ([sb respondsToSelector:@selector(_accessibilitySiriRequested)]) {
            [sb _accessibilitySiriRequested];
        }
    });
}

// 0.1 秒淡出隱藏 5 秒
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

// 觸控事件開始
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
            [self fadeAndHideFor5Seconds];
        }
    } else { // Haptic Touch
        [self handleHapticEndedWithDuration:duration];
    }
}

- (void)touchesCancelled:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    [super touchesCancelled:touches withEvent:event];
    if (self.is3DDeepPressed || self.isHapticEngaged || self.waitingForSecondTap) {
        sendHomeButtonHIDEvent(NO); // 確保觸控取消時釋放 Home 鍵
    }
    self.alpha = gSettings.idleOpacity;
    self.is3DDeepPressed = NO;
    self.isHapticEngaged = NO;
    self.waitingForSecondTap = NO;
}

// 3D Touch 邏輯 (向系統傳送實時 Home DOWN / UP)
- (void)handle3DTouch:(UITouch *)touch {
    CGFloat force = touch.force;
    CGFloat threshold = 1.5;

    if (force >= threshold && !self.is3DDeepPressed) {
        self.is3DDeepPressed = YES;
        self.alpha = 0.8;
        [self triggerFeedback];
        sendHomeButtonHIDEvent(YES); // 即時向系統發送 Home DOWN

        [self.deepPressTimer invalidate];
        self.deepPressTimer = [NSTimer scheduledTimerWithTimeInterval:1.0 repeats:NO block:^(NSTimer * _Nonnull timer) {
            if (gSettings.allowSiri) {
                self.hasTriggeredVoice = YES;
                [self triggerFeedback];
                sendHomeButtonHIDEvent(NO); // 結束 Home 按壓
                [self triggerSiri];
            }
        }];

    } else if (force < threshold - 0.3 && self.is3DDeepPressed) {
        [self handle3DTouchLifted];
    }
}

- (void)handle3DTouchLifted {
    self.is3DDeepPressed = NO;
    self.alpha = gSettings.idleOpacity;
    [self.deepPressTimer invalidate];

    if (self.hasTriggeredVoice) {
        self.hasTriggeredVoice = NO;
    } else {
        [self triggerFeedback];
        sendHomeButtonHIDEvent(NO); // 即時向系統發送 Home UP
    }
}

// Haptic Touch 邏輯
- (void)handleHapticBegan {
    if (self.waitingForSecondTap) {
        // 0.5 秒內的連續快速點按，即時傳送 Home DOWN
        [self.hapticSwitchTimer invalidate];
        self.alpha = 0.8;
        [self triggerFeedback];
        sendHomeButtonHIDEvent(YES);
    } else {
        self.isHapticEngaged = NO;
        self.hasTriggeredVoice = NO;

        // 1. 檢測按住達 0.5 秒發送 Home DOWN
        [self.hapticPressTimer invalidate];
        self.hapticPressTimer = [NSTimer scheduledTimerWithTimeInterval:0.5 repeats:NO block:^(NSTimer * _Nonnull timer) {
            self.isHapticEngaged = YES;
            self.alpha = 0.8;
            [self triggerFeedback];
            sendHomeButtonHIDEvent(YES); // 0.5 秒到了，發送 Home DOWN
        }];

        // 2. 檢測按住達 2.0 秒觸發 Siri
        [self.hapticVoiceTimer invalidate];
        self.hapticVoiceTimer = [NSTimer scheduledTimerWithTimeInterval:2.0 repeats:NO block:^(NSTimer * _Nonnull timer) {
            if (self.isHapticEngaged && gSettings.allowSiri) {
                self.hasTriggeredVoice = YES;
                [self triggerFeedback];
                sendHomeButtonHIDEvent(NO); // 放開 Home 按壓
                [self triggerSiri];
            }
        }];
    }
}

- (void)handleHapticEndedWithDuration:(NSTimeInterval)duration {
    [self.hapticPressTimer invalidate];
    [self.hapticVoiceTimer invalidate];

    if (self.hasTriggeredVoice) {
        self.hasTriggeredVoice = NO;
        self.alpha = gSettings.idleOpacity;
    } else if (self.isHapticEngaged) {
        // 首次按住超過 0.5 秒放手 -> 發送 Home UP
        [self triggerFeedback];
        sendHomeButtonHIDEvent(NO);
        self.alpha = 0.8;

        // 開啟 0.5 秒隨後快速點按等待視窗
        self.waitingForSecondTap = YES;
        [self.hapticSwitchTimer invalidate];
        self.hapticSwitchTimer = [NSTimer scheduledTimerWithTimeInterval:0.5 repeats:NO block:^(NSTimer * _Nonnull timer) {
            self.waitingForSecondTap = NO;
            self.alpha = gSettings.idleOpacity;
        }];
    } else if (self.waitingForSecondTap) {
        // 快速點按放手 -> 發送 Home UP
        [self triggerFeedback];
        sendHomeButtonHIDEvent(NO);
        self.alpha = 0.8;

        // 重新刷新 0.5 秒視窗，等待可能發生的第三次點按
        [self.hapticSwitchTimer invalidate];
        self.hapticSwitchTimer = [NSTimer scheduledTimerWithTimeInterval:0.5 repeats:NO block:^(NSTimer * _Nonnull timer) {
            self.waitingForSecondTap = NO;
            self.alpha = gSettings.idleOpacity;
        }];
    } else if (duration < 0.5) {
        // 少於 0.5 秒輕觸 -> 淡出隱藏 5 秒
        [self fadeAndHideFor5Seconds];
    }

    self.isHapticEngaged = NO;
}

@end

static PressHBWindow *gHBWindow = nil;
static PressHBButton *gHBButton = nil;

static void updateWindowPosition() {
    if (!gHBWindow || !gHBButton) return;

    CGRect screenBounds = [UIScreen mainScreen].bounds;
    CGFloat width = MIN(screenBounds.size.width, screenBounds.size.height);
    CGFloat height = MAX(screenBounds.size.width, screenBounds.size.height);

    CGFloat btnSize = 64.0;
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

    if (!gIsAppLaunched) return;

    dispatch_async(dispatch_get_main_queue(), ^{
        if (!gSettings.enabled) {
            if (gHBWindow) {
                gHBWindow.hidden = YES;
            }
            return;
        }

        if (!gHBWindow) {
            UIWindowScene *activeScene = nil;
            for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
                if ([scene isKindOfClass:[UIWindowScene class]]) {
                    activeScene = (UIWindowScene *)scene;
                    break;
                }
            }

            if (activeScene) {
                gHBWindow = [[PressHBWindow alloc] initWithWindowScene:activeScene];
            } else {
                gHBWindow = [[PressHBWindow alloc] initWithFrame:CGRectZero];
            }

            gHBWindow.windowLevel = UIWindowLevelStatusBar + 100;
            gHBWindow.backgroundColor = [UIColor clearColor];

            PressHBRootViewController *vc = [[PressHBRootViewController alloc] init];
            vc.view.backgroundColor = [UIColor clearColor];
            gHBWindow.rootViewController = vc;

            gHBButton = [[PressHBButton alloc] initWithFrame:CGRectZero];
            [vc.view addSubview:gHBButton];
        }

        updateWindowPosition();
        gHBButton.alpha = gSettings.idleOpacity;
        gHBWindow.hidden = NO;
    });
}

static void setupNotificationObservers() {
    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];

    // 鍵盤狀態過濾
    [nc addObserverForName:UIKeyboardWillShowNotification object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification * _Nonnull note) {
        if (!gSettings.allowKeyboard && gHBWindow) {
            gHBWindow.hidden = YES;
        }
    }];

    [nc addObserverForName:UIKeyboardWillHideNotification object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification * _Nonnull note) {
        if (gSettings.enabled && gHBWindow) {
            gHBWindow.hidden = NO;
        }
    }];

    // 橫向狀態過濾
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    [nc addObserverForName:UIApplicationDidChangeStatusBarOrientationNotification object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification * _Nonnull note) {
        UIInterfaceOrientation orientation = [UIApplication sharedApplication].statusBarOrientation;
        BOOL isLandscape = UIInterfaceOrientationIsLandscape(orientation);
        if (isLandscape && !gSettings.allowLandscape) {
            if (gHBWindow) gHBWindow.hidden = YES;
        } else {
            if (gSettings.enabled && gHBWindow) gHBWindow.hidden = NO;
        }
    }];
#pragma clang diagnostic pop
}

%hook SBLockScreenManager
- (void)lockUIFromSource:(int)arg1 withOptions:(id)arg2 {
    %orig;
    if (!gSettings.allowLockScreen && gHBWindow) {
        dispatch_async(dispatch_get_main_queue(), ^{
            gHBWindow.hidden = YES;
        });
    }
}

- (void)unlockUIFromSource:(int)arg1 {
    %orig;
    if (gSettings.enabled && gHBWindow) {
        dispatch_async(dispatch_get_main_queue(), ^{
            gHBWindow.hidden = NO;
        });
    }
}
%end

%ctor {
    @autoreleasepool {
        loadPreferences();

        [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidFinishLaunchingNotification
                                                          object:nil
                                                           queue:[NSOperationQueue mainQueue]
                                                      usingBlock:^(NSNotification * _Nonnull note) {
            gIsAppLaunched = YES;
            setupNotificationObservers();
            reloadTweakState();
        }];

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
