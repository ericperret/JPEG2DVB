--==============================================================================
--  Nom        : prbs_disp.vhd
--  Projet     : JPEG2DVB, portage FPGA (émetteur DVB-S 23 cm)
--  Objet      : dispersion d'énergie DVB-S (EN 300 421 § 4.4.1), un octet par
--               cycle ; référence bit à bit : JPEG2DVB étape 09
--  Auteur     : Eric PERRET
--  Date       : 2026-10-19
--  Version    : 1.0
--  Plateforme : VHDL-2008, synthétisable (Libero SoC)
--  Licence    : CC BY-NC 4.0
--  Interface  : flux d'octets valid / ready ; s_sop = 1er octet (synchro 0x47)
--               de chaque paquet TS de 188 octets
--  Principe   : groupes de 8 paquets ; paquet 0 : synchro remplacée par 0xB8 et
--               générateur réinitialisé ; paquets 1 à 7 : synchro inchangée, le
--               générateur tourne 8 pas sans être appliqué ; octets 1 à 187 :
--               ou exclusif avec 8 bits de sortie du générateur
--  Historique : 1.0  2026-10-19  création
--==============================================================================
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
