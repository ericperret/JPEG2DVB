/*
 * ══════════════════════════════════════════════════════════════
 *  Nom      : test_adf4351.c
 *  Projet   : JPEG2DVB — chantier 2 : programmation du PIC depuis l'ESP32
 *  Objet    : contrôle sur PC (gcc) de la fonction de calcul des registres de l'ADF4351,
 *             extraite du firmware par build.sh (bloc CALCUL_ADF4351 de jpeg2dvb_prog.ino).
 *             Affiche les images EEPROM pour la simulation du PIC (pic14.js).
 *  Auteur   : Eric PERRET
 *  Date     : 2026-11-21
 *  Version  : 1.0.0
 *  Usage    : gcc -Wall -Wextra -o test_adf4351 test_adf4351.c && ./test_adf4351
 *             (adf4351_extrait.c doit être dans le même dossier)
 * ══════════════════════════════════════════════════════════════
 */
#include <stdio.h>
#include <stdint.h>
#include <string.h>

#include "adf4351_extrait.c"

static int erreurs = 0;

static uint32_t champ(uint32_t r, unsigned msb, unsigned lsb)
{
    return (r >> lsb) & ((msb - lsb == 31u) ? 0xFFFFFFFFu : ((1u << (msb - lsb + 1u)) - 1u));
}

static void verifier(int cond, const char *f, const char *quoi, uint32_t lu, uint32_t attendu)
{
    if (!cond) {
        printf("  ÉCHEC %s MHz : %s = %lu (0x%lX), attendu %lu (0x%lX)\n", f, quoi,
               (unsigned long)lu, (unsigned long)lu, (unsigned long)attendu, (unsigned long)attendu);
        erreurs++;
    }
}

#define EGAL(r, msb, lsb, val, nom) verifier(champ((r), (msb), (lsb)) == (uint32_t)(val), ftxt, nom, champ((r), (msb), (lsb)), (uint32_t)(val))

