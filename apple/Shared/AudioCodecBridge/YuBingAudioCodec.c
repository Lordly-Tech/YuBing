#include "YuBingAudioCodec.h"

#include <FFmpeg.h>
#include <stdio.h>
#include <string.h>

static void yubing_error(char *buffer, int32_t capacity, int code, const char *context) {
    if (buffer == NULL || capacity <= 0) {
        return;
    }
    char detail[AV_ERROR_MAX_STRING_SIZE] = {0};
    av_strerror(code, detail, sizeof(detail));
    snprintf(buffer, (size_t)capacity, "%s: %s", context, detail);
}

static const char *yubing_metadata_value(
    AVDictionary *container_metadata,
    AVDictionary *stream_metadata,
    const char *const *keys,
    size_t key_count
) {
    for (size_t index = 0; index < key_count; index++) {
        AVDictionaryEntry *entry = av_dict_get(container_metadata, keys[index], NULL, 0);
        if (entry == NULL) {
            entry = av_dict_get(stream_metadata, keys[index], NULL, 0);
        }
        if (entry != NULL && entry->value != NULL && entry->value[0] != '\0') {
            return entry->value;
        }
    }
    return NULL;
}

static char *yubing_copy_metadata_value(
    AVDictionary *container_metadata,
    AVDictionary *stream_metadata,
    const char *const *keys,
    size_t key_count
) {
    const char *value = yubing_metadata_value(
        container_metadata,
        stream_metadata,
        keys,
        key_count
    );
    return value == NULL ? NULL : av_strdup(value);
}

void yubing_free_audio_metadata(YuBingAudioMetadata *metadata) {
    if (metadata == NULL) {
        return;
    }
    av_freep(&metadata->title);
    av_freep(&metadata->artist);
    av_freep(&metadata->album);
    av_freep(&metadata->album_artist);
    av_freep(&metadata->genre);
    av_freep(&metadata->date);
    av_freep(&metadata->track_number);
    av_freep(&metadata->disc_number);
    av_freep(&metadata->lyrics);
    av_freep(&metadata->codec);
    av_freep(&metadata->artwork_data);
    memset(metadata, 0, sizeof(*metadata));
}

