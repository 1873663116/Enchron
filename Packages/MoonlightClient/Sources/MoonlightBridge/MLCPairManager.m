
#import "MLCPairManager.h"
#import "MLCCryptoManager.h"
#import "MLCHttpResponse.h"
#import "MLCServerInfoResponse.h"
#import "MLCUtils.h"

#include <dispatch/dispatch.h>

@implementation MLCPairManager {
    MLCHttpManager* _httpManager;
    NSData* _clientCert;
    id<MLCPairCallback> _callback;
    NSString* _pin;
}

- (id)initWithManager:(MLCHttpManager*)httpManager clientCert:(NSData*)clientCert callback:(id<MLCPairCallback>)callback {
    return [self initWithManager:httpManager clientCert:clientCert callback:callback pin:nil];
}

- (id)initWithManager:(MLCHttpManager*)httpManager clientCert:(NSData*)clientCert callback:(id<MLCPairCallback>)callback pin:(NSString*)pin {
    self = [super init];
    _httpManager = httpManager;
    _clientCert = clientCert;
    _callback = callback;
    _pin = [pin copy];
    return self;
}

- (void)main {
    NSString* PIN = _pin ?: [self generatePIN];
    [_callback startPairing:PIN];

    MLCServerInfoResponse* serverInfoResp = [[MLCServerInfoResponse alloc] init];
    [_httpManager executeRequestSynchronously:[MLCHttpRequest requestForResponse:serverInfoResp withUrlRequest:[_httpManager newServerInfoRequest:false]
                                               fallbackError:401 fallbackRequest:[_httpManager newHttpServerInfoRequest]]];
    if ([serverInfoResp isStatusOk]) {
        if (![[serverInfoResp getStringTag:@"PairStatus"] isEqual:@"1"]) {
            NSString* appversion = [serverInfoResp getStringTag:@"appversion"];
            if (appversion == nil) {
                [_callback pairFailed:@"Missing XML element"];
                return;
            }
            [self initiatePairWithPin:PIN forServerMajorVersion:[[appversion substringToIndex:1] intValue] withState:[serverInfoResp getStringTag:@"state"]];
        } else {
            [_callback alreadyPaired];
        }
    }
    else {
        [_callback pairFailed:serverInfoResp.statusMessage];
    }
}

- (void)finishPairingForResponse:(MLCHttpResponse*)resp withFallbackError:(NSString*)errorMsg {
    [_httpManager executeRequestSynchronously:[MLCHttpRequest requestWithUrlRequest:[_httpManager newUnpairRequest]]];

    if (![resp isStatusOk]) {
        errorMsg = resp.statusMessage;
    }

    [_callback pairFailed:errorMsg];
}

- (void)finishPairingWithSuccess:(NSData*)derCertBytes {
    [_callback pairSuccessful:derCertBytes];
}

