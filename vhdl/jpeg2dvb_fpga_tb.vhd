--==============================================================================
--  Nom        : jpeg2dvb_fpga_tb.vhd
--  Projet     : JPEG2DVB, portage FPGA (émetteur DVB-S 23 cm)
--  Objet      : bancs de test GHDL, comparaison au bit près avec les références de fpga_test/
--  Auteur     : Eric PERRET
--  Date       : 2026-10-19
--  Version    : 1.0
--  Plateforme : VHDL-2008, simulation (GHDL)
--  Licence    : CC BY-NC 4.0
--  Contenu    : 11 unités, dans l'ordre d'analyse ; chacune garde son
--               cartouche, entre les balises « -- >>> nom.vhd » et « -- <<< nom.vhd »
--               (les paquetages générés sont réécrits par les outils de fpga_test/)
--  Historique : 1.0  2026-10-19  fusion des fichiers de vhdl/tb/
--==============================================================================

-- >>> tb_pkg.vhd
--==============================================================================
--  Nom        : tb_pkg.vhd
--  Projet     : JPEG2DVB, portage FPGA (émetteur DVB-S 23 cm)
--  Objet      : outils des bancs de test : lecture des fichiers binaires de
--               référence produits par JPEG2DVB, aléa reproductible pour
--               éprouver le contrôle de flux (valid / ready)
--  Auteur     : Eric PERRET
--  Date       : 2026-10-19
--  Version    : 1.0
--  Plateforme : VHDL-2008, simulation (GHDL)
--  Licence    : CC BY-NC 4.0
--  Historique : 1.0  2026-10-19  création
--==============================================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package tb_pkg is
    -- fichier binaire lu octet par octet
    type octets_f is file of character;
    function octet(c : character) return std_logic_vector;
    -- générateur pseudo-aléatoire 16 bits (Galois, x¹⁶ + x¹⁴ + x¹³ + x¹¹ + 1)
    function alea(r : std_logic_vector(15 downto 0)) return std_logic_vector;
    -- références : dossier de lancement (fpga_test/)
    constant REF : string := "./";
end package tb_pkg;

package body tb_pkg is
    function octet(c : character) return std_logic_vector is
    begin
        return std_logic_vector(to_unsigned(character'pos(c), 8));
    end function;

    function alea(r : std_logic_vector(15 downto 0)) return std_logic_vector is
        variable v : std_logic_vector(15 downto 0) := r;
    begin
        if v(0) = '1' then
            v := ('0' & v(15 downto 1)) xor x"B400";
        else
            v := '0' & v(15 downto 1);
        end if;
        return v;
    end function;
end package body tb_pkg;
-- <<< tb_pkg.vhd

-- >>> tb_octets.vhd
--==============================================================================
--  Nom        : tb_octets.vhd
--  Projet     : JPEG2DVB, portage FPGA (émetteur DVB-S 23 cm)
--  Objet      : banc de test des modules à flux d'octets (dispersion d'énergie,
--               Reed-Solomon, entrelaceur) : entrée lue dans un fichier de
--               JPEG2DVB, sortie comparée octet par octet au fichier de l'étape
--               suivante ; trous aléatoires côté entrée et côté sortie pour
--               éprouver le contrôle de flux
--  Auteur     : Eric PERRET
--  Date       : 2026-10-19
--  Version    : 1.1
--  Plateforme : VHDL-2008, simulation (GHDL)
--  Licence    : CC BY-NC 4.0
--  Paramètres : G_DUT 1 = prbs_disp, 2 = rs_enc, 3 = interleaver, 4 = ts_mux
--  Historique : 1.0  2026-10-19  création
--               1.1  2026-10-19  multiplexeur TS (G_DUT = 4)
--==============================================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;
use work.dvbs_pkg.all;
use work.tb_pkg.all;

entity tb_octets is
    generic (
        G_DUT    : natural := 1;
        G_IN     : string  := "ts.bin";
        G_OUT    : string  := "rand.bin";
        G_N_IN   : natural := 12032;
        G_N_OUT  : natural := 12032;
        G_PKT    : natural := 188;          -- longueur des paquets en entrée (repère s_sop)
        G_ALEA   : boolean := true
    );
end entity tb_octets;

architecture sim of tb_octets is
    signal clk     : std_logic := '0';
    signal rst     : std_logic := '1';
    signal s_valid : std_logic := '0';
    signal s_ready : std_logic;
    signal s_data  : octet_t := (others => '0');
    signal s_sop   : std_logic := '0';
    signal m_valid : std_logic;
    signal m_ready : std_logic := '1';
    signal m_data  : octet_t;
    signal m_sop   : std_logic;
begin
    clk <= not clk after 5 ns;

    g1 : if G_DUT = 1 generate
        dut : entity work.prbs_disp port map (clk, rst, s_valid, s_ready, s_data, s_sop, m_valid, m_ready, m_data, m_sop);
    elsif G_DUT = 2 generate
        dut : entity work.rs_enc port map (clk, rst, s_valid, s_ready, s_data, s_sop, m_valid, m_ready, m_data, m_sop);
    elsif G_DUT = 3 generate
        dut : entity work.interleaver port map (clk, rst, s_valid, s_ready, s_data, s_sop, m_valid, m_ready, m_data, m_sop);
    elsif G_DUT = 4 generate
        dut : entity work.ts_mux port map (clk, rst, s_valid, s_ready, s_data, m_valid, m_ready, m_data, m_sop);
    end generate;

    -- source : octets du fichier d'entrée
    source : process
        file f      : octets_f open read_mode is REF & G_IN;
        variable c  : character;
        variable r  : std_logic_vector(15 downto 0) := x"ACE1";
    begin
        wait until rising_edge(clk);
        wait until rising_edge(clk);
        rst <= '0';
        for k in 0 to G_N_IN - 1 loop
            read(f, c);
            if G_ALEA then
                r := alea(r);
                if r(0) = '1' and r(1) = '1' then
                    s_valid <= '0';
                    wait until rising_edge(clk);
                end if;
            end if;
            s_data  <= octet(c);
            s_sop   <= '1' when k mod G_PKT = 0 else '0';
            s_valid <= '1';
            loop
                wait until rising_edge(clk);
                exit when s_ready = '1';
            end loop;
        end loop;
        s_valid <= '0';
        wait;
    end process;

    -- puits : m_ready aléatoire
    pression : process (clk)
        variable r : std_logic_vector(15 downto 0) := x"1D0F";
    begin
        if rising_edge(clk) then
            r := alea(r);
            if G_ALEA then
                m_ready <= r(0) or r(2);
            end if;
        end if;
    end process;

    -- comparaison avec le fichier de référence
    controle : process (clk)
        file f           : octets_f open read_mode is REF & G_OUT;
        variable c       : character;
        variable n, err  : natural := 0;
        variable cycles  : natural := 0;
    begin
        if rising_edge(clk) then
            cycles := cycles + 1;
            if m_valid = '1' and m_ready = '1' and n < G_N_OUT then
                read(f, c);
                if m_data /= octet(c) then
                    if err < 10 then
                        report "ecart a l'octet " & integer'image(n) & " : " & to_hstring(m_data) & " au lieu de " & to_hstring(octet(c)) severity warning;
                    end if;
                    err := err + 1;
                end if;
                n := n + 1;
                if n = G_N_OUT then
                    if err = 0 then
                        report "OK " & G_OUT & " : " & integer'image(n) & " octets identiques (" & integer'image(cycles) & " cycles)";
                    else
                        report "ECHEC " & G_OUT & " : " & integer'image(err) & " octets differents sur " & integer'image(n) severity error;
                    end if;
                    finish;
                end if;
            end if;
            if cycles > 20 * G_N_OUT + 10000 then
                report "ECHEC " & G_OUT & " : delai depasse, " & integer'image(n) & " octets recus" severity error;
                finish;
            end if;
        end if;
    end process;
end architecture sim;
-- <<< tb_octets.vhd

-- >>> tb_conv.vhd
--==============================================================================
--  Nom        : tb_conv.vhd
--  Projet     : JPEG2DVB, portage FPGA (émetteur DVB-S 23 cm)
--  Objet      : banc de test du codeur convolutif (taux G_FEC) : entrée = sortie
--               de l'entrelaceur (JPEG2DVB étape 11), sortie comparée bit à bit
--               aux bits codés de l'étape 12 (I puis Q de chaque symbole,
--               regroupés par octets, poids fort en tête)
--  Auteur     : Eric PERRET
--  Date       : 2026-10-19
--  Version    : 1.0
--  Plateforme : VHDL-2008, simulation (GHDL)
--  Licence    : CC BY-NC 4.0
--  Historique : 1.0  2026-10-19  création
--==============================================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;
use work.dvbs_pkg.all;
use work.tb_pkg.all;

