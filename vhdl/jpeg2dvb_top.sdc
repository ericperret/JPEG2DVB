# ==============================================================================
#  Nom        : jpeg2dvb_top.sdc
#  Projet     : JPEG2DVB, portage FPGA (émetteur DVB-S 23 cm)
#  Objet      : contraintes de timing de jpeg2dvb_top (Libero SoC) ; les
#               horloges des PLL (80 MHz, 320 MHz, 14,318 MHz) sont ajoutées par
#               Constraint Manager ▸ Timing ▸ Derive Constraints
#  Auteur     : Eric PERRET
#  Date       : 2026-11-16
#  Version    : 1.1
#  Licence    : CC BY-NC 4.0
#  Historique : 1.0  2026-11-10  création (chantier 6, entité de tête)
#               1.1  2026-11-16  ports mcu_scl et mcu_sda retirés (bus du
#                                microcontrôleur supprimé en 2.20)
# ==============================================================================

# oscillateur MEMS 50 MHz et horloge pixel du décodeur (27 MHz)
create_clock -name osc_50   -period 20.000 [get_ports osc_50]
create_clock -name tvp_sclk -period 37.037 [get_ports tvp_sclk]

# horloge pixel : sans relation de phase avec les PLL
set_clock_groups -asynchronous -group [get_clocks tvp_sclk]

# bus I²C, LED, commandes du décodeur : signaux lents, synchronisés ou statiques
set_false_path -from [get_ports {tvp_scl tvp_sda}]
set_false_path -to   [get_ports {tvp_scl tvp_sda tvp_resetb tvp_pdn led_pll led_tvp led_video}]
