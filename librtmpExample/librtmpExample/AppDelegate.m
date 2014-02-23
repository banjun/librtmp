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


@interface AppDelegate ()

@property (nonatomic) NSTextField *urlField;
@property (nonatomic) NSButton *liveCheckbox;

@property (nonatomic) RTMP *rtmp;
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
                options:nil];
    [contentView addSubview:self.urlField];
    
    self.liveCheckbox = [[NSButton alloc] initWithFrame:NSZeroRect];
    [self.liveCheckbox setButtonType:NSSwitchButton];
    self.liveCheckbox.title = @"--live";
    [self.liveCheckbox bind:@"value"
                   toObject:[NSUserDefaultsController sharedUserDefaultsController]
                withKeyPath:@"values.rtmpLive"
                    options:nil];
    [self.liveCheckbox sizeToFit];
    self.liveCheckbox.frame = NSMakeRect(20, self.urlField.frame.origin.y - self.liveCheckbox.frame.size.height - 10, self.liveCheckbox.frame.size.width, self.liveCheckbox.frame.size.height);
    self.liveCheckbox.autoresizingMask = NSViewMaxXMargin | NSViewMinYMargin;
    [contentView addSubview:self.liveCheckbox];
    
    NSButton *goButton = [[NSButton alloc] initWithFrame:NSZeroRect];
    goButton.bezelStyle = NSRoundedBezelStyle;
    goButton.title = NSLocalizedString(@"Go", @"");
    [goButton sizeToFit];
    goButton.frame = NSMakeRect(contentView.frame.size.width - goButton.frame.size.width - 20, self.urlField.frame.origin.y - goButton.frame.size.width - 10, goButton.frame.size.width, goButton.frame.size.height);
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
    
    RTMP_LogSetLevel(RTMP_LOGERROR);
    
    self.rtmp = RTMP_Alloc();
    if (!self.rtmp) {
        NSLog(@"failed to alloc RTMP");
        return;
    }
    RTMP_Init(self.rtmp);
    
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
    
    for (int i = 0; i < 100; ++i) {
        RTMPPacket packet = {0};
        if (RTMP_ReadPacket(self.rtmp, &packet)) {
            NSLog(@"RTMP read %d bytes as packet", packet.m_nBytesRead);
            RTMPPacket_Dump(&packet);
            if (packet.m_packetType == RTMP_PACKET_TYPE_INFO) {
                [self decodeAudioInfo:&packet];
            }
            if (packet.m_packetType == RTMP_PACKET_TYPE_AUDIO) {
                NSLog(@"found audio packet (%d bytes)", packet.m_nBodySize);
                if (packet.m_nBodySize > 2) {
                    // first 'AF 01' means audio AAC raw
                    unsigned char soundBytes[] = {0xAF, 0x01};
                    size_t soundBytesLength = sizeof(soundBytes) / sizeof(soundBytes[0]);
                    if (memcmp(packet.m_body, soundBytes, soundBytesLength) == 0) {
                        [self writeAACWithADTS:[NSData dataWithBytesNoCopy:packet.m_body + soundBytesLength
                                                                    length:packet.m_nBodySize - soundBytesLength
                                                              freeWhenDone:NO]];
                    }
                }
            }
        } else {
            NSLog(@"failed to read packet.");
            break;
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
    
    adtsHeader[3] = (adtsHeader[3] & 0xfc) | (aacFrameLength >> 14); // take first 2bit to lower 2 bit
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
