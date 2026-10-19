--==============================================================================
--  Nom        : interleaver.vhd
--  Projet     : JPEG2DVB, portage FPGA (émetteur DVB-S 23 cm)
--  Objet      : entrelaceur convolutif de Forney, I = 12 branches, M = 17
--               (EN 300 421 § 4.4.2) ; référence bit à bit : JPEG2DVB étape 11
--  Auteur     : Eric PERRET
--  Date       : 2026-10-19
--  Version    : 1.0
--  Plateforme : VHDL-2008, synthétisable (Libero SoC)
--  Licence    : CC BY-NC 4.0
--  Interface  : flux d'octets valid / ready, s_sop sur la synchro de chaque mot
--               RS de 204 octets ; un octet sort pour chaque octet entré
--  Principe   : l'octet k passe par la branche j = k mod 12, une FIFO de j × 17
--               octets ; les 11 FIFO occupent une mémoire de 1 122 octets
--               (adresse de base 17·j(j−1)/2). La synchro passe toujours par la
--               branche 0 : s_sop remet la branche à 0. Après la remise à zéro,
--               la mémoire est mise à 0 (1 122 cycles) comme dans JPEG2DVB.
--  Historique : 1.0  2026-10-19  création
--==============================================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.dvbs_pkg.all;

entity interleaver is
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
end entity interleaver;

architecture rtl of interleaver is
    constant I : natural := 12;
    constant M : natural := 17;
    constant TAILLE : natural := M * I * (I - 1) / 2;            -- 1 122
    type base_t is array (0 to I - 1) of natural range 0 to TAILLE;
    function bases return base_t is
        variable b : base_t;
    begin
        for j in 0 to I - 1 loop
            if j = 0 then b(j) := 0; else b(j) := M * j * (j - 1) / 2; end if;
        end loop;
        return b;
    end function;
    constant BASE : base_t := bases;
    type ram_t is array (0 to TAILLE - 1) of octet_t;
    signal ram     : ram_t;
    type ptr_t is array (1 to I - 1) of natural range 0 to M * (I - 1) - 1;
    signal ptr     : ptr_t := (others => 0);
    signal branche : natural range 0 to I - 1 := 0;
    signal efface  : std_logic := '1';
    signal adr_eff : natural range 0 to TAILLE - 1 := 0;
    signal o_valid : std_logic := '0';
    signal libre   : std_logic;
begin
    libre   <= (not o_valid) or m_ready;
    s_ready <= libre and not efface;
    m_valid <= o_valid;

    process (clk)
        variable b : natural range 0 to I - 1;
        variable a : natural range 0 to TAILLE - 1;
    begin
        if rising_edge(clk) then
            if rst = '1' then
                efface  <= '1';
                adr_eff <= 0;
                branche <= 0;
                ptr     <= (others => 0);
                o_valid <= '0';
            elsif efface = '1' then
                ram(adr_eff) <= x"00";
                if adr_eff = TAILLE - 1 then
                    efface <= '0';
                else
                    adr_eff <= adr_eff + 1;
                end if;
            elsif libre = '1' then
                o_valid <= s_valid;
                if s_valid = '1' then
                    m_sop <= s_sop;
                    b := 0 when s_sop = '1' else branche;
                    if b = 0 then
                        m_data <= s_data;
                    else
                        a := BASE(b) + ptr(b);
                        m_data <= ram(a);                    -- lecture avant écriture
                        ram(a) <= s_data;
                        ptr(b) <= 0 when ptr(b) = M * b - 1 else ptr(b) + 1;
                    end if;
                    branche <= 0 when b = I - 1 else b + 1;
                end if;
            end if;
        end if;
    end process;
end architecture rtl;
