#import <UIKit/UIKit.h>
#import <objc/runtime.h>

// ==================== 前置宣告 ====================
static void HideIsland(void);
static void ShowIsland(void);

// ==================== 全域變數 ====================
static UIWindow *islandWindow = nil;
static UIView *islandContainer = nil;
static UIView *gestureCaptureView = nil;
static BOOL isIslandVisible = NO;

// ==================== 工具方法 ====================
static UIWindow *GetKeyWindow(void) {
    for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
        if ([scene isKindOfClass:[UIWindowScene class]]) {
            UIWindowScene *windowScene = (UIWindowScene *)scene;
            for (UIWindow *window in windowScene.windows) {
                if (window.isKeyWindow) {
                    return window;
                }
            }
            if (windowScene.windows.count > 0) {
                return windowScene.windows.firstObject;
            }
        }
    }
    return nil;
}

static CGFloat DynamicIslandTopOffset(void) {
    UIWindow *keyWindow = GetKeyWindow();
    if (keyWindow && keyWindow.windowScene) {
        CGFloat height = keyWindow.windowScene.statusBarManager.statusBarFrame.size.height;
        if (height > 47.0) {
            return 59.0;
        }
        return height + 8.0;
    }
    return 59.0;
}

static void ShowIsland(void) {
    if (isIslandVisible) return;
    
    UIWindow *keyWindow = GetKeyWindow();
    if (!keyWindow) return;
    
    islandWindow = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    islandWindow.windowLevel = UIWindowLevelAlert + 1;
    islandWindow.backgroundColor = [UIColor clearColor];
    islandWindow.hidden = NO;
    
    CGFloat top = DynamicIslandTopOffset();
    CGFloat width = [UIScreen mainScreen].bounds.size.width - 32.0;
    
    islandContainer = [[UIView alloc] initWithFrame:CGRectMake(16.0, top, width, 320.0)];
    islandContainer.backgroundColor = [UIColor colorWithRed:0.11 green:0.11 blue:0.12 alpha:0.96];
    islandContainer.layer.cornerRadius = 28.0;
    islandContainer.layer.cornerCurve = kCACornerCurveContinuous;
    islandContainer.clipsToBounds = YES;
    islandContainer.alpha = 0.0;
    islandContainer.transform = CGAffineTransformMakeScale(0.92, 0.92);
    
    [islandWindow addSubview:islandContainer];
    
    // 關閉按鈕
    UIButton *closeBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    closeBtn.frame = CGRectMake(width - 50.0, 12.0, 36.0, 36.0);
    [closeBtn setTitle:@"✕" forState:UIControlStateNormal];
    [closeBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    closeBtn.titleLabel.font = [UIFont systemFontOfSize:20.0 weight:UIFontWeightMedium];
    [closeBtn addAction:[UIAction actionWithHandler:^(__kindof UIAction * _Nonnull action) {
        HideIsland();
    }] forControlEvents:UIControlEventTouchUpInside];
    
    [islandContainer addSubview:closeBtn];
    
    [UIView animateWithDuration:0.35
                          delay:0.0
         usingSpringWithDamping:0.85
          initialSpringVelocity:0.6
                        options:UIViewAnimationOptionCurveEaseOut
                     animations:^{
        islandContainer.alpha = 1.0;
        islandContainer.transform = CGAffineTransformIdentity;
    } completion:nil];
    
    isIslandVisible = YES;
}

static void HideIsland(void) {
    if (!isIslandVisible) return;
    
    [UIView animateWithDuration:0.25 animations:^{
        islandContainer.alpha = 0.0;
        islandContainer.transform = CGAffineTransformMakeScale(0.92, 0.92);
    } completion:^(BOOL finished) {
        islandWindow.hidden = YES;
        islandWindow = nil;
        islandContainer = nil;
        isIslandVisible = NO;
    }];
}

// ==================== 建立頂部透明捕捉區 ====================
static void SetupGestureCapture(void) {
    UIWindow *window = GetKeyWindow();
    if (!window || gestureCaptureView) return;
    
    // 在最上方建立一個高度 70pt 的透明 View 專門抓手勢
    gestureCaptureView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, [UIScreen mainScreen].bounds.size.width, 70.0)];
    gestureCaptureView.backgroundColor = [UIColor clearColor];
    gestureCaptureView.userInteractionEnabled = YES;
    
    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:[UIApplication sharedApplication].delegate
                                                                          action:@selector(dm_handlePan:)];
    // 因為 target 可能有問題，改用下面的方式
    [gestureCaptureView addGestureRecognizer:pan];
    
    // 正確的 target 設定
    pan = [[UIPanGestureRecognizer alloc] initWithTarget:gestureCaptureView action:@selector(dm_handlePan:)];
    // 我們用 runtime 加方法比較穩定
    [window addSubview:gestureCaptureView];
    [window bringSubviewToFront:gestureCaptureView];
    
    NSLog(@"[DynamicMainland] Gesture capture view added");
}

// ==================== SpringBoard Hook ====================
%hook SpringBoard

- (void)applicationDidFinishLaunching:(id)application {
    %orig;
    
    // 多試幾次，確保 window 已經準備好
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        SetupGestureCapture();
    });
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(4.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (!gestureCaptureView) {
            SetupGestureCapture();
        }
    });
}

%new
- (void)dm_handlePan:(UIPanGestureRecognizer *)gesture {
    if (isIslandVisible) return;
    
    CGPoint translation = [gesture translationInView:gesture.view];
    
    if (gesture.state == UIGestureRecognizerStateChanged || gesture.state == UIGestureRecognizerStateEnded) {
        if (translation.y > 30.0) {
            ShowIsland();
            
            // 重置手勢，避免卡住
            gesture.enabled = NO;
            gesture.enabled = YES;
        }
    }
}

%end

// 讓 gestureCaptureView 也能回應方法
%hook UIView

%new
- (void)dm_handlePan:(UIPanGestureRecognizer *)gesture {
    if (isIslandVisible) return;
    
    CGPoint translation = [gesture translationInView:gesture.view];
    
    if (gesture.state == UIGestureRecognizerStateChanged || gesture.state == UIGestureRecognizerStateEnded) {
        if (translation.y > 30.0) {
            ShowIsland();
            gesture.enabled = NO;
            gesture.enabled = YES;
        }
    }
}

%end

// ==================== 建構函式 ====================
%ctor {
    NSLog(@"[DynamicMainland] Loaded");
}
