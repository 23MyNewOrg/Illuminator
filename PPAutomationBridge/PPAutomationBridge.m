//
//  PPAutomationBridge.m
//  PPHCore
//
//  Created by Erceg,Boris on 10/8/13.
//  Copyright 2013 PayPal. All rights reserved.
//

#ifdef DEBUG

#import "PPAutomationBridge.h"
#import "QServer.h"

#define DOCUMENTS_FOLDER NSHomeDirectory()


@interface PPAutomationBridgeAction ()

+ (instancetype)actionWithDictionary:(NSDictionary *)dictionary;

@end

////////////////////////////////////////////////////////////////////////////////////////////////////
@interface PPAutomationBridge() <
QServerDelegate,
NSStreamDelegate>

@property (nonatomic, strong, readwrite) QServer *server;

//streams
@property (nonatomic, strong) NSInputStream *inputStream;
@property (nonatomic, strong) NSOutputStream *outputStream;
@property (nonatomic, strong) NSMutableData *inputData;
@property (nonatomic, strong) NSMutableData *outputData;
@property (nonatomic) uint writtenBytes;


@property (nonatomic, weak) id<PPAutomationBridgeDelegate> delegate;


@end

////////////////////////////////////////////////////////////////////////////////////////////////////
@implementation PPAutomationBridge

#pragma mark -
#pragma mark Init & Factory

static PPAutomationBridge *bridgeInstance = nil;

+ (instancetype)bridge {
    @synchronized(self) {
        if (bridgeInstance == nil) {
            bridgeInstance = [[self alloc] init];
        }
        return bridgeInstance;
    }
}


- (id)init {
    self = [super init];
    if (self) {
        NSString *automationUDID = nil;
#ifdef AUTOMATION_UDID
        automationUDID =  AUTOMATION_UDID;
#else
        automationUDID = [[[UIDevice currentDevice] identifierForVendor] UUIDString];
#endif
        self.server = [[QServer alloc] initWithDomain:@"local."
                                                 type:@"_bridge._tcp."
                                                 name:[NSString stringWithFormat:@"UIAutomationBridge_%@", automationUDID]
                                        preferredPort:4200];
        [self.server setDelegate:self];

    }

    return self;
}

- (void)dealloc {
    if (self.server) {
        [self.server stop];
    }
}



- (void)startAutomationBridgeWithDelegate:(id<PPAutomationBridgeDelegate>)delegate {
    self.delegate = delegate;
    if (self.server) {
        [self.server start];
    }

}

- (void)stopAutomationBridge {
    if (self.server) {
        [self.server stop];
    }
}

- (NSDictionary *)receivedMessage:(NSString *)message {
    self.isActivated = YES;
    id jsonObject = [NSJSONSerialization JSONObjectWithData:[message dataUsingEncoding:NSUTF8StringEncoding]
                                                    options: NSJSONReadingMutableContainers
                                                      error: nil];
    if ([NSJSONSerialization isValidJSONObject:jsonObject]) {
        NSMutableDictionary *returnDict = [NSMutableDictionary dictionary];
        NSDictionary *result = [self.delegate automationBridge:self receivedAction:[PPAutomationBridgeAction actionWithDictionary:jsonObject]];
        if (result) {
            [returnDict setObject:result forKey:@"result"];
        }
        [returnDict setObject:[jsonObject objectForKey:@"callUID"] forKey:@"callUID"];
        return returnDict;
    }

    return nil;
}
#pragma mark -
#pragma mark QServerDelegate

- (id)server:(QServer *)server connectionForInputStream:(NSInputStream *)inputStream outputStream:(NSOutputStream *)outputStream {
    [self setInputStream:inputStream];
    [self setOutputStream:outputStream];
    return self;
}

#pragma mark -
#pragma mark helpers

- (void)readData {
    NSString* string = [[NSString alloc] initWithData:self.inputData encoding:NSASCIIStringEncoding];
    if (string) {
        NSDictionary *returnMessage = [self receivedMessage:string];
        [self answerWith:returnMessage];
    }
}


