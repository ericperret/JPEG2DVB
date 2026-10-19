--==============================================================================
--  Nom        : rs_enc.vhd
--  Projet     : JPEG2DVB, portage FPGA (émetteur DVB-S 23 cm)
--  Objet      : codeur Reed-Solomon RS(204,188) raccourci, t = 8 (EN 300 421
--               § 4.4.2) ; référence bit à bit : JPEG2DVB étape 10
--  Auteur     : Eric PERRET
--  Date       : 2026-10-19
--  Version    : 1.0
--  Plateforme : VHDL-2008, synthétisable (Libero SoC)
--  Licence    : CC BY-NC 4.0
--  Interface  : entrée : paquets de 188 octets (s_sop sur le 1er) ; sortie :
--               paquets de 204 octets, les 16 octets de parité suivent les données
--  Principe   : division de m(x)·x¹⁶ par g(x) dans un registre de 16 octets ;
--               parité émise du coefficient de plus haut degré au plus bas ;
--               l'entrée est suspendue (s_ready = 0) pendant les 16 octets de parité
--  Historique : 1.0  2026-10-19  création
--==============================================================================
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
