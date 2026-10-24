
#import "MLCHttpManager.h"
#import "MLCCryptoManager.h"
#import "MLCServerInfoResponse.h"
#import "MLCUtils.h"

#include <string.h>

#import <Limelight.h>

#define SHORT_TIMEOUT_SEC 2
#define NORMAL_TIMEOUT_SEC 5
#define LONG_TIMEOUT_SEC 60
#define EXTRA_LONG_TIMEOUT_SEC 180

@implementation MLCHttpManager {
    NSString* _urlSafeHostName;
    NSString* _baseHTTPURL;
    NSString* _uniqueId;
    NSString* _deviceName;
    NSData* _serverCert;

    MLCHostRecord* _host;
    NSString* _baseHTTPSURL;
}

+ (NSData*)fixXmlVersion:(NSData*)xmlData {
    NSString* dataString = [[NSString alloc] initWithData:xmlData encoding:NSUTF8StringEncoding];
    NSString* xmlString = [dataString stringByReplacingOccurrencesOfString:@"UTF-16" withString:@"UTF-8" options:NSCaseInsensitiveSearch range:NSMakeRange(0, [dataString length])];

    return [xmlString dataUsingEncoding:NSUTF8StringEncoding];
}

- (void)setServerCert:(NSData*)serverCert {
    _serverCert = serverCert;
}

- (id)initWithHost:(MLCHostRecord*)host {
    self = [self initWithAddress:host.addressPortString httpsPort:host.httpsPort serverCert:host.serverCert];
    _host = host;
    return self;
}

- (id)initWithAddress:(NSString*)hostAddressPortString httpsPort:(unsigned short)httpsPort serverCert:(NSData*)serverCert {
    self = [super init];
    _uniqueId = @"0123456789ABCDEF";
    _deviceName = MLCDeviceName();
    _serverCert = serverCert;

    NSString* address = [MLCUtils addressPortStringToAddress:hostAddressPortString];
    unsigned short port = [MLCUtils addressPortStringToPort:hostAddressPortString];

    if ([address containsString:@":"]) {
        _urlSafeHostName = [NSString stringWithFormat:@"[%@]", address];
    } else {
        _urlSafeHostName = address;
    }

    _baseHTTPURL = [NSString stringWithFormat:@"http://%@:%u", _urlSafeHostName, port];

    if (httpsPort) {
        _baseHTTPSURL = [NSString stringWithFormat:@"https://%@:%u", _urlSafeHostName, httpsPort];
    }

    return self;
}

- (BOOL)ensureHttpsUrlPopulated:(bool)fastFail {
    if (!_baseHTTPSURL) {
        if (_host && _host.httpsPort != 0) {
            _baseHTTPSURL = [NSString stringWithFormat:@"https://%@:%u", _urlSafeHostName, _host.httpsPort];
        }
        else {
            MLCServerInfoResponse* serverInfoResponse = [[MLCServerInfoResponse alloc] init];
            [self executeRequestSynchronously:[MLCHttpRequest requestForResponse:serverInfoResponse withUrlRequest:[self newHttpServerInfoRequest:false]]];
            MLCHostRecord* dummyHost = [[MLCHostRecord alloc] init];
            if (![serverInfoResponse isStatusOk]) {
                return NO;
            }
            [serverInfoResponse populateHost:dummyHost];

            if (_host) {
                _host.httpsPort = dummyHost.httpsPort;
            }

            _baseHTTPSURL = [NSString stringWithFormat:@"https://%@:%u", _urlSafeHostName, dummyHost.httpsPort];
        }
    }

    return YES;
}