static void controler(uint32_t f_demi)
{
    adf4351_t c;
    char ftxt[16];
    uint32_t i, somme;
    snprintf(ftxt, sizeof ftxt, "%lu,%c", (unsigned long)(f_demi / 2u), (f_demi & 1u) ? '5' : '0');
    if (adf4351_calculer(f_demi, &c) != 0) {
        printf("  ÉCHEC %s MHz : refusée\n", ftxt);
        erreurs++;
        return;
    }
    /* fréquence : f = (INT + FRAC/MOD) × PFD / diviseur, PFD = REFIN × (1+D) / (R × (1+T)) */
    {
        const uint32_t refin = 50u, d = champ(c.r[2], 25, 25), t = champ(c.r[2], 24, 24), r = champ(c.r[2], 23, 14);
        const uint32_t pfd_x = refin * (1u + d);          /* MHz × R × (1+T) */
        const uint32_t den = r * (1u + t);
        const uint32_t n_int = champ(c.r[0], 30, 15), n_frac = champ(c.r[0], 14, 3), mod = champ(c.r[1], 14, 3);
        const uint32_t div = 1u << champ(c.r[4], 22, 20);
        /* 2·f = 2·(INT·MOD + FRAC)·PFD / (MOD·div) */
        const uint64_t num = 2ull * ((uint64_t)n_int * mod + n_frac) * pfd_x;
        const uint64_t dnm = (uint64_t)mod * div * den;
        verifier(den != 0u && pfd_x % den == 0u && pfd_x / den == 25u, ftxt, "PFD (MHz)", den ? pfd_x / den : 0u, 25u);
        verifier(dnm != 0u && num % dnm == 0u && num / dnm == f_demi, ftxt, "fréquence (demi-MHz)",
                 dnm ? (uint32_t)(num / dnm) : 0u, f_demi);
        verifier(c.vco_mhz >= 2200u && c.vco_mhz <= 4400u, ftxt, "VCO (MHz)", c.vco_mhz, 2200u);
        verifier(c.vco_mhz == (n_int * mod + n_frac) * 25u / mod, ftxt, "VCO = (INT + FRAC/MOD) × PFD", (n_int * mod + n_frac) * 25u / mod, c.vco_mhz);
        verifier(c.diviseur == div, ftxt, "diviseur", div, c.diviseur);
        verifier(c.diviseur == ((f_demi >= 2200u) ? 2u : 4u), ftxt, "choix du diviseur", c.diviseur, (f_demi >= 2200u) ? 2u : 4u);
        verifier(n_int >= 75u && n_int <= 65535u, ftxt, "INT (prescaler 8/9 : ≥ 75)", n_int, 75u);
        verifier(n_frac < mod, ftxt, "FRAC < MOD", n_frac, mod);
        verifier(c.int_n == n_int && c.frac == n_frac, ftxt, "INT/FRAC retournés", c.int_n, n_int);
        verifier(pfd_x / den * 1000u / champ(c.r[4], 19, 12) <= 125u, ftxt, "horloge de bande (kHz)", pfd_x / den * 1000u / champ(c.r[4], 19, 12), 125u);
    }
    /* R0 */
    EGAL(c.r[0], 2, 0, 0, "R0 contrôle");
    EGAL(c.r[0], 31, 31, 0, "R0 DB31 réservé");
    /* R1 */
    EGAL(c.r[1], 2, 0, 1, "R1 contrôle");
    EGAL(c.r[1], 14, 3, 25, "R1 MOD");
    EGAL(c.r[1], 26, 15, 1, "R1 PHASE");
    EGAL(c.r[1], 27, 27, 1, "R1 prescaler 8/9");
    EGAL(c.r[1], 28, 28, 0, "R1 ajustement de phase");
    EGAL(c.r[1], 31, 29, 0, "R1 réservés");
    /* R2 */
    EGAL(c.r[2], 2, 0, 2, "R2 contrôle");
    EGAL(c.r[2], 3, 3, 0, "R2 RAZ compteurs");
    EGAL(c.r[2], 4, 4, 0, "R2 CP 3 états");
    EGAL(c.r[2], 5, 5, 0, "R2 mise en veille");
    EGAL(c.r[2], 6, 6, 1, "R2 polarité positive");
    EGAL(c.r[2], 7, 7, 0, "R2 LDP 10 ns");
    EGAL(c.r[2], 8, 8, 0, "R2 LDF fractionnaire");
    EGAL(c.r[2], 12, 9, 7, "R2 pompe de charge 2,5 mA");
    EGAL(c.r[2], 13, 13, 0, "R2 double tampon");
    EGAL(c.r[2], 23, 14, 2, "R2 compteur R");
    EGAL(c.r[2], 24, 24, 0, "R2 RDIV2");
    EGAL(c.r[2], 25, 25, 0, "R2 doubleur");
    EGAL(c.r[2], 28, 26, 0, "R2 MUXOUT 3 états");
    EGAL(c.r[2], 30, 29, 0, "R2 mode faible bruit");
    EGAL(c.r[2], 31, 31, 0, "R2 DB31 réservé");
    /* R3 */
    EGAL(c.r[3], 2, 0, 3, "R3 contrôle");
    EGAL(c.r[3], 14, 3, 150, "R3 diviseur d'horloge");
    EGAL(c.r[3], 16, 15, 0, "R3 mode diviseur d'horloge");
    EGAL(c.r[3], 17, 17, 0, "R3 DB17 réservé");
    EGAL(c.r[3], 18, 18, 0, "R3 CSR");
    EGAL(c.r[3], 20, 19, 0, "R3 DB20-19 réservés");
    EGAL(c.r[3], 21, 21, 0, "R3 annulation de charge");
    EGAL(c.r[3], 22, 22, 0, "R3 ABP 6 ns");
    EGAL(c.r[3], 23, 23, 0, "R3 horloge de bande mode bas");
    EGAL(c.r[3], 31, 24, 0, "R3 réservés");
    /* R4 */
    EGAL(c.r[4], 2, 0, 4, "R4 contrôle");
    EGAL(c.r[4], 4, 3, 3, "R4 puissance RFOUTA +5 dBm");
    EGAL(c.r[4], 5, 5, 1, "R4 RFOUTA activée");
    EGAL(c.r[4], 7, 6, 0, "R4 puissance RFOUTB");
    EGAL(c.r[4], 8, 8, 0, "R4 RFOUTB coupée");
    EGAL(c.r[4], 9, 9, 0, "R4 sélection RFOUTB");
    EGAL(c.r[4], 10, 10, 1, "R4 MTLD");
    EGAL(c.r[4], 11, 11, 0, "R4 VCO actif");
    EGAL(c.r[4], 19, 12, 200, "R4 diviseur horloge de bande");
    EGAL(c.r[4], 22, 20, (f_demi >= 2200u) ? 1 : 2, "R4 diviseur de sortie");
    EGAL(c.r[4], 23, 23, 1, "R4 contre-réaction fondamentale");
    EGAL(c.r[4], 31, 24, 0, "R4 réservés");
    /* R5 */
    EGAL(c.r[5], 2, 0, 5, "R5 contrôle");
    EGAL(c.r[5], 18, 3, 0, "R5 DB18-3 réservés");
    EGAL(c.r[5], 20, 19, 3, "R5 DB20-19 réservés (11)");
    EGAL(c.r[5], 21, 21, 0, "R5 DB21 réservé");
    EGAL(c.r[5], 23, 22, 1, "R5 LD détection numérique");
    EGAL(c.r[5], 31, 24, 0, "R5 réservés");
    /* EEPROM */
    for (i = 0u; i < 6u; i++) {
        uint32_t v = ((uint32_t)c.eeprom[i * 4u] << 24) | ((uint32_t)c.eeprom[i * 4u + 1u] << 16)
                   | ((uint32_t)c.eeprom[i * 4u + 2u] << 8) | c.eeprom[i * 4u + 3u];
        verifier(v == c.r[5u - i], ftxt, "EEPROM ordre R5→R0", v, c.r[5u - i]);
    }
    verifier(c.eeprom[24] == 0x4Au, ftxt, "EEPROM signature", c.eeprom[24], 0x4Au);
    somme = 0u;
    for (i = 0u; i < 26u; i++) somme += c.eeprom[i];
    verifier((somme & 0xFFu) == 0u, ftxt, "EEPROM somme mod 256", somme & 0xFFu, 0u);

    printf("  %7s MHz : ÷%lu VCO %lu INT %lu FRAC %lu  R0 %08lX R1 %08lX R2 %08lX R3 %08lX R4 %08lX R5 %08lX\n",
           ftxt, (unsigned long)c.diviseur, (unsigned long)c.vco_mhz, (unsigned long)c.int_n, (unsigned long)c.frac,
           (unsigned long)c.r[0], (unsigned long)c.r[1], (unsigned long)c.r[2],
           (unsigned long)c.r[3], (unsigned long)c.r[4], (unsigned long)c.r[5]);
    printf("IMAGE ");
    for (i = 0u; i < 26u; i++) printf("%02X", c.eeprom[i]);
    printf("\n");
}

