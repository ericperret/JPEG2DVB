/*
 * ══════════════════════════════════════════════════════════════
 *  Nom      : jpeg2dvb_prog.ino
 *  Projet   : JPEG2DVB — chantier 2 : programmation du PIC et du FPGA depuis l'ESP32
 *  Objet    : firmware du M5Stack CoreS3 branché sur J7 :
 *               - point d'accès Wi-Fi + portail captif + page web (prog_page.h)
 *               - PIC de U6 (PIC16(L)F18323, 18324, 18325, 18326, reconnu par son DEVID) :
 *                 ICSP basse tension (DS40001738), lecture, première programmation
 *                 (programme fixe pic_fw.h, configuration, repère User ID, EEPROM),
 *                 écriture de la fréquence (EEPROM seule : registres de l'ADF4351)
 *               - FPGA PolarFire (IC1) : JTAG-DirectC v2021.2, fichier /fpga.dat en FFat
 *  Auteur   : Eric PERRET
 *  Date     : 2026-11-23
 *  Version  : 1.1.0
 *  Historique : 1.0.0  2026-11-21  création
 *             1.1.0  2026-11-23  PIC : modèle reconnu par le DEVID (8 PIC broche à broche
 *                                compatibles), lecture du contenu, première programmation
 *                                distincte de l'écriture de la fréquence (EEPROM seule),
 *                                repère JPEG2DVB + version en User ID
 *  Cible    : M5Stack CoreS3 (ESP32-S3)
 *  Compilé  : arduino-esp32 3.3.12 + M5Unified 0.2.25 (voir build.sh)
 *  FQBN     : esp32:esp32:esp32s3:CDCOnBoot=cdc,PSRAM=opi,FlashSize=16M,
 *             FlashMode=qio,PartitionScheme=app3M_fat9M_16MB
 *  Fichiers : jpeg2dvb_prog.ino, prog_page.h, pic_fw.h, pll_boot.asm (source de pic_fw.h),
 *             src/directc/ (JTAG-DirectC + portage, mis en place par build.sh)
 * ══════════════════════════════════════════════════════════════
 */

#include <M5Unified.h>
#include <WiFi.h>
#include <WebServer.h>
#include <DNSServer.h>
#include <ESPmDNS.h>
#include <FFat.h>
#include <Preferences.h>
#include "driver/gpio.h"
#include "esp_rom_sys.h"
#include "soc/soc.h"
#include "soc/gpio_reg.h"
#include "prog_page.h"
#include "pic_fw.h"
#include "src/directc/jpeg2dvb_port.h"


// ══════════════════════════════════════════════════════════════
//  CONFIGURATION
// ══════════════════════════════════════════════════════════════

#define VERSION_FW      "1.1.0"

// ── Wi-Fi ──
#define AP_SSID         "jpeg2dvb.local"
#define AP_MDP          "jpeg2dvb.local"
#define MDNS_NOM        "jpeg2dvb"
#define HTTP_PORT       80
#define DNS_PORT        53

// ── J7 (broches PIC et LD ; JTAG dans jpeg2dvb_port.h) ──
#define BR_MCLR         5
#define BR_ICSPCLK      6
#define BR_ICSPDAT      7
#define BR_LD           10

// ── Fichiers FFat ──
#define F_DAT           "/fpga.dat"
#define F_TMP           "/fpga.tmp"

// ── ICSP basse tension PIC16(L)F183XX (DS40001738, tableau 8-1) ──
#define ICSP_DEMI_US        1u          // TCKH, TCKL, TDS, TDH ≥ 100 ns
#define ICSP_TDLY_US        2u          // TDLY ≥ 1 µs
#define ICSP_TENTH_US       500u        // TENTH ≥ 250 µs
#define ICSP_TEXIT_US       2u          // TEXIT ≥ 1 µs
#define ICSP_TERAB_MS       6u          // TERAB ≤ 5 ms
#define ICSP_TPINT_PROG_MS  3u          // TPINT mémoire programme ≤ 2,5 ms
#define ICSP_TPINT_CONF_MS  6u          // TPINT configuration ≤ 5 ms
#define ICSP_TPINT_EE_MS    6u          // écriture EEPROM (TPEW ≤ 2,8 ms)
#define ICSP_CLE_LVP        0x4D434850UL // « MCHP », bit de poids faible en premier, 33 coups d'horloge
#define ICSP_RANGEE         32u         // mots par rangée de mémoire programme

#define CMD_CHARGER         0x02u       // Load Data for NVM
#define CMD_CHARGER_INC     0x22u       // Load Data for NVM, PC + 1
#define CMD_LIRE            0x04u       // Read Data from NVM
#define CMD_LIRE_INC        0x24u       // Read Data from NVM, PC + 1
#define CMD_INCREMENTER     0x06u       // Increment Address
#define CMD_CHARGER_PC      0x1Du       // Load PC Address
#define CMD_PROG_INTERNE    0x08u       // Begin Internally Timed Programming
#define CMD_EFFACER_TOUT    0x09u       // Bulk Erase Memory

#define PIC_ADR_REVID       0x8005u
#define PIC_ADR_DEVID       0x8006u
#define PIC_ADR_CONFIG      0x8007u
#define PIC_ADR_EEPROM      0xF000u
#define PIC_ADR_USERID      0x8000u

#define LD_ATTENTE_MS       1000u       // attente max de LD après programmation
#define LD_DEMARRAGE_MS     60u         // le PIC attend 20 ms puis écrit les 6 mots

// ── Journal ──
#define JOURNAL_LIGNES      256
#define JOURNAL_LARGEUR     160
#define JOURNAL_ENVOI_MAX   64          // lignes par réponse /journal


// ══════════════════════════════════════════════════════════════
//  CALCUL DES REGISTRES DE L'ADF4351
//  Bloc en C pur : extrait et contrôlé sur le PC par « ./build.sh controle »
// ══════════════════════════════════════════════════════════════

// >>> CALCUL_ADF4351
#define ADF_F_MIN_DEMI    1900u   /* 950,0 MHz en demi-MHz  */
#define ADF_F_MAX_DEMI    4300u   /* 2150,0 MHz en demi-MHz */
#define ADF_F_DIV2_DEMI   2200u   /* 1100,0 MHz : ÷2 à partir d'ici, ÷4 en dessous */
#define ADF_PFD_MHZ       25u     /* REFIN 50 MHz, doubleur coupé, RDIV2 = 0, R = 2 */
#define ADF_R             2u
#define ADF_MOD           25u     /* pas VCO = 1 MHz */
#define ADF_PHASE         1u
#define ADF_CP_2MA50      7u      /* 2,50 mA avec RSET = 5,1 kΩ */
#define ADF_CLKDIV        150u    /* diviseur d'horloge (mode coupé) */
#define ADF_BANDE_DIV     200u    /* 25 MHz / 200 = 125 kHz */
#define ADF_SIGNATURE     0x4Au
#define ADF_EEPROM_OCTETS 26u

typedef struct {
    uint32_t r[6];                        /* R0 à R5 */
    uint32_t vco_mhz;
    uint32_t int_n;
    uint32_t frac;
    uint32_t diviseur;                    /* 2 ou 4 */
    uint8_t  eeprom[ADF_EEPROM_OCTETS];   /* R5..R0 poids fort en premier, signature, contrôle */
} adf4351_t;

/* Lecture d'une fréquence « 1250 », « 1250,0 », « 1250.5 » → demi-MHz.
   Renvoie 0 si la valeur est acceptée (950,0 à 2150,0 MHz, pas de 0,5 MHz), -1 sinon. */
static int adf4351_analyser(const char *s, uint32_t *f_demi)
{
    uint32_t mhz = 0u, chiffres = 0u, demi = 0u;
    if (s == 0 || f_demi == 0) return -1;
    while (*s == ' ') s++;
    while (*s >= '0' && *s <= '9') {
        if (++chiffres > 4u) return -1;
        mhz = mhz * 10u + (uint32_t)(*s - '0');
        s++;
    }
    if (chiffres == 0u) return -1;
    if (*s == ',' || *s == '.') {
        s++;
        if (*s == '5') { demi = 1u; s++; }
        else if (*s == '0') { s++; }
        else return -1;
        while (*s == '0') s++;
    }
    while (*s == ' ') s++;
    if (*s != '\0') return -1;
    mhz = mhz * 2u + demi;
    if (mhz < ADF_F_MIN_DEMI || mhz > ADF_F_MAX_DEMI) return -1;
    *f_demi = mhz;
    return 0;
}

