#!/bin/sh
#==============================================================================
#  Nom        : run_tests_gmsk.sh
#  Projet     : JPEG2DVB, portage FPGA (mode GMSK)
#  Objet      : bancs du mode GMSK (gmsk_mod, sa liaison au sigma-delta, le flux TS à un
#               programme), sur ../vhdl/j2d_i2c_dvb-t-g.vhd ; référence : gmsk_ref.js
#  Auteur     : Eric PERRET
#  Date       : 2026-11-24
#  Version    : 1.0
#  Licence    : CC BY-NC 4.0
#  Lancement  : sh run_tests_gmsk.sh   (le socle reste testé par run_tests.sh, le DVB-T par run_tests_dvbt.sh)
#               La partie 3 simule 100 000 cycles de la chaîne complète : environ 7 minutes.
#==============================================================================
cd "$(dirname "$0")"
W=work_ghdl_g
D=/tmp/gh
mkdir -p $W $D/sdg
O="--std=08 --workdir=$W -frelaxed"
RTL=../vhdl/j2d_i2c_dvb-t-g.vhd
ghdl -a $O $RTL ../vhdl/jpeg2dvb_ip_sim.vhd gmsk_tb.vhd gmsk_sd_tb.vhd || exit 1

# 1. gmsk_mod seul : 3 000 échantillons, voie Q normale puis inversée, attentes aléatoires
ghdl -e $O tb_gmsk
for inv in 0 1; do
    node gmsk_ref.js vect 3000 $D/gmsk$inv $inv >/dev/null
    ghdl -r $O tb_gmsk -gG_REP=$D/gmsk$inv -gG_INV=$inv --ieee-asserts=disable-at-0 2>&1 | grep -E "OK |ECHEC" | sed 's/.*(report [a-z]*): //'
done

# 2. mesures par calcul : forme d'onde, largeur occupée, sigma-delta, EVM, erreurs de bit
node gmsk_mesure.js 16

# 3. TS → gmsk_mod → sigma-delta : bits recalculés depuis les mots, flux TS à un programme
ghdl -e $O tb_gmsk_sd
ghdl -r $O tb_gmsk_sd -gG_NG=100000 --ieee-asserts=disable-at-0 >$D/sdg/run.log 2>&1
node gmsk_verif.js $D/sdg

# 4. contrôle de synthèse
for top in gmsk_mod es_mux ts_mux dvbs_sd; do
    if ghdl --synth $O $RTL -e $top > $W/$top.synth.vhd 2> $W/$top.synth.log; then
        echo "synth   OK $top : synthétisable (GHDL --synth, $(grep -c latch $W/$top.synth.log) verrou)"
    else
        echo "synth   ECHEC $top : voir $W/$top.synth.log"
    fi
done
