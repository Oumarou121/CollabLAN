// Test autonome (aucune dependance a Qt) de services/PcmConverter : decodage
// WAV et conversion vers un format de peripherique. Retourne 0 si tout passe.
#include "PcmConverter.h"

#include <cmath>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <string>
#include <vector>

using namespace services::pcm;

namespace {

int g_failures = 0;

#define CHECK(cond)                                                                \
    do {                                                                           \
        if (!(cond)) {                                                             \
            std::printf("ECHEC %s:%d : %s\n", __FILE__, __LINE__, #cond);          \
            ++g_failures;                                                          \
        }                                                                          \
    } while (0)

void put16(std::vector<unsigned char> &v, std::uint16_t x)
{
    v.push_back(static_cast<unsigned char>(x & 0xFF));
    v.push_back(static_cast<unsigned char>(x >> 8));
}

void put32(std::vector<unsigned char> &v, std::uint32_t x)
{
    put16(v, static_cast<std::uint16_t>(x & 0xFFFF));
    put16(v, static_cast<std::uint16_t>(x >> 16));
}

void putTag(std::vector<unsigned char> &v, const char *tag)
{
    for (int i = 0; i < 4; ++i)
        v.push_back(static_cast<unsigned char>(tag[i]));
}

// WAV PCM 16 bits, canaux entrelaces fournis par l'appelant.
std::vector<unsigned char> makeWav16(int rate, int channels, const std::vector<std::int16_t> &samples)
{
    std::vector<unsigned char> wav;
    const std::uint32_t dataBytes = static_cast<std::uint32_t>(samples.size() * 2);
    putTag(wav, "RIFF");
    put32(wav, 36 + dataBytes);
    putTag(wav, "WAVE");
    putTag(wav, "fmt ");
    put32(wav, 16);
    put16(wav, 1); // PCM
    put16(wav, static_cast<std::uint16_t>(channels));
    put32(wav, static_cast<std::uint32_t>(rate));
    put32(wav, static_cast<std::uint32_t>(rate * channels * 2));
    put16(wav, static_cast<std::uint16_t>(channels * 2));
    put16(wav, 16);
    putTag(wav, "data");
    put32(wav, dataBytes);
    for (std::int16_t s : samples)
        put16(wav, static_cast<std::uint16_t>(s));
    return wav;
}

std::vector<std::int16_t> sine(int rate, double freq, int frames, double amplitude = 0.5)
{
    std::vector<std::int16_t> out(static_cast<std::size_t>(frames));
    for (int i = 0; i < frames; ++i)
        out[static_cast<std::size_t>(i)] = static_cast<std::int16_t>(
            std::lround(amplitude * 32767.0 * std::sin(2.0 * 3.14159265358979323846 * freq * i / rate)));
    return out;
}

std::int16_t at16(const std::vector<unsigned char> &b, std::size_t sampleIndex)
{
    std::int16_t v;
    std::memcpy(&v, &b[sampleIndex * 2], 2);
    return v;
}

int zeroCrossings(const std::vector<unsigned char> &pcm16, int channels, int channel)
{
    const std::size_t frames = pcm16.size() / 2 / static_cast<std::size_t>(channels);
    int crossings = 0;
    std::int16_t prev = at16(pcm16, static_cast<std::size_t>(channel));
    for (std::size_t i = 1; i < frames; ++i) {
        const std::int16_t cur = at16(pcm16, i * static_cast<std::size_t>(channels) + static_cast<std::size_t>(channel));
        if ((prev < 0) != (cur < 0))
            ++crossings;
        prev = cur;
    }
    return crossings;
}

void testDecodeMono16()
{
    const auto samples = sine(44100, 1000.0, 4410);
    const auto wav = makeWav16(44100, 1, samples);

    Clip clip;
    std::string err;
    CHECK(decodeWav(wav.data(), wav.size(), clip, &err));
    CHECK(clip.sampleRate == 44100);
    CHECK(clip.channels == 1);
    CHECK(clip.frames() == 4410);
    CHECK(std::fabs(clip.samples[10] - samples[10] / 32768.0f) < 1e-6f);
}

void testDecodeRejectsGarbage()
{
    Clip clip;
    std::string err;
    const unsigned char junk[] = {1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14};
    CHECK(!decodeWav(junk, sizeof(junk), clip, &err));
    CHECK(!err.empty());
    CHECK(!decodeWav(nullptr, 0, clip, &err));

    // WAV sans bloc data.
    std::vector<unsigned char> wav = makeWav16(44100, 1, {0, 0});
    wav.resize(36); // coupe avant "data"
    CHECK(!decodeWav(wav.data(), wav.size(), clip, &err));
}

void testDecodeTruncatedDataChunkIsBounded()
{
    auto wav = makeWav16(44100, 1, sine(44100, 500.0, 1000));
    wav.resize(wav.size() - 501); // fichier tronque, en-tete inchange
    Clip clip;
    CHECK(decodeWav(wav.data(), wav.size(), clip));
    CHECK(clip.frames() > 0 && clip.frames() < 1000);
}

void testConvertSameRateStereoInt16()
{
    const auto samples = sine(48000, 1000.0, 4800);
    Clip clip;
    const auto wav = makeWav16(48000, 1, samples);
    CHECK(decodeWav(wav.data(), wav.size(), clip));

    OutputFormat fmt{48000, 2, SampleType::Int16};
    const auto out = convertClip(clip, fmt);
    CHECK(out.size() == 4800u * 2u * 2u);
    // Mono -> L et R identiques, valeurs conservees.
    for (std::size_t i : {std::size_t(0), std::size_t(37), std::size_t(2400), std::size_t(4799)}) {
        CHECK(at16(out, i * 2) == at16(out, i * 2 + 1));
        CHECK(std::abs(at16(out, i * 2) - samples[i]) <= 1);
    }
}

void testResamplePreservesFrequencyAndDuration()
{
    // 1 kHz pendant 0,1 s a 44,1 kHz -> 48 kHz : 200 passages par zero, 4800 frames.
    const auto samples = sine(44100, 1000.0, 4410);
    Clip clip;
    const auto wav = makeWav16(44100, 1, samples);
    CHECK(decodeWav(wav.data(), wav.size(), clip));

    OutputFormat fmt{48000, 2, SampleType::Int16};
    const auto out = convertClip(clip, fmt);
    const std::size_t frames = out.size() / 4;
    CHECK(frames >= 4799 && frames <= 4801);
    const int zc = zeroCrossings(out, 2, 0);
    CHECK(zc >= 197 && zc <= 203);
}

void testMoreThanTwoChannelsOnlyFrontPair()
{
    const auto samples = sine(48000, 800.0, 480, 0.8);
    Clip clip;
    const auto wav = makeWav16(48000, 1, samples);
    CHECK(decodeWav(wav.data(), wav.size(), clip));

    OutputFormat fmt{48000, 8, SampleType::Float};
    const auto out = convertClip(clip, fmt);
    CHECK(out.size() == 480u * 8u * 4u);

    bool frontNonZero = false;
    bool restSilent = true;
    for (std::size_t i = 0; i < 480; ++i) {
        for (int c = 0; c < 8; ++c) {
            float v;
            std::memcpy(&v, &out[(i * 8 + static_cast<std::size_t>(c)) * 4], 4);
            if (c < 2 && std::fabs(v) > 0.1f)
                frontNonZero = true;
            if (c >= 2 && v != 0.0f)
                restSilent = false;
        }
    }
    CHECK(frontNonZero);
    CHECK(restSilent);
}

void testMonoTargetAveragesChannels()
{
    // Stereo : L = +0.5, R = -0.5 -> moyenne 0.
    std::vector<std::int16_t> stereo;
    for (int i = 0; i < 100; ++i) {
        stereo.push_back(16384);
        stereo.push_back(-16384);
    }
    Clip clip;
    const auto wav = makeWav16(48000, 2, stereo);
    CHECK(decodeWav(wav.data(), wav.size(), clip));
    CHECK(clip.channels == 2);

    OutputFormat fmt{48000, 1, SampleType::Int16};
    const auto out = convertClip(clip, fmt);
    CHECK(out.size() == 100u * 2u);
    CHECK(std::abs(at16(out, 50)) <= 1);
}

void testTailSilenceAndUInt8()
{
    const auto samples = sine(48000, 1000.0, 480, 1.0);
    Clip clip;
    const auto wav = makeWav16(48000, 1, samples);
    CHECK(decodeWav(wav.data(), wav.size(), clip));

    OutputFormat fmt{48000, 1, SampleType::UInt8};
    const auto out = convertClip(clip, fmt, /*tailSilenceMs=*/10); // 480 frames de silence
    CHECK(out.size() == 960u);
    for (std::size_t i = 480; i < 960; ++i)
        CHECK(out[i] == 128);
}

void testInt32PeakAndClamp()
{
    Clip clip;
    clip.sampleRate = 48000;
    clip.channels = 1;
    clip.samples = {1.0f, -1.0f, 2.0f, -2.0f, 0.0f};

    OutputFormat fmt{48000, 1, SampleType::Int32};
    const auto out = convertClip(clip, fmt);
    CHECK(out.size() == 5u * 4u);
    std::int32_t v[5];
    std::memcpy(v, out.data(), sizeof(v));
    CHECK(v[0] == 2147483647);
    CHECK(v[1] == -2147483647);
    CHECK(v[2] == 2147483647); // valeurs hors plage bornees, pas de debordement
    CHECK(v[3] == -2147483647);
    CHECK(v[4] == 0);
}

void testInvalidInputsGiveEmptyOutput()
{
    Clip empty;
    CHECK(convertClip(empty, OutputFormat{}).empty());

    Clip clip;
    clip.sampleRate = 44100;
    clip.channels = 1;
    clip.samples = {0.1f, 0.2f};
    CHECK(convertClip(clip, OutputFormat{0, 2, SampleType::Int16}).empty());
    CHECK(convertClip(clip, OutputFormat{48000, 0, SampleType::Int16}).empty());
}

} // namespace

int main()
{
    testDecodeMono16();
    testDecodeRejectsGarbage();
    testDecodeTruncatedDataChunkIsBounded();
    testConvertSameRateStereoInt16();
    testResamplePreservesFrequencyAndDuration();
    testMoreThanTwoChannelsOnlyFrontPair();
    testMonoTargetAveragesChannels();
    testTailSilenceAndUInt8();
    testInt32PeakAndClamp();
    testInvalidInputsGiveEmptyOutput();

    if (g_failures == 0)
        std::printf("test_pcmconverter : OK\n");
    return g_failures == 0 ? 0 : 1;
}
