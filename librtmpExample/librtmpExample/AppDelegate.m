//
//  AppDelegate.m
//  librtmpExample
//
//  Created by banjun on 2014/02/23.
//  Copyright (c) 2014年 banjun. All rights reserved.
//

#import "AppDelegate.h"
#import <librtmp/rtmp.h>
#import <librtmp/log.h>



typedef enum {
    AudioObjectTypeNull = 0,
    AudioObjectTypeAACMain,
    AudioObjectTypeAACLC,
    AudioObjectTypeAACSR,
    AudioObjectTypeAACLTP,
    AudioObjectTypeSBR,
    AudioObjectTypeAACScalable,
} AudioObjectType;

typedef struct {
    AudioObjectType type:5;
    uint8_t freqIndex:4;
    uint8_t channel:4;
    uint8_t frameLengthFlag:1;
    uint8_t dependsOnCoreCoder:1;
    uint8_t extensionFlag:1;
} AudioSetupData;

@interface AppDelegate ()

@property (nonatomic) NSTextField *urlField;
@property (nonatomic) NSButton *liveCheckbox;
@property (nonatomic) NSTextField *swfUrlField;

@property (nonatomic) RTMP *rtmp;
@property (nonatomic) AudioSetupData audioSetupData;
@property (nonatomic) double audioDataRate;
@property (nonatomic) NSFileHandle *audioFileHandle;

@end


@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification
{
    NSView *contentView = self.window.contentView;
    
    self.urlField = [[NSTextField alloc] initWithFrame:NSInsetRect(NSMakeRect(0, contentView.frame.size.height - 22 - 20, contentView.frame.size.width, 22), 20, 0)];
    self.urlField.autoresizingMask = NSViewWidthSizable | NSViewMinYMargin;
    [self.urlField bind:@"value"
               toObject:[NSUserDefaultsController sharedUserDefaultsController]
            withKeyPath:@"values.rtmpURL"
                options:@{NSNullPlaceholderBindingOption: @"rtmpURL"}];
    [contentView addSubview:self.urlField];
    [self.window makeFirstResponder:self.urlField];
    
    self.swfUrlField = [[NSTextField alloc] initWithFrame:NSInsetRect(NSMakeRect(0, self.urlField.frame.origin.y - 22- 20, contentView.frame.size.width, 22), 20, 0)];
    self.swfUrlField.autoresizingMask = NSViewWidthSizable | NSViewMinYMargin;
    [self.swfUrlField bind:@"value"
               toObject:[NSUserDefaultsController sharedUserDefaultsController]
            withKeyPath:@"values.swfURL"
                options:@{NSNullPlaceholderBindingOption: @"swfUrl"}];
    [contentView addSubview:self.swfUrlField];
    self.urlField.nextKeyView = self.swfUrlField;
    self.swfUrlField.nextKeyView = self.urlField;
    
    self.liveCheckbox = [[NSButton alloc] initWithFrame:NSZeroRect];
    [self.liveCheckbox setButtonType:NSSwitchButton];
    self.liveCheckbox.title = @"--live";
    [self.liveCheckbox bind:@"value"
                   toObject:[NSUserDefaultsController sharedUserDefaultsController]
                withKeyPath:@"values.rtmpLive"
                    options:nil];
    [self.liveCheckbox sizeToFit];
    self.liveCheckbox.frame = NSMakeRect(20, self.swfUrlField.frame.origin.y - self.liveCheckbox.frame.size.height - 10, self.liveCheckbox.frame.size.width, self.liveCheckbox.frame.size.height);
    self.liveCheckbox.autoresizingMask = NSViewMaxXMargin | NSViewMinYMargin;
    [contentView addSubview:self.liveCheckbox];
    
    NSButton *goButton = [[NSButton alloc] initWithFrame:NSZeroRect];
    goButton.bezelStyle = NSRoundedBezelStyle;
    goButton.title = NSLocalizedString(@"Go", @"");
    [goButton sizeToFit];
    goButton.frame = NSMakeRect(contentView.frame.size.width - goButton.frame.size.width - 20, self.swfUrlField.frame.origin.y - goButton.frame.size.width - 10, goButton.frame.size.width, goButton.frame.size.height);
    goButton.autoresizingMask = NSViewMinXMargin | NSViewMinYMargin;
    goButton.target = self;
    goButton.action = @selector(go:);
    goButton.keyEquivalent = @"\r";
    [contentView addSubview:goButton];
}

