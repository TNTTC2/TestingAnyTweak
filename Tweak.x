#import <UIKit/UIKit.h>
#import <objc/runtime.h>

// ==================== 前置宣告 ====================
static void HideIsland(void);
static void ShowIsland(void);

// ==================== 全域變數 ====================
static UIWindow *islandWindow = nil;
static UIView *islandContainer = nil;
static BOOL isIslandVisible = NO;

// ==================== 工具方法 ====================
static UIWindow *GetKeyWindow(void) {
    // 相容 iOS 13+ 的取得 keyWindow 方式
    for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
        if ([scene isKindOfClass:[UIWindowScene class]]) {
            UIWindowScene *windowScene = (UIWindowScene *)scene;
            for (UIWindow *window in windowScene.windows) {
                if (window.isKeyWindow) {
                    return window;
                }
            }
            // fallback
            if (windowScene.windows.count > 0) {
                return windowScene.windows.firstObject;
            }
        }
    }
    return nil;
}

static CGFloat DynamicIslandTopOffset(void) {
    // 使用 statusBarManager 取代 deprecated 的 statusBarFrame
    UIWindow *keyWindow = GetKeyWindow();
    if (keyWindow && keyWindow.windowScene) {
        CGFloat height = keyWindow.windowScene.statusBarManager.statusBarFrame.size.height;
        if (height > 47.0) {
            return 59.0; // 動態島大致位置
        }
        return height + 8.0;
    }
    // fallback
    return 59.0;
}

static void ShowIsland(void) {
    if (isIslandVisible) return;
    
    UIWindow *keyWindow = GetKeyWindow();
    if (!keyWindow) return;
    
    // 建立浮層 Window
    islandWindow = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    islandWindow.windowLevel = UIWindowLevelAlert + 1;
    islandWindow.backgroundColor = [UIColor clearColor];
    islandWindow.hidden = NO;
    
    // 主容器（島嶼本體）
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
    [closeBtn addTarget:[UIApplication sharedApplication].delegate
                 action:@selector(dm_hideIsland)
       forControlEvents:UIControlEventTouchUpInside];
    
    // 用 associated object 暫存關閉動作（簡單做法）
    [closeBtn addAction:[UIAction actionWithHandler:^(__kindof UIAction * _Nonnull action) {
        HideIsland();
    }] forControlEvents:UIControlEventTouchUpInside];
    
    [islandContainer addSubview:closeBtn];
    
    // 動畫出現
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

// ==================== SpringBoard 邊緣手勢（主要觸發方式）====================
%hook SpringBoard

- (void)applicationDidFinishLaunching:(id)application {
    %orig;
    
    // 延遲加入手勢，確保 window 已準備好
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        UIWindow *window = GetKeyWindow();
        if (!window) return;
        
        UIScreenEdgePanGestureRecognizer *edgePan = [[UIScreenEdgePanGestureRecognizer alloc] initWithTarget:self action:@selector(dm_handleEdgePan:)];
        edgePan.edges = UIRectEdgeTop;
        edgePan.delegate = (id<UIGestureRecognizerDelegate>)self;
        [window addGestureRecognizer:edgePan];
    });
}

%new
- (void)dm_handleEdgePan:(UIScreenEdgePanGestureRecognizer *)gesture {
    if (gesture.state == UIGestureRecognizerStateBegan || gesture.state == UIGestureRecognizerStateChanged) {
        CGPoint translation = [gesture translationInView:gesture.view];
        if (translation.y > 28.0 && !isIslandVisible) {
            ShowIsland();
        }
    }
}

%new
- (void)dm_hideIsland {
    HideIsland();
}

%end

// ==================== 建構函式 ====================
%ctor {
    NSLog(@"[DynamicMainland] Loaded");
}
