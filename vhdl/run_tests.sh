#!/bin/sh
#===============================================================================
#  Nom        : run_tests.sh
#  Projet     : JPEG2DVB, portage FPGA (émetteur DVB-S 23 cm)
#  Objet      : analyse les sources VHDL-2008 et lance tous les bancs de test
#               GHDL ; chaque banc compare la sortie de son module, au bit près,
#               aux fichiers de référence de JPEG2DVB (dossier ref/)
#  Auteur     : Eric PERRET
#  Date       : 2026-10-19
#  Version    : 1.0
#  Usage      : ./run_tests.sh            (depuis le dossier vhdl/)
#               ./run_tests.sh rs         (un seul banc : nom contenant « rs »)
#  Licence    : CC BY-NC 4.0
#  Historique : 1.0  2026-10-19  création
#===============================================================================
set -e
cd "$(dirname "$0")"
W=work_ghdl
mkdir -p $W
G="ghdl"
O="--std=08 --workdir=$W -frelaxed"

# ordre d'analyse : paquetages, modules, bancs
SRC="rtl/dvbs_pkg.vhd rtl/srrc_coef_pkg.vhd
     rtl/prbs_disp.vhd rtl/rs_enc.vhd rtl/interleaver.vhd rtl/conv_enc.vhd rtl/qpsk_map.vhd rtl/srrc_poly.vhd rtl/tx_backend.vhd
     tb/tb_pkg.vhd tb/tb_octets.vhd tb/tb_conv.vhd tb/tb_qpsk.vhd tb/tb_srrc.vhd tb/tb_backend.vhd"
for f in $SRC; do [ -f "$f" ] && $G -a $O "$f"; done

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
chaine|tb_backend|"

OK=0; KO=0
echo "$BANCS" | while IFS='|' read -r nom ent gen; do
    [ -n "$1" ] && case "$nom" in *"$1"*) ;; *) continue ;; esac
    [ -f "tb/$ent.vhd" ] || continue
    $G -e $O $ent >/dev/null
    R=$($G -r $O $ent $gen --ieee-asserts=disable-at-0 2>&1 || true)
    L=$(echo "$R" | grep -E "OK |ECHEC" | sed 's/.*(report [a-z]*): //' | head -1)
    [ -z "$L" ] && L="ECHEC : pas de verdict — $(echo "$R" | tail -1)"
    printf '%-7s %s\n' "$nom" "$L"
done

# contrôle de synthétisabilité (GHDL --synth) des modules de la carte
if [ -z "$1" ] || [ "$1" = "synth" ]; then
    RTL=$(echo "$SRC" | tr ' ' '\n' | grep '^rtl/')
    for top in tx_backend; do
        if $G --synth $O $RTL -e $top > $W/$top.synth.vhd 2> $W/$top.synth.log; then
            echo "synth   OK $top : synthétisable (GHDL --synth, $(grep -c latch $W/$top.synth.log) verrou)"
        else
            echo "synth   ECHEC $top : voir $W/$top.synth.log"
        fi
    done
fi
