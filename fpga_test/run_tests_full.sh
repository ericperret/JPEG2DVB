#!/bin/sh
#==============================================================================
#  Nom        : run_tests_full.sh
#  Projet     : JPEG2DVB, portage FPGA (intégration Full : DVB-S, S2, T, C, GMSK)
#  Objet      : rejoue sur ../vhdl/j2d_i2c_dvb-full.vhd les bancs du socle (run_tests.sh), du DVB-T
#               (run_tests_dvbt.sh), du DVB-C (run_tests_dvbc.sh) et du GMSK (run_tests_gmsk.sh) :
#               chaque script est lu, son fichier VHDL remplacé par celui du Full et son dossier de
#               travail renommé (work_full_*), sans modifier les scripts d'origine
#  Auteur     : Eric PERRET
#  Date       : 2026-11-24
#  Version    : 1.0
#  Licence    : CC BY-NC 4.0
#  Lancement  : sh run_tests_full.sh          (les quatre jeux, environ 25 minutes en série)
#               sh run_tests_full.sh gmsk     (un seul : socle, dvbt, dvbc ou gmsk)
#==============================================================================
cd "$(dirname "$0")"
DIR=$(pwd)
lancer() {   # E : nom du jeu (socle, dvbt, dvbc, gmsk) → T : script d'origine adapté, exécuté dans ce dossier
    case $1 in
        socle) src=run_tests.sh ;;
        *)     src=run_tests_$1.sh ;;
    esac
    echo "===== $1 ====="
    sed -e 's#\.\./vhdl/jpeg2dvb_fpga\.vhd#../vhdl/j2d_i2c_dvb-full.vhd#' \
        -e 's#\.\./vhdl/j2d_i2c_dvb-t-[cg]\.vhd#../vhdl/j2d_i2c_dvb-full.vhd#' \
        -e 's#\.\./vhdl/j2d_i2c_dvb-t\.vhd#../vhdl/j2d_i2c_dvb-full.vhd#' \
        -e 's#^W=work_ghdl[_a-z]*$#W=work_full_'"$1"'#' \
        -e 's#^cd "\$(dirname "\$0")"#cd '"$DIR"'#' $src | sh
}
for m in socle dvbt dvbc gmsk; do
    [ -n "$1" ] && [ "$1" != "$m" ] && continue
    lancer $m
done
