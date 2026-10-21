
#import <Foundation/Foundation.h>

#ifndef MLC_APP_RECORD_H
#define MLC_APP_RECORD_H

@interface MLCAppRecord : NSObject

@property (nullable, nonatomic, retain) NSString* id;
@property (nullable, nonatomic, retain) NSString* name;
@property (nonatomic) BOOL hdrSupported;
@property (nonatomic) BOOL hidden;

- (NSComparisonResult)compareName:(MLCAppRecord*)other;

@end

#endif
