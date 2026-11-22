; ==========================================================================
;  Nom      : pll_boot.asm
;  Projet   : JPEG2DVB — chantier 2 : programme fixe du PIC16F18323 (U6)
;  Objet    : au démarrage, lit dans l'EEPROM les 6 registres de l'ADF4351,
;             vérifie signature et somme, les écrit en SPI 3 fils (R5 → R0),
;             puis PDBRF (RC3) recopie LD (RA2) toutes les ~1 ms
;  Auteur   : Eric PERRET
;  Date     : 2026-11-21
;  Version  : 1.0.0
;  Outil    : outils/pic14.js (assembleur + simulateur) → pic_fw.h
;  Réf.     : DS40001799 (PIC16(L)F18313/18323), DS40001738 (programmation)
; ==========================================================================
;
;  EEPROM (26 octets) :
;    00h-17h : R5, R4, R3, R2, R1, R0 (4 octets chacun, poids fort en premier)
;    18h     : signature 4Ah
;    19h     : contrôle, somme des octets 00h à 19h = 0 modulo 256
;  Lecture de l'EEPROM par FSR0 : adresses 7000h-70FFh (DS40001799 § 11.3.1)
;  Horloge : HFINTOSC 1 MHz → Tcy = 4 µs
; ==========================================================================

; --- registres (adresses complètes ; la banque est choisie par MOVLB) ---
STATUS  equ 0x003
FSR0L   equ 0x004
FSR0H   equ 0x005
PORTA   equ 0x00C
TRISA   equ 0x08C
TRISC   equ 0x08E
LATA    equ 0x10C
LATC    equ 0x10E
ANSELA  equ 0x18C
ANSELC  equ 0x18E

; --- bits ---
Z       equ 2           ; STATUS
LD      equ 2           ; RA2 : LD de l'ADF4351
CLK     equ 0           ; RC0 : CLK de l'ADF4351
DAT     equ 1           ; RC1 : DATA de l'ADF4351
LE      equ 2           ; RC2 : LE de l'ADF4351
PDBRF   equ 3           ; RC3 : PDBRF de l'ADF4351

; --- variables en RAM commune 70h-7Fh (visibles de toutes les banques) ---
cpt1    equ 0x070
cpt2    equ 0x071
somme   equ 0x072
noct    equ 0x073
octet   equ 0x074
nbits   equ 0x075
nmots   equ 0x076

; --- mots de configuration (positions DS40001799) ---
; CONFIG1 : FEXTOSC=OFF, RSTOSC=HFINTOSC 1 MHz, CLKOUTEN=OFF, CSWEN=ON, FCMEN=OFF
        __config 0x8007, 0x1FEC
; CONFIG2 : MCLRE=ON, PWRTE=ON, WDTE=OFF, LPBOREN=OFF, BOREN=ON, BORV=bas,
;           PPS1WAY=ON, STVREN=ON, DEBUG=OFF
        __config 0x8008, 0x3FF1
; CONFIG3 : WRT=OFF, LVP=ON (obligatoire pour la reprogrammation par l'ESP32)
        __config 0x8009, 0x3FFF
; CONFIG4 : CP=OFF, CPD=OFF
        __config 0x800A, 0x3FFF

        org 0x0000

; --- 1. broches ---
debut:  movlb 2
        clrf LATA               ; RA4, RA5 à 0
        clrf LATC               ; RC0..RC5 à 0 (PDBRF = 0 : HF coupée)
        movlb 1
        movlw 0x0F              ; RA0, RA1, RA2, RA3 entrées ; RA4, RA5 sorties
        movwf TRISA
        clrf TRISC              ; RC0..RC5 sorties
        movlb 3
        clrf ANSELA             ; entrées numériques (RA2)
        clrf ANSELC

; --- 2. attente 20 ms ---
        movlw 20
        movwf cpt2
att20:  call att1ms
        decfsz cpt2,f
        goto att20

; --- 3. contrôle de l'image EEPROM ---
        movlw 0x70
        movwf FSR0H
        clrf FSR0L
        clrf somme
        movlw 26
        movwf noct
somme1: moviw FSR0++
        addwf somme,f
        decfsz noct,f
        goto somme1
        movf somme,f            ; Z = 1 si la somme est nulle
        btfss STATUS,Z
        goto echec
        movlw 0x18
        movwf FSR0L
        moviw FSR0++            ; W = signature
        xorlw 0x4A
        btfss STATUS,Z
        goto echec

; --- 4. écriture des 6 mots R5 → R0, bit de poids fort en premier ---
        clrf FSR0L
        movlb 2
        movlw 6
        movwf nmots
mot:    movlw 4
        movwf noct
oct:    moviw FSR0++
        movwf octet
        movlw 8
        movwf nbits
bit:    btfss octet,7
        bcf LATC,DAT
        btfsc octet,7
        bsf LATC,DAT            ; DATA posé
        bsf LATC,CLK            ; CLK à 1
        bcf LATC,CLK            ; CLK à 0
        lslf octet,f
        decfsz nbits,f
        goto bit
        decfsz noct,f
        goto oct
        bsf LATC,LE             ; chargement au front de LE
        bcf LATC,LE
        decfsz nmots,f
        goto mot
        bcf LATC,DAT

; --- 5. boucle : PDBRF recopie LD ---
boucle: movlb 0
        btfsc PORTA,LD
        goto ld1
        movlb 2
        bcf LATC,PDBRF
        goto pause
ld1:    movlb 2
        bsf LATC,PDBRF
pause:  call att1ms
        goto boucle

; --- image EEPROM invalide : HF coupée, rien n'est écrit ---
echec:  movlb 2
        bcf LATC,PDBRF
arret:  goto arret

; --- attente ~1 ms : 2 + 2 + 81 x 3 + 2 + 2 = 251 cycles de 4 µs ---
att1ms: movlw 82
        movwf cpt1
att1:   decfsz cpt1,f
        goto att1
        return

        end
