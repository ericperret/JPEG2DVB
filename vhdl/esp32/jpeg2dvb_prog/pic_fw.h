/*
 * ══════════════════════════════════════════════════════════════
 *  Nom      : pic_fw.h
 *  Projet   : JPEG2DVB — chantier 2 : programme du PIC de U6
 *  Objet    : programme du PIC en mots de 14 bits, 4 mots de configuration,
 *             repère User ID, table des PIC acceptés (DEVID, mémoire programme)
 *  Auteur   : Eric PERRET
 *  Date     : 2026-11-23
 *  Version  : 1.1.0
 *  Origine  : produit par pic14.js à partir de pll_boot.asm (ne pas modifier)
 * ══════════════════════════════════════════════════════════════
 */
#pragma once
#include <stdint.h>

#define PIC_FW_NB_MOTS   78u
#define PIC_FW_VERSION   "1.1.0"

/* User ID 8000h-8003h : repère « J2D » + version (majeur << 8 | mineur << 4 | correctif) */
static const uint16_t pic_fw_userid[4] = { 0x004A, 0x0032, 0x0044, 0x0110 };

/* PIC 14 broches acceptés (broche à broche compatibles avec U6) */
typedef struct { const char *nom; uint16_t devid; uint16_t flash; uint8_t lf; } pic_modele_t;
#define PIC_NB_MODELES   8u
static const pic_modele_t pic_modeles[PIC_NB_MODELES] = {
  { "PIC16F18323", 0x3067u, 2048u, 0u },
  { "PIC16LF18323", 0x3069u, 2048u, 1u },
  { "PIC16F18324", 0x303Au, 4096u, 0u },
  { "PIC16LF18324", 0x303Cu, 4096u, 1u },
  { "PIC16F18325", 0x303Eu, 8192u, 0u },
  { "PIC16LF18325", 0x3040u, 8192u, 1u },
  { "PIC16F18326", 0x30A4u, 16384u, 0u },
  { "PIC16LF18326", 0x30A6u, 16384u, 1u }
};