int32_t yubing_read_audio_metadata(
    const char *input_path,
    YuBingAudioMetadata *metadata,
    char *error_buffer,
    int32_t error_capacity
) {
    if (input_path == NULL || metadata == NULL) {
        return AVERROR(EINVAL);
    }
    memset(metadata, 0, sizeof(*metadata));

    AVFormatContext *input = NULL;
    int result = avformat_open_input(&input, input_path, NULL, NULL);
    if (result < 0) {
        yubing_error(error_buffer, error_capacity, result, "Unable to open audio metadata");
        return result;
    }
    result = avformat_find_stream_info(input, NULL);
    if (result < 0) {
        yubing_error(error_buffer, error_capacity, result, "Unable to read audio metadata");
        avformat_close_input(&input);
        return result;
    }

    const int audio_index = av_find_best_stream(input, AVMEDIA_TYPE_AUDIO, -1, -1, NULL, 0);
    if (audio_index < 0) {
        yubing_error(error_buffer, error_capacity, audio_index, "No audio stream");
        avformat_close_input(&input);
        return audio_index;
    }
    AVStream *audio_stream = input->streams[audio_index];
    AVCodecParameters *codec = audio_stream->codecpar;
    AVDictionary *container_metadata = input->metadata;
    AVDictionary *stream_metadata = audio_stream->metadata;

    const char *title_keys[] = {"title"};
    const char *artist_keys[] = {"artist", "performer", "album_artist", "albumartist"};
    const char *album_keys[] = {"album", "WM/AlbumTitle"};
    const char *album_artist_keys[] = {"album_artist", "albumartist", "WM/AlbumArtist"};
    const char *genre_keys[] = {"genre", "WM/Genre"};
    const char *date_keys[] = {"date", "year", "originaldate", "WM/Year"};
    const char *track_keys[] = {"track", "tracknumber", "WM/TrackNumber"};
    const char *disc_keys[] = {"disc", "discnumber", "disk"};
    const char *lyrics_keys[] = {
        "lyrics", "syncedlyrics", "unsyncedlyrics", "unsynchronizedlyrics", "WM/Lyrics"
    };

#define YUBING_KEY_COUNT(keys) (sizeof(keys) / sizeof((keys)[0]))
    metadata->title = yubing_copy_metadata_value(
        container_metadata, stream_metadata, title_keys, YUBING_KEY_COUNT(title_keys)
    );
    metadata->artist = yubing_copy_metadata_value(
        container_metadata, stream_metadata, artist_keys, YUBING_KEY_COUNT(artist_keys)
    );
    metadata->album = yubing_copy_metadata_value(
        container_metadata, stream_metadata, album_keys, YUBING_KEY_COUNT(album_keys)
    );
    metadata->album_artist = yubing_copy_metadata_value(
        container_metadata, stream_metadata, album_artist_keys, YUBING_KEY_COUNT(album_artist_keys)
    );
    metadata->genre = yubing_copy_metadata_value(
        container_metadata, stream_metadata, genre_keys, YUBING_KEY_COUNT(genre_keys)
    );
    metadata->date = yubing_copy_metadata_value(
        container_metadata, stream_metadata, date_keys, YUBING_KEY_COUNT(date_keys)
    );
    metadata->track_number = yubing_copy_metadata_value(
        container_metadata, stream_metadata, track_keys, YUBING_KEY_COUNT(track_keys)
    );
    metadata->disc_number = yubing_copy_metadata_value(
        container_metadata, stream_metadata, disc_keys, YUBING_KEY_COUNT(disc_keys)
    );
    metadata->lyrics = yubing_copy_metadata_value(
        container_metadata, stream_metadata, lyrics_keys, YUBING_KEY_COUNT(lyrics_keys)
    );
#undef YUBING_KEY_COUNT

    const char *codec_name = avcodec_get_name(codec->codec_id);
    metadata->codec = codec_name == NULL ? NULL : av_strdup(codec_name);
    metadata->sample_rate = codec->sample_rate;
    metadata->bit_depth = codec->bits_per_raw_sample > 0
        ? codec->bits_per_raw_sample
        : codec->bits_per_coded_sample;
    if (metadata->bit_depth <= 0) {
        metadata->bit_depth = av_get_bits_per_sample(codec->codec_id);
    }
    const AVCodecDescriptor *descriptor = avcodec_descriptor_get(codec->codec_id);
    metadata->is_lossless = descriptor != NULL &&
        (descriptor->props & AV_CODEC_PROP_LOSSLESS) != 0;

    for (unsigned int index = 0; index < input->nb_streams; index++) {
        AVStream *stream = input->streams[index];
        AVPacket *picture = &stream->attached_pic;
        if ((stream->disposition & AV_DISPOSITION_ATTACHED_PIC) == 0 ||
            picture->data == NULL || picture->size <= 0) {
            continue;
        }
        metadata->artwork_data = av_malloc((size_t)picture->size);
        if (metadata->artwork_data != NULL) {
            memcpy(metadata->artwork_data, picture->data, (size_t)picture->size);
            metadata->artwork_size = picture->size;
        }
        break;
    }

    avformat_close_input(&input);
    return 0;
}

static int yubing_write_packets(
    AVFormatContext *output,
    AVCodecContext *encoder,
    AVStream *stream,
    AVFrame *frame
) {
    int result = avcodec_send_frame(encoder, frame);
    if (result < 0) {
        return result;
    }

    AVPacket *packet = av_packet_alloc();
    if (packet == NULL) {
        return AVERROR(ENOMEM);
    }
    while ((result = avcodec_receive_packet(encoder, packet)) >= 0) {
        av_packet_rescale_ts(packet, encoder->time_base, stream->time_base);
        packet->stream_index = stream->index;
        result = av_interleaved_write_frame(output, packet);
        av_packet_unref(packet);
        if (result < 0) {
            av_packet_free(&packet);
            return result;
        }
    }
    av_packet_free(&packet);
    return result == AVERROR(EAGAIN) || result == AVERROR_EOF ? 0 : result;
}