static void saisie(const char *s, int accepte, uint32_t attendu)
{
    uint32_t f = 0u;
    int r = adf4351_analyser(s, &f);
    if ((r == 0) != (accepte != 0) || (accepte && f != attendu)) {
        printf("  ÉCHEC saisie « %s » : %s\n", s, r == 0 ? "acceptée" : "refusée");
        erreurs++;
    }
}

int main(void)
{
    static const uint32_t frequences[] = { 1900u, 2199u, 2200u, 2500u, 4300u };  /* 950,0 1099,5 1100,0 1250,0 2150,0 */
    adf4351_t c;
    uint32_t i;

    printf("Contrôle du calcul des registres ADF4351\n");
    for (i = 0u; i < sizeof frequences / sizeof frequences[0]; i++) controler(frequences[i]);

    /* toute la plage, par pas de 0,5 MHz */
    for (i = ADF_F_MIN_DEMI; i <= ADF_F_MAX_DEMI; i++) {
        if (adf4351_calculer(i, &c) != 0 || c.vco_mhz < 2200u || c.vco_mhz > 4400u
            || (c.int_n * 25u + c.frac) * 2u != i * c.diviseur || c.frac >= 25u) {
            printf("  ÉCHEC balayage %lu demi-MHz\n", (unsigned long)i);
            erreurs++;
        }
    }
    if (adf4351_calculer(1899u, &c) == 0 || adf4351_calculer(4301u, &c) == 0) {
        printf("  ÉCHEC hors plage acceptée\n");
        erreurs++;
    }

    /* saisie */
    saisie("950", 1, 1900u);       saisie("950,0", 1, 1900u);    saisie("1099.5", 1, 2199u);
    saisie("1100,0", 1, 2200u);    saisie("1250.0", 1, 2500u);   saisie("2150", 1, 4300u);
    saisie(" 1250,50 ", 1, 2500u + 1u); saisie("1250.00", 1, 2500u);
    saisie("949,5", 0, 0u);        saisie("2150,5", 0, 0u);      saisie("1250,3", 0, 0u);
    saisie("1250,05", 0, 0u);      saisie("1250,", 0, 0u);       saisie("", 0, 0u);
    saisie("abc", 0, 0u);          saisie("-1250", 0, 0u);       saisie("12500", 0, 0u);
    saisie("1250,5x", 0, 0u);

    if (erreurs) {
        printf("calcul ADF4351 : %d échec(s)\n", erreurs);
        return 1;
    }
    printf("calcul ADF4351 : conforme\n");
    return 0;
}