/* f_demi : fréquence de sortie en demi-MHz. Renvoie 0 si correct, -1 si hors plage. */
static int adf4351_calculer(uint32_t f_demi, adf4351_t *c)
{
    uint32_t i, somme, sel;
    if (c == 0 || f_demi < ADF_F_MIN_DEMI || f_demi > ADF_F_MAX_DEMI) return -1;
    c->diviseur = (f_demi >= ADF_F_DIV2_DEMI) ? 2u : 4u;
    sel = (c->diviseur == 2u) ? 1u : 2u;                   /* DB22-20 : 001 = ÷2, 010 = ÷4 */
    c->vco_mhz = f_demi * c->diviseur / 2u;
    c->int_n = c->vco_mhz / ADF_PFD_MHZ;
    c->frac = c->vco_mhz % ADF_PFD_MHZ;

    /* R0 : INT (DB30-15), FRAC (DB14-3) */
    c->r[0] = (c->int_n << 15) | (c->frac << 3) | 0u;
    /* R1 : ajustement de phase coupé (DB28), prescaler 8/9 (DB27), PHASE (DB26-15), MOD (DB14-3) */
    c->r[1] = (0u << 28) | (1u << 27) | (ADF_PHASE << 15) | (ADF_MOD << 3) | 1u;
    /* R2 : mode faible bruit (DB30-29 = 00), MUXOUT 3 états (DB28-26 = 000), doubleur coupé (DB25),
            RDIV2 = 0 (DB24), R (DB23-14), double tampon coupé (DB13), CP (DB12-9),
            LDF fractionnaire (DB8 = 0), LDP 10 ns (DB7 = 0), polarité positive (DB6 = 1),
            mise en veille, CP 3 états et RAZ compteurs inactifs (DB5-3 = 0) */
    c->r[2] = (0u << 29) | (0u << 26) | (0u << 25) | (0u << 24) | (ADF_R << 14) | (0u << 13)
            | (ADF_CP_2MA50 << 9) | (0u << 8) | (0u << 7) | (1u << 6) | 2u;
    /* R3 : horloge de sélection de bande en mode bas (DB23 = 0), ABP 6 ns (DB22 = 0),
            annulation de charge (DB21), CSR (DB18) et mode du diviseur d'horloge (DB16-15) coupés */
    c->r[3] = (0u << 23) | (0u << 22) | (0u << 21) | (0u << 18) | (0u << 15) | (ADF_CLKDIV << 3) | 3u;
    /* R4 : contre-réaction fondamentale (DB23 = 1), diviseur de sortie (DB22-20),
            horloge de bande (DB19-12), VCO actif (DB11 = 0), MTLD (DB10 = 1),
            RFOUTB coupée (DB9-6 = 0), RFOUTA activée (DB5 = 1) à +5 dBm (DB4-3 = 11) */
    c->r[4] = (1u << 23) | (sel << 20) | (ADF_BANDE_DIV << 12) | (0u << 11) | (1u << 10)
            | (0u << 9) | (0u << 8) | (0u << 6) | (1u << 5) | (3u << 3) | 4u;
    /* R5 : patte LD en détection numérique (DB23-22 = 01), réservés DB20-19 = 11 */
    c->r[5] = (1u << 22) | (3u << 19) | 5u;

    for (i = 0u; i < 6u; i++) {
        uint32_t v = c->r[5u - i];
        c->eeprom[i * 4u + 0u] = (uint8_t)(v >> 24);
        c->eeprom[i * 4u + 1u] = (uint8_t)(v >> 16);
        c->eeprom[i * 4u + 2u] = (uint8_t)(v >> 8);
        c->eeprom[i * 4u + 3u] = (uint8_t)v;
    }
    c->eeprom[24] = ADF_SIGNATURE;
    somme = 0u;
    for (i = 0u; i < 25u; i++) somme += c->eeprom[i];
    c->eeprom[25] = (uint8_t)((256u - (somme & 0xFFu)) & 0xFFu);
    return 0;
}
// <<< CALCUL_ADF4351


// ══════════════════════════════════════════════════════════════
//  TYPES ET ÉTAT GLOBAL
// ══════════════════════════════════════════════════════════════

enum Tache : uint8_t { T_AUCUNE = 0, T_PIC_LIRE, T_PIC_PROG, T_PIC_EE, T_FPGA_ID, T_FPGA_PROG };

// contenu de la mémoire programme du PIC
enum Contenu : uint8_t { C_INCONNU = 0, C_VIERGE, C_JPEG2DVB, C_AUTRE };

enum Resultat : uint8_t { Q_AUCUN = 0, Q_OK, Q_ALERTE, Q_ERREUR };

struct Etat {
    char     phase[64];
    char     action[64];
    char     resultat[128];
    uint8_t  qualite;           // Resultat
    uint8_t  progression;       // 0..100
    bool     pic_lu;            // DEVID lu au moins une fois
    uint16_t devid;
    uint16_t revid;
    int8_t   pic_idx;           // indice dans pic_modeles, -1 si DEVID inconnu
    uint8_t  pic_contenu;       // Contenu
    char     pic_version[24];   // version du programme JPEG2DVB (repère User ID)
    uint8_t  pic_ee;            // 0 non lue, 1 image valide, 2 image invalide ou vide
    uint32_t pic_ee_freq;       // fréquence de l'image EEPROM (demi-MHz), 0 si invalide
    bool     idcode_lu;
    uint32_t idcode;
    char     fpga_nom[24];
    bool     dat_present;
    uint32_t dat_taille;
    uint32_t dat_crc;
    uint32_t freq_demi;         // dernière fréquence écrite (0 = aucune)
};

struct Envoi {
    File     f;
    bool     actif;
    bool     ok;
    bool     refuse;
    uint32_t taille;
    uint32_t crc;
    size_t   n;                 // octets en attente dans tampon
    char     erreur[64];
};

struct CodeTexte {
    uint8_t     code;
    const char *texte;
};

static WebServer      serveur(HTTP_PORT);
static DNSServer      dns;
static Preferences    prefs;
static SemaphoreHandle_t verrou;
static TaskHandle_t   h_travail;

static Etat           etat;
static Envoi          envoi;
static uint8_t        envoi_tampon[4096];
static File           dat_fichier;              // ouvert pendant une action FPGA

static volatile uint8_t tache_en_cours = T_AUCUNE;
static volatile bool    ecran_modifie = true;
static adf4351_t      pll_demande;
static uint32_t       pll_demande_f = 0;

static char           journal[JOURNAL_LIGNES][JOURNAL_LARGEUR];
static uint32_t       journal_total = 0;
static char           ligne_cours[JOURNAL_LARGEUR];
static size_t         ligne_lg = 0;

static uint32_t       crc_table[256];

static const CodeTexte CODES_DIRECTC[] = {
    {   0, "succès" },
    {   2, "erreur de traitement des données" },
    {   6, "IDCODE incorrect (composant absent, fichier pour un autre composant ou liaison JTAG)" },
    {   7, "le composant ne répond pas (attente dépassée)" },
    {   8, "erreur d'effacement" },
    {   9, "erreur de somme de contrôle" },
    {  10, "erreur de programmation" },
    {  11, "erreur de vérification du cœur" },
    {  12, "erreur de vérification" },
    {  14, "erreur de programmation de la signature" },
    {  16, "verrou utilisateur actif" },
    {  18, "échec d'authentification du fichier" },
    {  20, "erreur de vérification FROM" },
    {  22, "erreur de programmation de la sécurité" },
    {  23, "erreur de programmation AES" },
    {  24, "erreur de programmation UROW" },
    {  25, "échec d'initialisation" },
    {  31, "erreur de clé (DMK / AES)" },
    {  33, "erreur cœur chiffré" },
    {  35, "non-concordance" },
    {  37, "erreur cœur non chiffré" },
    {  38, "erreur de programmation de la sécurité" },
    {  39, "erreur de vérification NVM" },
    {  41, "erreur de programmation NVM" },
    {  42, "réglage du verrou utilisateur incorrect" },
    {  43, "réglage UROW incorrect" },
    {  54, "erreur d'accès NVM" },
    {  60, "erreur de vérification du condensé" },
    { 100, "CRC du fichier DAT incorrect" },
    { 110, "état JTAG non géré" },
    { 150, "action introuvable" },
    { 151, "action non prise en charge par ce composant" },
    { 152, "code non activé (famille non compilée)" },
    { 153, "chevauchement de calibration" },
    { 154, "bit de sécurité incompatible" },
    { 160, "version du fichier DAT incompatible" },
    { 165, "erreur d'accès au fichier DAT" },
    { 170, "interface matérielle non sélectionnée" },
    { 180, "échec d'accès aux données du fichier DAT" },
};


// ══════════════════════════════════════════════════════════════
//  OUTILS
// ══════════════════════════════════════════════════════════════

static void attente_ms(uint32_t ms)
{
    vTaskDelay(pdMS_TO_TICKS(ms) + 1);      // au moins ms
}

static void crc_init()
{
    for (uint32_t i = 0; i < 256; i++) {
        uint32_t c = i;
        for (int k = 0; k < 8; k++) c = (c & 1u) ? (0xEDB88320u ^ (c >> 1)) : (c >> 1);
        crc_table[i] = c;
    }
}

// CRC32 (IEEE 802.3) : état initial 0xFFFFFFFF, résultat final = ~état
static uint32_t crc_maj(uint32_t etat_crc, const uint8_t *p, size_t n)
{
    while (n--) etat_crc = crc_table[(etat_crc ^ *p++) & 0xFFu] ^ (etat_crc >> 8);
    return etat_crc;
}

static const char *texte_directc(uint8_t code)
{
    for (size_t i = 0; i < sizeof(CODES_DIRECTC) / sizeof(CODES_DIRECTC[0]); i++)
        if (CODES_DIRECTC[i].code == code) return CODES_DIRECTC[i].texte;
    return "code inconnu";
}

static const char *nom_fpga(uint32_t idcode)
{
    switch (idcode & 0x0FFFFFFFu) {
        case 0x0F8111CFu: return "MPF100T";
        case 0x0F8101CFu: return "MPF050T";
        default: break;
    }
    if ((idcode & 0x0FF00FFFu) == 0x0F8001CFu) return "PolarFire (autre)";
    return "inconnu";
}

