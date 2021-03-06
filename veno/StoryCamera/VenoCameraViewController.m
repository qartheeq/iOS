//
//  WaterCameraViewController.m
//  wowo
//
//  Created by Donal on 13-8-20.
//  Copyright (c) 2013年 Donal. All rights reserved.
//

#import "VenoCameraViewController.h"
#import "AVCamCaptureManager.h"
#import "AVCamRecorder.h"
#import <AVFoundation/AVFoundation.h>
#import <AssetsLibrary/AssetsLibrary.h>
#import "AVCamUtilities.h"
#import "Tool.h"
#import "VenoPreviewViewController.h"
#import "ThumbnailViewController.h"

#define VideoDuration 6
#define VideoLimitDuration 2

@interface VenoCameraViewController () <AVCamCaptureManagerDelegate, UIGestureRecognizerDelegate, UIScrollViewDelegate, UIActionSheetDelegate, VenoPreviewViewControllerDelegate>
{
    UIView *menuView;
    UIView *videoLapView;
    UIButton *actionDoneButton;
    UIView *overlyView;
    AVCamCaptureManager *_captureManager;
    UIView *videoPreviewView;
    AVCaptureVideoPreviewLayer *captureVideoPreviewLayer;
    BOOL isVideoAction;
    UIView *touchView;
    //time
    NSTimer *levelTimer;
    float time;
    NSMutableArray *assetArray;
    NSMutableArray *clipTimeRanges;
    NSMutableArray *assetFilePathArray;
    
    BOOL _exporting;
    UIActivityIndicatorView *loadingIndicator;
}

- (CGPoint)convertToPointOfInterestFromViewCoordinates:(CGPoint)viewCoordinates;
- (void)tapToAutoFocus:(UIGestureRecognizer *)gestureRecognizer;
- (void)tapToContinouslyAutoFocus:(UIGestureRecognizer *)gestureRecognizer;
//- (void)updateButtonStates;

@end

@implementation VenoCameraViewController

-(void)doneAction
{
    if (assetArray.count <= 0 || [[_captureManager recorder] isRecording] || time <= VideoLimitDuration) {
        return;
    }
    [_captureManager.session stopRunning];
    [_captureManager setDelegate:nil];
    
    BOOL userHasSelectedClips = NO;
    for (AVURLAsset *clip in assetArray) {
        if (! [clip isKindOfClass:[NSNull class]]) {
            userHasSelectedClips = YES;
            break;
        }
    }
    
    // Synchronize changes with the editor.
    [self synchronizeWithEditor];
    if (_exporting) {
        return;
    }
    [self beginExport];
}

-(void)back
{
    if (assetFilePathArray.count > 0) {
        UIActionSheet *actionSheet = [[UIActionSheet alloc] initWithTitle:nil delegate:self cancelButtonTitle:@"Cancel" destructiveButtonTitle:@"Delete post" otherButtonTitles:nil, nil];
        [actionSheet showInView:self.view];
    }
    else
        [self dismissViewControllerAnimated:YES completion:nil];
}

