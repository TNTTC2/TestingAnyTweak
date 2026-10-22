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
- (void)_handleHIDEvent:(IOHIDEventRef)event;
@end

typedef struct {
    BOOL enabled;
    NSInteger touchMode; // 0 = 3D Touch, 1 = Haptic Touch
    CGFloat idleOpacity; // 0.4 ~ 0.8
    NSInteger position;  // 0=Bottom, 1=Bottom Left, 2=Bottom Right, 3=Top, 4=Top Left, 5=Top Right
    BOOL allowLandscape;
    BOOL allowKeyboard;
    BOOL allowLockScreen;
} PressHBSettings;

static PressHBSettings gSettings;
static BOOL gIsAppLaunched = NO;

// 向系統發送 Home 鍵 Down/Up HID 訊號
static void sendHomeButtonHIDEvent(BOOL isDown) {
    dispatch_async(dispatch_get_main_queue(), ^{
        uint64_t time = mach_absolute_time();
        static IOHIDEventCreateKeyboardEventFunc createKeyboardEvent = NULL;
        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{
            createKeyboardEvent = (IOHIDEventCreateKeyboardEventFunc)dlsym(RTLD_DEFAULT, "IOHIDEventCreateKeyboardEvent");
        });

        if (createKeyboardEvent) {
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

// 發送一次完整的 Home 鍵點按 (Down -> Up)
static void sendSingleHomeButtonClick(void) {
    sendHomeButtonHIDEvent(YES);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.05 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        sendHomeButtonHIDEvent(NO);
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

    gSettings.allowLandscape = keyExists ? CFPreferencesGetAppBooleanValue(CFSTR("allowLandscape"), kPreferenceDomain, NULL) : YES;
    gSettings.allowKeyboard = CFPreferencesGetAppBooleanValue(CFSTR("allowKeyboard"), kPreferenceDomain, NULL);
    gSettings.allowLockScreen = CFPreferencesGetAppBooleanValue(CFSTR("allowLockScreen"), kPreferenceDomain, NULL);
}

// 自訂 Window，不搶奪焦點
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

// 3D Touch 狀態標記
@property (nonatomic, assign) BOOL isDeepPressed;
@property (nonatomic, assign) BOOL was3DTriggeredInCurrentTouch;

// Haptic Touch 狀態標記 (對齊原生邏輯)
@property (nonatomic, assign) BOOL isHapticEngaged;
@property (nonatomic, assign) BOOL waitingForSecondLightTap;
@property (nonatomic, strong) NSTimer *hapticPressTimer;
@property (nonatomic, strong) NSTimer *hapticSwitchWindowTimer;
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

// 精準檢查目前是否為橫向
- (BOOL)isCurrentOrientationLandscape {
    UIWindowScene *scene = self.window.windowScene;
    if (scene) {
        return UIInterfaceOrientationIsLandscape(scene.interfaceOrientation);
    }
    return UIInterfaceOrientationIsLandscape([UIApplication sharedApplication].statusBarOrientation);
}

// 淡出隱藏 5 秒（輕點專用）
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
    if ([self isCurrentOrientationLandscape] && !gSettings.allowLandscape) return;

    if (gSettings.touchMode == 0) { // 3D Touch 模式
        self.isDeepPressed = NO;
        self.was3DTriggeredInCurrentTouch = NO;
        UITouch *touch = [touches anyObject];
        [self handle3DTouchForce:touch];
    } else { // Haptic Touch 模式
        if (self.waitingForSecondLightTap) {
            // 第二次點擊按下
            [self triggerFeedback];
            sendHomeButtonHIDEvent(YES);
        } else {
            // 第一次按下，啟動 0.5 秒長按計時
            self.isHapticEngaged = NO;
            [self.hapticPressTimer invalidate];
            self.hapticPressTimer = [NSTimer scheduledTimerWithTimeInterval:0.5 repeats:NO block:^(NSTimer * _Nonnull timer) {
                self.isHapticEngaged = YES;
                [self triggerFeedback]; // 達到 0.5 秒時震動
            }];
        }
    }
}

- (void)touchesMoved:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    [super touchesMoved:touches withEvent:event];
    if (self.isHiddenTemporarily) return;
    if ([self isCurrentOrientationLandscape] && !gSettings.allowLandscape) return;

    if (gSettings.touchMode == 0) {
        UITouch *touch = [touches anyObject];
        [self handle3DTouchForce:touch];
    }
}

// 處理 3D Touch 力度變化
- (void)handle3DTouchForce:(UITouch *)touch {
    CGFloat force = touch.force;
    CGFloat threshold = 1.5;

    if (force >= threshold && !self.isDeepPressed) {
        self.isDeepPressed = YES;
        self.was3DTriggeredInCurrentTouch = YES;
        self.alpha = 0.8;
        [self triggerFeedback];
        sendHomeButtonHIDEvent(YES);
    } else if (force < threshold - 0.3 && self.isDeepPressed) {
        [self process3DTouchRelease];
    }
}

// 3D Touch 鬆手/放開重壓邏輯
- (void)process3DTouchRelease {
    self.isDeepPressed = NO;
    self.alpha = gSettings.idleOpacity;
    [self triggerFeedback];
    sendHomeButtonHIDEvent(NO);
}

- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    [super touchesEnded:touches withEvent:event];
    if (self.isHiddenTemporarily) return;
    if ([self isCurrentOrientationLandscape] && !gSettings.allowLandscape) return;

    if (gSettings.touchMode == 0) { // 3D Touch 模式
        if (self.isDeepPressed) {
            [self process3DTouchRelease];
        } else if (!self.was3DTriggeredInCurrentTouch) {
            [self fadeAndHideFor5Seconds];
        } else {
            self.alpha = gSettings.idleOpacity;
        }
        self.isDeepPressed = NO;
        self.was3DTriggeredInCurrentTouch = NO;
    } else { // Haptic Touch 模式
        [self.hapticPressTimer invalidate];

        if (self.waitingForSecondLightTap) {
            // 第二次點擊放手 -> 發送 Home UP 完成雙擊
            [self triggerFeedback];
            sendHomeButtonHIDEvent(NO);
            self.waitingForSecondLightTap = NO;
            [self.hapticSwitchWindowTimer invalidate];
        } else {
            if (self.isHapticEngaged) {
                // 長按超過 0.5 秒後放手 -> 觸發一次 Home 點擊
                [self triggerFeedback];
                sendSingleHomeButtonClick();
                
                // 開啟 0.5 秒等待視窗接收第二次點擊（App 切換器）
                self.waitingForSecondLightTap = YES;
                [self.hapticSwitchWindowTimer invalidate];
                self.hapticSwitchWindowTimer = [NSTimer scheduledTimerWithTimeInterval:0.5 repeats:NO block:^(NSTimer * _Nonnull timer) {
                    self.waitingForSecondLightTap = NO;
                }];
            } else {
                // 按住少於 0.5 秒（輕點） -> 隱藏 5 秒
                [self fadeAndHideFor5Seconds];
            }
        }
        self.isHapticEngaged = NO;
    }
}

