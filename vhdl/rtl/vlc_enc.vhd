--==============================================================================
--  Nom        : vlc_enc.vhd
--  Projet     : JPEG2DVB, portage FPGA (émetteur DVB-S 23 cm)
--  Objet      : codage entropique MPEG-2 intra des blocs balayés en zigzag :
--               DC différentiel (B.12, B.13), paires run / niveau (B.14),
--               échappement, fin de bloc ; référence bit à bit : JPEG2DVB
--               étape 05
--  Auteur     : Eric PERRET
--  Date       : 2026-10-19
--  Version    : 1.0
--  Plateforme : VHDL-2008, synthétisable (Libero SoC)
--  Licence    : CC BY-NC 4.0
--  Interface  : entrée : vecteurs zigzag de 64 coefficients, 6 blocs par
--               macrobloc (Y0 à Y3, Cb, Cr), G_COLS macroblocs par slice ;
--               sortie : mots de code cadrés à droite (m_code, m_lg bits), un
--               mot au plus par coefficient ; m_fin_mb marque le dernier mot
--               du macrobloc
--  Principe   : prédicteurs DC (Y, Cb, Cr) remis à 128 au début de chaque
--               slice ; DC : code de taille puis différence (complément à 1 si
--               négative) ; AC : code de B.14 suivi du signe, sinon
--               échappement 000001 + run (6 bits) + niveau (12 bits, complément
--               à 2) ; le code de fin de bloc « 10 » est accolé au dernier mot
--  Historique : 1.0  2026-10-19  création
--==============================================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.vlc_tab_pkg.all;

entity vlc_enc is
    generic (
        G_COLS : natural := 22                       -- macroblocs par slice
    );
    port (
        clk      : in  std_logic;
        rst      : in  std_logic;
        s_valid  : in  std_logic;
        s_ready  : out std_logic;
        s_data   : in  signed(15 downto 0);
        m_valid  : out std_logic;
        m_ready  : in  std_logic;
        m_code   : out std_logic_vector(31 downto 0);
        m_lg     : out unsigned(5 downto 0);
        m_fin_mb : out std_logic
    );
end entity vlc_enc;

architecture rtl of vlc_enc is
    signal pos     : natural range 0 to 63 := 0;
    signal blk     : natural range 0 to 5 := 0;
    signal col     : natural range 0 to G_COLS - 1 := 0;
    signal run     : natural range 0 to 63 := 0;
    signal pred_y, pred_cb, pred_cr : integer range -2048 to 2047 := 128;
    signal o_valid : std_logic := '0';
    signal libre   : std_logic;

    -- nombre de bits de |d| (taille DC)
    function taille(a : natural) return natural is
        variable t : natural := 0;
    begin
        for k in 0 to 11 loop
            if a >= 2 ** k then t := k + 1; end if;
        end loop;
        return t;
    end function;
begin
    libre   <= (not o_valid) or m_ready;
    s_ready <= libre and not rst;
    m_valid <= o_valid;

    process (clk)
        variable v      : integer range -32768 to 32767;
        variable pred   : integer range -2048 to 2047;
        variable diff   : integer range -4096 to 4096;
        variable sz     : natural range 0 to 12;
        variable dct    : dc_vlc_t;
        variable ac     : ac_vlc_t;
        variable code   : unsigned(31 downto 0);
        variable lg     : natural range 0 to 32;
        variable niv    : natural range 0 to 32767;
        variable nrun   : natural range 0 to 63;
        variable py, pcb, pcr : integer range -2048 to 2047;
    begin
        if rising_edge(clk) then
            if rst = '1' then
                pos <= 0; blk <= 0; col <= 0; run <= 0;
                pred_y <= 128; pred_cb <= 128; pred_cr <= 128;
                o_valid <= '0';
            else
                if libre = '1' then
                    o_valid <= '0';
                end if;
                if s_valid = '1' and libre = '1' then
                    v := to_integer(s_data);
                    code := (others => '0');
                    lg := 0;
                    nrun := run;
                    py := pred_y; pcb := pred_cb; pcr := pred_cr;
                    if pos = 0 then
                        -- nouvelle slice : prédicteurs remis à 128
                        if blk = 0 and col = 0 then
                            py := 128; pcb := 128; pcr := 128;
                        end if;
                        if blk < 4 then pred := py; elsif blk = 4 then pred := pcb; else pred := pcr; end if;
                        diff := v - pred;
                        if blk < 4 then py := v; elsif blk = 4 then pcb := v; else pcr := v; end if;
                        if diff < 0 then sz := taille(-diff); else sz := taille(diff); end if;
                        if blk < 4 then dct := DC_LUMA(sz); else dct := DC_CHROMA(sz); end if;
                        code := resize(unsigned(dct.code), 32);
                        lg := dct.lg;
                        if sz > 0 then
                            code := shift_left(code, sz);
                            if diff > 0 then
                                code := code or to_unsigned(diff, 32);
                            else
                                code := code or to_unsigned(diff + 2 ** sz - 1, 32);
                            end if;
                            lg := lg + sz;
                        end if;
                        nrun := 0;
                    else
                        if v = 0 then
                            if nrun < 63 then nrun := nrun + 1; end if;
                        else
                            if v < 0 then niv := -v; else niv := v; end if;
                            ac := ac_code(nrun, niv mod 2048);
                            if ac.trouve and niv < 2048 then
                                code := shift_left(resize(unsigned(ac.code), 32), 1);
                                if v < 0 then code(0) := '1'; end if;
                                lg := ac.lg + 1;
                            else
                                code := resize(unsigned(AC_ESCAPE), 32);
                                code := shift_left(code, 6) or to_unsigned(nrun, 32);
                                if v < 0 then
                                    code := shift_left(code, 12) or to_unsigned((4096 + v) mod 4096, 32);
                                else
                                    code := shift_left(code, 12) or to_unsigned(v mod 4096, 32);
                                end if;
                                lg := 24;
                            end if;
                            nrun := 0;
                        end if;
                    end if;
                    if pos = 63 then
                        code := shift_left(code, 2) or resize(unsigned(AC_EOB), 32);
                        lg := lg + 2;
                    end if;
                    pred_y <= py; pred_cb <= pcb; pred_cr <= pcr;
                    run <= nrun;
                    if lg > 0 then
                        m_code   <= std_logic_vector(code);
                        m_lg     <= to_unsigned(lg, 6);
                        m_fin_mb <= '1' when pos = 63 and blk = 5 else '0';
                        o_valid  <= '1';
                    end if;
                    if pos = 63 then
                        pos <= 0;
                        run <= 0;
                        if blk = 5 then
                            blk <= 0;
                            col <= 0 when col = G_COLS - 1 else col + 1;
                        else
                            blk <= blk + 1;
                        end if;
                    else
                        pos <= pos + 1;
                    end if;
                end if;
            end if;
        end if;
    end process;
end architecture rtl;