static void frequence_texte(uint32_t f_demi, char *t, size_t n)
{
    snprintf(t, n, "%lu,%c", (unsigned long)(f_demi / 2u), (f_demi & 1u) ? '5' : '0');
}

static void json_texte(String &s, const char *t)
{
    s += '"';
    for (; *t; t++) {
        char c = *t;
        if (c == '"') s += "\\\"";
        else if (c == '\\') s += "\\\\";
        else if ((uint8_t)c < 0x20) {
            char b[8];
            snprintf(b, sizeof b, "\\u%04x", (unsigned)(uint8_t)c);
            s += b;
        } else s += c;
    }
    s += '"';
}

static void repondre_json(int code, const String &s)
{
    serveur.sendHeader("Cache-Control", "no-store");
    serveur.send(code, "application/json; charset=utf-8", s);
}

static void repondre_erreur(int code, const char *msg)
{
    String s = "{\"ok\":false,\"erreur\":";
    json_texte(s, msg);
    s += '}';
    repondre_json(code, s);
}


// ══════════════════════════════════════════════════════════════
//  JOURNAL ET ÉTAT (partagés entre la tâche web et la tâche de travail)
// ══════════════════════════════════════════════════════════════

static void journal_ligne(const char *t)
{
    xSemaphoreTake(verrou, portMAX_DELAY);
    strlcpy(journal[journal_total % JOURNAL_LIGNES], t, JOURNAL_LARGEUR);
    journal_total++;
    xSemaphoreGive(verrou);
    Serial.println(t);
}

static void journal_printf(const char *fmt, ...)
{
    char t[JOURNAL_LARGEUR];
    va_list ap;
    va_start(ap, fmt);
    vsnprintf(t, sizeof t, fmt, ap);
    va_end(ap);
    journal_ligne(t);
}

static void etat_texte(char *dst, size_t n, const char *t)
{
    xSemaphoreTake(verrou, portMAX_DELAY);
    strlcpy(dst, t, n);
    xSemaphoreGive(verrou);
    ecran_modifie = true;
}

static void etat_phase(const char *t, uint8_t progression)
{
    xSemaphoreTake(verrou, portMAX_DELAY);
    strlcpy(etat.phase, t, sizeof etat.phase);
    etat.progression = progression;
    xSemaphoreGive(verrou);
    ecran_modifie = true;
}

static void etat_resultat(uint8_t qualite, const char *t)
{
    xSemaphoreTake(verrou, portMAX_DELAY);
    strlcpy(etat.resultat, t, sizeof etat.resultat);
    etat.qualite = qualite;
    xSemaphoreGive(verrou);
    journal_ligne(t);
    ecran_modifie = true;
}

static bool occupe()
{
    return tache_en_cours != T_AUCUNE || envoi.actif;
}

// ── Fonctions appelées par le portage DirectC (C) ──
extern "C" void jpeg2dvb_journal(const char *texte)
{
    for (const char *p = texte; *p; p++) {
        if (*p == '\r' || *p == '\n') {
            if (ligne_lg) {
                ligne_cours[ligne_lg] = '\0';
                journal_ligne(ligne_cours);
                ligne_lg = 0;
            }
            continue;
        }
        ligne_cours[ligne_lg++] = *p;
        if (ligne_lg >= JOURNAL_LARGEUR - 1) {
            ligne_cours[ligne_lg] = '\0';
            journal_ligne(ligne_cours);
            ligne_lg = 0;
        }
    }
}

static void journal_vider_ligne()
{
    if (ligne_lg) {
        ligne_cours[ligne_lg] = '\0';
        journal_ligne(ligne_cours);
        ligne_lg = 0;
    }
}

extern "C" void jpeg2dvb_progression(uint8_t pourcent)
{
    if (pourcent > 100) pourcent = 100;
    if (etat.progression != pourcent) {
        etat.progression = pourcent;
        ecran_modifie = true;
    }
}

extern "C" uint32_t jpeg2dvb_lire_dat(uint32_t adresse, uint8_t *tampon, uint32_t nombre)
{
    static uint32_t appels = 0;
    if ((++appels & 15u) == 0) vTaskDelay(1);   // laisse tourner les tâches de même priorité
    if (!dat_fichier) return 0;
    if (dat_fichier.position() != adresse && !dat_fichier.seek(adresse)) return 0;
    return (uint32_t)dat_fichier.read(tampon, nombre);
}


// ══════════════════════════════════════════════════════════════
//  ICSP BASSE TENSION — PIC16(L)F183XX (DS40001738)
//  Données posées sur le front montant d'ICSPCLK, lues par le PIC au front
//  descendant ; commandes 6 bits et données 16 bits, bit de poids faible en premier.
// ══════════════════════════════════════════════════════════════

static inline void icsp_clk(bool v) { REG_WRITE(v ? GPIO_OUT_W1TS_REG : GPIO_OUT_W1TC_REG, 1UL << BR_ICSPCLK); }
static inline void icsp_dat(bool v) { REG_WRITE(v ? GPIO_OUT_W1TS_REG : GPIO_OUT_W1TC_REG, 1UL << BR_ICSPDAT); }
static inline bool icsp_dat_lu()    { return (REG_READ(GPIO_IN_REG) >> BR_ICSPDAT) & 1u; }
static inline void icsp_dat_pilote(bool p) { REG_WRITE(p ? GPIO_ENABLE_W1TS_REG : GPIO_ENABLE_W1TC_REG, 1UL << BR_ICSPDAT); }

static void icsp_bit(bool b)
{
    icsp_clk(true);
    icsp_dat(b);
    esp_rom_delay_us(ICSP_DEMI_US);
    icsp_clk(false);
    esp_rom_delay_us(ICSP_DEMI_US);
}

static void icsp_envoyer(uint32_t v, uint8_t n)
{
    for (uint8_t i = 0; i < n; i++) icsp_bit((v >> i) & 1u);
}

static void icsp_commande(uint8_t c)
{
    icsp_envoyer(c, 6);
    esp_rom_delay_us(ICSP_TDLY_US);
}

// commande + donnée 14 bits (bit de départ 0, 14 bits, bit d'arrêt 0)
static void icsp_charger(uint8_t c, uint16_t mot)
{
    icsp_commande(c);
    icsp_envoyer(((uint32_t)(mot & 0x3FFFu)) << 1, 16);
    esp_rom_delay_us(ICSP_TDLY_US);
}

// Load PC Address : bit de départ 0, adresse sur 22 bits, bit d'arrêt 0
static void icsp_pc(uint32_t adresse)
{
    icsp_commande(CMD_CHARGER_PC);
    icsp_envoyer((adresse & 0x3FFFFFu) << 1, 24);
    esp_rom_delay_us(ICSP_TDLY_US);
}

// commande de lecture ; le PIC pilote ICSPDAT du 1er au 16e front descendant
static uint16_t icsp_lire(uint8_t c)
{
    icsp_commande(c);
    icsp_dat(false);
    icsp_dat_pilote(false);
    uint32_t v = 0;
    for (uint8_t i = 0; i < 16; i++) {
        icsp_clk(true);
        esp_rom_delay_us(ICSP_DEMI_US);
        if (icsp_dat_lu()) v |= 1UL << i;
        icsp_clk(false);
        esp_rom_delay_us(ICSP_DEMI_US);
    }
    esp_rom_delay_us(ICSP_DEMI_US);
    icsp_dat_pilote(true);
    esp_rom_delay_us(ICSP_TDLY_US);
    return (uint16_t)((v >> 1) & 0x3FFFu);
}

static void icsp_entrer()
{
    REG_WRITE(GPIO_OUT_W1TC_REG, (1UL << BR_ICSPCLK) | (1UL << BR_ICSPDAT) | (1UL << BR_MCLR));
    pinMode(BR_ICSPCLK, OUTPUT);
    pinMode(BR_ICSPDAT, OUTPUT);
    gpio_set_direction((gpio_num_t)BR_ICSPDAT, GPIO_MODE_INPUT_OUTPUT);
    esp_rom_delay_us(1);                       // TENTS
    pinMode(BR_MCLR, OUTPUT);                  // MCLR à 0
    esp_rom_delay_us(ICSP_TENTH_US);           // TENTH
    icsp_envoyer(ICSP_CLE_LVP, 32);
    icsp_bit(false);                           // 33e coup d'horloge
    esp_rom_delay_us(ICSP_TENTH_US);
}

static void icsp_sortir()
{
    pinMode(BR_ICSPDAT, INPUT);
    pinMode(BR_ICSPCLK, INPUT);
    esp_rom_delay_us(ICSP_TEXIT_US);
    pinMode(BR_MCLR, INPUT);                   // R47 remonte MCLR : le PIC redémarre
}

static const pic_modele_t *pic_modele(uint16_t devid)
{
    for (uint32_t i = 0; i < PIC_NB_MODELES; i++)
        if (pic_modeles[i].devid == devid) return &pic_modeles[i];
    return nullptr;
}

static const char *pic_contenu_texte(uint8_t c)
{
    return c == C_VIERGE ? "vierge" : c == C_JPEG2DVB ? "programme JPEG2DVB" : c == C_AUTRE ? "autre programme" : "inconnu";
}

