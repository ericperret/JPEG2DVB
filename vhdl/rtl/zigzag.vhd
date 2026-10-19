--==============================================================================
--  Nom        : zigzag.vhd
--  Projet     : JPEG2DVB, portage FPGA (émetteur DVB-S 23 cm)
--  Objet      : balayage zigzag (alternate_scan = 0) d'un bloc de 64
--               coefficients ; référence bit à bit : JPEG2DVB étape 04
--  Auteur     : Eric PERRET
--  Date       : 2026-10-19
--  Version    : 1.0
--  Plateforme : VHDL-2008, synthétisable (Libero SoC)
--  Licence    : CC BY-NC 4.0
--  Interface  : entrée : 64 coefficients en ordre naturel ; sortie : les mêmes
--               en ordre zigzag (sortie i = entrée ZZ(i))
--  Principe   : deux mémoires de bloc en alternance : un bloc se charge
--               pendant que le précédent sort, un coefficient par cycle
--  Historique : 1.0  2026-10-19  création
--==============================================================================
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
