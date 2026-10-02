#import "RedStarRootListController.h"
#import <UIKit/UIKit.h>
#import <CoreFoundation/CoreFoundation.h>

#define kPreferenceDomain CFSTR("com.tnhdev.fun.redstar")

@implementation RedStarRootListController

- (NSArray *)specifiers {
	if (!_specifiers) {
		_specifiers = [self loadSpecifiersFromPlistName:@"Root" target:self];
	}
	return _specifiers;
}

- (void)runTestAndLog {
	NSMutableString *logMessage = [NSMutableString string];
	NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
	[formatter setDateFormat:@"yyyy-MM-dd HH:mm:ss"];
	NSString *nowStr = [formatter stringFromDate:[NSDate date]];
	
	[logMessage appendFormat:@"=== RedStar Test Log [%@] ===\n", nowStr];

	// 1. 強制 cfprefsd 同步記憶體與磁碟設定
	CFPreferencesAppSynchronize(kPreferenceDomain);

	// 2. 使用 CFPreferences API 讀取正確數值
	Boolean keyExists = false;
	BOOL enabled = CFPreferencesGetAppBooleanValue(CFSTR("enabled"), kPreferenceDomain, &keyExists);
	
	CFStringRef intervalCF = (CFStringRef)CFPreferencesCopyAppValue(CFSTR("intervalMinutes"), kPreferenceDomain);
	NSString *interval = (__bridge_transfer NSString *)intervalCF ?: @"5";

	CFStringRef uuidCF = (CFStringRef)CFPreferencesCopyAppValue(CFSTR("appUUID"), kPreferenceDomain);
	NSString *uuid = (__bridge_transfer NSString *)uuidCF ?: @"";

	[logMessage appendFormat:@"[Setting] Enabled: %@\n", enabled ? @"YES" : @"NO"];
	[logMessage appendFormat:@"[Setting] Interval: %@ mins\n", interval];
	[logMessage appendFormat:@"[Setting] App UUID: %@\n", uuid];

	if ([uuid length] == 0) {
		[logMessage appendString:@"[Error] App UUID is empty!\n"];
	} else {
		NSString *targetDir = [NSString stringWithFormat:@"/var/mobile/Containers/Data/Application/%@/Library", uuid];
		[logMessage appendFormat:@"[Path Check] Target Path: %@\n", targetDir];

		NSFileManager *fm = [NSFileManager defaultManager];
		BOOL isDir = NO;
		BOOL exists = [fm fileExistsAtPath:targetDir isDirectory:&isDir];

		if (!exists) {
			[logMessage appendString:@"[Path Check] Result: FAILED (Directory does not exist)\n"];
		} else if (!isDir) {
			[logMessage appendString:@"[Path Check] Result: FAILED (Path is not a directory)\n"];
		} else {
			[logMessage appendString:@"[Path Check] Result: SUCCESS (Directory exists)\n"];

			// 嘗試測試畫面擷取
			UIWindow *keyWindow = nil;
			for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
				if (scene.activationState == UISceneActivationStateForegroundActive && [scene isKindOfClass:[UIWindowScene class]]) {
					UIWindowScene *windowScene = (UIWindowScene *)scene;
					for (UIWindow *window in windowScene.windows) {
						if (window.isKeyWindow) {
							keyWindow = window;
							break;
						}
					}
				}
				if (keyWindow) break;
			}

			if (!keyWindow) {
				[logMessage appendString:@"[Screenshot] Result: FAILED (No active UIWindow)\n"];
			} else {
				@try {
					UIGraphicsBeginImageContextWithOptions(keyWindow.bounds.size, YES, 0.0);
					[keyWindow drawViewHierarchyInRect:keyWindow.bounds afterScreenUpdates:NO];
					UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
					UIGraphicsEndImageContext();

					if (!image) {
						[logMessage appendString:@"[Screenshot] Result: FAILED (Nil image)\n"];
					} else {
						NSData *imageData = UIImagePNGRepresentation(image);
						NSDateFormatter *fileFormatter = [[NSDateFormatter alloc] init];
						[fileFormatter setDateFormat:@"yyyyMMdd_HHmmss"];
						NSString *fileName = [NSString stringWithFormat:@"TEST_%@.png", [fileFormatter stringFromDate:[NSDate date]]];
						NSString *filePath = [targetDir stringByAppendingPathComponent:fileName];

						NSError *writeError = nil;
						BOOL saved = [imageData writeToFile:filePath options:NSDataWritingAtomic error:&writeError];
						if (saved) {
							[logMessage appendFormat:@"[Save Test] SUCCESS: %@\n", filePath];
						} else {
							[logMessage appendFormat:@"[Save Test] FAILED: %@\n", writeError.localizedDescription];
						}
					}
				} @catch (NSException *e) {
					[logMessage appendFormat:@"[Screenshot] Exception: %@\n", e.reason];
				}
			}
		}
	}

	[logMessage appendString:@"===================================\n\n"];

	// 3. 寫入用戶層級日誌目錄 /var/mobile/Library/Logs/RedStar/
	NSString *logDir = @"/var/mobile/Library/Logs/RedStar";
	NSFileManager *fm = [NSFileManager defaultManager];
	if (![fm fileExistsAtPath:logDir]) {
		[fm createDirectoryAtPath:logDir withIntermediateDirectories:YES attributes:nil error:nil];
	}

	NSString *logFilePath = [logDir stringByAppendingPathComponent:@"test_log.txt"];
	NSFileHandle *fileHandle = [NSFileHandle fileHandleForWritingAtPath:logFilePath];
	if (!fileHandle) {
		[logMessage writeToFile:logFilePath atomically:YES encoding:NSUTF8StringEncoding error:nil];
	} else {
		[fileHandle seekToEndOfFile];
		[fileHandle writeData:[logMessage dataUsingEncoding:NSUTF8StringEncoding]];
		[fileHandle closeFile];
	}

	// 顯示彈窗
	UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Test Completed"
                                                                   message:[NSString stringWithFormat:@"Log Path: %@\n\nSummary:\n%@", logFilePath, logMessage]
                                                            preferredStyle:UIAlertControllerStyleAlert];
	[alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
	[self presentViewController:alert animated:YES completion:nil];
}

@end