- (void)executeRequestSynchronously:(MLCHttpRequest*)request {
    if (!request.request) {
        if (request.response) {
            request.response.statusCode = EHOSTDOWN;
            request.response.statusMessage = @"Host is unreachable";
        }

        return;
    }

    __block NSData* requestResp = nil;
    __block NSError* respError = nil;
    __block dispatch_semaphore_t requestLock = dispatch_semaphore_create(0);

    Log(LOG_D, @"Making Request: %@", request);
    NSURLSession* urlSession = [NSURLSession sessionWithConfiguration:[NSURLSessionConfiguration ephemeralSessionConfiguration] delegate:self delegateQueue:nil];
    [[urlSession dataTaskWithRequest:request.request completionHandler:^(NSData* __nullable data, NSURLResponse* __nullable response, NSError* __nullable error) {

        if (error != NULL) {
            Log(LOG_D, @"Connection error: %@", error);
            respError = error;
        }
        else {
            Log(LOG_D, @"Received response: %@", response);

            if (data != NULL) {
                Log(LOG_D, @"\n\nReceived data: %@\n\n", [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding]);
                if ([[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] != nil) {
                    requestResp = [MLCHttpManager fixXmlVersion:data];
                } else {
                    requestResp = data;
                }
            }
        }

        dispatch_semaphore_signal(requestLock);
    }] resume];

    dispatch_semaphore_wait(requestLock, DISPATCH_TIME_FOREVER);
    [urlSession invalidateAndCancel];

    if (!respError && request.response) {
        [request.response populateWithData:requestResp];

        if (request.response.statusCode == request.fallbackError && request.fallbackRequest != NULL) {
            Log(LOG_D, @"Request failed with fallback error code: %d", request.fallbackError);
            request.request = request.fallbackRequest;
            request.fallbackError = 0;
            request.fallbackRequest = NULL;
            [self executeRequestSynchronously:request];
        }
    }
    else if (respError && [respError code] == NSURLErrorServerCertificateUntrusted) {
        if (request.fallbackRequest) {
            Log(LOG_D, @"Attempting fallback request after certificate trust failure");
            request.request = request.fallbackRequest;
            request.fallbackError = 0;
            request.fallbackRequest = NULL;
            [self executeRequestSynchronously:request];
        }
    }
    else if (respError && request.response) {
        request.response.statusCode = [respError code];
        request.response.statusMessage = [respError localizedDescription];
    }
}

- (NSURLRequest*)createRequestFromString:(NSString*)urlString timeout:(int)timeout {
    NSURL* url = [[NSURL alloc] initWithString:urlString];
    NSMutableURLRequest* request = [NSMutableURLRequest requestWithURL:url];
    [request setTimeoutInterval:timeout];
    return request;
}

- (NSURLRequest*)newPairRequest:(NSData*)salt clientCert:(NSData*)clientCert {
    NSString* urlString = [NSString stringWithFormat:@"%@/pair?uniqueid=%@&devicename=%@&updateState=1&phrase=getservercert&salt=%@&clientcert=%@",
                           _baseHTTPURL, _uniqueId, _deviceName, [self bytesToHex:salt], [self bytesToHex:clientCert]];
    return [self createRequestFromString:urlString timeout:EXTRA_LONG_TIMEOUT_SEC];
}

- (NSURLRequest*)newUnpairRequest {
    NSString* urlString = [NSString stringWithFormat:@"%@/unpair?uniqueid=%@", _baseHTTPURL, _uniqueId];
    return [self createRequestFromString:urlString timeout:NORMAL_TIMEOUT_SEC];
}

- (NSURLRequest*)newChallengeRequest:(NSData*)challenge {
    NSString* urlString = [NSString stringWithFormat:@"%@/pair?uniqueid=%@&devicename=%@&updateState=1&clientchallenge=%@",
                           _baseHTTPURL, _uniqueId, _deviceName, [self bytesToHex:challenge]];
    return [self createRequestFromString:urlString timeout:NORMAL_TIMEOUT_SEC];
}

- (NSURLRequest*)newChallengeRespRequest:(NSData*)challengeResp {
    NSString* urlString = [NSString stringWithFormat:@"%@/pair?uniqueid=%@&devicename=%@&updateState=1&serverchallengeresp=%@",
                           _baseHTTPURL, _uniqueId, _deviceName, [self bytesToHex:challengeResp]];
    return [self createRequestFromString:urlString timeout:NORMAL_TIMEOUT_SEC];
}

- (NSURLRequest*)newClientSecretRespRequest:(NSString*)clientPairSecret {
    NSString* urlString = [NSString stringWithFormat:@"%@/pair?uniqueid=%@&devicename=%@&updateState=1&clientpairingsecret=%@", _baseHTTPURL, _uniqueId, _deviceName, clientPairSecret];
    return [self createRequestFromString:urlString timeout:NORMAL_TIMEOUT_SEC];
}

- (NSURLRequest*)newPairChallenge {
    if (![self ensureHttpsUrlPopulated:NO]) {
        return nil;
    }

    NSString* urlString = [NSString stringWithFormat:@"%@/pair?uniqueid=%@&devicename=%@&updateState=1&phrase=pairchallenge", _baseHTTPSURL, _uniqueId, _deviceName];
    return [self createRequestFromString:urlString timeout:NORMAL_TIMEOUT_SEC];
}

- (NSURLRequest*)newAppListRequest {
    if (![self ensureHttpsUrlPopulated:NO]) {
        return nil;
    }

    NSString* urlString = [NSString stringWithFormat:@"%@/applist?uniqueid=%@", _baseHTTPSURL, _uniqueId];
    return [self createRequestFromString:urlString timeout:NORMAL_TIMEOUT_SEC];
}

- (NSURLRequest*)newServerInfoRequest:(bool)fastFail {
    if (_serverCert == nil) {
        return [self newHttpServerInfoRequest:fastFail];
    }

    if (![self ensureHttpsUrlPopulated:fastFail]) {
        return nil;
    }

    NSString* urlString = [NSString stringWithFormat:@"%@/serverinfo?uniqueid=%@", _baseHTTPSURL, _uniqueId];
    return [self createRequestFromString:urlString timeout:(fastFail ? SHORT_TIMEOUT_SEC : NORMAL_TIMEOUT_SEC)];
}

- (NSURLRequest*)newHttpServerInfoRequest:(bool)fastFail {
    NSString* urlString = [NSString stringWithFormat:@"%@/serverinfo", _baseHTTPURL];
    return [self createRequestFromString:urlString timeout:(fastFail ? SHORT_TIMEOUT_SEC : NORMAL_TIMEOUT_SEC)];
}

- (NSURLRequest*)newHttpServerInfoRequest {
    return [self newHttpServerInfoRequest:false];
}

- (NSURLRequest*)newLaunchOrResumeRequest:(NSString*)verb config:(MLCStreamConfiguration*)config {
    if (![self ensureHttpsUrlPopulated:NO]) {
        return nil;
    }

    int fps = (config.frameRate > 60 && ![config.appVersion containsString:@".-"]) ? 0 : config.frameRate;

    NSString* urlString = [NSString stringWithFormat:@"%@/%@?uniqueid=%@&appid=%@&mode=%dx%dx%d&additionalStates=1&sops=%d&rikey=%@&rikeyid=%d%@&localAudioPlayMode=%d&surroundAudioInfo=%d&remoteControllersBitmap=%d&gcmap=%d&gcpersist=%d%s",
                           _baseHTTPSURL, verb, _uniqueId,
                           config.appID,
                           config.width, config.height, fps,
                           config.optimizeGameSettings ? 1 : 0,
                           [MLCUtils bytesToHex:config.riKey], config.riKeyId,
                           (config.supportedVideoFormats & VIDEO_FORMAT_MASK_10BIT) ? @"&hdrMode=1&clientHdrCapVersion=0&clientHdrCapSupportedFlagsInUint32=0&clientHdrCapMetaDataId=NV_STATIC_METADATA_TYPE_1&clientHdrCapDisplayData=0x0x0x0x0x0x0x0x0x0x0": @"",
                           config.playAudioOnPC ? 1 : 0,
                           SURROUNDAUDIOINFO_FROM_AUDIO_CONFIGURATION(config.audioConfiguration),
                           config.gamepadMask, config.gamepadMask,
                           !config.multiController ? 1 : 0,
                           LiGetLaunchUrlQueryParameters()];
    Log(LOG_I, @"Requesting: %@", urlString);
    return [self createRequestFromString:urlString timeout:LONG_TIMEOUT_SEC];
}

- (NSURLRequest*)newQuitAppRequest {
    if (![self ensureHttpsUrlPopulated:NO]) {
        return nil;
    }

    NSString* urlString = [NSString stringWithFormat:@"%@/cancel?uniqueid=%@", _baseHTTPSURL, _uniqueId];
    return [self createRequestFromString:urlString timeout:LONG_TIMEOUT_SEC];
}

- (NSURLRequest*)newAppAssetRequestWithAppId:(NSString*)appId {
    if (![self ensureHttpsUrlPopulated:NO]) {
        return nil;
    }

    NSString* urlString = [NSString stringWithFormat:@"%@/appasset?uniqueid=%@&appid=%@&AssetType=2&AssetIdx=0", _baseHTTPSURL, _uniqueId, appId];
    return [self createRequestFromString:urlString timeout:NORMAL_TIMEOUT_SEC];
}

- (NSString*)bytesToHex:(NSData*)data {
    const unsigned char* bytes = [data bytes];
    NSMutableString* hex = [[NSMutableString alloc] init];
    for (int i = 0; i < [data length]; i++) {
        [hex appendFormat:@"%02X", bytes[i]];
    }
    return hex;
}

- (NSArray*)getCertificate:(SecIdentityRef)identity {
    SecCertificateRef certificate = nil;

    SecIdentityCopyCertificate(identity, &certificate);

    return [[NSArray alloc] initWithObjects:(__bridge_transfer id)certificate, nil];
}

- (SecIdentityRef)getClientCertificate {
    SecIdentityRef identityApp = nil;
    NSData* p12Bytes = [MLCCryptoManager readP12FromFile];
    if (p12Bytes == nil) {
        Log(LOG_E, @"Client certificate store is missing; cannot answer the TLS challenge");
        return nil;
    }
    CFDataRef p12Data = (__bridge CFDataRef)p12Bytes;

    CFStringRef password = CFSTR("limelight");
    const void* keys[] = { kSecImportExportPassphrase };
    const void* values[] = { password };
    CFDictionaryRef options = CFDictionaryCreate(NULL, keys, values, 1, NULL, NULL);
    CFArrayRef items = nil;
    OSStatus securityError = SecPKCS12Import(p12Data, options, &items);

    if (securityError == errSecSuccess) {
        CFDictionaryRef identityDict = CFArrayGetValueAtIndex(items, 0);
        identityApp = (SecIdentityRef)CFRetain(CFDictionaryGetValue(identityDict, kSecImportItemIdentity));
        CFRelease(items);
    } else {
        Log(LOG_E, @"Error opening Certificate.");
    }

    CFRelease(options);
    CFRelease(password);

    return identityApp;
}

- (void)URLSession:(NSURLSession*)session didReceiveChallenge:(NSURLAuthenticationChallenge*)challenge completionHandler:(nonnull void (^)(NSURLSessionAuthChallengeDisposition, NSURLCredential* __nullable))completionHandler {
    if ([challenge.protectionSpace.authenticationMethod isEqualToString:NSURLAuthenticationMethodServerTrust])
    {
        if (SecTrustGetCertificateCount(challenge.protectionSpace.serverTrust) != 1) {
            Log(LOG_E, @"Server certificate count mismatch");
            completionHandler(NSURLSessionAuthChallengePerformDefaultHandling, NULL);
            return;
        }

        SecCertificateRef actualCert = SecTrustGetCertificateAtIndex(challenge.protectionSpace.serverTrust, 0);
        if (actualCert == nil) {
            Log(LOG_E, @"Server certificate parsing error");
            completionHandler(NSURLSessionAuthChallengePerformDefaultHandling, NULL);
            return;
        }

        CFDataRef actualCertData = SecCertificateCopyData(actualCert);
        if (actualCertData == nil) {
            Log(LOG_E, @"Server certificate data parsing error");
            completionHandler(NSURLSessionAuthChallengePerformDefaultHandling, NULL);
            return;
        }

        if (_serverCert == nil) {
            Log(LOG_E, @"HTTPS request without a pinned server certificate");
            CFRelease(actualCertData);
            completionHandler(NSURLSessionAuthChallengePerformDefaultHandling, NULL);
            return;
        }

        if (!CFEqual(actualCertData, (__bridge CFDataRef)_serverCert)) {
            Log(LOG_E, @"Server certificate mismatch");
            CFRelease(actualCertData);
            completionHandler(NSURLSessionAuthChallengePerformDefaultHandling, NULL);
            return;
        }

        CFRelease(actualCertData);

        completionHandler(NSURLSessionAuthChallengeUseCredential,
                          [NSURLCredential credentialForTrust:challenge.protectionSpace.serverTrust]);
    }
    else if ([challenge.protectionSpace.authenticationMethod isEqualToString:NSURLAuthenticationMethodClientCertificate])
    {
        SecIdentityRef identity = [self getClientCertificate];
        if (identity == nil) {
            Log(LOG_E, @"Client certificate unavailable for the TLS challenge");
            completionHandler(NSURLSessionAuthChallengePerformDefaultHandling, NULL);
            return;
        }
        NSArray* certArray = [self getCertificate:identity];
        NSURLCredential* newCredential = [NSURLCredential credentialWithIdentity:identity certificates:certArray persistence:NSURLCredentialPersistencePermanent];
        CFRelease(identity);
        completionHandler(NSURLSessionAuthChallengeUseCredential, newCredential);
    }
    else
    {
        completionHandler(NSURLSessionAuthChallengePerformDefaultHandling, NULL);
    }
}

@end
