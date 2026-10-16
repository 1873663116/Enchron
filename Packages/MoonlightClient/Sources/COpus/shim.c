#include <opus/opus.h>

// Link anchor for the vendored libopus slice.
int enchron_opus_link_anchor(void) {
    return opus_get_version_string() != 0;
}
