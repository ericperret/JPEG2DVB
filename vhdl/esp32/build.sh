#!/bin/bash
# ============================================================
# Nom      : build.sh
# Projet   : JPEG2DVB — chantier 2 : programmation du PIC et du FPGA depuis l'ESP32
# Objet    : compile / flash / moniteur du firmware jpeg2dvb_prog (M5Stack CoreS3),
#            mise en place de JTAG-DirectC (Microchip, non redistribué),
#            contrôles sur PC (calcul ADF4351, programme du PIC)
# Auteur   : Eric PERRET
# Date     : 2026-11-21
# Version  : 1.0.0
# ------------------------------------------------------------
# Usage :
#   ./build.sh            compile seulement
#   ./build.sh compile    compile seulement
#   ./build.sh flash      compile + téléverse
#   ./build.sh mon        moniteur série (quitter : Ctrl-C)
#   ./build.sh all        compile + téléverse + moniteur
#   ./build.sh controle   contrôles sur PC : calcul ADF4351 (gcc),
#                         assemblage et simulation du PIC (node)
# Environnement : arduino-cli dans ~/bin, cœur esp32 3.3.12, M5Unified 0.2.25
# ============================================================

set -e
export PATH="$PATH:$HOME/bin"

ICI="$(cd "$(dirname "$0")" && pwd)"
SKETCH="$ICI/jpeg2dvb_prog"
DC="$SKETCH/src/directc"
BUILD="$ICI/.build"
FQBN="esp32:esp32:esp32s3:CDCOnBoot=cdc,PSRAM=opi,FlashSize=16M,FlashMode=qio,PartitionScheme=app3M_fat9M_16MB"
COEUR_VERSION="3.3.12"
M5U_VERSION="0.2.25"
BAUD=115200

DIRECTC_DEPOT="https://github.com/MicrochipTech/adg_fpga_reconfiguration.git"
DIRECTC_COMMIT="2de7cdc9d2c7ecadb0da81ac5ed396a9a5affea3"
DIRECTC_CHEMIN="fpga_reconfiguration/firmware/src/DirectC"

# fichiers du projet (avertissements interdits) ; le reste de src/directc est DirectC
MOTIF_PROJET='(jpeg2dvb_prog\.ino|prog_page\.h|pic_fw\.h|/src/directc/(dpuser\.c|gpio_hw_interface\.c|jpeg2dvb_port\.h)):[0-9]+:'

# --- environnement de compilation ---------------------------
verifier_outils() {
    command -v arduino-cli >/dev/null || { echo "ERREUR: arduino-cli introuvable (attendu dans ~/bin)"; exit 1; }
    local c m
    c=$(arduino-cli core list 2>/dev/null | awk '$1=="esp32:esp32"{print $2}')
    [ "$c" = "$COEUR_VERSION" ] || { echo "ERREUR: cœur esp32:esp32 $COEUR_VERSION requis (installé : ${c:-aucun})"; exit 1; }
    m=$(arduino-cli lib list 2>/dev/null | awk '$1=="M5Unified"{print $2}')
    [ "$m" = "$M5U_VERSION" ] || { echo "ERREUR: M5Unified $M5U_VERSION requise (installée : ${m:-aucune})"; exit 1; }
}

# --- JTAG-DirectC : récupération (une seule fois) + portage -
preparer_directc() {
    if [ ! -f "$DC/dpalg.c" ]; then
        command -v git >/dev/null || { echo "ERREUR: git introuvable"; exit 1; }
        local TMP S
        TMP=$(mktemp -d)
        trap 'rm -rf "$TMP"' EXIT
        echo "=== Récupération de JTAG-DirectC (Microchip, commit ${DIRECTC_COMMIT:0:7}) ==="
        git -C "$TMP" init -q
        git -C "$TMP" remote add origin "$DIRECTC_DEPOT"
        git -C "$TMP" fetch -q --depth 1 origin "$DIRECTC_COMMIT"
        git -C "$TMP" checkout -q FETCH_HEAD
        S="$TMP/$DIRECTC_CHEMIN"
        [ -f "$S/dpalg.c" ] || { echo "ERREUR: $DIRECTC_CHEMIN introuvable dans le dépôt Microchip"; exit 1; }
        mkdir -p "$DC"
        # copie à plat (Arduino ne met pas les sous-dossiers de src/ dans les chemins d'inclusion) :
        # racine, G5Algo (PolarFire) et JTAG ; seulement les en-têtes de G3Algo, G4Algo et RTG4Algo
        # (inclus par dpalg.c, familles non compilées)
        cp "$S"/*.c "$S"/*.h "$DC/"
        cp "$S"/G5Algo/*.c "$S"/G5Algo/*.h "$DC/"
        cp "$S"/JTAG/*.c "$S"/JTAG/*.h "$DC/"
        cp "$S"/G3Algo/*.h "$S"/G4Algo/*.h "$S"/RTG4Algo/*.h "$DC/"
        cp "$TMP/license.md" "$DC/LICENCE_MICROCHIP.md"
        rm -rf "$TMP"
        trap - EXIT
    fi
    cp "$SKETCH/portage/dpuser.c" "$SKETCH/portage/gpio_hw_interface.c" "$SKETCH/portage/jpeg2dvb_port.h" "$DC/"
    bash "$SKETCH/portage/reglages.sh" "$DC"
}

# --- bilan des avertissements -------------------------------
bilan_avertissements() {
    local LOG="$1" A="$BUILD/avertissements.txt" P D
    grep -E ':[0-9]+:[0-9]+: warning:' "$LOG" | sort -u > "$A" || true
    P=$(grep -cE "$MOTIF_PROJET" "$A" || true)
    D=$(grep '/src/directc/' "$A" | grep -cvE "$MOTIF_PROJET" || true)
    echo "=== Avertissements : projet $P, DirectC $D, bibliothèques $(( $(wc -l < "$A") - P - D )) ==="
    if [ "$D" -gt 0 ]; then
        echo "--- DirectC (Microchip, non modifié) :"
        grep '/src/directc/' "$A" | grep -vE "$MOTIF_PROJET" | sed -E 's|.*/src/directc/||' | sed 's/^/    /'
    fi
    if [ "$P" -gt 0 ]; then
        echo "--- Projet :"
        grep -E "$MOTIF_PROJET" "$A" | sed 's/^/    /'
        echo "ERREUR: avertissements sur les fichiers du projet"
        exit 1
    fi
}

