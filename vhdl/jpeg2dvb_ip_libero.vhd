--==============================================================================
--  Nom        : jpeg2dvb_ip_libero.vhd
--  Projet     : JPEG2DVB, portage FPGA (émetteur DVB-S 23 cm)
--  Objet      : enveloppes des blocs générés par le catalogue Libero pour
--               jpeg2dvb_top : horloges (PF_CCC_SYS, PF_CCC_TVP) et
--               sortie_lvds (PF_IOD_TX_SD) ; à importer dans Libero à la place
--               de jpeg2dvb_ip_sim.vhd (modèles GHDL des mêmes entités)
--  Auteur     : Eric PERRET
--  Date       : 2026-11-10
--  Version    : 1.0
--  Plateforme : Libero SoC, PolarFire MPF100T-FCG484I
--  Licence    : CC BY-NC 4.0
--  Blocs      : PF_CCC_SYS   : PLL, référence 50 MHz ; sortie 0 : 80 MHz
--                              (horloge globale) ; sortie 1 : 320 MHz (HS_IO_CLK
--                              des sérialiseurs), même PLL
--               PF_CCC_TVP   : PLL, référence 50 MHz ; sortie 0 : 14,318182 MHz
--                              (VCO 1 575 MHz, division 110)
--               PF_IOD_TX_SD : PF_IOD_GENERIC_TX, interface TX_DDRX_B_G_FA
--                              (DDR, 8 bits par cycle), 2 voies (0 : I, 1 : Q),
--                              sans horloge transmise, LVDS en banque GPIO
--  Remarques  : noms de ports des composants à confronter aux déclarations
--               générées par Libero (component/hdl/*.vhd) ; ordre des bits :
--               TX_DATA(0) supposé émis en premier, d'où l'inversion des bits
--               (sigma_delta émet le bit 7 en premier)
--  Historique : 1.0  2026-11-10  création (chantier 6, entité de tête)
--==============================================================================

--------------------------------------------------------------------------------
-- horloges : deux PLL depuis l'oscillateur 50 MHz ; verrou : les deux PLL
--   verrouillés
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;

entity horloges is
    port (
        osc_50  : in  std_logic;
        clk_sys : out std_logic;
        clk_hs  : out std_logic;
        clk_tvp : out std_logic;
        verrou  : out std_logic
    );
end entity horloges;

architecture libero of horloges is
    component PF_CCC_SYS is
        port (
            REF_CLK_0        : in  std_logic;
            OUT0_FABCLK_0    : out std_logic;
            OUT1_HS_IO_CLK_0 : out std_logic;
            PLL_LOCK_0       : out std_logic
        );
    end component;
    component PF_CCC_TVP is
        port (
            REF_CLK_0     : in  std_logic;
            OUT0_FABCLK_0 : out std_logic;
            PLL_LOCK_0    : out std_logic
        );
    end component;
    signal v_sys, v_tvp : std_logic;
begin
    u_sys : PF_CCC_SYS port map (REF_CLK_0 => osc_50, OUT0_FABCLK_0 => clk_sys, OUT1_HS_IO_CLK_0 => clk_hs, PLL_LOCK_0 => v_sys);
    u_tvp : PF_CCC_TVP port map (REF_CLK_0 => osc_50, OUT0_FABCLK_0 => clk_tvp, PLL_LOCK_0 => v_tvp);
    verrou <= v_sys and v_tvp;
end architecture libero;

--------------------------------------------------------------------------------
-- sortie_lvds : sérialiseurs 8:1 des voies I et Q (640 Mbit/s) ; d_i, d_q :
--   bit 7 émis en premier
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;

entity sortie_lvds is
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
end entity sortie_lvds;

architecture libero of sortie_lvds is
    component PF_IOD_TX_SD is
        port (
            TX_CLK_G        : in  std_logic;
            HS_IO_CLK       : in  std_logic;
            ARST_N          : in  std_logic;
            HS_IO_CLK_PAUSE : in  std_logic;
            TX_DATA_0       : in  std_logic_vector(7 downto 0);
            TX_DATA_1       : in  std_logic_vector(7 downto 0);
            TXD             : out std_logic_vector(1 downto 0);
            TXD_N           : out std_logic_vector(1 downto 0)
        );
    end component;
    signal r_i, r_q   : std_logic_vector(7 downto 0);
    signal txd, txd_n : std_logic_vector(1 downto 0);
    signal arst_n     : std_logic;
begin
    -- inversion : bit 7 de sigma_delta → TX_DATA(0), émis en premier
    g : for k in 0 to 7 generate
        r_i(k) <= d_i(7 - k);
        r_q(k) <= d_q(7 - k);
    end generate;
    arst_n <= not rst;
    u_iod : PF_IOD_TX_SD port map (TX_CLK_G => clk_sys, HS_IO_CLK => clk_hs, ARST_N => arst_n, HS_IO_CLK_PAUSE => '0',
                                   TX_DATA_0 => r_i, TX_DATA_1 => r_q, TXD => txd, TXD_N => txd_n);
    i_p <= txd(0); i_n <= txd_n(0);
    q_p <= txd(1); q_n <= txd_n(1);
end architecture libero;
