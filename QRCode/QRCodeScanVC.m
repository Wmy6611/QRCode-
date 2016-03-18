//
//  QRCodeScanVC.m
//  QRCode
//
//  Created by Wmy on 16/3/18.
//  Copyright © 2016年 Wmy. All rights reserved.
//

#import "QRCodeScanVC.h"
#import <AVFoundation/AVFoundation.h>

#define Dev_ScreenWidth     [UIScreen mainScreen].bounds.size.width
#define Dev_ScreenHeight    [UIScreen mainScreen].bounds.size.height

#define kRecordMargeLeading (0.15 * Dev_ScreenWidth)
#define kRecordMargeTop     124.0f
#define kRecordSideLength   (Dev_ScreenWidth - 2*kRecordMargeLeading)
#define kRecordFrame        CGRectMake(kRecordMargeLeading, kRecordMargeTop, kRecordSideLength,  kRecordSideLength)


@interface QRCodeScanVC () <AVCaptureMetadataOutputObjectsDelegate, UIAlertViewDelegate>
{
    BOOL _canScan;   // 处理完上一次的扫描结果才能处理新的扫描数据  YES:可接收新的扫描数据
}
@property (nonatomic, strong) CADisplayLink *link;
@property (nonatomic, strong) AVCaptureDevice *device;
@property (nonatomic, strong) AVCaptureSession *session;
@property (nonatomic, strong) UIImageView *lineImageView;
@end

@implementation QRCodeScanVC

#pragma mark - life cycle

- (void)viewDidDisappear:(BOOL)animated {
    if (_link) {
        [_link removeFromRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
        [_link invalidate];
        _link = nil;
    }
    _session = nil;
    _device = nil;
    [super viewDidDisappear:animated];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor whiteColor];
    
    _canScan = YES;
    [self startScan];
    [self UIConfigure];
}


#pragma mark - 开始二维码扫描
/**
 *  检测设备是否支持
 */
- (void)startScan{
    if (![self startReading])
    {
        UIAlertView *alert = [[UIAlertView alloc]initWithTitle:@"提示"
                                                       message:@"该设备硬件不支持，或用户禁用了相机（请到设置里启用相机）"
                                                      delegate:self
                                             cancelButtonTitle:@"OK"
                                             otherButtonTitles:nil,nil];
        [alert setTag:1001];
        [alert show];
    }
}

/**
 *  初始化扫描
 */
- (BOOL)startReading {
    
    // Device
    self.device = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
    
    // Input
    NSError *error;
    AVCaptureDeviceInput *input = [AVCaptureDeviceInput deviceInputWithDevice:_device error:&error];
    if (!input) {
        NSLog(@"%@", [error localizedDescription]);
        return NO;
    }
    
    // Output
    AVCaptureMetadataOutput *output = [[AVCaptureMetadataOutput alloc] init];
    [output setMetadataObjectsDelegate:self queue:dispatch_get_main_queue()];
    
    // Session
    self.session = [[AVCaptureSession alloc] init];
    [_session setSessionPreset:AVCaptureSessionPresetHigh];
    if ([_session canAddInput:input])
        [_session addInput:input];
    if ([_session canAddOutput:output])
        [_session addOutput:output];
    
    // 扫码类型
    output.metadataObjectTypes = @[AVMetadataObjectTypeQRCode];
    
    // Preview
    AVCaptureVideoPreviewLayer *preview = [AVCaptureVideoPreviewLayer layerWithSession:_session];
    preview.videoGravity = AVLayerVideoGravityResizeAspectFill;
    preview.frame = self.view.bounds;
    [self.view.layer addSublayer:preview];
    
    [output setRectOfInterest:CGRectMake((kRecordMargeTop)/Dev_ScreenHeight,
                                         (kRecordMargeLeading)/Dev_ScreenWidth,
                                         kRecordSideLength/Dev_ScreenHeight,
                                         kRecordSideLength/Dev_ScreenWidth)];
    // Start
    [_session startRunning];
    
    return YES;
}

#pragma mark - AVCaptureMetadataOutputObjectsDelegate

- (void)captureOutput:(AVCaptureOutput *)captureOutput didOutputMetadataObjects:(NSArray *)metadataObjects fromConnection:(AVCaptureConnection *)connection {
    
    if (!_canScan)   return;
    _canScan = NO;
    
    if (metadataObjects != nil && [metadataObjects count] > 0)
    {
        AVMetadataMachineReadableCodeObject *metadataObj = [metadataObjects objectAtIndex:0];
        NSString *result;
        if ([[metadataObj type] isEqualToString:AVMetadataObjectTypeQRCode]) {
            result = metadataObj.stringValue;
        } else {
            NSLog(@"不是二维码");
        }
        [self performSelectorOnMainThread:@selector(reportScanResult:) withObject:result waitUntilDone:NO];
    }
}

/**
 *  处理结果
 */
- (void)reportScanResult:(NSString *)result {
    
    if ([result hasPrefix:@"http://"] || [result hasPrefix:@"https://"]) {
        // 链接
        UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"是否打开链接？"
                                                        message:result
                                                       delegate:self
                                              cancelButtonTitle:@"取消"
                                              otherButtonTitles:@"打开", nil];
        [alert setTag:1002];
        [alert show];
    }else {
        // 非链接
        UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"扫描结果"
                                                        message:result
                                                       delegate:self
                                              cancelButtonTitle:@"关闭"
                                              otherButtonTitles:nil, nil];
        [alert setTag:1003];
        [alert show];
        
    }
    
}