compiler() {
    verifier_outils
    preparer_directc
    mkdir -p "$BUILD"
    local LOG="$BUILD/compilation.log" rc
    set +e
    arduino-cli compile --fqbn "$FQBN" --warnings all --build-path "$BUILD" "$SKETCH" 2>&1 | tee "$LOG"
    rc=${PIPESTATUS[0]}
    set -e
    if [ "$rc" -ne 0 ]; then
        # erreurs uniquement dans DirectC et toutes issues d'avertissements promus (-Werror=) :
        # nouvelle compilation au niveau d'avertissement par défaut du cœur
        if grep -E ': error:' "$LOG" | grep -qv '/src/directc/' \
           || ! grep -qE ': error:.*\[-Werror=' "$LOG" \
           || grep -E ': error:' "$LOG" | grep -qv '\[-Werror='; then
            echo "=== ERREUR DE COMPILATION ==="
            exit 1
        fi
        echo "=== Avertissements DirectC traités en erreurs par le cœur : compilation sans avertissements ==="
        grep -E ': error:' "$LOG" | sed -E 's|.*/src/directc/|    |'
        arduino-cli compile --fqbn "$FQBN" --warnings none --build-path "$BUILD" "$SKETCH" 2>&1 | tee "$LOG.2" \
            || { echo "=== ERREUR DE COMPILATION ==="; exit 1; }
        echo "LIMITE: avertissements des fichiers du projet non contrôlés lors de cette compilation"
    else
        bilan_avertissements "$LOG"
    fi
    echo "=== COMPILATION OK ==="
}

port_serie() {
    PORT=$(ls /dev/ttyACM* 2>/dev/null | head -1)
    [ -z "$PORT" ] && PORT=$(ls /dev/ttyUSB* 2>/dev/null | head -1)
    [ -n "$PORT" ] || { echo "ERREUR: aucun port série (CoreS3 branché en USB ?)"; exit 1; }
}

controler() {
    command -v gcc >/dev/null || { echo "ERREUR: gcc introuvable"; exit 1; }
    command -v node >/dev/null || { echo "ERREUR: node introuvable"; exit 1; }
    local T IMAGES
    T=$(mktemp -d)
    trap 'rm -rf "$T"' EXIT
    echo "=== Calcul des registres ADF4351 (fonction du firmware, gcc) ==="
    sed -n '/^\/\/ >>> CALCUL_ADF4351/,/^\/\/ <<< CALCUL_ADF4351/p' "$SKETCH/jpeg2dvb_prog.ino" > "$T/adf4351_extrait.c"
    [ -s "$T/adf4351_extrait.c" ] || { echo "ERREUR: bloc CALCUL_ADF4351 introuvable"; exit 1; }
    cp "$ICI/outils/test_adf4351.c" "$T/"
    gcc -std=c11 -Wall -Wextra -Werror -O2 -o "$T/test_adf4351" "$T/test_adf4351.c"
    "$T/test_adf4351" | tee "$T/sortie.txt"
    [ "${PIPESTATUS[0]}" -eq 0 ] || exit 1
    IMAGES=$(grep '^IMAGE ' "$T/sortie.txt" | cut -d' ' -f2)
    echo "=== Programme du PIC (pic14.js : assemblage et simulation) ==="
    node "$ICI/outils/pic14.js" asm "$SKETCH/pic/pll_boot.asm" "$T/pic_fw.h"
    cmp -s "$T/pic_fw.h" "$SKETCH/pic_fw.h" \
        || { echo "ERREUR: pic_fw.h n'est pas à jour : node outils/pic14.js asm jpeg2dvb_prog/pic/pll_boot.asm jpeg2dvb_prog/pic_fw.h"; exit 1; }
    echo "pic_fw.h à jour"
    # shellcheck disable=SC2086
    node "$ICI/outils/pic14.js" sim "$SKETCH/pic/pll_boot.asm" $IMAGES
    rm -rf "$T"
    trap - EXIT
    echo "=== CONTRÔLES OK ==="
}

case "${1:-compile}" in
  compile)
    compiler
    ;;
  flash)
    compiler
    port_serie
    arduino-cli upload -p "$PORT" --fqbn "$FQBN" --input-dir "$BUILD" "$SKETCH"
    echo "=== FLASH OK sur $PORT ==="
    ;;
  mon)
    port_serie
    echo "Moniteur $PORT @ $BAUD - Ctrl-C pour quitter"
    arduino-cli monitor -p "$PORT" -c baudrate=$BAUD
    ;;
  all)
    "$0" flash
    sleep 2
    "$0" mon
    ;;
  controle)
    controler
    ;;
  *)
    echo "Usage: $0 [compile|flash|mon|all|controle]"
    exit 1
    ;;
esac
