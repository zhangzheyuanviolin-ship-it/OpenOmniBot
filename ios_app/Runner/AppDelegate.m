#import "AppDelegate.h"
@implementation AppDelegate

- (BOOL)application:(UIApplication *)application
    didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
  BOOL didFinish = [super application:application didFinishLaunchingWithOptions:launchOptions];

  Class bootstrapClass = NSClassFromString(@"OmnibotFlutterBootstrap");
  if (bootstrapClass && [bootstrapClass respondsToSelector:@selector(warmUp)]) {
    [bootstrapClass performSelector:@selector(warmUp)];
  }

  UIViewController *rootViewController = nil;
  Class hostingBridgeClass = NSClassFromString(@"OmnibotHostingBridge");
  SEL makeRootSelector = NSSelectorFromString(@"makeRootViewController");
  if (hostingBridgeClass && [hostingBridgeClass respondsToSelector:makeRootSelector]) {
    IMP implementation = [hostingBridgeClass methodForSelector:makeRootSelector];
    UIViewController *(*factory)(id, SEL) = (void *)implementation;
    rootViewController = factory(hostingBridgeClass, makeRootSelector);
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