entity tb_conv is
    generic (
        G_FEC   : natural := 0;
        G_IN    : string  := "inter.bin";
        G_OUT   : string  := "conv.bin";
        G_N_IN  : natural := 13056;
        G_N_OUT : natural := 26112
    );
end entity tb_conv;

architecture sim of tb_conv is
    signal clk     : std_logic := '0';
    signal rst     : std_logic := '1';
    signal s_valid : std_logic := '0';
    signal s_ready : std_logic;
    signal s_data  : octet_t := (others => '0');
    signal m_valid : std_logic;
    signal m_ready : std_logic := '1';
    signal m_data  : std_logic_vector(1 downto 0);
begin
    clk <= not clk after 5 ns;
    dut : entity work.conv_enc generic map (G_FEC => G_FEC) port map (clk, rst, s_valid, s_ready, s_data, m_valid, m_ready, m_data);

    source : process
        file f     : octets_f open read_mode is REF & G_IN;
        variable c : character;
        variable r : std_logic_vector(15 downto 0) := x"ACE1";
    begin
        wait until rising_edge(clk);
        wait until rising_edge(clk);
        rst <= '0';
        for k in 0 to G_N_IN - 1 loop
            read(f, c);
            r := alea(r);
            if r(0) = '1' and r(1) = '1' then
                s_valid <= '0';
                wait until rising_edge(clk);
            end if;
            s_data  <= octet(c);
            s_valid <= '1';
            loop
                wait until rising_edge(clk);
                exit when s_ready = '1';
            end loop;
        end loop;
        s_valid <= '0';
        wait;
    end process;

    pression : process (clk)
        variable r : std_logic_vector(15 downto 0) := x"1D0F";
    begin
        if rising_edge(clk) then
            r := alea(r);
            m_ready <= r(0) or r(2);
        end if;
    end process;

    controle : process (clk)
        file f          : octets_f open read_mode is REF & G_OUT;
        variable c      : character;
        variable acc    : std_logic_vector(7 downto 0);
        variable nb     : natural := 0;
        variable n, err : natural := 0;
        variable cycles : natural := 0;
    begin
        if rising_edge(clk) then
            cycles := cycles + 1;
            if m_valid = '1' and m_ready = '1' and n < G_N_OUT then
                acc := acc(5 downto 0) & m_data;
                nb  := nb + 2;
                if nb = 8 then
                    nb := 0;
                    read(f, c);
                    if acc /= octet(c) then
                        if err < 10 then
                            report "ecart a l'octet " & integer'image(n) & " : " & to_hstring(acc) & " au lieu de " & to_hstring(octet(c)) severity warning;
                        end if;
                        err := err + 1;
                    end if;
                    n := n + 1;
                    if n = G_N_OUT then
                        if err = 0 then
                            report "OK " & G_OUT & " : " & integer'image(n) & " octets identiques (" & integer'image(n * 8) & " bits codes, " & integer'image(cycles) & " cycles)";
                        else
                            report "ECHEC " & G_OUT & " : " & integer'image(err) & " octets differents sur " & integer'image(n) severity error;
                        end if;
                        finish;
                    end if;
                end if;
            end if;
            if cycles > 40 * G_N_OUT + 10000 then
                report "ECHEC " & G_OUT & " : delai depasse, " & integer'image(n) & " octets recus" severity error;
                finish;
            end if;
        end if;
    end process;
