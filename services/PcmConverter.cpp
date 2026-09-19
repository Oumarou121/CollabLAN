#include "PcmConverter.h"

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <cstring>

namespace services::pcm {

namespace {

constexpr std::uint16_t kFormatPcm = 1;
constexpr std::uint16_t kFormatFloat = 3;
constexpr std::uint16_t kFormatExtensible = 0xFFFE;

std::uint16_t readU16(const unsigned char *p)
{
    return static_cast<std::uint16_t>(p[0] | (p[1] << 8));
}

std::uint32_t readU32(const unsigned char *p)
{
    return static_cast<std::uint32_t>(p[0])
         | (static_cast<std::uint32_t>(p[1]) << 8)
         | (static_cast<std::uint32_t>(p[2]) << 16)
         | (static_cast<std::uint32_t>(p[3]) << 24);
}

bool fail(std::string *error, const char *message)
{
    if (error)
        *error = message;
    return false;
}

float clampUnit(float v)
{
    return std::max(-1.0f, std::min(1.0f, v));
}

} // namespace

bool decodeWav(const unsigned char *data, std::size_t size, Clip &out, std::string *error)
{
    out = Clip{};

    if (!data || size < 12)
        return fail(error, "fichier trop court");
    if (std::memcmp(data, "RIFF", 4) != 0 || std::memcmp(data + 8, "WAVE", 4) != 0)
        return fail(error, "en-tete RIFF/WAVE absent");

    std::uint16_t formatTag = 0;
    std::uint16_t channels = 0;
    std::uint32_t sampleRate = 0;
    std::uint16_t bitsPerSample = 0;
    bool haveFmt = false;

    const unsigned char *pcmData = nullptr;
    std::size_t pcmSize = 0;

    std::size_t pos = 12;
    while (pos + 8 <= size) {
        const unsigned char *chunk = data + pos;
        const std::size_t chunkSize = readU32(chunk + 4);
        const std::size_t bodyPos = pos + 8;
        // La taille declaree peut depasser le fichier (en-tete tronque ou
        // 0xFFFFFFFF pour un flux) : on la borne a ce qui est reellement la.
        const std::size_t available = size - bodyPos;
        const std::size_t bodySize = std::min(chunkSize, available);

        if (std::memcmp(chunk, "fmt ", 4) == 0) {
            if (bodySize < 16)
                return fail(error, "bloc fmt trop court");
            const unsigned char *f = data + bodyPos;
            formatTag = readU16(f);
            channels = readU16(f + 2);
            sampleRate = readU32(f + 4);
            bitsPerSample = readU16(f + 14);
            if (formatTag == kFormatExtensible) {
                // cbSize(2) validBits(2) channelMask(4) puis GUID dont les 2
                // premiers octets reprennent le vrai code de format.
                if (bodySize < 26)
                    return fail(error, "bloc fmt extensible trop court");
                formatTag = readU16(f + 24);
            }
            haveFmt = true;
        } else if (std::memcmp(chunk, "data", 4) == 0) {
            pcmData = data + bodyPos;
            pcmSize = bodySize;
            break; // les blocs apres "data" ne nous interessent pas
        }

        // Les blocs RIFF sont alignes sur 2 octets.
        pos = bodyPos + chunkSize + (chunkSize & 1u);
        if (chunkSize > available)
            break;
    }

    if (!haveFmt)
        return fail(error, "bloc fmt absent");
    if (!pcmData)
        return fail(error, "bloc data absent");
    if (channels == 0 || sampleRate == 0)
        return fail(error, "canaux ou frequence invalides");

    const bool isPcm = (formatTag == kFormatPcm)
        && (bitsPerSample == 8 || bitsPerSample == 16 || bitsPerSample == 24 || bitsPerSample == 32);
    const bool isFloat = (formatTag == kFormatFloat) && bitsPerSample == 32;
    if (!isPcm && !isFloat)
        return fail(error, "format WAV non pris en charge (PCM 8/16/24/32 bits ou float 32 bits attendu)");

    const std::size_t bytesPerSample = bitsPerSample / 8u;
    const std::size_t frameBytes = bytesPerSample * channels;
    const std::size_t frameCount = pcmSize / frameBytes;
    if (frameCount == 0)
        return fail(error, "aucun echantillon");

    out.sampleRate = static_cast<int>(sampleRate);
    out.channels = channels;
    out.samples.resize(frameCount * channels);

    const unsigned char *src = pcmData;
    for (std::size_t i = 0; i < out.samples.size(); ++i, src += bytesPerSample) {
        float v = 0.0f;
        if (isFloat) {
            std::uint32_t raw = readU32(src);
            float f;
            std::memcpy(&f, &raw, sizeof(f));
            v = f;
        } else if (bitsPerSample == 8) {
            v = (static_cast<int>(src[0]) - 128) / 128.0f; // 8 bits : non signe
        } else if (bitsPerSample == 16) {
            v = static_cast<std::int16_t>(readU16(src)) / 32768.0f;
        } else if (bitsPerSample == 24) {
            std::int32_t s = static_cast<std::int32_t>(src[0] | (src[1] << 8) | (src[2] << 16));
            if (s & 0x800000)
                s |= ~0xFFFFFF; // extension de signe
            v = s / 8388608.0f;
        } else { // 32 bits entiers
            v = static_cast<std::int32_t>(readU32(src)) / 2147483648.0f;
        }
        out.samples[i] = clampUnit(v);
    }
    return true;
}

std::vector<unsigned char> convertClip(const Clip &clip, const OutputFormat &format, int tailSilenceMs)
{
    if (clip.sampleRate <= 0 || clip.channels <= 0 || clip.frames() == 0
        || format.sampleRate <= 0 || format.channels <= 0)
        return {};

    const std::size_t srcFrames = clip.frames();
    const int srcChannels = clip.channels;

    // 1) Reduction a deux "voies" (gauche/droite) ou une seule (mono cible).
    std::vector<float> laneL(srcFrames);
    std::vector<float> laneR(srcFrames);
    const bool monoTarget = (format.channels == 1);
    for (std::size_t i = 0; i < srcFrames; ++i) {
        const float *frame = &clip.samples[i * srcChannels];
        const float left = frame[0];
        const float right = srcChannels >= 2 ? frame[1] : frame[0];
        if (monoTarget) {
            float sum = 0.0f;
            for (int c = 0; c < srcChannels; ++c)
                sum += frame[c];
            laneL[i] = sum / static_cast<float>(srcChannels);
            laneR[i] = laneL[i];
        } else {
            laneL[i] = left;
            laneR[i] = right;
        }
    }

    // 2) Reechantillonnage lineaire vers la frequence cible.
    std::size_t dstFrames = srcFrames;
    if (clip.sampleRate != format.sampleRate) {
        const double ratio = static_cast<double>(format.sampleRate) / clip.sampleRate;
        dstFrames = std::max<std::size_t>(1, static_cast<std::size_t>(std::llround(srcFrames * ratio)));
        std::vector<float> outL(dstFrames);
        std::vector<float> outR(dstFrames);
        const double step = static_cast<double>(clip.sampleRate) / format.sampleRate;
        for (std::size_t i = 0; i < dstFrames; ++i) {
            const double srcPos = i * step;
            std::size_t i0 = static_cast<std::size_t>(srcPos);
            if (i0 >= srcFrames)
                i0 = srcFrames - 1;
            const std::size_t i1 = std::min(i0 + 1, srcFrames - 1);
            const float frac = static_cast<float>(srcPos - static_cast<double>(i0));
            outL[i] = laneL[i0] + (laneL[i1] - laneL[i0]) * frac;
            outR[i] = laneR[i0] + (laneR[i1] - laneR[i0]) * frac;
        }
        laneL.swap(outL);
        laneR.swap(outR);
    }

    // 3) Silence final.
    const std::size_t tailFrames = tailSilenceMs > 0
        ? static_cast<std::size_t>(static_cast<double>(format.sampleRate) * tailSilenceMs / 1000.0)
        : 0;
    const std::size_t totalFrames = dstFrames + tailFrames;

    // 4) Placement dans les canaux cibles + encodage.
    std::size_t bytesPerSample = 0;
    switch (format.sampleType) {
    case SampleType::UInt8: bytesPerSample = 1; break;
    case SampleType::Int16: bytesPerSample = 2; break;
    case SampleType::Int32: bytesPerSample = 4; break;
    case SampleType::Float: bytesPerSample = 4; break;
    }
    if (bytesPerSample == 0)
        return {};

    std::vector<unsigned char> out(totalFrames * static_cast<std::size_t>(format.channels) * bytesPerSample, 0);
    // UInt8 : le silence est 128, pas 0.
    if (format.sampleType == SampleType::UInt8)
        std::fill(out.begin(), out.end(), static_cast<unsigned char>(128));

    unsigned char *dst = out.data();
    for (std::size_t i = 0; i < totalFrames; ++i) {
        for (int c = 0; c < format.channels; ++c, dst += bytesPerSample) {
            float v = 0.0f;
            if (i < dstFrames) {
                if (monoTarget || c == 0)
                    v = laneL[i];
                else if (c == 1)
                    v = laneR[i];
                // canaux >= 2 : silence
            }
            v = clampUnit(v);

            switch (format.sampleType) {
            case SampleType::UInt8: {
                const int s = static_cast<int>(std::lround(v * 127.0f)) + 128;
                dst[0] = static_cast<unsigned char>(std::max(0, std::min(255, s)));
                break;
            }
            case SampleType::Int16: {
                const std::int16_t s = static_cast<std::int16_t>(std::lround(v * 32767.0f));
                std::memcpy(dst, &s, sizeof(s));
                break;
            }
            case SampleType::Int32: {
                const std::int32_t s = static_cast<std::int32_t>(std::llround(static_cast<double>(v) * 2147483647.0));
                std::memcpy(dst, &s, sizeof(s));
                break;
            }
            case SampleType::Float:
                std::memcpy(dst, &v, sizeof(v));
                break;
            }
        }
    }
    return out;
}

} // namespace services::pcm
