//
//  MLCIdManager.h
//  Adapted from moonlight-ios Limelight/Crypto/IdManager.h at 02dc9780.
//  Persistence is NSUserDefaults instead of the CoreData store.
//

#import <Foundation/Foundation.h>

#ifndef MLC_ID_MANAGER_H
#define MLC_ID_MANAGER_H

@interface MLCIdManager : NSObject

+ (NSString*)getUniqueId;

@end

#endif