end architecture sim;
-- <<< tb_conv.vhd

-- >>> tb_qpsk.vhd
--==============================================================================
--  Nom        : tb_qpsk.vhd
--  Projet     : JPEG2DVB, portage FPGA (émetteur DVB-S 23 cm)
--  Objet      : banc de test de la mise en correspondance QPSK : entrée = bits
--               codés de l'étape 12, sortie comparée aux symboles entiers I, Q
--               (octets signés) de l'étape 13
--  Auteur     : Eric PERRET
--  Date       : 2026-10-19
--  Version    : 1.0
--  Plateforme : VHDL-2008, simulation (GHDL)
--  Licence    : CC BY-NC 4.0
--  Historique : 1.0  2026-10-19  création
--==============================================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;
use work.tb_pkg.all;

entity tb_qpsk is
    generic (
        G_IN    : string  := "conv.bin";
        G_OUT   : string  := "qpsk.bin";
        G_N_SYM : natural := 104448
    );
end entity tb_qpsk;

architecture sim of tb_qpsk is
    signal clk     : std_logic := '0';
    signal s_valid : std_logic := '0';
    signal s_ready : std_logic;
    signal s_data  : std_logic_vector(1 downto 0) := "00";
    signal m_valid : std_logic;
    signal m_ready : std_logic := '1';
    signal m_i, m_q : signed(1 downto 0);
begin
    clk <= not clk after 5 ns;
    dut : entity work.qpsk_map port map (s_valid, s_ready, s_data, m_valid, m_ready, m_i, m_q);

    source : process
        file f     : octets_f open read_mode is REF & G_IN;
        variable c : character;
        variable o : std_logic_vector(7 downto 0);
    begin
        wait until rising_edge(clk);
        for k in 0 to G_N_SYM / 4 - 1 loop
            read(f, c);
            o := octet(c);
            for p in 3 downto 0 loop
                s_data  <= o(2 * p + 1 downto 2 * p);
                s_valid <= '1';
                loop
                    wait until rising_edge(clk);
                    exit when s_ready = '1';
                end loop;
            end loop;
        end loop;
        s_valid <= '0';
        wait;
    end process;

    pression : process (clk)
        variable r : std_logic_vector(15 downto 0) := x"1D0F";
    begin
        if rising_edge(clk) then
            r := alea(r);
            m_ready <= r(0) or r(2);
        end if;
    end process;

    controle : process (clk)
        file f          : octets_f open read_mode is REF & G_OUT;
        variable ci, cq : character;
        variable n, err : natural := 0;
    begin
        if rising_edge(clk) then
            if m_valid = '1' and m_ready = '1' and n < G_N_SYM then
                read(f, ci); read(f, cq);
                if resize(m_i, 8) /= signed(octet(ci)) or resize(m_q, 8) /= signed(octet(cq)) then
                    if err < 10 then
                        report "ecart au symbole " & integer'image(n) severity warning;
                    end if;
                    err := err + 1;
                end if;
                n := n + 1;
                if n = G_N_SYM then
                    if err = 0 then
                        report "OK " & G_OUT & " : " & integer'image(n) & " symboles identiques";
                    else
                        report "ECHEC " & G_OUT & " : " & integer'image(err) & " symboles differents sur " & integer'image(n) severity error;
                    end if;
                    finish;
                end if;
            end if;
        end if;
    end process;
end architecture sim;
-- <<< tb_qpsk.vhd

-- >>> tb_srrc.vhd
--==============================================================================
--  Nom        : tb_srrc.vhd
--  Projet     : JPEG2DVB, portage FPGA (émetteur DVB-S 23 cm)
--  Objet      : banc de test du filtre SRRC polyphase : entrée = symboles ±1
--               de l'étape 13, sortie comparée aux échantillons I/Q 16 bits
--               (petit-boutiste, entrelacés) du fichier .cs16 de l'étape 14
--  Auteur     : Eric PERRET
--  Date       : 2026-10-19
--  Version    : 1.0
--  Plateforme : VHDL-2008, simulation (GHDL)
--  Licence    : CC BY-NC 4.0
--  Historique : 1.0  2026-10-19  création
--==============================================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;
use work.tb_pkg.all;

entity tb_srrc is
    generic (
        G_IN    : string  := "qpsk.bin";
        G_OUT   : string  := "iq.cs16";
        G_N_SYM : natural := 104448;        -- symboles lus
        G_N_ECH : natural := 160000         -- échantillons comparés (20 000 symboles)
    );
end entity tb_srrc;

architecture sim of tb_srrc is
    signal clk     : std_logic := '0';
    signal rst     : std_logic := '1';
    signal s_valid : std_logic := '0';
    signal s_ready : std_logic;
    signal s_i, s_q : signed(1 downto 0) := "00";
    signal m_valid : std_logic;
    signal m_ready : std_logic := '1';
    signal m_i, m_q : signed(15 downto 0);
