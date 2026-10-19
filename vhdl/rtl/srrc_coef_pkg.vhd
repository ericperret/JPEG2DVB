--==============================================================================
--  Nom        : srrc_coef_pkg.vhd
--  Projet     : JPEG2DVB, portage FPGA (émetteur DVB-S 23 cm)
--  Objet      : coefficients du filtre SRRC en forme polyphase, entiers 16 bits
--               (fichier généré par scripts/refs.js depuis l'étape 14 de JPEG2DVB)
--  Auteur     : Eric PERRET
--  Date       : 2026-10-19
--  Version    : 1.0
--  Paramètres : α = 0.35, 12 symboles, 8 échantillons par symbole,
--               fenêtre kaiser, 97 coefficients, échelle E = 169630.0752
--  Principe   : échantillon n·8 + r = somme sur d de C(r)(d) · s(n − 6 + d),
--               symboles s = ±1 ; la somme des |C(r)(d)| ne dépasse pas 0,95 × 32 767
--  Licence    : CC BY-NC 4.0
--  Historique : 1.0  2026-10-19  création
--==============================================================================
library ieee;
use ieee.std_logic_1164.all;

package srrc_coef_pkg is
    constant SRRC_SPS  : natural := 8;
    constant SRRC_TAPS : natural := 13;
    type srrc_phase_t is array (0 to SRRC_TAPS - 1) of integer range -32768 to 32767;
    type srrc_coef_t  is array (0 to SRRC_SPS - 1) of srrc_phase_t;
    constant SRRC_C : srrc_coef_t := (
        0 => (    -3,     18,     12,   -273,    904,  -1672,  23231,  -1672,    904,   -273,     12,     18,     -3),
        1 => (     0,     19,    -27,   -197,   1063,  -3109,  22448,    802,    422,   -278,     57,      9,     -4),
        2 => (     0,     16,    -50,    -90,    955,  -3575,  20204,   4214,   -375,   -178,     93,     -7,     -3),
        3 => (     0,      9,    -55,     10,    679,  -3261,  16796,   8301,  -1389,     36,    105,    -27,     -1),
        4 => (     0,      3,    -45,     78,    342,  -2436,  12659,  12659,  -2436,    342,     78,    -45,      3),
        5 => (     0,     -1,    -27,    105,     36,  -1389,   8301,  16796,  -3261,    679,     10,    -55,      9),
        6 => (     0,     -3,     -7,     93,   -178,   -375,   4214,  20204,  -3575,    955,    -90,    -50,     16),
        7 => (     0,     -4,      9,     57,   -278,    422,    802,  22448,  -3109,   1063,   -197,    -27,     19)
    );
end package srrc_coef_pkg;
