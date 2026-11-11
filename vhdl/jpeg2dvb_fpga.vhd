--==============================================================================
--  Nom        : jpeg2dvb_fpga.vhd
--  Projet     : JPEG2DVB, portage FPGA (émetteur DVB-S 23 cm)
--  Objet      : modules synthétisables de l'émetteur DVB-S, de l'entrée vidéo PAL
--               (décodeur TVP5150AM1) et de la mire animée aux échantillons I/Q ;
--               chaque module de la chaîne reproduit au bit près une étape de
--               JPEG2DVB
--  Auteur     : Eric PERRET
--  Date       : 2026-11-11
--  Version    : 2.13
--  Plateforme : VHDL-2008, synthétisable (Libero SoC)
--  Licence    : CC BY-NC 4.0
--  Contenu    : 34 unités, dans l'ordre d'analyse :
--               dvbs_pkg      types et fonctions communs (PRBS, GF(2⁸), RS, convolutif)
--               srrc_coef_pkg coefficients SRRC (généré par refs.js)
--               sdm_coef_pkg  SRRC à 640 MS/s du sigma-delta (généré par sdm.js)
--               mire_pkg      géométrie et palette de la mire (généré par mire.js)
--               vlc_tab_pkg   tables VLC B.12 à B.14 (généré par gen_vlc.js)
--               csa_tab_pkg   tables de l'embrouillage DVB-CSA (généré par csa.js)
--               prbs_disp     dispersion d'énergie (étape 09)
--               rs_enc        Reed-Solomon (204,188) (étape 10)
--               interleaver   entrelaceur de Forney I = 12 (étape 11)
--               conv_enc      codeur convolutif, 1/2 à 7/8 (étape 12)
--               qpsk_map      QPSK (étape 13)
--               srrc_poly     filtre SRRC polyphase × 8 (étape 14)
--               tx_backend    chaîne arrière, TS → I/Q (09 à 14)
--               dct8x8_int    DCT 8 × 8 entière (étape 02)
--               quant_intra   quantification intra (étape 03)
--               zigzag        balayage zigzag (étape 04)
--               vlc_enc       codage VLC (étape 05)
--               bit_packer    mots de longueur variable → octets
--               es_mux        flux élémentaire (étape 06)
--               ts_mux        PES et Transport Stream (étapes 07, 08)
--               csa_enc       embrouillage DVB-CSA d'un PID, clé fixe (BISS-1)
--               rate_ctrl     régulation de débit TM5 (étape 03)
--               mire_gen      mire animée (étape 01)
--               video_enc     tête de chaîne, mire → TS (01 à 08)
--               dvbs_tx       émetteur complet, mire → I/Q
--               sd_entree     apport des symboles à la boucle (SRRC par tables)
--               sdm3          sigma-delta 1 bit d'ordre 3, 8 bits par cycle, anticipation
--               sigma_delta   sortie sigma-delta I/Q depuis les symboles QPSK
--               bt656_rx      récepteur BT.656 du décodeur TVP5150AM1 (SCLK 27 MHz)
--               i2c_maitre    maître I²C minimal (étirement, libération du bus)
--               tvp_ctrl      pilotage du TVP5150AM1 : démarrage, PAL forcé, choix
--                             automatique ou imposée de l'entrée AIP1A / AIP1B
--               dvbs_sd       émetteur de la mire aux bits sigma-delta (80 MHz)
--               regs_i2c      esclave I²C 2Ah du microcontrôleur et registres
--               jpeg2dvb_top  entité de tête de la carte (PLL, LVDS, décodeur,
--                             microcontrôleur, LED) ; blocs Libero dans
--                             jpeg2dvb_ip_libero.vhd (jpeg2dvb_ip_sim.vhd en simulation)
--  Conventions: flux valid / ready ; bibliothèque ieee seule (clauses
--               library / use par unité) ; fonctions et process commentés
--               « E : entrées → T : traitement → S : sorties » ; les paquetages
--               générés par fpga_test/ restent entre « -- >>> » et « -- <<< »
--  Historique : 1.0  2026-10-19  modules créés (étapes 01 à 14 de JPEG2DVB)
--                    rate_ctrl 1.0 : régulation de débit TM5
--                    dvbs_pkg 1.1 : budget_image (régulation TM5)
--                    es_mux 1.1 : slice_ok : attente du code de la
--                      régulation TM5
--                    video_enc 1.1 : régulation TM5 (rate_ctrl) :
--                      un code par rangée
--                    dvbs_tx 1.1 : régulation TM5 : budget tiré du
--                      canal (10 MS/s, FEC, 95 % de vidéo), plus
--                      d'entrée code
--               2.0  2026-10-19  fusion propre : cartouche unique, context
--                                commun, commentaires de fonction
--               2.1  2026-10-19  sortie sigma-delta (point P3) : cic8, sdm3,
--                                sigma_delta ; dvbs_pkg 1.2 : type ech8_t
--               2.2  2026-10-19  sortie sigma-delta refaite pour le timing (P3) :
--                                SRRC à 640 MS/s par tables depuis les symboles
--                                (sd_entree, sdm_coef_pkg), états sur 16 bits,
--                                8 décisions par anticipation (sdm3) ; cic8 retiré ;
--                                dvbs_pkg 1.3 : SD_W, sd_grp_t
--               2.3  2026-11-04  entrée vidéo PAL (chantier 3a) : décodeur
--                                TVP5150AM1 piloté par I²C (i2c_maitre,
--                                tvp_ctrl), récepteur BT.656 (bt656_rx)
--               2.4  2026-11-10  clauses library / use explicites à la place
--                                du « context » VHDL-2008 (lecture par Libero) ;
--                                interleaver : pointeurs de branche sans valeur
--                                initiale, en registres (Synplify MF682)
--               2.5  2026-11-10  entité de tête (chantier 6) : dvbs_sd, regs_i2c,
--                                jpeg2dvb_top ; tvp_ctrl : entrée imposée (choix)
--               2.6  2026-11-11  réduction de surface, sortie inchangée au bit près :
--                                sdm3 : seuils et corrections multiples de FS, donc
--                                comparaisons, Pk et candidats sur les seuls bits de
--                                poids fort (14 bits au lieu de 24), états x1, x2, x3
--                                sur 17, 20, 22 bits ; dvbs_pkg 1.4 : SD_G, apports
--                                du groupe sur 16 bits (sd_entree)
--               2.7  2026-11-11  quant_intra : inverses en mémoire morte synchrone
--                                (2 048 mots de 26 bits, LSRAM) au lieu d'une table
--                                combinatoire, division sur 17 × 14 bits, trois
--                                étages ; sortie inchangée au bit près
--               2.8  2026-11-11  dct8x8_int : symétrie des coefficients (4 multiplieurs
--                                par passe), passe lignes pendant le chargement,
--                                R' et F en mémoire (64 × 18, 64 × 12) au lieu de
--                                1 664 bascules ; sortie inchangée au bit près
--               2.9  2026-11-11  ts_mux : écarts d'ordonnancement et PTS tenus en
--                                cumul (additions) au lieu de quatre produits ;
--                                plus de rebouclage du compteur de créneaux (8 jours)
--                                ni du PTS à 2²¹ images ; sortie inchangée au bit près
--               2.10 2026-11-11  interleaver : lecture synchrone de la mémoire
--                                (adresse de la branche suivante présentée un cycle
--                                avant), pour une LSRAM ; sortie et cadence inchangées
--               2.11 2026-11-11  mire : image de 101 376 mots retirée ; mire_pkg 1.2
--                                décrit la mire par sa géométrie (mire_idx), mire_gen
--                                calcule la couleur par comparaisons ; sortie inchangée
--               2.12 2026-11-11  embrouillage DVB-CSA (BISS-1) : csa_tab_pkg, csa_enc
--                                (module seul, pas encore dans la chaîne)
--               2.13 2026-11-11  ts_mux à deux programmes (MCPC, G_MCPC) : canal 2 sur
--                                s2_*, PAT à 2 programmes, PMT 2 (0x0200), vidéo 0x0201 ;
--                                à un programme (défaut), sortie inchangée
--==============================================================================

--------------------------------------------------------------------------------
-- dvbs_pkg : types et fonctions communs de la chaîne DVB-S (EN 300 421) :
--   dispersion d'énergie, corps de Galois GF(2⁸), Reed-Solomon,
--   codeur convolutif, budget de la régulation de débit
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package dvbs_pkg is

    subtype octet_t is std_logic_vector(7 downto 0);
    type octet_tab_t is array (natural range <>) of octet_t;

    ----------------------------------------------------------------------------
    -- Dispersion d'énergie (§ 4.4.1) : générateur 1 + X¹⁴ + X¹⁵
    -- Registre : bit k-1 = étage k ; initialisation étages 1 à 15 = 100101010000000
    -- Sortie = étage 14 ⊕ étage 15, réinjectée dans l'étage 1
    ----------------------------------------------------------------------------
    subtype prbs_reg_t is std_logic_vector(14 downto 0);
    constant PRBS_INIT : prbs_reg_t := "000000010101001";      -- 0x00A9
    function prbs_pas(r : prbs_reg_t) return prbs_reg_t;        -- un pas
    function prbs_pas8(r : prbs_reg_t) return prbs_reg_t;       -- huit pas
    function prbs_octet(r : prbs_reg_t) return octet_t;         -- 8 bits de sortie, premier bit en poids fort

    ----------------------------------------------------------------------------
    -- GF(2⁸), polynôme primitif x⁸ + x⁴ + x³ + x² + 1 (0x11D)
    ----------------------------------------------------------------------------
    function gf_mul(a, b : octet_t) return octet_t;

    ----------------------------------------------------------------------------
    -- RS(204,188) : g(x) = (x + λ⁰)(x + λ¹)…(x + λ¹⁵), coefficients du plus haut
    -- degré au plus bas (RS_GEN(0) = 1)
    ----------------------------------------------------------------------------
    constant RS_GEN : octet_tab_t(0 to 16) := (
        x"01", x"3B", x"0D", x"68", x"BD", x"44", x"D1", x"1E", x"08",
        x"A3", x"41", x"29", x"E5", x"62", x"32", x"24", x"3B");

    ----------------------------------------------------------------------------
    -- Codeur convolutif K = 7 (§ 4.4.3) : masques sur (entrée & registre),
    -- registre de 6 bits, D0 (bit précédent) en poids fort
    ----------------------------------------------------------------------------
    constant CONV_G1 : std_logic_vector(6 downto 0) := "1111001";   -- 171 octal, sortie X
    constant CONV_G2 : std_logic_vector(6 downto 0) := "1011011";   -- 133 octal, sortie Y
    function parite(v : std_logic_vector) return std_logic;

    ----------------------------------------------------------------------------
    -- Sortie sigma-delta : apport des entrées d'un groupe de 8 instants (sdm3)
    ----------------------------------------------------------------------------
    constant SD_W : natural := 24;                                 -- largeur des mots de la boucle (|Pk| < 2²³)
    constant SD_G : natural := 16;                                 -- largeur des apports (|In|, |U| ≤ 26 966)
    type sd_grp_t is array (0 to 7) of signed(SD_G - 1 downto 0);  -- In3 … In7, U1, U2, U3 d'un groupe

    ----------------------------------------------------------------------------
    -- Budget de la régulation TM5 (étape 03) en bits par image :
    -- T = ⌊Rs·2·fn·188·part / (fd·204·100·fps)⌋, Rs multiple de 100·fps
    -- fec : 0 = 1/2, 1 = 2/3, 2 = 3/4, 3 = 5/6, 4 = 7/8 ; part en %
    ----------------------------------------------------------------------------
    function budget_image(rs, fec, part, fps : natural) return natural;

end package dvbs_pkg;

package body dvbs_pkg is
    -- budget_image : E : Rs, FEC, part vidéo, images/s → T : formule entière de
    --   l'étape 03 → S : T en bits par image
    function budget_image(rs, fec, part, fps : natural) return natural is
        type n_t is array (0 to 4) of natural;
        constant FN : n_t := (1, 2, 3, 5, 7);
        constant FD : n_t := (2, 3, 4, 6, 8);
        constant A  : natural := rs / (100 * fps);
    begin
        assert rs mod (100 * fps) = 0 report "budget_image : Rs doit etre multiple de 100 x fps" severity failure;
        return (A * 376 * FN(fec) * part) / (FD(fec) * 204);
    end function;


    -- prbs_pas : E : registre → T : décalage, étage 14 ⊕ étage 15 réinjecté
    --   dans l'étage 1 → S : registre suivant
    function prbs_pas(r : prbs_reg_t) return prbs_reg_t is
        variable f : std_logic;
    begin
        f := r(13) xor r(14);
        return r(13 downto 0) & f;
    end function;

    -- prbs_pas8 : E : registre → T : huit pas → S : registre après un octet
    function prbs_pas8(r : prbs_reg_t) return prbs_reg_t is
        variable v : prbs_reg_t := r;
    begin
        for k in 0 to 7 loop
            v := prbs_pas(v);
        end loop;
        return v;
    end function;

    -- prbs_octet : E : registre → T : huit bits de sortie (étage 14 ⊕ 15) → S :
    --   octet de brouillage, premier bit en poids fort
    function prbs_octet(r : prbs_reg_t) return octet_t is
        variable v : prbs_reg_t := r;
        variable o : octet_t;
    begin
        for k in 7 downto 0 loop
            o(k) := v(13) xor v(14);
            v := prbs_pas(v);
        end loop;
        return o;
    end function;

    -- gf_mul : E : a, b de GF(2⁸) → T : produit polynomial réduit par 0x11D → S
    --   : a·b
    function gf_mul(a, b : octet_t) return octet_t is
        variable p  : octet_t := (others => '0');
        variable aa : octet_t := a;
    begin
        for k in 0 to 7 loop
            if b(k) = '1' then
                p := p xor aa;
            end if;
            if aa(7) = '1' then
                aa := (aa(6 downto 0) & '0') xor x"1D";
            else
                aa := aa(6 downto 0) & '0';
            end if;
        end loop;
        return p;
    end function;

    -- parite : E : vecteur → T : ou exclusif de tous ses bits → S : parité
    function parite(v : std_logic_vector) return std_logic is
        variable p : std_logic := '0';
    begin
        for k in v'range loop
            p := p xor v(k);
        end loop;
        return p;
    end function;

end package body dvbs_pkg;

