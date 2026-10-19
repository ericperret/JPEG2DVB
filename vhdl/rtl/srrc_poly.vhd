--==============================================================================
--  Nom        : srrc_poly.vhd
--  Projet     : JPEG2DVB, portage FPGA (émetteur DVB-S 23 cm)
--  Objet      : filtre de mise en forme SRRC, α = 0,35, 8 échantillons par
--               symbole, forme polyphase à coefficients entiers 16 bits ;
--               référence bit à bit : JPEG2DVB étape 14 (fichier .cs16)
--  Auteur     : Eric PERRET
--  Date       : 2026-10-19
--  Version    : 1.0
--  Plateforme : VHDL-2008, synthétisable (Libero SoC)
--  Licence    : CC BY-NC 4.0
--  Interface  : entrée : symboles I, Q signés 2 bits (±1) ; sortie : I, Q
--               signés 16 bits, 8 échantillons par symbole, un par cycle
--  Principe   : registre des 13 derniers symboles (initialement 0, comme les
--               symboles hors flux de JPEG2DVB) ; à l'arrivée du symbole n + 6,
--               les 8 échantillons du symbole n sont calculés :
--               y(8n + r) = Σd C(r)(d) · s(n − 6 + d). Symboles ±1 : additions
--               et soustractions de constantes, aucun multiplieur. La somme des
--               |C| ne dépasse pas 0,95 × 32 767 : pas de saturation.
--               Débit : 8 cycles par symbole (le symbole suivant est accepté
--               pendant le 8e échantillon), soit 80 MHz pour 10 MS/s.
--  Historique : 1.0  2026-10-19  création
--==============================================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.srrc_coef_pkg.all;

entity srrc_poly is
    port (
        clk     : in  std_logic;
        rst     : in  std_logic;
        s_valid : in  std_logic;
        s_ready : out std_logic;
        s_i     : in  signed(1 downto 0);
        s_q     : in  signed(1 downto 0);
        m_valid : out std_logic;
        m_ready : in  std_logic;
        m_i     : out signed(15 downto 0);
        m_q     : out signed(15 downto 0)
    );
end entity srrc_poly;

architecture rtl of srrc_poly is
    type sym_tab_t is array (0 to SRRC_TAPS - 1) of signed(1 downto 0);    -- 0 : le plus ancien
    signal sh_i, sh_q : sym_tab_t := (others => (others => '0'));
    signal recus   : natural range 0 to SRRC_TAPS := 0;     -- symboles reçus (saturé)
    signal occupe  : std_logic := '0';
    signal r       : natural range 0 to SRRC_SPS - 1 := 0;
    signal o_valid : std_logic := '0';
    signal libre   : std_logic;
    signal pret    : std_logic;

    function somme(sh : sym_tab_t; ph : natural) return signed is
        variable acc : integer range -65536 to 65535 := 0;
    begin
        for d in 0 to SRRC_TAPS - 1 loop
            if sh(d) = "01" then
                acc := acc + SRRC_C(ph)(d);
            elsif sh(d) = "11" then
                acc := acc - SRRC_C(ph)(d);
            end if;
        end loop;
        return to_signed(acc, 16);
    end function;
begin
    libre   <= (not o_valid) or m_ready;
    pret    <= '1' when rst = '0' and (occupe = '0' or (r = SRRC_SPS - 1 and libre = '1')) else '0';
    s_ready <= pret;
    m_valid <= o_valid;

    process (clk)
        variable entre : boolean;
    begin
        if rising_edge(clk) then
            if rst = '1' then
                sh_i    <= (others => (others => '0'));
                sh_q    <= (others => (others => '0'));
                recus   <= 0;
                occupe  <= '0';
                r       <= 0;
                o_valid <= '0';
            else
                if libre = '1' then
                    o_valid <= '0';
                end if;
                -- échantillon r du symbole central (position 6 du registre)
                if occupe = '1' and libre = '1' then
                    m_i     <= somme(sh_i, r);
                    m_q     <= somme(sh_q, r);
                    o_valid <= '1';
                    if r = SRRC_SPS - 1 then
                        occupe <= '0';
                    end if;
                    r <= 0 when r = SRRC_SPS - 1 else r + 1;
                end if;
                -- nouveau symbole
                entre := s_valid = '1' and pret = '1';
                if entre then
                    sh_i <= sh_i(1 to SRRC_TAPS - 1) & s_i;
                    sh_q <= sh_q(1 to SRRC_TAPS - 1) & s_q;
                    if recus < SRRC_TAPS then
                        recus <= recus + 1;
                    end if;
                    -- 7 symboles reçus : le symbole 0 est au centre
                    if recus >= SRRC_TAPS / 2 then
                        occupe <= '1';
                        r      <= 0;
                    end if;
                end if;
            end if;
        end if;
    end process;
end architecture rtl;
