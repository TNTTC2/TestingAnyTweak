#import <UIKit/UIKit.h>
#import <objc/runtime.h>

// ==================== 全域變數 ====================
static UIWindow *islandWindow = nil;
static UIView *islandContainer = nil;
static BOOL isIslandVisible = NO;

// ==================== 工具方法 ====================
static CGFloat DynamicIslandTopOffset() {
    // 簡單判斷動態島 / 瀏海高度（後續可再精準化）
    CGFloat height = [UIApplication sharedApplication].statusBarFrame.size.height;
    if (height > 47) return 59.0; // 動態島大概位置
    return height + 8.0;
}

static void ShowIsland() {
    if (isIslandVisible) return;
    
    UIWindow *keyWindow = nil;
    for (UIWindow *window in [UIApplication sharedApplication].windows) {
        if (window.isKeyWindow) {
            keyWindow = window;
            break;
        }
    }
    if (!keyWindow) return;
    
    // 建立浮層 Window
    islandWindow = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    islandWindow.windowLevel = UIWindowLevelAlert + 1;
    islandWindow.backgroundColor = [UIColor clearColor];
    islandWindow.hidden = NO;
    
    // 主容器（島嶼本體）
    CGFloat top = DynamicIslandTopOffset();
    CGFloat width = [UIScreen mainScreen].bounds.size.width - 32;
    islandContainer = [[UIView alloc] initWithFrame:CGRectMake(16, top, width, 320)];
    islandContainer.backgroundColor = [UIColor colorWithRed:0.11 green:0.11 blue:0.12 alpha:0.96];
    islandContainer.layer.cornerRadius = 28;
    islandContainer.layer.cornerCurve = kCACornerCurveContinuous;
    islandContainer.clipsToBounds = YES;
    islandContainer.alpha = 0;
    islandContainer.transform = CGAffineTransformMakeScale(0.92, 0.92);
    
    // 簡單關閉手勢（點背景關閉）
    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:nil action:nil];
    // 暫時先用按鈕關閉，之後再補完整手勢
    
    [islandWindow addSubview:islandContainer];
    
    // 測試用關閉按鈕
    UIButton *closeBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    closeBtn.frame = CGRectMake(width - 50, 12, 36, 36);
    [closeBtn setTitle:@"✕" forState:UIControlStateNormal];
    [closeBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    closeBtn.titleLabel.font = [UIFont systemFontOfSize:20 weight:UIFontWeightMedium];
    [closeBtn addTarget:nil action:@selector(hideIsland) forControlEvents:UIControlEventTouchUpInside];
    // 暫時用 block 方式處理
    objc_setAssociatedObject(closeBtn, "closeAction", ^{
        HideIsland();
    }, OBJC_ASSOCIATION_COPY_NONATOMIC);
    
    [islandContainer addSubview:closeBtn];
    
    // 動畫出現
    [UIView animateWithDuration:0.35 delay:0 usingSpringWithDamping:0.85 initialSpringVelocity:0.6 options:UIViewAnimationOptionCurveEaseOut animations:^{
        islandContainer.alpha = 1.0;
        islandContainer.transform = CGAffineTransformIdentity;
    } completion:nil];
    
    isIslandVisible = YES;
}

static void HideIsland() {
    if (!isIslandVisible) return;
    
    [UIView animateWithDuration:0.25 animations:^{
        islandContainer.alpha = 0;
        islandContainer.transform = CGAffineTransformMakeScale(0.92, 0.92);
    } completion:^(BOOL finished) {
        islandWindow.hidden = YES;
        islandWindow = nil;
        islandContainer = nil;
        isIslandVisible = NO;
    }];
}

// ==================== 狀態列下拉手勢 ====================
%hook UIStatusBar_Base

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    %orig;
    
    UITouch *touch = [touches anyObject];
    CGPoint location = [touch locationInView:self];
    
    // 簡單判斷從狀態列開始向下滑
    if (location.y < 20) {
        // 這裡先用點擊觸發測試，之後改成真正的 pan 手勢
        static CFAbsoluteTime lastTrigger = 0;
        CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
        if (now - lastTrigger > 0.8) {
            lastTrigger = now;
            ShowIsland();
        }
    }
}

%end

// 更穩定的方式：在 SpringBoard 加邊緣手勢
%hook SpringBoard

- (void)applicationDidFinishLaunching:(id)application {
    %orig;
    
    // 延遲加手勢，確保 window 已經準備好
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        UIWindow *window = [UIApplication sharedApplication].keyWindow;
        if (!window) return;
        
        UIScreenEdgePanGestureRecognizer *edgePan = [[UIScreenEdgePanGestureRecognizer alloc] initWithTarget:self action:@selector(dm_handleEdgePan:)];
        edgePan.edges = UIRectEdgeTop;
        [window addGestureRecognizer:edgePan];
    });
}

%new
- (void)dm_handleEdgePan:(UIScreenEdgePanGestureRecognizer *)gesture {
    if (gesture.state == UIGestureRecognizerStateBegan || gesture.state == UIGestureRecognizerStateChanged) {
        CGPoint translation = [gesture translationInView:gesture.view];
        if (translation.y > 30 && !isIslandVisible) {
            ShowIsland();
        }
    }
}

%end

// ==================== 建構函式 ====================
%ctor {
    NSLog(@"[DynamicMainland] Loaded");
}