begin
    clk <= not clk after 5 ns;
    dut : entity work.srrc_poly port map (clk, rst, s_valid, s_ready, s_i, s_q, m_valid, m_ready, m_i, m_q);

    source : process
        file f          : octets_f open read_mode is REF & G_IN;
        variable ci, cq : character;
    begin
        wait until rising_edge(clk);
        wait until rising_edge(clk);
        rst <= '0';
        for k in 0 to G_N_SYM - 1 loop
            read(f, ci); read(f, cq);
            s_i     <= resize(signed(octet(ci)), 2);
            s_q     <= resize(signed(octet(cq)), 2);
            s_valid <= '1';
            loop
                wait until rising_edge(clk);
                exit when s_ready = '1';
            end loop;
        end loop;
        s_valid <= '0';
        wait;
    end process;

    -- sortie à plein débit la plupart du temps, avec quelques arrêts
    pression : process (clk)
        variable r : std_logic_vector(15 downto 0) := x"1D0F";
    begin
        if rising_edge(clk) then
            r := alea(r);
            m_ready <= r(0) or r(1) or r(2);
        end if;
    end process;

    controle : process (clk)
        file f          : octets_f open read_mode is REF & G_OUT;
        variable a, b   : character;
        variable ei, eq : signed(15 downto 0);
        variable n, err : natural := 0;
        variable cycles : natural := 0;
    begin
        if rising_edge(clk) then
            cycles := cycles + 1;
            if m_valid = '1' and m_ready = '1' and n < G_N_ECH then
                read(f, a); read(f, b); ei := signed(octet(b) & octet(a));
                read(f, a); read(f, b); eq := signed(octet(b) & octet(a));
                if m_i /= ei or m_q /= eq then
                    if err < 10 then
                        report "ecart a l'echantillon " & integer'image(n) & " : " & integer'image(to_integer(m_i)) & ", " & integer'image(to_integer(m_q)) &
                               " au lieu de " & integer'image(to_integer(ei)) & ", " & integer'image(to_integer(eq)) severity warning;
                    end if;
                    err := err + 1;
                end if;
                n := n + 1;
                if n = G_N_ECH then
                    if err = 0 then
                        report "OK " & G_OUT & " : " & integer'image(n) & " echantillons I/Q identiques (" & integer'image(cycles) & " cycles)";
                    else
                        report "ECHEC " & G_OUT & " : " & integer'image(err) & " echantillons differents sur " & integer'image(n) severity error;
                    end if;
                    finish;
                end if;
            end if;
        end if;
    end process;
end architecture sim;
-- <<< tb_srrc.vhd

-- >>> tb_backend.vhd
--==============================================================================
--  Nom        : tb_backend.vhd
--  Projet     : JPEG2DVB, portage FPGA (émetteur DVB-S 23 cm)
--  Objet      : banc de test de la chaîne arrière complète : paquets TS de
--               l'étape 08 en entrée, échantillons I/Q comparés au fichier
--               .cs16 de l'étape 14 ; sortie à plein débit (un échantillon
--               par cycle demandé, comme vers le sigma-delta)
--  Auteur     : Eric PERRET
--  Date       : 2026-10-19
--  Version    : 1.0
--  Plateforme : VHDL-2008, simulation (GHDL)
--  Licence    : CC BY-NC 4.0
--  Historique : 1.0  2026-10-19  création
--==============================================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;
use work.dvbs_pkg.all;
use work.tb_pkg.all;

entity tb_backend is
    generic (
        G_IN    : string  := "ts.bin";
        G_OUT   : string  := "iq.cs16";
        G_N_IN  : natural := 12032;          -- 64 paquets TS
        G_N_ECH : natural := 160000          -- 20 000 symboles
    );
end entity tb_backend;

architecture sim of tb_backend is
    signal clk     : std_logic := '0';
    signal rst     : std_logic := '1';
    signal s_valid : std_logic := '0';
    signal s_ready : std_logic;
    signal s_data  : octet_t := (others => '0');
    signal s_sop   : std_logic := '0';
    signal m_valid : std_logic;
    signal m_ready : std_logic := '1';
    signal m_i, m_q : signed(15 downto 0);