-(void)setUI
{
    menuView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, screenframe.size.width, 44)];
    [menuView setBackgroundColor:[UIColor blackColor]];
    [self.view addSubview:menuView];
    
    videoLapView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 0, menuView.frame.size.height)];
    [videoLapView setBackgroundColor:[UIColor colorWithRed:0/255.0 green:190/255.0 blue:143/255.0 alpha:1.0]];
    [menuView addSubview:videoLapView];
    
    UIButton *actionCancelButton = [UIButton buttonWithType:UIButtonTypeCustom];
    [actionCancelButton setFrame:CGRectMake(0, 0, 44, 44)];
    [actionCancelButton setBackgroundImage:[UIImage imageNamed:@"ActionCancelDefault.png"] forState:UIControlStateNormal];
    [actionCancelButton setBackgroundImage:[UIImage imageNamed:@"ActionCancelPressed.png"] forState:UIControlStateHighlighted];
    [actionCancelButton addTarget:self action:@selector(back) forControlEvents:UIControlEventTouchUpInside];
    [menuView addSubview:actionCancelButton];
    
    actionDoneButton = [UIButton buttonWithType:UIButtonTypeCustom];
    [actionDoneButton setFrame:CGRectMake(screenframe.size.width-44, 0, 44, 44)];
    [actionDoneButton setBackgroundImage:[UIImage imageNamed:@"ActionDoneDisabled.png"] forState:UIControlStateDisabled];
    [actionDoneButton setBackgroundImage:[UIImage imageNamed:@"ActionDoneEnabled.png"] forState:UIControlStateNormal];
    [actionDoneButton setBackgroundImage:[UIImage imageNamed:@"ActionDonePressed.png"] forState:UIControlStateHighlighted];
    [actionDoneButton setEnabled:NO];
    [actionDoneButton addTarget:self action:@selector(doneAction) forControlEvents:UIControlEventTouchUpInside];
    [menuView addSubview:actionDoneButton];
    
    loadingIndicator = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhite];
    [loadingIndicator setFrame:CGRectMake(screenframe.size.width-35, 10, 25, 25)];
    loadingIndicator.hidden = YES;
    [menuView addSubview:loadingIndicator];
    
    videoPreviewView = [[UIView alloc] initWithFrame:CGRectMake(0, 44, screenframe.size.width, 320)];
    [videoPreviewView setBackgroundColor:[UIColor clearColor]];
    [self.view addSubview:videoPreviewView];
    
    overlyView = [[UIView alloc] initWithFrame:CGRectMake(0,  364, screenframe.size.width, screenframe.size.height - 366)];
    [overlyView setBackgroundColor:[UIColor blackColor]];
    [self.view addSubview:overlyView];
}

- (void)dealloc
{
	[_captureManager.session stopRunning];
    [_captureManager setDelegate:nil];
    for (NSString *tempFilePath in assetFilePathArray) {
        [Tool deleteVideoFile:tempFilePath];
    }
    [assetFilePathArray removeAllObjects];
    [assetArray removeAllObjects];
    [clipTimeRanges removeAllObjects];
    assetFilePathArray = nil;
    assetArray = nil;
    clipTimeRanges = nil;
    self.editor = nil;
    loadingIndicator = nil;
    actionDoneButton = nil;
    menuView = nil;
    videoLapView = nil;
    videoPreviewView = nil;
    overlyView = nil;
    levelTimer = nil;
    _captureManager = nil;
}

- (void)viewDidLoad
{
    self.editor = [[SimpleEditor alloc] init];
    _exporting = NO;
    assetFilePathArray = [[NSMutableArray alloc] init];
    assetArray = [NSMutableArray arrayWithCapacity:0];
    clipTimeRanges = [NSMutableArray arrayWithCapacity:0];
    [self setUI];
	if ( _captureManager == nil) {
		_captureManager = [[AVCamCaptureManager alloc] init];
		[_captureManager setDelegate:self];
        
		if ([_captureManager setupSession]) {
            // Create video preview layer and add it to the UI
			AVCaptureVideoPreviewLayer *newCaptureVideoPreviewLayer = [[AVCaptureVideoPreviewLayer alloc] initWithSession:[_captureManager session]];
			UIView *view = videoPreviewView;
			CALayer *viewLayer = [view layer];
			[viewLayer setMasksToBounds:YES];
			
			CGRect bounds = [view bounds];
			[newCaptureVideoPreviewLayer setFrame:bounds];
			            			
			[newCaptureVideoPreviewLayer setVideoGravity:AVLayerVideoGravityResizeAspectFill];
			
			[viewLayer insertSublayer:newCaptureVideoPreviewLayer below:[[viewLayer sublayers] objectAtIndex:0]];
			
			captureVideoPreviewLayer = newCaptureVideoPreviewLayer;
			
            // Start the session. This is done asychronously since -startRunning doesn't return until the session is running.
			dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
				[_captureManager.session startRunning];
			});
            // Add a single tap gesture to focus on the point tapped, then lock focus
			UITapGestureRecognizer *singleTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(tapToAutoFocus:)];
			[singleTap setDelegate:self];
			[singleTap setNumberOfTapsRequired:1];
			
            // Add a double tap gesture to reset the focus mode to continuous auto focus
			UITapGestureRecognizer *doubleTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(tapToContinouslyAutoFocus:)];
			[doubleTap setDelegate:self];
			[doubleTap setNumberOfTapsRequired:2];
			[singleTap requireGestureRecognizerToFail:doubleTap];
            
            touchView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 80, 80)];
            CALayer * layer = [touchView layer];
            layer.borderColor = [[UIColor colorWithRed:232/255.0 green:232/255.0 blue:232/255.0 alpha:1] CGColor];
            layer.borderWidth = 1.0f;
            touchView.clipsToBounds=TRUE;
            [touchView setHidden:YES];
            [view addSubview:touchView];
		}
	}
    
    [super viewDidLoad];
}

