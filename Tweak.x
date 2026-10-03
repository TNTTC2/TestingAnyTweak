#import <UIKit/UIKit.h>
#import <CoreFoundation/CoreFoundation.h>
#import <AudioToolbox/AudioToolbox.h>
#import <mach/mach_time.h>
#import <dlfcn.h>

#define kPreferenceDomain CFSTR("com.tnhdev.fun.presshb")

// --- IOHIDEvent 底層定義 ---
typedef struct __IOHIDEvent *IOHIDEventRef;
typedef uint32_t IOHIDEventType;

#define kIOHIDEventTypeDigitizer 11

typedef enum {
    kIOHIDEventFieldDigitizerX = (11 << 16) | 0,
    kIOHIDEventFieldDigitizerY = (11 << 16) | 1,
    kIOHIDEventFieldDigitizerPressure = (11 << 16) | 3,
    kIOHIDEventFieldDigitizerIsTouching = (11 << 16) | 5
} IOHIDEventFieldDigitizer;

extern IOHIDEventType IOHIDEventGetType(IOHIDEventRef event);
extern float IOHIDEventGetFloatValue(IOHIDEventRef event, uint32_t field);
extern integer_t IOHIDEventGetIntValue(IOHIDEventRef event, uint32_t field);
typedef IOHIDEventRef (*IOHIDEventCreateKeyboardEventFunc)(CFAllocatorRef allocator, uint64_t timeStamp, uint16_t usagePage, uint16_t usage, Boolean down, uint32_t flags);

@interface SpringBoard : UIApplication
- (void)_handleHIDEvent:(IOHIDEventRef)event;
@end

typedef struct {
    BOOL enabled;
    NSInteger touchMode; // 0 = 3D Touch, 1 = Haptic Touch
    CGFloat idleOpacity;
    NSInteger position;
    BOOL allowLandscape;
    BOOL allowKeyboard;
    BOOL allowLockScreen;
} PressHBSettings;

static PressHBSettings gSettings;
static BOOL gIsAppLaunched = NO;

// 發送 Home 鍵 Down/Up HID 訊號
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

@interface PressHBWindow : UIWindow
@end
@implementation PressHBWindow
- (BOOL)_canBecomeKeyWindow { return NO; }
@end

@interface PressHBRootViewController : UIViewController
@end
@implementation PressHBRootViewController
- (BOOL)shouldAutorotate { return NO; }
- (UIInterfaceOrientationMask)supportedInterfaceOrientations { return UIInterfaceOrientationMaskPortrait; }
@end

@interface PressHBButton : UIView
@property (nonatomic, assign) BOOL isHiddenTemporarily;
@property (nonatomic, strong) NSTimer *hideTimer;
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
@end

static PressHBWindow *gHBWindow = nil;
static PressHBButton *gHBButton = nil;

// --- 全域 3D Touch 狀態 (不受 App 切換影響) ---
static BOOL gIsHIDDeepPressed = NO;
static BOOL gWas3DTriggeredInSession = NO;

// 處理底層 3D Touch 硬體壓力和位置
static void processRawDigitizerEvent(float rawX, float rawY, float pressure, BOOL isTouching) {
    if (!gHBWindow || gHBWindow.hidden || gHBButton.isHiddenTemporarily) return;

    // 將 0.0 ~ 1.0 的相對座標轉換為螢幕像素座標
    CGRect screenBounds = [UIScreen mainScreen].bounds;
    CGPoint touchPoint = CGPointMake(rawX * screenBounds.size.width, rawY * screenBounds.size.height);

    // 檢查觸控點是否落在懸浮按鈕範圍內
    BOOL isInside = CGRectContainsPoint(gHBWindow.frame, touchPoint);

    if (!isTouching) {
        // 放手：手指離開螢幕
        if (gIsHIDDeepPressed) {
            gIsHIDDeepPressed = NO;
            dispatch_async(dispatch_get_main_queue(), ^{
                gHBButton.alpha = gSettings.idleOpacity;
                [gHBButton triggerFeedback];
            });
            sendHomeButtonHIDEvent(NO);
        } else if (isInside && !gWas3DTriggeredInSession) {
            // 純輕點放手：隱藏 5 秒
            dispatch_async(dispatch_get_main_queue(), ^{
                [gHBButton fadeAndHideFor5Seconds];
            });
        }
        gWas3DTriggeredInSession = NO;
        return;
    }

    if (isInside) {
        // 底層硬件 Pressure 閾值：重壓門檻約為 0.45 ~ 0.5，放鬆門檻約為 0.25
        float pressThreshold = 0.45f;
        float releaseThreshold = 0.25f;

        if (pressure >= pressThreshold && !gIsHIDDeepPressed) {
            // 無縫重壓 Down！
            gIsHIDDeepPressed = YES;
            gWas3DTriggeredInSession = YES;
            dispatch_async(dispatch_get_main_queue(), ^{
                gHBButton.alpha = 0.8;
                [gHBButton triggerFeedback];
            });
            sendHomeButtonHIDEvent(YES);
        } else if (pressure < releaseThreshold && gIsHIDDeepPressed) {
            // 無縫鬆手 Up！（手指不離開螢幕，可直接再次重壓）
            gIsHIDDeepPressed = NO;
            dispatch_async(dispatch_get_main_queue(), ^{
                gHBButton.alpha = gSettings.idleOpacity;
                [gHBButton triggerFeedback];
            });
            sendHomeButtonHIDEvent(NO);
        }
    } else {
        // 手指移出按鈕區域
        if (gIsHIDDeepPressed) {
            gIsHIDDeepPressed = NO;
            dispatch_async(dispatch_get_main_queue(), ^{
                gHBButton.alpha = gSettings.idleOpacity;
            });
            sendHomeButtonHIDEvent(NO);
        }
    }
}

%hook SpringBoard
- (void)_handleHIDEvent:(IOHIDEventRef)event {
    %orig;

    if (gSettings.enabled && gSettings.touchMode == 0 && gHBWindow && !gHBWindow.hidden) {
        if (IOHIDEventGetType(event) == kIOHIDEventTypeDigitizer) {
            float x = IOHIDEventGetFloatValue(event, kIOHIDEventFieldDigitizerX);
            float y = IOHIDEventGetFloatValue(event, kIOHIDEventFieldDigitizerY);
            float pressure = IOHIDEventGetFloatValue(event, kIOHIDEventFieldDigitizerPressure);
            integer_t touching = IOHIDEventGetIntValue(event, kIOHIDEventFieldDigitizerIsTouching);

            processRawDigitizerEvent(x, y, pressure, (touching != 0));
        }
    }
}
%end

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

        if (!gHBWindow) {
            UIWindowScene *activeScene = nil;
            for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
                if ([scene isKindOfClass:[UIWindowScene class]]) {
                    activeScene = (UIWindowScene *)scene;
                    break;
                }
            }

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

%ctor {
    @autoreleasepool {
        loadPreferences();

        [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidFinishLaunchingNotification
                                                          object:nil
                                                           queue:[NSOperationQueue mainQueue]
                                                      usingBlock:^(NSNotification * _Nonnull note) {
            gIsAppLaunched = YES;
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