begin
    clk <= not clk after 6.25 ns;          -- 80 MHz
    dut : entity work.tx_backend generic map (G_FEC => 0)
        port map (clk, rst, s_valid, s_ready, s_data, s_sop, m_valid, m_ready, m_i, m_q);

    source : process
        file f     : octets_f open read_mode is REF & G_IN;
        variable c : character;
    begin
        wait until rising_edge(clk);
        wait until rising_edge(clk);
        rst <= '0';
        for k in 0 to G_N_IN - 1 loop
            read(f, c);
            s_data  <= octet(c);
            s_sop   <= '1' when k mod 188 = 0 else '0';
            s_valid <= '1';
            loop
                wait until rising_edge(clk);
                exit when s_ready = '1';
            end loop;
        end loop;
        s_valid <= '0';
        wait;
    end process;

    controle : process (clk)
        file f            : octets_f open read_mode is REF & G_OUT;
        variable a, b     : character;
        variable ei, eq   : signed(15 downto 0);
        variable n, err   : natural := 0;
        variable cycles   : natural := 0;
        variable premier  : natural := 0;
        variable trous    : natural := 0;
    begin
        if rising_edge(clk) then
            cycles := cycles + 1;
            if n > 0 and n < G_N_ECH and m_valid = '0' then
                trous := trous + 1;            -- cycle sans échantillon une fois le flux établi
            end if;
            if m_valid = '1' and m_ready = '1' and n < G_N_ECH then
                if n = 0 then premier := cycles; end if;
                read(f, a); read(f, b); ei := signed(std_logic_vector'(octet(b) & octet(a)));
                read(f, a); read(f, b); eq := signed(std_logic_vector'(octet(b) & octet(a)));
                if m_i /= ei or m_q /= eq then
                    if err < 10 then
                        report "ecart a l'echantillon " & integer'image(n) severity warning;
                    end if;
                    err := err + 1;
                end if;
                n := n + 1;
                if n = G_N_ECH then
                    if err = 0 then
                        report "OK " & G_OUT & " : " & integer'image(n) & " echantillons I/Q identiques depuis le TS ; premier au cycle " &
                               integer'image(premier) & ", " & integer'image(trous) & " cycles sans echantillon ensuite";
                    else
                        report "ECHEC " & G_OUT & " : " & integer'image(err) & " echantillons differents sur " & integer'image(n) severity error;
                    end if;
                    finish;
                end if;
            end if;
            if cycles > 4 * G_N_ECH + 100000 then
                report "ECHEC " & G_OUT & " : delai depasse, " & integer'image(n) & " echantillons recus" severity error;
                finish;
            end if;
        end if;
    end process;
end architecture sim;
-- <<< tb_backend.vhd

-- >>> tb_bloc.vhd
--==============================================================================
--  Nom        : tb_bloc.vhd
--  Projet     : JPEG2DVB, portage FPGA (émetteur DVB-S 23 cm)
--  Objet      : banc de test des modules à blocs 8 × 8 du codage vidéo (DCT
--               entière, quantification, zigzag) : entrée et sortie comparées
--               aux fichiers de JPEG2DVB (image 0, 2 376 blocs)
--  Auteur     : Eric PERRET
--  Date       : 2026-10-19
--  Version    : 1.0
--  Plateforme : VHDL-2008, simulation (GHDL)
--  Licence    : CC BY-NC 4.0
--  Paramètres : G_DUT 1 = dct8x8_int (entrée octets), 2 = quant_intra,
--               3 = zigzag (entrée int16 LE) ; sortie int16 LE
--  Historique : 1.0  2026-10-19  création
--==============================================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;
use work.tb_pkg.all;

entity tb_bloc is
    generic (
        G_DUT  : natural := 1;
        G_IN   : string  := "mb0.bin";
        G_OUT  : string  := "dct0.bin";
        G_N    : natural := 152064;
        G_CODE : natural := 8
    );
end entity tb_bloc;

architecture sim of tb_bloc is
    signal clk     : std_logic := '0';
    signal rst     : std_logic := '1';
    signal s_valid : std_logic := '0';
    signal s_ready : std_logic;
    signal s_pix   : unsigned(7 downto 0) := (others => '0');
    signal s_coef  : signed(15 downto 0) := (others => '0');
    signal m_valid : std_logic;
    signal m_ready : std_logic := '1';
    signal m_data  : signed(15 downto 0);
    signal code    : unsigned(4 downto 0) := to_unsigned(G_CODE, 5);
begin
    clk <= not clk after 5 ns;

    g1 : if G_DUT = 1 generate
        dut : entity work.dct8x8_int port map (clk, rst, s_valid, s_ready, s_pix, m_valid, m_ready, m_data);
    elsif G_DUT = 2 generate
        dut : entity work.quant_intra port map (clk, rst, code, s_valid, s_ready, s_coef, m_valid, m_ready, m_data);
    elsif G_DUT = 3 generate
        dut : entity work.zigzag port map (clk, rst, s_valid, s_ready, s_coef, m_valid, m_ready, m_data);
    end generate;

    source : process
        file f     : octets_f open read_mode is REF & G_IN;
        variable a, b : character;
        variable r : std_logic_vector(15 downto 0) := x"ACE1";
    begin
        wait until rising_edge(clk);
        wait until rising_edge(clk);
        rst <= '0';
        for k in 0 to G_N - 1 loop
            if G_DUT = 1 then
                read(f, a);
                s_pix <= unsigned(octet(a));
            else
                read(f, a); read(f, b);
                s_coef <= signed(std_logic_vector'(octet(b) & octet(a)));
            end if;
            r := alea(r);
            if r(0) = '1' and r(1) = '1' and r(2) = '1' then
                s_valid <= '0';
                wait until rising_edge(clk);
            end if;
            s_valid <= '1';
            loop
                wait until rising_edge(clk);
                exit when s_ready = '1';
            end loop;
        end loop;
        s_valid <= '0';
        wait;
    end process;

    pression : process (clk)
        variable r : std_logic_vector(15 downto 0) := x"1D0F";
    begin
        if rising_edge(clk) then
            r := alea(r);
            m_ready <= r(0) or r(2);
        end if;
    end process;

    controle : process (clk)
        file f          : octets_f open read_mode is REF & G_OUT;
        variable a, b   : character;
        variable e      : signed(15 downto 0);
        variable n, err : natural := 0;
        variable cycles : natural := 0;
    begin
        if rising_edge(clk) then
            cycles := cycles + 1;
            if m_valid = '1' and m_ready = '1' and n < G_N then
                read(f, a); read(f, b);
                e := signed(std_logic_vector'(octet(b) & octet(a)));
                if m_data /= e then
                    if err < 10 then
                        report "ecart au coefficient " & integer'image(n) & " (bloc " & integer'image(n / 64) & ", rang " & integer'image(n mod 64) & ") : " &
                               integer'image(to_integer(m_data)) & " au lieu de " & integer'image(to_integer(e)) severity warning;
                    end if;
                    err := err + 1;
                end if;
                n := n + 1;
                if n = G_N then
                    if err = 0 then
                        report "OK " & G_OUT & " : " & integer'image(n) & " coefficients identiques (" & integer'image(cycles) & " cycles)";
                    else
                        report "ECHEC " & G_OUT & " : " & integer'image(err) & " coefficients differents sur " & integer'image(n) severity error;
                    end if;
                    finish;
                end if;
            end if;
            if cycles > 8 * G_N + 10000 then
                report "ECHEC " & G_OUT & " : delai depasse, " & integer'image(n) & " coefficients recus" severity error;
                finish;
            end if;
        end if;
    end process;
end architecture sim;
-- <<< tb_bloc.vhd

-- >>> tb_vlc.vhd
--==============================================================================
--  Nom        : tb_vlc.vhd
--  Projet     : JPEG2DVB, portage FPGA (émetteur DVB-S 23 cm)
--  Objet      : banc de test du codeur VLC : vecteurs zigzag de l'image 0
--               (étape 04) en entrée ; mots de code mis bout à bout et
--               comparés bit à bit aux bits de l'étape 05, longueur de chaque
--               macrobloc comparée à la référence
--  Auteur     : Eric PERRET
--  Date       : 2026-10-19
--  Version    : 1.0
--  Plateforme : VHDL-2008, simulation (GHDL)
--  Licence    : CC BY-NC 4.0
--  Historique : 1.0  2026-10-19  création
--==============================================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;
use work.tb_pkg.all;

entity tb_vlc is
    generic (
        G_IN   : string  := "zz0.bin";
        G_N    : natural := 152064;          -- coefficients (une image)
        G_MB   : natural := 396
    );
end entity tb_vlc;

architecture sim of tb_vlc is
    signal clk      : std_logic := '0';
    signal rst      : std_logic := '1';
    signal s_valid  : std_logic := '0';
    signal s_ready  : std_logic;
    signal s_data   : signed(15 downto 0) := (others => '0');
    signal m_valid  : std_logic;
    signal m_ready  : std_logic := '1';
    signal m_code   : std_logic_vector(31 downto 0);
    signal m_lg     : unsigned(5 downto 0);
    signal m_fin_mb : std_logic;
begin
    clk <= not clk after 5 ns;
    dut : entity work.vlc_enc port map (clk, rst, s_valid, s_ready, s_data, m_valid, m_ready, m_code, m_lg, m_fin_mb);

    source : process
        file f        : octets_f open read_mode is REF & G_IN;
        variable a, b : character;
    begin
        wait until rising_edge(clk);
        wait until rising_edge(clk);
        rst <= '0';
        for k in 0 to G_N - 1 loop
            read(f, a); read(f, b);
            s_data  <= signed(std_logic_vector'(octet(b) & octet(a)));
            s_valid <= '1';
            loop
                wait until rising_edge(clk);
                exit when s_ready = '1';
            end loop;
        end loop;
        s_valid <= '0';
        wait;
    end process;

    pression : process (clk)
        variable r : std_logic_vector(15 downto 0) := x"1D0F";
    begin
        if rising_edge(clk) then
            r := alea(r);
            m_ready <= r(0) or r(2);
        end if;
    end process;

    controle : process (clk)
        file fb          : octets_f open read_mode is REF & "vlc.bin";
        file fl          : octets_f open read_mode is REF & "mbbits.bin";
        variable a, b    : character;
        variable acc     : std_logic_vector(63 downto 0) := (others => '0');
        variable nacc    : natural := 0;
        variable lg      : natural;
        variable bits_mb : natural := 0;
        variable ref_mb  : natural;
        variable nmb     : natural := 0;
        variable noct    : natural := 0;
        variable err_o, err_l : natural := 0;
        variable e       : std_logic_vector(7 downto 0);
    begin
        if rising_edge(clk) then
            if m_valid = '1' and m_ready = '1' and nmb < G_MB then
                lg := to_integer(m_lg);
                acc := std_logic_vector(shift_left(unsigned(acc), lg)) or (std_logic_vector(resize(unsigned(m_code), 64)) and std_logic_vector(shift_left(to_unsigned(1, 64), lg) - 1));
                nacc := nacc + lg;
                bits_mb := bits_mb + lg;
                while nacc >= 8 loop
                    read(fb, a);
                    e := acc(nacc - 1 downto nacc - 8);
                    if e /= octet(a) then
                        if err_o < 10 then
                            report "ecart a l'octet " & integer'image(noct) & " (macrobloc " & integer'image(nmb) & ")" severity warning;
                        end if;
                        err_o := err_o + 1;
                    end if;
                    noct := noct + 1;
                    nacc := nacc - 8;
                end loop;
                if m_fin_mb = '1' then
                    read(fl, a); read(fl, b);
                    ref_mb := character'pos(b) * 256 + character'pos(a);
                    if ref_mb /= bits_mb then
                        if err_l < 10 then
                            report "macrobloc " & integer'image(nmb) & " : " & integer'image(bits_mb) & " bits au lieu de " & integer'image(ref_mb) severity warning;
                        end if;
                        err_l := err_l + 1;
                    end if;
                    bits_mb := 0;
                    nmb := nmb + 1;
                    if nmb = G_MB then
                        if err_o = 0 and err_l = 0 then
                            report "OK vlc.bin : " & integer'image(G_MB) & " macroblocs, " & integer'image(noct) & " octets identiques, longueurs identiques";
                        else
                            report "ECHEC vlc.bin : " & integer'image(err_o) & " octets et " & integer'image(err_l) & " longueurs differents" severity error;
                        end if;
                        finish;
                    end if;
                end if;
            end if;
        end if;
    end process;
end architecture sim;
-- <<< tb_vlc.vhd

-- >>> tb_es.vhd
--==============================================================================
--  Nom        : tb_es.vhd
--  Projet     : JPEG2DVB, portage FPGA (émetteur DVB-S 23 cm)
--  Objet      : banc de test de l'assemblage du flux élémentaire : bits VLC
--               des macroblocs de l'étape 05 (toutes les images) en entrée,
--               découpés en mots de 1 à 24 bits ; sortie comparée octet par
--               octet au flux élémentaire de l'étape 06 (fin de séquence comprise)
--  Auteur     : Eric PERRET
--  Date       : 2026-10-19
--  Version    : 1.0
--  Plateforme : VHDL-2008, simulation (GHDL)
--  Licence    : CC BY-NC 4.0
--  Historique : 1.0  2026-10-19  création
--==============================================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;
use work.tb_pkg.all;

entity tb_es is
    generic (
        G_IMAGES : natural := 3;
        G_N_OUT  : natural := 79147;         -- taille de es.bin
        G_CODE   : natural := 8
    );
end entity tb_es;

architecture sim of tb_es is
    signal clk      : std_logic := '0';
    signal rst      : std_logic := '1';
    signal s_valid  : std_logic := '0';
    signal s_ready  : std_logic;
    signal s_code   : std_logic_vector(31 downto 0) := (others => '0');
    signal s_lg     : unsigned(5 downto 0) := (others => '0');
    signal s_fin_mb : std_logic := '0';
    signal m_valid  : std_logic;
    signal m_ready  : std_logic := '1';
    signal m_data   : std_logic_vector(7 downto 0);
    signal code     : unsigned(4 downto 0) := to_unsigned(G_CODE, 5);
begin
    clk <= not clk after 5 ns;
    dut : entity work.es_mux generic map (G_IMAGES => G_IMAGES)
        port map (clk, rst, code, s_valid, s_ready, s_code, s_lg, s_fin_mb, m_valid, m_ready, m_data);

    -- source : bits de chaque macrobloc, découpés en mots de longueur pseudo-aléatoire
    source : process
        file fb         : octets_f open read_mode is REF & "vlc.bin";
        file fl         : octets_f open read_mode is REF & "mbbits.bin";
        variable a, b   : character;
        variable octet_c : std_logic_vector(7 downto 0);
        variable nb_oct : natural := 0;              -- bits restant dans octet_c
        variable reste, lg : natural;
        variable mot    : std_logic_vector(31 downto 0);
        variable r      : std_logic_vector(15 downto 0) := x"ACE1";
    begin
        wait until rising_edge(clk);
        wait until rising_edge(clk);
        rst <= '0';
        for m in 0 to G_IMAGES * 396 - 1 loop
            read(fl, a); read(fl, b);
            reste := character'pos(b) * 256 + character'pos(a);
            while reste > 0 loop
                r  := alea(r);
                lg := 1 + to_integer(unsigned(r(4 downto 0))) mod 24;
                if lg > reste then lg := reste; end if;
                mot := (others => '0');
                for k in 1 to lg loop
                    if nb_oct = 0 then
                        read(fb, a);
                        octet_c := octet(a);
                        nb_oct := 8;
                    end if;
                    mot := mot(30 downto 0) & octet_c(nb_oct - 1);
                    nb_oct := nb_oct - 1;
                end loop;
                reste := reste - lg;
                s_code   <= mot;
                s_lg     <= to_unsigned(lg, 6);
                s_fin_mb <= '1' when reste = 0 else '0';
                s_valid  <= '1';
                loop
                    wait until rising_edge(clk);
                    exit when s_ready = '1';
                end loop;
            end loop;
        end loop;
        s_valid <= '0';
        wait;
    end process;

    pression : process (clk)
        variable r : std_logic_vector(15 downto 0) := x"1D0F";
    begin
        if rising_edge(clk) then
            r := alea(r);
            m_ready <= r(0) or r(2);
        end if;
    end process;

    controle : process (clk)
        file f          : octets_f open read_mode is REF & "es.bin";
        variable c      : character;
        variable n, err : natural := 0;
        variable cycles : natural := 0;
    begin
        if rising_edge(clk) then
            cycles := cycles + 1;
            if m_valid = '1' and m_ready = '1' and n < G_N_OUT then
                read(f, c);
                if m_data /= octet(c) then
                    if err < 10 then
                        report "ecart a l'octet " & integer'image(n) & " : " & to_hstring(m_data) & " au lieu de " & to_hstring(octet(c)) severity warning;
                    end if;
                    err := err + 1;
                end if;
                n := n + 1;
                if n = G_N_OUT then
                    if err = 0 then
                        report "OK es.bin : " & integer'image(n) & " octets identiques (" & integer'image(G_IMAGES) & " images, en-tetes et fin de sequence)";
                    else
                        report "ECHEC es.bin : " & integer'image(err) & " octets differents sur " & integer'image(n) severity error;
                    end if;
                    finish;
                end if;
            end if;
            if cycles > 40 * G_N_OUT + 100000 then
                report "ECHEC es.bin : delai depasse, " & integer'image(n) & " octets recus" severity error;
                finish;
            end if;
        end if;
    end process;
end architecture sim;
-- <<< tb_es.vhd

-- >>> tb_mire.vhd
--==============================================================================
--  Nom        : tb_mire.vhd
--  Projet     : JPEG2DVB, portage FPGA (émetteur DVB-S 23 cm)
--  Objet      : banc de test de la mire animée : macroblocs des 2 premières
--               images comparés à ceux de l'étape 01 (fpga_test/mire.png chargée,
--               option « mobile »)
--  Auteur     : Eric PERRET
--  Date       : 2026-10-19
--  Version    : 1.0
--  Plateforme : VHDL-2008, simulation (GHDL)
--  Licence    : CC BY-NC 4.0
--  Historique : 1.0  2026-10-19  création
--==============================================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;
use work.tb_pkg.all;

entity tb_mire is
    generic (
        G_N : natural := 304128              -- 2 images
    );
end entity tb_mire;

architecture sim of tb_mire is
    signal clk     : std_logic := '0';
    signal rst     : std_logic := '1';
    signal m_valid : std_logic;
    signal m_ready : std_logic := '1';
    signal m_data  : unsigned(7 downto 0);
    signal m_debut : std_logic;
begin
    clk <= not clk after 5 ns;
    dut : entity work.mire_gen port map (clk, rst, m_valid, m_ready, m_data, m_debut);

    process
    begin
        wait until rising_edge(clk);
        wait until rising_edge(clk);
        rst <= '0';
        wait;
    end process;

    pression : process (clk)
        variable r : std_logic_vector(15 downto 0) := x"1D0F";
    begin
        if rising_edge(clk) then
            r := alea(r);
            m_ready <= r(0) or r(2);
        end if;
    end process;

    controle : process (clk)
        file f          : octets_f open read_mode is REF & "mire_mb.bin";
        variable c      : character;
        variable n, err : natural := 0;
    begin
        if rising_edge(clk) then
            if m_valid = '1' and m_ready = '1' and n < G_N then
                read(f, c);
                if std_logic_vector(m_data) /= octet(c) then
                    if err < 10 then
                        report "ecart a l'octet " & integer'image(n) & " (image " & integer'image(n / 152064) & ", macrobloc " & integer'image((n mod 152064) / 384) &
                               ") : " & integer'image(to_integer(m_data)) & " au lieu de " & integer'image(character'pos(c)) severity warning;
                    end if;
                    err := err + 1;
                end if;
                if (n mod 152064 = 0) and m_debut /= '1' then
                    report "m_debut absent au debut de l'image" severity warning;
                    err := err + 1;
                end if;
                n := n + 1;
                if n = G_N then
                    if err = 0 then
                        report "OK mire_mb.bin : " & integer'image(n) & " octets identiques (" & integer'image(n / 152064) & " images)";
                    else
                        report "ECHEC mire_mb.bin : " & integer'image(err) & " octets differents sur " & integer'image(n) severity error;
                    end if;
                    finish;
                end if;
            end if;
        end if;
    end process;
end architecture sim;
-- <<< tb_mire.vhd

-- >>> tb_dvbs.vhd
--==============================================================================
--  Nom        : tb_dvbs.vhd
--  Projet     : JPEG2DVB, portage FPGA (émetteur DVB-S 23 cm)
--  Objet      : bancs de test de bout en bout, mire animée (fpga_test/mire.png,
--               3 images, DCT en virgule fixe, code d'échelle 8) :
--               G_DUT = 1 : video_enc, paquets TS prélevés au rythme du canal
--               (un par 13 056 cycles), comparés au TS de l'étape 08 ;
--               G_DUT = 2 : dvbs_tx, échantillons I/Q comparés au .cs16 de
--               l'étape 14
--  Auteur     : Eric PERRET
--  Date       : 2026-10-19
--  Version    : 1.0
--  Plateforme : VHDL-2008, simulation (GHDL)
--  Licence    : CC BY-NC 4.0
--  Historique : 1.0  2026-10-19  création
--==============================================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;
use work.tb_pkg.all;

entity tb_dvbs is
    generic (
        G_DUT : natural := 1;
        G_OUT : string  := "mire_ts.bin";
        G_N   : natural := 144572          -- octets TS (1) ou échantillons I/Q (2)
    );
end entity tb_dvbs;

architecture sim of tb_dvbs is
    signal clk     : std_logic := '0';
    signal rst     : std_logic := '1';
    signal code    : unsigned(4 downto 0) := to_unsigned(8, 5);
    signal m_valid : std_logic;
    signal m_ready : std_logic := '0';
    signal m_data  : std_logic_vector(7 downto 0);
    signal m_sop   : std_logic;
    signal m_i, m_q : signed(15 downto 0);
begin
    clk <= not clk after 6.25 ns;            -- 80 MHz

    g1 : if G_DUT = 1 generate
        dut : entity work.video_enc generic map (G_IMAGES => 3)
            port map (clk, rst, code, m_valid, m_ready, m_data, m_sop);
        -- un paquet de 188 octets par créneau de 13 056 cycles
        rythme : process (clk)
            variable cyc    : natural := 0;
            variable credit : integer := 0;
        begin
            if rising_edge(clk) then
                if rst = '0' then
                    if m_valid = '1' and m_ready = '1' then credit := credit - 1; end if;
                    if cyc = 0 then credit := credit + 188; end if;
                    cyc := (cyc + 1) mod 13056;
                    m_ready <= '1' when credit > 0 else '0';
                end if;
            end if;
        end process;
    elsif G_DUT = 2 generate
        dut : entity work.dvbs_tx generic map (G_IMAGES => 3)
            port map (clk, rst, code, m_valid, m_ready, m_i, m_q);
        m_ready <= '1';
    end generate;

    process
    begin
        wait until rising_edge(clk);
        wait until rising_edge(clk);
        rst <= '0';
        wait;
    end process;

    controle : process (clk)
        file f          : octets_f open read_mode is REF & G_OUT;
        variable a, b   : character;
        variable ei, eq : signed(15 downto 0);
        variable n, err : natural := 0;
        variable cycles : natural := 0;
    begin
        if rising_edge(clk) then
            cycles := cycles + 1;
            if m_valid = '1' and m_ready = '1' and n < G_N then
                if G_DUT = 1 then
                    read(f, a);
                    if m_data /= octet(a) then
                        if err < 10 then
                            report "ecart a l'octet " & integer'image(n) & " (paquet " & integer'image(n / 188) & ") : " & to_hstring(m_data) & " au lieu de " & to_hstring(octet(a)) severity warning;
                        end if;
                        err := err + 1;
                    end if;
                else
                    read(f, a); read(f, b); ei := signed(std_logic_vector'(octet(b) & octet(a)));
                    read(f, a); read(f, b); eq := signed(std_logic_vector'(octet(b) & octet(a)));
                    if m_i /= ei or m_q /= eq then
                        if err < 10 then
                            report "ecart a l'echantillon " & integer'image(n) severity warning;
                        end if;
                        err := err + 1;
                    end if;
                end if;
                n := n + 1;
                if n = G_N then
                    if err = 0 then
                        if G_DUT = 1 then
                            report "OK " & G_OUT & " : " & integer'image(n) & " octets TS identiques depuis la mire (" & integer'image(cycles) & " cycles)";
                        else
                            report "OK " & G_OUT & " : " & integer'image(n) & " echantillons I/Q identiques depuis la mire (" & integer'image(cycles) & " cycles)";
                        end if;
                    else
                        report "ECHEC " & G_OUT & " : " & integer'image(err) & " differences sur " & integer'image(n) severity error;
                    end if;
                    finish;
                end if;
            end if;
        end if;
    end process;
end architecture sim;
-- <<< tb_dvbs.vhd
