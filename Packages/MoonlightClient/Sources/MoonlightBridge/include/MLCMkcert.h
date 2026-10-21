
#ifndef MLC_MKCERT_H
#define MLC_MKCERT_H

#include <openssl/x509v3.h>
#include <openssl/pkcs12.h>

typedef struct MLCCertKeyPair {
    X509* x509;
    EVP_PKEY* pkey;
    PKCS12* p12;
} MLCCertKeyPair;

struct MLCCertKeyPair MLCGenerateCertKeyPair(void);
void MLCFreeCertKeyPair(MLCCertKeyPair certKeyPair);

#endif