- (void)touchesCancelled:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    [super touchesCancelled:touches withEvent:event];
    [self.hapticPressTimer invalidate];
    [self.hapticSwitchWindowTimer invalidate];

    self.alpha = gSettings.idleOpacity;
    if (gSettings.touchMode == 0) {
        if (self.isDeepPressed) {
            [self process3DTouchRelease];
        }
        self.isDeepPressed = NO;
        self.was3DTriggeredInCurrentTouch = NO;
    } else {
        sendHomeButtonHIDEvent(NO);
    }
    self.isHapticEngaged = NO;
    self.waitingForSecondLightTap = NO;
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
        case 0: x = (width - btnSize) / 2.0; y = height - btnSize - marginY; break;
        case 1: x = marginX; y = height - btnSize - marginY; break;
        case 2: x = width - btnSize - marginX; y = height - btnSize - marginY; break;
        case 3: x = (width - btnSize) / 2.0; y = marginY + 20.0; break;
        case 4: x = marginX; y = marginY + 20.0; break;
        case 5: x = width - btnSize - marginX; y = marginY + 20.0; break;
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
            if (gHBWindow) gHBWindow.hidden = YES;
            return;
        }

        // 強制橫向檢查：若不允許橫向且目前為橫向，直接隱藏視窗
        BOOL isLandscape = NO;
        UIWindowScene *activeScene = nil;
        for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
            if ([scene isKindOfClass:[UIWindowScene class]]) {
                activeScene = (UIWindowScene *)scene;
                break;
            }
        }
        
        if (activeScene) {
            isLandscape = UIInterfaceOrientationIsLandscape(activeScene.interfaceOrientation);
        } else {
            isLandscape = UIInterfaceOrientationIsLandscape([UIApplication sharedApplication].statusBarOrientation);
        }

        if (isLandscape && !gSettings.allowLandscape) {
            if (gHBWindow) gHBWindow.hidden = YES;
            return;
        }

        if (!gHBWindow) {
            gHBWindow = activeScene ? [[PressHBWindow alloc] initWithWindowScene:activeScene] : [[PressHBWindow alloc] initWithFrame:CGRectZero];
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

    // 螢幕旋轉 / 狀態列方向改變過濾
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    [nc addObserverForName:UIApplicationDidChangeStatusBarOrientationNotification object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification * _Nonnull note) {
        reloadTweakState();
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
