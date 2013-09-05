//
//  AppDelegate.m
//  veno
//
//  Created by Donal on 13-9-2.
//  Copyright (c) 2013年 vikaa. All rights reserved.
//

#import "AppDelegate.h"
#import "VenoCameraViewController.h"

@implementation AppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions
{
    self.window = [[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]] ;
    [self AppBeginCreat];
    VenoCameraViewController *vc = [[VenoCameraViewController alloc] init];
    UINavigationController *navCtrl = [[UINavigationController alloc] initWithRootViewController:vc];
    self.window.rootViewController = navCtrl;
    [navCtrl setNavigationBarHidden:YES];
    [self.window makeKeyAndVisible];
    return YES;
}

-(void)AppBeginCreat
{
    NSFileManager * fileManager = [NSFileManager defaultManager];
    if ([fileManager fileExistsAtPath:[self getDataFilePathWithName:@"video"]] == NO)
        [fileManager createDirectoryAtPath:[self getDataFilePathWithName:@"video"] withIntermediateDirectories:YES attributes:nil error:nil];
    if ([fileManager fileExistsAtPath:[self getDataFilePathWithName:@"CompressedPhoto"]] == NO)
        [fileManager createDirectoryAtPath:[self getDataFilePathWithName:@"CompressedPhoto"] withIntermediateDirectories:YES attributes:nil error:nil];
    if ([fileManager fileExistsAtPath:[self getDataFilePathWithName:@"JsonData"]] == NO) {
        [fileManager createDirectoryAtPath:[self getDataFilePathWithName:@"JsonData"] withIntermediateDirectories:YES attributes:nil error:nil];
    }
}

-(NSString*)getDataFilePathWithName:(NSString*)name
{
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *documentsDirectory = [paths objectAtIndex:0];
    NSString *path = [documentsDirectory stringByAppendingPathComponent:name];
    return path;
}

- (void)applicationWillResignActive:(UIApplication *)application
{
    // Sent when the application is about to move from active to inactive state. This can occur for certain types of temporary interruptions (such as an incoming phone call or SMS message) or when the user quits the application and it begins the transition to the background state.
    // Use this method to pause ongoing tasks, disable timers, and throttle down OpenGL ES frame rates. Games should use this method to pause the game.
}

- (void)applicationDidEnterBackground:(UIApplication *)application
{
    // Use this method to release shared resources, save user data, invalidate timers, and store enough application state information to restore your application to its current state in case it is terminated later. 
    // If your application supports background execution, this method is called instead of applicationWillTerminate: when the user quits.
}

- (void)applicationWillEnterForeground:(UIApplication *)application
{
    // Called as part of the transition from the background to the inactive state; here you can undo many of the changes made on entering the background.
}

- (void)applicationDidBecomeActive:(UIApplication *)application
{
    // Restart any tasks that were paused (or not yet started) while the application was inactive. If the application was previously in the background, optionally refresh the user interface.
}

- (void)applicationWillTerminate:(UIApplication *)application
{
    // Called when the application is about to terminate. Save data if appropriate. See also applicationDidEnterBackground:.
}

@end
