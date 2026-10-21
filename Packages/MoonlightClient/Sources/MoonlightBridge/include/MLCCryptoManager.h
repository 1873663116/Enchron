
#import <Foundation/Foundation.h>

#ifndef MLC_CRYPTO_MANAGER_H
#define MLC_CRYPTO_MANAGER_H

@interface MLCCryptoManager : NSObject

+ (void)setStorageDirectory:(NSString*)dir;
+ (NSString*)storageDirectory;

+ (void)generateKeyPairUsingSSL;
+ (NSData*)readCertFromFile;
+ (NSData*)readKeyFromFile;
+ (NSData*)readP12FromFile;
+ (NSData*)getSignatureFromCert:(NSData*)cert;
+ (NSData*)pemToDer:(NSData*)pemCertBytes;

- (NSData*)createAESKeyFromSaltSHA1:(NSData*)saltedPIN;
- (NSData*)createAESKeyFromSaltSHA256:(NSData*)saltedPIN;
- (NSData*)SHA1HashData:(NSData*)data;
- (NSData*)SHA256HashData:(NSData*)data;
- (NSData*)aesEncrypt:(NSData*)data withKey:(NSData*)key;
- (NSData*)aesDecrypt:(NSData*)data withKey:(NSData*)key;
- (bool)verifySignature:(NSData*)data withSignature:(NSData*)signature andCert:(NSData*)cert;
- (NSData*)signData:(NSData*)data withKey:(NSData*)key;

@end

#endif