static uint32_t lire_be32(const uint8_t *p)
{
    return ((uint32_t)p[0] << 24) | ((uint32_t)p[1] << 16) | ((uint32_t)p[2] << 8) | p[3];
}

// fréquence de sortie (demi-MHz) d'une image EEPROM ; 0 si signature, somme ou registres incohérents
static uint32_t eeprom_frequence(const uint8_t *ee)
{
    uint32_t somme = 0;
    for (uint32_t i = 0; i < ADF_EEPROM_OCTETS; i++) somme += ee[i];
    if (ee[24] != ADF_SIGNATURE || (somme & 0xFFu) != 0u) return 0;
    const uint32_t r0 = lire_be32(ee + 20), r1 = lire_be32(ee + 16), r4 = lire_be32(ee + 4);
    const uint32_t int_n = (r0 >> 15) & 0xFFFFu, frac = (r0 >> 3) & 0xFFFu, mod = (r1 >> 3) & 0xFFFu;
    const uint32_t div = 1u << ((r4 >> 20) & 7u);
    if (mod < 2u || frac >= mod) return 0;
    const uint32_t num = 2u * ADF_PFD_MHZ * (int_n * mod + frac), den = mod * div;
    if (num % den) return 0;
    const uint32_t f = num / den;
    return (f >= ADF_F_MIN_DEMI && f <= ADF_F_MAX_DEMI) ? f : 0;
}

// entrée en programmation, DEVID et REVID ; renvoie le modèle, ou nullptr après sortie
static const pic_modele_t *pic_identifier(char *msg, size_t lmsg)
{
    etat_phase("Entrée en programmation basse tension", 2);
    icsp_entrer();
    icsp_pc(PIC_ADR_DEVID);
    const uint16_t devid = icsp_lire(CMD_LIRE);
    icsp_pc(PIC_ADR_REVID);
    const uint16_t revid = icsp_lire(CMD_LIRE);
    const pic_modele_t *m = pic_modele(devid);
    xSemaphoreTake(verrou, portMAX_DELAY);
    etat.pic_lu = true;
    etat.devid = devid;
    etat.revid = revid;
    etat.pic_idx = m ? (int8_t)(m - pic_modeles) : -1;
    etat.pic_contenu = C_INCONNU;
    etat.pic_version[0] = '\0';
    etat.pic_ee = 0;
    etat.pic_ee_freq = 0;
    xSemaphoreGive(verrou);
    journal_printf("PIC : DEVID %04Xh, REVID %04Xh — %s", devid, revid, m ? m->nom : "modèle non pris en charge");
    if (!m) {
        icsp_sortir();
        if (devid == 0x3FFFu || devid == 0x0000u)
            snprintf(msg, lmsg, "PIC : pas de réponse (DEVID %04Xh) — PIC absent, non alimenté ou LVP désactivé", devid);
        else
            snprintf(msg, lmsg, "PIC : DEVID %04Xh non pris en charge — modèles acceptés : PIC16(L)F18323, 18324, 18325, 18326", devid);
    }
    return m;
}

// lecture complète (mémoire programme, configuration, User ID, EEPROM) ; met à jour l'état
static uint8_t pic_examiner(const pic_modele_t *m, uint8_t p0, uint8_t p1)
{
    bool vierge = true, fw = true;
    uint16_t cfg[4], uid[4];
    uint8_t ee[ADF_EEPROM_OCTETS];
    icsp_pc(0);
    for (uint32_t a = 0; a < m->flash; a++) {
        const uint16_t v = icsp_lire(CMD_LIRE_INC);
        if (v != 0x3FFFu) vierge = false;
        if (v != ((a < PIC_FW_NB_MOTS) ? pic_fw_mots[a] : 0x3FFFu)) fw = false;
        if ((a & 511u) == 511u) etat_phase("Lecture de la mémoire programme", p0 + (uint8_t)((p1 - p0) * a / m->flash));
    }
    icsp_pc(PIC_ADR_USERID);
    for (uint32_t k = 0; k < 4; k++) uid[k] = icsp_lire(CMD_LIRE_INC);
    icsp_pc(PIC_ADR_CONFIG);
    for (uint32_t k = 0; k < 4; k++) {
        cfg[k] = icsp_lire(CMD_LIRE_INC);
        if ((cfg[k] ^ pic_fw_config[k]) & pic_fw_config_masque[k]) fw = false;
    }
    icsp_pc(PIC_ADR_EEPROM);
    for (uint32_t i = 0; i < ADF_EEPROM_OCTETS; i++) ee[i] = (uint8_t)icsp_lire(CMD_LIRE_INC);

    const uint8_t contenu = vierge ? C_VIERGE : fw ? C_JPEG2DVB : C_AUTRE;
    char version[24] = "";
    if (contenu == C_JPEG2DVB) {
        if (uid[0] == pic_fw_userid[0] && uid[1] == pic_fw_userid[1] && uid[2] == pic_fw_userid[2])
            snprintf(version, sizeof version, "%u.%u.%u", (unsigned)(uid[3] >> 8), (unsigned)((uid[3] >> 4) & 15u), (unsigned)(uid[3] & 15u));
        else
            strlcpy(version, "1.0.0 (sans repère)", sizeof version);
    }
    const uint32_t f = eeprom_frequence(ee);
    xSemaphoreTake(verrou, portMAX_DELAY);
    etat.pic_contenu = contenu;
    strlcpy(etat.pic_version, version, sizeof etat.pic_version);
    etat.pic_ee = f ? 1 : 2;
    etat.pic_ee_freq = f;
    xSemaphoreGive(verrou);
    char t[24] = "";
    if (f) frequence_texte(f, t, sizeof t);
    journal_printf("PIC : %s%s%s, configuration %04X %04X %04X %04X, User ID %04X %04X %04X %04X, EEPROM %s%s",
                   pic_contenu_texte(contenu), version[0] ? " " : "", version,
                   cfg[0], cfg[1], cfg[2], cfg[3], uid[0], uid[1], uid[2], uid[3],
                   f ? t : "sans image valide", f ? " MHz" : "");
    return contenu;
}

// écriture des 26 octets d'EEPROM (zone effacée) puis relecture
static bool pic_eeprom(const uint8_t *ee, uint8_t p0, char *msg, size_t lmsg)
{
    icsp_pc(PIC_ADR_EEPROM);
    for (uint32_t i = 0; i < ADF_EEPROM_OCTETS; i++) {
        etat_phase("Écriture de l'EEPROM", p0 + (uint8_t)(10 * i / ADF_EEPROM_OCTETS));
        icsp_charger(CMD_CHARGER, ee[i]);
        icsp_commande(CMD_PROG_INTERNE);
        attente_ms(ICSP_TPINT_EE_MS);
        icsp_commande(CMD_INCREMENTER);
    }
    icsp_pc(PIC_ADR_EEPROM);
    for (uint32_t i = 0; i < ADF_EEPROM_OCTETS; i++) {
        const uint16_t v = icsp_lire(CMD_LIRE_INC) & 0xFFu;
        if (v != ee[i]) {
            snprintf(msg, lmsg, "PIC : EEPROM %02lXh fausse : lu %02Xh, attendu %02Xh",
                     (unsigned long)i, v, ee[i]);
            return false;
        }
    }
    return true;
}

