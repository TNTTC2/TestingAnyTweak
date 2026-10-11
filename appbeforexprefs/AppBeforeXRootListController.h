#import <UIKit/UIKit.h>

@interface PSSpecifier : NSObject
+ (id)preferenceSpecifierNamed:(NSString *)name target:(id)target set:(SEL)set get:(SEL)get detail:(Class)detail cell:(NSInteger)cellType edit:(Class)editClass;
- (void)setProperty:(id)property forKey:(NSString *)key;
- (id)propertyForKey:(NSString *)key;
@property (nonatomic) SEL action;
@end

@interface PSListController : UIViewController {
    NSMutableArray *_specifiers;
}
- (NSArray *)specifiers;
- (NSArray *)loadSpecifiersFromPlistName:(NSString *)name target:(id)target;
- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier;
@end

enum {
    PSGroupCell = 0,
    PSLinkCell = 1,
    PSSwitchCell = 5
};

@interface AppBeforeXRootListController : PSListController
@end