// Convert from view coordinates to camera coordinates, where {0,0} represents the top left of the picture area, and {1,1} represents
// the bottom right in landscape mode with the home button on the right.
- (CGPoint)convertToPointOfInterestFromViewCoordinates:(CGPoint)viewCoordinates
{
    CGPoint pointOfInterest = CGPointMake(.5f, .5f);
    CGSize frameSize = videoPreviewView.frame.size;
    
    //    if ([captureVideoPreviewLayer isMirrored]) {
    //        viewCoordinates.x = frameSize.width - viewCoordinates.x;
    //    }
    
    if ( [[captureVideoPreviewLayer videoGravity] isEqualToString:AVLayerVideoGravityResize] ) {
		// Scale, switch x and y, and reverse x
        pointOfInterest = CGPointMake(viewCoordinates.y / frameSize.height, 1.f - (viewCoordinates.x / frameSize.width));
    } else {
        CGRect cleanAperture;
        for (AVCaptureInputPort *port in [[_captureManager videoInput] ports]) {
            if ([port mediaType] == AVMediaTypeVideo) {
                cleanAperture = CMVideoFormatDescriptionGetCleanAperture([port formatDescription], YES);
                CGSize apertureSize = cleanAperture.size;
                CGPoint point = viewCoordinates;
                
                CGFloat apertureRatio = apertureSize.height / apertureSize.width;
                CGFloat viewRatio = frameSize.width / frameSize.height;
                CGFloat xc = .5f;
                CGFloat yc = .5f;
                
                if ( [[captureVideoPreviewLayer videoGravity] isEqualToString:AVLayerVideoGravityResizeAspect] ) {
                    if (viewRatio > apertureRatio) {
                        CGFloat y2 = frameSize.height;
                        CGFloat x2 = frameSize.height * apertureRatio;
                        CGFloat x1 = frameSize.width;
                        CGFloat blackBar = (x1 - x2) / 2;
						// If point is inside letterboxed area, do coordinate conversion; otherwise, don't change the default value returned (.5,.5)
                        if (point.x >= blackBar && point.x <= blackBar + x2) {
							// Scale (accounting for the letterboxing on the left and right of the video preview), switch x and y, and reverse x
                            xc = point.y / y2;
                            yc = 1.f - ((point.x - blackBar) / x2);
                        }
                    } else {
                        CGFloat y2 = frameSize.width / apertureRatio;
                        CGFloat y1 = frameSize.height;
                        CGFloat x2 = frameSize.width;
                        CGFloat blackBar = (y1 - y2) / 2;
						// If point is inside letterboxed area, do coordinate conversion. Otherwise, don't change the default value returned (.5,.5)
                        if (point.y >= blackBar && point.y <= blackBar + y2) {
							// Scale (accounting for the letterboxing on the top and bottom of the video preview), switch x and y, and reverse x
                            xc = ((point.y - blackBar) / y2);
                            yc = 1.f - (point.x / x2);
                        }
                    }
                } else if ([[captureVideoPreviewLayer videoGravity] isEqualToString:AVLayerVideoGravityResizeAspectFill]) {
					// Scale, switch x and y, and reverse x
                    if (viewRatio > apertureRatio) {
                        CGFloat y2 = apertureSize.width * (frameSize.width / apertureSize.height);
                        xc = (point.y + ((y2 - frameSize.height) / 2.f)) / y2; // Account for cropped height
                        yc = (frameSize.width - point.x) / frameSize.width;
                    } else {
                        CGFloat x2 = apertureSize.height * (frameSize.height / apertureSize.width);
                        yc = 1.f - ((point.x + ((x2 - frameSize.width) / 2)) / x2); // Account for cropped width
                        xc = point.y / frameSize.height;
                    }
                }
                
                pointOfInterest = CGPointMake(xc, yc);
                break;
            }
        }
    }
    
    return pointOfInterest;
}

