/*
 * ══════════════════════════════════════════════════════════════
 *  Nom      : jpeg2dvb_port.h
 *  Projet   : JPEG2DVB — chantier 2 : programmation du FPGA depuis l'ESP32 (M5Stack CoreS3)
 *  Objet    : interface entre le firmware (jpeg2dvb_prog.ino) et le portage JTAG-DirectC
 *  Auteur   : Eric PERRET
 *  Date     : 2026-11-21
 *  Version  : 1.0.0
 * ══════════════════════════════════════════════════════════════
 */
#ifndef JPEG2DVB_PORT_H
#define JPEG2DVB_PORT_H

#include <stdint.h>

/* ── Broches JTAG (J7 ↔ CoreS3) ── */
#define JPEG2DVB_GPIO_TCK     8u
#define JPEG2DVB_GPIO_TMS     9u
#define JPEG2DVB_GPIO_TDI     17u
#define JPEG2DVB_GPIO_TDO     18u
#define JPEG2DVB_GPIO_TRSTB   1u

/* ── Actions DirectC utilisées (valeurs de dpalg.h, contrôlées dans dpuser.c) ── */
#define JPEG2DVB_ACTION_INFO        1u   /* DP_DEVICE_INFO_ACTION_CODE */
#define JPEG2DVB_ACTION_IDCODE      2u   /* DP_READ_IDCODE_ACTION_CODE */
#define JPEG2DVB_ACTION_PROGRAMMER  5u   /* DP_PROGRAM_ACTION_CODE     */
#define JPEG2DVB_ACTION_VERIFIER    6u   /* DP_VERIFY_ACTION_CODE      */

#ifdef __cplusplus
extern "C" {
#endif

/* fournies par le firmware */
void     jpeg2dvb_journal(const char *texte);
void     jpeg2dvb_progression(uint8_t pourcent);
uint32_t jpeg2dvb_lire_dat(uint32_t adresse, uint8_t *tampon, uint32_t nombre);

/* fournies par le portage */
uint8_t  jpeg2dvb_executer(uint8_t action);   /* lance dp_top(), renvoie le code DirectC */
uint32_t jpeg2dvb_idcode(void);               /* dernier IDCODE lu (révision en bits 31-28) */
uint8_t  jpeg2dvb_erreur_dat(void);           /* 1 si une lecture du fichier DAT a échoué */
uint16_t jpeg2dvb_code_sortie(void);          /* code de sortie détaillé DirectC (ERROR_CODE) */

#ifdef __cplusplus
}
#endif

#endif /* JPEG2DVB_PORT_H */