- (IBAction)go:(id)sender
{
    NSString *urlString = self.urlField.stringValue;
    NSLog(@"url = %@", urlString);
    // example: 'rtmpe://netradio-r1-flash.nhk.jp/live/NetRadio_R1_flash@63346' and --live
    
    NSString *swfURLString = self.swfUrlField.stringValue;
    NSLog(@"swfUrl = %@", swfURLString);
    // example: http://www3.nhk.or.jp/netradio/files/swf/rtmpe.swf
    
    RTMP_LogSetLevel(RTMP_LOGERROR);
    
    self.rtmp = RTMP_Alloc();
    if (!self.rtmp) {
        NSLog(@"failed to alloc RTMP");
        return;
    }
    RTMP_Init(self.rtmp);
    
    // set swfurl
    if (swfURLString.length > 0) {
        self.rtmp->Link.swfUrl = (AVal)AVC((char *)swfURLString.UTF8String);
        self.rtmp->Link.lFlags |= RTMP_LF_SWFV;
    }
    
    RTMP_SetupURL(self.rtmp, (char *)urlString.UTF8String);
    
    // set --live
    if (self.liveCheckbox.state == NSOnState) {
        self.rtmp->Link.lFlags |= RTMP_LF_LIVE;
    }
    
    if (!RTMP_Connect(self.rtmp, NULL)) {
        NSLog(@"failed to connect");
    }
    if (!RTMP_ConnectStream(self.rtmp, 0)) {
        NSLog(@"failed to connect stream");
    }
    
    NSDate *start = [NSDate date];
    while ([[NSDate date] timeIntervalSinceDate:start] <= 10 * 60) {
        @autoreleasepool {
            RTMPPacket packet = {0};
            if (RTMP_ReadPacket(self.rtmp, &packet)) {
                NSLog(@"RTMP read %d bytes as packet", packet.m_nBytesRead);
                RTMPPacket_Dump(&packet);
                if (packet.m_packetType == RTMP_PACKET_TYPE_INFO) {
                    [self decodeAudioInfo:&packet];
                } else if (packet.m_packetType == RTMP_PACKET_TYPE_AUDIO) {
                    NSLog(@"found audio packet (%d bytes)", packet.m_nBodySize);
                    
                    static unsigned char firstFrame[] = {0xAF, 0x00}; // AAC sequence header (FLV Audio Tag)
                    static size_t firstFrameLength = sizeof(firstFrame) / sizeof(firstFrame[0]);
                    static unsigned char soundBytes[] = {0xAF, 0x01}; // AAC raw (FLV Audio Tag)
                    static size_t soundBytesLength = sizeof(soundBytes) / sizeof(soundBytes[0]);
                    // unless first is 0xAX, non AAC data follows
                    
                    if (packet.m_nBodySize > firstFrameLength && memcmp(packet.m_body, firstFrame, firstFrameLength) == 0) {
                        // first 'AF 00' means audio extra data (first frame)
                        AudioSetupData data = self.audioSetupData;
                        data.type = (packet.m_body[2] >> 3);
                        data.freqIndex = ((packet.m_body[2] & 7) << 1) + (packet.m_body[3] >> 7); // NOTE: mismatch to audiodatarate?
                        data.channel = (packet.m_body[3] >> 3) & 0x0F;
                        self.audioSetupData = data;
                    } else if (packet.m_nBodySize > soundBytesLength && memcmp(packet.m_body, soundBytes, soundBytesLength) == 0) {
                        // first 'AF 01' means audio AAC raw
                        [self writeAACWithADTS:[NSData dataWithBytesNoCopy:packet.m_body + soundBytesLength
                                                                    length:packet.m_nBodySize - soundBytesLength
                                                              freeWhenDone:NO]];
                    }
                } else if (packet.m_packetType == RTMP_PACKET_TYPE_CONTROL) {
                    NSLog(@"control packet received");
                    
                    // reply ping
                    RTMP_ClientPacket(self.rtmp, &packet);
                } else {
                    NSLog(@"packet type = %d", packet.m_packetType);
                }
            } else {
                NSLog(@"failed to read packet.");
                break;
            }
        }
    }
    
    RTMP_Close(self.rtmp);
    RTMP_Free(self.rtmp);
    self.rtmp = NULL;
    
    [self.audioFileHandle closeFile];
    self.audioFileHandle = nil;
    NSLog(@"disconnected stream");
}

