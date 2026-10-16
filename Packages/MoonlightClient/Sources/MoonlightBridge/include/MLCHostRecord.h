//
//  MLCHostRecord.h
//  Adapted from moonlight-ios Limelight/Database/TemporaryHost.h at 02dc9780.
//  CoreData is replaced by a plain in-memory record.
//

#import <Foundation/Foundation.h>
#import "MLCAppRecord.h"
#import "MLCUtils.h"

#ifndef MLC_HOST_RECORD_H
#define MLC_HOST_RECORD_H

@interface MLCHostRecord : NSObject

@property (atomic) HostState state;
@property (atomic) PairState pairState;
@property (atomic, nullable, retain) NSString* addressPortString;
@property (atomic, nullable, retain) NSString* currentGame;
@property (atomic) unsigned short httpsPort;
@property (atomic) BOOL isNvidiaServerSoftware;

@property (atomic, nullable, retain) NSData* serverCert;
@property (atomic, nullable, retain) NSString* address;
@property (atomic, nullable, retain) NSString* externalAddress;
@property (atomic, nullable, retain) NSString* localAddress;
@property (atomic, nullable, retain) NSString* ipv6Address;
@property (atomic, nullable, retain) NSString* mac;
@property (atomic) int serverCodecModeSupport;

@property (atomic, retain) NSString* name;
@property (atomic, retain) NSString* uuid;
@property (atomic, retain) NSArray<MLCAppRecord*>* appList;

- (NSComparisonResult)compareName:(MLCHostRecord*)other;

@end

#endif
