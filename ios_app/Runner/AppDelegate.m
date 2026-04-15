#import "AppDelegate.h"

@implementation AppDelegate

- (BOOL)application:(UIApplication *)application
    didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
  BOOL didFinish = [super application:application didFinishLaunchingWithOptions:launchOptions];

  Class bootstrapClass = NSClassFromString(@"OmnibotFlutterBootstrap");
  if (bootstrapClass && [bootstrapClass respondsToSelector:@selector(warmUp)]) {
    [bootstrapClass performSelector:@selector(warmUp)];
  }

  Class hostingControllerClass = NSClassFromString(@"OmnibotHostingController");
  UIViewController *rootViewController = nil;
  if (hostingControllerClass) {
    rootViewController = [[hostingControllerClass alloc] init];
  }
  if (rootViewController == nil) {
    rootViewController = [UIViewController new];
    rootViewController.view.backgroundColor = [UIColor systemBackgroundColor];
  }

  self.window = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
  self.window.backgroundColor = [UIColor systemBackgroundColor];
  self.window.rootViewController = rootViewController;
  [self.window makeKeyAndVisible];
  return didFinish;
}

@end
