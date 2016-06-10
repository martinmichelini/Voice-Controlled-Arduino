//
//  ViewController.m
//  Voice Control
//
//  Created by Martin Michelini on 6/9/16.
//  Copyright © 2016 Martin Michelini. All rights reserved.
//

#import "ViewController.h"
#import "BLE.h"
#import <SpeechKit/SpeechKit.h>

// State Logic: IDLE -> LISTENING -> PROCESSING -> repeat
enum {
    SKSIdle = 1,
    SKSListening = 2,
    SKSProcessing = 3
};
typedef NSUInteger SKSState;

@interface ViewController () <BLEDelegate, SKTransactionDelegate> {
    SKSession* _skSession;
    SKTransaction* _skTransaction;
    SKSState _state;
    NSTimer *_volumePollTimer;
}

@property (strong, nonatomic) BLE *ble;

@property (weak, nonatomic) IBOutlet UIButton *btnConnect;
@property (weak, nonatomic) IBOutlet UIButton *btnLight;
@property (weak, nonatomic) IBOutlet UIActivityIndicatorView *indConnecting;
@property (weak, nonatomic) IBOutlet UILabel *lblRSSI;
@property (nonatomic) BOOL lightSwitch;

@end

@implementation ViewController

@synthesize ble;


- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view, typically from a nib.
    
    ble = [[BLE alloc] init];
    [ble controlSetup];
    ble.delegate = self;
    
    self.lightSwitch = YES;
    self.btnLight.backgroundColor = [UIColor lightGrayColor];
    
    [self setUpSpeechRecognition];
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

- (void)setUpSpeechRecognition {
    UIButton* button = [UIButton buttonWithType:UIButtonTypeRoundedRect];
    [button setTitle:@"Start ASR" forState:UIControlStateNormal];
    [button addTarget:self action:@selector(toggleRecognition) forControlEvents:UIControlEventTouchUpInside];
    [button sizeToFit];
    button.center = self.view.center;
    [self.view addSubview:button];
    _state = SKSIdle;
    _skTransaction = nil;
    _skSession = [[SKSession alloc] initWithFabric];
    [self loadEarcons];
}

#pragma mark - ASR Actions

- (void)toggleRecognition
{
    switch (_state) {
        case SKSIdle:
            [self recognize];
            break;
        case SKSListening:
            [self stopRecording];
            break;
        case SKSProcessing:
            [self cancel];
            break;
        default:
            break;
    }
}

- (void)recognize
{
    // Start listening to the user.
    _skTransaction = [_skSession recognizeWithType:SKTransactionSpeechTypeDictation
                                         detection:SKTransactionEndOfSpeechDetectionShort
                                          language:@"eng-USA"
                                          delegate:self];
}

- (void)stopRecording
{
    // Stop recording the user.
    [_skTransaction stopRecording];
}

- (void)cancel
{
    // Cancel the Reco transaction.
    // This will only cancel if we have not received a response from the server yet.
    [_skTransaction cancel];
}

# pragma mark - SKTransactionDelegate

- (void)transactionDidBeginRecording:(SKTransaction *)transaction
{
    NSLog(@"transactionDidBeginRecording");
    _state = SKSListening;
    [self startPollingVolume];
}

- (void)transactionDidFinishRecording:(SKTransaction *)transaction
{
    NSLog(@"transactionDidFinishRecording");
    _state = SKSProcessing;
    [self stopPollingVolume];
}

- (void)transaction:(SKTransaction *)transaction didReceiveRecognition:(SKRecognition *)recognition
{
    NSLog(@"didReceiveRecognition: %@", recognition.text);
    NSString *command = [recognition.text lowercaseString];
    
    NSLog(@"Command: %@", command);
    
    if ([command containsString:@"light on"]) {
        [self lightOn];
    } else if ([command containsString:@"light off"]) {
        [self lighfOff];
    }
    
    _state = SKSIdle;
}

- (void)transaction:(SKTransaction *)transaction didReceiveServiceResponse:(NSDictionary *)response
{
    NSLog(@"didReceiveServiceResponse: %@", response);
}

- (void)transaction:(SKTransaction *)transaction didFinishWithSuggestion:(NSString *)suggestion
{
    NSLog(@"didFinishWithSuggestion");
    _state = SKSIdle;
    _skTransaction = nil;
}

- (void)transaction:(SKTransaction *)transaction didFailWithError:(NSError *)error suggestion:(NSString *)suggestion
{
    NSLog(@"didFailWithError: %@. %@", [error description], suggestion);
    // Something went wrong. Ensure that your credentials are correct.
    // The user could also be offline, so be sure to handle this case appropriately.
    _state = SKSIdle;
    _skTransaction = nil;
}

# pragma mark - Volume level

- (void)startPollingVolume
{
    // Every 50 milliseconds we should update the volume meter in our UI.
    _volumePollTimer = [NSTimer scheduledTimerWithTimeInterval:0.05
                                                        target:self
                                                      selector:@selector(pollVolume)
                                                      userInfo:nil repeats:YES];
}

- (void) pollVolume
{
    float volumeLevel = [_skTransaction audioLevel];
    NSLog(@"%.2f", volumeLevel);
}

- (void) stopPollingVolume
{
    [_volumePollTimer invalidate];
    _volumePollTimer = nil;
}

# pragma mark - Earcons

/*!
 We strongly recommend adding earcons (a brief sound that acts as a signal to
 convey system information) to your application.
 Earcons must be encoded in PCM 16K.
 */
