#ifndef SERVICES_PCMCONVERTER_H
#define SERVICES_PCMCONVERTER_H

#include <cstddef>
#include <string>
#include <vector>

namespace services::pcm {

/**
 * @brief Decodage WAV + conversion PCM vers le format d'un peripherique de sortie.
 *
 * Volontairement ecrit en C++ standard (aucune dependance a Qt) : la logique
 * est ainsi testable seule (tests/UnitTests/test_pcmconverter.cpp), et
 * AudioService n'a plus besoin du pipeline de decodage/conversion FFmpeg de
 * QMediaPlayer.
 *
 * Contexte : sur certaines cartes son (ex. Realtek en partage WASAPI dont le
 * format prefere n'a pas de disposition de canaux connue de Qt),
 * QMediaPlayer echoue avec
 *   "QAudioSink::start: QAudioFormat not supported by QAudioDevice"
 *   "[SWR] Output channel layout "" is invalid or unsupported"
 * et ne joue rien, sans jamais remonter d'erreur. On decode donc le WAV
 * nous-memes puis on convertit vers preferredFormat() du peripherique -- la
 * meme technique que VoiceAudioIO, qui fonctionne sur ce materiel.
 */

/// Format d'un echantillon PCM natif d'un peripherique (Qt6 : pas de 24 bits,
/// il est expose comme Int32).
enum class SampleType {
    UInt8,
    Int16,
    Int32,
    Float
};

/// Son decode : echantillons flottants [-1, 1] entrelaces.
struct Clip {
    int sampleRate = 0;
    int channels = 0;
    std::vector<float> samples;

    std::size_t frames() const
    {
        return channels > 0 ? samples.size() / static_cast<std::size_t>(channels) : 0;
    }
};

/// Format cible (celui accepte par le peripherique de sortie).
struct OutputFormat {
    int sampleRate = 48000;
    int channels = 2;
    SampleType sampleType = SampleType::Int16;
};

/**
 * @brief Decode un fichier WAV en memoire.
 *
 * Formats pris en charge : PCM 8/16/24/32 bits, float 32 bits, y compris
 * l'en-tete WAVE_FORMAT_EXTENSIBLE. Retourne false (et remplit @p error si
 * non nul) pour tout autre contenu.
 */
bool decodeWav(const unsigned char *data, std::size_t size, Clip &out, std::string *error = nullptr);

/**
 * @brief Convertit un son vers @p format (frequence, canaux, type d'echantillon).
 *
 * - Frequence : interpolation lineaire (suffisante pour des sons courts de
 *   notification).
 * - Canaux : source mono -> L et R identiques ; source multi-canaux -> L/R
 *   = canaux 0 et 1 (mono cible = moyenne). Si la cible a plus de 2 canaux,
 *   seuls les canaux 0 et 1 (avant gauche/droit) portent le son, les
 *   autres restent muets (evite de jouer une notification sur 8 haut-parleurs).
 * - @p tailSilenceMs : silence ajoute a la fin, pour que le peripherique ne
 *   tronque pas la fin du son quand il vide son tampon.
 *
 * Retourne des octets PCM entrelaces dans l'ordre natif de la machine
 * (little-endian sous Windows), directement utilisables par QAudioSink.
 * Retourne un tableau vide si @p clip ou @p format est invalide.
 */
std::vector<unsigned char> convertClip(const Clip &clip, const OutputFormat &format, int tailSilenceMs = 0);

} // namespace services::pcm

#endif // SERVICES_PCMCONVERTER_H
