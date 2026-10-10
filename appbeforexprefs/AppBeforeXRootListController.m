#import "AppBeforeXRootListController.h"
#import <Preferences/PSSpecifier.h>

@implementation AppBeforeXRootListController

- (NSArray *)specifiers {
    if (!_specifiers) {
        _specifiers = [self loadSpecifiersFromPlistName:@"Root" target:self];
    }
    return _specifiers;
}

- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier {
    [super setPreferenceValue:value specifier:specifier];
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                         CFSTR("com.tnhdev.fun.appbeforeX/preferences.changed"),
                                         NULL, NULL, YES);
}

@end