-(void)hideTouchView
{
    touchView.hidden = YES;
}

// Auto focus at a particular point. The focus mode will change to locked once the auto focus happens.
- (void)tapToAutoFocus:(UIGestureRecognizer *)gestureRecognizer
{
    CGPoint tapPoint = [gestureRecognizer locationInView:videoPreviewView];
    
    [touchView setFrame:CGRectMake(tapPoint.x-40, tapPoint.y-40, 80, 80)];
    [touchView setHidden:NO];
    [self performSelector:@selector(hideTouchView) withObject:nil afterDelay:1];

    if ([[[_captureManager videoInput] device] isFocusPointOfInterestSupported]) {
        CGPoint convertedFocusPoint = [self convertToPointOfInterestFromViewCoordinates:tapPoint];
        [_captureManager autoFocusAtPoint:convertedFocusPoint];
    }
    if ([[[_captureManager videoInput] device] isExposurePointOfInterestSupported]) {
        CGPoint convertedFocusPoint = [self convertToPointOfInterestFromViewCoordinates:tapPoint];
        [_captureManager autoExposureAtPoint:convertedFocusPoint];
    }
    
}

// Change to continuous auto focus. The camera will constantly focus at the point choosen.
- (void)tapToContinouslyAutoFocus:(UIGestureRecognizer *)gestureRecognizer
{
    if ([[[_captureManager videoInput] device] isFocusPointOfInterestSupported])
        [_captureManager continuousFocusAtPoint:CGPointMake(.5f, .5f)];
    
    if ([[[_captureManager videoInput] device] isExposurePointOfInterestSupported])
        [_captureManager continuousExposureAtPoint:CGPointMake(.5f, .5f)];
    
}

#pragma mark 录制视频
-(void)updateTimer
{
    if (isVideoAction) {
        time += 0.03;
        CGRect videoLapRect = [videoLapView frame];
        videoLapRect.size.width = time * screenframe.size.width / VideoDuration;
        [videoLapView setFrame:videoLapRect];
        if (time >= VideoDuration) {
            [self videoRecordEnd];
            time = VideoDuration;
        }
    }
}

-(void)videoRecordEnd
{
    [levelTimer invalidate];
    [_captureManager stopRecording];
    if (time > VideoLimitDuration) {
        [actionDoneButton setEnabled:YES];
    }
    else{
        [actionDoneButton setEnabled:NO];
    }
}

