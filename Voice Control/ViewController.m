//
//  ViewController.m
//  Voice Control
//
//  Created by Martin Michelini on 6/9/16.
//  Copyright © 2016 Martin Michelini. All rights reserved.
//

#import "ViewController.h"
#import "BLE.h"

@interface ViewController () <BLEDelegate>

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
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
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
    
    UInt8 buf[3] = {0x01, 0x00, 0x00};
    
    if (self.lightSwitch) {
        buf[1] = 0x01;
        self.btnLight.backgroundColor = [UIColor greenColor];
    }
    else
    {
        buf[1] = 0x00;
        self.btnLight.backgroundColor = [UIColor lightGrayColor];
    }
    NSData *data = [[NSData alloc] initWithBytes:buf length:3];
    [ble write:data];
}


@end
