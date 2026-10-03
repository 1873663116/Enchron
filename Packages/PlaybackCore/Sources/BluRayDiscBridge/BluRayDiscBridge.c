#include "BluRayDiscBridge.h"

#include <libbluray/bluray.h>
#include <libbluray/filesystem.h>

#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <stdatomic.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

typedef struct {
    PBBlurayIOCallbacks io;
    bool local;
    bool image;
    int imageFD;
    char *root;
    atomic_bool interrupted;
} DiscSource;

typedef struct {
    PBBlurayClipInfo info;
    PBBlurayStreamInfo *streams;
} ClipRecord;

typedef struct {
    PBBlurayTitleInfo info;
    ClipRecord *clips;
} TitleRecord;

struct PBBlurayCatalog {
    DiscSource *source;
    BLURAY *disc;
    TitleRecord *titles;
    uint32_t count;
    uint8_t *metadataXML;
    int64_t metadataXMLSize;
};

struct PBBlurayReader {
    DiscSource *source;
    BLURAY *disc;
    TitleRecord title;
};

typedef struct {
    DiscSource *source;
    void *handle;
    int64_t size;
    int64_t offset;
} FileState;

typedef struct {
    DiscSource *source;
    void *handle;
} DirectoryState;

static void set_error(char *error, size_t capacity, const char *message) {
    if (error && capacity) {
        snprintf(error, capacity, "%s", message);
    }
}

static bool cancelled(const DiscSource *source) {
    return atomic_load(&source->interrupted) ||
        (source->io.isCancelled && source->io.isCancelled(source->io.context));
}

static bool safe_relative_path(const char *path) {
    if (!path) return false;
    while (*path == '/') path++;
    while (*path) {
        const char *end = strchr(path, '/');
        size_t length = end ? (size_t)(end - path) : strlen(path);
        if (length == 2 && path[0] == '.' && path[1] == '.') return false;
        if (memchr(path, '\\', length)) return false;
        if (!end) break;
        path = end + 1;
    }
    return true;
}

static char *local_path(const DiscSource *source, const char *relative) {
    if (!safe_relative_path(relative)) return NULL;
    while (*relative == '/') relative++;
    size_t rootLength = strlen(source->root);
    size_t relativeLength = strlen(relative);
    if (rootLength > SIZE_MAX - relativeLength - 2) return NULL;
    char *path = malloc(rootLength + relativeLength + 2);
    if (!path) return NULL;
    snprintf(path, rootLength + relativeLength + 2, "%s/%s", source->root, relative);
    return path;
}

typedef struct { int fd; } LocalFile;

static int64_t local_image_read(void *context, int64_t offset,
                                 uint8_t *buffer, int64_t count) {
    DiscSource *source = context;
    if (offset < 0 || count < 0 || count > SSIZE_MAX) return -1;
    return pread(source->imageFD, buffer, (size_t)count, offset);
}

static void *local_file_open(void *context, const char *relative, int64_t *size) {
    DiscSource *source = context;
    char *path = local_path(source, relative);
    if (!path) return NULL;
    int fd = open(path, O_RDONLY);
    free(path);
    if (fd < 0) return NULL;
    struct stat statBuffer;
    if (fstat(fd, &statBuffer) != 0 || !S_ISREG(statBuffer.st_mode)) {
        close(fd);
        return NULL;
    }
    LocalFile *file = malloc(sizeof(*file));
    if (!file) {
        close(fd);
        return NULL;
    }
    file->fd = fd;
    *size = statBuffer.st_size;
    return file;
}

static int64_t local_file_read(void *context, void *handle, int64_t offset,
                                uint8_t *buffer, int64_t count) {
    (void)context;
    LocalFile *file = handle;
    if (offset < 0 || count < 0 || count > SSIZE_MAX) return -1;
    return pread(file->fd, buffer, (size_t)count, offset);
}

static void local_file_close(void *context, void *handle) {
    (void)context;
    LocalFile *file = handle;
    close(file->fd);
    free(file);
}

static void *local_directory_open(void *context, const char *relative) {
    DiscSource *source = context;
    char *path = local_path(source, relative);
    if (!path) return NULL;
    DIR *directory = opendir(path);
    free(path);
    return directory;
}