-(void)touchesBegan:(NSSet *)touches withEvent:(UIEvent *)event
{
    [super touchesBegan:touches withEvent:event];
    if (event.allTouches.count > 1) {
        return;
    }
    UITouch *touch = [touches anyObject];
    CGPoint currentLocation = [touch locationInView:self.view];
    debugLog(@"%i",[[_captureManager recorder] isRecording]);
    if (currentLocation.y > (menuView.frame.origin.y+menuView.frame.size.height) && currentLocation.y < overlyView.frame.origin.y && !isVideoAction) {
        if ((![[_captureManager recorder] isRecording])  ) {
            [_captureManager startRecording];
            levelTimer = [NSTimer scheduledTimerWithTimeInterval: 0.03 target: self selector: @selector(updateTimer) userInfo:nil repeats: YES];
        }
        return;
    }
}

-(void)touchesMoved:(NSSet *)touches withEvent:(UIEvent *)event
{
    [super touchesMoved:touches withEvent:event];
    if (event.allTouches.count > 1) {
        return;
    }
    UITouch *touch = [touches anyObject];
    CGPoint currentLocation = [touch locationInView:self.view];
    
    if ((currentLocation.y < (menuView.frame.origin.y+menuView.frame.size.height) || currentLocation.y > overlyView.frame.origin.y) && isVideoAction) {
        if ([[_captureManager recorder] isRecording]) {
            [self videoRecordEnd];
        }
        return;
    }
}

-(void)touchesEnded:(NSSet *)touches withEvent:(UIEvent *)event
{
    [super touchesEnded:touches withEvent:event];
    if (event.allTouches.count > 1) {
        return;
    }
    UITouch *touch = [touches anyObject];
    CGPoint currentLocation = [touch locationInView:self.view];
    
    if (currentLocation.y > (menuView.frame.origin.y+menuView.frame.size.height) && currentLocation.y < overlyView.frame.origin.y && isVideoAction) {
        if ([[_captureManager recorder] isRecording]) {
            [self videoRecordEnd];
        }
        return;
    }
}


#pragma mark AvCamManagerDelegate
- (void)captureManager:(AVCamCaptureManager *)captureManager didFailWithError:(NSError *)error
{
    CFRunLoopPerformBlock(CFRunLoopGetMain(), kCFRunLoopCommonModes, ^(void) {
        UIAlertView *alertView = [[UIAlertView alloc] initWithTitle:[error localizedDescription]
                                                            message:[error localizedFailureReason]
                                                           delegate:nil
                                                  cancelButtonTitle:NSLocalizedString(@"OK", @"OK button title")
                                                  otherButtonTitles:nil];
        [alertView show];
    });
}

- (void)captureManagerRecordingBegan:(AVCamCaptureManager *)captureManager
{
    CFRunLoopPerformBlock(CFRunLoopGetMain(), kCFRunLoopCommonModes, ^(void) {
        isVideoAction = YES;
    });
}

- (void)captureManagerRecordingFinished:(AVCamCaptureManager *)captureManager withMov:(NSString *)path
{
    CFRunLoopPerformBlock(CFRunLoopGetMain(), kCFRunLoopCommonModes, ^(void) {
        isVideoAction = NO;
        if (path != nil) {
            [assetFilePathArray addObject:path];
            AVURLAsset *asset = [AVURLAsset URLAssetWithURL:[NSURL fileURLWithPath:path] options:nil];
            [assetArray addObject:asset];
            CMTimeRange timeRange = kCMTimeRangeZero;
            timeRange.duration = asset.duration;
            NSValue *timeRangeValue = [NSValue valueWithCMTimeRange:timeRange];
            [clipTimeRanges addObject:timeRangeValue];
        }
    });
}

- (void)captureManagerStillImageCaptured:(AVCamCaptureManager *)captureManager StillImage:(UIImage *)image
{
    CFRunLoopPerformBlock(CFRunLoopGetMain(), kCFRunLoopCommonModes, ^(void) {
    });
}

- (void)captureManagerDeviceConfigurationChanged:(AVCamCaptureManager *)captureManager
{
    
}

