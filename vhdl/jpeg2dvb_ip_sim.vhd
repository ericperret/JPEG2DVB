--==============================================================================
--  Nom        : jpeg2dvb_ip_sim.vhd
--  Projet     : JPEG2DVB, portage FPGA (émetteur DVB-S 23 cm)
--  Objet      : modèles de simulation (GHDL) des blocs Libero de la carte :
--               horloges (deux PLL PF_CCC) et sortie_lvds (sérialiseurs
--               PF_IOD_GENERIC_TX) ; mêmes entités que jpeg2dvb_ip_libero.vhd,
--               qui les remplace dans Libero
--  Auteur     : Eric PERRET
--  Date       : 2026-11-10
--  Version    : 1.0
--  Plateforme : VHDL-2008, simulation seule ; analyser après jpeg2dvb_fpga.vhd
--  Licence    : CC BY-NC 4.0
--  Contenu    : horloges      80 MHz, 320 MHz, 14,31818 MHz, verrouillage à 20 µs
--               sortie_lvds   8 bits par cycle et par voie, bit 7 en premier,
--                             1,5625 ns par bit (640 Mbit/s)
--  Historique : 1.0  2026-11-10  création (chantier 6, entité de tête)
--==============================================================================

--------------------------------------------------------------------------------
-- horloges : modèle des deux PLL : clk_sys 80 MHz et clk_hs 320 MHz alignées,
--   clk_tvp 14,31818 MHz ; verrou à 1 après 20 µs ; osc_50 ignoré
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

architecture sim of horloges is
    signal hs, sys, tvp : std_logic := '0';
begin
    hs  <= not hs after 1.5625 ns;
    sys <= not sys after 6.25 ns;
    tvp <= not tvp after 34.920635 ns;                   -- 14,31818 MHz (22 / 315 µs)
    clk_hs  <= hs;
    clk_sys <= sys;
    clk_tvp <= tvp;
    verrou  <= '0', '1' after 20 us;
end architecture sim;

--------------------------------------------------------------------------------
-- sortie_lvds : modèle des deux sérialiseurs 8:1 : à chaque front montant de
--   clk_sys, les 8 bits présents sur d_i et d_q sont émis bit 7 en premier,
--   1,5625 ns par bit ; sorties complémentaires ; 0 pendant rst
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

architecture sim of sortie_lvds is
    constant T  : time := 1.5625 ns;
    signal si, sq : std_logic := '0';
begin
    i_p <= si; i_n <= not si;
    q_p <= sq; q_n <= not sq;

    -- E : groupes de 8 bits → T : forme d'onde de 8 bits par front de clk_sys
    --   → S : voies série
    process (clk_sys)
        variable a, b : std_logic_vector(7 downto 0);
    begin
        if rising_edge(clk_sys) then
            if rst = '1' then a := x"00"; b := x"00"; else a := d_i; b := d_q; end if;
            si <= transport a(7), a(6) after T, a(5) after 2 * T, a(4) after 3 * T,
                            a(3) after 4 * T, a(2) after 5 * T, a(1) after 6 * T, a(0) after 7 * T;
            sq <= transport b(7), b(6) after T, b(5) after 2 * T, b(4) after 3 * T,
                            b(3) after 4 * T, b(2) after 5 * T, b(1) after 6 * T, b(0) after 7 * T;
        end if;
    end process;
end architecture sim;
