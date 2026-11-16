--==============================================================================
--  Nom        : sonde.vhd
--  Projet     : JPEG2DVB, portage FPGA (émetteur DVB-S 23 cm)
--  Objet      : design minimal (une bascule) placé et routé par
--               jpeg2dvb_libero.tcl sur le MPF050T-FCVG484 pour obtenir de
--               Libero la table des broches du boîtier (rapport de broches)
--  Auteur     : Eric PERRET
--  Date       : 2026-11-16
--  Version    : 1.0
--  Plateforme : VHDL-2008, synthétisable (Libero SoC)
--  Licence    : CC BY-NC 4.0
--  Historique : 1.0  2026-11-16  création
--==============================================================================
library ieee;
use ieee.std_logic_1164.all;

entity sonde is
    port (
        clk : in  std_logic;
        q   : out std_logic
    );
end entity sonde;

architecture rtl of sonde is
    signal r : std_logic := '0';
begin
    process (clk)
    begin
        if rising_edge(clk) then
            r <= not r;
        end if;
    end process;
    q <= r;
end architecture rtl;
