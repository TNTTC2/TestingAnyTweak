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

// ==================== 自訂下拉手勢（加大範圍）====================
%hook SpringBoard

- (void)applicationDidFinishLaunching:(id)application {
    %orig;
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.8 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        UIWindow *window = GetKeyWindow();
        if (!window) return;
        
        UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(dm_handlePan:)];
        pan.delegate = (id<UIGestureRecognizerDelegate>)self;
        pan.cancelsTouchesInView = NO;
        pan.maximumNumberOfTouches = 1;
        [window addGestureRecognizer:pan];
        
        NSLog(@"[DynamicMainland] Pan gesture added");
    });
}

%new
- (void)dm_handlePan:(UIPanGestureRecognizer *)gesture {
    if (isIslandVisible) return;
    
    CGPoint location = [gesture locationInView:gesture.view];
    CGPoint translation = [gesture translationInView:gesture.view];
    
    // 只接受從螢幕最上方 80pt 以內開始的下拉
    if (gesture.state == UIGestureRecognizerStateBegan) {
        if (location.y > 80.0) {
            // 開始位置太低，忽略這次手勢
            gesture.state = UIGestureRecognizerStateFailed;
            return;
        }
    }
    
    // 向下拉超過 35pt 就觸發
    if (gesture.state == UIGestureRecognizerStateChanged || gesture.state == UIGestureRecognizerStateEnded) {
        if (translation.y > 35.0) {
            ShowIsland();
            // 觸發後重置，避免連續觸發
            gesture.enabled = NO;
            gesture.enabled = YES;
        }
    }
}

// 允許跟其他手勢同時辨識（重要！否則容易被系統手勢擋住）
%new
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer {
    return YES;
}

%end

// ==================== 建構函式 ====================
%ctor {
    NSLog(@"[DynamicMainland] Loaded");
}