// première programmation : effacement, programme, User ID, configuration, EEPROM, vérification
static bool pic_programmer(const uint8_t *ee, char *msg, size_t lmsg)
{
    uint16_t v;
    const pic_modele_t *m = pic_identifier(msg, lmsg);
    if (!m) return false;

    // effacement global : mémoire programme, User ID, configuration, puis EEPROM
    etat_phase("Effacement global", 5);
    icsp_pc(PIC_ADR_USERID);
    icsp_commande(CMD_EFFACER_TOUT);
    attente_ms(ICSP_TERAB_MS);
    icsp_pc(PIC_ADR_EEPROM);
    icsp_commande(CMD_EFFACER_TOUT);
    attente_ms(ICSP_TERAB_MS);

    // mémoire programme par rangées de 32 mots
    const uint32_t rangees = (PIC_FW_NB_MOTS + ICSP_RANGEE - 1) / ICSP_RANGEE;
    for (uint32_t r = 0; r < rangees; r++) {
        etat_phase("Écriture de la mémoire programme", 10 + (uint8_t)(20 * r / rangees));
        icsp_pc(r * ICSP_RANGEE);
        for (uint32_t i = 0; i < ICSP_RANGEE; i++) {
            uint32_t a = r * ICSP_RANGEE + i;
            uint16_t mot = (a < PIC_FW_NB_MOTS) ? pic_fw_mots[a] : 0x3FFFu;
            icsp_charger(i < ICSP_RANGEE - 1 ? CMD_CHARGER_INC : CMD_CHARGER, mot);
        }
        icsp_commande(CMD_PROG_INTERNE);
        attente_ms(ICSP_TPINT_PROG_MS);
    }

    // User ID (repère JPEG2DVB + version), un mot à la fois
    etat_phase("Écriture du repère User ID", 32);
    for (uint32_t k = 0; k < 4; k++) {
        icsp_pc(PIC_ADR_USERID + k);
        icsp_charger(CMD_CHARGER, pic_fw_userid[k]);
        icsp_commande(CMD_PROG_INTERNE);
        attente_ms(ICSP_TPINT_CONF_MS);
    }

    // mots de configuration (mêmes valeurs et mêmes masques sur les 8 modèles)
    etat_phase("Écriture de la configuration", 36);
    for (uint32_t k = 0; k < 4; k++) {
        icsp_pc(PIC_ADR_CONFIG + k);
        icsp_charger(CMD_CHARGER, pic_fw_config[k]);
        icsp_commande(CMD_PROG_INTERNE);
        attente_ms(ICSP_TPINT_CONF_MS);
    }

    // EEPROM, un octet à la fois, puis relecture
    if (!pic_eeprom(ee, 40, msg, lmsg)) {
        icsp_sortir();
        return false;
    }

    // relecture de toute la mémoire programme du modèle
    etat_phase("Vérification", 52);
    icsp_pc(0);
    for (uint32_t a = 0; a < m->flash; a++) {
        uint16_t attendu = (a < PIC_FW_NB_MOTS) ? pic_fw_mots[a] : 0x3FFFu;
        v = icsp_lire(CMD_LIRE_INC);
        if (v != attendu) {
            icsp_sortir();
            snprintf(msg, lmsg, "PIC : vérification fausse en %04lXh : lu %04Xh, attendu %04Xh",
                     (unsigned long)a, v, attendu);
            return false;
        }
        if ((a & 511u) == 511u) etat_phase("Vérification", 52 + (uint8_t)(40 * a / m->flash));
    }
    icsp_pc(PIC_ADR_USERID);
    for (uint32_t k = 0; k < 4; k++) {
        v = icsp_lire(CMD_LIRE_INC);
        if (v != pic_fw_userid[k]) {
            icsp_sortir();
            snprintf(msg, lmsg, "PIC : User ID %04lXh faux : lu %04Xh, attendu %04Xh",
                     (unsigned long)(PIC_ADR_USERID + k), v, pic_fw_userid[k]);
            return false;
        }
    }
    icsp_pc(PIC_ADR_CONFIG);
    for (uint32_t k = 0; k < 4; k++) {
        v = icsp_lire(CMD_LIRE_INC);
        if ((v ^ pic_fw_config[k]) & pic_fw_config_masque[k]) {
            icsp_sortir();
            snprintf(msg, lmsg, "PIC : configuration %04lXh fausse : lu %04Xh, attendu %04Xh",
                     (unsigned long)(PIC_ADR_CONFIG + k), v, pic_fw_config[k]);
            return false;
        }
    }
    etat_phase("Sortie de programmation", 96);
    icsp_sortir();
    xSemaphoreTake(verrou, portMAX_DELAY);
    etat.pic_contenu = C_JPEG2DVB;
    strlcpy(etat.pic_version, PIC_FW_VERSION, sizeof etat.pic_version);
    etat.pic_ee = 1;
    etat.pic_ee_freq = eeprom_frequence(ee);
    xSemaphoreGive(verrou);
    snprintf(msg, lmsg, "%s programmé et vérifié", m->nom);
    return true;
}

// écriture de la fréquence : EEPROM seule, si le programme JPEG2DVB est en place
static bool pic_frequence(const uint8_t *ee, char *msg, size_t lmsg)
{
    const pic_modele_t *m = pic_identifier(msg, lmsg);
    if (!m) return false;
    const uint8_t c = pic_examiner(m, 5, 70);
    if (c != C_JPEG2DVB) {
        icsp_sortir();
        snprintf(msg, lmsg, "%s %s : utiliser « Programmer le PIC » (première programmation)",
                 m->nom, c == C_VIERGE ? "vierge" : "avec un autre programme");
        return false;
    }
    etat_phase("Effacement de l'EEPROM", 75);
    icsp_pc(PIC_ADR_EEPROM);                   // F000h : EEPROM seule (DS40001738, tableau 3-2)
    icsp_commande(CMD_EFFACER_TOUT);
    attente_ms(ICSP_TERAB_MS);
    if (!pic_eeprom(ee, 80, msg, lmsg)) {
        icsp_sortir();
        return false;
    }
    etat_phase("Sortie de programmation", 96);
    icsp_sortir();
    xSemaphoreTake(verrou, portMAX_DELAY);
    etat.pic_ee = 1;
    etat.pic_ee_freq = eeprom_frequence(ee);
    xSemaphoreGive(verrou);
    snprintf(msg, lmsg, "%s : EEPROM écrite et vérifiée", m->nom);
    return true;
}

// LD = 1 stable (3 lectures à 10 ms) avant LD_ATTENTE_MS
static bool attendre_ld()
{
    const uint32_t t0 = millis();
    uint8_t stable = 0;
    attente_ms(LD_DEMARRAGE_MS);
    while (millis() - t0 < LD_ATTENTE_MS) {
        stable = digitalRead(BR_LD) ? stable + 1 : 0;
        if (stable >= 3) return true;
        attente_ms(10);
    }
    return false;
}

static void travail_pic_lire()
{
    char msg[160];
    etat_texte(etat.action, sizeof etat.action, "PIC : lecture");
    etat_resultat(Q_AUCUN, "En cours");
    const pic_modele_t *m = pic_identifier(msg, sizeof msg);
    if (!m) {
        etat_resultat(Q_ERREUR, msg);
        return;
    }
    const uint8_t c = pic_examiner(m, 5, 95);
    icsp_sortir();
    Etat e;
    xSemaphoreTake(verrou, portMAX_DELAY);
    e = etat;
    xSemaphoreGive(verrou);
    char t[24] = "";
    if (e.pic_ee_freq) frequence_texte(e.pic_ee_freq, t, sizeof t);
    snprintf(msg, sizeof msg, "%s : %s%s%s — EEPROM %s%s", m->nom, pic_contenu_texte(c),
             e.pic_version[0] ? " " : "", e.pic_version,
             e.pic_ee_freq ? t : "sans image valide", e.pic_ee_freq ? " MHz" : "");
    etat_phase("Terminé", 100);
    etat_resultat(c == C_JPEG2DVB && e.pic_ee_freq ? Q_OK : Q_ALERTE, msg);
}

// complet : première programmation ; sinon fréquence seule (EEPROM)
static void travail_pic(bool complet)
{
    adf4351_t c = pll_demande;
    const uint32_t f = pll_demande_f;
    char t[24], msg[160];
    frequence_texte(f, t, sizeof t);
    {
        char a[64];
        snprintf(a, sizeof a, complet ? "PIC : programmation complète, %s MHz" : "PIC : fréquence %s MHz", t);
        etat_texte(etat.action, sizeof etat.action, a);
    }
    etat_resultat(Q_AUCUN, "En cours");
    journal_printf("PIC : %s pour %s MHz (diviseur %lu, INT %lu, FRAC %lu)",
                   complet ? "programmation complète" : "écriture de la fréquence", t,
                   (unsigned long)c.diviseur, (unsigned long)c.int_n, (unsigned long)c.frac);
    if (!(complet ? pic_programmer(c.eeprom, msg, sizeof msg) : pic_frequence(c.eeprom, msg, sizeof msg))) {
        etat_resultat(Q_ERREUR, msg);
        return;
    }
    journal_ligne(msg);
    xSemaphoreTake(verrou, portMAX_DELAY);
    etat.freq_demi = f;
    xSemaphoreGive(verrou);
    prefs.putUInt("freq2", f);
    etat_phase("Attente du verrouillage de la PLL", 98);
    const size_t n = strlen(msg);
    if (attendre_ld()) {
        snprintf(msg + n, sizeof msg - n, " à %s MHz — PLL verrouillée", t);
        etat_resultat(Q_OK, msg);
    } else {
        snprintf(msg + n, sizeof msg - n, " à %s MHz — PLL non verrouillée", t);
        etat_resultat(Q_ALERTE, msg);
    }
}


// ══════════════════════════════════════════════════════════════
//  FPGA — JTAG-DirectC
// ══════════════════════════════════════════════════════════════

static void jtag_prendre()
{
    REG_WRITE(GPIO_OUT_W1TS_REG, (1UL << JPEG2DVB_GPIO_TMS) | (1UL << JPEG2DVB_GPIO_TDI));
    REG_WRITE(GPIO_OUT_W1TC_REG, (1UL << JPEG2DVB_GPIO_TCK) | (1UL << JPEG2DVB_GPIO_TRSTB));
    pinMode(JPEG2DVB_GPIO_TDO, INPUT);
    pinMode(JPEG2DVB_GPIO_TCK, OUTPUT);
    pinMode(JPEG2DVB_GPIO_TMS, OUTPUT);
    pinMode(JPEG2DVB_GPIO_TDI, OUTPUT);
    pinMode(JPEG2DVB_GPIO_TRSTB, OUTPUT);
}

static void jtag_liberer()
{
    pinMode(JPEG2DVB_GPIO_TCK, INPUT);
    pinMode(JPEG2DVB_GPIO_TMS, INPUT);
    pinMode(JPEG2DVB_GPIO_TDI, INPUT);
    pinMode(JPEG2DVB_GPIO_TRSTB, INPUT);
    pinMode(JPEG2DVB_GPIO_TDO, INPUT);
}