static int local_directory_next(void *context, void *handle,
                                 char *name, size_t capacity) {
    (void)context;
    DIR *directory = handle;
    struct dirent *entry;
    do {
        errno = 0;
        entry = readdir(directory);
        if (!entry) return errno ? -1 : 1;
    } while (!strcmp(entry->d_name, ".") || !strcmp(entry->d_name, ".."));
    size_t length = strlen(entry->d_name);
    if (length >= capacity) return -1;
    memcpy(name, entry->d_name, length + 1);
    return 0;
}

static void local_directory_close(void *context, void *handle) {
    (void)context;
    closedir(handle);
}

static DiscSource *source_from_io(PBBlurayAccessKind kind,
                                   const PBBlurayIOCallbacks *io) {
    if (!io || !io->context) return NULL;
    if (kind == PBBlurayAccessImage && !io->imageReadAt) return NULL;
    if (kind == PBBlurayAccessFiles &&
        (!io->fileOpen || !io->fileReadAt || !io->fileClose ||
         !io->directoryOpen || !io->directoryNext || !io->directoryClose)) return NULL;
    if (kind != PBBlurayAccessImage && kind != PBBlurayAccessFiles) return NULL;
    DiscSource *source = calloc(1, sizeof(*source));
    if (!source) return NULL;
    atomic_init(&source->interrupted, false);
    source->io = *io;
    source->image = kind == PBBlurayAccessImage;
    source->imageFD = -1;
    return source;
}

static DiscSource *source_from_path(const char *path,
                                     char *error, size_t capacity) {
    if (!path) {
        set_error(error, capacity, "io: Missing disc path");
        return NULL;
    }
    struct stat statBuffer;
    if (stat(path, &statBuffer) != 0) {
        set_error(error, capacity, "io: Disc path is unavailable");
        return NULL;
    }
    DiscSource *source = calloc(1, sizeof(*source));
    if (!source) {
        set_error(error, capacity, "io: Unable to allocate disc source");
        return NULL;
    }
    atomic_init(&source->interrupted, false);
    source->local = true;
    source->imageFD = -1;
    source->io.context = source;
    if (S_ISREG(statBuffer.st_mode)) {
        source->image = true;
        source->imageFD = open(path, O_RDONLY);
        source->io.imageReadAt = local_image_read;
        if (source->imageFD < 0) {
            set_error(error, capacity, "io: Disc image cannot be opened");
            free(source);
            return NULL;
        }
    } else if (S_ISDIR(statBuffer.st_mode)) {
        source->image = false;
        source->root = strdup(path);
        if (!source->root) {
            free(source);
            set_error(error, capacity, "io: Unable to allocate disc path");
            return NULL;
        }
        size_t length = strlen(source->root);
        while (length && source->root[length - 1] == '/') source->root[--length] = 0;
        if (length >= 5 && strcmp(source->root + length - 5, "/BDMV") == 0) {
            source->root[length - 5] = 0;
        }
        source->io.fileOpen = local_file_open;
        source->io.fileReadAt = local_file_read;
        source->io.fileClose = local_file_close;
        source->io.directoryOpen = local_directory_open;
        source->io.directoryNext = local_directory_next;
        source->io.directoryClose = local_directory_close;
    } else {
        set_error(error, capacity, "unsupported: Disc source is not a file or directory");
        free(source);
        return NULL;
    }
    return source;
}

static void source_close(DiscSource *source) {
    if (!source) return;
    if (source->imageFD >= 0) close(source->imageFD);
    if (!source->local && source->io.contextClose) {
        source->io.contextClose(source->io.context);
    }
    free(source->root);
    free(source);
}

static int image_read_blocks(void *context, void *buffer, int lba, int blocks) {
    DiscSource *source = context;
    if (cancelled(source) || lba < 0 || blocks < 0 ||
        (int64_t)lba > INT64_MAX / 2048 ||
        (int64_t)blocks > INT64_MAX / 2048) return -1;
    int64_t offset = (int64_t)lba * 2048;
    int64_t wanted = (int64_t)blocks * 2048;
    int64_t received = source->io.imageReadAt(source->io.context, offset,
                                                buffer, wanted);
    if (received < 0 || received > wanted || received % 2048 != 0) return -1;
    return (int)(received / 2048);
}

static FileState *file_state(BD_FILE_H *file) { return file->internal; }

static void file_close(BD_FILE_H *file) {
    FileState *state = file_state(file);
    state->source->io.fileClose(state->source->io.context, state->handle);
    free(state);
    free(file);
}