static int yubing_convert_frame(
    AVFrame *input,
    SwrContext *resampler,
    AVFormatContext *output,
    AVCodecContext *encoder,
    AVStream *stream,
    int64_t *sample_cursor
) {
    int64_t delay = swr_get_delay(resampler, input->sample_rate);
    int output_capacity = (int)av_rescale_rnd(
        delay + input->nb_samples,
        encoder->sample_rate,
        input->sample_rate,
        AV_ROUND_UP
    );
    AVFrame *converted = av_frame_alloc();
    if (converted == NULL) {
        return AVERROR(ENOMEM);
    }
    converted->format = encoder->sample_fmt;
    converted->sample_rate = encoder->sample_rate;
    converted->nb_samples = output_capacity;
    converted->ch_layout = encoder->ch_layout;
    int result = av_frame_get_buffer(converted, 0);
    if (result < 0) {
        av_frame_free(&converted);
        return result;
    }

    result = swr_convert(
        resampler,
        converted->extended_data,
        output_capacity,
        (const uint8_t **)input->extended_data,
        input->nb_samples
    );
    if (result < 0) {
        av_frame_free(&converted);
        return result;
    }
    converted->nb_samples = result;
    converted->pts = *sample_cursor;
    *sample_cursor += result;
    result = result > 0 ? yubing_write_packets(output, encoder, stream, converted) : 0;
    av_frame_free(&converted);
    return result;
}