#pragma mark - UIAlertViewDelegate

- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex {
    if (alertView.tag == 1001) {
        // 设备不支持，退出扫描界面
        [self.navigationController popViewControllerAnimated:YES];
    }
    else if (alertView.tag == 1002 || alertView.tag == 1003)
    {
        if(buttonIndex == 1)
            [[UIApplication sharedApplication] openURL:[NSURL URLWithString:alertView.message]];
        
        [self performSelector:@selector(restart) withObject:nil afterDelay:0.8];
    }
}

- (void)restart {
    _canScan = YES;
    [_session startRunning];
}

#pragma mark - tool bar response
/**
 *  打开关闭闪光灯
 */
- (void)systemTorchChangeMode {
    
    // 判断摄像头是否提供闪光灯
    if ([self.device hasTorch]) {
        // 呼叫硬件以控制硬件
        [_device lockForConfiguration:nil];
        if (_device.torchActive) {
            [_device setTorchMode:AVCaptureTorchModeOff];
        } else {
            [_device setTorchMode:AVCaptureTorchModeOn];
        }
        // 控制完毕
        [_device unlockForConfiguration];
    }
}

/**
 *  toolbarAction
 */
- (void)toolbarAction:(id)sender {
    
    UIButton *btn = (UIButton *)sender;
    switch (btn.tag) {
        case 101: // 相册
            NSLog(@"相册");
            
            break;
            
        case 102: // 手电筒
            [self systemTorchChangeMode];
            break;
            
        case 103: // 我的二维码
            NSLog(@"我的二维码");
            
            break;
            
        default:
            break;
    }
}

#pragma mark -
/**
 *  开始扫描线动画
 */
- (void)startAnimation {
    
    CGRect rect = _lineImageView.frame;
    rect.origin.y += 2;
    _lineImageView.frame = rect;
    
    if (rect.origin.y + rect.size.height >= kRecordMargeTop + kRecordSideLength) {
        rect.origin.y = kRecordMargeTop;
        _lineImageView.frame = rect;
    }
}

#pragma mark - UIConfigure

- (void)UIConfigure {
    
    [self createCoverView];
    [self createRecordSideImage];
    [self.view addSubview:self.lineImageView];
    [self createToolbar];
    
    _link = [CADisplayLink displayLinkWithTarget:self selector:@selector(startAnimation)];
    [_link addToRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
}

- (void)createToolbar {
    
    UIImage *image = [UIImage imageNamed:@"QRCode_toolBar"];
    CGSize size = image.size;
    
    CGFloat imageViewH = size.height * Dev_ScreenWidth / size.width;
    CGFloat imageViewY = self.view.bounds.size.height - imageViewH;
    CGRect rect = CGRectMake(0, imageViewY, Dev_ScreenWidth, imageViewH);
    
    UIImageView *imageView = [[UIImageView alloc] initWithImage:image];
    [imageView setFrame:rect];
    [imageView setUserInteractionEnabled:YES];
    [imageView setAlpha:0.6];
    [self.view addSubview:imageView];
    
    
    CGFloat btnW = Dev_ScreenWidth / 3;
    CGFloat btnH = imageViewH;
    for (int i = 0; i<3; i++) {
        CGFloat btnX = i * btnW;
        UIButton *btn = [UIButton buttonWithType:UIButtonTypeCustom];
        [btn setFrame:CGRectMake(btnX, 0, btnW, btnH)];
        [btn setBackgroundColor:[UIColor clearColor]];
        [btn setTag:101+i];
        [btn addTarget:self action:@selector(toolbarAction:) forControlEvents:UIControlEventTouchUpInside];
        [imageView addSubview:btn];
    }
}

- (UIImageView *)lineImageView {
    if (!_lineImageView) {
        CGRect rect = kRecordFrame;
        rect.size.height = 2;
        UIImageView *imageView = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"QRCode_scanline"]];
        imageView.frame = rect;
        _lineImageView = imageView;
    }
    return _lineImageView;
}

- (void)createRecordSideImage {
    
    UIImage *image = [UIImage imageNamed:@"QRCode_pick"];
    image = [image stretchableImageWithLeftCapWidth:floorf(image.size.width/2)
                                       topCapHeight:floorf(image.size.height/2)];
    
    UIImageView *imageView = [[UIImageView alloc] initWithImage:image];
    imageView.frame = CGRectMake(kRecordMargeLeading-10, kRecordMargeTop-10, kRecordSideLength+20,  kRecordSideLength+20);
    [self.view addSubview:imageView];
}

- (void)createCoverView {
    
    UIView *view = [[UIView alloc] initWithFrame:self.view.bounds];
    [view setBackgroundColor:[[UIColor blackColor] colorWithAlphaComponent:0.3]];
    [self.view addSubview:view];
    
    UIBezierPath *path = [UIBezierPath bezierPathWithRect:CGRectMake(0, 0, Dev_ScreenWidth, Dev_ScreenHeight)];
    [path appendPath:[[UIBezierPath bezierPathWithRoundedRect:kRecordFrame cornerRadius:0] bezierPathByReversingPath]];
    
    CAShapeLayer *shapeLayer = [CAShapeLayer layer];
    shapeLayer.path = path.CGPath;
    
    [view.layer setMask:shapeLayer];
    
}

@end
