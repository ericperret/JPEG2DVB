#!/bin/sh
#===============================================================================
#  Nom        : run_tests.sh
#  Projet     : JPEG2DVB, portage FPGA (émetteur DVB-S 23 cm)
#  Objet      : analyse les sources VHDL-2008 et lance tous les bancs de test
#               GHDL ; chaque banc compare la sortie de son module, au bit près,
#               aux fichiers de référence de JPEG2DVB (ce dossier)
#  Auteur     : Eric PERRET
#  Date       : 2026-10-19
#  Version    : 1.4
#  Usage      : ./run_tests.sh            (dossier fpga_test/)
#               ./run_tests.sh rs         (un seul banc : nom contenant « rs »)
#  Licence    : CC BY-NC 4.0
#  Historique : 1.0  2026-10-19  création
#               1.1  2026-10-19  sources fusionnées ../vhdl/jpeg2dvb_fpga.vhd et
#                                jpeg2dvb_fpga_tb.vhd ; rate_ctrl au contrôle de synthèse
#               1.2  2026-10-19  régulation TM5 : banc rc, quant8 à G_CODE = 0 (code par
#                                rangée), tailles es / ts / video des nouvelles références
#               1.3  2026-10-19  banc sdm (sortie sigma-delta) ; cic8, sdm3, sigma_delta au
#                                contrôle de synthèse
#               1.4  2026-10-19  sortie sigma-delta par tables : sd_entree au contrôle de
#                                synthèse (cic8 retiré)
#===============================================================================
set -e
cd "$(dirname "$0")"
W=work_ghdl
mkdir -p $W
G="ghdl"
O="--std=08 --workdir=$W -frelaxed"

# ordre d'analyse : paquetages, modules, bancs
RTL=../vhdl/jpeg2dvb_fpga.vhd
TB=../vhdl/jpeg2dvb_fpga_tb.vhd
$G -a $O $RTL $TB

# nom | entité | génériques
BANCS="prbs|tb_octets|-gG_DUT=1 -gG_IN=ts.bin -gG_OUT=rand.bin -gG_N_IN=12032 -gG_N_OUT=12032 -gG_PKT=188
rs|tb_octets|-gG_DUT=2 -gG_IN=rand.bin -gG_OUT=rs.bin -gG_N_IN=12032 -gG_N_OUT=13056 -gG_PKT=188
inter|tb_octets|-gG_DUT=3 -gG_IN=rs.bin -gG_OUT=inter.bin -gG_N_IN=13056 -gG_N_OUT=13056 -gG_PKT=204
conv12|tb_conv|
conv23|tb_conv|-gG_FEC=1 -gG_OUT=conv23.bin -gG_N_OUT=19584
conv34|tb_conv|-gG_FEC=2 -gG_OUT=conv34.bin -gG_N_OUT=17408
conv56|tb_conv|-gG_FEC=3 -gG_OUT=conv56.bin -gG_N_OUT=15667
conv78|tb_conv|-gG_FEC=4 -gG_OUT=conv78.bin -gG_N_OUT=14921
qpsk|tb_qpsk|
srrc|tb_srrc|
chaine|tb_backend|
dct|tb_bloc|-gG_DUT=1 -gG_IN=mb0.bin -gG_OUT=dct0.bin
quant8|tb_bloc|-gG_DUT=2 -gG_IN=dct0.bin -gG_OUT=q0.bin -gG_CODE=0
quant1|tb_bloc|-gG_DUT=2 -gG_IN=dct0.bin -gG_OUT=q0_c1.bin -gG_CODE=1
quant31|tb_bloc|-gG_DUT=2 -gG_IN=dct0.bin -gG_OUT=q0_c31.bin -gG_CODE=31
zigzag|tb_bloc|-gG_DUT=3 -gG_IN=q0.bin -gG_OUT=zz0.bin
vlc|tb_vlc|
es|tb_es|-gG_N_OUT=115224
rc|tb_rc|
ts|tb_octets|-gG_DUT=4 -gG_IN=es.bin -gG_OUT=ts_v.bin -gG_N_IN=115224 -gG_N_OUT=183488 -gG_PKT=188
mire|tb_mire|
video|tb_dvbs|-gG_DUT=1 -gG_OUT=mire_ts.bin -gG_N=148708
emetteur|tb_dvbs|-gG_DUT=2 -gG_OUT=mire_iq.cs16 -gG_N=160000
sdm|tb_sdm|"

OK=0; KO=0
echo "$BANCS" | while IFS='|' read -r nom ent gen; do
    [ -n "$1" ] && case "$nom" in *"$1"*) ;; *) continue ;; esac
    $G -e $O $ent >/dev/null
    R=$($G -r $O $ent $gen --ieee-asserts=disable-at-0 2>&1 || true)
    L=$(echo "$R" | grep -E "OK |ECHEC" | sed 's/.*(report [a-z]*): //' | head -1)
    [ -z "$L" ] && L="ECHEC : pas de verdict — $(echo "$R" | tail -1)"
    printf '%-7s %s\n' "$nom" "$L"
done

# contrôle de synthétisabilité (GHDL --synth) des modules de la carte
if [ -z "$1" ] || [ "$1" = "synth" ]; then
    for top in tx_backend dct8x8_int quant_intra zigzag vlc_enc es_mux ts_mux rate_ctrl mire_gen video_enc dvbs_tx sd_entree sdm3 sigma_delta; do
        if $G --synth $O $RTL -e $top > $W/$top.synth.vhd 2> $W/$top.synth.log; then
            echo "synth   OK $top : synthétisable (GHDL --synth, $(grep -c latch $W/$top.synth.log) verrou)"
        else
            echo "synth   ECHEC $top : voir $W/$top.synth.log"
        fi
    done
fi
