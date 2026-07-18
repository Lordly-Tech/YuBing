#ifndef YUBING_AUDIO_CODEC_H
#define YUBING_AUDIO_CODEC_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

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