- (void)answerWith:(NSDictionary *)dictionary {
    self.outputData = [[NSJSONSerialization dataWithJSONObject:dictionary
                                                       options:0
                                                         error:nil] mutableCopy];
    [_outputStream open];
    [self setInputStream:nil];
}

- (void)setInputStream:(NSInputStream *)inputStream {
    _inputData = nil;
    if (_inputStream) {
        [_inputStream close];
        [_inputStream removeFromRunLoop:[NSRunLoop currentRunLoop]
                                forMode:NSDefaultRunLoopMode];
        _inputStream = nil;
    }
    if (inputStream) {
        _inputStream = inputStream;
        [_inputStream setDelegate:self];
        [_inputStream scheduleInRunLoop:[NSRunLoop currentRunLoop]
                                forMode:NSDefaultRunLoopMode];
        [_inputStream open];
    }
}

- (void)setOutputStream:(NSOutputStream *)outputStream {
    _outputData = nil;
    if (_outputStream) {
        [_outputStream close];
        [_outputStream removeFromRunLoop:[NSRunLoop currentRunLoop]
                                forMode:NSDefaultRunLoopMode];
        _outputStream = nil;
        _writtenBytes = 0;
    }
    if (outputStream) {
        _outputStream = outputStream;
        [_outputStream setDelegate:self];
        [_outputStream scheduleInRunLoop:[NSRunLoop currentRunLoop]
                                 forMode:NSDefaultRunLoopMode];
    }
}



#pragma mark -
#pragma mark NSStreamDelegate

- (void)stream:(NSStream *)stream handleEvent:(NSStreamEvent)eventCode {
    if (stream == self.inputStream) {
        [self inputStream:stream handleEvent:eventCode];
    } else if (stream == self.outputStream) {
        [self outputStream:stream handleEvent:eventCode];
    }
}

- (void)inputStream:(NSStream *)stream handleEvent:(NSStreamEvent)eventCode {

    switch(eventCode) {
        case NSStreamEventHasBytesAvailable: {
            self.inputData = [NSMutableData data];

            uint8_t buffer[32768];
            unsigned int len = 0;
            len = [(NSInputStream *)stream read:buffer maxLength:sizeof(buffer)];
            if(len) {
                [self.inputData appendBytes:(const void *)buffer length:len];
            }
            [self readData];
            break;
        }
        default:
            break;
    }

}

- (void)outputStream:(NSStream *)stream handleEvent:(NSStreamEvent)eventCode {
    switch(eventCode) {
        case NSStreamEventHasSpaceAvailable: {
            const uint8_t *pData = [self.outputData bytes];
            while ([self.outputStream hasSpaceAvailable] && self.writtenBytes < self.outputData.length) {
                int r = [self.outputStream write:pData+self.writtenBytes maxLength:self.outputData.length-self.writtenBytes];
                if (r == -1) {
                    break;
                }
                self.writtenBytes += r;
            }
            if (self.outputData.length-self.writtenBytes == 0) {
                self.outputStream = nil;
            }
            break;
        case NSStreamEventEndEncountered:
            self.outputStream = nil;
            break;
        case NSStreamEventErrorOccurred:
            break;
        default:
            break;
        }
    }

}

@end

////////////////////////////////////////////////////////////////////////////////////////////////////
@implementation PPAutomationBridgeAction

+ (instancetype)actionWithDictionary:(NSDictionary *)dictionary {
    PPAutomationBridgeAction *action = [PPAutomationBridgeAction new];
    [action setSelector:[dictionary objectForKey:@"selector"]];
    if ([dictionary objectForKey:@"argument"]) {
        [action setArguments:[dictionary objectForKey:@"argument"]];
    }
    return action;
}

- (NSDictionary *)resultFromTarget:(id)target {
    SEL selector = NSSelectorFromString(self.selector);
    if ([target respondsToSelector:selector]) {
        id result = nil;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
        result = [target performSelector:selector withObject:self.arguments];
#pragma clang diagnostic pop
        return result;
    } else {
        return nil;
    }
}

@end

#endif
