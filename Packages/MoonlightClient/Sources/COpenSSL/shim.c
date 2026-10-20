#include <openssl/opensslv.h>

// Link and header smoke anchor for the vendored OpenSSL slice.
unsigned long enchron_openssl_version_number(void) {
    return OPENSSL_VERSION_NUMBER;
}