/* mémoire programme, à partir de 0000h (mot non utilisé = 3FFFh) */
static const uint16_t pic_fw_mots[PIC_FW_NB_MOTS] = {
  /* 0000 */ 0x0022,   /* movlb 2 */
  /* 0001 */ 0x018C,   /* clrf LATA */
  /* 0002 */ 0x018E,   /* clrf LATC */
  /* 0003 */ 0x0021,   /* movlb 1 */
  /* 0004 */ 0x300F,   /* movlw 0x0F */
  /* 0005 */ 0x008C,   /* movwf TRISA */
  /* 0006 */ 0x018E,   /* clrf TRISC */
  /* 0007 */ 0x0023,   /* movlb 3 */
  /* 0008 */ 0x018C,   /* clrf ANSELA */
  /* 0009 */ 0x018E,   /* clrf ANSELC */
  /* 000A */ 0x3014,   /* movlw 20 */
  /* 000B */ 0x00F1,   /* movwf cpt2 */
  /* 000C */ 0x2049,   /* call att1ms */
  /* 000D */ 0x0BF1,   /* decfsz cpt2,f */
  /* 000E */ 0x280C,   /* goto att20 */
  /* 000F */ 0x3070,   /* movlw 0x70 */
  /* 0010 */ 0x0085,   /* movwf FSR0H */
  /* 0011 */ 0x0184,   /* clrf FSR0L */
  /* 0012 */ 0x01F2,   /* clrf somme */
  /* 0013 */ 0x301A,   /* movlw 26 */
  /* 0014 */ 0x00F3,   /* movwf noct */
  /* 0015 */ 0x0012,   /* moviw FSR0++ */
  /* 0016 */ 0x07F2,   /* addwf somme,f */
  /* 0017 */ 0x0BF3,   /* decfsz noct,f */
  /* 0018 */ 0x2815,   /* goto somme1 */
  /* 0019 */ 0x08F2,   /* movf somme,f */
  /* 001A */ 0x1D03,   /* btfss STATUS,Z */
  /* 001B */ 0x2846,   /* goto echec */
  /* 001C */ 0x3018,   /* movlw 0x18 */
  /* 001D */ 0x0084,   /* movwf FSR0L */
  /* 001E */ 0x0012,   /* moviw FSR0++ */
  /* 001F */ 0x3A4A,   /* xorlw 0x4A */
  /* 0020 */ 0x1D03,   /* btfss STATUS,Z */
  /* 0021 */ 0x2846,   /* goto echec */
  /* 0022 */ 0x0184,   /* clrf FSR0L */
  /* 0023 */ 0x0022,   /* movlb 2 */
  /* 0024 */ 0x3006,   /* movlw 6 */
  /* 0025 */ 0x00F6,   /* movwf nmots */
  /* 0026 */ 0x3004,   /* movlw 4 */
  /* 0027 */ 0x00F3,   /* movwf noct */
  /* 0028 */ 0x0012,   /* moviw FSR0++ */
  /* 0029 */ 0x00F4,   /* movwf octet */
  /* 002A */ 0x3008,   /* movlw 8 */
  /* 002B */ 0x00F5,   /* movwf nbits */
  /* 002C */ 0x1FF4,   /* btfss octet,7 */
  /* 002D */ 0x108E,   /* bcf LATC,DAT */
  /* 002E */ 0x1BF4,   /* btfsc octet,7 */
  /* 002F */ 0x148E,   /* bsf LATC,DAT */
  /* 0030 */ 0x140E,   /* bsf LATC,CLK */
  /* 0031 */ 0x100E,   /* bcf LATC,CLK */
  /* 0032 */ 0x35F4,   /* lslf octet,f */
  /* 0033 */ 0x0BF5,   /* decfsz nbits,f */
  /* 0034 */ 0x282C,   /* goto bit */
  /* 0035 */ 0x0BF3,   /* decfsz noct,f */
  /* 0036 */ 0x2828,   /* goto oct */
  /* 0037 */ 0x150E,   /* bsf LATC,LE */
  /* 0038 */ 0x110E,   /* bcf LATC,LE */
  /* 0039 */ 0x0BF6,   /* decfsz nmots,f */
  /* 003A */ 0x2826,   /* goto mot */
  /* 003B */ 0x108E,   /* bcf LATC,DAT */
  /* 003C */ 0x0020,   /* movlb 0 */
  /* 003D */ 0x190C,   /* btfsc PORTA,LD */
  /* 003E */ 0x2842,   /* goto ld1 */
  /* 003F */ 0x0022,   /* movlb 2 */
  /* 0040 */ 0x118E,   /* bcf LATC,PDBRF */
  /* 0041 */ 0x2844,   /* goto pause */
  /* 0042 */ 0x0022,   /* movlb 2 */
  /* 0043 */ 0x158E,   /* bsf LATC,PDBRF */
  /* 0044 */ 0x2049,   /* call att1ms */
  /* 0045 */ 0x283C,   /* goto boucle */
  /* 0046 */ 0x0022,   /* movlb 2 */
  /* 0047 */ 0x118E,   /* bcf LATC,PDBRF */
  /* 0048 */ 0x2848,   /* goto arret */
  /* 0049 */ 0x3052,   /* movlw 82 */
  /* 004A */ 0x00F0,   /* movwf cpt1 */
  /* 004B */ 0x0BF0,   /* decfsz cpt1,f */
  /* 004C */ 0x284B,   /* goto att1 */
  /* 004D */ 0x0008    /* return */
};

/* mots de configuration 8007h à 800Ah, et masques des bits implémentés */
static const uint16_t pic_fw_config[4] = { 0x1FEC, 0x3FF1, 0x3FFF, 0x3FFF };
static const uint16_t pic_fw_config_masque[4] = { 0x2977, 0x3AEF, 0x2003, 0x0003 };