- (void)loadEarcons
{
    NSString* startEarconPath = [[NSBundle mainBundle] pathForResource:@"sk_start" ofType:@"pcm"];
    NSString* stopEarconPath = [[NSBundle mainBundle] pathForResource:@"sk_stop" ofType:@"pcm"];
    NSString* errorEarconPath = [[NSBundle mainBundle] pathForResource:@"sk_stop" ofType:@"pcm"];
    NSString* cancelEarconPath = [[NSBundle mainBundle] pathForResource:@"sk_stop" ofType:@"pcm"];
    
    SKPCMFormat* audioFormat = [[SKPCMFormat alloc] init];
    audioFormat.sampleFormat = SKPCMSampleFormatSignedLinear16;
    audioFormat.sampleRate = 16000;
    audioFormat.channels = 1;
    
    _skSession.startEarcon = [[SKAudioFile alloc] initWithURL:[NSURL fileURLWithPath:startEarconPath] pcmFormat:audioFormat];
    _skSession.endEarcon = [[SKAudioFile alloc] initWithURL:[NSURL fileURLWithPath:stopEarconPath] pcmFormat:audioFormat];
    _skSession.errorEarcon = [[SKAudioFile alloc] initWithURL:[NSURL fileURLWithPath:errorEarconPath] pcmFormat:audioFormat];
    _skSession.cancelEarcon = [[SKAudioFile alloc] initWithURL:[NSURL fileURLWithPath:cancelEarconPath] pcmFormat:audioFormat];
}

#pragma mark - BLE delegate

NSTimer *rssiTimer;

- (void)bleDidDisconnect {
    NSLog(@"->Disconnected");
    
    [self.btnConnect setTitle:@"Connect" forState:UIControlStateNormal];
    [self.indConnecting stopAnimating];
    
    self.lblRSSI.text = @"---";
    
    [rssiTimer invalidate];
}

// When RSSI is changed, this will be called
-(void) bleDidUpdateRSSI:(NSNumber *) rssi {
    self.lblRSSI.text = rssi.stringValue;
}

-(void) readRSSITimer:(NSTimer *)timer {
    [ble readRSSI];
}

// When disconnected, this will be called
-(void) bleDidConnect {
    NSLog(@"->Connected");
    
    [self.indConnecting stopAnimating];
    
    self.lightSwitch = NO;
    
    // send reset
    UInt8 buf[] = {0x04, 0x00, 0x00};
    NSData *data = [[NSData alloc] initWithBytes:buf length:3];
    [ble write:data];
    
    // Schedule to read RSSI every 1 sec.
    rssiTimer = [NSTimer scheduledTimerWithTimeInterval:(float)1.0 target:self selector:@selector(readRSSITimer:) userInfo:nil repeats:YES];
}

// When data is comming, this will be called
-(void) bleDidReceiveData:(unsigned char *)data length:(int)length {
    NSLog(@"Length: %d", length);
    
    // parse data, all commands are in 3-byte
    for (int i = 0; i < length; i+=3)
    {
        NSLog(@"0x%02X, 0x%02X, 0x%02X", data[i], data[i+1], data[i+2]);
        
        if (data[i] == 0x0A)
        {
            //            if (data[i+1] == 0x01)
            //                swDigitalIn.on = true;
            //            else
            //                swDigitalIn.on = false;
        }
        else if (data[i] == 0x0B)
        {
            UInt16 Value;
            
            Value = data[i+2] | data[i+1] << 8;
            //            lblAnalogIn.text = [NSString stringWithFormat:@"%d", Value];
        }
    }
}

#pragma mark - Actions

// Connect button will call to this
- (IBAction)btnScanForPeripherals:(id)sender {
    if (ble.activePeripheral)
        if(ble.activePeripheral.state == CBPeripheralStateConnected)
        {
            [[ble CM] cancelPeripheralConnection:[ble activePeripheral]];
            [self.btnConnect setTitle:@"Connect" forState:UIControlStateNormal];
            return;
        }
    
    if (ble.peripherals)
        ble.peripherals = nil;
    
    [self.btnConnect setEnabled:false];
    [ble findBLEPeripherals:2];
    
    [NSTimer scheduledTimerWithTimeInterval:(float)2.0 target:self selector:@selector(connectionTimer:) userInfo:nil repeats:NO];
    
    [self.indConnecting startAnimating];
}

-(void) connectionTimer:(NSTimer *)timer{
    [self.btnConnect setEnabled:true];
    [self.btnConnect setTitle:@"Disconnect" forState:UIControlStateNormal];
    
    if (ble.peripherals.count > 0)
    {
        [ble connectPeripheral:[ble.peripherals objectAtIndex:0]];
    }
    else
    {
        [self.btnConnect setTitle:@"Connect" forState:UIControlStateNormal];
        [self.indConnecting stopAnimating];
    }
}

- (IBAction)turnLightOn:(UIButton *)sender {
    self.lightSwitch =! self.lightSwitch;
    
    if (self.lightSwitch) {
        [self lightOn];
    }
    else
    {
        [self lighfOff];
    }
}

- (void)lightOn {
    UInt8 buf[3] = {0x01, 0x00, 0x00};
    
    buf[1] = 0x01;
    self.btnLight.backgroundColor = [UIColor greenColor];
    
    NSData *data = [[NSData alloc] initWithBytes:buf length:3];
    [ble write:data];
}

- (void)lighfOff {
    UInt8 buf[3] = {0x01, 0x00, 0x00};
    
    buf[1] = 0x00;
    self.btnLight.backgroundColor = [UIColor lightGrayColor];
    
    NSData *data = [[NSData alloc] initWithBytes:buf length:3];
    [ble write:data];
}

@end