static int64_t file_seek(BD_FILE_H *file, int64_t offset, int32_t origin) {
    FileState *state = file_state(file);
    int64_t base;
    switch (origin) {
    case SEEK_SET: base = 0; break;
    case SEEK_CUR: base = state->offset; break;
    case SEEK_END: base = state->size; break;
    default: return -1;
    }
    int64_t result;
    if (__builtin_add_overflow(base, offset, &result) || result < 0) return -1;
    state->offset = result;
    return result;
}

static int64_t file_tell(BD_FILE_H *file) { return file_state(file)->offset; }
static int file_eof(BD_FILE_H *file) {
    FileState *state = file_state(file);
    return state->offset >= state->size;
}

static int64_t file_read(BD_FILE_H *file, uint8_t *buffer, int64_t count) {
    FileState *state = file_state(file);
    if (cancelled(state->source) || count < 0) return -1;
    int64_t received = state->source->io.fileReadAt(state->source->io.context,
        state->handle, state->offset, buffer, count);
    if (received < 0 || received > count) return -1;
    state->offset += received;
    return received;
}

static BD_FILE_H *open_file(void *context, const char *relative) {
    DiscSource *source = context;
    if (cancelled(source) || !safe_relative_path(relative)) return NULL;
    int64_t size = -1;
    void *handle = source->io.fileOpen(source->io.context, relative, &size);
    if (!handle) return NULL;
    if (size < 0) {
        source->io.fileClose(source->io.context, handle);
        return NULL;
    }
    BD_FILE_H *file = calloc(1, sizeof(*file));
    FileState *state = calloc(1, sizeof(*state));
    if (!file || !state) {
        free(file);
        free(state);
        source->io.fileClose(source->io.context, handle);
        return NULL;
    }
    *state = (FileState){ .source = source, .handle = handle, .size = size };
    *file = (BD_FILE_H){ .internal = state, .close = file_close,
        .seek = file_seek, .tell = file_tell, .eof = file_eof,
        .read = file_read, .write = NULL };
    return file;
}

static DirectoryState *directory_state(BD_DIR_H *directory) {
    return directory->internal;
}

static void directory_close(BD_DIR_H *directory) {
    DirectoryState *state = directory_state(directory);
    state->source->io.directoryClose(state->source->io.context, state->handle);
    free(state);
    free(directory);
}

static int directory_read(BD_DIR_H *directory, BD_DIRENT *entry) {
    DirectoryState *state = directory_state(directory);
    if (cancelled(state->source)) return -1;
    return state->source->io.directoryNext(state->source->io.context,
        state->handle, entry->d_name, sizeof(entry->d_name));
}

static BD_DIR_H *open_directory(void *context, const char *relative) {
    DiscSource *source = context;
    if (cancelled(source) || !safe_relative_path(relative)) return NULL;
    void *handle = source->io.directoryOpen(source->io.context, relative);
    if (!handle) return NULL;
    BD_DIR_H *directory = calloc(1, sizeof(*directory));
    DirectoryState *state = calloc(1, sizeof(*state));
    if (!directory || !state) {
        free(directory);
        free(state);
        source->io.directoryClose(source->io.context, handle);
        return NULL;
    }
    *state = (DirectoryState){ .source = source, .handle = handle };
    *directory = (BD_DIR_H){ .internal = state,
        .close = directory_close, .read = directory_read };
    return directory;
}

static BLURAY *open_disc(DiscSource *source, char *error, size_t capacity) {
    BLURAY *disc = bd_init();
    if (!disc) {
        set_error(error, capacity, "io: Unable to allocate Blu-ray parser");
        return NULL;
    }
    int opened = source->image
        ? bd_open_stream(disc, source, image_read_blocks)
        : bd_open_files(disc, source, open_directory, open_file);
    if (!opened) {
        const BLURAY_DISC_INFO *info = bd_get_disc_info(disc);
        if (info && (info->aacs_detected || info->bdplus_detected)) {
            set_error(error, capacity, "encrypted: This encrypted Blu-ray disc is unsupported");
        } else if (!source->image) {
            int64_t size = -1;
            void *index = source->io.fileOpen(source->io.context,
                "BDMV/index.bdmv", &size);
            if (index) {
                source->io.fileClose(source->io.context, index);
                set_error(error, capacity, "corrupt: Blu-ray index cannot be parsed");
            } else {
                set_error(error, capacity, "unsupported: Blu-ray structure was not detected");
            }
        } else {
            set_error(error, capacity, "unsupported: Blu-ray structure was not detected");
        }
        bd_close(disc);
        return NULL;
    }
    const BLURAY_DISC_INFO *info = bd_get_disc_info(disc);
    if (info && (info->aacs_detected || info->bdplus_detected)) {
        set_error(error, capacity, "encrypted: This encrypted Blu-ray disc is unsupported");
        bd_close(disc);
        return NULL;
    }
    return disc;
}

