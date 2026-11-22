#!/bin/bash
# ============================================================
# Nom      : reglages.sh
# Projet   : JPEG2DVB — chantier 2 : programmation du FPGA depuis l'ESP32 (M5Stack CoreS3)
# Objet    : réglages de JTAG-DirectC v2021.2 appliqués par build.sh à la copie
#            src/directc/ (les sources Microchip ne sont pas redistribuées) :
#              - dpuser.h : G5 (PolarFire) activé, RTG4 désactivé, USE_PAGING activé,
#                           prototype de jpeg2dvb_page_dat()
#              - dpcom.c  : dp_get_page_data() complété (lecture de /fpga.dat en FFat)
#            Chaque réglage n'est appliqué qu'une fois (repère « jpeg2dvb »).
# Auteur   : Eric PERRET
# Date     : 2026-11-21
# Version  : 1.0.0
# Usage    : reglages.sh <dossier src/directc>
# ============================================================
set -e
D="$1"
[ -f "$D/dpuser.h" ] && [ -f "$D/dpcom.c" ] || { echo "ERREUR: dpuser.h ou dpcom.c absent de $D"; exit 1; }

H="$D/dpuser.h"
if ! grep -q "jpeg2dvb" "$H"; then
    sed -i \
        -e 's|^#define ENABLE_RTG4_SUPPORT|/* #define ENABLE_RTG4_SUPPORT */ /* jpeg2dvb : désactivé */|' \
        -e 's|^//#define ENABLE_G5_SUPPORT|#define ENABLE_G5_SUPPORT /* jpeg2dvb : PolarFire */|' \
        -e 's|^//#define USE_PAGING|#define USE_PAGING /* jpeg2dvb : lecture paginée du fichier DAT */|' \
        -e 's|^void dp_delay(DPULONG microseconds);|&\nvoid jpeg2dvb_page_dat(DPULONG adresse); /* jpeg2dvb */|' \
        "$H"
fi

C="$D/dpcom.c"
if ! grep -q "jpeg2dvb_page_dat" "$C"; then
    sed -i '/Add a funciton call here to get the page data from the external storage device/{n;s|$|\n    jpeg2dvb_page_dat(image_requested_address); /* jpeg2dvb */|}' "$C"
fi

# contrôle
grep -q "^#define ENABLE_G5_SUPPORT" "$H"                   || { echo "ERREUR: réglage G5 non appliqué ($H)"; exit 1; }
grep -q "^#define USE_PAGING" "$H"                          || { echo "ERREUR: réglage USE_PAGING non appliqué ($H)"; exit 1; }
grep -q "^#define ENABLE_RTG4_SUPPORT" "$H"                 && { echo "ERREUR: RTG4 toujours actif ($H)"; exit 1; }
grep -q "^#define ENABLE_G3_SUPPORT\|^#define ENABLE_G4_SUPPORT" "$H" && { echo "ERREUR: G3/G4 actifs ($H)"; exit 1; }
grep -q "^void jpeg2dvb_page_dat" "$H"                      || { echo "ERREUR: prototype jpeg2dvb_page_dat absent ($H)"; exit 1; }
grep -q "^    jpeg2dvb_page_dat(image_requested_address);" "$C" || { echo "ERREUR: dp_get_page_data non complété ($C)"; exit 1; }
exit 0
