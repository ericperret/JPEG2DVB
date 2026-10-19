--==============================================================================
--  Nom        : bit_packer.vhd
--  Projet     : JPEG2DVB, portage FPGA (émetteur DVB-S 23 cm)
--  Objet      : mise bout à bout de mots binaires de longueur variable (0 à 32
--               bits, cadrés à droite) en octets, poids fort en tête, avec
--               alignement sur l'octet à la demande (bits de bourrage à 0)
--  Auteur     : Eric PERRET
--  Date       : 2026-10-19
--  Version    : 1.0
--  Plateforme : VHDL-2008, synthétisable (Libero SoC)
--  Licence    : CC BY-NC 4.0
--  Interface  : entrée : s_code, s_lg, s_align (aligner après ce mot) ;
--               sortie : octets (valid / ready)
--  Principe   : accumulateur de 64 bits ; un mot accepté si au plus 24 bits
--               attendent ; un octet sort par cycle dès que 8 bits sont prêts
--  Historique : 1.0  2026-10-19  création
--==============================================================================
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