static bool metadata_filename(const char *name) {
    if (!name || strlen(name) != 12 || memcmp(name, "bdmt_", 5) ||
        memcmp(name + 8, ".xml", 4)) return false;
    for (size_t index = 5; index < 8; index++) {
        char character = name[index];
        if (!((character >= 'a' && character <= 'z') ||
              (character >= 'A' && character <= 'Z'))) return false;
    }
    return true;
}

static uint8_t *read_metadata_xml(BLURAY *disc, int64_t *resultSize) {
    enum { MAX_METADATA_XML_SIZE = 1024 * 1024 };
    *resultSize = 0;
    BD_DIR_H *directory = bd_open_dir(disc, "BDMV/META/DL");
    if (!directory) return NULL;
    char selected[sizeof(((BD_DIRENT *)0)->d_name)] = {0};
    BD_DIRENT entry;
    while (directory->read(directory, &entry) == 0) {
        if (!metadata_filename(entry.d_name)) continue;
        if (!strcmp(entry.d_name, "bdmt_eng.xml")) {
            memcpy(selected, entry.d_name, sizeof(selected));
            break;
        }
        if (!selected[0] || strcmp(entry.d_name, selected) < 0) {
            memcpy(selected, entry.d_name, sizeof(selected));
        }
    }
    directory->close(directory);
    if (!selected[0]) return NULL;

    char path[sizeof("BDMV/META/DL/") + sizeof(selected)] = {0};
    int pathLength = snprintf(path, sizeof(path), "BDMV/META/DL/%s", selected);
    if (pathLength < 0 || (size_t)pathLength >= sizeof(path)) return NULL;
    void *data = NULL;
    int64_t size = 0;
    if (!bd_read_file(disc, path, &data, &size) || !data || size <= 0 ||
        size > MAX_METADATA_XML_SIZE) {
        free(data);
        return NULL;
    }
    *resultSize = size;
    return data;
}

static PBBlurayStreamInfo stream_info(const BLURAY_STREAM_INFO *stream,
                                      PBBlurayStreamKind kind) {
    PBBlurayStreamInfo result = {0};
    result.pid = stream->pid;
    result.codingType = stream->coding_type;
    result.kind = kind;
    result.format = stream->format;
    result.rate = stream->rate;
    memcpy(result.language, stream->lang, sizeof(result.language));
    return result;
}

static void title_free(TitleRecord *title) {
    if (!title) return;
    for (uint32_t index = 0; index < title->info.clipCount; index++) {
        free(title->clips[index].streams);
    }
    free(title->clips);
    memset(title, 0, sizeof(*title));
}

