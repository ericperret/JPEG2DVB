--==============================================================================
--  Nom        : jpeg2dvb_ip_sim.vhd
--  Projet     : JPEG2DVB, portage FPGA (émetteur DVB-S 23 cm)
--  Objet      : modèles de simulation (GHDL) des trois cœurs créés dans le
--               catalogue Libero : PF_CCC_SYS, PF_CCC_TVP (PLL) et PF_IOD_TX_SD
--               (sérialiseurs PF_IOD_GENERIC_TX) ; liés par jpeg2dvb_fpga.vhd
--               (horloges, sortie_lvds)
--  Auteur     : Eric PERRET
--  Date       : 2026-11-12
--  Version    : 2.0
--  Plateforme : VHDL-2008, simulation seule ; analyser après jpeg2dvb_fpga.vhd
--  Licence    : CC BY-NC 4.0
--  Contenu    : PF_CCC_SYS    80 MHz, 320 MHz, verrouillage à 20 µs
--               PF_CCC_TVP    14,31818 MHz, verrouillage à 20 µs
--               PF_IOD_TX_SD  8 bits par cycle et par voie, TX_DATA(0) en
--                             premier, 1,5625 ns par bit (640 Mbit/s)
--  Historique : 1.0  2026-11-10  modèles de horloges et sortie_lvds
--               2.0  2026-11-12  modèles des cœurs Libero ; horloges et
--                                sortie_lvds passent dans jpeg2dvb_fpga.vhd
--==============================================================================

--------------------------------------------------------------------------------
-- PF_CCC_SYS : clk 80 MHz et HS_IO_CLK 320 MHz alignées ; verrou après 20 µs
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;

entity PF_CCC_SYS is
    port (
        REF_CLK_0        : in  std_logic;
        OUT0_FABCLK_0    : out std_logic;
        OUT1_HS_IO_CLK_0 : out std_logic;
        PLL_LOCK_0       : out std_logic
    );
end entity PF_CCC_SYS;

architecture sim of PF_CCC_SYS is
    signal hs, sys : std_logic := '0';
begin
    hs  <= not hs after 1.5625 ns;
    sys <= not sys after 6.25 ns;
    OUT0_FABCLK_0    <= sys;
    OUT1_HS_IO_CLK_0 <= hs;
    PLL_LOCK_0       <= '0', '1' after 20 us;
end architecture sim;

--------------------------------------------------------------------------------
-- PF_CCC_TVP : 14,31818 MHz ; verrou après 20 µs
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;

entity PF_CCC_TVP is
    port (
        REF_CLK_0     : in  std_logic;
        OUT0_FABCLK_0 : out std_logic;
        PLL_LOCK_0    : out std_logic
    );
end entity PF_CCC_TVP;

architecture sim of PF_CCC_TVP is
    signal tvp : std_logic := '0';
begin
    tvp <= not tvp after 34.920635 ns;                   -- 14,31818 MHz (22 / 315 µs)
    OUT0_FABCLK_0 <= tvp;
    PLL_LOCK_0    <= '0', '1' after 20 us;
end architecture sim;

--------------------------------------------------------------------------------
-- PF_IOD_TX_SD : à chaque front montant de TX_CLK_G, les 8 bits de chaque voie
--   sont émis TX_DATA(0) en premier, 1,5625 ns par bit ; sorties
--   complémentaires ; 0 pendant ARST_N = 0
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;

entity PF_IOD_TX_SD is
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
end entity PF_IOD_TX_SD;

architecture sim of PF_IOD_TX_SD is
    constant T  : time := 1.5625 ns;
    signal s0, s1 : std_logic := '0';
begin
    TXD   <= s1 & s0;
    TXD_N <= (not s1) & (not s0);

    -- E : groupes de 8 bits → T : forme d'onde de 8 bits par front de TX_CLK_G
    --   → S : voies série
    process (TX_CLK_G)
        variable a, b : std_logic_vector(7 downto 0);
    begin
        if rising_edge(TX_CLK_G) then
            if ARST_N = '0' then a := x"00"; b := x"00"; else a := TX_DATA_0; b := TX_DATA_1; end if;
            s0 <= transport a(0), a(1) after T, a(2) after 2 * T, a(3) after 3 * T,
                            a(4) after 4 * T, a(5) after 5 * T, a(6) after 6 * T, a(7) after 7 * T;
            s1 <= transport b(0), b(1) after T, b(2) after 2 * T, b(3) after 3 * T,
                            b(4) after 4 * T, b(5) after 5 * T, b(6) after 6 * T, b(7) after 7 * T;
        end if;
    end process;
end architecture sim;
