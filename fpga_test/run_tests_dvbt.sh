#!/bin/sh
#==============================================================================
#  Nom        : run_tests_dvbt.sh
#  Projet     : JPEG2DVB, portage FPGA (mode DVB-T)
#  Objet      : bancs du modulateur DVB-T (dvbt_mod) et de sa liaison au
#               sigma-delta, sur ../vhdl/j2d_i2c_dvb-t.vhd ; référence : dvbt_ref.js
#  Auteur     : Eric PERRET
#  Date       : 2026-11-24
#  Version    : 1.0
#  Licence    : CC BY-NC 4.0
#  Lancement  : sh run_tests_dvbt.sh   (le socle reste testé par run_tests.sh)
#==============================================================================
cd "$(dirname "$0")"
W=work_ghdl_dvbt
D=/tmp/gh
mkdir -p $W $D/vec3 $D/sd
O="--std=08 --workdir=$W -frelaxed"
RTL=../vhdl/j2d_i2c_dvb-t.vhd
ghdl -a $O $RTL ../vhdl/jpeg2dvb_ip_sim.vhd dvbt_tb.vhd dvbt_sd_tb.vhd || exit 1

# 1. dvbt_mod seul : 3 symboles, groupes comparés à la référence
node dvbt_ref.js vect 3 $D/vec3 >/dev/null
ghdl -e $O tb_dvbt
ghdl -r $O tb_dvbt --ieee-asserts=disable-at-0 2>&1 | grep -E "OK |ECHEC" | sed 's/.*(report [a-z]*): //'

# 2. TS → dvbt_mod → sigma-delta : bits recalculés depuis les mots
ghdl -e $O tb_dvbt_sd
ghdl -r $O tb_dvbt_sd --ieee-asserts=disable-at-0 >$D/sd/run.log 2>&1
node dvbt_verif.js $D/sd

# 3. contrôle de synthèse
for top in dvbt_binter dvbt_hgen dvbt_sinter dvbt_cells dvbt_ifft dvbt_fir dvbt_mod dvbs_sd; do
    if ghdl --synth $O $RTL -e $top > $W/$top.synth.vhd 2> $W/$top.synth.log; then
        echo "synth   OK $top : synthétisable (GHDL --synth, $(grep -c latch $W/$top.synth.log) verrou)"
    else
        echo "synth   ECHEC $top : voir $W/$top.synth.log"
    fi
done