- (void)decodeAudioInfo:(RTMPPacket *)packet
{
    if (packet->m_packetType != RTMP_PACKET_TYPE_INFO) return;
    
    AMFObject amfObj = {0};
    if (AMF_Decode(&amfObj, packet->m_body, packet->m_nBodySize, FALSE) > 0) {
        AMF_Dump(&amfObj);
        
        AMFObjectProperty *nameProp = AMF_GetProp(&amfObj, NULL, 0);
        if (nameProp->p_type == AMF_STRING) {
            AVal onMetadata = AVC("onMetaData");
            AVal name = {0};
            AMFProp_GetString(nameProp, &name);
            if (AVMATCH(&name, &onMetadata)) {
                AMFObject metadata = {0};
                AMFProp_GetObject(AMF_GetProp(&amfObj, NULL, 1), &metadata);
                
                AVal audiodatarate = AVC("audiodatarate");
                AMFObjectProperty *rateProp = AMF_GetProp(&metadata, &audiodatarate, -1);
                if (rateProp->p_type == AMF_NUMBER) {
                    self.audioDataRate = AMFProp_GetNumber(rateProp);
                    NSLog(@"audioDataRate = %f", self.audioDataRate);
                }
            }
        }
    }
}

- (void)writeAACWithADTS:(NSData *)aacRawData
{
    static double freqs[] = {
        96, 88.2, 64, 48, 44.1, 32, 24, 22.05, 16, 12, 11.025, 8
    };
    int freqIndex = -1;
    for (int i = 0; i < sizeof(freqs) / sizeof(freqs[0]); ++i) {
        if (freqs[i] == self.audioDataRate) {
            freqIndex = i;
            break;
        }
    }
    if (freqIndex < 0) {
        NSLog(@"unknown freq: %f", self.audioDataRate);
        return;
    }
    if (freqIndex != self.audioSetupData.freqIndex) {
        // NOTE: freq[freqIndex] == freq[audioSetupData.freqIndex] * 2 when HE-AAC (SBR)
        NSLog(@"freqIndex mismatch (%f (audiodatarate) vs %f (audioSetupData)). using audioSetupData", freqs[freqIndex], freqs[self.audioSetupData.freqIndex]);
        freqIndex = self.audioSetupData.freqIndex;
    }
    
    // map AudioObjectType -> ADTS profile
    int profile = 0;
    switch (self.audioSetupData.type) {
        case AudioObjectTypeAACMain:
            profile = 0;
            break;
        case AudioObjectTypeAACLC:
            profile = 1;
            break;
        case AudioObjectTypeAACScalable:
            profile = 2;
            break;
        default:
            NSLog(@"unsupported audio object type in ADTS: %d", self.audioSetupData.type);
            return;
    }
    
    unsigned char adtsHeader[7] = {
        0xff, // first 0xfff is for sync
        0xf1, // sync: 1111, id:0, layer:00, protection: 1(0 does not work)
        0x58, // profile: 01(LC), freq(4bits): (->table), private:0, channel msb(1bit): 0
        0x80, // channel(2bits) 10(2ch), length(last 2 bits)
        0x00, // length
        0x1f, // length(first 3bits), VBR
        0xfc, // VBR
    };
    size_t adtsHeaderLength = sizeof(adtsHeader) / sizeof(adtsHeader[0]);
    
    uint16_t aacFrameLength = adtsHeaderLength + aacRawData.length;
    
    adtsHeader[2] = ((profile & 3) << 6) | (freqIndex << 2) | (self.audioSetupData.channel & 4 >> 2);
    adtsHeader[3] = ((self.audioSetupData.channel & 3) << 6) | (aacFrameLength >> 14); // take first 2bit to lower 2 bit
    adtsHeader[4] = ((aacFrameLength >> 3) & 0xff); // next 8bit
    adtsHeader[5] = (adtsHeader[5] & 0x1f) | ((aacFrameLength & 7) << 5); // last 3bit
    
    if (!self.audioFileHandle) {
        NSString *audioFilePath = [NSTemporaryDirectory() stringByAppendingPathComponent:@"librtmpExample-export.aac"];
        [[NSFileManager defaultManager] createFileAtPath:audioFilePath contents:nil attributes:nil];
        self.audioFileHandle = [NSFileHandle fileHandleForWritingAtPath:audioFilePath];
        [[NSWorkspace sharedWorkspace] openFile:audioFilePath.stringByDeletingLastPathComponent];
    }
    [self.audioFileHandle writeData:[NSData dataWithBytesNoCopy:adtsHeader length:adtsHeaderLength freeWhenDone:NO]];
    [self.audioFileHandle writeData:aacRawData];
    [self.audioFileHandle synchronizeFile];
}

@end
