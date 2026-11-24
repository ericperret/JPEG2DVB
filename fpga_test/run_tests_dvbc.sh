#!/bin/sh
#==============================================================================
#  Nom        : run_tests_dvbc.sh
#  Projet     : JPEG2DVB, portage FPGA (mode DVB-C)
#  Objet      : bancs du mode DVB-C (dvbt_mod en c_mode, dvbc_map, SRRC 0,15) et de sa
#               liaison au sigma-delta, sur ../vhdl/j2d_i2c_dvb-t-c.vhd ; référence : dvbc_ref.js
#  Auteur     : Eric PERRET
#  Date       : 2026-11-24
#  Version    : 1.0
#  Licence    : CC BY-NC 4.0
#  Lancement  : sh run_tests_dvbc.sh   (le socle reste testé par run_tests.sh, le DVB-T par run_tests_dvbt.sh)
#==============================================================================
cd "$(dirname "$0")"
W=work_ghdl_dvbc
D=/tmp/gh
mkdir -p $W $D/vecc $D/sdc
O="--std=08 --workdir=$W -frelaxed"
RTL=../vhdl/j2d_i2c_dvb-t-c.vhd
ghdl -a $O $RTL ../vhdl/jpeg2dvb_ip_sim.vhd dvbc_tb.vhd dvbc_sd_tb.vhd || exit 1

# 1. dvbt_mod en DVB-C seul : 800 octets, groupes comparés à la référence
node dvbc_ref.js vect 800 $D/vecc >/dev/null
ghdl -e $O tb_dvbc
ghdl -r $O tb_dvbc -gG_NG=104000 --ieee-asserts=disable-at-0 2>&1 | grep -E "OK |ECHEC" | sed 's/.*(report [a-z]*): //'

# 2. TS → mapper → sigma-delta : bits recalculés depuis les octets
ghdl -e $O tb_dvbc_sd
ghdl -r $O tb_dvbc_sd --ieee-asserts=disable-at-0 >$D/sdc/run.log 2>&1
node dvbc_verif.js $D/sdc

# 3. contrôle de synthèse
for top in dvbc_map dvbt_fir dvbt_mod dvbs_sd; do
    if ghdl --synth $O $RTL -e $top > $W/$top.synth.vhd 2> $W/$top.synth.log; then
        echo "synth   OK $top : synthétisable (GHDL --synth, $(grep -c latch $W/$top.synth.log) verrou)"
    else
        echo "synth   ECHEC $top : voir $W/$top.synth.log"
    fi
done
