#ifndef YUBING_AUDIO_CODEC_H
#define YUBING_AUDIO_CODEC_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct {
    char *title;
    char *artist;
    char *album;
    char *album_artist;
    char *genre;
    char *date;
    char *track_number;
    char *disc_number;
    char *lyrics;
    char *codec;
    int32_t sample_rate;
    int32_t bit_depth;
    int32_t is_lossless;
    uint8_t *artwork_data;
    int64_t artwork_size;
} YuBingAudioMetadata;

int32_t yubing_read_audio_metadata(
    const char *input_path,
    YuBingAudioMetadata *metadata,
    char *error_buffer,
    int32_t error_capacity
);

void yubing_free_audio_metadata(YuBingAudioMetadata *metadata);

int32_t yubing_transcode_to_alac(
    const char *input_path,
    const char *output_path,
    char *error_buffer,
    int32_t error_capacity
);

#ifdef __cplusplus
}
#endif

#endif