// exécute une action DirectC et journalise son code
static uint8_t directc(uint8_t action, const char *phase)
{
    etat_phase(phase, 0);
    journal_printf("--- DirectC : %s ---", phase);
    uint8_t err = jpeg2dvb_executer(action);
    journal_vider_ligne();
    const uint32_t id = jpeg2dvb_idcode();
    if (id & 0x0FFFFFFFu) {
        xSemaphoreTake(verrou, portMAX_DELAY);
        etat.idcode = id;
        etat.idcode_lu = true;
        strlcpy(etat.fpga_nom, nom_fpga(id), sizeof etat.fpga_nom);
        xSemaphoreGive(verrou);
    }
    if (jpeg2dvb_erreur_dat()) journal_ligne("DirectC : lecture du fichier DAT incomplète");
    journal_printf("DirectC : code %u (%s), ERROR_CODE %04Xh", err, texte_directc(err), jpeg2dvb_code_sortie());
    return err;
}

static void travail_fpga(bool programmer)
{
    char msg[128];
    etat_texte(etat.action, sizeof etat.action, programmer ? "FPGA : programmer et vérifier" : "FPGA : identifier");
    etat_resultat(Q_AUCUN, "En cours");
    if (FFat.exists(F_DAT)) dat_fichier = FFat.open(F_DAT, FILE_READ);
    if (!dat_fichier) {
        etat_resultat(Q_ERREUR, "FPGA : fichier /fpga.dat absent");
        return;
    }
    // HF coupée : PIC tenu en reset, PDBRF tombe à 0 par R46
    REG_WRITE(GPIO_OUT_W1TC_REG, 1UL << BR_MCLR);
    pinMode(BR_MCLR, OUTPUT);
    jtag_prendre();

    uint8_t err;
    const char *etape;
    if (!programmer) {
        etape = "identification";
        err = directc(JPEG2DVB_ACTION_IDCODE, "Lecture de l'IDCODE");
        if (err == 0) {
            etape = "informations du composant";
            err = directc(JPEG2DVB_ACTION_INFO, "Informations du composant");
        }
    } else {
        etape = "programmation";
        err = directc(JPEG2DVB_ACTION_PROGRAMMER, "Programmation (effacement puis écriture)");
        if (err == 0) {
            etape = "vérification";
            err = directc(JPEG2DVB_ACTION_VERIFIER, "Vérification");
        }
    }

    // fin, quel que soit le résultat
    jtag_liberer();
    dat_fichier.close();
    pinMode(BR_MCLR, INPUT);                   // le PIC redémarre et reprogramme la PLL

    xSemaphoreTake(verrou, portMAX_DELAY);
    const bool id_ok = etat.idcode_lu;
    const uint32_t id = etat.idcode;
    xSemaphoreGive(verrou);
    if (err == 0) {
        if (id_ok) snprintf(msg, sizeof msg, "FPGA : %s réussie — IDCODE %08lXh (%s)",
                            programmer ? "programmation et vérification" : "identification",
                            (unsigned long)id, nom_fpga(id));
        else snprintf(msg, sizeof msg, "FPGA : %s réussie", programmer ? "programmation et vérification" : "identification");
        etat_phase("Terminé", 100);
        etat_resultat(Q_OK, msg);
    } else {
        snprintf(msg, sizeof msg, "FPGA : échec de la %s — code DirectC %u : %s", etape, err, texte_directc(err));
        etat_resultat(Q_ERREUR, msg);
    }
}


// ══════════════════════════════════════════════════════════════
//  TÂCHE DE TRAVAIL (FreeRTOS)
// ══════════════════════════════════════════════════════════════

static void tache_travail(void *)
{
    for (;;) {
        ulTaskNotifyTake(pdTRUE, portMAX_DELAY);
        switch (tache_en_cours) {
            case T_PIC_LIRE:  travail_pic_lire(); break;
            case T_PIC_PROG:  travail_pic(true); break;
            case T_PIC_EE:    travail_pic(false); break;
            case T_FPGA_ID:   travail_fpga(false); break;
            case T_FPGA_PROG: travail_fpga(true); break;
            default: break;
        }
        etat_phase("", 0);
        tache_en_cours = T_AUCUNE;
        ecran_modifie = true;
    }
}

// appelée uniquement depuis loop() (serveur web)
static bool demander(uint8_t t)
{
    if (occupe()) return false;
    tache_en_cours = t;
    xTaskNotifyGive(h_travail);
    return true;
}


// ══════════════════════════════════════════════════════════════
//  FICHIER DAT
// ══════════════════════════════════════════════════════════════

static void dat_examiner()
{
    File f;
    if (FFat.exists(F_DAT)) f = FFat.open(F_DAT, FILE_READ);
    if (!f) {
        etat.dat_present = false;
        etat.dat_taille = 0;
        etat.dat_crc = 0;
        return;
    }
    const uint32_t taille = f.size();
    uint32_t crc;
    if (prefs.getUInt("dat_taille", 0xFFFFFFFFu) == taille && prefs.isKey("dat_crc")) {
        crc = prefs.getUInt("dat_crc", 0);
    } else {
        uint32_t c = 0xFFFFFFFFu;
        size_t n;
        while ((n = f.read(envoi_tampon, sizeof envoi_tampon)) > 0) c = crc_maj(c, envoi_tampon, n);
        crc = ~c;
        prefs.putUInt("dat_taille", taille);
        prefs.putUInt("dat_crc", crc);
    }
    f.close();
    etat.dat_present = true;
    etat.dat_taille = taille;
    etat.dat_crc = crc;
}

static bool envoi_vider()
{
    if (!envoi.n) return true;
    const bool ok = envoi.f.write(envoi_tampon, envoi.n) == envoi.n;
    envoi.n = 0;
    return ok;
}

static void http_envoi_donnees()
{
    HTTPUpload &u = serveur.upload();
    switch (u.status) {
        case UPLOAD_FILE_START: {
            envoi.refuse = occupe();
            envoi.ok = false;
            envoi.erreur[0] = '\0';
            if (envoi.refuse) {
                strlcpy(envoi.erreur, "occupé : une opération est en cours", sizeof envoi.erreur);
                return;
            }
            String nom = u.filename;
            nom.toLowerCase();
            if (!nom.endsWith(".dat")) {
                envoi.refuse = true;
                strlcpy(envoi.erreur, "le fichier doit être un .dat", sizeof envoi.erreur);
                return;
            }
            if (FFat.exists(F_TMP)) FFat.remove(F_TMP);
            envoi.f = FFat.open(F_TMP, FILE_WRITE);
            envoi.ok = (bool)envoi.f;
            if (!envoi.ok) strlcpy(envoi.erreur, "création du fichier impossible", sizeof envoi.erreur);
            envoi.actif = true;
            envoi.taille = 0;
            envoi.n = 0;
            envoi.crc = 0xFFFFFFFFu;
            etat_texte(etat.action, sizeof etat.action, "FPGA : réception du fichier DAT");
            journal_printf("Envoi : réception de %s", u.filename.c_str());
            break;
        }
        case UPLOAD_FILE_WRITE: {
            if (envoi.refuse || !envoi.ok) return;
            envoi.crc = crc_maj(envoi.crc, u.buf, u.currentSize);
            envoi.taille += u.currentSize;
            size_t i = 0;
            while (i < u.currentSize) {
                size_t m = sizeof envoi_tampon - envoi.n;
                if (m > u.currentSize - i) m = u.currentSize - i;
                memcpy(envoi_tampon + envoi.n, u.buf + i, m);
                envoi.n += m;
                i += m;
                if (envoi.n == sizeof envoi_tampon && !envoi_vider()) {
                    envoi.ok = false;
                    strlcpy(envoi.erreur, "écriture FFat impossible (espace plein ?)", sizeof envoi.erreur);
                    return;
                }
            }
            break;
        }
        case UPLOAD_FILE_END: {
            if (envoi.refuse) return;
            if (envoi.ok && !envoi_vider()) {
                envoi.ok = false;
                strlcpy(envoi.erreur, "écriture FFat impossible (espace plein ?)", sizeof envoi.erreur);
            }
            if (envoi.f) envoi.f.close();
            if (envoi.ok && envoi.taille == 0) {
                envoi.ok = false;
                strlcpy(envoi.erreur, "fichier vide", sizeof envoi.erreur);
            }
            if (envoi.ok) {
                if (FFat.exists(F_DAT)) FFat.remove(F_DAT);
                envoi.ok = FFat.rename(F_TMP, F_DAT);
                if (!envoi.ok) strlcpy(envoi.erreur, "renommage impossible", sizeof envoi.erreur);
            }
            if (envoi.ok) {
                const uint32_t crc = ~envoi.crc;
                prefs.putUInt("dat_taille", envoi.taille);
                prefs.putUInt("dat_crc", crc);
                xSemaphoreTake(verrou, portMAX_DELAY);
                etat.dat_present = true;
                etat.dat_taille = envoi.taille;
                etat.dat_crc = crc;
                xSemaphoreGive(verrou);
                char m[96];
                snprintf(m, sizeof m, "Fichier DAT enregistré : %lu octets, CRC32 %08lX",
                         (unsigned long)envoi.taille, (unsigned long)crc);
                etat_resultat(Q_OK, m);
            } else {
                if (FFat.exists(F_TMP)) FFat.remove(F_TMP);
                char m[96];
                snprintf(m, sizeof m, "Envoi du fichier DAT : échec, %s", envoi.erreur);
                etat_resultat(Q_ERREUR, m);
            }
            envoi.actif = false;
            break;
        }
        case UPLOAD_FILE_ABORTED:
        default: {
            if (envoi.refuse) return;
            if (envoi.f) envoi.f.close();
            if (FFat.exists(F_TMP)) FFat.remove(F_TMP);
            envoi.ok = false;
            envoi.n = 0;
            strlcpy(envoi.erreur, "envoi interrompu", sizeof envoi.erreur);
            if (envoi.actif) etat_resultat(Q_ERREUR, "Envoi du fichier DAT interrompu");
            envoi.actif = false;
            break;
        }
    }
}