int32_t yubing_transcode_to_alac(
    const char *input_path,
    const char *output_path,
    char *error_buffer,
    int32_t error_capacity
) {
    AVFormatContext *input = NULL;
    AVFormatContext *output = NULL;
    AVCodecContext *decoder = NULL;
    AVCodecContext *encoder = NULL;
    SwrContext *resampler = NULL;
    AVPacket *packet = NULL;
    AVFrame *frame = NULL;
    AVStream *input_stream = NULL;
    AVStream *output_stream = NULL;
    int audio_index = -1;
    int result = 0;
    int header_written = 0;
    int64_t sample_cursor = 0;

    result = avformat_open_input(&input, input_path, NULL, NULL);
    if (result < 0) {
        yubing_error(error_buffer, error_capacity, result, "Unable to open input");
        goto cleanup;
    }
    result = avformat_find_stream_info(input, NULL);
    if (result < 0) {
        yubing_error(error_buffer, error_capacity, result, "Unable to read stream info");
        goto cleanup;
    }
    audio_index = av_find_best_stream(input, AVMEDIA_TYPE_AUDIO, -1, -1, NULL, 0);
    if (audio_index < 0) {
        result = audio_index;
        yubing_error(error_buffer, error_capacity, result, "No audio stream");
        goto cleanup;
    }
    input_stream = input->streams[audio_index];
    const AVCodec *decoder_codec = avcodec_find_decoder(input_stream->codecpar->codec_id);
    if (decoder_codec == NULL) {
        result = AVERROR_DECODER_NOT_FOUND;
        yubing_error(error_buffer, error_capacity, result, "Decoder unavailable");
        goto cleanup;
    }
    decoder = avcodec_alloc_context3(decoder_codec);
    if (decoder == NULL) {
        result = AVERROR(ENOMEM);
        goto cleanup;
    }
    result = avcodec_parameters_to_context(decoder, input_stream->codecpar);
    if (result < 0 || (result = avcodec_open2(decoder, decoder_codec, NULL)) < 0) {
        yubing_error(error_buffer, error_capacity, result, "Unable to open decoder");
        goto cleanup;
    }

    result = avformat_alloc_output_context2(&output, NULL, "ipod", output_path);
    if (result < 0 || output == NULL) {
        yubing_error(error_buffer, error_capacity, result, "Unable to create M4A output");
        goto cleanup;
    }
    const AVCodec *encoder_codec = avcodec_find_encoder(AV_CODEC_ID_ALAC);
    if (encoder_codec == NULL) {
        result = AVERROR_ENCODER_NOT_FOUND;
        yubing_error(error_buffer, error_capacity, result, "ALAC encoder unavailable");
        goto cleanup;
    }
    output_stream = avformat_new_stream(output, encoder_codec);
    encoder = avcodec_alloc_context3(encoder_codec);
    if (output_stream == NULL || encoder == NULL) {
        result = AVERROR(ENOMEM);
        goto cleanup;
    }

    encoder->sample_rate = decoder->sample_rate > 0 ? decoder->sample_rate : 44100;
    if (encoder->sample_rate > 192000) {
        encoder->sample_rate = 192000;
    }
    encoder->sample_fmt = AV_SAMPLE_FMT_S32P;
    if (encoder_codec->sample_fmts != NULL) {
        encoder->sample_fmt = encoder_codec->sample_fmts[0];
    }
    if (decoder->ch_layout.nb_channels > 0 && decoder->ch_layout.nb_channels <= 2) {
        av_channel_layout_copy(&encoder->ch_layout, &decoder->ch_layout);
    } else {
        av_channel_layout_default(&encoder->ch_layout, 2);
    }
    encoder->time_base = (AVRational){1, encoder->sample_rate};
    encoder->bits_per_raw_sample = decoder->bits_per_raw_sample > 0 ? decoder->bits_per_raw_sample : 24;
    if (output->oformat->flags & AVFMT_GLOBALHEADER) {
        encoder->flags |= AV_CODEC_FLAG_GLOBAL_HEADER;
    }
    result = avcodec_open2(encoder, encoder_codec, NULL);
    if (result < 0) {
        yubing_error(error_buffer, error_capacity, result, "Unable to open ALAC encoder");
        goto cleanup;
    }
    result = avcodec_parameters_from_context(output_stream->codecpar, encoder);
    if (result < 0) {
        goto cleanup;
    }
    output_stream->time_base = encoder->time_base;
    av_dict_copy(&output->metadata, input->metadata, 0);
    av_dict_copy(&output_stream->metadata, input_stream->metadata, 0);

    AVChannelLayout decoder_layout = decoder->ch_layout;
    if (decoder_layout.nb_channels <= 0) {
        av_channel_layout_default(&decoder_layout, 2);
    }
    result = swr_alloc_set_opts2(
        &resampler,
        &encoder->ch_layout,
        encoder->sample_fmt,
        encoder->sample_rate,
        &decoder_layout,
        decoder->sample_fmt,
        decoder->sample_rate,
        0,
        NULL
    );
    if (result < 0 || (result = swr_init(resampler)) < 0) {
        yubing_error(error_buffer, error_capacity, result, "Unable to create lossless converter");
        goto cleanup;
    }
    if (!(output->oformat->flags & AVFMT_NOFILE)) {
        result = avio_open(&output->pb, output_path, AVIO_FLAG_WRITE);
        if (result < 0) {
            yubing_error(error_buffer, error_capacity, result, "Unable to create output file");
            goto cleanup;
        }
    }
    result = avformat_write_header(output, NULL);
    if (result < 0) {
        yubing_error(error_buffer, error_capacity, result, "Unable to write M4A header");
        goto cleanup;
    }
    header_written = 1;
    packet = av_packet_alloc();
    frame = av_frame_alloc();
    if (packet == NULL || frame == NULL) {
        result = AVERROR(ENOMEM);
        goto cleanup;
    }

    while ((result = av_read_frame(input, packet)) >= 0) {
        if (packet->stream_index == audio_index) {
            result = avcodec_send_packet(decoder, packet);
            av_packet_unref(packet);
            if (result < 0) {
                goto cleanup;
            }
            while ((result = avcodec_receive_frame(decoder, frame)) >= 0) {
                result = yubing_convert_frame(
                    frame,
                    resampler,
                    output,
                    encoder,
                    output_stream,
                    &sample_cursor
                );
                av_frame_unref(frame);
                if (result < 0) {
                    goto cleanup;
                }
            }
            if (result != AVERROR(EAGAIN) && result != AVERROR_EOF) {
                goto cleanup;
            }
        } else {
            av_packet_unref(packet);
        }
    }
    if (result != AVERROR_EOF) {
        goto cleanup;
    }

    result = avcodec_send_packet(decoder, NULL);
    if (result >= 0) {
        while ((result = avcodec_receive_frame(decoder, frame)) >= 0) {
            result = yubing_convert_frame(
                frame,
                resampler,
                output,
                encoder,
                output_stream,
                &sample_cursor
            );
            av_frame_unref(frame);
            if (result < 0) {
                goto cleanup;
            }
        }
    }
    if (result == AVERROR(EAGAIN) || result == AVERROR_EOF) {
        result = yubing_write_packets(output, encoder, output_stream, NULL);
    }
    if (result >= 0) {
        result = av_write_trailer(output);
    }
    if (result < 0) {
        yubing_error(error_buffer, error_capacity, result, "Lossless conversion failed");
    }

cleanup:
    if (packet != NULL) av_packet_free(&packet);
    if (frame != NULL) av_frame_free(&frame);
    if (resampler != NULL) swr_free(&resampler);
    if (decoder != NULL) avcodec_free_context(&decoder);
    if (encoder != NULL) avcodec_free_context(&encoder);
    if (input != NULL) avformat_close_input(&input);
    if (output != NULL) {
        if (header_written && result < 0) {
            av_write_trailer(output);
        }
        if (!(output->oformat->flags & AVFMT_NOFILE) && output->pb != NULL) {
            avio_closep(&output->pb);
        }
        avformat_free_context(output);
    }
    return result < 0 ? (int32_t)result : 0;
}
