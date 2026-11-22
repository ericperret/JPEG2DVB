/*
 * ══════════════════════════════════════════════════════════════
 *  Nom      : dpuser.c
 *  Projet   : JPEG2DVB — chantier 2 : programmation du FPGA depuis l'ESP32 (M5Stack CoreS3)
 *  Objet    : portage JTAG-DirectC v2021.2 (Microchip) sur ESP32-S3 :
 *             délais, affichage vers le journal, accès paginé au fichier DAT,
 *             point d'entrée des actions. Remplace dpuser.c d'origine (Harmony SAM RH71).
 *  Auteur   : Eric PERRET
 *  Date     : 2026-11-21
 *  Version  : 1.0.0
 * ══════════════════════════════════════════════════════════════
 */
#include <stdio.h>
#include "dpuser.h"
#include "dpalg.h"
#include "dputil.h"
#include "dpcom.h"
#include "jpeg2dvb_port.h"
#include "esp_rom_sys.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"

_Static_assert(JPEG2DVB_ACTION_INFO == DP_DEVICE_INFO_ACTION_CODE, "action INFO");
_Static_assert(JPEG2DVB_ACTION_IDCODE == DP_READ_IDCODE_ACTION_CODE, "action IDCODE");
_Static_assert(JPEG2DVB_ACTION_PROGRAMMER == DP_PROGRAM_ACTION_CODE, "action PROGRAM");
_Static_assert(JPEG2DVB_ACTION_VERIFIER == DP_VERIFY_ACTION_CODE, "action VERIFY");

/* Programmation par broches (JTAG externe), sans MSS */
DPUCHAR hardware_interface = GPIO_SEL;
DPUCHAR enable_mss_support = FALSE;

/* Variables de pagination de dpcom.c, état du TAP de dpjtag.c */
extern DPULONG start_page_address;
extern DPULONG end_page_address;
extern DPUCHAR current_jtag_state;

static uint8_t  erreur_dat = 0u;
static uint32_t cumul_attente_us = 0u;

/* ── Délai ── */
void dp_delay(DPULONG microseconds)
{
    if (microseconds >= 2000u) {
        /* long délai : rend la main aux autres tâches */
        vTaskDelay((TickType_t)(microseconds / 1000u / portTICK_PERIOD_MS) + 1u);
        return;
    }
    esp_rom_delay_us((uint32_t)microseconds);
    cumul_attente_us += (uint32_t)microseconds;
    if (cumul_attente_us >= 50000u) {
        cumul_attente_us = 0u;
        vTaskDelay(1);
    }
}

/* ── RTG4 seulement : sans objet pour PolarFire, TRSTB reste à 1 ── */
void dp_exit_avionics_mode(void)
{
    return;
}

/* ── Accès paginé au fichier DAT (appelé par dp_get_page_data de dpcom.c) ── */
void jpeg2dvb_page_dat(DPULONG adresse)
{
    DPULONG lu = 0u;
    DPULONG i;

    if (return_bytes > PAGE_BUFFER_SIZE) {
        /* adresse au-delà de l'image : aucune donnée */
        return_bytes = 0u;
        erreur_dat = 1u;
    }
    if (return_bytes > 0u) {
        lu = jpeg2dvb_lire_dat((uint32_t)adresse, page_global_buffer, (uint32_t)return_bytes);
    }
    if (lu < return_bytes) {
        for (i = lu; i < return_bytes; i++) {
            page_global_buffer[i] = 0xFFu;
        }
        erreur_dat = 1u;
    }
    if (return_bytes == 0u) {
        start_page_address = 0u;
        end_page_address = 0u;
    } else {
        start_page_address = adresse;
        end_page_address = adresse + return_bytes - 1u;
    }
}

/* ── Point d'entrée ── */
uint8_t jpeg2dvb_executer(uint8_t action)
{
    erreur_dat = 0u;
    unique_exit_code = 0u;
    device_ID = 0u;
    device_rev = 0u;
    current_jtag_state = 0u;     /* état inconnu : dp_top() repart de TEST_LOGIC_RESET */
    Action_code = action;
    return dp_top();
}

uint32_t jpeg2dvb_idcode(void)
{
    return ((uint32_t)device_rev << 28) | ((uint32_t)device_ID & 0x0FFFFFFFu);
}

uint8_t jpeg2dvb_erreur_dat(void)
{
    return erreur_dat;
}

uint16_t jpeg2dvb_code_sortie(void)
{
    return (uint16_t)unique_exit_code;
}

#ifdef ENABLE_DISPLAY
/* ── Affichage : journal web et port série ── */
void dp_report_progress(DPUCHAR value)
{
    jpeg2dvb_progression((uint8_t)value);
}

void dp_display_text(DPCHAR *text)
{
    jpeg2dvb_journal((const char *)text);
}

void dp_display_value(DPULONG value, DPUINT descriptive)
{
    char t[24];
    if (descriptive == HEX) {
        snprintf(t, sizeof t, "%08lX", (unsigned long)value);
    } else if (descriptive == CHR) {
        t[0] = (char)value;
        t[1] = '\0';
    } else {
        snprintf(t, sizeof t, "%lu", (unsigned long)value);
    }
    jpeg2dvb_journal(t);
}

static void afficher_octet(DPUCHAR v, DPUINT descriptive)
{
    char t[8];
    if (descriptive == HEX) {
        snprintf(t, sizeof t, "%02X", (unsigned)v);
    } else if (descriptive == CHR) {
        t[0] = (char)v;
        t[1] = '\0';
    } else {
        snprintf(t, sizeof t, "%u ", (unsigned)v);
    }
    jpeg2dvb_journal(t);
}

/* octets du dernier au premier (ordre d'affichage DirectC) */
void dp_display_array(DPUCHAR *value, DPUINT bytes, DPUINT descriptive)
{
    DPUINT i;
    for (i = 0u; i < bytes; i++) {
        afficher_octet(value[bytes - 1u - i], descriptive);
    }
}

/* octets du premier au dernier */
void dp_display_array_reverse(DPUCHAR *outbuf, DPUINT bytes, DPUINT descriptive)
{
    DPUINT i;
    for (i = 0u; i < bytes; i++) {
        afficher_octet(outbuf[i], descriptive);
    }
}
#endif /* ENABLE_DISPLAY */
