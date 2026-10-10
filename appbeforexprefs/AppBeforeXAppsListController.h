#import <UIKit/UIKit.h>

// 手動宣告
@interface PSListController : UIViewController
- (NSArray *)loadSpecifiersFromPlistName:(NSString *)name target:(id)target;
@end

@interface PSSpecifier : NSObject
+ (instancetype)preferenceSpecifierNamed:(NSString *)name
                                  target:(id)target
                                     set:(SEL)set
                                     get:(SEL)get
                                  detail:(Class)detail
                                    cell:(int)cellType
                                    edit:(Class)edit;
- (void)setProperty:(id)value forKey:(NSString *)key;
- (id)propertyForKey:(NSString *)key;
@end

enum {
    PSGroupCell = 0,
    PSSwitchCell = 5,
    PSLinkCell = 1
};

@interface AppBeforeXAppsListController : PSListController
@end