- (void)initiatePairWithPin:(NSString*)PIN forServerMajorVersion:(int)serverMajorVersion withState:(NSString*)state {
    Log(LOG_I, @"Pairing with generation %d server in state %@", serverMajorVersion, state);

    NSData* salt = [MLCUtils randomBytes:16];
    NSData* saltedPIN = [self concatData:salt with:[PIN dataUsingEncoding:NSUTF8StringEncoding]];

    Log(LOG_I, @"PIN: %@, salt %@", PIN, salt);

    MLCHttpResponse* pairResp = [[MLCHttpResponse alloc] init];
    [_httpManager executeRequestSynchronously:[MLCHttpRequest requestForResponse:pairResp withUrlRequest:[_httpManager newPairRequest:salt clientCert:_clientCert]]];
    if (![self verifyResponseStatus:pairResp]) {
        if ([state hasSuffix:@"_SERVER_BUSY"]) {
            [self finishPairingForResponse:pairResp withFallbackError:@"You cannot pair while a previous session is still running on the host PC. Quit any running games or reboot the host PC, then try pairing again."];
        }
        else {
            [self finishPairingForResponse:pairResp withFallbackError:@"Pairing was declined by the target."];
        }
        return;
    }

    NSString* plainCert = [pairResp getStringTag:@"plaincert"];
    if ([plainCert length] == 0) {
        [self finishPairingForResponse:pairResp withFallbackError:@"Another pairing attempt is already in progress."];
        return;
    }

    NSData* derCertBytes = [MLCCryptoManager pemToDer:[MLCUtils hexToBytes:plainCert]];
    [_httpManager setServerCert:derCertBytes];

    MLCCryptoManager* cryptoMan = [[MLCCryptoManager alloc] init];
    NSData* aesKey;

    int hashLength;
    if (serverMajorVersion >= 7) {
        aesKey = [cryptoMan createAESKeyFromSaltSHA256:saltedPIN];
        hashLength = 32;
    }
    else {
        aesKey = [cryptoMan createAESKeyFromSaltSHA1:saltedPIN];
        hashLength = 20;
    }

    NSData* randomChallenge = [MLCUtils randomBytes:16];
    NSData* encryptedChallenge = [cryptoMan aesEncrypt:randomChallenge withKey:aesKey];

    MLCHttpResponse* challengeResp = [[MLCHttpResponse alloc] init];
    [_httpManager executeRequestSynchronously:[MLCHttpRequest requestForResponse:challengeResp withUrlRequest:[_httpManager newChallengeRequest:encryptedChallenge]]];
    if (![self verifyResponseStatus:challengeResp]) {
        [self finishPairingForResponse:challengeResp withFallbackError:@"Pairing stage #2 failed"];
        return;
    }

    NSData* encServerChallengeResp = [MLCUtils hexToBytes:[challengeResp getStringTag:@"challengeresponse"]];
    NSData* decServerChallengeResp = [cryptoMan aesDecrypt:encServerChallengeResp withKey:aesKey];

    NSData* serverResponse = [decServerChallengeResp subdataWithRange:NSMakeRange(0, hashLength)];
    NSData* serverChallenge = [decServerChallengeResp subdataWithRange:NSMakeRange(hashLength, 16)];

    NSData* clientSecret = [MLCUtils randomBytes:16];
    NSData* challengeRespHashInput = [self concatData:[self concatData:serverChallenge with:[MLCCryptoManager getSignatureFromCert:_clientCert]] with:clientSecret];
    NSData* challengeRespHash;
    if (serverMajorVersion >= 7) {
        challengeRespHash = [cryptoMan SHA256HashData:challengeRespHashInput];
    }
    else {
        challengeRespHash = [cryptoMan SHA1HashData:challengeRespHashInput];
    }

    assert([challengeRespHash length] <= 32);
    NSMutableData* paddedHash = [NSMutableData dataWithData:challengeRespHash];
    [paddedHash setLength:32];

    NSData* challengeRespEncrypted = [cryptoMan aesEncrypt:paddedHash withKey:aesKey];

    MLCHttpResponse* secretResp = [[MLCHttpResponse alloc] init];
    [_httpManager executeRequestSynchronously:[MLCHttpRequest requestForResponse:secretResp withUrlRequest:[_httpManager newChallengeRespRequest:challengeRespEncrypted]]];
    if (![self verifyResponseStatus:secretResp]) {
        [self finishPairingForResponse:secretResp withFallbackError:@"Pairing stage #3 failed"];
        return;
    }

    NSData* serverSecretResp = [MLCUtils hexToBytes:[secretResp getStringTag:@"pairingsecret"]];
    NSData* serverSecret = [serverSecretResp subdataWithRange:NSMakeRange(0, 16)];
    NSData* serverSignature = [serverSecretResp subdataWithRange:NSMakeRange(16, serverSecretResp.length - 16)];

    if (![cryptoMan verifySignature:serverSecret withSignature:serverSignature andCert:[MLCUtils hexToBytes:plainCert]]) {
        [self finishPairingForResponse:secretResp withFallbackError:@"Server certificate invalid"];
        return;
    }

    NSData* serverChallengeRespHashInput = [self concatData:[self concatData:randomChallenge with:[MLCCryptoManager getSignatureFromCert:[MLCUtils hexToBytes:plainCert]]] with:serverSecret];
    NSData* serverChallengeRespHash;
    if (serverMajorVersion >= 7) {
        serverChallengeRespHash = [cryptoMan SHA256HashData:serverChallengeRespHashInput];
    }
    else {
        serverChallengeRespHash = [cryptoMan SHA1HashData:serverChallengeRespHashInput];
    }
    if (![serverChallengeRespHash isEqual:serverResponse]) {
        [self finishPairingForResponse:secretResp withFallbackError:@"Incorrect PIN"];
        return;
    }

    NSData* clientPairingSecret = [self concatData:clientSecret with:[cryptoMan signData:clientSecret withKey:[MLCCryptoManager readKeyFromFile]]];
    MLCHttpResponse* clientSecretResp = [[MLCHttpResponse alloc] init];
    [_httpManager executeRequestSynchronously:[MLCHttpRequest requestForResponse:clientSecretResp withUrlRequest:[_httpManager newClientSecretRespRequest:[MLCUtils bytesToHex:clientPairingSecret]]]];
    if (![self verifyResponseStatus:clientSecretResp]) {
        [self finishPairingForResponse:clientSecretResp withFallbackError:@"Pairing stage #4 failed"];
        return;
    }

    MLCHttpResponse* clientPairChallengeResp = [[MLCHttpResponse alloc] init];
    [_httpManager executeRequestSynchronously:[MLCHttpRequest requestForResponse:clientPairChallengeResp withUrlRequest:[_httpManager newPairChallenge]]];
    if (![self verifyResponseStatus:clientPairChallengeResp]) {
        [self finishPairingForResponse:clientPairChallengeResp withFallbackError:@"Pairing stage #5 failed"];
        return;
    }

    [self finishPairingWithSuccess:derCertBytes];
}

- (BOOL)verifyResponseStatus:(MLCHttpResponse*)resp {
    if (![resp isStatusOk]) {
        return false;
    } else {
        NSInteger pairedStatus;

        if (![resp getIntTag:@"paired" value:&pairedStatus]) {
            return false;
        }

        return pairedStatus == 1;
    }
}

- (NSData*)concatData:(NSData*)data with:(NSData*)moreData {
    NSMutableData* concatData = [[NSMutableData alloc] initWithData:data];
    [concatData appendData:moreData];
    return concatData;
}

- (NSString*)generatePIN {
    NSString* PIN = [NSString stringWithFormat:@"%d%d%d%d",
                     arc4random_uniform(10), arc4random_uniform(10),
                     arc4random_uniform(10), arc4random_uniform(10)];
    return PIN;
}

@end