- (void) captureManagerDeviceOrientationChanged:(AVCamCaptureManager *)captureManager withOrientation:(UIDeviceOrientation)orientation
{
//    if (orientation == UIDeviceOrientationPortrait) {
//        [UIView beginAnimations:nil context:nil];
//        [UIView setAnimationDuration:ViewRotationDuration];
//        [UIView setAnimationDelegate:self];
//        recordButton.transform=CGAffineTransformIdentity;
//        recordButton.transform=CGAffineTransformMakeRotation(2*M_PI);
//        [UIView commitAnimations];
//        
//        [UIView beginAnimations:nil context:nil];
//        [UIView setAnimationDuration:ViewRotationDuration];
//        [UIView setAnimationDelegate:self];
//        changeCameraButton.transform=CGAffineTransformIdentity;
//        changeCameraButton.transform=CGAffineTransformMakeRotation(2*M_PI);
//        [UIView commitAnimations];
//    }
//	else if (orientation == UIDeviceOrientationPortraitUpsideDown) {
//        [UIView beginAnimations:nil context:nil];
//        [UIView setAnimationDuration:ViewRotationDuration];
//        [UIView setAnimationDelegate:self];
//        recordButton.transform=CGAffineTransformIdentity;
//        recordButton.transform=CGAffineTransformMakeRotation(-M_PI);
//        [UIView commitAnimations];
//        
//        [UIView beginAnimations:nil context:nil];
//        [UIView setAnimationDuration:ViewRotationDuration];
//        [UIView setAnimationDelegate:self];
//        changeCameraButton.transform=CGAffineTransformIdentity;
//        changeCameraButton.transform=CGAffineTransformMakeRotation(-M_PI);
//        [UIView commitAnimations];
//    }
//	else if (orientation == UIDeviceOrientationLandscapeLeft) {
//        [UIView beginAnimations:nil context:nil];
//        [UIView setAnimationDuration:ViewRotationDuration];
//        [UIView setAnimationDelegate:self];
//        recordButton.transform=CGAffineTransformIdentity;
//        recordButton.transform=CGAffineTransformMakeRotation(M_PI/2.0);
//        [UIView commitAnimations];
//        
//        [UIView beginAnimations:nil context:nil];
//        [UIView setAnimationDuration:ViewRotationDuration];
//        [UIView setAnimationDelegate:self];
//        changeCameraButton.transform=CGAffineTransformIdentity;
//        changeCameraButton.transform=CGAffineTransformMakeRotation(M_PI/2.0);
//        [UIView commitAnimations];
//        
//    }
//	else if (orientation == UIDeviceOrientationLandscapeRight) {
//        [UIView beginAnimations:nil context:nil];
//        [UIView setAnimationDuration:ViewRotationDuration];
//        [UIView setAnimationDelegate:self];
//        recordButton.transform=CGAffineTransformIdentity;
//        recordButton.transform=CGAffineTransformMakeRotation(-M_PI/2.0);
//        [UIView commitAnimations];
//        
//        [UIView beginAnimations:nil context:nil];
//        [UIView setAnimationDuration:ViewRotationDuration];
//        [UIView setAnimationDelegate:self];
//        changeCameraButton.transform=CGAffineTransformIdentity;
//        changeCameraButton.transform=CGAffineTransformMakeRotation(-M_PI/2.0);
//        [UIView commitAnimations];
//        
//    }
}

#pragma mark action sheet delegate
-(void)actionSheet:(UIActionSheet *)actionSheet clickedButtonAtIndex:(NSInteger)buttonIndex
{
    if (buttonIndex == 0) {
        [self dismissViewControllerAnimated:YES completion:nil];
    }
}

#pragma mark -
#pragma mark Editor Sync

- (void)synchronizeEditorClipsWithOurClips
{
	NSMutableArray *validClips = [NSMutableArray arrayWithCapacity:0];
	for (AVURLAsset *asset in assetArray) {
		if (! [asset isKindOfClass:[NSNull class]]) {
			[validClips addObject:asset];
		}
	}
	self.editor.clips = validClips;
}