static void http_envoi_fin()
{
    if (envoi.refuse) {
        repondre_erreur(409, envoi.erreur);
        return;
    }
    if (!envoi.ok) {
        repondre_erreur(500, envoi.erreur[0] ? envoi.erreur : "envoi incomplet");
        return;
    }
    char b[96];
    snprintf(b, sizeof b, "{\"ok\":true,\"taille\":%lu,\"crc\":\"%08lX\"}",
             (unsigned long)envoi.taille, (unsigned long)~envoi.crc);
    repondre_json(200, b);
}


// ══════════════════════════════════════════════════════════════
//  SERVEUR WEB
// ══════════════════════════════════════════════════════════════

static void http_page()
{
    serveur.sendHeader("Cache-Control", "no-store");
    serveur.send_P(200, "text/html; charset=utf-8", PAGE_PROG);
}

static void http_etat()
{
    Etat e;
    uint32_t jt;
    xSemaphoreTake(verrou, portMAX_DELAY);
    e = etat;
    jt = journal_total;
    xSemaphoreGive(verrou);
    const uint8_t t = tache_en_cours;
    char b[48];
    String s;
    s.reserve(1536);
    s += "{\"version\":";       json_texte(s, VERSION_FW);
    s += ",\"ssid\":";          json_texte(s, AP_SSID);
    s += ",\"ip\":";            json_texte(s, WiFi.softAPIP().toString().c_str());
    s += ",\"pic_devid\":";
    if (e.pic_lu) { snprintf(b, sizeof b, "\"%04X\"", e.devid); s += b; } else s += "null";
    s += ",\"pic_revid\":";
    if (e.pic_lu) { snprintf(b, sizeof b, "\"%04X\"", e.revid); s += b; } else s += "null";
    {
        const pic_modele_t *m = (e.pic_lu && e.pic_idx >= 0) ? &pic_modeles[e.pic_idx] : nullptr;
        s += ",\"pic_modele\":";  json_texte(s, m ? m->nom : "");
        s += ",\"pic_lf\":";      s += (m && m->lf) ? "true" : "false";
        s += ",\"pic_flash\":";   s += String(m ? m->flash : 0);
    }
    s += ",\"pic_contenu\":";
    json_texte(s, e.pic_contenu == C_VIERGE ? "vierge" : e.pic_contenu == C_JPEG2DVB ? "jpeg2dvb"
                : e.pic_contenu == C_AUTRE ? "autre" : "");
    s += ",\"pic_version\":";   json_texte(s, e.pic_version);
    s += ",\"pic_fw_version\":"; json_texte(s, PIC_FW_VERSION);
    s += ",\"pic_ee\":";        json_texte(s, e.pic_ee == 1 ? "valide" : e.pic_ee == 2 ? "invalide" : "");
    s += ",\"pic_ee_freq\":";
    if (e.pic_ee_freq) { frequence_texte(e.pic_ee_freq, b, sizeof b); json_texte(s, b); } else s += "\"\"";
    s += ",\"pic_modeles\":[";
    for (uint32_t i = 0; i < PIC_NB_MODELES; i++) { if (i) s += ','; json_texte(s, pic_modeles[i].nom); }
    s += ']';
    s += ",\"ld\":";            s += digitalRead(BR_LD) ? "1" : "0";
    s += ",\"fpga_idcode\":";
    if (e.idcode_lu) { snprintf(b, sizeof b, "\"%08lX\"", (unsigned long)e.idcode); s += b; } else s += "null";
    s += ",\"fpga_nom\":";      json_texte(s, e.idcode_lu ? e.fpga_nom : "");
    s += ",\"ffat_total\":";    s += String((uint32_t)FFat.totalBytes());
    s += ",\"ffat_libre\":";    s += String((uint32_t)(FFat.totalBytes() - FFat.usedBytes()));
    s += ",\"dat_present\":";   s += e.dat_present ? "true" : "false";
    s += ",\"dat_taille\":";    s += String(e.dat_taille);
    s += ",\"dat_crc\":";
    snprintf(b, sizeof b, "\"%08lX\"", (unsigned long)e.dat_crc); s += b;
    s += ",\"occupe\":";        s += (t != T_AUCUNE || envoi.actif) ? "true" : "false";
    s += ",\"tache\":";
    json_texte(s, t == T_PIC_LIRE ? "pic_lire" : t == T_PIC_PROG ? "pic_prog" : t == T_PIC_EE ? "pic_ee"
                : t == T_FPGA_ID ? "fpga_id" : t == T_FPGA_PROG ? "fpga_prog" : envoi.actif ? "envoi" : "");
    s += ",\"phase\":";         json_texte(s, e.phase);
    s += ",\"progression\":";   s += String(e.progression);
    s += ",\"action\":";        json_texte(s, e.action);
    s += ",\"resultat\":";      json_texte(s, e.resultat);
    s += ",\"qualite\":";
    json_texte(s, e.qualite == Q_OK ? "ok" : e.qualite == Q_ALERTE ? "alerte" : e.qualite == Q_ERREUR ? "erreur" : "");
    s += ",\"journal\":";       s += String(jt);
    s += ",\"freq\":";
    if (e.freq_demi) { frequence_texte(e.freq_demi, b, sizeof b); json_texte(s, b); } else s += "\"\"";
    s += '}';
    repondre_json(200, s);
}

static void http_journal()
{
    const bool suite = serveur.hasArg("depuis");
    const uint32_t depuis = suite ? (uint32_t)serveur.arg("depuis").toInt() : 0;
    String s;
    s.reserve(JOURNAL_ENVOI_MAX * 96);
    xSemaphoreTake(verrou, portMAX_DELAY);
    const uint32_t total = journal_total;
    // sans « depuis » : les dernières lignes
    uint32_t debut = suite ? depuis : (total > JOURNAL_ENVOI_MAX ? total - JOURNAL_ENVOI_MAX : 0);
    if (debut > total) debut = 0;                                  // redémarrage du module
    if (total - debut > JOURNAL_LIGNES) debut = total - JOURNAL_LIGNES;
    uint32_t fin = debut + JOURNAL_ENVOI_MAX;
    if (fin > total) fin = total;
    s += "{\"debut\":";
    s += String(debut);
    s += ",\"suivant\":";
    s += String(fin);
    s += ",\"total\":";
    s += String(total);
    s += ",\"lignes\":[";
    for (uint32_t i = debut; i < fin; i++) {
        if (i != debut) s += ',';
        json_texte(s, journal[i % JOURNAL_LIGNES]);
    }
    s += "]}";
    xSemaphoreGive(verrou);
    repondre_json(200, s);
}

// /pll (ecrire=1 : fréquence seule, EEPROM) et /pic/programmer (première programmation)
static void http_pll_commun(bool programmer)
{
    uint32_t f;
    if (!serveur.hasArg("frequence") || adf4351_analyser(serveur.arg("frequence").c_str(), &f) != 0) {
        repondre_erreur(400, "Fréquence refusée : 950,0 à 2150,0 MHz, par pas de 0,5 MHz");
        return;
    }
    adf4351_t c;
    adf4351_calculer(f, &c);
    const bool ecrire = programmer || serveur.arg("ecrire") == "1";
    if (ecrire) {
        if (occupe()) {
            repondre_erreur(409, "Occupé : une opération est en cours");
            return;
        }
        pll_demande = c;
        pll_demande_f = f;
        demander(programmer ? T_PIC_PROG : T_PIC_EE);
    }
    char b[24];
    String s;
    s.reserve(384);
    frequence_texte(f, b, sizeof b);
    s += "{\"ok\":true,\"frequence\":";
    json_texte(s, b);
    s += ",\"diviseur\":";  s += String(c.diviseur);
    s += ",\"vco\":";       s += String(c.vco_mhz);
    s += ",\"int\":";       s += String(c.int_n);
    s += ",\"frac\":";      s += String(c.frac);
    s += ",\"mod\":";       s += String(ADF_MOD);
    s += ",\"r\":[";
    for (int i = 0; i < 6; i++) {
        snprintf(b, sizeof b, "%s\"%08lX\"", i ? "," : "", (unsigned long)c.r[i]);
        s += b;
    }
    s += "],\"ecriture\":";
    s += ecrire ? "true" : "false";
    s += '}';
    repondre_json(200, s);
}

static void http_pic_lire()
{
    if (occupe()) {
        repondre_erreur(409, "Occupé : une opération est en cours");
        return;
    }
    demander(T_PIC_LIRE);
    repondre_json(200, "{\"ok\":true}");
}

static void http_fpga(uint8_t t)
{
    if (occupe()) {
        repondre_erreur(409, "Occupé : une opération est en cours");
        return;
    }
    if (!FFat.exists(F_DAT)) {
        repondre_erreur(404, "Aucun fichier /fpga.dat : envoyer d'abord le fichier DAT");
        return;
    }
    demander(t);
    repondre_json(200, "{\"ok\":true}");
}

