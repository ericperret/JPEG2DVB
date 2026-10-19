--==============================================================================
--  Nom        : qpsk_map.vhd
--  Projet     : JPEG2DVB, portage FPGA (émetteur DVB-S 23 cm)
--  Objet      : mise en correspondance QPSK (EN 300 421 § 4.5, figure 6) :
--               bit 0 → +1, bit 1 → −1 sur chaque voie ; référence bit à bit :
--               JPEG2DVB étape 13 (symboles entiers ±1)
--  Auteur     : Eric PERRET
--  Date       : 2026-10-19
--  Version    : 1.0
--  Plateforme : VHDL-2008, synthétisable (Libero SoC)
--  Licence    : CC BY-NC 4.0
--  Interface  : entrée : paire de bits (s_data(1) = I, s_data(0) = Q) ;
--               sortie : I et Q signés sur 2 bits (+1 = "01", −1 = "11") ;
--               combinatoire, le contrôle de flux traverse le module
--  Historique : 1.0  2026-10-19  création
--==============================================================================
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