- (void)synchronizeEditorClipTimeRangesWithOurClipTimeRanges
{
	NSMutableArray *validClipTimeRanges = [NSMutableArray arrayWithCapacity:3];
	for (NSValue *timeRange in clipTimeRanges) {
		if (! [timeRange isKindOfClass:[NSNull class]]) {
			[validClipTimeRanges addObject:timeRange];
		}
	}
	self.editor.clipTimeRanges = [validClipTimeRanges copy] ;
}

- (void)synchronizeWithEditor
{
	// Clips
	[self synchronizeEditorClipsWithOurClips];
	[self synchronizeEditorClipTimeRangesWithOurClipTimeRanges];
	
	// Commentary
	self.editor.commentary =  nil;
	CMTime commentaryStartTime = CMTimeMakeWithSeconds(0.0, 600);
	self.editor.commentaryStartTime = commentaryStartTime;
	
	// Transitions
	CMTime transitionDuration = CMTimeMakeWithSeconds(1.0, 600) ;
	self.editor.transitionDuration = transitionDuration;
	self.editor.transitionType = SimpleEditorTransitionTypeNone;
}

#pragma mark -
#pragma mark Export

- (void)beginExport
{
    actionDoneButton.alpha = 0.0;
    [loadingIndicator startAnimating];
    [loadingIndicator setHidden:NO];
    isVideoAction = YES;
	_exporting = YES;
	[self.editor buildCompositionObjectsForPlayback:NO];
	AVAssetExportSession *session = [self.editor assetExportSessionWithPreset:AVAssetExportPresetHighestQuality];
    
	NSString *filePath = nil;
	NSUInteger count = 0;
	do {
		filePath = NSTemporaryDirectory();
		
		NSString *numberString = count > 0 ? [NSString stringWithFormat:@"-%i", count] : @"";
		filePath = [filePath stringByAppendingPathComponent:[NSString stringWithFormat:@"Output-%@.mp4", numberString]];
		count++;
	} while([[NSFileManager defaultManager] fileExistsAtPath:filePath]);
	
	session.outputURL = [NSURL fileURLWithPath:filePath];
	session.outputFileType = AVFileTypeMPEG4;
	[session exportAsynchronouslyWithCompletionHandler:^
     {
         dispatch_async(dispatch_get_main_queue(), ^{
             debugLog(@"%@",filePath);
             [self exportDidFinish:session atPath:filePath];
         });
     }];
//    ThumbnailViewController *thumbnailController = [[ThumbnailViewController alloc] initWithEditor:self.editor] ;
//   [self presentViewController:thumbnailController animated:YES completion:nil];
}

- (void)exportDidFinish:(AVAssetExportSession *)session atPath:(NSString *)filePath
{
	_exporting = NO;
    actionDoneButton.alpha = 1.0;
    [loadingIndicator stopAnimating];
    [loadingIndicator setHidden:YES];
	debugLog(@"ex");
    [captureVideoPreviewLayer setHidden:YES];
    VenoPreviewViewController *vc = [[VenoPreviewViewController alloc] init];
    [vc setVideoFilePath:filePath];
    [vc setDelegate:self];
    [self presentViewController:vc animated:YES completion:nil];
}

#pragma mark VenoPreviewViewController delegate
-(void)publishVideo:(NSString *)filePath
{
    [self.presentedViewController dismissViewControllerAnimated:NO completion:nil];
    [self dismissViewControllerAnimated:NO completion:nil];
    [self.delegate publishVideo:filePath];
}

-(void)cancelPublishAndDeleteVideo
{
    [self.presentedViewController dismissViewControllerAnimated:NO completion:nil];
    [self dismissViewControllerAnimated:NO completion:nil];
}

@end