static void http_inconnu()
{
    // portail captif : toute autre adresse renvoie vers la page
    serveur.sendHeader("Location", String("http://") + WiFi.softAPIP().toString() + "/", true);
    serveur.send(302, "text/plain", "");
}


// ══════════════════════════════════════════════════════════════
//  ÉCRAN (M5Unified, police GLCD en page de codes 437)
// ══════════════════════════════════════════════════════════════

#define ECRAN_COLONNES  26

// UTF-8 → CP437 (accents du français), autres caractères → '?'
static void vers_cp437(const char *in, char *out, size_t n)
{
    size_t o = 0;
    const uint8_t *p = (const uint8_t *)in;
    while (*p && o + 1 < n) {
        uint32_t u;
        if (*p < 0x80) u = *p++;
        else if ((*p & 0xE0) == 0xC0 && p[1]) { u = ((p[0] & 0x1Fu) << 6) | (p[1] & 0x3Fu); p += 2; }
        else if ((*p & 0xF0) == 0xE0 && p[1] && p[2]) { u = ((p[0] & 0x0Fu) << 12) | ((p[1] & 0x3Fu) << 6) | (p[2] & 0x3Fu); p += 3; }
        else { p++; u = '?'; }
        uint8_t c;
        switch (u) {
            case 0xE9: c = 0x82; break;   // é
            case 0xE8: c = 0x8A; break;   // è
            case 0xEA: c = 0x88; break;   // ê
            case 0xEB: c = 0x89; break;   // ë
            case 0xE0: c = 0x85; break;   // à
            case 0xE2: c = 0x83; break;   // â
            case 0xE7: c = 0x87; break;   // ç
            case 0xEE: c = 0x8C; break;   // î
            case 0xEF: c = 0x8B; break;   // ï
            case 0xF4: c = 0x93; break;   // ô
            case 0xF9: c = 0x97; break;   // ù
            case 0xFB: c = 0x96; break;   // û
            case 0xFC: c = 0x81; break;   // ü
            case 0xC9: c = 0x90; break;   // É
            case 0xC7: c = 0x80; break;   // Ç
            case 0xC0: c = 'A'; break;    // À
            case 0xC8: case 0xCA: c = 'E'; break;
            case 0xB0: c = 0xF8; break;   // °
            case 0x2014: case 0x2013: c = '-'; break;
            case 0x2192: c = '>'; break;
            default: c = (u < 0x80) ? (uint8_t)u : '?'; break;
        }
        out[o++] = (char)c;
    }
    out[o] = '\0';
}

// écrit un texte en le coupant à ECRAN_COLONNES ; renvoie la ligne suivante (pixels)
static int ecran_texte(int y, uint16_t couleur, const char *utf8, int lignes_max)
{
    char t[160];
    vers_cp437(utf8, t, sizeof t);
    M5.Display.setTextColor(couleur, TFT_BLACK);
    size_t lg = strlen(t), i = 0;
    int n = 0;
    do {
        char seg[ECRAN_COLONNES + 1];
        size_t m = lg - i > ECRAN_COLONNES ? ECRAN_COLONNES : lg - i;
        memcpy(seg, t + i, m);
        seg[m] = '\0';
        M5.Display.drawString(seg, 4, y);
        y += 18;
        i += m;
        n++;
    } while (i < lg && n < lignes_max);
    return y;
}

static void ecran_dessiner(bool ld)
{
    Etat e;
    xSemaphoreTake(verrou, portMAX_DELAY);
    e = etat;
    xSemaphoreGive(verrou);
    const bool en_cours = occupe();
    char b[96];

    M5.Display.startWrite();
    M5.Display.fillScreen(TFT_BLACK);
    int y = 4;
    y = ecran_texte(y, TFT_CYAN, "JPEG2DVB programmation", 1);
    y += 4;
    snprintf(b, sizeof b, "Wi-Fi : %s", AP_SSID);
    y = ecran_texte(y, TFT_WHITE, b, 1);
    snprintf(b, sizeof b, "IP    : %s", WiFi.softAPIP().toString().c_str());
    y = ecran_texte(y, TFT_WHITE, b, 1);
    y = ecran_texte(y, ld ? TFT_GREEN : TFT_RED, ld ? "PLL   : verrouillée" : "PLL   : non verrouillée", 1);
    y += 6;
    y = ecran_texte(y, TFT_YELLOW, e.action[0] ? e.action : "Aucune action", 2);
    if (en_cours && e.phase[0]) {
        snprintf(b, sizeof b, "%s %u %%", e.phase, e.progression);
        y = ecran_texte(y, TFT_LIGHTGREY, b, 2);
    }
    if (e.resultat[0]) {
        const uint16_t c = e.qualite == Q_OK ? TFT_GREEN : e.qualite == Q_ALERTE ? TFT_ORANGE
                         : e.qualite == Q_ERREUR ? TFT_RED : TFT_LIGHTGREY;
        ecran_texte(y, c, e.resultat, 5);
    }
    M5.Display.endWrite();
}


// ══════════════════════════════════════════════════════════════
//  SETUP / LOOP
// ══════════════════════════════════════════════════════════════

static void broches_repos()
{
    // toutes les liaisons J7 en entrée sans tirage (haute impédance)
    const uint8_t br[] = { BR_MCLR, BR_ICSPCLK, BR_ICSPDAT, BR_LD,
                           JPEG2DVB_GPIO_TCK, JPEG2DVB_GPIO_TMS, JPEG2DVB_GPIO_TDI,
                           JPEG2DVB_GPIO_TDO, JPEG2DVB_GPIO_TRSTB };
    for (uint8_t p : br) pinMode(p, INPUT);
}

void setup()
{
    broches_repos();

    auto cfg = M5.config();
    cfg.serial_baudrate = 115200;
    cfg.output_power = false;          // 5 V du M5-Bus en entrée (alimenté par la carte)
    cfg.internal_imu = false;
    cfg.internal_rtc = false;
    cfg.internal_mic = false;
    cfg.internal_spk = false;
    cfg.external_imu = false;
    cfg.external_rtc = false;
    cfg.external_display_value = 0;
    cfg.external_speaker_value = 0;
    M5.begin(cfg);
    M5.Power.setExtOutput(false);
    broches_repos();

    M5.Display.setRotation(1);
    M5.Display.setFont(&fonts::Font0);
    M5.Display.setTextSize(2);
    M5.Display.setAttribute(lgfx::utf8_switch, 0);
    M5.Display.setAttribute(lgfx::cp437_switch, 1);
    M5.Display.fillScreen(TFT_BLACK);

    verrou = xSemaphoreCreateMutex();
    crc_init();

    journal_printf("JPEG2DVB prog v%s", VERSION_FW);
    prefs.begin("jpeg2dvb", false);
    etat.pic_idx = -1;
    etat.freq_demi = prefs.getUInt("freq2", 0);
    if (etat.freq_demi && (etat.freq_demi < ADF_F_MIN_DEMI || etat.freq_demi > ADF_F_MAX_DEMI)) etat.freq_demi = 0;

    if (!FFat.begin(true)) journal_ligne("FFat : montage impossible");
    if (FFat.exists(F_TMP)) FFat.remove(F_TMP);
    dat_examiner();
    if (etat.dat_present)
        journal_printf("FFat : /fpga.dat %lu octets, CRC32 %08lX",
                       (unsigned long)etat.dat_taille, (unsigned long)etat.dat_crc);

    WiFi.mode(WIFI_AP);
    WiFi.softAPConfig(IPAddress(192, 168, 4, 1), IPAddress(192, 168, 4, 1), IPAddress(255, 255, 255, 0));
    WiFi.softAP(AP_SSID, AP_MDP);
    dns.setErrorReplyCode(DNSReplyCode::NoError);
    dns.start(DNS_PORT, "*", WiFi.softAPIP());
    if (MDNS.begin(MDNS_NOM)) MDNS.addService("http", "tcp", HTTP_PORT);

    serveur.on("/", HTTP_GET, http_page);
    serveur.on("/etat", HTTP_GET, http_etat);
    serveur.on("/journal", HTTP_GET, http_journal);
    serveur.on("/pll", HTTP_POST, []() { http_pll_commun(false); });
    serveur.on("/pic/lire", HTTP_POST, http_pic_lire);
    serveur.on("/pic/programmer", HTTP_POST, []() { http_pll_commun(true); });
    serveur.on("/fpga/envoi", HTTP_POST, http_envoi_fin, http_envoi_donnees);
    serveur.on("/fpga/id", HTTP_POST, []() { http_fpga(T_FPGA_ID); });
    serveur.on("/fpga/prog", HTTP_POST, []() { http_fpga(T_FPGA_PROG); });
    serveur.onNotFound(http_inconnu);
    serveur.begin();

    xTaskCreatePinnedToCore(tache_travail, "travail", 8192, nullptr, 1, &h_travail, 1);
    journal_printf("Wi-Fi : %s, http://%s/", AP_SSID, WiFi.softAPIP().toString().c_str());
}

void loop()
{
    static uint32_t t_ecran = 0;
    static int ld_avant = -1;
    serveur.handleClient();
    M5.update();
    const uint32_t m = millis();
    if (m - t_ecran >= 250) {
        t_ecran = m;
        const int ld = digitalRead(BR_LD);
        if (ld != ld_avant || ecran_modifie) {
            ld_avant = ld;
            ecran_modifie = false;
            ecran_dessiner(ld);
        }
    }
    delay(1);
}