static bool title_fill(TitleRecord *record, BLURAY *disc,
                        const BLURAY_TITLE_INFO *title, bool isMain) {
    memset(record, 0, sizeof(*record));
    record->info.playlistID = title->playlist;
    record->info.duration90k = title->duration;
    record->info.clipCount = title->clip_count;
    record->info.chapterCount = title->chapter_count;
    record->info.isMain = isMain;
    record->clips = calloc(title->clip_count, sizeof(*record->clips));
    if (title->clip_count && !record->clips) return false;
    uint64_t titleSize = bd_get_title_size(disc);
    for (uint32_t index = 0; index < title->clip_count; index++) {
        const BLURAY_CLIP_INFO *clip = &title->clips[index];
        ClipRecord *out = &record->clips[index];
        memcpy(out->info.clipID, clip->clip_id, sizeof(out->info.clipID));
        out->info.startTime90k = clip->start_time;
        out->info.inTime90k = clip->in_time;
        out->info.outTime90k = clip->out_time;
        out->info.packetCount = clip->pkt_count;
        out->info.stillMode = clip->still_mode;
        out->info.stillTime = clip->still_time;
        out->info.hasInteractiveGraphics = clip->ig_stream_count > 0;
        out->info.streamCount = clip->video_stream_count + clip->audio_stream_count
            + clip->pg_stream_count;
        out->streams = calloc(out->info.streamCount, sizeof(*out->streams));
        if (out->info.streamCount && !out->streams) return false;
        uint32_t streamIndex = 0;
        for (uint32_t i = 0; i < clip->video_stream_count; i++) {
            out->streams[streamIndex++] = stream_info(&clip->video_streams[i],
                PBBlurayStreamVideo);
        }
        for (uint32_t i = 0; i < clip->audio_stream_count; i++) {
            out->streams[streamIndex++] = stream_info(&clip->audio_streams[i],
                PBBlurayStreamAudio);
        }
        for (uint32_t i = 0; i < clip->pg_stream_count; i++) {
            out->streams[streamIndex++] = stream_info(&clip->pg_streams[i],
                PBBlurayStreamSubtitle);
        }
        int64_t position = bd_seek_playitem(disc, index);
        if (position < 0) return false;
        out->info.byteStart = (uint64_t)position;
        if (index > 0) record->clips[index - 1].info.byteEnd = (uint64_t)position;
    }
    if (title->clip_count) record->clips[title->clip_count - 1].info.byteEnd = titleSize;
    bd_seek(disc, 0);
    return true;
}

static bool same_title(const TitleRecord *left, const TitleRecord *right) {
    if (left->info.duration90k != right->info.duration90k ||
        left->info.clipCount != right->info.clipCount) return false;
    for (uint32_t i = 0; i < left->info.clipCount; i++) {
        const ClipRecord *a = &left->clips[i], *b = &right->clips[i];
        if (memcmp(a->info.clipID, b->info.clipID, sizeof(a->info.clipID)) ||
            a->info.startTime90k != b->info.startTime90k ||
            a->info.inTime90k != b->info.inTime90k ||
            a->info.outTime90k != b->info.outTime90k ||
            a->info.streamCount != b->info.streamCount) return false;
        for (uint32_t stream = 0; stream < a->info.streamCount; stream++) {
            if (memcmp(&a->streams[stream], &b->streams[stream],
                       sizeof(PBBlurayStreamInfo))) return false;
        }
    }
    return true;
}

static int compare_playlist_id(const void *left, const void *right) {
    uint32_t a = ((const TitleRecord *)left)->info.playlistID;
    uint32_t b = ((const TitleRecord *)right)->info.playlistID;
    return (a > b) - (a < b);
}

static PBBlurayCatalog *catalog_open(DiscSource *source,
                                      char *error, size_t capacity) {
    BLURAY *disc = open_disc(source, error, capacity);
    if (!disc) {
        source_close(source);
        return NULL;
    }
    uint32_t rawCount = bd_get_titles(disc, TITLES_ALL, 0);
    if (!rawCount) {
        set_error(error, capacity, "corrupt: Blu-ray disc has no readable titles");
        bd_close(disc);
        source_close(source);
        return NULL;
    }
    PBBlurayCatalog *catalog = calloc(1, sizeof(*catalog));
    if (!catalog) {
        set_error(error, capacity, "io: Unable to allocate Blu-ray catalog");
        bd_close(disc);
        source_close(source);
        return NULL;
    }
    catalog->source = source;
    catalog->disc = disc;
    catalog->metadataXML = read_metadata_xml(disc, &catalog->metadataXMLSize);
    catalog->titles = calloc(rawCount, sizeof(*catalog->titles));
    if (!catalog->titles) {
        set_error(error, capacity, "io: Unable to allocate Blu-ray titles");
        PBBlurayCatalogClose(catalog);
        return NULL;
    }
    int mainIndex = bd_get_main_title(disc);
    for (uint32_t index = 0; index < rawCount; index++) {
        if (cancelled(source)) {
            set_error(error, capacity, "io: Blu-ray catalog was cancelled");
            PBBlurayCatalogClose(catalog);
            return NULL;
        }
        BLURAY_TITLE_INFO *title = bd_get_title_info(disc, index, 0);
        if (!title) continue;
        if (!title->clip_count || !bd_select_playlist(disc, title->playlist)) {
            bd_free_title_info(title);
            continue;
        }
        TitleRecord candidate;
        bool filled = title_fill(&candidate, disc, title, (int)index == mainIndex);
        bd_free_title_info(title);
        if (!filled) {
            title_free(&candidate);
            set_error(error, capacity, "corrupt: Blu-ray title metadata is inconsistent");
            PBBlurayCatalogClose(catalog);
            return NULL;
        }
        catalog->titles[catalog->count++] = candidate;
    }
    if (!catalog->count) {
        set_error(error, capacity, "corrupt: Blu-ray disc has no playable titles");
        PBBlurayCatalogClose(catalog);
        return NULL;
    }
    qsort(catalog->titles, catalog->count,
          sizeof(*catalog->titles), compare_playlist_id);
    uint32_t uniqueCount = 0;
    for (uint32_t index = 0; index < catalog->count; index++) {
        bool duplicate = false;
        for (uint32_t previous = 0; previous < uniqueCount; previous++) {
            if (same_title(&catalog->titles[previous], &catalog->titles[index])) {
                catalog->titles[previous].info.isMain |= catalog->titles[index].info.isMain;
                duplicate = true;
                break;
            }
        }
        if (duplicate) {
            title_free(&catalog->titles[index]);
        } else {
            if (uniqueCount != index) {
                catalog->titles[uniqueCount] = catalog->titles[index];
                memset(&catalog->titles[index], 0, sizeof(*catalog->titles));
            }
            uniqueCount++;
        }
    }
    catalog->count = uniqueCount;
    return catalog;
}

