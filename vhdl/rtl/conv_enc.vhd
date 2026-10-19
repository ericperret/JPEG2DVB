--==============================================================================
--  Nom        : conv_enc.vhd
--  Projet     : JPEG2DVB, portage FPGA (émetteur DVB-S 23 cm)
--  Objet      : codeur convolutif K = 7, G1 = 171, G2 = 133 (octal), poinçonnage
--               1/2, 2/3, 3/4, 5/6, 7/8 (EN 300 421 § 4.4.3, tableau 2) ;
--               référence bit à bit : JPEG2DVB étape 12
--  Auteur     : Eric PERRET
--  Date       : 2026-10-19
--  Version    : 1.0
--  Plateforme : VHDL-2008, synthétisable (Libero SoC)
--  Licence    : CC BY-NC 4.0
--  Interface  : entrée : octets (valid / ready), premier bit en poids fort ;
--               sortie : paires de bits (m_data(1) = I, m_data(0) = Q), une paire
--               par symbole QPSK
--  Principe   : un bit d'entrée par cycle ; X et Y retenus selon le motif de
--               poinçonnage, dans l'ordre X puis Y de chaque instant ; les bits
--               retenus sont regroupés deux par deux (I puis Q). Registre : D0
--               (bit précédent) en bit 5, D5 en bit 0.
--  Paramètre  : G_FEC 0 = 1/2, 1 = 2/3, 2 = 3/4, 3 = 5/6, 4 = 7/8
--  Historique : 1.0  2026-10-19  création
--==============================================================================
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
