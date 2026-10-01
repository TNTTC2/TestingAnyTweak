#import "RedStarRootListController.h"
#import <UIKit/UIKit.h>

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

	// 讀取 Preference 設定
	NSDictionary *prefs = [NSDictionary dictionaryWithContentsOfFile:@"/var/mobile/Library/Preferences/com.tnhdev.redstar.plist"];
	BOOL enabled = [prefs[@"enabled"] boolValue];
	NSString *interval = prefs[@"intervalMinutes"] ?: @"5";
	NSString *uuid = prefs[@"appUUID"] ?: @"";

	[logMessage appendFormat:@"[Setting] Enabled: %@\n", enabled ? @"YES" : @"NO"];
	[logMessage appendFormat:@"[Setting] Interval: %@ mins\n", interval];
	[logMessage appendFormat:@"[Setting] App UUID: %@\n", uuid];

	if ([uuid length] == 0) {
		[logMessage appendString:@"[Error] App UUID is empty!\n"];
	} else {
		NSString *targetDir = [NSString stringWithFormat:@"/var/mobile/Containers/Data/Application/%@/Library", uuid];
		[logMessage appendFormat:@"[Path Check] Attempted Target Path: %@\n", targetDir];

		NSFileManager *fm = [NSFileManager defaultManager];
		BOOL isDir = NO;
		BOOL exists = [fm fileExistsAtPath:targetDir isDirectory:&isDir];

		if (!exists) {
			[logMessage appendString:@"[Path Check] Result: FAILED (Directory does not exist)\n"];
		} else if (!isDir) {
			[logMessage appendString:@"[Path Check] Result: FAILED (Path exists but is not a directory)\n"];
		} else {
			[logMessage appendString:@"[Path Check] Result: SUCCESS (Directory exists)\n"];

			// 嘗試進行螢幕截圖測試
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
				// 降級嘗試獲取第一個 window
				for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
					if ([scene isKindOfClass:[UIWindowScene class]]) {
						UIWindowScene *windowScene = (UIWindowScene *)scene;
						if (windowScene.windows.count > 0) {
							keyWindow = windowScene.windows.firstObject;
							break;
						}
					}
				}
			}

			if (!keyWindow) {
				[logMessage appendString:@"[Screenshot] Result: FAILED (Could not find active UIWindow)\n"];
			} else {
				[logMessage appendFormat:@"[Screenshot] Found Window bounds: %@\n", NSStringFromCGRect(keyWindow.bounds)];
				@try {
					UIGraphicsBeginImageContextWithOptions(keyWindow.bounds.size, YES, 0.0);
					[keyWindow drawViewHierarchyInRect:keyWindow.bounds afterScreenUpdates:NO];
					UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
					UIGraphicsEndImageContext();

					if (!image) {
						[logMessage appendString:@"[Screenshot] Result: FAILED (Image context returned nil)\n"];
					} else {
						NSData *imageData = UIImagePNGRepresentation(image);
						if (!imageData) {
							[logMessage appendString:@"[Screenshot] Result: FAILED (PNG representation failed)\n"];
						} else {
							[logMessage appendFormat:@"[Screenshot] Result: SUCCESS (Image generated, size: %lu bytes)\n", (unsigned long)imageData.length];

							// 嘗試寫入目標路徑
							NSDateFormatter *fileFormatter = [[NSDateFormatter alloc] init];
							[fileFormatter setDateFormat:@"yyyyMMdd_HHmmss"];
							NSString *fileName = [NSString stringWithFormat:@"TEST_%@.png", [fileFormatter stringFromDate:[NSDate date]]];
							NSString *filePath = [targetDir stringByAppendingPathComponent:fileName];

							NSError *writeError = nil;
							BOOL saved = [imageData writeToFile:filePath options:NSDataWritingAtomic error:&writeError];
							if (saved) {
								[logMessage appendFormat:@"[Save Test] Result: SUCCESS\n[Save Test] File Saved At: %@\n", filePath];
							} else {
								[logMessage appendFormat:@"[Save Test] Result: FAILED (Error: %@)\n", writeError.localizedDescription];
							}
						}
					}
				} @catch (NSException *e) {
					[logMessage appendFormat:@"[Screenshot] Exception caught: %@\n", e.reason];
				}
			}
		}
	}

	[logMessage appendString:@"===================================\n\n"];

	// 確保 /var/jb/RedStar/ 目錄存在並寫入 Log 檔案
	NSString *logDir = @"/var/jb/RedStar";
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

	// 彈出測試結果提示框
	UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Test Completed"
                                                                   message:[NSString stringWithFormat:@"Log saved to /var/jb/RedStar/test_log.txt\n\nSummary:\n%@", logMessage]
                                                            preferredStyle:UIAlertControllerStyleAlert];
	UIAlertAction *okAction = [UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil];
	[alert addAction:okAction];
	[self presentViewController:alert animated:YES completion:nil];
}

@end