PBBlurayCatalog *PBBlurayCatalogOpen(const char *path,
                                      char *error, size_t capacity) {
    DiscSource *source = source_from_path(path, error, capacity);
    return source ? catalog_open(source, error, capacity) : NULL;
}

PBBlurayCatalog *PBBlurayCatalogOpenWithIO(PBBlurayAccessKind kind,
    const PBBlurayIOCallbacks *io, char *error, size_t capacity) {
    DiscSource *source = source_from_io(kind, io);
    if (!source) {
        set_error(error, capacity, "io: Invalid Blu-ray I/O callbacks");
        if (io && io->contextClose) io->contextClose(io->context);
        return NULL;
    }
    return catalog_open(source, error, capacity);
}

uint32_t PBBlurayCatalogCount(const PBBlurayCatalog *catalog) {
    return catalog ? catalog->count : 0;
}

const uint8_t *PBBlurayCatalogMetadataXML(const PBBlurayCatalog *catalog,
                                          int64_t *size) {
    if (!size) return NULL;
    *size = catalog ? catalog->metadataXMLSize : 0;
    return catalog ? catalog->metadataXML : NULL;
}

bool PBBlurayCatalogTitleAt(const PBBlurayCatalog *catalog,
    uint32_t index, PBBlurayTitleInfo *result) {
    if (!catalog || !result || index >= catalog->count) return false;
    *result = catalog->titles[index].info;
    return true;
}

bool PBBlurayCatalogClipAt(const PBBlurayCatalog *catalog,
    uint32_t titleIndex, uint32_t clipIndex, PBBlurayClipInfo *result) {
    if (!catalog || !result || titleIndex >= catalog->count ||
        clipIndex >= catalog->titles[titleIndex].info.clipCount) return false;
    *result = catalog->titles[titleIndex].clips[clipIndex].info;
    return true;
}

bool PBBlurayCatalogStreamAt(const PBBlurayCatalog *catalog,
    uint32_t titleIndex, uint32_t clipIndex, uint32_t streamIndex,
    PBBlurayStreamInfo *result) {
    if (!catalog || !result || titleIndex >= catalog->count ||
        clipIndex >= catalog->titles[titleIndex].info.clipCount ||
        streamIndex >= catalog->titles[titleIndex].clips[clipIndex].info.streamCount) return false;
    *result = catalog->titles[titleIndex].clips[clipIndex].streams[streamIndex];
    return true;
}

void PBBlurayCatalogClose(PBBlurayCatalog *catalog) {
    if (!catalog) return;
    for (uint32_t index = 0; index < catalog->count; index++) {
        title_free(&catalog->titles[index]);
    }
    free(catalog->titles);
    free(catalog->metadataXML);
    bd_close(catalog->disc);
    source_close(catalog->source);
    free(catalog);
}