-- >>> srrc_coef_pkg.vhd
--------------------------------------------------------------------------------
-- srrc_coef_pkg : coefficients du filtre SRRC en forme polyphase, entiers 16 bits
--   (fichier généré par fpga_test/refs.js depuis l'étape 14 de JPEG2DVB)
--   Paramètres : α = 0.35, 12 symboles, 8 échantillons par symbole,
--                fenêtre kaiser, 97 coefficients, échelle E = 169630.0752
--   Principe : échantillon n·8 + r = somme sur d de C(r)(d) · s(n − 6 + d),
--              symboles s = ±1 ; la somme des |C(r)(d)| ne dépasse pas 0,95 × 32 767
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

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
-- <<< srrc_coef_pkg.vhd

-- >>> sdm_coef_pkg.vhd
--------------------------------------------------------------------------------
-- sdm_coef_pkg : coefficients du filtre SRRC à 640 MS/s pour la sortie
--   sigma-delta (fichier généré par fpga_test/sdm.js)
--   Paramètres : α = 0,35, 12 symboles, 64 phases × 13 symboles, fenêtre de
--                Kaiser β = 5,65, crête 0,47 FS, FS = 2^10
--   Principe : u(8q + r) = somme sur d de SDM_H(8q + r)(d) · sym(d), d = 12
--              le symbole le plus récent, sym = ±1
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package sdm_coef_pkg is
    constant SDM_F   : natural := 10;
    type sdm_phase_t is array (0 to 12) of integer range -32768 to 32767;
    type sdm_coef_t  is array (0 to 63) of sdm_phase_t;
    constant SDM_H : sdm_coef_t := (
         0 => (    0,     0,     0,    -4,    14,   -26,   359,   -26,    14,    -4,     0,     0,     0),
         1 => (    0,     0,     0,    -4,    15,   -30,   359,   -22,    13,    -4,     0,     0,     0),
         2 => (    0,     0,     0,    -4,    15,   -33,   358,   -18,    13,    -4,     0,     0,     0),
         3 => (    0,     0,     0,    -4,    15,   -36,   357,   -13,    12,    -4,     0,     0,     0),
         4 => (    0,     0,     0,    -4,    16,   -39,   356,    -9,    11,    -4,     1,     0,     0),
         5 => (    0,     0,     0,    -4,    16,   -42,   354,    -4,    10,    -4,     1,     0,     0),
         6 => (    0,     0,     0,    -3,    16,   -44,   352,     1,     9,    -4,     1,     0,     0),
         7 => (    0,     0,     0,    -3,    16,   -46,   350,     7,     8,    -4,     1,     0,     0),
         8 => (    0,     0,     0,    -3,    16,   -48,   347,    12,     7,    -4,     1,     0,     0),
         9 => (    0,     0,     0,    -3,    16,   -50,   344,    18,     5,    -4,     1,     0,     0),
        10 => (    0,     0,    -1,    -3,    16,   -51,   340,    24,     4,    -4,     1,     0,     0),
        11 => (    0,     0,    -1,    -2,    16,   -52,   337,    31,     2,    -4,     1,     0,     0),
        12 => (    0,     0,    -1,    -2,    16,   -53,   332,    37,     1,    -4,     1,     0,     0),
        13 => (    0,     0,    -1,    -2,    16,   -54,   328,    44,    -1,    -4,     1,     0,     0),
        14 => (    0,     0,    -1,    -2,    15,   -55,   323,    51,    -2,    -3,     1,     0,     0),
        15 => (    0,     0,    -1,    -2,    15,   -55,   318,    58,    -4,    -3,     1,     0,     0),
        16 => (    0,     0,    -1,    -1,    15,   -55,   312,    65,    -6,    -3,     1,     0,     0),
        17 => (    0,     0,    -1,    -1,    14,   -55,   307,    73,    -8,    -2,     1,     0,     0),
        18 => (    0,     0,    -1,    -1,    14,   -55,   301,    80,    -9,    -2,     2,     0,     0),
        19 => (    0,     0,    -1,    -1,    13,   -55,   294,    88,   -11,    -2,     2,     0,     0),
        20 => (    0,     0,    -1,    -1,    13,   -54,   288,    96,   -13,    -1,     2,     0,     0),
        21 => (    0,     0,    -1,     0,    12,   -53,   281,   104,   -15,    -1,     2,     0,     0),
        22 => (    0,     0,    -1,     0,    12,   -53,   274,   112,   -17,     0,     2,     0,     0),
        23 => (    0,     0,    -1,     0,    11,   -52,   267,   120,   -19,     0,     2,     0,     0),
        24 => (    0,     0,    -1,     0,    10,   -50,   260,   128,   -21,     1,     2,     0,     0),
        25 => (    0,     0,    -1,     0,    10,   -49,   252,   137,   -24,     1,     2,     0,     0),
        26 => (    0,     0,    -1,     0,     9,   -48,   244,   145,   -26,     2,     2,     0,     0),
        27 => (    0,     0,    -1,     1,     9,   -46,   237,   154,   -28,     2,     2,    -1,     0),
        28 => (    0,     0,    -1,     1,     8,   -45,   229,   162,   -30,     3,     1,    -1,     0),
        29 => (    0,     0,    -1,     1,     7,   -43,   221,   170,   -32,     3,     1,    -1,     0),
        30 => (    0,     0,    -1,     1,     7,   -41,   212,   179,   -34,     4,     1,    -1,     0),
        31 => (    0,     0,    -1,     1,     6,   -40,   204,   187,   -36,     5,     1,    -1,     0),
        32 => (    0,     0,    -1,     1,     5,   -38,   196,   196,   -38,     5,     1,    -1,     0),
        33 => (    0,     0,    -1,     1,     5,   -36,   187,   204,   -40,     6,     1,    -1,     0),
        34 => (    0,     0,    -1,     1,     4,   -34,   179,   212,   -41,     7,     1,    -1,     0),
        35 => (    0,     0,    -1,     1,     3,   -32,   170,   221,   -43,     7,     1,    -1,     0),
        36 => (    0,     0,    -1,     1,     3,   -30,   162,   229,   -45,     8,     1,    -1,     0),
        37 => (    0,     0,    -1,     2,     2,   -28,   154,   237,   -46,     9,     1,    -1,     0),
        38 => (    0,     0,     0,     2,     2,   -26,   145,   244,   -48,     9,     0,    -1,     0),
        39 => (    0,     0,     0,     2,     1,   -24,   137,   252,   -49,    10,     0,    -1,     0),
        40 => (    0,     0,     0,     2,     1,   -21,   128,   260,   -50,    10,     0,    -1,     0),
        41 => (    0,     0,     0,     2,     0,   -19,   120,   267,   -52,    11,     0,    -1,     0),
        42 => (    0,     0,     0,     2,     0,   -17,   112,   274,   -53,    12,     0,    -1,     0),
        43 => (    0,     0,     0,     2,    -1,   -15,   104,   281,   -53,    12,     0,    -1,     0),
        44 => (    0,     0,     0,     2,    -1,   -13,    96,   288,   -54,    13,    -1,    -1,     0),
        45 => (    0,     0,     0,     2,    -2,   -11,    88,   294,   -55,    13,    -1,    -1,     0),
        46 => (    0,     0,     0,     2,    -2,    -9,    80,   301,   -55,    14,    -1,    -1,     0),
        47 => (    0,     0,     0,     1,    -2,    -8,    73,   307,   -55,    14,    -1,    -1,     0),
        48 => (    0,     0,     0,     1,    -3,    -6,    65,   312,   -55,    15,    -1,    -1,     0),
        49 => (    0,     0,     0,     1,    -3,    -4,    58,   318,   -55,    15,    -2,    -1,     0),
        50 => (    0,     0,     0,     1,    -3,    -2,    51,   323,   -55,    15,    -2,    -1,     0),
        51 => (    0,     0,     0,     1,    -4,    -1,    44,   328,   -54,    16,    -2,    -1,     0),
        52 => (    0,     0,     0,     1,    -4,     1,    37,   332,   -53,    16,    -2,    -1,     0),
        53 => (    0,     0,     0,     1,    -4,     2,    31,   337,   -52,    16,    -2,    -1,     0),
        54 => (    0,     0,     0,     1,    -4,     4,    24,   340,   -51,    16,    -3,    -1,     0),
        55 => (    0,     0,     0,     1,    -4,     5,    18,   344,   -50,    16,    -3,     0,     0),
        56 => (    0,     0,     0,     1,    -4,     7,    12,   347,   -48,    16,    -3,     0,     0),
        57 => (    0,     0,     0,     1,    -4,     8,     7,   350,   -46,    16,    -3,     0,     0),
        58 => (    0,     0,     0,     1,    -4,     9,     1,   352,   -44,    16,    -3,     0,     0),
        59 => (    0,     0,     0,     1,    -4,    10,    -4,   354,   -42,    16,    -4,     0,     0),
        60 => (    0,     0,     0,     1,    -4,    11,    -9,   356,   -39,    16,    -4,     0,     0),
        61 => (    0,     0,     0,     0,    -4,    12,   -13,   357,   -36,    15,    -4,     0,     0),
        62 => (    0,     0,     0,     0,    -4,    13,   -18,   358,   -33,    15,    -4,     0,     0),
        63 => (    0,     0,     0,     0,    -4,    13,   -22,   359,   -30,    15,    -4,     0,     0)
    );
end package sdm_coef_pkg;
-- <<< sdm_coef_pkg.vhd

-- >>> mire_pkg.vhd
--------------------------------------------------------------------------------
-- mire_pkg : mire 16 couleurs 352 × 288 décrite par sa géométrie (barres,
--   gamme de gris, bandeau, lettres, fond du compteur) : mire_idx
--   donne l'indice de couleur d'un pixel par comparaisons, sans
--   mémoire d'image ; palette Y, Cb, Cr ; frontières de couleur
--   sur coordonnées paires, la chrominance 4:2:0 d'un bloc 2 × 2
--   est donc celle de la palette
--   (fichier généré par fpga_test/mire.js ; même image : fpga_test/mire.png)
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package mire_pkg is
    constant MIRE_L : natural := 352;
    constant MIRE_H : natural := 288;
    type ycc_t is array (0 to 2) of natural range 0 to 255;
    type palette_t is array (0 to 15) of ycc_t;
    constant PALETTE : palette_t := (
         0 => (255, 128, 128),
         1 => (226, 1, 149),
         2 => (179, 171, 1),
         3 => (150, 44, 21),
         4 => (105, 212, 235),
         5 => (76, 85, 255),
         6 => (29, 255, 107),
         7 => (0, 128, 128),
         8 => (36, 128, 128),
         9 => (73, 128, 128),
        10 => (109, 128, 128),
        11 => (146, 128, 128),
        12 => (182, 128, 128),
        13 => (219, 128, 128),
        14 => (176, 62, 174),
        15 => (32, 134, 122));
    constant IDX_BLANC   : natural := 0;
    constant IDX_NOIR    : natural := 7;
    constant IDX_AMBRE   : natural := 14;
    constant IDX_ARDOISE : natural := 15;
    -- géométrie : 8 barres de couleur, 8 gris, bandeau, fond du compteur
    constant MIRE_BARRE     : natural := 44;      -- largeur d'une barre
    constant MIRE_Y_GRIS    : natural := 168;     -- première ligne de la gamme de gris
    constant MIRE_Y_BANDEAU : natural := 224;     -- première ligne du bandeau
    constant MIRE_Y_CPT     : natural := 276;     -- première ligne du fond du compteur
    type gris_t is array (0 to 7) of natural range 0 to 15;
    constant MIRE_GRIS : gris_t := (7, 8, 9, 10, 11, 12, 13, 0);
    -- lettres « AZS » : 7 lignes de 5 pavés par lettre, ligne du haut et pavé de
    --   gauche en premier ; pavé (lettre l, ligne j, colonne i) : bit 35·l + 5·j + i
    constant MIRE_X_TXT : natural := 120;
    constant MIRE_Y_TXT : natural := 236;
    constant MIRE_PAVE  : natural := 4;            -- côté d'un pavé
    constant MIRE_PAS   : natural := 28;           -- pas des lettres
    constant MIRE_NL    : natural := 3;            -- nombre de lettres
    constant MIRE_TXT : std_logic_vector(0 to 35 * MIRE_NL - 1) :=
        "01110100011000111111100011000110001" &    -- A
        "11111000010001000100010001000011111" &    -- Z
        "01111100001000001110000010000111110";    -- S
    function mire_idx(x, y : natural) return natural;
end package mire_pkg;

package body mire_pkg is
    -- mire_idx : E : x (0 à MIRE_L − 1), y (0 à MIRE_H − 1) → T : barre x / 44
    --   par comparaisons ; zone selon y ; pavé de lettre dans le bandeau → S :
    --   indice de couleur du pixel
    function mire_idx(x, y : natural) return natural is
        variable b : natural range 0 to 7 := 0;
        variable l : natural range 0 to MIRE_NL - 1 := 0;
        variable i : natural range 0 to 7;
        variable j : natural range 0 to 6;
    begin
        for k in 1 to 7 loop
            if x >= MIRE_BARRE * k then b := k; end if;
        end loop;
        if y < MIRE_Y_GRIS then
            return b;
        elsif y < MIRE_Y_BANDEAU then
            return MIRE_GRIS(b);
        elsif y >= MIRE_Y_CPT then
            return IDX_NOIR;
        elsif y >= MIRE_Y_TXT and y < MIRE_Y_TXT + 7 * MIRE_PAVE and x >= MIRE_X_TXT and x < MIRE_X_TXT + MIRE_NL * MIRE_PAS then
            for k in 1 to MIRE_NL - 1 loop
                if x >= MIRE_X_TXT + MIRE_PAS * k then l := k; end if;
            end loop;
            i := (x - MIRE_X_TXT - MIRE_PAS * l) / MIRE_PAVE;
            j := (y - MIRE_Y_TXT) / MIRE_PAVE;
            if i < 5 and MIRE_TXT(35 * l + 5 * j + i) = '1' then
                return IDX_AMBRE;
            end if;
        end if;
        return IDX_ARDOISE;
    end function;
end package body mire_pkg;
-- <<< mire_pkg.vhd

-- >>> vlc_tab_pkg.vhd
--------------------------------------------------------------------------------
-- vlc_tab_pkg : tables VLC MPEG-2 intra : B.12 (taille DC luminance), B.13
--   (taille DC chrominance), B.14 (coefficients AC, intra_vlc_format
--   = 0, 111 paires run / niveau, sans le bit de signe)
--   (fichier généré par fpga_test/gen_vlc.js depuis la page 05)
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package vlc_tab_pkg is
    type dc_vlc_t is record
        code : std_logic_vector(9 downto 0);       -- cadré à droite
        lg   : natural range 0 to 10;
    end record;
    type dc_tab_t is array (0 to 11) of dc_vlc_t;
    constant DC_LUMA : dc_tab_t := (
        0 => ("0000000100", 3),
        1 => ("0000000000", 2),
        2 => ("0000000001", 2),
        3 => ("0000000101", 3),
        4 => ("0000000110", 3),
        5 => ("0000001110", 4),
        6 => ("0000011110", 5),
        7 => ("0000111110", 6),
        8 => ("0001111110", 7),
        9 => ("0011111110", 8),
        10 => ("0111111110", 9),
        11 => ("0111111111", 9));
    constant DC_CHROMA : dc_tab_t := (
        0 => ("0000000000", 2),
        1 => ("0000000001", 2),
        2 => ("0000000010", 2),
        3 => ("0000000110", 3),
        4 => ("0000001110", 4),
        5 => ("0000011110", 5),
        6 => ("0000111110", 6),
        7 => ("0001111110", 7),
        8 => ("0011111110", 8),
        9 => ("0111111110", 9),
        10 => ("1111111110", 10),
        11 => ("1111111111", 10));
    constant AC_EOB    : std_logic_vector(1 downto 0) := "10";
    constant AC_ESCAPE : std_logic_vector(5 downto 0) := "000001";

    type ac_vlc_t is record
        trouve : boolean;
        code   : std_logic_vector(15 downto 0);    -- cadré à droite, sans le signe
        lg     : natural range 0 to 16;
    end record;
    function ac_code(run : natural range 0 to 63; niveau : natural range 0 to 2047) return ac_vlc_t;
end package vlc_tab_pkg;

package body vlc_tab_pkg is
    function ac_code(run : natural range 0 to 63; niveau : natural range 0 to 2047) return ac_vlc_t is
        variable v : ac_vlc_t := (false, (others => '0'), 0);
    begin
        case run is
            when 0 =>
                case niveau is
                    when  1 => v := (true, "0000000000000011", 2);
                    when  2 => v := (true, "0000000000000100", 4);
                    when  3 => v := (true, "0000000000000101", 5);
                    when  4 => v := (true, "0000000000000110", 7);
                    when  5 => v := (true, "0000000000100110", 8);
                    when  6 => v := (true, "0000000000100001", 8);
                    when  7 => v := (true, "0000000000001010", 10);
                    when  8 => v := (true, "0000000000011101", 12);
                    when  9 => v := (true, "0000000000011000", 12);
                    when 10 => v := (true, "0000000000010011", 12);
                    when 11 => v := (true, "0000000000010000", 12);
                    when 12 => v := (true, "0000000000011010", 13);
                    when 13 => v := (true, "0000000000011001", 13);
                    when 14 => v := (true, "0000000000011000", 13);
                    when 15 => v := (true, "0000000000010111", 13);
                    when 16 => v := (true, "0000000000011111", 14);
                    when 17 => v := (true, "0000000000011110", 14);
                    when 18 => v := (true, "0000000000011101", 14);
                    when 19 => v := (true, "0000000000011100", 14);
                    when 20 => v := (true, "0000000000011011", 14);
                    when 21 => v := (true, "0000000000011010", 14);
                    when 22 => v := (true, "0000000000011001", 14);
                    when 23 => v := (true, "0000000000011000", 14);
                    when 24 => v := (true, "0000000000010111", 14);
                    when 25 => v := (true, "0000000000010110", 14);
                    when 26 => v := (true, "0000000000010101", 14);
                    when 27 => v := (true, "0000000000010100", 14);
                    when 28 => v := (true, "0000000000010011", 14);
                    when 29 => v := (true, "0000000000010010", 14);
                    when 30 => v := (true, "0000000000010001", 14);
                    when 31 => v := (true, "0000000000010000", 14);
                    when 32 => v := (true, "0000000000011000", 15);
                    when 33 => v := (true, "0000000000010111", 15);
                    when 34 => v := (true, "0000000000010110", 15);
                    when 35 => v := (true, "0000000000010101", 15);
                    when 36 => v := (true, "0000000000010100", 15);
                    when 37 => v := (true, "0000000000010011", 15);
                    when 38 => v := (true, "0000000000010010", 15);
                    when 39 => v := (true, "0000000000010001", 15);
                    when 40 => v := (true, "0000000000010000", 15);
                    when others => null;
                end case;
            when 1 =>
                case niveau is
                    when  1 => v := (true, "0000000000000011", 3);
                    when  2 => v := (true, "0000000000000110", 6);
                    when  3 => v := (true, "0000000000100101", 8);
                    when  4 => v := (true, "0000000000001100", 10);
                    when  5 => v := (true, "0000000000011011", 12);
                    when  6 => v := (true, "0000000000010110", 13);
                    when  7 => v := (true, "0000000000010101", 13);
                    when  8 => v := (true, "0000000000011111", 15);
                    when  9 => v := (true, "0000000000011110", 15);
                    when 10 => v := (true, "0000000000011101", 15);
                    when 11 => v := (true, "0000000000011100", 15);
                    when 12 => v := (true, "0000000000011011", 15);
                    when 13 => v := (true, "0000000000011010", 15);
                    when 14 => v := (true, "0000000000011001", 15);
                    when 15 => v := (true, "0000000000010011", 16);
                    when 16 => v := (true, "0000000000010010", 16);
                    when 17 => v := (true, "0000000000010001", 16);
                    when 18 => v := (true, "0000000000010000", 16);
                    when others => null;
                end case;
            when 2 =>
                case niveau is
                    when  1 => v := (true, "0000000000000101", 4);
                    when  2 => v := (true, "0000000000000100", 7);
                    when  3 => v := (true, "0000000000001011", 10);
                    when  4 => v := (true, "0000000000010100", 12);
                    when  5 => v := (true, "0000000000010100", 13);
                    when others => null;
                end case;
            when 3 =>
                case niveau is
                    when  1 => v := (true, "0000000000000111", 5);
                    when  2 => v := (true, "0000000000100100", 8);
                    when  3 => v := (true, "0000000000011100", 12);
                    when  4 => v := (true, "0000000000010011", 13);
                    when others => null;
                end case;
            when 4 =>
                case niveau is
                    when  1 => v := (true, "0000000000000110", 5);
                    when  2 => v := (true, "0000000000001111", 10);
                    when  3 => v := (true, "0000000000010010", 12);
                    when others => null;
                end case;
            when 5 =>
                case niveau is
                    when  1 => v := (true, "0000000000000111", 6);
                    when  2 => v := (true, "0000000000001001", 10);
                    when  3 => v := (true, "0000000000010010", 13);
                    when others => null;
                end case;
            when 6 =>
                case niveau is
                    when  1 => v := (true, "0000000000000101", 6);
                    when  2 => v := (true, "0000000000011110", 12);
                    when  3 => v := (true, "0000000000010100", 16);
                    when others => null;
                end case;
            when 7 =>
                case niveau is
                    when  1 => v := (true, "0000000000000100", 6);
                    when  2 => v := (true, "0000000000010101", 12);
                    when others => null;
                end case;
            when 8 =>
                case niveau is
                    when  1 => v := (true, "0000000000000111", 7);
                    when  2 => v := (true, "0000000000010001", 12);
                    when others => null;
                end case;
            when 9 =>
                case niveau is
                    when  1 => v := (true, "0000000000000101", 7);
                    when  2 => v := (true, "0000000000010001", 13);
                    when others => null;
                end case;
            when 10 =>
                case niveau is
                    when  1 => v := (true, "0000000000100111", 8);
                    when  2 => v := (true, "0000000000010000", 13);
                    when others => null;
                end case;
            when 11 =>
                case niveau is
                    when  1 => v := (true, "0000000000100011", 8);
                    when  2 => v := (true, "0000000000011010", 16);
                    when others => null;
                end case;
            when 12 =>
                case niveau is
                    when  1 => v := (true, "0000000000100010", 8);
                    when  2 => v := (true, "0000000000011001", 16);
                    when others => null;
                end case;
            when 13 =>
                case niveau is
                    when  1 => v := (true, "0000000000100000", 8);
                    when  2 => v := (true, "0000000000011000", 16);
                    when others => null;
                end case;
            when 14 =>
                case niveau is
                    when  1 => v := (true, "0000000000001110", 10);
                    when  2 => v := (true, "0000000000010111", 16);
                    when others => null;
                end case;
            when 15 =>
                case niveau is
                    when  1 => v := (true, "0000000000001101", 10);
                    when  2 => v := (true, "0000000000010110", 16);
                    when others => null;
                end case;
            when 16 =>
                case niveau is
                    when  1 => v := (true, "0000000000001000", 10);
                    when  2 => v := (true, "0000000000010101", 16);
                    when others => null;
                end case;
            when 17 =>
                case niveau is
                    when  1 => v := (true, "0000000000011111", 12);
                    when others => null;
                end case;
            when 18 =>
                case niveau is
                    when  1 => v := (true, "0000000000011010", 12);
                    when others => null;
                end case;
            when 19 =>
                case niveau is
                    when  1 => v := (true, "0000000000011001", 12);
                    when others => null;
                end case;
            when 20 =>
                case niveau is
                    when  1 => v := (true, "0000000000010111", 12);
                    when others => null;
                end case;
            when 21 =>
                case niveau is
                    when  1 => v := (true, "0000000000010110", 12);
                    when others => null;
                end case;
            when 22 =>
                case niveau is
                    when  1 => v := (true, "0000000000011111", 13);
                    when others => null;
                end case;
            when 23 =>
                case niveau is
                    when  1 => v := (true, "0000000000011110", 13);
                    when others => null;
                end case;
            when 24 =>
                case niveau is
                    when  1 => v := (true, "0000000000011101", 13);
                    when others => null;
                end case;
            when 25 =>
                case niveau is
                    when  1 => v := (true, "0000000000011100", 13);
                    when others => null;
                end case;
            when 26 =>
                case niveau is
                    when  1 => v := (true, "0000000000011011", 13);
                    when others => null;
                end case;
            when 27 =>
                case niveau is
                    when  1 => v := (true, "0000000000011111", 16);
                    when others => null;
                end case;
            when 28 =>
                case niveau is
                    when  1 => v := (true, "0000000000011110", 16);
                    when others => null;
                end case;
            when 29 =>
                case niveau is
                    when  1 => v := (true, "0000000000011101", 16);
                    when others => null;
                end case;
            when 30 =>
                case niveau is
                    when  1 => v := (true, "0000000000011100", 16);
                    when others => null;
                end case;
            when 31 =>
                case niveau is
                    when  1 => v := (true, "0000000000011011", 16);
                    when others => null;
                end case;
            when others => null;
        end case;
        return v;
    end function;
end package body vlc_tab_pkg;
-- <<< vlc_tab_pkg.vhd

-- >>> csa_tab_pkg.vhd
--------------------------------------------------------------------------------
-- csa_tab_pkg : tables de l'embrouillage DVB-CSA, en forme directe :
--   boîte S et permutations du chiffrement par blocs, permutation
--   de la clé, sélections de bits et boîtes du chiffrement de flux
--   (fichier généré par fpga_test/csa.js)
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package csa_tab_pkg is
    -- chiffrement par blocs : boîte S ; le bit i de sa sortie va en CSA_BPERM(i)
    type csa_sbox_t is array (0 to 255) of std_logic_vector(7 downto 0);
    constant CSA_SBOX : csa_sbox_t := (
        x"3A", x"EA", x"68", x"FE", x"33", x"E9", x"88", x"1A", x"83", x"CF", x"E1", x"7F", x"BA", x"E2", x"38", x"12",
        x"E8", x"27", x"61", x"95", x"0C", x"36", x"E5", x"70", x"A2", x"06", x"82", x"7C", x"17", x"A3", x"26", x"49",
        x"BE", x"7A", x"6D", x"47", x"C1", x"51", x"8F", x"F3", x"CC", x"5B", x"67", x"BD", x"CD", x"18", x"08", x"C9",
        x"FF", x"69", x"EF", x"03", x"4E", x"48", x"4A", x"84", x"3F", x"B4", x"10", x"04", x"DC", x"F5", x"5C", x"C6",
        x"16", x"AB", x"AC", x"4C", x"F1", x"6A", x"2F", x"3C", x"3B", x"D4", x"D5", x"94", x"D0", x"C4", x"63", x"62",
        x"71", x"A1", x"F9", x"4F", x"2E", x"AA", x"C5", x"56", x"E3", x"39", x"93", x"CE", x"65", x"64", x"E4", x"58",
        x"6C", x"19", x"42", x"79", x"DD", x"EE", x"96", x"F6", x"8A", x"EC", x"1E", x"85", x"53", x"45", x"DE", x"BB",
        x"7E", x"0A", x"9A", x"13", x"2A", x"9D", x"C2", x"5E", x"5A", x"1F", x"32", x"35", x"9C", x"A8", x"73", x"30",
        x"29", x"3D", x"E7", x"92", x"87", x"1B", x"2B", x"4B", x"A5", x"57", x"97", x"40", x"15", x"E6", x"BC", x"0E",
        x"EB", x"C3", x"34", x"2D", x"B8", x"44", x"25", x"A4", x"1C", x"C7", x"23", x"ED", x"90", x"6E", x"50", x"00",
        x"99", x"9E", x"4D", x"D9", x"DA", x"8D", x"6F", x"5F", x"3E", x"D7", x"21", x"74", x"86", x"DF", x"6B", x"05",
        x"8E", x"5D", x"37", x"11", x"D2", x"28", x"75", x"D6", x"A7", x"77", x"24", x"BF", x"F0", x"B0", x"02", x"B7",
        x"F8", x"FC", x"81", x"09", x"B1", x"01", x"76", x"91", x"7D", x"0F", x"C8", x"A0", x"F2", x"CB", x"78", x"60",
        x"D1", x"F7", x"E0", x"B5", x"98", x"22", x"B3", x"20", x"1D", x"A6", x"DB", x"7B", x"59", x"9F", x"AE", x"31",
        x"FB", x"D3", x"B6", x"CA", x"43", x"72", x"07", x"F4", x"D8", x"41", x"14", x"55", x"0D", x"54", x"8B", x"B9",
        x"AD", x"46", x"0B", x"AF", x"80", x"52", x"2C", x"FA", x"8C", x"89", x"66", x"FD", x"B2", x"A9", x"9B", x"C0");
    type csa_bperm_t is array (0 to 7) of natural range 0 to 7;
    constant CSA_BPERM : csa_bperm_t := (1, 7, 5, 4, 2, 6, 0, 3);
    -- clé : le bit i va en CSA_KPERM(i)
    type csa_kperm_t is array (0 to 63) of natural range 0 to 63;
    constant CSA_KPERM : csa_kperm_t := (
        19, 27, 55, 46,  1, 15, 36, 22, 56, 61, 39, 21, 54, 58, 50, 28,
         7, 29, 51,  6, 33, 35, 20, 16, 47, 30, 32, 63, 10, 11,  4, 38,
        62, 26, 40, 18, 12, 52, 37, 53, 23, 59, 41, 17, 31,  0, 25, 43,
        44, 14,  2, 13, 45, 48,  3, 60, 49,  8, 34,  5,  9, 42, 57, 24);
    -- flux : bits de B (après décalage) ajoutés au bit o de D
    type csa_bsel_t is array (0 to 3, 0 to 3) of natural range 0 to 39;
    constant CSA_BSEL : csa_bsel_t := (
        (13, 27, 32, 38),
        (16, 21, 23, 34),
        (15, 18, 24, 33),
        (12, 25, 30, 39));
    -- flux : 7 boîtes ; entrées : 5 bits de A (après décalage, le premier en
    --   poids faible de l'indice) ; sorties : 2 bits parmi X (0 à 3), Y (4 à 7),
    --   Z (8 à 11), P (12), Q (13) ; tables d'un bit par sortie, indice de
    --   gauche à droite : CSA_F_T1 → CSA_F_OUT(k, 1), CSA_F_T0 → CSA_F_OUT(k, 0)
    type csa_f_in_t is array (0 to 6, 0 to 4) of natural range 0 to 39;
    constant CSA_F_IN : csa_f_in_t := (
        ( 9, 14, 27, 28, 37),
        (19, 22, 24, 33, 38),
        (13, 17, 20, 30, 39),
        ( 6, 16, 25, 31, 36),
        ( 7,  8, 21, 23, 26),
        ( 5, 11, 15, 18, 32),
        (10, 12, 29, 34, 35));
    type csa_f_out_t is array (0 to 6, 0 to 1) of natural range 0 to 13;
    constant CSA_F_OUT : csa_f_out_t := (
        ( 1, 11),
        ( 6,  8),
        ( 7,  9),
        ( 0, 10),
        ( 2,  4),
        ( 3,  5),
        (12, 13));
    type csa_f_tab_t is array (0 to 6) of std_logic_vector(0 to 31);
    constant CSA_F_T1 : csa_f_tab_t := (
        "11100100000110111110100101100001",
        "10101001011111000010101001011001",
        "01010110101010010100101111010010",
        "01000101101010110010110110010110",
        "10011110000011110100100110110100",
        "10010010100011010110011110110010",
        "01101010011101001001010101101010");
    constant CSA_F_T0 : csa_f_tab_t := (
        "11001101001010010010110011010110",
        "00011101010110100110001111000110",
        "00001100001101111111001110000110",
        "11011010011010010111101000010100",
        "01100110100110010110100101101001",
        "11011001001010001000011011011011",
        "00111001110000101001001111100101");
end package csa_tab_pkg;
-- <<< csa_tab_pkg.vhd

--------------------------------------------------------------------------------
-- prbs_disp : dispersion d'énergie DVB-S (EN 300 421 § 4.4.1), un octet par
--   cycle ; référence bit à bit : JPEG2DVB étape 09
--   Interface : flux d'octets valid / ready ; s_sop = 1er octet (synchro 0x47)
--               de chaque paquet TS de 188 octets
--   Principe : groupes de 8 paquets ; paquet 0 : synchro remplacée par 0xB8 et
--              générateur réinitialisé ; paquets 1 à 7 : synchro inchangée, le
--              générateur tourne 8 pas sans être appliqué ; octets 1 à 187 :
--              ou exclusif avec 8 bits de sortie du générateur
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.dvbs_pkg.all;

entity prbs_disp is
    port (
        clk     : in  std_logic;
        rst     : in  std_logic;                     -- synchrone, actif à 1
        s_valid : in  std_logic;
        s_ready : out std_logic;
        s_data  : in  octet_t;
        s_sop   : in  std_logic;
        m_valid : out std_logic;
        m_ready : in  std_logic;
        m_data  : out octet_t;
        m_sop   : out std_logic
    );
end entity prbs_disp;

architecture rtl of prbs_disp is
    signal reg     : prbs_reg_t := PRBS_INIT;
    signal paquet  : unsigned(2 downto 0) := (others => '0');   -- rang du prochain paquet dans le groupe
    signal o_valid : std_logic := '0';
    signal libre   : std_logic;
begin
    libre   <= (not o_valid) or m_ready;
    s_ready <= libre;
    m_valid <= o_valid;

    -- E : octets TS, s_sop → T : tous les 8 paquets synchro 0x47 → 0xB8 et
    --   registre réinitialisé ; synchros non brouillées (registre avancé),
    --   autres octets ⊕ PRBS → S : octets dispersés
    process (clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                reg     <= PRBS_INIT;
                paquet  <= (others => '0');
                o_valid <= '0';
            elsif libre = '1' then
                o_valid <= s_valid;
                if s_valid = '1' then
                    m_sop <= s_sop;
                    if s_sop = '1' then
                        paquet <= paquet + 1;
                        if paquet = 0 then
                            m_data <= x"B8";
                            reg    <= PRBS_INIT;
                        else
                            m_data <= s_data;
                            reg    <= prbs_pas8(reg);
                        end if;
                    else
                        m_data <= s_data xor prbs_octet(reg);
                        reg    <= prbs_pas8(reg);
                    end if;
                end if;
            end if;
        end if;
    end process;
end architecture rtl;

--------------------------------------------------------------------------------
-- rs_enc : codeur Reed-Solomon RS(204,188) raccourci, t = 8 (EN 300 421
--   § 4.4.2) ; référence bit à bit : JPEG2DVB étape 10
--   Interface : entrée : paquets de 188 octets (s_sop sur le 1er) ; sortie :
--               paquets de 204 octets, les 16 octets de parité suivent les données
--   Principe : division de m(x)·x¹⁶ par g(x) dans un registre de 16 octets ;
--              parité émise du coefficient de plus haut degré au plus bas ;
--              l'entrée est suspendue (s_ready = 0) pendant les 16 octets de parité
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.dvbs_pkg.all;

entity rs_enc is
    port (
        clk     : in  std_logic;
        rst     : in  std_logic;
        s_valid : in  std_logic;
        s_ready : out std_logic;
        s_data  : in  octet_t;
        s_sop   : in  std_logic;
        m_valid : out std_logic;
        m_ready : in  std_logic;
        m_data  : out octet_t;
        m_sop   : out std_logic
    );
end entity rs_enc;

architecture rtl of rs_enc is
    signal cnt     : natural range 0 to 203 := 0;     -- rang de l'octet dans le mot de 204
    signal par     : octet_tab_t(0 to 15) := (others => (others => '0'));
    signal o_valid : std_logic := '0';
    signal libre   : std_logic;
begin
    libre   <= (not o_valid) or m_ready;
    s_ready <= libre when cnt < 188 else '0';
    m_valid <= o_valid;

    -- E : paquets de 188 octets → T : division par g(x) au fil des octets
    --   (registre de 16 octets), puis émission des 16 octets de parité → S :
    --   paquets de 204 octets
    process (clk)
        variable fb : octet_t;
    begin
        if rising_edge(clk) then
            if rst = '1' then
                cnt     <= 0;
                par     <= (others => (others => '0'));
                o_valid <= '0';
            elsif libre = '1' then
                if cnt < 188 then
                    o_valid <= s_valid;
                    if s_valid = '1' then
                        m_data <= s_data;
                        m_sop  <= '1' when cnt = 0 else '0';
                        fb := s_data xor par(0);
                        for j in 0 to 14 loop
                            par(j) <= par(j + 1) xor gf_mul(fb, RS_GEN(j + 1));
                        end loop;
                        par(15) <= gf_mul(fb, RS_GEN(16));
                        cnt <= cnt + 1;
                    end if;
                else
                    -- octets de parité ; le registre se vide pour le mot suivant
                    o_valid <= '1';
                    m_data  <= par(0);
                    m_sop   <= '0';
                    par     <= par(1 to 15) & x"00";
                    cnt     <= 0 when cnt = 203 else cnt + 1;
                end if;
            end if;
        end if;
    end process;
end architecture rtl;

--------------------------------------------------------------------------------
-- interleaver : entrelaceur convolutif de Forney, I = 12 branches, M = 17
--   (EN 300 421 § 4.4.2) ; référence bit à bit : JPEG2DVB étape 11
--   Interface : flux d'octets valid / ready, s_sop sur la synchro de chaque mot
--               RS de 204 octets ; un octet sort pour chaque octet entré
--   Principe : l'octet k passe par la branche j = k mod 12, une FIFO de j × 17
--              octets ; les 11 FIFO occupent une mémoire de 1 122 octets
--              (adresse de base 17·j(j−1)/2). La synchro passe toujours par la
--              branche 0 : s_sop remet la branche à 0. Après la remise à zéro,
--              la mémoire est mise à 0 (1 122 cycles) comme dans JPEG2DVB.
--              Lecture synchrone : la branche de l'octet suivant est connue
--              (branche courante + 1, ou la même sans transfert) ; son adresse
--              est présentée à la mémoire un cycle avant, l'octet lu attend
--              dans lu. Lecture et écriture ne visent jamais la même adresse
--              (branches différentes).
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.dvbs_pkg.all;

entity interleaver is
    port (
        clk     : in  std_logic;
        rst     : in  std_logic;
        s_valid : in  std_logic;
        s_ready : out std_logic;
        s_data  : in  octet_t;
        s_sop   : in  std_logic;
        m_valid : out std_logic;
        m_ready : in  std_logic;
        m_data  : out octet_t;
        m_sop   : out std_logic
    );
end entity interleaver;

architecture rtl of interleaver is
    constant I : natural := 12;
    constant M : natural := 17;
    constant TAILLE : natural := M * I * (I - 1) / 2;            -- 1 122
    type base_t is array (0 to I - 1) of natural range 0 to TAILLE;
    -- bases : E : I, M → T : cumul des longueurs de branche j·M → S : adresse
    --   de début de chaque branche en mémoire
    function bases return base_t is
        variable b : base_t;
    begin
        for j in 0 to I - 1 loop
            if j = 0 then b(j) := 0; else b(j) := M * j * (j - 1) / 2; end if;
        end loop;
        return b;
    end function;
    constant BASE : base_t := bases;
    type ram_t is array (0 to TAILLE - 1) of octet_t;
    signal ram     : ram_t;
    type ptr_t is array (1 to I - 1) of natural range 0 to M * (I - 1) - 1;
    signal ptr     : ptr_t;
    attribute syn_ramstyle : string;
    attribute syn_ramstyle of ptr : signal is "registers";
    signal branche : natural range 0 to I - 1 := 0;
    signal efface  : std_logic := '1';
    signal adr_eff : natural range 0 to TAILLE - 1 := 0;
    signal o_valid : std_logic := '0';
    signal libre   : std_logic;
    signal adr_lec : natural range 0 to TAILLE - 1;      -- adresse de l'octet à sortir au transfert suivant
    signal lu      : octet_t;                            -- octet lu à adr_lec
begin
    libre   <= (not o_valid) or m_ready;
    s_ready <= libre and not efface;
    m_valid <= o_valid;

    -- E : transfert en cours, branche → T : branche de l'octet suivant → S :
    --   adresse de lecture (sans objet pour la branche 0)
    process (all)
        variable b, s : natural range 0 to I - 1;
    begin
        s := branche;
        if efface = '0' and libre = '1' and s_valid = '1' then
            if s_sop = '1' then b := 0; else b := branche; end if;
            if b = I - 1 then s := 0; else s := b + 1; end if;
        end if;
        if s = 0 then
            adr_lec <= 0;
        else
            adr_lec <= BASE(s) + ptr(s);
        end if;
    end process;

    -- lecture synchrone de la mémoire
    process (clk)
    begin
        if rising_edge(clk) then
            lu <= ram(adr_lec);
        end if;
    end process;

    -- E : octets des paquets de 204 → T : branche j = rang mod 12, lecture puis
    --   écriture dans la FIFO de j·17 octets → S : octets entrelacés
    process (clk)
        variable b : natural range 0 to I - 1;
        variable a : natural range 0 to TAILLE - 1;
    begin
        if rising_edge(clk) then
            if rst = '1' then
                efface  <= '1';
                adr_eff <= 0;
                branche <= 0;
                ptr     <= (others => 0);
                o_valid <= '0';
            elsif efface = '1' then
                ram(adr_eff) <= x"00";
                if adr_eff = TAILLE - 1 then
                    efface <= '0';
                else
                    adr_eff <= adr_eff + 1;
                end if;
            elsif libre = '1' then
                o_valid <= s_valid;
                if s_valid = '1' then
                    m_sop <= s_sop;
                    b := 0 when s_sop = '1' else branche;
                    if b = 0 then
                        m_data <= s_data;
                    else
                        a := BASE(b) + ptr(b);
                        m_data <= lu;                        -- lu au cycle précédent
                        ram(a) <= s_data;
                        ptr(b) <= 0 when ptr(b) = M * b - 1 else ptr(b) + 1;
                    end if;
                    branche <= 0 when b = I - 1 else b + 1;
                end if;
            end if;
        end if;
    end process;
end architecture rtl;

--------------------------------------------------------------------------------
-- conv_enc : codeur convolutif K = 7, G1 = 171, G2 = 133 (octal), poinçonnage
--   1/2, 2/3, 3/4, 5/6, 7/8 (EN 300 421 § 4.4.3, tableau 2) ;
--   référence bit à bit : JPEG2DVB étape 12
--   Interface : entrée : octets (valid / ready), premier bit en poids fort ;
--               sortie : paires de bits (m_data(1) = I, m_data(0) = Q), une paire
--               par symbole QPSK
--   Principe : un bit d'entrée par cycle ; X et Y retenus selon le motif de
--              poinçonnage, dans l'ordre X puis Y de chaque instant ; les bits
--              retenus sont regroupés deux par deux (I puis Q). Registre : D0
--              (bit précédent) en bit 5, D5 en bit 0.
--   Paramètre : G_FEC 0 = 1/2, 1 = 2/3, 2 = 3/4, 3 = 5/6, 4 = 7/8
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.dvbs_pkg.all;

entity conv_enc is
    generic (
        G_FEC : natural range 0 to 4 := 0
    );
    port (
        clk     : in  std_logic;
        rst     : in  std_logic;
        s_valid : in  std_logic;
        s_ready : out std_logic;
        s_data  : in  octet_t;
        m_valid : out std_logic;
        m_ready : in  std_logic;
        m_data  : out std_logic_vector(1 downto 0)
    );
end entity conv_enc;

architecture rtl of conv_enc is
    -- motifs de poinçonnage (X, Y), lus du bit 0 au bit L-1
    type motif_t is record
        l : natural range 1 to 7;
        x : std_logic_vector(6 downto 0);
        y : std_logic_vector(6 downto 0);
    end record;
    type motifs_t is array (0 to 4) of motif_t;
    constant MOTIFS : motifs_t := (
        (1, "0000001", "0000001"),              -- 1/2 : X 1        Y 1
        (2, "0000001", "0000011"),              -- 2/3 : X 10       Y 11
        (3, "0000101", "0000011"),              -- 3/4 : X 101      Y 110
        (5, "0010101", "0001011"),              -- 5/6 : X 10101    Y 11010
        (7, "1010001", "0101111"));             -- 7/8 : X 1000101  Y 1111010
    constant MT : motif_t := MOTIFS(G_FEC);

    signal octet_c  : octet_t := (others => '0');
    signal nbits    : natural range 0 to 8 := 0;          -- bits restant à coder dans octet_c
    signal reg      : std_logic_vector(5 downto 0) := (others => '0');
    signal phase    : natural range 0 to 6 := 0;          -- position dans le motif
    signal attente  : std_logic := '0';                   -- un bit retenu en attente de son partenaire
    signal bit_att  : std_logic := '0';
    signal o_valid  : std_logic := '0';
    signal libre    : std_logic;
begin
    libre   <= (not o_valid) or m_ready;
    s_ready <= '1' when nbits = 0 and rst = '0' else '0';
    m_valid <= o_valid;

    -- E : octets, premier bit en poids fort → T : registre K = 7, sorties X
    --   (171) et Y (133), poinçonnage selon G_FEC → S : bits codés
    process (clk)
        variable b, x, y : std_logic;
        variable etat    : std_logic_vector(6 downto 0);
        variable q       : std_logic_vector(2 downto 0);    -- bits disponibles, le plus ancien en poids fort
        variable n       : natural range 0 to 3;
    begin
        if rising_edge(clk) then
            if rst = '1' then
                nbits   <= 0;
                reg     <= (others => '0');
                phase   <= 0;
                attente <= '0';
                o_valid <= '0';
            else
                if libre = '1' then
                    o_valid <= '0';
                end if;
                if nbits = 0 then
                    if s_valid = '1' then
                        octet_c <= s_data;
                        nbits   <= 8;
                    end if;
                elsif libre = '1' then
                    -- un bit d'entrée
                    b    := octet_c(7);
                    etat := b & reg;
                    x    := parite(etat and CONV_G1);
                    y    := parite(etat and CONV_G2);
                    reg  <= b & reg(5 downto 1);
                    octet_c <= octet_c(6 downto 0) & '0';
                    nbits   <= nbits - 1;
                    phase   <= 0 when phase = MT.l - 1 else phase + 1;
                    -- file des bits retenus : attente, puis X, puis Y
                    n := 0; q := "000";
                    if attente = '1' then q(2 - n) := bit_att; n := n + 1; end if;
                    if MT.x(phase) = '1' then q(2 - n) := x; n := n + 1; end if;
                    if MT.y(phase) = '1' then q(2 - n) := y; n := n + 1; end if;
                    if n >= 2 then
                        m_data  <= q(2) & q(1);
                        o_valid <= '1';
                        attente <= '1' when n = 3 else '0';
                        bit_att <= q(0);
                    else
                        attente <= '1' when n = 1 else '0';
                        bit_att <= q(2);
                    end if;
                end if;
            end if;
        end if;
    end process;
end architecture rtl;

--------------------------------------------------------------------------------
-- qpsk_map : mise en correspondance QPSK (EN 300 421 § 4.5, figure 6) :
--   bit 0 → +1, bit 1 → −1 sur chaque voie ; référence bit à bit :
--   JPEG2DVB étape 13 (symboles entiers ±1)
--   Interface : entrée : paire de bits (s_data(1) = I, s_data(0) = Q) ;
--               sortie : I et Q signés sur 2 bits (+1 = "01", −1 = "11") ;
--               combinatoire, le contrôle de flux traverse le module
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity qpsk_map is
    port (
        s_valid : in  std_logic;
        s_ready : out std_logic;
        s_data  : in  std_logic_vector(1 downto 0);
        m_valid : out std_logic;
        m_ready : in  std_logic;
        m_i     : out signed(1 downto 0);
        m_q     : out signed(1 downto 0)
    );
end entity qpsk_map;

architecture rtl of qpsk_map is
begin
    m_valid <= s_valid;
    s_ready <= m_ready;
    m_i     <= "11" when s_data(1) = '1' else "01";
    m_q     <= "11" when s_data(0) = '1' else "01";
end architecture rtl;

--------------------------------------------------------------------------------
-- srrc_poly : filtre de mise en forme SRRC, α = 0,35, 8 échantillons par
--   symbole, forme polyphase à coefficients entiers 16 bits ;
--   référence bit à bit : JPEG2DVB étape 14 (fichier .cs16)
--   Interface : entrée : symboles I, Q signés 2 bits (±1) ; sortie : I, Q
--               signés 16 bits, 8 échantillons par symbole, un par cycle
--   Principe : registre des 13 derniers symboles (initialement 0, comme les
--              symboles hors flux de JPEG2DVB) ; à l'arrivée du symbole n + 6,
--              les 8 échantillons du symbole n sont calculés :
--              y(8n + r) = Σd C(r)(d) · s(n − 6 + d). Symboles ±1 : additions
--              et soustractions de constantes, aucun multiplieur. La somme des
--              |C| ne dépasse pas 0,95 × 32 767 : pas de saturation.
--              Débit : 8 cycles par symbole (le symbole suivant est accepté
--              pendant le 8e échantillon), soit 80 MHz pour 10 MS/s.
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.srrc_coef_pkg.all;

entity srrc_poly is
    port (
        clk     : in  std_logic;
        rst     : in  std_logic;
        s_valid : in  std_logic;
        s_ready : out std_logic;
        s_i     : in  signed(1 downto 0);
        s_q     : in  signed(1 downto 0);
        m_valid : out std_logic;
        m_ready : in  std_logic;
        m_i     : out signed(15 downto 0);
        m_q     : out signed(15 downto 0)
    );
end entity srrc_poly;

architecture rtl of srrc_poly is
    type sym_tab_t is array (0 to SRRC_TAPS - 1) of signed(1 downto 0);    -- 0 : le plus ancien
    signal sh_i, sh_q : sym_tab_t := (others => (others => '0'));
    signal recus   : natural range 0 to SRRC_TAPS := 0;     -- symboles reçus (saturé)
    signal occupe  : std_logic := '0';
    signal r       : natural range 0 to SRRC_SPS - 1 := 0;
    signal o_valid : std_logic := '0';
    signal libre   : std_logic;
    signal pret    : std_logic;

    -- somme : E : derniers symboles ±1, phase → T : coefficients de la phase
    --   ajoutés ou retranchés selon le signe (sans multiplieur) → S :
    --   échantillon
    function somme(sh : sym_tab_t; ph : natural) return signed is
        variable acc : integer range -65536 to 65535 := 0;
    begin
        for d in 0 to SRRC_TAPS - 1 loop
            if sh(d) = "01" then
                acc := acc + SRRC_C(ph)(d);
            elsif sh(d) = "11" then
                acc := acc - SRRC_C(ph)(d);
            end if;
        end loop;
        return to_signed(acc, 16);
    end function;
begin
    libre   <= (not o_valid) or m_ready;
    pret    <= '1' when rst = '0' and (occupe = '0' or (r = SRRC_SPS - 1 and libre = '1')) else '0';
    s_ready <= pret;
    m_valid <= o_valid;

    -- E : symboles QPSK → T : un symbole tous les 8 cycles dans la ligne à
    --   retard, une phase par cycle → S : un échantillon I/Q par cycle
    process (clk)
        variable entre : boolean;
    begin
        if rising_edge(clk) then
            if rst = '1' then
                sh_i    <= (others => (others => '0'));
                sh_q    <= (others => (others => '0'));
                recus   <= 0;
                occupe  <= '0';
                r       <= 0;
                o_valid <= '0';
            else
                if libre = '1' then
                    o_valid <= '0';
                end if;
                -- échantillon r du symbole central (position 6 du registre)
                if occupe = '1' and libre = '1' then
                    m_i     <= somme(sh_i, r);
                    m_q     <= somme(sh_q, r);
                    o_valid <= '1';
                    if r = SRRC_SPS - 1 then
                        occupe <= '0';
                    end if;
                    r <= 0 when r = SRRC_SPS - 1 else r + 1;
                end if;
                -- nouveau symbole
                entre := s_valid = '1' and pret = '1';
                if entre then
                    sh_i <= sh_i(1 to SRRC_TAPS - 1) & s_i;
                    sh_q <= sh_q(1 to SRRC_TAPS - 1) & s_q;
                    if recus < SRRC_TAPS then
                        recus <= recus + 1;
                    end if;
                    -- 7 symboles reçus : le symbole 0 est au centre
                    if recus >= SRRC_TAPS / 2 then
                        occupe <= '1';
                        r      <= 0;
                    end if;
                end if;
            end if;
        end if;
    end process;
end architecture rtl;

--------------------------------------------------------------------------------
-- tx_backend : chaîne arrière DVB-S complète, du Transport Stream aux
--   échantillons I/Q mis en forme : dispersion d'énergie →
--   RS(204,188) → entrelaceur → codeur convolutif → QPSK → SRRC ;
--   référence bit à bit : JPEG2DVB, étape 08 en entrée, fichier
--   .cs16 de l'étape 14 en sortie
--   Interface : entrée : paquets TS de 188 octets (s_sop sur la synchro 0x47) ;
--               sortie : I, Q signés 16 bits, 8 échantillons par symbole
--   Débit : horloge = 8 × débit symbole (80 MHz pour 10 MS/s) ; le SRRC
--           impose le rythme, le contrôle de flux remonte jusqu'à l'entrée TS
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.dvbs_pkg.all;

entity tx_backend is
    generic (
        G_FEC : natural range 0 to 4 := 0           -- 0 = 1/2 … 4 = 7/8
    );
    port (
        clk     : in  std_logic;
        rst     : in  std_logic;
        s_valid : in  std_logic;
        s_ready : out std_logic;
        s_data  : in  octet_t;
        s_sop   : in  std_logic;
        m_valid : out std_logic;
        m_ready : in  std_logic;
        m_i     : out signed(15 downto 0);
        m_q     : out signed(15 downto 0)
    );
end entity tx_backend;

architecture rtl of tx_backend is
    signal p_valid, p_ready, p_sop : std_logic;
    signal p_data                  : octet_t;
    signal r_valid, r_ready, r_sop : std_logic;
    signal r_data                  : octet_t;
    signal e_valid, e_ready, e_sop : std_logic;
    signal e_data                  : octet_t;
    signal c_valid, c_ready        : std_logic;
    signal c_data                  : std_logic_vector(1 downto 0);
    signal q_valid, q_ready        : std_logic;
    signal q_i, q_q                : signed(1 downto 0);
begin
    u_prbs : entity work.prbs_disp
        port map (clk, rst, s_valid, s_ready, s_data, s_sop, p_valid, p_ready, p_data, p_sop);
    u_rs : entity work.rs_enc
        port map (clk, rst, p_valid, p_ready, p_data, p_sop, r_valid, r_ready, r_data, r_sop);
    u_inter : entity work.interleaver
        port map (clk, rst, r_valid, r_ready, r_data, r_sop, e_valid, e_ready, e_data, e_sop);
    u_conv : entity work.conv_enc generic map (G_FEC => G_FEC)
        port map (clk, rst, e_valid, e_ready, e_data, c_valid, c_ready, c_data);
    u_qpsk : entity work.qpsk_map
        port map (c_valid, c_ready, c_data, q_valid, q_ready, q_i, q_q);
    u_srrc : entity work.srrc_poly
        port map (clk, rst, q_valid, q_ready, q_i, q_q, m_valid, m_ready, m_i, m_q);
end architecture rtl;

--------------------------------------------------------------------------------
-- dct8x8_int : DCT 8 × 8 entière, MPEG-2 intra (sans centrage) ; référence
--   bit à bit : JPEG2DVB étape 02, option « virgule fixe »
--   Interface : entrée : 64 pixels d'un bloc (octets non signés), ligne par
--               ligne ; sortie : 64 coefficients signés 16 bits en ordre
--               naturel F[v][u] (indice 8v + u)
--   Principe : Ci[k][n] = round(4096 · c(k)/2 · cos((2n+1)kπ/16)), 13 bits ;
--              passe lignes R'[y][u] = (Σx Ci[u][x]·f[y][x] + 32) >> 6 ;
--              passe colonnes F[v][u] = (Σy Ci[v][y]·R'[y][u] + 2¹⁷) >> 18
--              (décalages arithmétiques).
--              Symétrie Ci[k][7 − n] = (−1)^k · Ci[k][n] : chaque somme porte sur
--              4 produits Ci[k][n] · (a(n) ± a(7 − n)), + si k pair, − si k impair
--              (4 multiplieurs par passe, même résultat entier).
--   Étages : lignes : les 8 pixels d'une ligne reçus, leurs sommes et
--            différences sont figées ; les 8 R' de la ligne sont écrits en
--            mémoire pendant que la ligne suivante se charge ;
--            colonnes : la colonne u de R' est lue (8 cycles), sommes et
--            différences figées, les 8 F[v][u] écrits dans le tampon de sortie
--            pendant la lecture de la colonne suivante ;
--            sortie : tampon lu en ordre naturel, pendant le chargement du bloc
--            suivant. |F| ≤ 2 040 : tampon de 12 bits.
--   Débit : environ 140 cycles par bloc en régime continu (192 auparavant).
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity dct8x8_int is
    port (
        clk     : in  std_logic;
        rst     : in  std_logic;
        s_valid : in  std_logic;
        s_ready : out std_logic;
        s_data  : in  unsigned(7 downto 0);
        m_valid : out std_logic;
        m_ready : in  std_logic;
        m_data  : out signed(15 downto 0)
    );
end entity dct8x8_int;

architecture rtl of dct8x8_int is
    -- moitié gauche de Ci (n = 0 à 3) ; Ci[k][7 − n] = (−1)^k · Ci[k][n]
    type ci_t is array (0 to 7, 0 to 3) of integer range -2048 to 2047;
    constant CI : ci_t := (
        (1448,  1448,  1448,  1448),
        (2009,  1703,  1138,   400),
        (1892,   784,  -784, -1892),
        (1703,  -400, -2009, -1138),
        (1448, -1448, -1448,  1448),
        (1138, -2009,   400,  1703),
        ( 784, -1892,  1892,  -784),
        ( 400, -1138,  1703, -2009));

    -- passe lignes
    type pix7_t is array (0 to 6) of unsigned(7 downto 0);
    type opl_t  is array (0 to 3) of signed(9 downto 0);
    signal lig      : pix7_t;                              -- pixels 0 à 6 de la ligne en cours
    signal l_s, l_d : opl_t;                               -- f(x) + f(7 − x), f(x) − f(7 − x)
    signal xi, yi   : natural range 0 to 7 := 0;
    signal charge   : std_logic := '1';                    -- le bloc se charge
    signal l_act    : std_logic := '0';
    signal l_u, l_y : natural range 0 to 7 := 0;
    -- R' en mémoire (adresse 8y + u)
    type rr_t is array (0 to 63) of signed(17 downto 0);
    signal rr       : rr_t;
    signal rr_plein : std_logic := '0';                    -- R' complet, à lire
    -- passe colonnes
    type col7_t is array (0 to 6) of signed(17 downto 0);
    type opc_t  is array (0 to 3) of signed(18 downto 0);
    signal c_occ    : std_logic := '0';                    -- passe colonnes en cours
    signal c_act    : std_logic := '0';                    -- lecture de R' en cours
    signal c_u, c_y : natural range 0 to 7 := 0;
    signal q_valid  : std_logic := '0';
    signal q_u, q_y : natural range 0 to 7 := 0;
    signal rq       : signed(17 downto 0);                 -- R' lu
    signal col      : col7_t;                              -- R'[0..6][u] de la colonne en cours
    signal k_s, k_d : opc_t;                               -- R'(y) + R'(7 − y), R'(y) − R'(7 − y)
    signal k_act    : std_logic := '0';
    signal k_v, k_u : natural range 0 to 7 := 0;
    -- tampon de sortie (adresse 8v + u)
    type fb_t is array (0 to 63) of signed(11 downto 0);
    signal fb       : fb_t;
    signal f_plein  : std_logic := '0';
    signal lec      : natural range 0 to 63 := 0;
    signal o_valid  : std_logic := '0';
    signal libre    : std_logic;
begin
    libre   <= (not o_valid) or m_ready;
    s_ready <= charge and not rst;
    m_valid <= o_valid;

    -- E : pixels 0..255 par blocs de 64 → T : passe lignes (Σ + 32) >> 6 au fil
    --   du chargement, passe colonnes (Σ + 2¹⁷) >> 18 colonne par colonne,
    --   coefficients Ci sur 13 bits → S : coefficients F[v][u] en ordre naturel
    process (clk)
        variable tl   : signed(9 downto 0);
        variable accl : signed(24 downto 0);
        variable tc   : signed(18 downto 0);
        variable accc : signed(33 downto 0);
        variable p7   : signed(9 downto 0);
    begin
        if rising_edge(clk) then
            if rst = '1' then
                xi <= 0; yi <= 0; charge <= '1'; l_act <= '0'; rr_plein <= '0';
                c_occ <= '0'; c_act <= '0'; q_valid <= '0'; k_act <= '0';
                f_plein <= '0'; lec <= 0; o_valid <= '0';
            else
                ----------------------------------------------------------------
                -- passe lignes : R'[l_y][l_u], un par cycle
                ----------------------------------------------------------------
                if l_act = '1' then
                    accl := to_signed(32, 25);
                    for i in 0 to 3 loop
                        if l_u mod 2 = 0 then tl := l_s(i); else tl := l_d(i); end if;
                        accl := accl + resize(to_signed(CI(l_u, i), 13) * tl, 25);
                    end loop;
                    rr(l_y * 8 + l_u) <= resize(shift_right(accl, 6), 18);
                    if l_u = 7 then
                        l_act <= '0';
                        if l_y = 7 then
                            rr_plein <= '1';
                        end if;
                    else
                        l_u <= l_u + 1;
                    end if;
                end if;
                ----------------------------------------------------------------
                -- chargement : au huitième pixel, sommes et différences de la ligne
                ----------------------------------------------------------------
                if s_valid = '1' and charge = '1' then
                    if xi < 7 then
                        lig <= lig(1 to 6) & s_data;
                        xi  <= xi + 1;
                    else
                        p7 := signed(resize(s_data, 10));
                        l_s(0) <= signed(resize(lig(0), 10)) + p7;
                        l_d(0) <= signed(resize(lig(0), 10)) - p7;
                        for i in 1 to 3 loop
                            l_s(i) <= signed(resize(lig(i), 10)) + signed(resize(lig(7 - i), 10));
                            l_d(i) <= signed(resize(lig(i), 10)) - signed(resize(lig(7 - i), 10));
                        end loop;
                        l_act <= '1';
                        l_u   <= 0;
                        l_y   <= yi;
                        xi    <= 0;
                        if yi = 7 then
                            yi     <= 0;
                            charge <= '0';
                        else
                            yi <= yi + 1;
                        end if;
                    end if;
                end if;

                ----------------------------------------------------------------
                -- passe colonnes : F[k_v][k_u], un par cycle, vers le tampon
                ----------------------------------------------------------------
                if k_act = '1' then
                    accc := to_signed(131072, 34);
                    for i in 0 to 3 loop
                        if k_v mod 2 = 0 then tc := k_s(i); else tc := k_d(i); end if;
                        accc := accc + resize(to_signed(CI(k_v, i), 13) * tc, 34);
                    end loop;
                    fb(k_v * 8 + k_u) <= resize(shift_right(accc, 18), 12);
                    if k_v = 7 then
                        k_act <= '0';
                        if k_u = 7 then
                            f_plein <= '1';
                            c_occ   <= '0';
                        end if;
                    else
                        k_v <= k_v + 1;
                    end if;
                end if;
                -- R' lu : colonne rangée, puis sommes et différences au huitième
                if q_valid = '1' then
                    if q_y < 7 then
                        col <= col(1 to 6) & rq;
                    else
                        k_s(0) <= resize(col(0), 19) + resize(rq, 19);
                        k_d(0) <= resize(col(0), 19) - resize(rq, 19);
                        for i in 1 to 3 loop
                            k_s(i) <= resize(col(i), 19) + resize(col(7 - i), 19);
                            k_d(i) <= resize(col(i), 19) - resize(col(7 - i), 19);
                        end loop;
                        k_act <= '1';
                        k_v   <= 0;
                        k_u   <= q_u;
                    end if;
                end if;
                -- lecture de R' colonne par colonne ; la dernière adresse émise,
                --   le bloc suivant peut se charger
                q_valid <= c_act;
                q_u     <= c_u;
                q_y     <= c_y;
                rq      <= rr(c_y * 8 + c_u);
                if c_act = '1' then
                    if c_y = 7 then
                        c_y <= 0;
                        if c_u = 7 then
                            c_u      <= 0;
                            c_act    <= '0';
                            rr_plein <= '0';
                            charge   <= '1';
                        else
                            c_u <= c_u + 1;
                        end if;
                    else
                        c_y <= c_y + 1;
                    end if;
                elsif rr_plein = '1' and c_occ = '0' and f_plein = '0' then
                    c_act <= '1';
                    c_occ <= '1';
                    c_u   <= 0;
                    c_y   <= 0;
                end if;

                ----------------------------------------------------------------
                -- sortie : tampon en ordre naturel
                ----------------------------------------------------------------
                if libre = '1' then
                    o_valid <= '0';
                    if f_plein = '1' then
                        m_data  <= resize(fb(lec), 16);
                        o_valid <= '1';
                        if lec = 63 then
                            lec     <= 0;
                            f_plein <= '0';
                        else
                            lec <= lec + 1;
                        end if;
                    end if;
                end if;
            end if;
        end if;
    end process;
end architecture rtl;

--------------------------------------------------------------------------------
-- quant_intra : quantification MPEG-2 intra, matrice par défaut, q_scale_type 0 ;
--   référence bit à bit : JPEG2DVB étape 03
--   Interface : entrée : coefficients DCT signés 16 bits, blocs de 64 en ordre
--               naturel ; code : quantiser_scale_code (1 à 31) lu avec chaque
--               coefficient ; sortie : coefficients quantifiés signés 16 bits
--   Principe : DC : (F + 4) >> 3 borné à 0..255 ;
--              AC : ±floor((32|F| + D) / (2D)) borné à 2 047, D = W·2·code
--              (même arrondi que Math.round de la page 03). Division exacte :
--              le quotient vaut ⌊n / d⌋ avec n = 16|F| + W·code et d = 2·W·code ;
--              estimation ⌊n·m / 2¹⁸⌋ par l'inverse m = ⌊2¹⁸ / d⌋ + 1, puis
--              correction d'une unité (vérifié sur les 63 × 31 × 4 096 cas).
--              m (14 bits) et W·code (12 bits) sont lus dans une mémoire morte
--              synchrone de 2 048 mots (adresse : code & position).
--   Étages : A : |F|, DC, lecture de la mémoire ; B : produit n·m ;
--            C : correction, bornage, signe. Les trois avancent ensemble.
--   Domaine : |F| ≤ 4 095 (la DCT de pixels 8 bits donne |F| ≤ 2 040)
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity quant_intra is
    port (
        clk     : in  std_logic;
        rst     : in  std_logic;
        code    : in  unsigned(4 downto 0);
        s_valid : in  std_logic;
        s_ready : out std_logic;
        s_data  : in  signed(15 downto 0);
        m_valid : out std_logic;
        m_ready : in  std_logic;
        m_data  : out signed(15 downto 0)
    );
end entity quant_intra;

architecture rtl of quant_intra is
    type w_t is array (0 to 63) of natural range 0 to 255;
    -- default_intra_quantiser_matrix, ordre naturel F[v][u]
    constant W : w_t := (
         8, 16, 19, 22, 26, 27, 29, 34,
        16, 16, 22, 24, 27, 29, 34, 37,
        19, 22, 26, 27, 29, 34, 34, 38,
        22, 22, 26, 27, 29, 34, 37, 40,
        22, 26, 27, 29, 32, 35, 40, 48,
        26, 27, 29, 32, 35, 40, 48, 58,
        26, 27, 29, 34, 38, 46, 56, 69,
        27, 29, 35, 38, 46, 56, 69, 83);
    constant RB : natural := 18;                         -- échelle de l'inverse : 2^RB
    subtype mot_t is std_logic_vector(25 downto 0);      -- m (14 bits) & W·code (12 bits)
    type rom_t is array (0 to 2047) of mot_t;
    -- inverses : E : matrice W → T : pour 32 codes × 64 positions (code 0 traité
    --   comme 1, position 0 = DC, inutilisée), m = ⌊2^RB / (2·W·code)⌋ + 1 et
    --   W·code → S : contenu de la mémoire morte, adresse = 64·code + position
    function inverses return rom_t is
        variable t  : rom_t := (others => (others => '0'));
        variable c  : natural range 1 to 31;
        variable wc : natural range 0 to 4095;
    begin
        for cc in 0 to 31 loop
            if cc = 0 then c := 1; else c := cc; end if;
            for i in 1 to 63 loop
                wc := W(i) * c;
                t(64 * cc + i) := std_logic_vector(to_unsigned((2 ** RB) / (2 * wc) + 1, 14)) & std_logic_vector(to_unsigned(wc, 12));
            end loop;
        end loop;
        return t;
    end function;
    constant INV : rom_t := inverses;

    signal idx     : natural range 0 to 63 := 0;
    signal adr     : unsigned(10 downto 0);
    signal rom_q   : mot_t := (others => '0');           -- étage A : mot lu
    signal a_valid, a_dc, a_neg : std_logic := '0';
    signal a_abs   : unsigned(11 downto 0) := (others => '0');   -- |F|, ou DC borné
    signal b_valid, b_dc, b_neg : std_logic := '0';
    signal b_n     : unsigned(16 downto 0) := (others => '0');   -- n = 16|F| + W·code
    signal b_wc    : unsigned(11 downto 0) := (others => '0');
    signal b_q     : unsigned(12 downto 0) := (others => '0');   -- estimation, ou DC borné
    signal o_valid : std_logic := '0';
    signal libre   : std_logic;
begin
    libre   <= (not o_valid) or m_ready;
    s_ready <= libre and not rst;
    m_valid <= o_valid;
    adr     <= code & to_unsigned(idx, 6);

    -- E : code, position → T : lecture synchrone → S : inverse et W·code du
    --   coefficient entré dans l'étage A
    process (clk)
    begin
        if rising_edge(clk) then
            if libre = '1' then
                rom_q <= INV(to_integer(adr));
            end if;
        end if;
    end process;

    -- E : coefficient, code → T : A : DC (F + 4) >> 3 borné à 0..255, AC |F| et
    --   signe ; B : estimation du quotient par l'inverse ; C : correction d'une
    --   unité, borné à 2 047, signe → S : coefficient quantifié
    process (clk)
        variable dc : signed(16 downto 0);
        variable a  : unsigned(15 downto 0);
        variable n  : unsigned(16 downto 0);
        variable p  : unsigned(30 downto 0);
        variable d  : unsigned(12 downto 0);
        variable q  : unsigned(12 downto 0);
        variable r  : integer range 0 to 2047;
    begin
        if rising_edge(clk) then
            if rst = '1' then
                idx     <= 0;
                a_valid <= '0';
                b_valid <= '0';
                o_valid <= '0';
            elsif libre = '1' then
                -- étage A
                a_valid <= s_valid;
                if s_valid = '1' then
                    if idx = 0 then
                        dc := shift_right(resize(s_data, 17) + 4, 3);
                        if dc < 0 then
                            a_abs <= (others => '0');
                        elsif dc > 255 then
                            a_abs <= to_unsigned(255, 12);
                        else
                            a_abs <= unsigned(dc(11 downto 0));
                        end if;
                        a_dc  <= '1';
                        a_neg <= '0';
                    else
                        a     := unsigned(abs(s_data));
                        a_abs <= a(11 downto 0);
                        a_dc  <= '0';
                        a_neg <= s_data(15);
                    end if;
                    idx <= 0 when idx = 63 else idx + 1;
                end if;
                -- étage B
                b_valid <= a_valid;
                b_dc    <= a_dc;
                b_neg   <= a_neg;
                n       := resize(a_abs & "0000", 17) + unsigned(rom_q(11 downto 0));
                p       := n * unsigned(rom_q(25 downto 12));
                b_n     <= n;
                b_wc    <= unsigned(rom_q(11 downto 0));
                if a_dc = '1' then
                    b_q <= resize(a_abs, 13);
                else
                    b_q <= p(30 downto RB);
                end if;
                -- étage C
                o_valid <= b_valid;
                q := b_q;
                if b_dc = '0' then
                    d := b_wc & '0';
                    if q * d > resize(b_n, 26) then
                        q := q - 1;
                    end if;
                end if;
                if q > 2047 then
                    r := 2047;
                else
                    r := to_integer(q);
                end if;
                if b_neg = '1' then
                    m_data <= to_signed(-r, 16);
                else
                    m_data <= to_signed(r, 16);
                end if;
            end if;
        end if;
    end process;
end architecture rtl;

--------------------------------------------------------------------------------
-- zigzag : balayage zigzag (alternate_scan = 0) d'un bloc de 64
--   coefficients ; référence bit à bit : JPEG2DVB étape 04
--   Interface : entrée : 64 coefficients en ordre naturel ; sortie : les mêmes
--               en ordre zigzag (sortie i = entrée ZZ(i))
--   Principe : deux mémoires de bloc en alternance : un bloc se charge
--              pendant que le précédent sort, un coefficient par cycle
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity zigzag is
    port (
        clk     : in  std_logic;
        rst     : in  std_logic;
        s_valid : in  std_logic;
        s_ready : out std_logic;
        s_data  : in  signed(15 downto 0);
        m_valid : out std_logic;
        m_ready : in  std_logic;
        m_data  : out signed(15 downto 0)
    );
end entity zigzag;

architecture rtl of zigzag is
    type zz_t is array (0 to 63) of natural range 0 to 63;
    constant ZZ : zz_t := (
         0,  1,  8, 16,  9,  2,  3, 10, 17, 24, 32, 25, 18, 11,  4,  5,
        12, 19, 26, 33, 40, 48, 41, 34, 27, 20, 13,  6,  7, 14, 21, 28,
        35, 42, 49, 56, 57, 50, 43, 36, 29, 22, 15, 23, 30, 37, 44, 51,
        58, 59, 52, 45, 38, 31, 39, 46, 53, 60, 61, 54, 47, 55, 62, 63);
    type mem_t is array (0 to 127) of signed(15 downto 0);
    signal mem      : mem_t;
    signal ecr      : natural range 0 to 63 := 0;      -- position d'écriture
    signal bec      : std_logic := '0';                 -- banc en écriture
    signal plein    : std_logic_vector(0 to 1) := "00"; -- banc prêt à sortir
    signal lec      : natural range 0 to 63 := 0;
    signal bl       : std_logic := '0';                 -- banc en lecture
    signal o_valid  : std_logic := '0';
    signal libre    : std_logic;
    signal s_rdy    : std_logic;
begin
    libre   <= (not o_valid) or m_ready;
    s_rdy   <= '1' when rst = '0' and plein(to_integer(unsigned'("" & bec))) = '0' else '0';
    s_ready <= s_rdy;
    m_valid <= o_valid;

    -- E : coefficients en ordre naturel → T : écriture dans un banc pendant la
    --   lecture de l'autre en ordre zigzag → S : vecteurs de 64
    process (clk)
        variable pl : std_logic_vector(0 to 1);
    begin
        if rising_edge(clk) then
            if rst = '1' then
                ecr <= 0; bec <= '0'; plein <= "00"; lec <= 0; bl <= '0'; o_valid <= '0';
            else
                pl := plein;
                -- écriture
                if s_valid = '1' and s_rdy = '1' then
                    mem(to_integer(unsigned'("" & bec)) * 64 + ecr) <= s_data;
                    if ecr = 63 then
                        ecr <= 0;
                        pl(to_integer(unsigned'("" & bec))) := '1';
                        bec <= not bec;
                    else
                        ecr <= ecr + 1;
                    end if;
                end if;
                -- lecture
                if libre = '1' then
                    o_valid <= '0';
                    if plein(to_integer(unsigned'("" & bl))) = '1' then
                        m_data  <= mem(to_integer(unsigned'("" & bl)) * 64 + ZZ(lec));
                        o_valid <= '1';
                        if lec = 63 then
                            lec <= 0;
                            pl(to_integer(unsigned'("" & bl))) := '0';
                            bl <= not bl;
                        else
                            lec <= lec + 1;
                        end if;
                    end if;
                end if;
                plein <= pl;
            end if;
        end if;
    end process;
end architecture rtl;

--------------------------------------------------------------------------------
-- vlc_enc : codage entropique MPEG-2 intra des blocs balayés en zigzag :
--   DC différentiel (B.12, B.13), paires run / niveau (B.14),
--   échappement, fin de bloc ; référence bit à bit : JPEG2DVB
--   étape 05
--   Interface : entrée : vecteurs zigzag de 64 coefficients, 6 blocs par
--               macrobloc (Y0 à Y3, Cb, Cr), G_COLS macroblocs par slice ;
--               sortie : mots de code cadrés à droite (m_code, m_lg bits), un
--               mot au plus par coefficient ; m_fin_mb marque le dernier mot
--               du macrobloc
--   Principe : prédicteurs DC (Y, Cb, Cr) remis à 128 au début de chaque
--              slice ; DC : code de taille puis différence (complément à 1 si
--              négative) ; AC : code de B.14 suivi du signe, sinon
--              échappement 000001 + run (6 bits) + niveau (12 bits, complément
--              à 2) ; le code de fin de bloc « 10 » est accolé au dernier mot
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.vlc_tab_pkg.all;

entity vlc_enc is
    generic (
        G_COLS : natural := 22                       -- macroblocs par slice
    );
    port (
        clk      : in  std_logic;
        rst      : in  std_logic;
        s_valid  : in  std_logic;
        s_ready  : out std_logic;
        s_data   : in  signed(15 downto 0);
        m_valid  : out std_logic;
        m_ready  : in  std_logic;
        m_code   : out std_logic_vector(31 downto 0);
        m_lg     : out unsigned(5 downto 0);
        m_fin_mb : out std_logic
    );
end entity vlc_enc;

architecture rtl of vlc_enc is
    signal pos     : natural range 0 to 63 := 0;
    signal blk     : natural range 0 to 5 := 0;
    signal col     : natural range 0 to G_COLS - 1 := 0;
    signal run     : natural range 0 to 63 := 0;
    signal pred_y, pred_cb, pred_cr : integer range -2048 to 2047 := 128;
    signal o_valid : std_logic := '0';
    signal libre   : std_logic;

    -- nombre de bits de |d| (taille DC)
    function taille(a : natural) return natural is
        variable t : natural := 0;
    begin
        for k in 0 to 11 loop
            if a >= 2 ** k then t := k + 1; end if;
        end loop;
        return t;
    end function;
begin
    libre   <= (not o_valid) or m_ready;
    s_ready <= libre and not rst;
    m_valid <= o_valid;

    -- E : vecteurs zigzag, 6 blocs par macrobloc → T : DC différentiel par
    --   composante, couples (run, niveau) en B.14 ou échappement 24 bits, fin
    --   de bloc → S : mots (code, longueur), m_fin sur le dernier mot du
    --   macrobloc
    process (clk)
        variable v      : integer range -32768 to 32767;
        variable pred   : integer range -2048 to 2047;
        variable diff   : integer range -4096 to 4096;
        variable sz     : natural range 0 to 12;
        variable dct    : dc_vlc_t;
        variable ac     : ac_vlc_t;
        variable code   : unsigned(31 downto 0);
        variable lg     : natural range 0 to 32;
        variable niv    : natural range 0 to 32767;
        variable nrun   : natural range 0 to 63;
        variable py, pcb, pcr : integer range -2048 to 2047;
    begin
        if rising_edge(clk) then
            if rst = '1' then
                pos <= 0; blk <= 0; col <= 0; run <= 0;
                pred_y <= 128; pred_cb <= 128; pred_cr <= 128;
                o_valid <= '0';
            else
                if libre = '1' then
                    o_valid <= '0';
                end if;
                if s_valid = '1' and libre = '1' then
                    v := to_integer(s_data);
                    code := (others => '0');
                    lg := 0;
                    nrun := run;
                    py := pred_y; pcb := pred_cb; pcr := pred_cr;
                    if pos = 0 then
                        -- nouvelle slice : prédicteurs remis à 128
                        if blk = 0 and col = 0 then
                            py := 128; pcb := 128; pcr := 128;
                        end if;
                        if blk < 4 then pred := py; elsif blk = 4 then pred := pcb; else pred := pcr; end if;
                        diff := v - pred;
                        if blk < 4 then py := v; elsif blk = 4 then pcb := v; else pcr := v; end if;
                        if diff < 0 then sz := taille(-diff); else sz := taille(diff); end if;
                        if blk < 4 then dct := DC_LUMA(sz); else dct := DC_CHROMA(sz); end if;
                        code := resize(unsigned(dct.code), 32);
                        lg := dct.lg;
                        if sz > 0 then
                            code := shift_left(code, sz);
                            if diff > 0 then
                                code := code or to_unsigned(diff, 32);
                            else
                                code := code or to_unsigned(diff + 2 ** sz - 1, 32);
                            end if;
                            lg := lg + sz;
                        end if;
                        nrun := 0;
                    else
                        if v = 0 then
                            if nrun < 63 then nrun := nrun + 1; end if;
                        else
                            if v < 0 then niv := -v; else niv := v; end if;
                            ac := ac_code(nrun, niv mod 2048);
                            if ac.trouve and niv < 2048 then
                                code := shift_left(resize(unsigned(ac.code), 32), 1);
                                if v < 0 then code(0) := '1'; end if;
                                lg := ac.lg + 1;
                            else
                                code := resize(unsigned(AC_ESCAPE), 32);
                                code := shift_left(code, 6) or to_unsigned(nrun, 32);
                                if v < 0 then
                                    code := shift_left(code, 12) or to_unsigned((4096 + v) mod 4096, 32);
                                else
                                    code := shift_left(code, 12) or to_unsigned(v mod 4096, 32);
                                end if;
                                lg := 24;
                            end if;
                            nrun := 0;
                        end if;
                    end if;
                    if pos = 63 then
                        code := shift_left(code, 2) or resize(unsigned(AC_EOB), 32);
                        lg := lg + 2;
                    end if;
                    pred_y <= py; pred_cb <= pcb; pred_cr <= pcr;
                    run <= nrun;
                    if lg > 0 then
                        m_code   <= std_logic_vector(code);
                        m_lg     <= to_unsigned(lg, 6);
                        m_fin_mb <= '1' when pos = 63 and blk = 5 else '0';
                        o_valid  <= '1';
                    end if;
                    if pos = 63 then
                        pos <= 0;
                        run <= 0;
                        if blk = 5 then
                            blk <= 0;
                            col <= 0 when col = G_COLS - 1 else col + 1;
                        else
                            blk <= blk + 1;
                        end if;
                    else
                        pos <= pos + 1;
                    end if;
                end if;
            end if;
        end if;
    end process;
end architecture rtl;

--------------------------------------------------------------------------------
-- bit_packer : mise bout à bout de mots binaires de longueur variable (0 à 32
--   bits, cadrés à droite) en octets, poids fort en tête, avec
--   alignement sur l'octet à la demande (bits de bourrage à 0)
--   Interface : entrée : s_code, s_lg, s_align (aligner après ce mot) ;
--               sortie : octets (valid / ready)
--   Principe : accumulateur de 64 bits ; un mot accepté si au plus 24 bits
--              attendent ; un octet sort par cycle dès que 8 bits sont prêts
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity bit_packer is
    port (
        clk     : in  std_logic;
        rst     : in  std_logic;
        s_valid : in  std_logic;
        s_ready : out std_logic;
        s_code  : in  std_logic_vector(31 downto 0);
        s_lg    : in  unsigned(5 downto 0);
        s_align : in  std_logic;
        m_valid : out std_logic;
        m_ready : in  std_logic;
        m_data  : out std_logic_vector(7 downto 0)
    );
end entity bit_packer;

architecture rtl of bit_packer is
    signal acc     : unsigned(63 downto 0) := (others => '0');
    signal nacc    : natural range 0 to 64 := 0;
    signal o_valid : std_logic := '0';
    signal libre   : std_logic;
    signal rdy     : std_logic;
begin
    libre   <= (not o_valid) or m_ready;
    rdy     <= '1' when rst = '0' and nacc <= 24 else '0';
    s_ready <= rdy;
    m_valid <= o_valid;

    -- E : mot, longueur, alignement → T : accumulation, un octet sort dès que 8
    --   bits sont prêts, bourrage à 0 sur alignement → S : octets
    process (clk)
        variable a  : unsigned(63 downto 0);
        variable n  : natural range 0 to 71;
        variable lg : natural range 0 to 32;
        variable k  : natural range 0 to 7;
        variable t  : unsigned(63 downto 0);
    begin
        if rising_edge(clk) then
            if rst = '1' then
                acc <= (others => '0'); nacc <= 0; o_valid <= '0';
            else
                a := acc; n := nacc;
                if libre = '1' then
                    o_valid <= '0';
                    if n >= 8 then
                        t := shift_right(a, n - 8);
                        m_data  <= std_logic_vector(t(7 downto 0));
                        o_valid <= '1';
                        n := n - 8;
                    end if;
                end if;
                if s_valid = '1' and rdy = '1' then
                    lg := to_integer(s_lg);
                    if lg > 0 then
                        a := shift_left(a, lg) or (resize(unsigned(s_code), 64) and (shift_left(to_unsigned(1, 64), lg) - 1));
                        n := n + lg;
                    end if;
                    if s_align = '1' then
                        k := (8 - n mod 8) mod 8;
                        a := shift_left(a, k);
                        n := n + k;
                    end if;
                end if;
                acc  <= a;
                nacc <= n;
            end if;
        end if;
    end process;
end architecture rtl;

--------------------------------------------------------------------------------
-- es_mux : assemblage du flux élémentaire MPEG-2 vidéo (images I) : en-têtes
--   de séquence, d'extension, de GOP et d'image, slices, bits VLC
--   des macroblocs ; référence bit à bit : JPEG2DVB étape 06
--   Interface : entrée : mots VLC du codeur (s_code, s_lg, s_fin_mb sur le
--               dernier mot de chaque macrobloc) ; slice_code : code d'échelle
--               de la slice à venir, slice_ok : code prêt (l'en-tête de slice
--               attend) ; sortie : octets du flux élémentaire
--   Principe : par image : [Sequence Header, Sequence Extension, GOP Header
--              si n mod 12 = 0] + Picture Header (temporal_reference = n mod 12,
--              vbv_delay 0xFFFF) + Picture Coding Extension, puis une slice par
--              rangée : 0x000001, rang + 1, code (5 bits), extra_bit 0, pour chaque
--              macrobloc « 1 » (adresse) « 1 » (intra) et ses bits VLC, alignement.
--              Après G_IMAGES images (0 = sans fin) : sequence_end_code.
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity es_mux is
    generic (
        G_LARG     : natural := 352;
        G_HAUT     : natural := 288;
        G_BIT_RATE : natural := 23040;        -- unités de 400 bit/s (débit TS)
        G_VBV      : natural := 112;          -- unités de 16 kbit
        G_GOP      : natural := 12;
        G_FPS      : natural := 25;
        G_IMAGES   : natural := 0
    );
    port (
        clk        : in  std_logic;
        rst        : in  std_logic;
        slice_code : in  unsigned(4 downto 0);
        slice_ok   : in  std_logic;
        s_valid    : in  std_logic;
        s_ready    : out std_logic;
        s_code     : in  std_logic_vector(31 downto 0);
        s_lg       : in  unsigned(5 downto 0);
        s_fin_mb   : in  std_logic;
        m_valid    : out std_logic;
        m_ready    : in  std_logic;
        m_data     : out std_logic_vector(7 downto 0)
    );
end entity es_mux;

architecture rtl of es_mux is
    constant COLS : natural := G_LARG / 16;
    constant ROWS : natural := G_HAUT / 16;

    -- slv : E : entier, largeur → S : vecteur non signé
    function slv(v, n : natural) return std_logic_vector is
    begin
        return std_logic_vector(to_unsigned(v, n));
    end function;

    type etat_t is (EN_TETE, SLICE1, SLICE2, MB_ENTETE, MB_DONNEES, SLICE_FIN, FIN_SEQ, ARRET);
    signal etat  : etat_t := EN_TETE;
    signal i     : natural range 0 to 12 := 0;
    signal image : natural range 0 to 2 ** 30 := 0;
    -- time_code du GOP : images, secondes, minutes, heures de l'image courante
    signal tc_im : natural range 0 to 63 := 0;
    signal tc_se, tc_mi : natural range 0 to 59 := 0;
    signal tc_h  : natural range 0 to 23 := 0;
    signal tr    : natural range 0 to 1023 := 0;          -- temporal_reference
    signal rang  : natural range 0 to 255 := 0;
    signal col   : natural range 0 to 255 := 0;

    signal p_valid, p_ready, p_align : std_logic;
    signal p_code : std_logic_vector(31 downto 0);
    signal p_lg   : unsigned(5 downto 0);
    signal w_code  : std_logic_vector(31 downto 0);
    signal w_lg    : natural range 0 to 32;
    signal w_align : std_logic;
begin
    packer : entity work.bit_packer
        port map (clk, rst, p_valid, p_ready, p_code, p_lg, p_align, m_valid, m_ready, m_data);

    -- mot présenté au packer selon l'état ; en-têtes de l'image : mots 0 à 7
    -- (séquence et GOP, au début de chaque GOP), 8 à 12 (image)
    process (all)
    begin
        w_code <= (others => '0'); w_lg <= 0; w_align <= '0';
        case etat is
            when EN_TETE =>
                case i is
                    when 0  => w_code <= x"000001B3"; w_lg <= 32;
                    when 1  => w_code <= slv(G_LARG, 12) & slv(G_HAUT, 12) & "0010" & "0011"; w_lg <= 32;       -- 4:3, 25 im/s
                    when 2  => w_code <= slv(G_BIT_RATE, 18) & '1' & slv(G_VBV, 10) & "000"; w_lg <= 32;        -- marqueur, VBV, matrices par défaut
                    when 3  => w_code <= x"000001B5"; w_lg <= 32;
                    when 4  => w_code <= "0001" & x"48" & '1' & "01" & "00" & "00" & x"000" & '1'; w_lg <= 32;    -- Main@Main, progressif, 4:2:0
                    when 5  => w_lg <= 16;                                                                      -- vbv ext, low_delay, frame_rate ext
                    when 6  => w_code <= x"000001B8"; w_lg <= 32;
                    when 7  => w_code(26 downto 0) <= '0' & slv(tc_h, 5) & slv(tc_mi, 6) & '1' & slv(tc_se, 6) & slv(tc_im, 6) & '1' & '0';
                               w_lg <= 27; w_align <= '1';                                                      -- GOP fermé
                    when 8  => w_code <= x"00000100"; w_lg <= 32;
                    when 9  => w_code(29 downto 0) <= slv(tr, 10) & "001" & x"FFFF" & '0'; w_lg <= 30; w_align <= '1';   -- image I
                    when 10 => w_code <= x"000001B5"; w_lg <= 32;
                    when 11 => w_code <= "1000" & x"FFFF" & "00" & "11" & "01000001"; w_lg <= 32;               -- f_code, dc 8 bits, trame, frame_pred_frame_dct, chroma_420_type
                    when others => w_code(1 downto 0) <= "10"; w_lg <= 2; w_align <= '1';                       -- progressive_frame, composite 0
                end case;
            when SLICE1    => w_code <= x"000001" & slv(rang + 1, 8); w_lg <= 32;
            when SLICE2    => w_code(5 downto 0) <= std_logic_vector(slice_code) & '0'; w_lg <= 6;
            when MB_ENTETE => w_code(1 downto 0) <= "11"; w_lg <= 2;
            when SLICE_FIN => w_align <= '1';
            when FIN_SEQ   => w_code <= x"000001B7"; w_lg <= 32;
            when others    => null;
        end case;
    end process;
    p_valid <= s_valid when etat = MB_DONNEES else '0' when etat = ARRET else slice_ok when etat = SLICE2 else '1';
    p_code  <= s_code when etat = MB_DONNEES else w_code;
    p_lg    <= s_lg when etat = MB_DONNEES else to_unsigned(w_lg, 6);
    p_align <= '0' when etat = MB_DONNEES else w_align;
    s_ready <= p_ready when etat = MB_DONNEES else '0';

    -- E : acceptation du packer, fins de macrobloc → T : en-têtes, slices,
    --   macroblocs ; rang, image, time_code, temporal_reference → S : état
    --   suivant
    process (clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                etat <= EN_TETE; i <= 0; image <= 0; rang <= 0; col <= 0;
                tc_im <= 0; tc_se <= 0; tc_mi <= 0; tc_h <= 0; tr <= 0;
            elsif etat = ARRET then
                null;
            elsif etat = MB_DONNEES then
                if s_valid = '1' and p_ready = '1' and s_fin_mb = '1' then
                    if col = COLS - 1 then
                        col  <= 0;
                        etat <= SLICE_FIN;
                    else
                        col  <= col + 1;
                        etat <= MB_ENTETE;
                    end if;
                end if;
            elsif p_ready = '1' and (etat /= SLICE2 or slice_ok = '1') then
                case etat is
                    when EN_TETE =>
                        if i = 12 then
                            etat <= SLICE1;
                            rang <= 0;
                        else
                            i <= i + 1;
                        end if;
                    when SLICE1    => etat <= SLICE2;
                    when SLICE2    => etat <= MB_ENTETE;
                    when MB_ENTETE => etat <= MB_DONNEES;
                    when SLICE_FIN =>
                        if rang = ROWS - 1 then
                            if G_IMAGES /= 0 and image = G_IMAGES - 1 then
                                etat <= FIN_SEQ;
                            else
                                image <= image + 1;
                                -- temporal_reference : rang dans le GOP
                                if tr = G_GOP - 1 then tr <= 0; i <= 0; else tr <= tr + 1; i <= 8; end if;
                                -- time_code de l'image suivante
                                if tc_im = G_FPS - 1 then
                                    tc_im <= 0;
                                    if tc_se = 59 then
                                        tc_se <= 0;
                                        if tc_mi = 59 then
                                            tc_mi <= 0;
                                            tc_h  <= 0 when tc_h = 23 else tc_h + 1;
                                        else
                                            tc_mi <= tc_mi + 1;
                                        end if;
                                    else
                                        tc_se <= tc_se + 1;
                                    end if;
                                else
                                    tc_im <= tc_im + 1;
                                end if;
                                etat  <= EN_TETE;
                            end if;
                        else
                            rang <= rang + 1;
                            etat <= SLICE1;
                        end if;
                    when FIN_SEQ => etat <= ARRET;
                    when others  => null;
                end case;
            end if;
        end if;
    end process;
end architecture rtl;

--------------------------------------------------------------------------------
-- ts_mux : mise en paquets PES (un par image) et multiplexage Transport
--   Stream à débit constant ; référence bit à bit : JPEG2DVB
--   étapes 07 et 08 (version 2.4, instants en entiers exacts)
--   Interface : entrée : octets du flux élémentaire (es_mux) ; sortie : paquets
--               TS de 188 octets (m_sop sur la synchro), un paquet par créneau
--   Principe : le flux élémentaire est rangé dans une mémoire tournante de
--              128 Ko ; les débuts d'image (sequence_header, ou picture_start
--              hors en-tête de séquence) et la fin de séquence sont repérés
--              par leurs codes de début. Le paquet k (créneau de 1 504 bits au
--              débit TS) est choisi dans l'ordre : PAT puis PMT toutes les
--              80 ms ; PCR toutes les 30 ms ; vidéo si l'image n est
--              disponible (instant ≥ (n+1)/25) ; sinon PCR seul ou paquet nul.
--              Instants exacts pour 10 MS/s, FEC 1/2 (R_ts = 9 215 686,27 bit/s) :
--              t_k ≥ a/b ⇔ 51·k ≥ a·12 500·25/b, soit 51k ≥ 25 000·m (PSI),
--              51k ≥ 9 375·m (PCR), 51k ≥ 12 500·(n+1) (images).
--              PCR(k) = round((188k + 10)·5 508 / 235), tenu en cumul exact :
--              +4 406 par créneau, +1 tous les 470/188 créneaux.
--              PES : 00 00 01 E0, longueur, 84 80 05, PTS = 3 600·(n+1) + 9 000.
--              Sans multiplieur : les écarts 51k − 25 000·m, 51k − 9 375·m et
--              51k − 12 500·(n+1) sont tenus en registres (+51 par créneau,
--              période retranchée à chaque émission) et comparés à zéro ; ils
--              restent bornés, sans rebouclage. L'écart des images est figé
--              au-delà de 2³⁸ (flux vidéo absent). PTS : +3 600 par image,
--              modulo 2³³.
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity ts_mux is
    generic (
        G_K     : natural := 51;            -- 51 k  ≥  …  (créneau k)
        G_PSI   : natural := 25000;         -- période PAT/PMT 80 ms
        G_PCR   : natural := 9375;          -- période PCR 30 ms
        G_IMG   : natural := 12500;         -- période image 40 ms
        G_GOP   : natural := 12;
        G_MCPC  : boolean := false;         -- deux programmes (canal 2 sur s2_*)
        G_AB1   : natural := 17;            -- mémoire du canal 1 : 2^G_AB1 octets
        G_AB2   : natural := 14             -- mémoire du canal 2 : 2^G_AB2 octets
    );
    port (
        clk      : in  std_logic;
        rst      : in  std_logic;
        s_valid  : in  std_logic;
        s_ready  : out std_logic;
        s_data   : in  std_logic_vector(7 downto 0);
        m_valid  : out std_logic;
        m_ready  : in  std_logic;
        m_data   : out std_logic_vector(7 downto 0);
        m_sop    : out std_logic;
        s2_valid : in  std_logic := '0';
        s2_ready : out std_logic;
        s2_data  : in  std_logic_vector(7 downto 0) := (others => '0')
    );
end entity ts_mux;

architecture rtl of ts_mux is
    subtype octet_t is std_logic_vector(7 downto 0);
    type octets_t is array (natural range <>) of octet_t;

    -- CRC-32 MPEG-2 (polynôme 0x04C11DB7, registre initial 0xFFFFFFFF)
    function crc32(d : octets_t) return std_logic_vector is
        variable c : std_logic_vector(31 downto 0) := (others => '1');
        variable f : std_logic;
    begin
        for i in d'range loop
            for b in 7 downto 0 loop
                f := c(31) xor d(i)(b);
                c := c(30 downto 0) & '0';
                if f = '1' then c := c xor x"04C11DB7"; end if;
            end loop;
        end loop;
        return c;
    end function;
    -- paquet_psi : E : en-tête TS (avec pointer_field), section → T : section
    --   suivie de son CRC-32, bourrage 0xFF → S : paquet de 188 octets
    function paquet_psi(entete : octets_t; section : octets_t) return octets_t is
        variable p : octets_t(0 to 187) := (others => x"FF");
        variable c : std_logic_vector(31 downto 0) := crc32(section);
        variable j : natural := 0;
    begin
        for i in entete'range loop p(j) := entete(i); j := j + 1; end loop;
        for i in section'range loop p(j) := section(i); j := j + 1; end loop;
        p(j) := c(31 downto 24); p(j + 1) := c(23 downto 16); p(j + 2) := c(15 downto 8); p(j + 3) := c(7 downto 0);
        return p;
    end function;
    -- PAT : programme 1 → PMT PID 0x0100 (et programme 2 → PMT PID 0x0200 en
    --   MCPC) ; PMT 1 : vidéo MPEG-2 PID 0x0101, PCR sur 0x0101 ; PMT 2 : vidéo
    --   MPEG-2 PID 0x0201, PCR sur 0x0101
    -- pat : E : MCPC ou non → S : paquet PAT à un ou deux programmes
    function pat(mcpc : boolean) return octets_t is
    begin
        if mcpc then
            return paquet_psi((x"47", x"40", x"00", x"10", x"00"),
                (x"00", x"B0", x"11", x"00", x"01", x"C1", x"00", x"00", x"00", x"01", x"E1", x"00", x"00", x"02", x"E2", x"00"));
        end if;
        return paquet_psi((x"47", x"40", x"00", x"10", x"00"),
            (x"00", x"B0", x"0D", x"00", x"01", x"C1", x"00", x"00", x"00", x"01", x"E1", x"00"));
    end function;
    constant PAT_P : octets_t(0 to 187) := pat(G_MCPC);
    constant PMT1  : octets_t(0 to 187) := paquet_psi((x"47", x"41", x"00", x"10", x"00"),
        (x"02", x"B0", x"12", x"00", x"01", x"C1", x"00", x"00", x"E1", x"01", x"F0", x"00", x"02", x"E1", x"01", x"F0", x"00"));
    constant PMT2  : octets_t(0 to 187) := paquet_psi((x"47", x"42", x"00", x"10", x"00"),
        (x"02", x"B0", x"12", x"00", x"02", x"C1", x"00", x"00", x"E1", x"01", x"F0", x"00", x"02", x"E2", x"01", x"F0", x"00"));

    -- mémoires des flux élémentaires : canal 1 (indice 0), canal 2 (indice 1)
    -- ab_max : E : deux largeurs d'adresse → S : la plus grande
    function ab_max(a, b : natural) return natural is
    begin
        if a > b then return a; end if;
        return b;
    end function;
    constant ABM : natural := ab_max(G_AB1, G_AB2);
    subtype adr_t is unsigned(ABM - 1 downto 0);
    -- masque : E : canal → S : masque d'adresse de sa mémoire
    function masque(c : natural) return adr_t is
        variable m : adr_t := (others => '0');
    begin
        if c = 0 then
            m(G_AB1 - 1 downto 0) := (others => '1');
        else
            m(G_AB2 - 1 downto 0) := (others => '1');
        end if;
        return m;
    end function;
    type ram1_t is array (0 to 2 ** G_AB1 - 1) of octet_t;
    type ram2_t is array (0 to 2 ** G_AB2 - 1) of octet_t;
    signal ram1   : ram1_t;
    signal ram2   : ram2_t;
    type adr2_t  is array (0 to 1) of adr_t;
    type adr28_t is array (0 to 1, 0 to 7) of adr_t;
    type u32_2_t is array (0 to 1) of unsigned(31 downto 0);
    type der3_2_t is array (0 to 1) of std_logic_vector(23 downto 0);
    signal sv     : std_logic_vector(0 to 1);
    signal sd     : octets_t(0 to 1);
    signal ecr    : adr2_t := (others => (others => '0'));
    signal der3   : der3_2_t := (others => (others => '1'));    -- 3 derniers octets
    signal en_tete_seq : std_logic_vector(0 to 1) := "00";
    signal au_deb, au_fin : adr28_t := (others => (others => (others => '0')));
    signal nb_deb, nb_cpl : u32_2_t := (others => (others => '0'));   -- images commencées, complètes

    -- ordonnancement
    type type_t is (T_PAT, T_PMT, T_PCR, T_NUL, T_VID);
    signal typ      : type_t := T_NUL;
    signal can      : natural range 0 to 1 := 0;                              -- canal du paquet vidéo en cours
    signal i_pmt    : natural range 0 to 1 := 0;                              -- PMT en cours
    signal d_psi, d_pcr : signed(31 downto 0) := (others => '0');             -- G_K·k − G_PSI·m, G_K·k − G_PCR·m
    type d_img_2_t is array (0 to 1) of signed(39 downto 0);
    type pts_2_t is array (0 to 1) of unsigned(32 downto 0);
    signal d_img    : d_img_2_t := (others => to_signed(-G_IMG, 40));         -- G_K·k − G_IMG·(n + 1)
    signal pts_r    : pts_2_t := (others => to_unsigned(12600, 33));          -- 3 600·(n + 1) + 9 000
    signal pmt_du   : natural range 0 to 2 := 0;                              -- PMT restant à émettre
    signal pcr_base : unsigned(32 downto 0) := (others => '0');
    signal pcr_ext  : unsigned(8 downto 0) := to_unsigned(234, 9);
    signal pcr_r    : natural range 0 to 469 := 415;
    signal p_base   : unsigned(32 downto 0);
    signal p_ext    : unsigned(8 downto 0);
    type cc_2_t is array (0 to 1) of unsigned(3 downto 0);
    signal cc_pat   : unsigned(3 downto 0) := (others => '0');
    signal cc_pmt, cc_vid : cc_2_t := (others => (others => '0'));
    signal n_vid    : u32_2_t := (others => (others => '0'));
    type gop_2_t is array (0 to 1) of natural range 0 to 255;
    signal n_gop    : gop_2_t := (others => 0);
    type lg_2_t is array (0 to 1) of natural range 0 to 2 ** ABM + 16;
    signal pes_ptr  : lg_2_t := (others => 0);                 -- octet suivant du PES en cours
    signal pes_lg   : lg_2_t := (others => 0);
    signal debut, avec_pcr, rai : std_logic := '0';
    signal afl      : natural range 0 to 184 := 0;
    signal actif    : std_logic := '0';
    signal pos      : natural range 0 to 187 := 0;
    -- pipeline de sortie
    signal a_valid, a_ram, a_sop : std_logic := '0';
    signal a_can    : natural range 0 to 1 := 0;
    signal a_oct, ram_q1, ram_q2 : octet_t := (others => '0');
    signal o_valid  : std_logic := '0';
    signal libre    : std_logic;
    signal place    : std_logic_vector(0 to 1);
begin
    libre    <= (not o_valid) or m_ready;
    m_valid  <= o_valid;
    s_ready  <= place(0) and not rst;
    s2_ready <= place(1) and not rst when G_MCPC else '0';
    sv(0) <= s_valid;  sd(0) <= s_data;
    sv(1) <= s2_valid when G_MCPC else '0';
    sd(1) <= s2_data;

    -- place libre : on ne recouvre pas l'image la plus ancienne non encore envoyée
    process (all)
        variable base : adr_t;
    begin
        for c in 0 to 1 loop
            if n_vid(c) < nb_deb(c) then
                base := au_deb(c, to_integer(n_vid(c)(2 downto 0)));
            else
                base := ecr(c);
            end if;
            if ((ecr(c) - base) and masque(c)) < masque(c) - 15 and nb_deb(c) - n_vid(c) < 7 then place(c) <= '1'; else place(c) <= '0'; end if;
        end loop;
    end process;

    -- E : octets ES des deux canaux, créneaux → T : mémoires tournantes,
    --   repérage des débuts d'image, choix PAT/PMT, PCR, vidéo du canal 1, du
    --   canal 2 ou nul par créneau → S : paquets TS
    process (clk)
        variable w      : adr_t;
        variable fire_psi, fire_pcr : boolean;
        variable pret   : boolean;
        variable v      : natural range 0 to 1;
        variable af, maxcu, cu, reste : natural range 0 to 2 ** ABM + 16;
        variable oct    : octet_t;
        variable lit    : boolean;
        variable adr    : adr_t;
        variable pts    : unsigned(32 downto 0);
        variable lp     : natural range 0 to 2 ** ABM + 16;
        variable carry  : natural range 0 to 1;
        variable e2     : natural range 0 to 1023;
        variable ni     : natural range 0 to 7;
    begin
        if rising_edge(clk) then
            if rst = '1' then
                ecr <= (others => (others => '0')); der3 <= (others => (others => '1')); en_tete_seq <= "00";
                nb_deb <= (others => (others => '0')); nb_cpl <= (others => (others => '0'));
                d_psi <= (others => '0'); d_pcr <= (others => '0'); d_img <= (others => to_signed(-G_IMG, 40));
                pts_r <= (others => to_unsigned(12600, 33)); pmt_du <= 0;
                pcr_base <= (others => '0'); pcr_ext <= to_unsigned(234, 9); pcr_r <= 415;
                cc_pat <= (others => '0'); cc_pmt <= (others => (others => '0')); cc_vid <= (others => (others => '0'));
                n_vid <= (others => (others => '0')); n_gop <= (others => 0); pes_ptr <= (others => 0); actif <= '0'; pos <= 0;
                a_valid <= '0'; o_valid <= '0';
            else
                ----------------------------------------------------------------
                -- écriture des flux élémentaires, repérage des images
                ----------------------------------------------------------------
                for c in 0 to 1 loop
                    if sv(c) = '1' and place(c) = '1' then
                        w := ecr(c);
                        if c = 0 then
                            ram1(to_integer(w(G_AB1 - 1 downto 0))) <= sd(0);
                        else
                            ram2(to_integer(w(G_AB2 - 1 downto 0))) <= sd(1);
                        end if;
                        ecr(c)  <= (w + 1) and masque(c);
                        der3(c) <= der3(c)(15 downto 0) & sd(c);
                        if der3(c) = x"000001" then
                            if sd(c) = x"B3" or (sd(c) = x"00" and en_tete_seq(c) = '0') then
                                -- début d'image à w − 3 ; l'image précédente est complète
                                if nb_deb(c) > 0 then
                                    au_fin(c, to_integer(nb_deb(c)(2 downto 0) - 1)) <= (w - 3) and masque(c);
                                    nb_cpl(c) <= nb_cpl(c) + 1;
                                end if;
                                au_deb(c, to_integer(nb_deb(c)(2 downto 0))) <= (w - 3) and masque(c);
                                nb_deb(c) <= nb_deb(c) + 1;
                                if sd(c) = x"B3" then en_tete_seq(c) <= '1'; else en_tete_seq(c) <= '0'; end if;
                            elsif sd(c) = x"00" then
                                en_tete_seq(c) <= '0';
                            elsif sd(c) = x"B7" then
                                -- fin de séquence : la dernière image se termine après ce code
                                au_fin(c, to_integer(nb_deb(c)(2 downto 0) - 1)) <= (w + 1) and masque(c);
                                nb_cpl(c) <= nb_cpl(c) + 1;
                            end if;
                        end if;
                    end if;
                end loop;

                ----------------------------------------------------------------
                -- sortie : étage B (octet final), étage A (choix et lecture)
                ----------------------------------------------------------------
                if libre = '1' then
                    o_valid <= a_valid;
                    m_sop   <= a_sop;
                    if a_ram = '0' then
                        m_data <= a_oct;
                    elsif a_can = 0 then
                        m_data <= ram_q1;
                    else
                        m_data <= ram_q2;
                    end if;

                    if actif = '0' then
                        -- choix du paquet du créneau k
                        a_valid  <= '0';
                        fire_psi := d_psi >= 0;
                        fire_pcr := d_pcr >= 0;
                        -- canal 1 d'abord ; canal 2 seulement hors créneau d'un PCR dû
                        pret := false; v := 0;
                        if n_vid(0) < nb_cpl(0) and d_img(0) >= 0 then
                            pret := true;
                        elsif G_MCPC and n_vid(1) < nb_cpl(1) and d_img(1) >= 0 and not fire_pcr then
                            pret := true; v := 1;
                        end if;
                        d_psi <= d_psi + G_K;
                        d_pcr <= d_pcr + G_K;
                        for c in 0 to 1 loop
                            if d_img(c)(38) = '0' or d_img(c)(39) = '1' then
                                d_img(c) <= d_img(c) + G_K;
                            end if;
                        end loop;
                        avec_pcr <= '0';
                        if fire_psi then
                            typ <= T_PAT; d_psi <= d_psi + G_K - G_PSI;
                            if G_MCPC then pmt_du <= 2; else pmt_du <= 1; end if;
                        elsif pmt_du /= 0 then
                            typ <= T_PMT; pmt_du <= pmt_du - 1;
                            if G_MCPC and pmt_du = 1 then i_pmt <= 1; else i_pmt <= 0; end if;
                        else
                            if fire_pcr then d_pcr <= d_pcr + G_K - G_PCR; avec_pcr <= '1'; end if;
                            if not pret then
                                if fire_pcr then typ <= T_PCR; else typ <= T_NUL; end if;
                            else
                                typ <= T_VID;
                                can <= v;
                                ni := to_integer(n_vid(v)(2 downto 0));
                                if pes_ptr(v) = 0 then
                                    lp := to_integer((au_fin(v, ni) - au_deb(v, ni)) and masque(v)) + 14;
                                    pes_lg(v) <= lp;
                                else
                                    lp := pes_lg(v);
                                end if;
                                if pes_ptr(v) = 0 then debut <= '1'; else debut <= '0'; end if;
                                if pes_ptr(v) = 0 and n_gop(v) = 0 then rai <= '1'; else rai <= '0'; end if;
                                if fire_pcr then af := 8; elsif pes_ptr(v) = 0 and n_gop(v) = 0 then af := 2; else af := 0; end if;
                                maxcu := 184 - af;
                                reste := lp - pes_ptr(v);
                                if reste < maxcu then cu := reste; else cu := maxcu; end if;
                                afl <= af + maxcu - cu;
                            end if;
                        end if;
                        p_base <= pcr_base; p_ext <= pcr_ext;
                        -- PCR du créneau suivant
                        e2 := pcr_r + 188;
                        if e2 >= 470 then carry := 1; e2 := e2 - 470; else carry := 0; end if;
                        pcr_r <= e2;
                        if to_integer(pcr_ext) + 206 + carry >= 300 then
                            pcr_ext  <= to_unsigned(to_integer(pcr_ext) + 206 + carry - 300, 9);
                            pcr_base <= pcr_base + 15;
                        else
                            pcr_ext  <= to_unsigned(to_integer(pcr_ext) + 206 + carry, 9);
                            pcr_base <= pcr_base + 14;
                        end if;
                        actif <= '1';
                        pos   <= 0;
                    else
                        -- octet pos du paquet choisi
                        oct := x"FF"; lit := false; adr := (others => '0');
                        case typ is
                            when T_PAT =>
                                oct := PAT_P(pos);
                                if pos = 3 then oct := x"1" & std_logic_vector(cc_pat); end if;
                            when T_PMT =>
                                if i_pmt = 0 then oct := PMT1(pos); else oct := PMT2(pos); end if;
                                if pos = 3 then oct := x"1" & std_logic_vector(cc_pmt(i_pmt)); end if;
                            when T_NUL =>
                                case pos is
                                    when 0 => oct := x"47"; when 1 => oct := x"1F"; when 2 => oct := x"FF"; when 3 => oct := x"10";
                                    when others => null;
                                end case;
                            when T_PCR | T_VID =>
                                -- PID 0x0101 (canal 1, PCR seul) ou 0x0201 (canal 2)
                                case pos is
                                    when 0 => oct := x"47";
                                    when 1 =>
                                        if typ = T_VID and can = 1 then oct := x"02"; else oct := x"01"; end if;
                                        if typ = T_VID and debut = '1' then oct(6) := '1'; end if;
                                    when 2 => oct := x"01";
                                    when 3 =>
                                        if typ = T_PCR then oct := x"2" & std_logic_vector(cc_vid(0));
                                        elsif afl > 0 then oct := x"3" & std_logic_vector(cc_vid(can));
                                        else oct := x"1" & std_logic_vector(cc_vid(can)); end if;
                                    when others => null;
                                end case;
                                if typ = T_PCR then
                                    if pos = 4 then oct := std_logic_vector(to_unsigned(183, 8)); end if;
                                    if pos = 5 then oct := x"10"; end if;
                                end if;
                                if (typ = T_PCR or (typ = T_VID and avec_pcr = '1')) and pos >= 6 and pos <= 11 then
                                    case pos is
                                        when 6  => oct := std_logic_vector(p_base(32 downto 25));
                                        when 7  => oct := std_logic_vector(p_base(24 downto 17));
                                        when 8  => oct := std_logic_vector(p_base(16 downto 9));
                                        when 9  => oct := std_logic_vector(p_base(8 downto 1));
                                        when 10 => oct := p_base(0) & "111111" & p_ext(8);
                                        when others => oct := std_logic_vector(p_ext(7 downto 0));
                                    end case;
                                end if;
                                if typ = T_VID and pos >= 4 then
                                    if afl > 0 and pos = 4 then
                                        oct := std_logic_vector(to_unsigned(afl - 1, 8));
                                    elsif afl > 1 and pos = 5 then
                                        oct := '0' & rai & '0' & avec_pcr & "0000";      -- random_access, PCR_flag
                                    elsif pos >= 4 + afl then
                                        -- charge utile : en-tête PES puis flux élémentaire
                                        ni := to_integer(n_vid(can)(2 downto 0));
                                        pts := pts_r(can);
                                        case pes_ptr(can) is
                                            when 0 | 1 => oct := x"00";
                                            when 2  => oct := x"01";
                                            when 3  => oct := x"E0";
                                            when 4  => if pes_lg(can) - 6 > 65535 then oct := x"00"; else oct := std_logic_vector(to_unsigned((pes_lg(can) - 6) / 256, 8)); end if;
                                            when 5  => if pes_lg(can) - 6 > 65535 then oct := x"00"; else oct := std_logic_vector(to_unsigned((pes_lg(can) - 6) mod 256, 8)); end if;
                                            when 6  => oct := x"84";
                                            when 7  => oct := x"80";
                                            when 8  => oct := x"05";
                                            when 9  => oct := "0010" & std_logic_vector(pts(32 downto 30)) & '1';
                                            when 10 => oct := std_logic_vector(pts(29 downto 22));
                                            when 11 => oct := std_logic_vector(pts(21 downto 15)) & '1';
                                            when 12 => oct := std_logic_vector(pts(14 downto 7));
                                            when 13 => oct := std_logic_vector(pts(6 downto 0)) & '1';
                                            when others =>
                                                lit := true;
                                                adr := (au_deb(can, ni) + to_unsigned(pes_ptr(can) - 14, ABM)) and masque(can);
                                        end case;
                                        if pes_ptr(can) = pes_lg(can) - 1 then
                                            pes_ptr(can) <= 0;
                                            n_vid(can)   <= n_vid(can) + 1;
                                            d_img(can)   <= d_img(can) - G_IMG;
                                            pts_r(can)   <= pts_r(can) + 3600;
                                            if n_gop(can) = G_GOP - 1 then n_gop(can) <= 0; else n_gop(can) <= n_gop(can) + 1; end if;
                                        else
                                            pes_ptr(can) <= pes_ptr(can) + 1;
                                        end if;
                                    end if;
                                end if;
                        end case;
                        a_oct   <= oct;
                        if lit then a_ram <= '1'; else a_ram <= '0'; end if;
                        a_can   <= can;
                        if pos = 0 then a_sop <= '1'; else a_sop <= '0'; end if;
                        a_valid <= '1';
                        ram_q1  <= ram1(to_integer(adr(G_AB1 - 1 downto 0)));
                        ram_q2  <= ram2(to_integer(adr(G_AB2 - 1 downto 0)));
                        if pos = 187 then
                            actif <= '0';
                            case typ is
                                when T_PAT => cc_pat <= cc_pat + 1;
                                when T_PMT => cc_pmt(i_pmt) <= cc_pmt(i_pmt) + 1;
                                when T_VID => cc_vid(can) <= cc_vid(can) + 1;
                                when others => null;
                            end case;
                        else
                            pos <= pos + 1;
                        end if;
                    end if;
                end if;
            end if;
        end if;
    end process;
end architecture rtl;

--------------------------------------------------------------------------------
-- csa_enc : embrouillage DVB-CSA des paquets TS d'un PID, clé fixe (BISS-1) ;
--   référence bit à bit : fpga_test/csa.js (ts_csa.bin)
--   Interface : entrée et sortie : paquets TS de 188 octets (valid / ready,
--               s_sop et m_sop sur la synchro) ; en : embrouillage actif ;
--               cw : mot de contrôle de 8 octets, octet 0 en bits 7..0 (stable
--               pendant le fonctionnement)
--   Paramètre : G_PID : PID embrouillé (vidéo 0x0101)
--   Principe : le paquet est rangé en mémoire (188 octets). Un paquet du PID,
--              avec charge utile, non déjà embrouillé et d'au moins 8 octets de
--              charge est chiffré derrière son en-tête (4 octets, plus le champ
--              d'adaptation), transport_scrambling_control passe à « 10 » ;
--              les autres passent inchangés.
--              Blocs : du dernier bloc entier de 8 octets au premier,
--              bloc ← E(bloc ⊕ bloc suivant chiffré), 56 tours d'un cycle ; la
--              clé des tours sort d'un registre de 64 bits : K0 (six
--              permutations du mot de contrôle, simple câblage), un octet par
--              tour, permutation inverse tous les 8 tours.
--              Sortie : les octets sont relus dans l'ordre ; le premier bloc
--              initialise le chiffrement de flux (4 tours par octet), les
--              octets suivants reçoivent 8 bits de flux (4 tours) ; ils
--              partent dans une file de 256 octets lue par l'aval.
--   Débit : environ 3 400 cycles par paquet embrouillé (créneau TS le plus
--           court : 7 461 cycles à 10 MS/s, FEC 7/8) ; le paquet suivant se
--           charge dès que le précédent est entièrement dans la file.
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.dvbs_pkg.all;
use work.csa_tab_pkg.all;

entity csa_enc is
    generic (
        G_PID : natural := 16#0101#
    );
    port (
        clk     : in  std_logic;
        rst     : in  std_logic;
        en      : in  std_logic;
        cw      : in  std_logic_vector(63 downto 0);
        s_valid : in  std_logic;
        s_ready : out std_logic;
        s_data  : in  octet_t;
        s_sop   : in  std_logic;
        m_valid : out std_logic;
        m_ready : in  std_logic;
        m_data  : out octet_t;
        m_sop   : out std_logic
    );
end entity csa_enc;

architecture rtl of csa_enc is
    subtype mot_t is std_logic_vector(63 downto 0);
    subtype reg_t is std_logic_vector(39 downto 0);
    subtype q_t   is std_logic_vector(3 downto 0);
    -- état du chiffrement de flux
    type flux_t is record
        a, b             : reg_t;
        x, y, z, d, e, f : q_t;
        p, q, c          : std_logic;
    end record;

    -- cle_perm : E : clé → S : clé permutée (le bit i va en CSA_KPERM(i))
    function cle_perm(k : mot_t) return mot_t is
        variable n : mot_t;
    begin
        for i in 0 to 63 loop
            n(CSA_KPERM(i)) := k(i);
        end loop;
        return n;
    end function;
    -- cle_inv : E : clé → S : permutation inverse
    function cle_inv(k : mot_t) return mot_t is
        variable n : mot_t;
    begin
        for i in 0 to 63 loop
            n(i) := k(CSA_KPERM(i));
        end loop;
        return n;
    end function;
    -- cle_0 : E : mot de contrôle → T : six permutations → S : clé des tours 0 à 7
    function cle_0(k : mot_t) return mot_t is
        variable n : mot_t := k;
    begin
        for i in 1 to 6 loop
            n := cle_perm(n);
        end loop;
        return n;
    end function;
    -- perm8 : E : sortie de la boîte S → S : ses bits permutés
    function perm8(s : octet_t) return octet_t is
        variable r : octet_t;
    begin
        for i in 0 to 7 loop
            r(CSA_BPERM(i)) := s(i);
        end loop;
        return r;
    end function;
    -- flux_init : E : mot de contrôle → S : état initial (A, B chargés, quartets
    --   de chaque octet échangés ; le reste à zéro)
    function flux_init(k : mot_t) return flux_t is
        variable s : flux_t;
    begin
        s.a := (others => '0'); s.b := (others => '0');
        for j in 0 to 3 loop
            for b in 0 to 7 loop
                s.a(8 * j + b) := k(8 * j + (b + 4) mod 8);
                s.b(8 * j + b) := k(32 + 8 * j + (b + 4) mod 8);
            end loop;
        end loop;
        s.x := "0000"; s.y := "0000"; s.z := "0000"; s.d := "0000"; s.e := "0000"; s.f := "0000";
        s.p := '0'; s.q := '0'; s.c := '0';
        return s;
    end function;
    -- boite : E : table de 32 bits, indice de 5 bits → T : sélection par
    --   comparaisons (logique, pas de mémoire) → S : bit de la table
    function boite(tab : std_logic_vector(0 to 31); v : std_logic_vector(4 downto 0)) return std_logic is
        variable r : std_logic := '0';
    begin
        for i in 0 to 31 loop
            if unsigned(v) = i and tab(i) = '1' then
                r := '1';
            end if;
        end loop;
        return r;
    end function;
    -- flux_tour : E : état, initialisation, quartets d'entrée pour A et B → T :
    --   un tour (décalages, D, E, F, retenue, boîtes) → S : état suivant
    function flux_tour(s : flux_t; init : std_logic; iva, ivb : q_t) return flux_t is
        variable r      : flux_t;
        variable na, tb : q_t;
        variable bs     : q_t;
        variable som    : unsigned(4 downto 0);
        variable v      : std_logic_vector(4 downto 0);
        variable res    : std_logic_vector(13 downto 0);
    begin
        na := s.a(39 downto 36) xor s.x;
        tb := s.b(27 downto 24) xor s.b(39 downto 36) xor s.y;
        if init = '1' then
            na := na xor s.d xor iva;
            tb := tb xor ivb;
        end if;
        if s.p = '1' then
            tb := tb(2 downto 0) & tb(3);
        end if;
        r.a := s.a(35 downto 0) & na;
        r.b := s.b(35 downto 0) & tb;
        for o in 0 to 3 loop
            bs(o) := r.b(CSA_BSEL(o, 0)) xor r.b(CSA_BSEL(o, 1)) xor r.b(CSA_BSEL(o, 2)) xor r.b(CSA_BSEL(o, 3));
        end loop;
        r.d := s.e xor s.z xor bs;
        r.e := s.f;
        if s.q = '1' then
            som := resize(unsigned(s.z), 5) + resize(unsigned(s.e), 5) + unsigned'("0000" & s.c);
            r.f := std_logic_vector(som(3 downto 0));
            r.c := som(4);
        else
            r.f := s.e;
            r.c := s.c;
        end if;
        for k in 0 to 6 loop
            for m in 0 to 4 loop
                v(m) := r.a(CSA_F_IN(k, m));
            end loop;
            res(CSA_F_OUT(k, 0)) := boite(CSA_F_T0(k), v);
            res(CSA_F_OUT(k, 1)) := boite(CSA_F_T1(k), v);
        end loop;
        r.x := res(3 downto 0); r.y := res(7 downto 4); r.z := res(11 downto 8);
        r.p := res(12); r.q := res(13);
        return r;
    end function;

    -- mémoire du paquet et file de sortie
    type ram_t is array (0 to 255) of octet_t;
    signal tamp    : ram_t;
    signal adr     : unsigned(7 downto 0) := (others => '0');
    signal lu      : octet_t;
    signal fifo    : ram_t;
    signal f_ecr, f_lec : unsigned(8 downto 0) := (others => '0');
    signal f_pleine, f_vide : std_logic;
    signal cs      : natural range 0 to 187 := 0;          -- rang de l'octet en sortie

    type etat_t is (CHARGE, PREP, B_LIT, B_TOURS, B_ECRIT, S_ADR, S_ATT, S_OCT, S_TOURS, S_POUSSE);
    signal etat    : etat_t := CHARGE;
    signal wp      : natural range 0 to 187 := 0;
    signal h1, h2, h3, h4 : octet_t := (others => '0');
    signal brouille : std_logic := '0';
    signal hdr     : natural range 0 to 188 := 188;        -- premier octet de la charge
    signal bi      : natural range 0 to 22 := 0;           -- bloc en cours
    signal base    : natural range 0 to 187 := 0;          -- son premier octet
    signal cnt     : natural range 0 to 63 := 0;
    signal w, chaine : mot_t := (others => '0');           -- bloc en cours, bloc suivant chiffré (octet 0 en bits 7..0)
    signal kreg    : mot_t := (others => '0');
    signal pos     : natural range 0 to 187 := 0;
    signal oct, ks, sor : octet_t := (others => '0');      -- octet relu, flux, octet à sortir
    signal rc      : natural range 0 to 3 := 0;
    signal fl      : flux_t;
    signal o_valid : std_logic := '0';
    signal libre   : std_logic;
begin
    libre    <= (not o_valid) or m_ready;
    m_valid  <= o_valid;
    s_ready  <= '1' when etat = CHARGE and rst = '0' else '0';
    f_vide   <= '1' when f_ecr = f_lec else '0';
    f_pleine <= '1' when f_ecr(7 downto 0) = f_lec(7 downto 0) and f_ecr(8) /= f_lec(8) else '0';

    -- lecture synchrone de la mémoire du paquet
    process (clk)
    begin
        if rising_edge(clk) then
            lu <= tamp(to_integer(adr));
        end if;
    end process;

    -- E : paquets TS, mot de contrôle → T : rangement, chiffrement par blocs
    --   depuis la fin, relecture avec chiffrement de flux → S : octets dans la
    --   file, puis vers l'aval
    process (clk)
        variable ecr    : boolean;
        variable e_adr  : natural range 0 to 255;
        variable e_oct  : octet_t;
        variable pousse : boolean;
        variable p      : natural range 0 to 187;
        variable hd     : natural range 0 to 511;
        variable nb     : natural range 0 to 23;
        variable kb, s, o, kn : octet_t;
        variable v0, v1, v2, v3, v4, v5, v6, v7 : octet_t;
        variable wr     : mot_t;
        variable kr     : mot_t;
        variable nf     : flux_t;
    begin
        if rising_edge(clk) then
            ecr := false; e_adr := 0; e_oct := (others => '0');
            pousse := false;
            if rst = '1' then
                etat <= CHARGE; wp <= 0; brouille <= '0'; cnt <= 0; pos <= 0; rc <= 0;
                f_ecr <= (others => '0');
            else
                case etat is
                    -- rangement du paquet, en-tête retenu
                    when CHARGE =>
                        if s_valid = '1' then
                            if s_sop = '1' then p := 0; else p := wp; end if;
                            ecr := true; e_adr := p; e_oct := s_data;
                            case p is
                                when 1 => h1 <= s_data;
                                when 2 => h2 <= s_data;
                                when 3 => h3 <= s_data;
                                when 4 => h4 <= s_data;
                                when others => null;
                            end case;
                            if p = 187 then
                                wp   <= 0;
                                etat <= PREP;
                            else
                                wp <= p + 1;
                            end if;
                        end if;
                    -- règle de l'en-tête : paquet à embrouiller ou non
                    when PREP =>
                        hd := 4;
                        if h3(5) = '1' then
                            hd := 5 + to_integer(unsigned(h4));
                        end if;
                        if en = '1' and unsigned(std_logic_vector'(h1(4 downto 0) & h2)) = G_PID and h3(4) = '1' and h3(7 downto 6) = "00" and hd <= 180 then
                            nb := (188 - hd) / 8;
                            brouille <= '1';
                            hdr    <= hd;
                            bi     <= nb - 1;
                            base   <= hd + 8 * (nb - 1);
                            chaine <= (others => '0');
                            fl     <= flux_init(cw);
                            cnt    <= 0;
                            etat   <= B_LIT;
                        else
                            brouille <= '0';
                            hdr  <= 188;
                            pos  <= 0;
                            etat <= S_ADR;
                        end if;
                    -- bloc lu (adresse au cycle c, octet deux cycles après), ⊕ bloc suivant chiffré
                    when B_LIT =>
                        if cnt <= 7 then
                            adr <= to_unsigned(base + cnt, 8);
                        end if;
                        if cnt >= 2 then
                            -- octet cnt − 2 : entre par le haut, les deux registres tournent d'un octet
                            w      <= (lu xor chaine(7 downto 0)) & w(63 downto 8);
                            chaine <= chaine(7 downto 0) & chaine(63 downto 8);
                        end if;
                        if cnt = 9 then
                            cnt  <= 0;
                            kreg <= cle_0(cw);
                            etat <= B_TOURS;
                        else
                            cnt <= cnt + 1;
                        end if;
                    -- 56 tours ; clé : octet de poids faible de kreg, ⊕ rang du groupe de 8 tours
                    when B_TOURS =>
                        kb := kreg(7 downto 0) xor std_logic_vector(to_unsigned(cnt / 8, 8));
                        v0 := w(7 downto 0);   v1 := w(15 downto 8);  v2 := w(23 downto 16); v3 := w(31 downto 24);
                        v4 := w(39 downto 32); v5 := w(47 downto 40); v6 := w(55 downto 48); v7 := w(63 downto 56);
                        s  := CSA_SBOX(to_integer(unsigned(kb xor v7)));
                        -- W7 … W0 ← W0 ⊕ S, W7, W6 ⊕ perm(S), W5, W4 ⊕ W0, W3 ⊕ W0, W2 ⊕ W0, W1
                        w  <= (v0 xor s) & v7 & (v6 xor perm8(s)) & v5 & (v4 xor v0) & (v3 xor v0) & (v2 xor v0) & v1;
                        kr := kreg(7 downto 0) & kreg(63 downto 8);
                        if cnt mod 8 = 7 then
                            kreg <= cle_inv(kr);
                        else
                            kreg <= kr;
                        end if;
                        if cnt = 55 then
                            cnt  <= 0;
                            etat <= B_ECRIT;
                        else
                            cnt <= cnt + 1;
                        end if;
                    -- bloc chiffré rangé à sa place ; il sert au bloc précédent
                    when B_ECRIT =>
                        ecr := true; e_adr := base + cnt; e_oct := w(7 downto 0);
                        wr := w(7 downto 0) & w(63 downto 8);      -- un tour complet en 8 cycles
                        w  <= wr;
                        if cnt = 7 then
                            chaine <= wr;
                            cnt    <= 0;
                            if bi = 0 then
                                pos  <= 0;
                                etat <= S_ADR;
                            else
                                bi   <= bi - 1;
                                base <= base - 8;
                                etat <= B_LIT;
                            end if;
                        else
                            cnt <= cnt + 1;
                        end if;
                    -- relecture de l'octet pos
                    when S_ADR =>
                        adr  <= to_unsigned(pos, 8);
                        etat <= S_ATT;
                    when S_ATT =>
                        etat <= S_OCT;
                    when S_OCT =>
                        o := lu;
                        if pos = 3 and brouille = '1' then
                            o(7 downto 6) := "10";
                        end if;
                        oct <= o;
                        sor <= o;                                  -- octet en clair, sauf flux ci-dessous
                        if brouille = '1' and pos >= hdr then
                            rc   <= 0;
                            etat <= S_TOURS;
                        else
                            etat <= S_POUSSE;
                        end if;
                    -- 4 tours du flux : initialisation par le premier bloc, puis 8 bits de flux
                    when S_TOURS =>
                        if pos < hdr + 8 then
                            if rc mod 2 = 0 then
                                fl <= flux_tour(fl, '1', oct(7 downto 4), oct(3 downto 0));
                            else
                                fl <= flux_tour(fl, '1', oct(3 downto 0), oct(7 downto 4));
                            end if;
                        else
                            nf := flux_tour(fl, '0', "0000", "0000");
                            fl <= nf;
                            kn := ks(5 downto 0) & (nf.d(3) xor nf.d(2)) & (nf.d(1) xor nf.d(0));
                            ks <= kn;
                            if rc = 3 then
                                sor <= oct xor kn;
                            end if;
                        end if;
                        if rc = 3 then
                            etat <= S_POUSSE;
                        else
                            rc <= rc + 1;
                        end if;
                    -- octet vers la file
                    when S_POUSSE =>
                        if f_pleine = '0' then
                            pousse := true;
                            if pos = 187 then
                                etat <= CHARGE;
                            else
                                pos  <= pos + 1;
                                etat <= S_ADR;
                            end if;
                        end if;
                end case;

                -- écritures des deux mémoires
                if ecr then
                    tamp(e_adr) <= e_oct;
                end if;
                if pousse then
                    fifo(to_integer(f_ecr(7 downto 0))) <= sor;
                    f_ecr <= f_ecr + 1;
                end if;
            end if;
        end if;
    end process;

    -- E : file → T : un octet par transfert, synchro tous les 188 octets → S :
    --   paquets TS vers l'aval
    process (clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                f_lec <= (others => '0'); cs <= 0; o_valid <= '0';
            elsif libre = '1' then
                o_valid <= '0';
                if f_vide = '0' then
                    m_data  <= fifo(to_integer(f_lec(7 downto 0)));
                    m_sop   <= '1' when cs = 0 else '0';
                    o_valid <= '1';
                    f_lec   <= f_lec + 1;
                    cs      <= 0 when cs = 187 else cs + 1;
                end if;
            end if;
        end if;
    end process;
end architecture rtl;

--------------------------------------------------------------------------------
-- rate_ctrl : régulation de débit TM5 en entiers, un quantiser_scale_code par
--   rangée de macroblocs (slice) ; référence bit à bit : JPEG2DVB
--   étape 03 (3.0)
--   Interface : s_* / m_* : coefficients DCT, de la DCT vers la quantification ;
--               la vanne se ferme à la fin de chaque rangée et se rouvre quand
--               le code de la rangée suivante est prêt ;
--               v_* : mots VLC acceptés par l'assemblage (observés seulement) ;
--               code, code_ok : code de la rangée en cours, pour la
--               quantification et l'en-tête de slice
--   Paramètres : G_COLS × G_ROWS macroblocs (22 × 18, ou 45 × 36 en 720 × 576),
--                G_T budget en bits par image, G_GOP longueur du GOP
--   Principe : avant la rangée s (j = s·G_COLS, N = G_COLS·G_ROWS) :
--                d = d0 + B − ⌊T·j / N⌋, B bits des rangées déjà produites
--                code = 1 si d ≤ 0, sinon ⌊(31·d + T) / 2T⌋ borné à 1..31
--              bits d'une slice : 38 + Σ (2 + bits VLC du macrobloc), arrondi
--              à l'octet ; fin d'image : B += 136 (+ 240 en tête de GOP),
--              d0 ← max(0, d0 + B − T) ; d0 initial = ⌊20·T / 31⌋.
--              ⌊T·j / N⌋ = ⌊T·s / G_ROWS⌋ tenu en cumul (quotient, reste) ;
--              division par 2T en 5 pas (quotient ≤ 31).
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity rate_ctrl is
    generic (
        G_COLS : natural := 22;
        G_ROWS : natural := 18;
        G_T    : natural := 350196;
        G_GOP  : natural := 12
    );
    port (
        clk     : in  std_logic;
        rst     : in  std_logic;
        -- coefficients DCT → quantification
        s_valid : in  std_logic;
        s_ready : out std_logic;
        s_data  : in  signed(15 downto 0);
        m_valid : out std_logic;
        m_ready : in  std_logic;
        m_data  : out signed(15 downto 0);
        -- mots VLC acceptés par l'assemblage du flux élémentaire
        v_valid : in  std_logic;
        v_ready : in  std_logic;
        v_lg    : in  unsigned(5 downto 0);
        v_fin   : in  std_logic;
        -- code de la rangée
        code    : out unsigned(4 downto 0);
        code_ok : out std_logic
    );
end entity rate_ctrl;

architecture rtl of rate_ctrl is
    constant W      : natural := 40;                     -- largeur des cumuls (bits)
    constant COEFS  : natural := G_COLS * 384;           -- coefficients par rangée
    constant SB0    : natural := 38 + 2 * G_COLS;        -- en-tête de slice + adresses et types
    constant T_Q    : natural := G_T / G_ROWS;
    constant T_R    : natural := G_T mod G_ROWS;
    constant DEN    : signed(W - 1 downto 0) := to_signed(2 * G_T, W);
    constant D0_INI : natural := (20 * (G_T / 31)) + (20 * (G_T mod 31)) / 31;   -- ⌊20·T / 31⌋ sans débordement

    type etat_t is (CALCUL, DIVISION, PRET);
    signal etat    : etat_t := CALCUL;
    signal ouvert  : std_logic := '0';
    signal n_coef  : natural range 0 to COEFS - 1 := 0;

    -- côté VLC : position et bits
    signal col     : natural range 0 to G_COLS - 1 := 0;
    signal rang    : natural range 0 to G_ROWS - 1 := 0;
    signal sb      : unsigned(W - 1 downto 0) := to_unsigned(SB0, W);    -- bits de la slice en cours
    signal b_img   : signed(W - 1 downto 0) := (others => '0');          -- B
    signal d0      : signed(W - 1 downto 0) := to_signed(D0_INI, W);
    signal cib_q   : signed(W - 1 downto 0) := (others => '0');          -- ⌊T·s / G_ROWS⌋
    signal cib_r   : natural range 0 to G_ROWS - 1 := 0;
    signal n_gop   : natural range 0 to G_GOP - 1 := 0;

    -- division
    signal num     : signed(W - 1 downto 0) := (others => '0');
    signal k       : natural range 0 to 4 := 4;
    signal quot    : unsigned(4 downto 0) := (others => '0');
    signal code_r  : unsigned(4 downto 0) := to_unsigned(1, 5);
begin
    -- vanne : un coefficient passe tel quel quand le code de sa rangée est prêt
    m_valid <= s_valid and ouvert;
    s_ready <= m_ready and ouvert;
    m_data  <= s_data;
    code    <= code_r;
    code_ok <= '1' when etat = PRET else '0';

    -- E : coefficients, mots VLC acceptés → T : vanne de rangée, bits de slice
    --   arrondis à l'octet, B et d0, code par division en 5 pas → S : code,
    --   code_ok
    process (clk)
        variable sa   : unsigned(W - 1 downto 0);
        variable b    : signed(W - 1 downto 0);
        variable dn   : signed(W - 1 downto 0);
        variable d    : signed(W - 1 downto 0);
        variable n31  : signed(W + 4 downto 0);
        variable essai : signed(W - 1 downto 0);
    begin
        if rising_edge(clk) then
            if rst = '1' then
                etat <= CALCUL; ouvert <= '0'; n_coef <= 0;
                col <= 0; rang <= 0; sb <= to_unsigned(SB0, W);
                b_img <= (others => '0'); d0 <= to_signed(D0_INI, W);
                cib_q <= (others => '0'); cib_r <= 0; n_gop <= 0;
                code_r <= to_unsigned(1, 5);
            else
                -- vanne : fermeture après le dernier coefficient de la rangée
                if s_valid = '1' and m_ready = '1' and ouvert = '1' then
                    if n_coef = COEFS - 1 then
                        n_coef <= 0;
                        ouvert <= '0';
                    else
                        n_coef <= n_coef + 1;
                    end if;
                end if;

                -- comptage des bits produits
                if v_valid = '1' and v_ready = '1' then
                    if v_fin = '1' and col = G_COLS - 1 then
                        -- fin de rangée : slice arrondie à l'octet, ajoutée à B
                        sa := sb + v_lg + 7;
                        sa(2 downto 0) := "000";
                        b  := b_img + signed(sa);
                        sb <= to_unsigned(SB0, W);
                        col <= 0;
                        if rang = G_ROWS - 1 then
                            -- fin d'image : en-têtes d'image (et de séquence, GOP)
                            b := b + 136;
                            if n_gop = 0 then b := b + 240; end if;
                            dn := d0 + b - G_T;
                            if dn < 0 then d0 <= (others => '0'); else d0 <= dn; end if;
                            b_img <= (others => '0');
                            rang  <= 0;
                            cib_q <= (others => '0'); cib_r <= 0;
                            n_gop <= 0 when n_gop = G_GOP - 1 else n_gop + 1;
                        else
                            b_img <= b;
                            rang  <= rang + 1;
                            if cib_r + T_R >= G_ROWS then
                                cib_r <= cib_r + T_R - G_ROWS;
                                cib_q <= cib_q + T_Q + 1;
                            else
                                cib_r <= cib_r + T_R;
                                cib_q <= cib_q + T_Q;
                            end if;
                        end if;
                        etat <= CALCUL;                 -- code de la rangée suivante
                    else
                        sb <= sb + v_lg;
                        if v_fin = '1' then col <= col + 1; end if;
                    end if;
                end if;

                case etat is
                    when CALCUL =>
                        -- d = d0 + B − ⌊T·s / G_ROWS⌋ (registres déjà à jour)
                        if not (v_valid = '1' and v_ready = '1' and v_fin = '1' and col = G_COLS - 1) then
                            d := d0 + b_img - cib_q;
                            if d <= 0 then
                                code_r <= to_unsigned(1, 5);
                                etat   <= PRET;
                                ouvert <= '1';
                            else
                                n31 := shift_left(resize(d, W + 5), 5) - resize(d, W + 5) + G_T;     -- 31·d + T
                                if n31 >= shift_left(resize(DEN, W + 5), 5) then                     -- quotient ≥ 32
                                    code_r <= to_unsigned(31, 5);
                                    etat   <= PRET;
                                    ouvert <= '1';
                                else
                                    num  <= resize(n31, W);
                                    k    <= 4;
                                    quot <= (others => '0');
                                    etat <= DIVISION;
                                end if;
                            end if;
                        end if;
                    when DIVISION =>
                        essai := num - shift_left(DEN, k);
                        if essai >= 0 then
                            num <= essai;
                            quot(k) <= '1';
                        end if;
                        if k = 0 then
                            if essai >= 0 then
                                code_r <= quot or "00001";
                            elsif quot = 0 then
                                code_r <= to_unsigned(1, 5);
                            else
                                code_r <= quot;
                            end if;
                            etat   <= PRET;
                            ouvert <= '1';
                        else
                            k <= k - 1;
                        end if;
                    when PRET =>
                        null;
                end case;
            end if;
        end if;
    end process;
end architecture rtl;

--------------------------------------------------------------------------------
-- mire_gen : mire animée : image 16 couleurs calculée (mire_idx), carré mobile et
--   compteur d'images incrustés, conversion Y, Cb, Cr par palette,
--   sortie en macroblocs 4:2:0 ; référence bit à bit : JPEG2DVB
--   étape 01 (fpga_test/mire.png chargée, option « mobile »)
--   Interface : sortie : octets dans l'ordre des macroblocs (rangée par rangée),
--               6 blocs par macrobloc (Y haut-gauche, haut-droite, bas-gauche,
--               bas-droite, Cb, Cr), 64 valeurs par bloc ligne par ligne ;
--               m_debut marque le premier octet de chaque image
--   Principe : image n : carré 32 × 32 en y = 176, x = 8n mod 320 (bord noir de
--              2 pixels, intérieur blanc) ; compteur binaire de n sur 12 carrés
--              8 × 8 en y = 280, x = 8 + 10b (blanc = 1, poids fort à gauche).
--              Toutes les frontières sont paires : la chrominance d'un bloc
--              2 × 2 est celle de son pixel haut-gauche.
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.mire_pkg.all;

entity mire_gen is
    port (
        clk     : in  std_logic;
        rst     : in  std_logic;
        m_valid : out std_logic;
        m_ready : in  std_logic;
        m_data  : out unsigned(7 downto 0);
        m_debut : out std_logic
    );
end entity mire_gen;

architecture rtl of mire_gen is
    constant COLS : natural := MIRE_L / 16;
    constant ROWS : natural := MIRE_H / 16;
    signal n       : unsigned(11 downto 0) := (others => '0');   -- rang de l'image
    signal sq_x    : natural range 0 to 319 := 0;                -- abscisse du carré : 8n mod 320
    signal row     : natural range 0 to ROWS - 1 := 0;
    signal col     : natural range 0 to COLS - 1 := 0;
    signal blk     : natural range 0 to 5 := 0;
    signal yy, xx  : natural range 0 to 7 := 0;
    signal o_valid : std_logic := '0';
    signal libre   : std_logic;

    -- couleur du pixel (x, y) de l'image n, incrustations comprises
    function couleur(x, y : natural; img : unsigned(11 downto 0); x0 : natural) return natural is
        variable b  : natural range 0 to 11;
    begin
        if y >= 176 and y < 208 and x >= x0 and x < x0 + 32 then
            if y >= 178 and y < 206 and x >= x0 + 2 and x < x0 + 30 then
                return IDX_BLANC;
            else
                return IDX_NOIR;
            end if;
        end if;
        if y >= 280 and x >= 8 and x < 8 + 10 * 11 + 8 and (x - 8) mod 10 < 8 then
            b := (x - 8) / 10;
            if img(11 - b) = '1' then return IDX_BLANC; else return IDX_NOIR; end if;
        end if;
        return mire_idx(x, y);
    end function;
begin
    libre   <= (not o_valid) or m_ready;
    m_valid <= o_valid;

    -- E : — → T : balayage des macroblocs de l'image n (4 blocs Y, Cb, Cr),
    --   carré mobile et compteur → S : pixels 4:2:0, m_debut en tête d'image
    process (clk)
        variable px, py : natural range 0 to 511;
        variable c      : natural range 0 to 15;
        variable v      : natural range 0 to 255;
    begin
        if rising_edge(clk) then
            if rst = '1' then
                n <= (others => '0'); sq_x <= 0; row <= 0; col <= 0; blk <= 0; yy <= 0; xx <= 0; o_valid <= '0';
            elsif libre = '1' then
                if blk < 4 then
                    px := col * 16 + (blk mod 2) * 8 + xx;
                    py := row * 16 + (blk / 2) * 8 + yy;
                else
                    px := 2 * (col * 8 + xx);
                    py := 2 * (row * 8 + yy);
                end if;
                c := couleur(px, py, n, sq_x);
                if blk < 4 then v := PALETTE(c)(0); elsif blk = 4 then v := PALETTE(c)(1); else v := PALETTE(c)(2); end if;
                m_data  <= to_unsigned(v, 8);
                m_debut <= '1' when row = 0 and col = 0 and blk = 0 and yy = 0 and xx = 0 else '0';
                o_valid <= '1';
                -- pixel suivant
                if xx < 7 then
                    xx <= xx + 1;
                else
                    xx <= 0;
                    if yy < 7 then
                        yy <= yy + 1;
                    else
                        yy <= 0;
                        if blk < 5 then
                            blk <= blk + 1;
                        else
                            blk <= 0;
                            if col < COLS - 1 then
                                col <= col + 1;
                            else
                                col <= 0;
                                if row < ROWS - 1 then
                                    row <= row + 1;
                                else
                                    row <= 0;
                                    n   <= n + 1;
                                    sq_x <= 0 when sq_x = 312 else sq_x + 8;
                                end if;
                            end if;
                        end if;
                    end if;
                end if;
            end if;
        end if;
    end process;
end architecture rtl;

--------------------------------------------------------------------------------
-- video_enc : tête de chaîne vidéo : mire animée → DCT entière → régulation
--   TM5 → quantification → zigzag → VLC → flux élémentaire → PES et
--   Transport Stream à débit constant ; référence bit à bit :
--   JPEG2DVB étapes 01 à 08 (mire fpga_test/mire.png, DCT entière,
--   régulation TM5 de l'étape 03 3.0)
--   Interface : sortie : paquets TS de
--               188 octets (m_sop sur la synchro), à prélever au rythme du
--               canal (un paquet par créneau de 13 056 cycles à 80 MHz)
--   Paramètres : G_IMAGES : nombre d'images avant sequence_end_code (0 = sans fin)
--                G_T : budget en bits par image (350 196 : 10 MS/s, FEC 1/2,
--                95 % de vidéo, 25 images/s)
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity video_enc is
    generic (
        G_IMAGES : natural := 0;
        G_T      : natural := 350196
    );
    port (
        clk     : in  std_logic;
        rst     : in  std_logic;
        m_valid : out std_logic;
        m_ready : in  std_logic;
        m_data  : out std_logic_vector(7 downto 0);
        m_sop   : out std_logic
    );
end entity video_enc;

architecture rtl of video_enc is
    signal p_valid, p_ready, p_debut : std_logic;
    signal p_data                    : unsigned(7 downto 0);
    signal d_valid, d_ready          : std_logic;
    signal d_data                    : signed(15 downto 0);
    signal g_valid, g_ready          : std_logic;
    signal g_data                    : signed(15 downto 0);
    signal code                      : unsigned(4 downto 0);
    signal code_ok                   : std_logic;
    signal q_valid, q_ready          : std_logic;
    signal q_data                    : signed(15 downto 0);
    signal z_valid, z_ready          : std_logic;
    signal z_data                    : signed(15 downto 0);
    signal v_valid, v_ready, v_fin   : std_logic;
    signal v_code                    : std_logic_vector(31 downto 0);
    signal v_lg                      : unsigned(5 downto 0);
    signal e_valid, e_ready          : std_logic;
    signal e_data                    : std_logic_vector(7 downto 0);
begin
    u_mire : entity work.mire_gen
        port map (clk, rst, p_valid, p_ready, p_data, p_debut);
    u_dct : entity work.dct8x8_int
        port map (clk, rst, p_valid, p_ready, p_data, d_valid, d_ready, d_data);
    u_rc : entity work.rate_ctrl generic map (G_T => G_T)
        port map (clk, rst, d_valid, d_ready, d_data, g_valid, g_ready, g_data, v_valid, v_ready, v_lg, v_fin, code, code_ok);
    u_quant : entity work.quant_intra
        port map (clk, rst, code, g_valid, g_ready, g_data, q_valid, q_ready, q_data);
    u_zz : entity work.zigzag
        port map (clk, rst, q_valid, q_ready, q_data, z_valid, z_ready, z_data);
    u_vlc : entity work.vlc_enc
        port map (clk, rst, z_valid, z_ready, z_data, v_valid, v_ready, v_code, v_lg, v_fin);
    u_es : entity work.es_mux generic map (G_IMAGES => G_IMAGES)
        port map (clk, rst, code, code_ok, v_valid, v_ready, v_code, v_lg, v_fin, e_valid, e_ready, e_data);
    u_ts : entity work.ts_mux
        port map (clk, rst, e_valid, e_ready, e_data, m_valid, m_ready, m_data, m_sop);
end architecture rtl;

--------------------------------------------------------------------------------
-- dvbs_tx : émetteur complet, de la mire animée aux échantillons I/Q mis
--   en forme : video_enc (étapes 01 à 08) → tx_backend (étapes
--   09 à 14) ; référence bit à bit : fichier .cs16 de JPEG2DVB
--   Interface : horloge 80 MHz (8 × 10 MS/s) ; sortie : I, Q signés 16 bits, un échantillon par cycle, vers
--               l'interpolateur et le sigma-delta (à venir)
--   Principe : le filtre SRRC impose le rythme ; le contrôle de flux remonte
--              jusqu'au multiplexeur TS, qui émet ainsi un paquet par créneau
--              de 13 056 cycles, comme dans le modèle temporel de JPEG2DVB
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.dvbs_pkg.all;

entity dvbs_tx is
    generic (
        G_IMAGES : natural := 0;
        G_FEC    : natural range 0 to 4 := 0
    );
    port (
        clk     : in  std_logic;
        rst     : in  std_logic;
        m_valid : out std_logic;
        m_ready : in  std_logic;
        m_i     : out signed(15 downto 0);
        m_q     : out signed(15 downto 0)
    );
end entity dvbs_tx;

architecture rtl of dvbs_tx is
    signal t_valid, t_ready, t_sop : std_logic;
    signal t_data                  : std_logic_vector(7 downto 0);
begin
    u_video : entity work.video_enc generic map (G_IMAGES => G_IMAGES, G_T => budget_image(10_000_000, G_FEC, 95, 25))
        port map (clk, rst, t_valid, t_ready, t_data, t_sop);
    u_canal : entity work.tx_backend generic map (G_FEC => G_FEC)
        port map (clk, rst, t_valid, t_ready, t_data, t_sop, m_valid, m_ready, m_i, m_q);
end architecture rtl;

--------------------------------------------------------------------------------
-- sd_entree : apport des entrées à la boucle sigma-delta pour un cycle de 8
--   instants (une voie) : le filtre SRRC à 640 MS/s est intégré aux tables ;
--   référence bit à bit : fpga_test/sdm.js
--   Interface : en : un groupe (fenêtre de 13 symboles, cycle q de 0 à 7)
--               consommé ; sorties registrées : in_k (k = 3 à 7) et u1, u2, u3
--   Principe : avec u(j) = Σd SDM_H(8q + j)(d)·sym(d), les grandeurs utiles sont
--              linéaires en sym : Ink = Σ(j<k) C(k−1−j, 2)·u(j) (In0 = In1 =
--              In2 = 0), U1 = Σ u(j), U2 = Σ (7−j)·u(j), U3 = Σ C(7−j, 2)·u(j).
--              Leurs coefficients par symbole sont précalculés (8 cycles × 13
--              symboles) : chaque grandeur est une somme de 13 constantes
--              signées par les bits de la fenêtre.
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.dvbs_pkg.all;
use work.sdm_coef_pkg.all;

entity sd_entree is
    port (
        clk : in  std_logic;
        rst : in  std_logic;
        en  : in  std_logic;
        fen : in  std_logic_vector(12 downto 0);   -- bit d = symbole d (1 → −1), d = 12 le plus récent
        q   : in  natural range 0 to 7;
        g   : out sd_grp_t                         -- In3 … In7, U1, U2, U3
    );
end entity sd_entree;

architecture rtl of sd_entree is
    -- poids des grandeurs (0 à 4 : In3 à In7, 5 à 7 : U1 à U3) sur u(j)
    function poids(i, j : natural) return integer is
        variable k, m : integer;
    begin
        if i <= 4 then
            k := i + 3;
            if j < k then m := k - 1 - j; return m * (m - 1) / 2; else return 0; end if;
        elsif i = 5 then return 1;
        elsif i = 6 then return 7 - j;
        else m := 7 - j; return m * (m - 1) / 2;
        end if;
    end function;
    type coef_t is array (0 to 7, 0 to 7, 0 to 12) of integer;   -- [q][grandeur][d]
    -- tables : E : SDM_H → S : coefficient de chaque grandeur par cycle et symbole
    function tables return coef_t is
        variable t : coef_t;
        variable s : integer;
    begin
        for qq in 0 to 7 loop
            for i in 0 to 7 loop
                for d in 0 to 12 loop
                    s := 0;
                    for j in 0 to 7 loop
                        s := s + poids(i, j) * SDM_H(8 * qq + j)(d);
                    end loop;
                    t(qq, i, d) := s;
                end loop;
            end loop;
        end loop;
        return t;
    end function;
    constant TAB : coef_t := tables;
    signal g_r : sd_grp_t := (others => (others => '0'));
begin
    g <= g_r;

    -- E : fenêtre, cycle → T : 8 sommes de 13 constantes signées → S : groupe
    process (clk)
        variable s : signed(SD_G - 1 downto 0);
    begin
        if rising_edge(clk) then
            if rst = '1' then
                g_r <= (others => (others => '0'));
            elsif en = '1' then
                for i in 0 to 7 loop
                    s := (others => '0');
                    for d in 0 to 12 loop
                        if fen(d) = '0' then
                            s := s + to_signed(TAB(q, i, d), SD_G);
                        else
                            s := s - to_signed(TAB(q, i, d), SD_G);
                        end if;
                    end loop;
                    g_r(i) <= s;
                end loop;
            end if;
        end if;
    end process;
end architecture rtl;

--------------------------------------------------------------------------------
-- sdm3 : modulateur sigma-delta 1 bit d'ordre 3 (une voie), 8 bits par cycle,
--   décisions par anticipation ; référence bit à bit : fpga_test/sdm.js
--   Interface : charge : premier groupe (P ← In, U) ; pas : émet les 8 bits du
--               groupe courant et prend le groupe suivant gs (son In, son U) ;
--               bits : registrés, bits(7) le premier émis (1 = +FS)
--   Principe : CIFB, FS = 2^SDM_F, états × 16 : x3 ← x3 + x2 − 16·FS·s,
--              x2 ← x2 + x1 − 6·FS·s, x1 ← x1 + u − FS·s, s = +1 si x3 ≥ 0.
--              Registres : X (x1, x2, x3) et Pk = C(k,2)·x1 + k·x2 + x3 + Ink,
--              valeur de x3 au pas k sans les décisions du cycle. Décision :
--              sk = Pk ≥ Dk(s0…sk−1) ; les 255 comparaisons à des constantes sont
--              faites en parallèle (signe d'une soustraction) ; s0…s3 en chaîne de
--              multiplexeurs, s4…s7 calculées pour les 16 débuts possibles puis
--              choisies par s0…s3. État suivant : Y = M⁸·X + U (sans les
--              décisions), X ← Y − T(s), Pk ← C(k,2)·y1 + k·y2 + y3 + In'k −
--              Rk(s) ; T et R sont linéaires en s : demi-tables de 16 constantes
--              pour s0…s3 et pour s4…s7 ; les 16 résultats possibles selon s4…s7
--              sont préparés, puis choisis. Garde : si |xi| > 2¹⁵ en début de
--              cycle, les états repartent de zéro (P ← In').
--   Largeurs : Dk, T et R sont multiples de FS : Pk ≥ Dk équivaut à
--              ⌊Pk / FS⌋ ≥ Dk / FS, et ⌊(Q − R) / FS⌋ = ⌊Q / FS⌋ − R / FS. Seuls
--              les SD_W − SDM_F bits de poids fort de Pk sont gardés, comparés
--              et corrigés ; les SDM_F bits de poids faible de x1, x2, x3 sont
--              ceux de Y. Bornes sous la garde (|U1| ≤ 3 840, |U2| ≤ 13 473,
--              |U3| ≤ 26 966) : |x1| ≤ 44 800 (17 bits), |x2| ≤ 386 209 (20 bits),
--              |x3| ≤ 1 599 830 (22 bits), |Pk| ≤ 5 260 950 (24 bits).
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.dvbs_pkg.all;
use work.sdm_coef_pkg.all;

entity sdm3 is
    port (
        clk    : in  std_logic;
        rst    : in  std_logic;
        charge : in  std_logic;
        pas    : in  std_logic;
        gs     : in  sd_grp_t;
        bits   : out std_logic_vector(7 downto 0)
    );
end entity sdm3;

architecture rtl of sdm3 is
    constant FS    : integer := 2 ** SDM_F;
    constant A1    : integer := FS;
    constant A2    : integer := 6 * FS;
    constant A3    : integer := 16 * FS;
    constant GARDE : integer := 2 ** 15;
    constant W1    : natural := 17;                      -- x1, y1
    constant W2    : natural := 20;                      -- x2, y2
    constant W3    : natural := 22;                      -- x3, y3
    constant WH    : natural := SD_W - SDM_F;            -- poids forts de Pk
    subtype mot_t  is signed(SD_W - 1 downto 0);
    subtype haut_t is signed(WH - 1 downto 0);
    subtype app_t  is signed(SD_G - 1 downto 0);
    type haut8_t is array (0 to 7) of haut_t;
    type int_tab is array (natural range <>) of integer;

    function c2(m : integer) return integer is begin return m * (m - 1) / 2; end function;
    function c(m : integer) return integer is begin return c2(m) * A1 + m * A2 + A3; end function;
    -- seuils Dk(b) : motif b de k bits (poids fort = s0), rangés à 2^k − 1 + b
    function seuils return int_tab is
        variable t : int_tab(0 to 254);
        variable d, sj : integer;
    begin
        for k in 0 to 7 loop
            for b in 0 to 2 ** k - 1 loop
                d := 0;
                for j in 0 to k - 1 loop
                    if (b / 2 ** (k - 1 - j)) mod 2 = 1 then sj := 1; else sj := -1; end if;
                    d := d + c(k - 1 - j) * sj;
                end loop;
                t(2 ** k - 1 + b) := d;
            end loop;
        end loop;
        return t;
    end function;
    constant DK : int_tab(0 to 254) := seuils;

    -- poids de la décision sj (j = 0 à 7) dans la correction de l'état après
    --   8 pas : i = 1, 2, 3 pour x1, x2, x3 ; i = 10 + k pour Pk du cycle suivant
    function rho(i, j : natural) return integer is
        constant m : integer := 7 - j;
        constant t1 : integer := A1;
        constant t2 : integer := m * A1 + A2;
        constant t3 : integer := c2(m) * A1 + m * A2 + A3;
    begin
        if i = 1 then return t1; elsif i = 2 then return t2; elsif i = 3 then return t3;
        else return c2(i - 10) * t1 + (i - 10) * t2 + t3;
        end if;
    end function;
    -- demi-table : somme des ±rho(i, j) pour les 4 décisions j0 … j0 + 3 du motif v
    --   (poids fort = décision j0)
    function demi(i, j0 : natural) return int_tab is
        variable t : int_tab(0 to 15);
        variable s : integer;
    begin
        for v in 0 to 15 loop
            s := 0;
            for j in 0 to 3 loop
                if (v / 2 ** (3 - j)) mod 2 = 1 then s := s + rho(i, j0 + j); else s := s - rho(i, j0 + j); end if;
            end loop;
            t(v) := s;
        end loop;
        return t;
    end function;
    -- tables des corrections : H pour s0…s3, L pour s4…s7
    constant TH1 : int_tab(0 to 15) := demi(1, 0);  constant TL1 : int_tab(0 to 15) := demi(1, 4);
    constant TH2 : int_tab(0 to 15) := demi(2, 0);  constant TL2 : int_tab(0 to 15) := demi(2, 4);
    constant TH3 : int_tab(0 to 15) := demi(3, 0);  constant TL3 : int_tab(0 to 15) := demi(3, 4);
    constant RH0 : int_tab(0 to 15) := demi(10, 0); constant RL0 : int_tab(0 to 15) := demi(10, 4);
    constant RH1 : int_tab(0 to 15) := demi(11, 0); constant RL1 : int_tab(0 to 15) := demi(11, 4);
    constant RH2 : int_tab(0 to 15) := demi(12, 0); constant RL2 : int_tab(0 to 15) := demi(12, 4);
    constant RH3 : int_tab(0 to 15) := demi(13, 0); constant RL3 : int_tab(0 to 15) := demi(13, 4);
    constant RH4 : int_tab(0 to 15) := demi(14, 0); constant RL4 : int_tab(0 to 15) := demi(14, 4);
    constant RH5 : int_tab(0 to 15) := demi(15, 0); constant RL5 : int_tab(0 to 15) := demi(15, 4);
    constant RH6 : int_tab(0 to 15) := demi(16, 0); constant RL6 : int_tab(0 to 15) := demi(16, 4);
    constant RH7 : int_tab(0 to 15) := demi(17, 0); constant RL7 : int_tab(0 to 15) := demi(17, 4);

    signal x1         : signed(W1 - 1 downto 0) := (others => '0');
    signal x2         : signed(W2 - 1 downto 0) := (others => '0');
    signal x3         : signed(W3 - 1 downto 0) := (others => '0');
    signal p          : haut8_t := (others => (others => '0'));     -- ⌊Pk / FS⌋
    signal u1, u2, u3 : app_t := (others => '0');
    signal b_r        : std_logic_vector(7 downto 0) := (others => '0');
    type cmp_t is array (0 to 7) of std_logic_vector(0 to 127);
    signal cmp        : cmp_t := (others => (others => '0'));     -- cmp(k)(b) = Pk ≥ Dk(b)

    -- in_de : E : groupe, k → S : Ink (0 pour k < 3)
    function in_de(g : sd_grp_t; k : natural) return app_t is
    begin
        if k < 3 then return (others => '0'); else return g(k - 3); end if;
    end function;
    -- haut : E : mot de la boucle → S : ses poids forts, ⌊v / FS⌋
    function haut(v : mot_t) return haut_t is
    begin
        return v(SD_W - 1 downto SDM_F);
    end function;
    -- rh, rl : E : k, motif de 4 décisions → S : demi-correction de Pk
    function rh(k, v : natural) return integer is
    begin
        case k is
            when 0 => return RH0(v); when 1 => return RH1(v); when 2 => return RH2(v); when 3 => return RH3(v);
            when 4 => return RH4(v); when 5 => return RH5(v); when 6 => return RH6(v); when others => return RH7(v);
        end case;
    end function;
    function rl(k, v : natural) return integer is
    begin
        case k is
            when 0 => return RL0(v); when 1 => return RL1(v); when 2 => return RL2(v); when 3 => return RL3(v);
            when 4 => return RL4(v); when 5 => return RL5(v); when 6 => return RL6(v); when others => return RL7(v);
        end case;
    end function;
begin
    bits <= b_r;

    -- comparaisons : les 255 tests Pk ≥ Dk(b) en parallèle, par le signe d'une
    --   soustraction (chaîne de retenue) sur les poids forts : ⌊Pk / FS⌋ − Dk / FS
    g_k : for k in 0 to 7 generate
        g_b : for b in 0 to 2 ** k - 1 generate
            signal dif : signed(WH downto 0);
        begin
            dif <= resize(p(k), WH + 1) - to_signed(DK(2 ** k - 1 + b) / FS, WH + 1);
            cmp(k)(b) <= not dif(WH);
        end generate;
    end generate;

    -- E : comparaisons, X, U du groupe courant, groupe suivant → T : décisions
    --   s0…s3 en chaîne, s4…s7 calculées pour les 16 débuts possibles puis
    --   choisies ; corrections en deux demi-tables (s0…s3 tôt, s4…s7 tard)
    --   → S : 8 bits, état suivant
    process (clk)
        type s4_t is array (0 to 15) of std_logic_vector(4 to 7);
        variable s       : std_logic_vector(0 to 7);
        variable sv      : s4_t;
        variable hi, lo  : natural range 0 to 15;
        variable vb      : std_logic_vector(0 to 3);
        variable t       : std_logic_vector(0 to 7);
        variable y1      : signed(W1 - 1 downto 0);
        variable y2      : signed(W2 - 1 downto 0);
        variable y3      : signed(W3 - 1 downto 0);
        variable q       : mot_t;
        variable qh      : haut_t;
        type c1_t is array (0 to 15) of signed(W1 - SDM_F - 1 downto 0);
        type c2_t is array (0 to 15) of signed(W2 - SDM_F - 1 downto 0);
        type c3_t is array (0 to 15) of signed(W3 - SDM_F - 1 downto 0);
        type cp_t is array (0 to 15) of haut_t;
        variable c1      : c1_t;
        variable c2v     : c2_t;
        variable c3      : c3_t;
        variable cp      : cp_t;
        variable ovf     : boolean;
    begin
        if rising_edge(clk) then
            if rst = '1' then
                x1 <= (others => '0'); x2 <= (others => '0'); x3 <= (others => '0');
                p <= (others => (others => '0'));
                u1 <= (others => '0'); u2 <= (others => '0'); u3 <= (others => '0');
                b_r <= (others => '0');
            elsif charge = '1' then
                for k in 0 to 7 loop p(k) <= haut(resize(in_de(gs, k), SD_W)); end loop;
                u1 <= gs(5); u2 <= gs(6); u3 <= gs(7);
                x1 <= (others => '0'); x2 <= (others => '0'); x3 <= (others => '0');
            elsif pas = '1' then
                -- s0…s3 : sk = Pk ≥ Dk(s0…sk−1)
                s(0) := cmp(0)(0);
                for k in 1 to 3 loop
                    s(k) := cmp(k)(to_integer(unsigned(s(0 to k - 1))));
                end loop;
                hi := to_integer(unsigned(s(0 to 3)));
                -- s4…s7 pour chacun des 16 débuts v, puis choix par s0…s3
                for v in 0 to 15 loop
                    vb := std_logic_vector(to_unsigned(v, 4));
                    t(0 to 3) := vb;
                    for k in 4 to 7 loop
                        t(k) := cmp(k)(to_integer(unsigned(t(0 to k - 1))));
                    end loop;
                    sv(v) := t(4 to 7);
                end loop;
                s(4 to 7) := sv(hi);
                lo := to_integer(unsigned(s(4 to 7)));
                for k in 0 to 7 loop b_r(7 - k) <= s(k); end loop;
                -- état suivant : Y = M⁸·X + U, X ← Y − T(s), Pk ← Qk − Rk(s)
                ovf := abs (x1) > GARDE or abs (x2) > GARDE or abs (x3) > GARDE;
                y1 := x1 + resize(u1, W1);
                y2 := shift_left(resize(x1, W2), 3) + x2 + resize(u2, W2);
                y3 := shift_left(resize(x1, W3), 5) - shift_left(resize(x1, W3), 2) + shift_left(resize(x2, W3), 3) + x3 + resize(u3, W3);
                if ovf then
                    x1 <= (others => '0'); x2 <= (others => '0'); x3 <= (others => '0');
                    for k in 0 to 7 loop p(k) <= haut(resize(in_de(gs, k), SD_W)); end loop;
                else
                    -- 16 candidats (un par motif s4…s7) calculés sans attendre s4…s7,
                    --   la demi-correction de s0…s3 retranchée dès que s0…s3 sont connus,
                    --   puis choix par s4…s7 ; corrections multiples de FS : seuls les
                    --   poids forts sont corrigés, les SDM_F poids faibles sont ceux de Y
                    for v in 0 to 15 loop
                        c1(v) := y1(W1 - 1 downto SDM_F) - to_signed(TL1(v) / FS, W1 - SDM_F) - to_signed(TH1(hi) / FS, W1 - SDM_F);
                        c2v(v) := y2(W2 - 1 downto SDM_F) - to_signed(TL2(v) / FS, W2 - SDM_F) - to_signed(TH2(hi) / FS, W2 - SDM_F);
                        c3(v) := y3(W3 - 1 downto SDM_F) - to_signed(TL3(v) / FS, W3 - SDM_F) - to_signed(TH3(hi) / FS, W3 - SDM_F);
                    end loop;
                    x1 <= c1(lo) & y1(SDM_F - 1 downto 0);
                    x2 <= c2v(lo) & y2(SDM_F - 1 downto 0);
                    x3 <= c3(lo) & y3(SDM_F - 1 downto 0);
                    for k in 0 to 7 loop
                        q := resize(y1 * to_signed(c2(k), 6), SD_W) + resize(y2 * to_signed(k, 5), SD_W) + resize(y3, SD_W) + resize(in_de(gs, k), SD_W);
                        qh := haut(q);
                        for v in 0 to 15 loop
                            cp(v) := qh - to_signed(rl(k, v) / FS, WH) - to_signed(rh(k, hi) / FS, WH);
                        end loop;
                        p(k) <= cp(lo);
                    end loop;
                end if;
                u1 <= gs(5); u2 <= gs(6); u3 <= gs(7);
            end if;
        end if;
    end process;
end architecture rtl;

--------------------------------------------------------------------------------
-- sigma_delta : sortie sigma-delta I/Q depuis les symboles QPSK : fenêtre des
--   13 derniers symboles, filtre SRRC à 640 MS/s par tables (sd_entree), puis
--   sigma-delta d'ordre 3 par anticipation (sdm3) sur chaque voie, 8 bits par
--   cycle et par voie (640 Mbit/s à 80 MHz) vers les sérialiseurs LVDS (à
--   venir) ; référence bit à bit : fpga_test/sd_iq.bin
--   Interface : entrée : un symbole (bits I et Q, 0 → +1) par transfert ;
--               chaque symbole donne 8 cycles de sortie ; sortie : m_i, m_q,
--               8 bits chacun, bit 7 émis en premier
--   Principe : trois étages avancés ensemble : groupes (fenêtre, cycle q),
--              apport des entrées (registré), boucle. La boucle traite le
--              groupe g quand le groupe g + 1 est prêt (son In sert à l'état
--              suivant). Avant le premier symbole, la fenêtre vaut +1.
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.dvbs_pkg.all;

entity sigma_delta is
    port (
        clk     : in  std_logic;
        rst     : in  std_logic;
        s_valid : in  std_logic;
        s_ready : out std_logic;
        s_i     : in  std_logic;
        s_q     : in  std_logic;
        m_valid : out std_logic;
        m_ready : in  std_logic;
        m_i     : out std_logic_vector(7 downto 0);
        m_q     : out std_logic_vector(7 downto 0)
    );
end entity sigma_delta;

architecture rtl of sigma_delta is
    signal fen_i, fen_q : std_logic_vector(12 downto 0) := (others => '0');
    signal q            : natural range 0 to 7 := 0;
    signal a_ok         : std_logic := '0';     -- fenêtre chargée : groupes à produire
    signal b_ok         : std_logic := '0';     -- apport des entrées registré
    signal l_ok         : std_logic := '0';     -- boucle chargée
    signal o_ok         : std_logic := '0';     -- bits en sortie
    signal gi, gq       : sd_grp_t;
    signal pas, charge, prend_b, produit, prend_s, q7 : std_logic;
begin
    -- boucle : pas si groupe suivant prêt et sortie libre ; charge au départ
    pas     <= l_ok and b_ok and (m_ready or not o_ok);
    charge  <= (not l_ok) and b_ok;
    prend_b <= pas or charge;
    -- groupes : un par cycle si l'étage B est libre ou se vide
    produit <= a_ok and ((not b_ok) or prend_b);
    -- symbole : accepté quand aucun groupe n'est en attente ou au dernier cycle
    q7      <= '1' when q = 7 else '0';
    prend_s <= s_valid and ((not a_ok) or (produit and q7));
    s_ready <= (not a_ok) or (produit and q7);
    m_valid <= o_ok;

    u_ei : entity work.sd_entree port map (clk, rst, produit, fen_i, q, gi);
    u_eq : entity work.sd_entree port map (clk, rst, produit, fen_q, q, gq);
    u_si : entity work.sdm3 port map (clk, rst, charge, pas, gi, m_i);
    u_sq : entity work.sdm3 port map (clk, rst, charge, pas, gq, m_q);

    -- E : symboles, avancées → T : fenêtres, cycle q, occupation des étages
    --   → S : m_valid
    process (clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                fen_i <= (others => '0'); fen_q <= (others => '0');
                q <= 0; a_ok <= '0'; b_ok <= '0'; l_ok <= '0'; o_ok <= '0';
            else
                if produit = '1' then
                    q <= (q + 1) mod 8;
                    if q = 7 then a_ok <= '0'; end if;
                end if;
                if prend_s = '1' then
                    fen_i <= s_i & fen_i(12 downto 1);
                    fen_q <= s_q & fen_q(12 downto 1);
                    a_ok  <= '1';
                end if;
                if produit = '1' then b_ok <= '1'; elsif prend_b = '1' then b_ok <= '0'; end if;
                if charge = '1' then l_ok <= '1'; end if;
                if pas = '1' then o_ok <= '1'; elsif m_ready = '1' then o_ok <= '0'; end if;
            end if;
        end if;
    end process;
end architecture rtl;

--------------------------------------------------------------------------------
-- bt656_rx : récepteur ITU-R BT.656 du décodeur vidéo TVP5150AM1 (PAL 625
--   lignes, 8 bits, synchros intégrées) ; domaine de l'horloge SCLK du
--   décodeur (27 MHz) ; référence octet à octet : fpga_test/bt656_ref.bin
--   (fpga_test/bt656.js)
--   Interface : d : un octet par cycle, sans contrôle de flux (le flux
--               BT.656 est continu) ; sortie : un couple de pixels (Cb, Y0,
--               Cr, Y1) par impulsion o_valid ; o_trame : bit F (0 = trame
--               1) ; o_ligne : 0 à 287 dans la trame ; o_x : couple 0 à
--               359 ; o_dt : premier couple de la trame ; o_sync : un début
--               de trame a été vu, les couples sont émis
--   Principe : FF 00 00 XY est un code de synchronisation, XY = 1 F V H P3 P2
--              P1 P0 (bits de protection non contrôlés : source propre) ;
--              un SAV (H = 0) de ligne active (V = 0) est suivi de 1 440
--              octets Cb Y Cr Y ; la ligne repart de 0 au premier SAV actif
--              qui suit un SAV de suppression (V = 1) ; rien n'est émis
--              avant ce premier début de trame
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity bt656_rx is
    port (
        clk     : in  std_logic;
        rst     : in  std_logic;
        d       : in  std_logic_vector(7 downto 0);
        o_valid : out std_logic;
        o_cb    : out std_logic_vector(7 downto 0);
        o_y0    : out std_logic_vector(7 downto 0);
        o_cr    : out std_logic_vector(7 downto 0);
        o_y1    : out std_logic_vector(7 downto 0);
        o_trame : out std_logic;
        o_ligne : out unsigned(8 downto 0);
        o_x     : out unsigned(8 downto 0);
        o_dt    : out std_logic;
        o_sync  : out std_logic
    );
end entity bt656_rx;

architecture rtl of bt656_rx is
    signal r1, r2, r3 : std_logic_vector(7 downto 0) := (others => '0');   -- 3 octets précédents, r3 le plus ancien
    signal actif      : std_logic := '0';                                  -- octets actifs en cours
    signal ph         : unsigned(1 downto 0) := "00";                      -- 0 Cb, 1 Y0, 2 Cr, 3 Y1
    signal cb, y0, cr : std_logic_vector(7 downto 0) := (others => '0');
    signal x          : unsigned(8 downto 0) := (others => '0');
    signal ligne      : unsigned(8 downto 0) := (others => '0');
    signal trame      : std_logic := '0';
    signal v_prec     : std_logic := '0';                                  -- V du SAV précédent
    signal sync       : std_logic := '0';
    signal prem       : std_logic := '0';                                  -- ligne en cours = première de la trame
begin
    o_sync <= sync;

    -- E : octets BT.656 → T : codes de synchronisation, trame, ligne, couples
    --   → S : couples de pixels et leur position
    process (clk)
    begin
        if rising_edge(clk) then
            o_valid <= '0';
            o_dt    <= '0';
            if rst = '1' then
                r1 <= (others => '0'); r2 <= (others => '0'); r3 <= (others => '0');
                actif <= '0'; ph <= "00"; x <= (others => '0'); ligne <= (others => '0');
                trame <= '0'; v_prec <= '0'; sync <= '0'; prem <= '0';
            else
                r3 <= r2; r2 <= r1; r1 <= d;
                if r3 = x"FF" and r2 = x"00" and r1 = x"00" then
                    -- d = XY : fin de la zone active, SAV éventuel
                    actif <= '0';
                    if d(4) = '0' then
                        v_prec <= d(5);
                        if d(5) = '0' then
                            ph <= "00";
                            x  <= (others => '0');
                            if v_prec = '1' then
                                ligne <= (others => '0');
                                trame <= d(6);
                                prem  <= '1';
                                sync  <= '1';
                                actif <= '1';
                            else
                                ligne <= ligne + 1;
                                prem  <= '0';
                                actif <= sync;
                            end if;
                        end if;
                    end if;
                elsif actif = '1' then
                    case ph is
                        when "00" => cb <= d;
                        when "01" => y0 <= d;
                        when "10" => cr <= d;
                        when others =>
                            o_cb <= cb; o_y0 <= y0; o_cr <= cr; o_y1 <= d;
                            o_trame <= trame; o_ligne <= ligne; o_x <= x;
                            o_valid <= '1';
                            if x = 0 and prem = '1' then o_dt <= '1'; end if;
                            if x = 359 then actif <= '0'; end if;
                            x <= x + 1;
                    end case;
                    ph <= ph + 1;
                end if;
            end if;
        end if;
    end process;
end architecture rtl;

--------------------------------------------------------------------------------
-- i2c_maitre : maître I²C minimal (un seul esclave, sans arbitrage), pour le
--   décodeur TVP5150AM1 (adresse B8h, I2CSEL à 0) ; l'esclave peut étirer SCL
--   Interface : go, si occupe = 0, lance une transaction : lire = 0 : S,
--               B8h, reg, val, P (écriture d'un registre) ; lire = 1 : S,
--               B8h, reg, P, S, B9h, lecture, NACK, P (lecture d'un
--               registre) ; fini : impulsion de fin ; ack_ok : tous les
--               octets émis ont été acquittés ; lu : octet lu ; scl_oe,
--               sda_oe : '1' tire la ligne à 0 (drain ouvert, rappels de
--               4,7 kΩ sur la carte)
--   Principe : programme de symboles (début, octet émis, octet lu, fin) ;
--              chaque bit dure 4 quarts de période : SDA posé SCL bas, SCL
--              relâché, SCL haut (SDA lu en fin de quart), SCL bas ; début et
--              fin tenus 2 quarts (mode standard : 4 µs) ; un quart où SCL
--              est relâché ne s'écoule que si SCL est lu à 1 (étirement par
--              l'esclave) ; libération : si SDA est tenu à 0 au moment d'un
--              début (esclave interrompu au milieu d'un octet), jusqu'à 9
--              impulsions SCL avant le début
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity i2c_maitre is
    generic (
        G_QUART : positive := 200            -- cycles par quart de période SCL (80 MHz, 100 kHz)
    );
    port (
        clk    : in  std_logic;
        rst    : in  std_logic;
        go     : in  std_logic;
        lire   : in  std_logic;
        reg    : in  std_logic_vector(7 downto 0);
        val    : in  std_logic_vector(7 downto 0);
        occupe : out std_logic;
        fini   : out std_logic;
        ack_ok : out std_logic;
        lu     : out std_logic_vector(7 downto 0);
        scl_oe : out std_logic;
        sda_oe : out std_logic;
        scl_i  : in  std_logic;
        sda_i  : in  std_logic
    );
end entity i2c_maitre;

architecture rtl of i2c_maitre is
    type sym_t is (S_DEB, S_ECR, S_LEC, S_FIN);
    type prog_t is array (0 to 7) of sym_t;
    constant P_ECR : prog_t := (S_DEB, S_ECR, S_ECR, S_ECR, S_FIN, S_FIN, S_FIN, S_FIN);   -- 5 symboles utiles
    constant P_LEC : prog_t := (S_DEB, S_ECR, S_ECR, S_FIN, S_DEB, S_ECR, S_LEC, S_FIN);
    signal l_lire       : std_logic := '0';
    signal l_reg, l_val : std_logic_vector(7 downto 0) := (others => '0');
    signal oc           : std_logic := '0';
    signal idx          : natural range 0 to 7 := 0;
    signal q            : natural range 0 to 3 := 0;
    signal k            : natural range 0 to 8 := 0;
    signal cnt          : natural range 0 to G_QUART - 1 := 0;
    signal scl_s, sda_s : std_logic_vector(1 downto 0) := "11";             -- synchroniseurs
    signal sh           : std_logic_vector(7 downto 0) := (others => '0');
    signal oe_scl, oe_sda : std_logic := '0';
    signal lib          : std_logic := '0';                                  -- libération du bus en cours
    signal nlib         : natural range 0 to 9 := 0;

    -- sym_de : E : sens, rang → S : symbole du programme
    function sym_de(lr : std_logic; i : natural) return sym_t is
    begin
        if lr = '1' then return P_LEC(i); else return P_ECR(i); end if;
    end function;
    -- octet_de : E : sens, rang, registre, valeur → S : octet émis à ce rang
    function octet_de(lr : std_logic; i : natural; r, v : std_logic_vector) return std_logic_vector is
    begin
        if i = 1 then return x"B8";
        elsif i = 2 then return r;
        elsif i = 5 then return x"B9";
        elsif lr = '0' and i = 3 then return v;
        else return x"FF";
        end if;
    end function;
begin
    occupe <= oc;
    scl_oe <= oe_scl;
    sda_oe <= oe_sda;

    -- E : commande, lignes lues → T : symboles, bits, quarts de période,
    --   étirement → S : lignes tirées, fin, acquittement, octet lu
    process (clk)
        variable s, ns    : sym_t;
        variable nq       : natural range 0 to 3;
        variable nk       : natural range 0 to 8;
        variable nidx     : natural range 0 to 8;
        variable b        : std_logic;
        variable o        : std_logic_vector(7 downto 0);
        variable long     : natural range 5 to 8;
    begin
        if rising_edge(clk) then
            scl_s <= scl_s(0) & scl_i;
            sda_s <= sda_s(0) & sda_i;
            fini  <= '0';
            if rst = '1' then
                oc <= '0'; oe_scl <= '0'; oe_sda <= '0'; ack_ok <= '1'; lu <= (others => '0');
                idx <= 0; q <= 0; k <= 0; cnt <= 0; lib <= '0'; nlib <= 0;
            elsif oc = '0' then
                if go = '1' then
                    l_lire <= lire; l_reg <= reg; l_val <= val;
                    oc <= '1'; idx <= 0; q <= 0; k <= 0; cnt <= G_QUART - 1; ack_ok <= '1'; nlib <= 0;
                    oe_scl <= '0'; oe_sda <= '0';                  -- début, quart 0 : lignes relâchées
                end if;
            elsif oe_scl = '0' and scl_s(1) = '0' then
                null;                                              -- SCL relâché mais lu à 0 : étirement
            elsif cnt /= 0 then
                cnt <= cnt - 1;
            elsif lib = '1' then
                -- libération du bus : impulsions SCL (2 quarts bas, 2 quarts
                --   relâché) tant que SDA est tenu à 0 par l'esclave, 9 au plus,
                --   puis reprise du début (lignes relâchées)
                cnt <= G_QUART - 1;
                if q < 3 then
                    q <= q + 1;
                    if q = 1 then oe_scl <= '0'; end if;
                elsif sda_s(1) = '1' or nlib = 9 then
                    lib <= '0'; q <= 0;
                else
                    nlib <= nlib + 1; q <= 0; oe_scl <= '1';
                end if;
            elsif sym_de(l_lire, idx) = S_DEB and q = 0 and sda_s(1) = '0' and nlib = 0 then
                -- début demandé mais SDA tenu à 0 (esclave interrompu au milieu
                --   d'un octet) : libération du bus
                cnt <= G_QUART - 1;
                lib <= '1'; nlib <= 1; q <= 0; oe_scl <= '1';
            else
                cnt <= G_QUART - 1;
                s := sym_de(l_lire, idx);
                -- lecture de SDA en fin de quart 2 : acquittement, bits lus
                if q = 2 then
                    if s = S_ECR and k = 8 and sda_s(1) /= '0' then ack_ok <= '0'; end if;
                    if s = S_LEC and k < 8 then sh <= sh(6 downto 0) & sda_s(1); end if;
                end if;
                -- quart suivant
                nidx := idx; nk := k;
                if q < 3 then
                    nq := q + 1;
                else
                    nq := 0;
                    if (s = S_ECR or s = S_LEC) and k < 8 then nk := k + 1; else nk := 0; nidx := idx + 1; end if;
                end if;
                if l_lire = '1' then long := 8; else long := 5; end if;
                if nidx = long then
                    oc <= '0'; fini <= '1'; lu <= sh;
                    oe_scl <= '0'; oe_sda <= '0';
                else
                    idx <= nidx; q <= nq; k <= nk;
                    ns := sym_de(l_lire, nidx);
                    o  := octet_de(l_lire, nidx, l_reg, l_val);
                    -- niveaux des lignes pendant le nouveau quart
                    case ns is
                        when S_DEB =>
                            if nq = 0 then oe_scl <= '0'; oe_sda <= '0';
                            elsif nq < 3 then oe_scl <= '0'; oe_sda <= '1';   -- SDA descend, SCL haut : début (tenu 2 quarts)
                            else oe_scl <= '1'; oe_sda <= '1';
                            end if;
                        when S_ECR | S_LEC =>
                            if ns = S_ECR and nk < 8 then b := o(7 - nk); else b := '1'; end if;
                            oe_sda <= not b;
                            if nq = 0 or nq = 3 then oe_scl <= '1'; else oe_scl <= '0'; end if;
                        when S_FIN =>
                            if nq = 0 then oe_scl <= '1'; oe_sda <= '1';
                            elsif nq < 3 then oe_scl <= '0'; oe_sda <= '1';   -- SCL haut, SDA bas (2 quarts)
                            else oe_scl <= '0'; oe_sda <= '0';                -- SDA monte, SCL haut : fin
                            end if;
                    end case;
                end if;
            end if;
        end if;
    end process;
end architecture rtl;

--------------------------------------------------------------------------------
-- tvp_ctrl : pilotage du décodeur vidéo TVP5150AM1 par I²C, sans
--   microcontrôleur ; banc : tb_tvp (modèle I²C du décodeur)
--   Interface : tvp_resetb, tvp_pdn : broches RESETB et PDN du décodeur ;
--               scl_oe, sda_oe, scl_i, sda_i : bus I²C (voir i2c_maitre) ;
--               present : décodeur identifié (80h = 51h, 81h = 50h) ;
--               video_ok : décodeur verrouillé (lignes et trames) sur
--               l'entrée choisie, flux BT.656 exploitable ; entree : 0 =
--               AIP1A, 1 = AIP1B ; choix (même horloge) : 00 ou 11 = choix
--               automatique, 01 = AIP1A imposée, 10 = AIP1B imposée ; tenir
--               rst à 1 tant que l'horloge 14,31818 MHz du décodeur (XTAL1)
--               n'est pas stable
--   Principe : démarrage : RESETB à 0 pendant 20 ms (alimentations), 1 ms
--              d'attente (200 µs minimum), lecture de l'identifiant ; absent :
--              nouvel essai chaque seconde ; configuration : CFh ← 00h et
--              D0h…FCh ← FFh (VBI coupé), 28h ← 04h (PAL B/G/H/I forcé),
--              00h ← 00h (AIP1A), 03h ← 09h (sorties YOUT et SCLK actives) ;
--              100 µs entre deux transactions (64 µs exigées après une
--              écriture des registres 00h à 8Fh) ; surveillance : lecture de
--              88h toutes les 20 ms, verrouillé si bits 1 et 2 à 1
--              (sous-porteuse ignorée : source noir et blanc admise) ;
--              acquisition : 10 lectures de stabilisation, verrouillé après
--              5 lectures verrouillées, entrée suivante après 25 lectures
--              sans succès ; perte : video_ok tombe à la première lecture
--              non verrouillée, retour sur AIP1A après 50 lectures (1 s)
--              sans 5 lectures verrouillées consécutives ; entrée imposée :
--              choisie dès la surveillance, jamais changée par le choix
--              automatique ; garde : une
--              transaction de plus de 10 ms remet le maître à zéro, le
--              décodeur est réputé absent, puis identifié et reconfiguré
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tvp_ctrl is
    generic (
        G_HZ     : positive := 80_000_000;   -- horloge
        G_I2C_HZ : positive := 100_000       -- fréquence SCL
    );
    port (
        clk        : in  std_logic;
        rst        : in  std_logic;
        tvp_resetb : out std_logic;
        tvp_pdn    : out std_logic;
        scl_oe     : out std_logic;
        sda_oe     : out std_logic;
        scl_i      : in  std_logic;
        sda_i      : in  std_logic;
        present    : out std_logic;
        video_ok   : out std_logic;
        entree     : out std_logic;
        choix      : in  std_logic_vector(1 downto 0) := "00"
    );
end entity tvp_ctrl;

architecture rtl of tvp_ctrl is
    constant C_MS     : positive := G_HZ / 1000;
    constant T_ALIM   : positive := 20 * C_MS;            -- RESETB à 0 après la mise sous tension
    constant T_REVEIL : positive := C_MS;                 -- après RESETB, avant le premier accès
    constant T_ECART  : positive := C_MS / 10;            -- entre deux transactions (100 µs)
    constant T_SCRUT  : positive := 20 * C_MS;            -- période de surveillance
    constant T_ABS    : positive := 1000 * C_MS;          -- nouvel essai si décodeur absent
    constant T_GARDE  : positive := 10 * C_MS;            -- transaction bloquée (SCL tenu à 0)
    constant K_STAB   : natural := 10;
    constant K_OK     : natural := 5;
    constant K_ACQ    : natural := 25;
    constant K_PERTE  : natural := 50;

    -- configuration : registre & valeur, dans l'ordre d'écriture
    constant N_CFG : natural := 49;
    type cfg_t is array (0 to N_CFG - 1) of std_logic_vector(15 downto 0);
    -- table : E : — → S : CFh ← 00h, D0h…FCh ← FFh, 28h ← 04h, 00h ← 00h, 03h ← 09h
    function table return cfg_t is
        variable t : cfg_t;
    begin
        t(0) := x"CF00";
        for i in 0 to 44 loop t(1 + i) := std_logic_vector(to_unsigned(16#D0# + i, 8)) & x"FF"; end loop;
        t(46) := x"2804";
        t(47) := x"0000";
        t(48) := x"0309";
        return t;
    end function;
    constant CFG : cfg_t := table;

    type etat_t is (E_ALIM, E_REVEIL, E_TX, E_PAUSE, E_ID0, E_ID1, E_CFG, E_ABS, E_SURV, E_LU88, E_SEL);
    type mode_t is (M_ACQ, M_VERR, M_PERTE);
    signal etat, apres : etat_t := E_ALIM;
    signal mode        : mode_t := M_ACQ;
    signal tempo       : natural range 0 to T_ABS := T_ALIM;
    signal scrut       : natural range 0 to T_SCRUT := 0;
    signal icfg        : natural range 0 to N_CFG - 1 := 0;
    signal n_stab      : natural range 0 to K_STAB := 0;
    signal n_ok        : natural range 0 to K_OK := 0;
    signal n_cpt       : natural range 0 to K_PERTE := 0;
    signal lance       : std_logic := '0';
    signal go, t_lire  : std_logic := '0';
    signal t_reg, t_val : std_logic_vector(7 downto 0) := (others => '0');
    signal i_occ, i_fini, i_ack : std_logic;
    signal i_lu        : std_logic_vector(7 downto 0);
    signal ent, vok, pres, resetb : std_logic := '0';
    signal i_raz, i_rst : std_logic := '0';
begin
    tvp_pdn    <= '1';
    tvp_resetb <= resetb;
    present    <= pres;
    video_ok   <= vok;
    entree     <= ent;
    i_rst      <= rst or i_raz;

    u_i2c : entity work.i2c_maitre generic map (G_QUART => G_HZ / (4 * G_I2C_HZ))
        port map (clk, i_rst, go, t_lire, t_reg, t_val, i_occ, i_fini, i_ack, i_lu, scl_oe, sda_oe, scl_i, sda_i);

    -- E : temps, résultats des transactions → T : démarrage, identification,
    --   configuration, surveillance du verrouillage, choix de l'entrée
    --   → S : RESETB, transactions, present, video_ok, entree
    process (clk)
        -- transaction : E : sens, registre, valeur, état de reprise
        --   → S : transaction lancée par E_TX, résultat lu en état « suite »
        procedure transaction(lr : std_logic; r, v : std_logic_vector(7 downto 0); suite : etat_t) is
        begin
            t_lire <= lr; t_reg <= r; t_val <= v; apres <= suite; lance <= '0'; etat <= E_TX;
        end procedure;
        -- choisir : E : entrée (0 = AIP1A) → S : écriture de 00h, puis acquisition
        procedure choisir(e : std_logic) is
        begin
            ent <= e;
            vok <= '0';
            transaction('0', x"00", "000000" & e & '0', E_SEL);
        end procedure;
        variable verrou : boolean;
        variable impose : boolean;                          -- entrée imposée par choix (01 : A, 10 : B)
    begin
        if rising_edge(clk) then
            go    <= '0';
            i_raz <= '0';
            impose := choix = "01" or choix = "10";
            if scrut /= 0 then scrut <= scrut - 1; end if;
            if rst = '1' then
                etat <= E_ALIM; tempo <= T_ALIM; resetb <= '0'; pres <= '0'; vok <= '0'; ent <= '0';
                mode <= M_ACQ; scrut <= 0; lance <= '0'; icfg <= 0;
                n_stab <= 0; n_ok <= 0; n_cpt <= 0;
            else
                case etat is
                    when E_ALIM =>
                        if tempo = 0 then resetb <= '1'; tempo <= T_REVEIL; etat <= E_REVEIL; else tempo <= tempo - 1; end if;
                    when E_REVEIL =>
                        if tempo = 0 then transaction('1', x"80", x"00", E_ID0); else tempo <= tempo - 1; end if;
                    when E_TX =>
                        -- garde : transaction bloquée → maître remis à zéro, décodeur
                        --   réputé absent, nouvelle identification puis configuration
                        if lance = '0' then
                            if i_occ = '0' then go <= '1'; lance <= '1'; tempo <= T_GARDE; end if;
                        elsif i_fini = '1' then
                            tempo <= T_ECART; etat <= E_PAUSE;
                        elsif tempo = 0 then
                            i_raz <= '1'; tempo <= T_ABS; etat <= E_ABS;
                        else
                            tempo <= tempo - 1;
                        end if;
                    when E_PAUSE =>
                        if tempo = 0 then etat <= apres; else tempo <= tempo - 1; end if;
                    when E_ID0 =>
                        if i_ack = '1' and i_lu = x"51" then transaction('1', x"81", x"00", E_ID1);
                        else tempo <= T_ABS; etat <= E_ABS;
                        end if;
                    when E_ID1 =>
                        if i_ack = '1' and i_lu = x"50" then
                            pres <= '1'; icfg <= 0;
                            transaction('0', CFG(0)(15 downto 8), CFG(0)(7 downto 0), E_CFG);
                        else
                            tempo <= T_ABS; etat <= E_ABS;
                        end if;
                    when E_CFG =>
                        if icfg = N_CFG - 1 then
                            ent <= '0'; mode <= M_ACQ; n_stab <= 0; n_ok <= 0; n_cpt <= 0;
                            scrut <= T_SCRUT; etat <= E_SURV;
                        else
                            icfg <= icfg + 1;
                            transaction('0', CFG(icfg + 1)(15 downto 8), CFG(icfg + 1)(7 downto 0), E_CFG);
                        end if;
                    when E_ABS =>
                        pres <= '0'; vok <= '0';
                        if tempo = 0 then transaction('1', x"80", x"00", E_ID0); else tempo <= tempo - 1; end if;
                    when E_SURV =>
                        if impose and ent /= choix(1) then
                            choisir(choix(1));
                        elsif scrut = 0 then
                            scrut <= T_SCRUT; transaction('1', x"88", x"00", E_LU88);
                        end if;
                    when E_LU88 =>
                        verrou := i_ack = '1' and i_lu(2 downto 1) = "11";
                        etat <= E_SURV;
                        case mode is
                            when M_ACQ =>
                                if n_stab < K_STAB then
                                    n_stab <= n_stab + 1;
                                elsif verrou and n_ok = K_OK - 1 then
                                    mode <= M_VERR; vok <= '1';
                                else
                                    if verrou then n_ok <= n_ok + 1; else n_ok <= 0; end if;
                                    if n_cpt /= K_ACQ - 1 then n_cpt <= n_cpt + 1;
                                    elsif impose then n_cpt <= 0;
                                    else choisir(not ent);
                                    end if;
                                end if;
                            when M_VERR =>
                                if not verrou then vok <= '0'; mode <= M_PERTE; n_cpt <= 1; n_ok <= 0; end if;
                            when M_PERTE =>
                                if verrou and n_ok = K_OK - 1 then
                                    mode <= M_VERR; vok <= '1';
                                else
                                    if verrou then n_ok <= n_ok + 1; else n_ok <= 0; end if;
                                    if n_cpt /= K_PERTE - 1 then n_cpt <= n_cpt + 1;
                                    elsif impose then n_cpt <= 0;
                                    else choisir('0');
                                    end if;
                                end if;
                        end case;
                    when E_SEL =>
                        mode <= M_ACQ; n_stab <= 0; n_ok <= 0; n_cpt <= 0; etat <= E_SURV;
                end case;
            end if;
        end if;
    end process;
end architecture rtl;

--------------------------------------------------------------------------------
-- dvbs_sd : émetteur de la mire animée aux bits sigma-delta : video_enc
--   (étapes 01 à 08) → dispersion → RS(204,188) → entrelaceur → codeur
--   convolutif → sigma_delta ; chaque bloc est vérifié au bit près par son
--   banc (video, chaine, sdm)
--   Interface : horloge 80 MHz (10 MS/s) ; sortie : 8 bits sigma-delta par
--               cycle et par voie (m_i, m_q, bit 7 émis en premier), vers les
--               sérialiseurs LVDS (640 Mbit/s)
--   Principe : la sortie sigma-delta impose le rythme (un symbole par 8
--              cycles) ; le contrôle de flux remonte jusqu'au multiplexeur TS ;
--              bit du codeur à 1 → symbole −1 (bit de signe de qpsk_map),
--              convention de l'entrée de sigma_delta
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.dvbs_pkg.all;

entity dvbs_sd is
    generic (
        G_IMAGES : natural := 0;
        G_FEC    : natural range 0 to 4 := 0
    );
    port (
        clk     : in  std_logic;
        rst     : in  std_logic;
        m_valid : out std_logic;
        m_ready : in  std_logic;
        m_i     : out std_logic_vector(7 downto 0);
        m_q     : out std_logic_vector(7 downto 0)
    );
end entity dvbs_sd;

architecture rtl of dvbs_sd is
    signal t_valid, t_ready, t_sop : std_logic;
    signal t_data                  : octet_t;
    signal p_valid, p_ready, p_sop : std_logic;
    signal p_data                  : octet_t;
    signal r_valid, r_ready, r_sop : std_logic;
    signal r_data                  : octet_t;
    signal e_valid, e_ready, e_sop : std_logic;
    signal e_data                  : octet_t;
    signal c_valid, c_ready        : std_logic;
    signal c_data                  : std_logic_vector(1 downto 0);
begin
    u_video : entity work.video_enc generic map (G_IMAGES => G_IMAGES, G_T => budget_image(10_000_000, G_FEC, 95, 25))
        port map (clk, rst, t_valid, t_ready, t_data, t_sop);
    u_prbs : entity work.prbs_disp
        port map (clk, rst, t_valid, t_ready, t_data, t_sop, p_valid, p_ready, p_data, p_sop);
    u_rs : entity work.rs_enc
        port map (clk, rst, p_valid, p_ready, p_data, p_sop, r_valid, r_ready, r_data, r_sop);
    u_inter : entity work.interleaver
        port map (clk, rst, r_valid, r_ready, r_data, r_sop, e_valid, e_ready, e_data, e_sop);
    u_conv : entity work.conv_enc generic map (G_FEC => G_FEC)
        port map (clk, rst, e_valid, e_ready, e_data, c_valid, c_ready, c_data);
    u_sd : entity work.sigma_delta
        port map (clk, rst, c_valid, c_ready, c_data(1), c_data(0), m_valid, m_ready, m_i, m_q);
end architecture rtl;

--------------------------------------------------------------------------------
-- regs_i2c : esclave I²C (adresse 7 bits G_ADR, 2Ah par défaut) et banc de
--   registres de réglage, écrits par le microcontrôleur de la carte ;
--   banc : tb_top
--   Registres : 00h identifiant 4Ah (lecture seule) ; 01h version 01h
--               (lecture seule) ; 02h MODE : bit 0 DVB-S2, bits 3..1 FEC
--               (0 = 1/2 … 4 = 7/8), bit 4 débit 2,5 MS/s (sinon 10 MS/s),
--               défaut 00h ; 03h ENTREE : bits 1..0 : 0 automatique, 1 AIP1A,
--               2 AIP1B, 3 mire, défaut 00h ; 04h ETAT (lecture seule) :
--               entrée etat ; autres adresses : lues 00h, écritures ignorées
--   Protocole : écriture : S, adresse + 0, registre, données… (pointeur
--               incrémenté après chaque octet), P ; lecture : S, adresse + 0,
--               registre, Sr, adresse + 1, données… jusqu'au NACK, P
--   Principe : SCL et SDA synchronisés et filtrés (3 échantillons égaux) ;
--              SDA retardé de 4 cycles de plus que SCL (début et fin jamais
--              confondus avec un bit, même sans temps de maintien) ; bits lus
--              au front montant de SCL, SDA posé au front descendant ; pas
--              d'étirement de SCL (SCL en entrée seule)
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity regs_i2c is
    generic (
        G_ADR : std_logic_vector(6 downto 0) := "0101010"     -- 2Ah
    );
    port (
        clk    : in  std_logic;
        rst    : in  std_logic;
        scl_i  : in  std_logic;
        sda_i  : in  std_logic;
        sda_oe : out std_logic;
        etat   : in  std_logic_vector(7 downto 0);
        mode   : out std_logic_vector(7 downto 0);
        entree : out std_logic_vector(7 downto 0)
    );
end entity regs_i2c;

architecture rtl of regs_i2c is
    type st_t is (S_LIBRE, S_ADR, S_REG, S_ECR, S_LEC);
    signal st          : st_t := S_LIBRE;
    signal scl_s       : std_logic_vector(4 downto 0) := (others => '1');   -- 2 synchronisation + 3 filtre
    signal sda_s       : std_logic_vector(8 downto 0) := (others => '1');   -- 2 + 4 de retard + 3 filtre
    signal scl, sda    : std_logic := '1';                                  -- lignes filtrées
    signal scl_d, sda_d : std_logic := '1';                                 -- valeurs filtrées précédentes
    signal nb          : natural range 0 to 9 := 0;                         -- fronts montants dans l'octet
    signal sh          : std_logic_vector(7 downto 0) := (others => '0');
    signal tx          : std_logic_vector(7 downto 0) := (others => '0');
    signal ptr         : unsigned(7 downto 0) := (others => '0');
    signal m_ack, prem : std_logic := '0';
    signal oe          : std_logic := '0';
    signal r_mode      : std_logic_vector(7 downto 0) := x"00";
    signal r_entree    : std_logic_vector(7 downto 0) := x"00";

    -- lire : E : adresse, registres → S : octet lu
    function lire(a : unsigned(7 downto 0); m, e, et : std_logic_vector(7 downto 0)) return std_logic_vector is
    begin
        case to_integer(a) is
            when 0      => return x"4A";
            when 1      => return x"01";
            when 2      => return m;
            when 3      => return e;
            when 4      => return et;
            when others => return x"00";
        end case;
    end function;
begin
    sda_oe <= oe;
    mode   <= r_mode;
    entree <= r_entree;

    -- E : SCL, SDA, état → T : filtrage, début / fin, octets reçus et émis,
    --   acquittements, registres → S : SDA tiré, registres
    process (clk)
        variable scl_m : std_logic;
        variable b                   : std_logic_vector(7 downto 0);
    begin
        if rising_edge(clk) then
            scl_s <= scl_s(3 downto 0) & scl_i;
            sda_s <= sda_s(7 downto 0) & sda_i;
            scl_d <= scl;
            sda_d <= sda;
            if scl_s(4 downto 2) = "111" then scl_m := '1'; elsif scl_s(4 downto 2) = "000" then scl_m := '0'; else scl_m := scl; end if;
            scl <= scl_m;
            if sda_s(8 downto 6) = "111" then sda <= '1'; elsif sda_s(8 downto 6) = "000" then sda <= '0'; end if;
            if rst = '1' then
                st <= S_LIBRE; oe <= '0'; nb <= 0; ptr <= (others => '0');
                r_mode <= x"00"; r_entree <= x"00";
            elsif scl = '1' and scl_d = '1' and sda_d = '1' and sda = '0' then
                st <= S_ADR; nb <= 0; oe <= '0';                    -- début (ou début répété)
            elsif scl = '1' and scl_d = '1' and sda_d = '0' and sda = '1' then
                st <= S_LIBRE; oe <= '0';                           -- fin
            elsif st /= S_LIBRE then
                if scl_d = '0' and scl = '1' then
                    -- front montant : bit reçu ou acquittement du maître
                    if nb < 8 then sh <= sh(6 downto 0) & sda; end if;
                    if nb = 8 then m_ack <= not sda; end if;
                    nb <= nb + 1;
                elsif scl_d = '1' and scl = '0' then
                    -- front descendant : SDA pour la tranche suivante
                    if nb = 8 then
                        if st = S_LEC then
                            oe <= '0';                              -- acquittement du maître
                        else
                            case st is
                                when S_ADR =>
                                    if sh(7 downto 1) = G_ADR then
                                        oe <= '1';
                                        if sh(0) = '1' then st <= S_LEC; prem <= '1'; else st <= S_REG; end if;
                                    else
                                        st <= S_LIBRE;
                                    end if;
                                when S_REG =>
                                    ptr <= unsigned(sh); oe <= '1'; st <= S_ECR;
                                when others =>
                                    case to_integer(ptr) is
                                        when 2      => r_mode   <= sh and x"1F";
                                        when 3      => r_entree <= sh and x"03";
                                        when others => null;
                                    end case;
                                    ptr <= ptr + 1; oe <= '1';
                            end case;
                        end if;
                    elsif nb = 9 then
                        nb <= 0; oe <= '0';
                        if st = S_LEC then
                            if prem = '1' or m_ack = '1' then
                                b := lire(ptr, r_mode, r_entree, etat);
                                tx <= b; oe <= not b(7); ptr <= ptr + 1; prem <= '0';
                            else
                                st <= S_LIBRE;                      -- NACK du maître : fin de lecture
                            end if;
                        end if;
                    elsif st = S_LEC and nb >= 1 and nb <= 7 then
                        oe <= not tx(7 - nb);
                    end if;
                end if;
            end if;
        end if;
    end process;
end architecture rtl;

--------------------------------------------------------------------------------
-- jpeg2dvb_top : entité de tête de la carte (MPF100T-FCG484I) ; banc : tb_top
--   Horloges : oscillateur MEMS 50 MHz → horloges (PLL) : clk_sys 80 MHz,
--              clk_hs 320 MHz (sérialiseurs), clk_tvp 14,31818 MHz (XTAL1 du
--              décodeur) ; tvp_sclk 27 MHz (décodeur) pour bt656_rx
--   Ports : osc_50 ; tvp_* : décodeur TVP5150AM1 (XTAL1, RESETB, PDN, bus
--           I²C maître, SCLK, YOUT) ; mcu_scl, mcu_sda : bus I²C du
--           microcontrôleur (FPGA esclave 2Ah, regs_i2c) ; sd_i_p/n, sd_q_p/n :
--           sorties LVDS sigma-delta 640 Mbit/s ; led_pll, led_tvp, led_video :
--           PLL verrouillés, décodeur présent, vidéo verrouillée (actives à 1)
--   Principe : remise à zéro tenue tant que les PLL ne sont pas verrouillés,
--              relâchée de façon synchrone (8 cycles) ; registre ENTREE →
--              choix de tvp_ctrl (1 : AIP1A, 2 : AIP1B, 0 et 3 : automatique ;
--              3 : mire imposée, réservé à la sélection de source du chantier
--              3b) ; registre MODE rangé, branché aux chantiers FEC, débit et
--              DVB-S2 ; source : mire animée (dvbs_sd, DVB-S, FEC 1/2, 10 MS/s) ;
--              sigma-delta au repos (01010101) avant le premier symbole
--   Paramètres : G_TVP_HZ : horloge vue par tvp_ctrl (80 MHz ; réduite en
--                simulation pour raccourcir les délais du décodeur)
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity jpeg2dvb_top is
    generic (
        G_TVP_HZ : positive := 80_000_000
    );
    port (
        osc_50     : in    std_logic;
        tvp_xtal1  : out   std_logic;
        tvp_resetb : out   std_logic;
        tvp_pdn    : out   std_logic;
        tvp_scl    : inout std_logic;
        tvp_sda    : inout std_logic;
        tvp_sclk   : in    std_logic;
        tvp_d      : in    std_logic_vector(7 downto 0);
        mcu_scl    : in    std_logic;
        mcu_sda    : inout std_logic;
        sd_i_p     : out   std_logic;
        sd_i_n     : out   std_logic;
        sd_q_p     : out   std_logic;
        sd_q_n     : out   std_logic;
        led_pll    : out   std_logic;
        led_tvp    : out   std_logic;
        led_video  : out   std_logic
    );
end entity jpeg2dvb_top;

architecture rtl of jpeg2dvb_top is
    component horloges is
        port (
            osc_50  : in  std_logic;
            clk_sys : out std_logic;
            clk_hs  : out std_logic;
            clk_tvp : out std_logic;
            verrou  : out std_logic
        );
    end component;
    component sortie_lvds is
        port (
            clk_sys : in  std_logic;
            clk_hs  : in  std_logic;
            rst     : in  std_logic;
            d_i     : in  std_logic_vector(7 downto 0);
            d_q     : in  std_logic_vector(7 downto 0);
            i_p     : out std_logic;
            i_n     : out std_logic;
            q_p     : out std_logic;
            q_n     : out std_logic
        );
    end component;

    signal clk_sys, clk_hs, clk_tvp, verrou : std_logic;
    signal raz_sys    : std_logic_vector(7 downto 0) := (others => '1');
    signal raz_sclk   : std_logic_vector(2 downto 0) := (others => '1');
    signal rst, rst_sclk : std_logic;
    signal pll_s      : std_logic_vector(1 downto 0) := "00";
    signal sd_valid   : std_logic;
    signal sd_i, sd_q : std_logic_vector(7 downto 0);
    signal s_i, s_q   : std_logic_vector(7 downto 0);
    signal t_scl_oe, t_sda_oe, m_sda_oe : std_logic;
    signal t_scl_i, t_sda_i, m_scl_i, m_sda_i : std_logic;
    signal present, video_ok, entree   : std_logic;
    signal r_mode, r_entree, etat      : std_logic_vector(7 downto 0);
    signal choix      : std_logic_vector(1 downto 0);
    signal mire_imposee : std_logic;
    signal b_valid, b_trame, b_dt, b_sync : std_logic;
    signal b_cb, b_y0, b_cr, b_y1 : std_logic_vector(7 downto 0);
    signal b_ligne, b_x : unsigned(8 downto 0);
begin
    u_horl : horloges port map (osc_50, clk_sys, clk_hs, clk_tvp, verrou);
    tvp_xtal1 <= clk_tvp;

    -- remise à zéro : E : verrouillage des PLL → T : mise à 1 immédiate,
    --   relâchement synchrone après 8 cycles → S : rst (clk_sys), rst_sclk
    --   (tvp_sclk)
    process (clk_sys, verrou)
    begin
        if verrou = '0' then
            raz_sys <= (others => '1');
        elsif rising_edge(clk_sys) then
            raz_sys <= raz_sys(6 downto 0) & '0';
        end if;
    end process;
    rst <= raz_sys(7);
    process (tvp_sclk, rst)
    begin
        if rst = '1' then
            raz_sclk <= (others => '1');
        elsif rising_edge(tvp_sclk) then
            raz_sclk <= raz_sclk(1 downto 0) & '0';
        end if;
    end process;
    rst_sclk <= raz_sclk(2);

    -- chaîne d'émission et sorties LVDS (repos 01010101 avant le premier symbole)
    u_tx : entity work.dvbs_sd port map (clk_sys, rst, sd_valid, '1', sd_i, sd_q);
    s_i <= sd_i when sd_valid = '1' else "01010101";
    s_q <= sd_q when sd_valid = '1' else "01010101";
    u_lvds : sortie_lvds port map (clk_sys, clk_hs, rst, s_i, s_q, sd_i_p, sd_i_n, sd_q_p, sd_q_n);

    -- décodeur vidéo : pilotage I²C (drain ouvert) et réception BT.656
    u_tvp : entity work.tvp_ctrl generic map (G_HZ => G_TVP_HZ, G_I2C_HZ => 100_000)
        port map (clk_sys, rst, tvp_resetb, tvp_pdn, t_scl_oe, t_sda_oe, t_scl_i, t_sda_i,
                  present, video_ok, entree, choix);
    t_scl_i <= to_x01(tvp_scl);
    t_sda_i <= to_x01(tvp_sda);
    tvp_scl <= '0' when t_scl_oe = '1' else 'Z';
    tvp_sda <= '0' when t_sda_oe = '1' else 'Z';
    u_bt656 : entity work.bt656_rx
        port map (tvp_sclk, rst_sclk, tvp_d, b_valid, b_cb, b_y0, b_cr, b_y1, b_trame, b_ligne, b_x, b_dt, b_sync);

    -- registres du microcontrôleur
    process (clk_sys)
    begin
        if rising_edge(clk_sys) then
            pll_s <= pll_s(0) & verrou;
        end if;
    end process;
    etat <= "0000" & entree & video_ok & present & pll_s(1);
    u_regs : entity work.regs_i2c port map (clk_sys, rst, m_scl_i, m_sda_i, m_sda_oe, etat, r_mode, r_entree);
    m_scl_i <= to_x01(mcu_scl);
    m_sda_i <= to_x01(mcu_sda);
    mcu_sda <= '0' when m_sda_oe = '1' else 'Z';
    choix <= "01" when r_entree(1 downto 0) = "01" else
             "10" when r_entree(1 downto 0) = "10" else "00";
    mire_imposee <= '1' when r_entree(1 downto 0) = "11" else '0';

    led_pll   <= pll_s(1);
    led_tvp   <= present;
    led_video <= video_ok;
end architecture rtl;