static PBBlurayReader *reader_open(DiscSource *source, uint32_t playlistID,
                                    char *error, size_t capacity) {
    BLURAY *disc = open_disc(source, error, capacity);
    if (!disc) {
        source_close(source);
        return NULL;
    }
    bd_get_titles(disc, TITLES_ALL, 0);
    BLURAY_TITLE_INFO *title = bd_get_playlist_info(disc, playlistID, 0);
    if (!title || !title->clip_count || !bd_select_playlist(disc, playlistID)) {
        set_error(error, capacity, "unsupported: Blu-ray playlist is unavailable");
        if (title) bd_free_title_info(title);
        bd_close(disc);
        source_close(source);
        return NULL;
    }
    PBBlurayReader *reader = calloc(1, sizeof(*reader));
    if (!reader) {
        set_error(error, capacity, "io: Unable to allocate Blu-ray reader");
        bd_free_title_info(title);
        bd_close(disc);
        source_close(source);
        return NULL;
    }
    reader->source = source;
    reader->disc = disc;
    bool filled = title_fill(&reader->title, disc, title, false);
    bd_free_title_info(title);
    if (!filled) {
        set_error(error, capacity, "corrupt: Blu-ray playlist metadata is inconsistent");
        PBBlurayClose(reader);
        return NULL;
    }
    return reader;
}

PBBlurayReader *PBBlurayOpen(const char *path, uint32_t playlistID,
                              char *error, size_t capacity) {
    DiscSource *source = source_from_path(path, error, capacity);
    return source ? reader_open(source, playlistID, error, capacity) : NULL;
}

PBBlurayReader *PBBlurayOpenWithIO(PBBlurayAccessKind kind,
    const PBBlurayIOCallbacks *io, uint32_t playlistID,
    char *error, size_t capacity) {
    DiscSource *source = source_from_io(kind, io);
    if (!source) {
        set_error(error, capacity, "io: Invalid Blu-ray I/O callbacks");
        if (io && io->contextClose) io->contextClose(io->context);
        return NULL;
    }
    return reader_open(source, playlistID, error, capacity);
}

int PBBlurayRead(PBBlurayReader *reader, uint8_t *buffer, int count) {
    if (!reader || !buffer || count < 0 || cancelled(reader->source)) return -1;
    return bd_read(reader->disc, buffer, count);
}

int64_t PBBluraySeekBytes(PBBlurayReader *reader, uint64_t offset) {
    if (!reader || cancelled(reader->source) || offset > PBBluraySize(reader)) return -1;
    return bd_seek(reader->disc, offset);
}

int64_t PBBluraySeekTime(PBBlurayReader *reader, uint64_t time90k) {
    if (!reader || cancelled(reader->source) || time90k > PBBlurayDuration(reader)) return -1;
    return bd_seek_time(reader->disc, time90k);
}

uint64_t PBBlurayTell(const PBBlurayReader *reader) {
    return reader ? bd_tell(reader->disc) : 0;
}

uint64_t PBBluraySize(const PBBlurayReader *reader) {
    return reader ? bd_get_title_size(reader->disc) : 0;
}

uint64_t PBBlurayDuration(const PBBlurayReader *reader) {
    return reader ? reader->title.info.duration90k : 0;
}

uint32_t PBBlurayReaderClipCount(const PBBlurayReader *reader) {
    return reader ? reader->title.info.clipCount : 0;
}

bool PBBlurayReaderClipAt(const PBBlurayReader *reader,
    uint32_t clipIndex, PBBlurayClipInfo *result) {
    if (!reader || !result || clipIndex >= reader->title.info.clipCount) return false;
    *result = reader->title.clips[clipIndex].info;
    return true;
}

bool PBBlurayReaderStreamAt(const PBBlurayReader *reader,
    uint32_t clipIndex, uint32_t streamIndex, PBBlurayStreamInfo *result) {
    if (!reader || !result || clipIndex >= reader->title.info.clipCount ||
        streamIndex >= reader->title.clips[clipIndex].info.streamCount) return false;
    *result = reader->title.clips[clipIndex].streams[streamIndex];
    return true;
}

void PBBlurayReaderSetInterrupted(PBBlurayReader *reader, bool interrupted) {
    if (!reader) return;
    atomic_store(&reader->source->interrupted, interrupted);
    if (reader->source->io.setInterrupted) {
        reader->source->io.setInterrupted(reader->source->io.context, interrupted);
    }
}

void PBBlurayClose(PBBlurayReader *reader) {
    if (!reader) return;
    title_free(&reader->title);
    bd_close(reader->disc);
    source_close(reader->source);
    free(reader);
}
