--==============================================================================
--  Nom        : jpeg2dvb_fpga_tb.vhd
--  Projet     : JPEG2DVB, portage FPGA (émetteur DVB-S 23 cm)
--  Objet      : bancs de test GHDL : chaque banc lit les références de
--               fpga_test/ et compare la sortie de son module au bit près
--  Auteur     : Eric PERRET
--  Date       : 2026-11-04
--  Version    : 2.4
--  Plateforme : VHDL-2008, simulation (GHDL) ; analyser d'abord jpeg2dvb_fpga.vhd
--  Licence    : CC BY-NC 4.0
--  Contenu    : 16 unités, dans l'ordre d'analyse :
--               tb_pkg        lecture des fichiers et des codes, générateur pseudo-aléatoire
--               tb_octets     modules à flux d'octets (09, 10, 11, TS)
--               tb_conv       codeur convolutif, 5 taux
--               tb_qpsk       QPSK
--               tb_srrc       filtre SRRC
--               tb_backend    chaîne arrière complète
--               tb_bloc       DCT, quantification, zigzag
--               tb_vlc        codage VLC
--               tb_es         flux élémentaire
--               tb_rc         régulation de débit TM5
--               tb_mire       mire animée
--               tb_dvbs       tête de chaîne et émetteur complet
--               tb_sdm        sortie sigma-delta
--               tb_bt656      récepteur BT.656
--               tb_tvp5150    modèle I²C du décodeur TVP5150AM1
--               tb_tvp        pilotage du TVP5150AM1 (3 scénarios)
--  Conventions: context jpeg2dvb_ctx (déclaré dans jpeg2dvb_fpga.vhd) ;
--               trous aléatoires en entrée et en sortie de chaque module à
--               contrôle de flux ;
--               process commentés « E : entrées → T : traitement → S : sorties »
--  Lancement  : fpga_test/run_tests.sh
--  Historique : 1.0  2026-10-19  bancs créés
--                    tb_octets 1.1 : multiplexeur TS (G_DUT = 4)
--               2.0  2026-10-19  fusion propre : cartouche unique, context
--                                commun, commentaires de fonction
--               2.1  2026-10-19  régulation TM5 : tb_pkg lit qcode.bin ;
--                                tb_bloc G_CODE = 0 : code de chaque rangée ;
--                                tb_es : slice_ok, code par slice ; tb_dvbs sans
--                                entrée code ; nouveau banc tb_rc
--               2.2  2026-10-19  nouveau banc tb_sdm (sortie sigma-delta)
--               2.3  2026-10-19  tb_sdm : entrée par les symboles QPSK (qpsk.bin)
--               2.4  2026-11-04  entrée vidéo PAL : tb_bt656 (bt656.bin),
--                                tb_tvp5150, tb_tvp (fonctionnement, décodeur
--                                absent, blocage du bus)
--==============================================================================

--------------------------------------------------------------------------------
-- tb_pkg : outils des bancs de test : lecture des fichiers binaires de
--   référence produits par JPEG2DVB, aléa reproductible pour
--   éprouver le contrôle de flux (valid / ready)
--------------------------------------------------------------------------------
context work.jpeg2dvb_ctx;

package tb_pkg is
    -- fichier binaire lu octet par octet
    type octets_f is file of character;
    function octet(c : character) return std_logic_vector;
    -- générateur pseudo-aléatoire 16 bits (Galois, x¹⁶ + x¹⁴ + x¹³ + x¹¹ + 1)
    function alea(r : std_logic_vector(15 downto 0)) return std_logic_vector;
    -- références : dossier de lancement (fpga_test/)
    constant REF : string := "./";
    -- quantiser_scale_code de chaque slice (qcode.bin, étape 03)
    type codes_t is array (natural range <>) of natural range 0 to 31;
    impure function lire_qcode(n : natural) return codes_t;
end package tb_pkg;

package body tb_pkg is
    -- octet : E : caractère lu dans un fichier binaire → S : octet
    function octet(c : character) return std_logic_vector is
    begin
        return std_logic_vector(to_unsigned(character'pos(c), 8));
    end function;

    -- alea : E : registre → T : un pas de Galois → S : registre suivant
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

    -- lire_qcode : E : nombre de slices → T : un octet par slice dans qcode.bin
    --   → S : codes des n premières slices
    impure function lire_qcode(n : natural) return codes_t is
        file f     : octets_f open read_mode is REF & "qcode.bin";
        variable c : character;
        variable r : codes_t(0 to n - 1);
    begin
        for i in r'range loop
            read(f, c);
            r(i) := character'pos(c);
        end loop;
        return r;
    end function;
end package body tb_pkg;

--------------------------------------------------------------------------------
-- tb_octets : banc de test des modules à flux d'octets (dispersion d'énergie,
--   Reed-Solomon, entrelaceur) : entrée lue dans un fichier de
--   JPEG2DVB, sortie comparée octet par octet au fichier de l'étape
--   suivante ; trous aléatoires côté entrée et côté sortie pour
--   éprouver le contrôle de flux
--   Paramètres : G_DUT 1 = prbs_disp, 2 = rs_enc, 3 = interleaver, 4 = ts_mux
--------------------------------------------------------------------------------
context work.jpeg2dvb_ctx;
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

--------------------------------------------------------------------------------
-- tb_conv : banc de test du codeur convolutif (taux G_FEC) : entrée = sortie
--   de l'entrelaceur (JPEG2DVB étape 11), sortie comparée bit à bit
--   aux bits codés de l'étape 12 (I puis Q de chaque symbole,
--   regroupés par octets, poids fort en tête)
--------------------------------------------------------------------------------
context work.jpeg2dvb_ctx;
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

    -- source : E : fichier d'entrée → T : une donnée par acceptation, trous
    --   aléatoires → S : flux vers le module
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

    -- pression : E : — → T : m_ready pseudo-aléatoire → S : contrôle de flux en
    --   sortie
    pression : process (clk)
        variable r : std_logic_vector(15 downto 0) := x"1D0F";
    begin
        if rising_edge(clk) then
            r := alea(r);
            m_ready <= r(0) or r(2);
        end if;
    end process;

    -- contrôle : E : sorties acceptées, fichier de référence → T : comparaison
    --   donnée par donnée, délai maximal → S : verdict OK / ECHEC
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

--------------------------------------------------------------------------------
-- tb_qpsk : banc de test de la mise en correspondance QPSK : entrée = bits
--   codés de l'étape 12, sortie comparée aux symboles entiers I, Q
--   (octets signés) de l'étape 13
--------------------------------------------------------------------------------
context work.jpeg2dvb_ctx;
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

    -- source : E : fichier d'entrée → T : une donnée par acceptation, trous
    --   aléatoires → S : flux vers le module
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

    -- pression : E : — → T : m_ready pseudo-aléatoire → S : contrôle de flux en
    --   sortie
    pression : process (clk)
        variable r : std_logic_vector(15 downto 0) := x"1D0F";
    begin
        if rising_edge(clk) then
            r := alea(r);
            m_ready <= r(0) or r(2);
        end if;
    end process;

    -- contrôle : E : sorties acceptées, fichier de référence → T : comparaison
    --   donnée par donnée, délai maximal → S : verdict OK / ECHEC
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

--------------------------------------------------------------------------------
-- tb_srrc : banc de test du filtre SRRC polyphase : entrée = symboles ±1
--   de l'étape 13, sortie comparée aux échantillons I/Q 16 bits
--   (petit-boutiste, entrelacés) du fichier .cs16 de l'étape 14
--------------------------------------------------------------------------------
context work.jpeg2dvb_ctx;
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

    -- source : E : fichier d'entrée → T : une donnée par acceptation, trous
    --   aléatoires → S : flux vers le module
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

    -- contrôle : E : sorties acceptées, fichier de référence → T : comparaison
    --   donnée par donnée, délai maximal → S : verdict OK / ECHEC
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

--------------------------------------------------------------------------------
-- tb_backend : banc de test de la chaîne arrière complète : paquets TS de
--   l'étape 08 en entrée, échantillons I/Q comparés au fichier
--   .cs16 de l'étape 14 ; sortie à plein débit (un échantillon
--   par cycle demandé, comme vers le sigma-delta)
--------------------------------------------------------------------------------
context work.jpeg2dvb_ctx;
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

    -- source : E : fichier d'entrée → T : une donnée par acceptation, trous
    --   aléatoires → S : flux vers le module
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

    -- contrôle : E : sorties acceptées, fichier de référence → T : comparaison
    --   donnée par donnée, délai maximal → S : verdict OK / ECHEC
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

--------------------------------------------------------------------------------
-- tb_bloc : banc de test des modules à blocs 8 × 8 du codage vidéo (DCT
--   entière, quantification, zigzag) : entrée et sortie comparées
--   aux fichiers de JPEG2DVB (image 0, 2 376 blocs)
--   Paramètres : G_DUT 1 = dct8x8_int (entrée octets), 2 = quant_intra,
--                3 = zigzag (entrée int16 LE) ; sortie int16 LE ;
--                G_CODE (quant_intra) : code fixe 1 à 31, ou 0 : code de chaque
--                rangée lu dans qcode.bin (rangée = coefficient / 8 448)
--------------------------------------------------------------------------------
context work.jpeg2dvb_ctx;
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
    constant RANGEE : natural := 22 * 384;           -- coefficients par rangée de macroblocs
    constant QC     : codes_t := lire_qcode(G_N / RANGEE);
begin
    clk <= not clk after 5 ns;

    g1 : if G_DUT = 1 generate
        dut : entity work.dct8x8_int port map (clk, rst, s_valid, s_ready, s_pix, m_valid, m_ready, m_data);
    elsif G_DUT = 2 generate
        dut : entity work.quant_intra port map (clk, rst, code, s_valid, s_ready, s_coef, m_valid, m_ready, m_data);
    elsif G_DUT = 3 generate
        dut : entity work.zigzag port map (clk, rst, s_valid, s_ready, s_coef, m_valid, m_ready, m_data);
    end generate;

    -- source : E : fichier d'entrée → T : une donnée par acceptation, trous
    --   aléatoires → S : flux vers le module
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
                if G_DUT = 2 and G_CODE = 0 then
                    code <= to_unsigned(QC(k / RANGEE), 5);
                end if;
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

    -- pression : E : — → T : m_ready pseudo-aléatoire → S : contrôle de flux en
    --   sortie
    pression : process (clk)
        variable r : std_logic_vector(15 downto 0) := x"1D0F";
    begin
        if rising_edge(clk) then
            r := alea(r);
            m_ready <= r(0) or r(2);
        end if;
    end process;

    -- contrôle : E : sorties acceptées, fichier de référence → T : comparaison
    --   donnée par donnée, délai maximal → S : verdict OK / ECHEC
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

--------------------------------------------------------------------------------
-- tb_vlc : banc de test du codeur VLC : vecteurs zigzag de l'image 0
--   (étape 04) en entrée ; mots de code mis bout à bout et
--   comparés bit à bit aux bits de l'étape 05, longueur de chaque
--   macrobloc comparée à la référence
--------------------------------------------------------------------------------
context work.jpeg2dvb_ctx;
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

    -- source : E : fichier d'entrée → T : une donnée par acceptation, trous
    --   aléatoires → S : flux vers le module
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

    -- pression : E : — → T : m_ready pseudo-aléatoire → S : contrôle de flux en
    --   sortie
    pression : process (clk)
        variable r : std_logic_vector(15 downto 0) := x"1D0F";
    begin
        if rising_edge(clk) then
            r := alea(r);
            m_ready <= r(0) or r(2);
        end if;
    end process;

    -- contrôle : E : sorties acceptées, fichier de référence → T : comparaison
    --   donnée par donnée, délai maximal → S : verdict OK / ECHEC
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

--------------------------------------------------------------------------------
-- tb_es : banc de test de l'assemblage du flux élémentaire : bits VLC
--   des macroblocs de l'étape 05 (toutes les images) en entrée,
--   découpés en mots de 1 à 24 bits ; sortie comparée octet par
--   octet au flux élémentaire de l'étape 06 (fin de séquence comprise) ;
--   code de chaque slice lu dans qcode.bin, slice_ok = 1 (code toujours prêt)
--------------------------------------------------------------------------------
context work.jpeg2dvb_ctx;
use std.env.all;
use work.tb_pkg.all;

entity tb_es is
    generic (
        G_IMAGES : natural := 3;
        G_N_OUT  : natural := 115224         -- taille de es.bin
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
    constant QC     : codes_t := lire_qcode(G_IMAGES * 18);
    signal slice    : natural range 0 to G_IMAGES * 18 - 1 := 0;
    signal code     : unsigned(4 downto 0);
    signal slice_ok : std_logic := '1';
begin
    clk <= not clk after 5 ns;
    code <= to_unsigned(QC(slice), 5);
    dut : entity work.es_mux generic map (G_IMAGES => G_IMAGES)
        port map (clk, rst, code, slice_ok, s_valid, s_ready, s_code, s_lg, s_fin_mb, m_valid, m_ready, m_data);

    -- slices : E : macroblocs acceptés → T : slice suivante après le dernier
    --   macrobloc de chaque rangée → S : rang de la slice, donc son code
    slices : process (clk)
        variable mb : natural range 0 to 21 := 0;
    begin
        if rising_edge(clk) then
            if s_valid = '1' and s_ready = '1' and s_fin_mb = '1' then
                if mb = 21 then
                    mb := 0;
                    if slice < G_IMAGES * 18 - 1 then slice <= slice + 1; end if;
                else
                    mb := mb + 1;
                end if;
            end if;
        end if;
    end process;

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

    -- pression : E : — → T : m_ready pseudo-aléatoire → S : contrôle de flux en
    --   sortie
    pression : process (clk)
        variable r : std_logic_vector(15 downto 0) := x"1D0F";
    begin
        if rising_edge(clk) then
            r := alea(r);
            m_ready <= r(0) or r(2);
        end if;
    end process;

    -- contrôle : E : sorties acceptées, fichier de référence → T : comparaison
    --   donnée par donnée, délai maximal → S : verdict OK / ECHEC
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

--------------------------------------------------------------------------------
-- tb_rc : banc de test de la régulation de débit TM5 (rate_ctrl) : compteur
--   en entrée de la vanne, mots VLC simulés depuis mbbits.bin (étape 05,
--   longueur de chaque macrobloc, mots de 1 à 24 bits) dès que les
--   coefficients du macrobloc ont franchi la vanne ; contrôle à chaque
--   coefficient sorti : donnée transmise telle quelle, code prêt et égal à
--   qcode.bin (étape 03) pour sa rangée, bits VLC de la rangée précédente
--   tous comptés (vanne)
--------------------------------------------------------------------------------
context work.jpeg2dvb_ctx;
use std.env.all;
use work.tb_pkg.all;

entity tb_rc is
    generic (
        G_IMAGES : natural := 3;
        G_COLS   : natural := 22;
        G_ROWS   : natural := 18;
        G_T      : natural := 350196
    );
end entity tb_rc;

architecture sim of tb_rc is
    constant NR    : natural := G_IMAGES * G_ROWS;        -- rangées (slices)
    constant NMB   : natural := NR * G_COLS;              -- macroblocs
    constant COEFS : natural := G_COLS * 384;             -- coefficients par rangée
    constant NC    : natural := NMB * 384;                -- coefficients
    constant QC    : codes_t := lire_qcode(NR);
    signal clk     : std_logic := '0';
    signal rst     : std_logic := '1';
    signal s_valid : std_logic := '0';
    signal s_ready : std_logic;
    signal s_data  : signed(15 downto 0) := (others => '0');
    signal m_valid : std_logic;
    signal m_ready : std_logic := '1';
    signal m_data  : signed(15 downto 0);
    signal v_valid : std_logic := '0';
    signal v_ready : std_logic := '1';
    signal v_lg    : unsigned(5 downto 0) := (others => '0');
    signal v_fin   : std_logic := '0';
    signal code    : unsigned(4 downto 0);
    signal code_ok : std_logic;
    signal mb_q    : natural := 0;                        -- macroblocs passés par la vanne
begin
    clk <= not clk after 5 ns;
    dut : entity work.rate_ctrl generic map (G_COLS => G_COLS, G_ROWS => G_ROWS, G_T => G_T, G_GOP => 12)
        port map (clk, rst, s_valid, s_ready, s_data, m_valid, m_ready, m_data, v_valid, v_ready, v_lg, v_fin, code, code_ok);

    -- source : E : — → T : compteur, un coefficient par acceptation, trous
    --   aléatoires → S : flux vers la vanne
    source : process
        variable r : std_logic_vector(15 downto 0) := x"ACE1";
    begin
        wait until rising_edge(clk);
        wait until rising_edge(clk);
        rst <= '0';
        for k in 0 to NC - 1 loop
            s_data <= to_signed(k mod 32768, 16);
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

    -- vlc : E : mbbits.bin, macroblocs passés par la vanne → T : bits de chaque
    --   macrobloc en mots de longueur pseudo-aléatoire, dernier mot marqué →
    --   S : mots VLC vers rate_ctrl
    vlc : process
        file fl       : octets_f open read_mode is REF & "mbbits.bin";
        variable a, b : character;
        variable reste, lg : natural;
        variable r    : std_logic_vector(15 downto 0) := x"BEEF";
    begin
        wait until rising_edge(clk);
        wait until rising_edge(clk);
        for m in 0 to NMB - 1 loop
            read(fl, a); read(fl, b);
            reste := character'pos(b) * 256 + character'pos(a);
            v_valid <= '0';
            while mb_q <= m loop
                wait until rising_edge(clk);
            end loop;
            while reste > 0 loop
                r  := alea(r);
                lg := 1 + to_integer(unsigned(r(4 downto 0))) mod 24;
                if lg > reste then lg := reste; end if;
                reste := reste - lg;
                v_lg    <= to_unsigned(lg, 6);
                v_fin   <= '1' when reste = 0 else '0';
                v_valid <= '1';
                loop
                    wait until rising_edge(clk);
                    exit when v_ready = '1';
                end loop;
            end loop;
        end loop;
        v_valid <= '0';
        wait;
    end process;

    -- pression : E : — → T : m_ready et v_ready pseudo-aléatoires → S : contrôle
    --   de flux en sortie de la vanne et côté assemblage
    pression : process (clk)
        variable r : std_logic_vector(15 downto 0) := x"1D0F";
    begin
        if rising_edge(clk) then
            r := alea(r);
            m_ready <= r(0) or r(2);
            v_ready <= r(5) or r(9);
        end if;
    end process;

    -- contrôle : E : coefficients sortis, mots VLC acceptés, code, code_ok,
    --   qcode.bin → T : donnée, code de la rangée, ordre vanne / VLC, délai
    --   maximal → S : verdict OK / ECHEC
    controle : process (clk)
        variable n, s       : natural := 0;
        variable mv         : natural := 0;
        variable err_d, err_c, err_v : natural := 0;
        variable vu         : natural := 0;                  -- rangées contrôlées
        variable cycles     : natural := 0;
    begin
        if rising_edge(clk) then
            cycles := cycles + 1;
            if v_valid = '1' and v_ready = '1' and v_fin = '1' then
                mv := mv + 1;
            end if;
            if m_valid = '1' and m_ready = '1' and n < NC then
                s := n / COEFS;
                if m_data /= to_signed(n mod 32768, 16) then
                    if err_d < 10 then
                        report "coefficient " & integer'image(n) & " altere par la vanne" severity warning;
                    end if;
                    err_d := err_d + 1;
                end if;
                if code_ok /= '1' or to_integer(code) /= QC(s) then
                    if err_c < 10 then
                        report "rangee " & integer'image(s) & " (image " & integer'image(s / G_ROWS) & ", slice " & integer'image(s mod G_ROWS) & ") : code " &
                               integer'image(to_integer(code)) & " (code_ok " & std_logic'image(code_ok) & ") au lieu de " & integer'image(QC(s)) severity warning;
                    end if;
                    err_c := err_c + 1;
                end if;
                if mv < s * G_COLS then
                    if err_v < 10 then
                        report "vanne ouverte trop tot : rangee " & integer'image(s) & " avec " & integer'image(mv) & " macroblocs VLC comptes" severity warning;
                    end if;
                    err_v := err_v + 1;
                end if;
                if n mod COEFS = 0 then vu := vu + 1; end if;
                n := n + 1;
                if n mod 384 = 0 then mb_q <= n / 384; end if;
            end if;
            if n = NC and mv = NMB then
                if err_d = 0 and err_c = 0 and err_v = 0 then
                    report "OK qcode.bin : " & integer'image(vu) & " codes de rangee identiques, " & integer'image(n) & " coefficients transmis, vanne respectee (" & integer'image(cycles) & " cycles)";
                else
                    report "ECHEC qcode.bin : " & integer'image(err_c) & " coefficients sous un mauvais code, " & integer'image(err_d) & " alteres, " & integer'image(err_v) & " passes trop tot" severity error;
                end if;
                finish;
            end if;
            if cycles > 8 * NC + 100000 then
                report "ECHEC qcode.bin : delai depasse, " & integer'image(n) & " coefficients et " & integer'image(mv) & " macroblocs VLC" severity error;
                finish;
            end if;
        end if;
    end process;
end architecture sim;

--------------------------------------------------------------------------------
-- tb_mire : banc de test de la mire animée : macroblocs des 2 premières
--   images comparés à ceux de l'étape 01 (fpga_test/mire.png chargée,
--   option « mobile »)
--------------------------------------------------------------------------------
context work.jpeg2dvb_ctx;
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

    -- réinitialisation : rst relâché après deux cycles
    process
    begin
        wait until rising_edge(clk);
        wait until rising_edge(clk);
        rst <= '0';
        wait;
    end process;

    -- pression : E : — → T : m_ready pseudo-aléatoire → S : contrôle de flux en
    --   sortie
    pression : process (clk)
        variable r : std_logic_vector(15 downto 0) := x"1D0F";
    begin
        if rising_edge(clk) then
            r := alea(r);
            m_ready <= r(0) or r(2);
        end if;
    end process;

    -- contrôle : E : sorties acceptées, fichier de référence → T : comparaison
    --   donnée par donnée, délai maximal → S : verdict OK / ECHEC
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

--------------------------------------------------------------------------------
-- tb_dvbs : bancs de test de bout en bout, mire animée (fpga_test/mire.png,
--   3 images, DCT entière, régulation TM5 interne) :
--   G_DUT = 1 : video_enc, paquets TS prélevés au rythme du canal
--   (un par 13 056 cycles), comparés au TS de l'étape 08 ;
--   G_DUT = 2 : dvbs_tx, échantillons I/Q comparés au .cs16 de
--   l'étape 14
--------------------------------------------------------------------------------
context work.jpeg2dvb_ctx;
use std.env.all;
use work.tb_pkg.all;

entity tb_dvbs is
    generic (
        G_DUT : natural := 1;
        G_OUT : string  := "mire_ts.bin";
        G_N   : natural := 148708          -- octets TS (1) ou échantillons I/Q (2)
    );
end entity tb_dvbs;

architecture sim of tb_dvbs is
    signal clk     : std_logic := '0';
    signal rst     : std_logic := '1';
    signal m_valid : std_logic;
    signal m_ready : std_logic := '0';
    signal m_data  : std_logic_vector(7 downto 0);
    signal m_sop   : std_logic;
    signal m_i, m_q : signed(15 downto 0);
begin
    clk <= not clk after 6.25 ns;            -- 80 MHz

    g1 : if G_DUT = 1 generate
        dut : entity work.video_enc generic map (G_IMAGES => 3)
            port map (clk, rst, m_valid, m_ready, m_data, m_sop);
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
            port map (clk, rst, m_valid, m_ready, m_i, m_q);
        m_ready <= '1';
    end generate;

    -- réinitialisation : rst relâché après deux cycles
    process
    begin
        wait until rising_edge(clk);
        wait until rising_edge(clk);
        rst <= '0';
        wait;
    end process;

    -- contrôle : E : sorties acceptées, fichier de référence → T : comparaison
    --   donnée par donnée, délai maximal → S : verdict OK / ECHEC
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

--------------------------------------------------------------------------------
-- tb_sdm : banc de test de la sortie sigma-delta : symboles QPSK de
--   qpsk.bin (étape 13) en entrée, avec trous aléatoires ; 8 bits I et 8 bits Q
--   par cycle comparés à sd_iq.bin (fpga_test/sdm.js) ; contre-pression
--   aléatoire en sortie
--------------------------------------------------------------------------------
context work.jpeg2dvb_ctx;
use std.env.all;
use work.tb_pkg.all;

entity tb_sdm is
    generic (
        G_N : natural := 160000              -- cycles de sortie (8 par symbole)
    );
end entity tb_sdm;

architecture sim of tb_sdm is
    signal clk     : std_logic := '0';
    signal rst     : std_logic := '1';
    signal s_valid : std_logic := '0';
    signal s_ready : std_logic;
    signal s_i     : std_logic := '0';
    signal s_q     : std_logic := '0';
    signal m_valid : std_logic;
    signal m_ready : std_logic := '1';
    signal m_i     : std_logic_vector(7 downto 0);
    signal m_q     : std_logic_vector(7 downto 0);
begin
    clk <= not clk after 6.25 ns;            -- 80 MHz
    dut : entity work.sigma_delta port map (clk, rst, s_valid, s_ready, s_i, s_q, m_valid, m_ready, m_i, m_q);

    -- source : E : qpsk.bin (I, Q signés 8 bits) → T : un symbole par
    --   acceptation (bit 1 pour −1), trous aléatoires ; un symbole de plus que
    --   la sortie comparée → S : bits I, Q vers le module
    source : process
        file f        : octets_f open read_mode is REF & "qpsk.bin";
        variable a, b : character;
        variable r    : std_logic_vector(15 downto 0) := x"ACE1";
    begin
        wait until rising_edge(clk);
        wait until rising_edge(clk);
        rst <= '0';
        for k in 0 to G_N / 8 loop
            read(f, a); read(f, b);
            s_i <= octet(a)(7); s_q <= octet(b)(7);
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

    -- pression : E : — → T : m_ready pseudo-aléatoire → S : contrôle de flux en
    --   sortie
    pression : process (clk)
        variable r : std_logic_vector(15 downto 0) := x"1D0F";
    begin
        if rising_edge(clk) then
            r := alea(r);
            m_ready <= r(0) or r(2);
        end if;
    end process;

    -- contrôle : E : bits acceptés, sd_iq.bin → T : comparaison octet par
    --   octet, délai maximal → S : verdict OK / ECHEC
    controle : process (clk)
        file f          : octets_f open read_mode is REF & "sd_iq.bin";
        variable a, b   : character;
        variable n, err : natural := 0;
        variable cycles : natural := 0;
    begin
        if rising_edge(clk) then
            cycles := cycles + 1;
            if m_valid = '1' and m_ready = '1' and n < G_N then
                read(f, a); read(f, b);
                if m_i /= octet(a) or m_q /= octet(b) then
                    if err < 10 then
                        report "ecart a cycle " & integer'image(n) & " : I " & to_hstring(m_i) & " au lieu de " & to_hstring(octet(a)) &
                               ", Q " & to_hstring(m_q) & " au lieu de " & to_hstring(octet(b)) severity warning;
                    end if;
                    err := err + 1;
                end if;
                n := n + 1;
                if n = G_N then
                    if err = 0 then
                        report "OK sd_iq.bin : " & integer'image(n) & " cycles, " & integer'image(16 * n) & " bits sigma-delta identiques (" & integer'image(cycles) & " cycles)";
                    else
                        report "ECHEC sd_iq.bin : " & integer'image(err) & " cycles differents sur " & integer'image(n) severity error;
                    end if;
                    finish;
                end if;
            end if;
            if cycles > 4 * G_N + 10000 then
                report "ECHEC sd_iq.bin : delai depasse, " & integer'image(n) & " cycles recus" severity error;
                finish;
            end if;
        end if;
    end process;
end architecture sim;

--------------------------------------------------------------------------------
-- tb_bt656 : banc du récepteur BT.656 : flux fpga_test/bt656.bin (un octet
--   par cycle de 27 MHz, entrée au milieu d'une ligne de suppression de
--   trame), couples comparés octet à octet à fpga_test/bt656_ref.bin ;
--   trame, ligne, position et début de trame vérifiés pour chaque couple ;
--   aucun couple ne doit sortir avant le premier début de trame ni après
--   la dernière ligne active
--------------------------------------------------------------------------------
context work.jpeg2dvb_ctx;
use std.env.all;
use work.tb_pkg.all;

entity tb_bt656 is
    generic (
        G_N : natural := 414720              -- couples attendus : 4 trames × 288 lignes × 360
    );
end entity tb_bt656;

architecture sim of tb_bt656 is
    constant N_TRAME : natural := 288 * 360;
    signal clk     : std_logic := '0';
    signal rst     : std_logic := '1';
    signal d       : std_logic_vector(7 downto 0) := x"10";
    signal fin_e   : boolean := false;
    signal o_valid, o_trame, o_dt, o_sync : std_logic;
    signal o_cb, o_y0, o_cr, o_y1 : std_logic_vector(7 downto 0);
    signal o_ligne, o_x : unsigned(8 downto 0);
begin
    clk <= not clk after 18.5 ns;
    dut : entity work.bt656_rx port map (clk, rst, d, o_valid, o_cb, o_y0, o_cr, o_y1, o_trame, o_ligne, o_x, o_dt, o_sync);

    -- entrée : E : bt656.bin → T : un octet par cycle après la remise à zéro
    --   → S : d, fin_e à la fin du fichier
    entree : process
        file f     : octets_f open read_mode is REF & "bt656.bin";
        variable c : character;
    begin
        wait until rising_edge(clk);
        wait until rising_edge(clk);
        rst <= '0';
        while not endfile(f) loop
            read(f, c);
            d <= octet(c);
            wait until rising_edge(clk);
        end loop;
        d <= x"10";
        fin_e <= true;
        wait;
    end process;

    -- contrôle : E : couples, bt656_ref.bin → T : comparaison des 4 octets,
    --   trame, ligne, position attendues ; 10 cycles après la fin de l'entrée
    --   → S : verdict OK / ECHEC
    controle : process (clk)
        file f           : octets_f open read_mode is REF & "bt656_ref.bin";
        variable c       : character;
        variable n, err  : natural := 0;
        variable att     : std_logic_vector(31 downto 0);
        variable fin_cpt : natural := 0;
        variable p       : natural;
    begin
        if rising_edge(clk) then
            if o_valid = '1' then
                if n >= G_N then
                    if err < 10 then report "couple en trop apres la reference" severity warning; end if;
                    err := err + 1;
                else
                    for i in 0 to 3 loop read(f, c); att(31 - 8 * i downto 24 - 8 * i) := octet(c); end loop;
                    p := n mod N_TRAME;
                    if (o_cb & o_y0 & o_cr & o_y1) /= att or o_x /= p mod 360 or o_ligne /= p / 360
                       or (o_trame = '1') /= ((n / N_TRAME) mod 2 = 1) or (o_dt = '1') /= (p = 0) then
                        if err < 10 then
                            report "ecart au couple " & integer'image(n) & " (trame " & integer'image(n / N_TRAME) & ", ligne " & integer'image(p / 360) &
                                   ", couple " & integer'image(p mod 360) & ") : ligne lue " & integer'image(to_integer(o_ligne)) & ", couple lu " & integer'image(to_integer(o_x)) severity warning;
                        end if;
                        err := err + 1;
                    end if;
                end if;
                n := n + 1;
            end if;
            if fin_e then
                fin_cpt := fin_cpt + 1;
                if fin_cpt = 10 then
                    if err = 0 and n = G_N and o_sync = '1' then
                        report "OK bt656_ref.bin : " & integer'image(n) & " couples identiques (4 trames, couleur et noir et blanc), trame, ligne et position conformes";
                    else
                        report "ECHEC bt656_ref.bin : " & integer'image(err) & " ecarts, " & integer'image(n) & " couples sur " & integer'image(G_N) severity error;
                    end if;
                    finish;
                end if;
            end if;
        end if;
    end process;
end architecture sim;

--------------------------------------------------------------------------------
-- tb_tvp5150 : modèle du décodeur TVP5150AM1 vu du bus I²C (adresse B8h) :
--   registres, identifiant 51h 50h, état 88h (bits 1, 2 : verrouillage
--   lignes et trames, bit 3 : sous-porteuse) calculé d'après les sources
--   src_a, src_b (0 : aucune, 1 : couleur, 2 : noir et blanc) et le
--   registre 00h, verrouillage 60 ms après la présence de la source et le
--   choix de l'entrée ; étire SCL de 10 µs après chaque acquittement ;
--   contrôle : RESETB relâché après 20 ms, aucun accès moins de 200 µs
--   après, PDN à 1, 64 µs entre la fin d'une écriture des registres 00h à
--   8Fh et le début suivant, écritures conformes à la configuration
--   attendue (reprise complète admise) puis seulement 00h ← 00h ou 02h ;
--   un début ou une fin interrompt l'octet en cours d'émission
--   Paramètres : G_ABS = 1 : décodeur absent (aucun acquittement) ;
--                G_ABS = 2 : blocage : SCL tenu à 0 pendant 20 ms après
--                l'adresse de lecture B9h de la première lecture passé 1,3 s,
--                puis octet repris là où il était (SDA tenu à 0)
--------------------------------------------------------------------------------
context work.jpeg2dvb_ctx;

entity tb_tvp5150 is
    generic (
        G_ABS : natural := 0
    );
    port (
        resetb  : in    std_logic;
        pdn     : in    std_logic;
        scl     : inout std_logic;
        sda     : inout std_logic;
        src_a   : in    natural;
        src_b   : in    natural;
        n_err   : out   natural;
        n_sel   : out   natural;
        n_debut : out   natural
    );
end entity tb_tvp5150;

architecture sim of tb_tvp5150 is
    signal scl_x, sda_x : std_logic;
    signal t_rst        : time := time'high;
    signal e_bus, e_chr : natural := 0;
begin
    scl_x <= to_x01(scl);
    sda_x <= to_x01(sda);
    n_err <= e_bus + e_chr;

    -- chronologie I²C (mode standard, 100 kHz) : E : SCL, SDA → T : SCL haut
    --   ≥ 4 µs, SCL bas ≥ 4,7 µs, début : tenue ≥ 4 µs, préparation ≥ 4,7 µs,
    --   bus libre ≥ 4,7 µs après une fin ; fin : préparation ≥ 4 µs
    --   → S : erreurs e_chr
    chrono : process
        variable t_haut, t_bas, t_deb, t_fin : time := 0 ns;
        variable deb : boolean := false;
        variable n   : natural := 0;
        procedure erreur(m : string) is
        begin
            if n < 10 then report "modele TVP5150 : " & m & " a " & time'image(now) severity warning; end if;
            n := n + 1; e_chr <= n;
        end procedure;
    begin
        wait on scl_x, sda_x;
        if now = 0 ns then
            null;                                          -- résolution initiale des lignes
        elsif scl_x'event then
            if scl_x = '1' then
                if now - t_bas < 4.7 us then erreur("SCL bas moins de 4,7 us"); end if;
                t_haut := now;
            else
                if now - t_haut < 4 us then erreur("SCL haut moins de 4 us"); end if;
                if deb and now - t_deb < 4 us then erreur("tenue du debut moins de 4 us"); end if;
                deb := false;
                t_bas := now;
            end if;
        elsif scl_x = '1' then
            if sda_x = '0' then
                if now - t_haut < 4.7 us then erreur("preparation du debut moins de 4,7 us"); end if;
                if now - t_fin < 4.7 us then erreur("bus libre moins de 4,7 us"); end if;
                deb := true; t_deb := now;
            else
                if now - t_haut < 4 us then erreur("preparation de la fin moins de 4 us"); end if;
                t_fin := now;
            end if;
        end if;
    end process;

    -- RESETB : E : broche → T : contrôle des 20 ms → S : instant du relâchement
    reset : process
    begin
        wait until resetb = '1';
        t_rst <= now;
        if now < 20 ms then report "modele TVP5150 : RESETB relache avant 20 ms" severity warning; end if;
        wait;
    end process;

    -- bus : E : SCL, SDA, sources → T : esclave I²C, registres, contrôles de
    --   chronologie et de configuration → S : SDA, SCL tirés, compteurs
    bus_i2c : process
        type regs_t is array (0 to 255) of std_logic_vector(7 downto 0);
        type init_t is array (0 to 48) of std_logic_vector(15 downto 0);
        -- attendu : E : — → S : écritures de la configuration dans l'ordre
        function attendu return init_t is
            variable t : init_t;
        begin
            t(0) := x"CF00";
            for i in 0 to 44 loop t(1 + i) := std_logic_vector(to_unsigned(16#D0# + i, 8)) & x"FF"; end loop;
            t(46) := x"2804"; t(47) := x"0000"; t(48) := x"0309";
            return t;
        end function;
        constant INIT     : init_t := attendu;
        variable regs     : regs_t := (16#03# => x"01", 16#0D# => x"47", 16#80# => x"51", 16#81# => x"50", others => x"00");
        variable ptr      : natural range 0 to 255 := 0;
        variable o        : std_logic_vector(7 downto 0);
        variable e, nb    : natural;
        variable v        : std_logic;
        variable nack     : boolean;
        variable err, nsel, ndeb, necr : natural := 0;
        variable t_sel    : time := 0 ns;
        variable t_stop   : time := 0 ns;
        variable ecr_bas  : boolean := false;     -- la transaction a écrit un registre 00h à 8Fh
        variable bloque_fait : boolean := false;

        procedure erreur(m : string) is
        begin
            if err < 10 then report "modele TVP5150 : " & m severity warning; end if;
            err := err + 1; e_bus <= err;
        end procedure;
        -- etat88 : E : registre 00h, sources, instants → S : registre d'état 1
        impure function etat88 return std_logic_vector is
            variable s : natural;
            variable r : std_logic_vector(7 downto 0) := x"00";
            variable t : time;
        begin
            if regs(0)(1 downto 0) = "10" then s := src_b; t := src_b'last_event; else s := src_a; t := src_a'last_event; end if;
            if s /= 0 and t >= 60 ms and now - t_sel >= 60 ms then
                r(2 downto 1) := "11";
                if s = 1 then r(3) := '1'; end if;
            end if;
            return r;
        end function;
        -- debut : E : — → T : contrôles à chaque condition de début
        procedure debut is
        begin
            ndeb := ndeb + 1; n_debut <= ndeb;
            if t_rst = time'high or now < t_rst + 200 us then erreur("acces I2C avant RESETB + 200 us"); end if;
            if pdn /= '1' then erreur("PDN a 0"); end if;
            if ecr_bas and now - t_stop < 64 us then erreur("moins de 64 us apres une ecriture"); end if;
            ecr_bas := false;
        end procedure;
        -- lit_bit : E : SCL, SDA → S : bit lu, e : 0 bit, 1 début, 2 fin
        procedure lit_bit(b : out std_logic; ev : out natural) is
        begin
            wait until scl_x = '1';
            b := sda_x;
            wait on scl_x, sda_x;
            if scl_x = '1' then
                if sda_x = '1' then ev := 2; else ev := 1; end if;
            else
                ev := 0;
            end if;
        end procedure;
        -- lit_octet : E : bus → S : octet, ev (début ou fin rencontré)
        procedure lit_octet(r : out std_logic_vector(7 downto 0); ev : out natural) is
            variable b  : std_logic;
            variable ee : natural;
        begin
            for i in 7 downto 0 loop
                lit_bit(b, ee);
                if ee /= 0 then ev := ee; return; end if;
                r(i) := b;
            end loop;
            ev := 0;
        end procedure;
        -- acquitte : E : premier bit à émettre ensuite ('1' : aucun ou bit à 1),
        --   blocage demandé → T : SDA à 0 pendant le 9e coup d'horloge, puis
        --   SCL tenu à 0 pendant 10 µs (étirement) ou 20 ms (blocage), le bit
        --   suivant posé avant de relâcher SCL
        procedure acquitte(suivant : std_logic; bloque : boolean) is
        begin
            sda <= '0';
            wait until scl_x = '1';
            wait until scl_x = '0';
            sda <= 'Z';
            scl <= '0';
            if bloque then wait for 20 ms; else wait for 10 us; end if;
            if suivant = '0' then sda <= '0'; end if;
            wait for 1 us;
            scl <= 'Z';
        end procedure;
        -- envoie : E : octet → T : 8 bits, poids fort en tête, puis lecture de
        --   l'acquittement du maître → S : nack ; ev : 1 ou 2 si un début ou une
        --   fin interrompt l'octet (SDA relâché)
        procedure envoie(r : std_logic_vector(7 downto 0); na : out boolean; ev : out natural) is
        begin
            ev := 0; na := true;
            for i in 7 downto 0 loop
                if r(i) = '0' then sda <= '0'; else sda <= 'Z'; end if;
                wait until scl_x = '1';
                wait on scl_x, sda_x;
                if scl_x = '1' then
                    sda <= 'Z';
                    if sda_x = '1' then ev := 2; else ev := 1; end if;
                    return;
                end if;
            end loop;
            sda <= 'Z';
            wait until scl_x = '1';
            na := sda_x = '1';
            wait until scl_x = '0';
        end procedure;
        -- ecrit : E : registre, valeur → T : rangement, contrôle de l'ordre
        procedure ecrit(r : natural; val : std_logic_vector(7 downto 0)) is
        begin
            regs(r) := val;
            if r <= 16#8F# then ecr_bas := true; end if;
            if necr > 48 and r = 16#CF# and val = x"00" then
                necr := 0;                                 -- reprise de la configuration (après blocage)
            end if;
            if necr <= 48 then
                if std_logic_vector(to_unsigned(r, 8)) & val /= INIT(necr) then
                    erreur("ecriture " & integer'image(necr) & " inattendue : registre " & integer'image(r) & " <- " & integer'image(to_integer(unsigned(val))));
                end if;
            elsif r /= 0 or (val /= x"00" and val /= x"02") then
                erreur("ecriture hors choix d'entree apres la configuration");
            end if;
            if r = 0 then nsel := nsel + 1; n_sel <= nsel; t_sel := now; end if;
            necr := necr + 1;
        end procedure;
    begin
        scl <= 'Z'; sda <= 'Z';
        e_bus <= 0; n_sel <= 0; n_debut <= 0;
        loop
            wait on sda_x until sda_x = '0' and scl_x = '1';
            debut;
            trans : loop
                lit_octet(o, e);
                if e = 1 then debut; next trans; elsif e = 2 then exit trans; end if;
                exit trans when G_ABS = 1 or o(7 downto 1) /= "1011100";
                if o(0) = '0' then
                    -- écriture : registre puis données
                    acquitte('1', false);
                    lit_octet(o, e);
                    if e = 1 then debut; next trans; elsif e = 2 then exit trans; end if;
                    ptr := to_integer(unsigned(o));
                    acquitte('1', false);
                    nb := 0;
                    loop
                        lit_octet(o, e);
                        if e = 2 then t_stop := now; exit trans; end if;
                        if e = 1 then t_stop := now; debut; next trans; end if;
                        ecrit(ptr, o);
                        acquitte('1', false);
                        ptr := (ptr + 1) mod 256;
                        nb := nb + 1;
                    end loop;
                else
                    -- lecture : octets jusqu'au NACK, puis fin ; blocage éventuel
                    if ptr = 16#88# then o := etat88; else o := regs(ptr); end if;
                    if G_ABS = 2 and not bloque_fait and now >= 1300 ms then
                        bloque_fait := true;
                        acquitte(o(7), true);
                    else
                        acquitte(o(7), false);
                    end if;
                    loop
                        envoie(o, nack, e);
                        if e = 1 then debut; next trans; elsif e = 2 then exit trans; end if;
                        ptr := (ptr + 1) mod 256;
                        exit when nack;
                        if ptr = 16#88# then o := etat88; else o := regs(ptr); end if;
                    end loop;
                    wait on sda_x until sda_x = '1' and scl_x = '1';
                    exit trans;
                end if;
            end loop;
        end loop;
    end process;
end architecture sim;

--------------------------------------------------------------------------------
-- tb_tvp : banc de tvp_ctrl avec le modèle tb_tvp5150 ; horloge 2 MHz (les
--   délais de tvp_ctrl sont tirés de G_HZ : chronologie réelle), I²C 100 kHz
--   Scénario G_ABS = 0 : AIP1A sans signal, AIP1B en couleur → verrouillage
--   sur B ; à 1,5 s, B disparaît, A en noir et blanc → video_ok tombe,
--   retour sur A après 1 s, verrouillage ; de 3,2 à 3,5 s, coupure de A →
--   video_ok tombe puis revient sans changement d'entrée
--   Scénario G_ABS = 1 : décodeur absent → present et video_ok restent à 0,
--   l'identifiant est relu chaque seconde
--   Scénario G_ABS = 2 : verrouillé sur B, transaction bloquée à 1,3 s (SCL
--   tenu 20 ms, puis SDA tenu à 0) → garde, décodeur réputé absent, bus
--   libéré, nouvelle configuration, verrouillage sur B
--------------------------------------------------------------------------------
context work.jpeg2dvb_ctx;
use std.env.all;

entity tb_tvp is
    generic (
        G_ABS : natural := 0
    );
end entity tb_tvp;

architecture sim of tb_tvp is
    signal clk     : std_logic := '0';
    signal rst     : std_logic := '1';
    signal scl, sda : std_logic;
    signal scl_oe, sda_oe, scl_x, sda_x : std_logic;
    signal resetb, pdn, present, video_ok, entree : std_logic;
    signal src_a, src_b : natural := 0;
    signal n_err, n_sel, n_debut : natural;
begin
    clk <= not clk after 250 ns;
    -- bus : rappels, maître à drain ouvert
    scl <= 'H';
    sda <= 'H';
    scl <= '0' when scl_oe = '1' else 'Z';
    sda <= '0' when sda_oe = '1' else 'Z';
    scl_x <= to_x01(scl);
    sda_x <= to_x01(sda);

    dut : entity work.tvp_ctrl generic map (G_HZ => 2_000_000, G_I2C_HZ => 100_000)
        port map (clk, rst, resetb, pdn, scl_oe, sda_oe, scl_x, sda_x, present, video_ok, entree);
    modele : entity work.tb_tvp5150 generic map (G_ABS => G_ABS)
        port map (resetb, pdn, scl, sda, src_a, src_b, n_err, n_sel, n_debut);

    -- scénario et contrôle : E : sorties de tvp_ctrl, compteurs du modèle
    --   → T : sources changées aux instants du scénario, états attendus
    --   vérifiés à des instants éloignés des transitions → S : verdict
    process
        variable err : natural := 0;
        -- voir : E : instant, present, video_ok, entree attendus → T : attente,
        --   comparaison → S : err
        procedure voir(t : time; pr, ok, ent : std_logic; m : string) is
        begin
            wait for t - now;
            if present /= pr or video_ok /= ok or entree /= ent then
                report m & " : present = " & std_logic'image(present) & ", video_ok = " & std_logic'image(video_ok) &
                       ", entree = " & std_logic'image(entree) severity warning;
                err := err + 1;
            end if;
        end procedure;
        -- verdict : E : nom, choix d'entrée attendus, texte → S : ligne OK / ECHEC
        procedure verdict(nom : string; nsel : natural; m : string) is
        begin
            if n_sel /= nsel then
                report "choix d'entree : " & integer'image(n_sel) & " ecritures de 00h au lieu de " & integer'image(nsel) severity warning;
                err := err + 1;
            end if;
            if err = 0 and n_err = 0 then
                report "OK " & nom & " : " & m & " (" & integer'image(n_debut) & " debuts I2C)";
            else
                report "ECHEC " & nom & " : " & integer'image(err) & " etats faux, " & integer'image(n_err) & " erreurs du modele" severity error;
            end if;
        end procedure;
    begin
        wait for 1 us;
        rst <= '0';
        if G_ABS = 0 then
            src_b <= 1;
            voir(600 ms, '1', '0', '0', "600 ms (acquisition sur A)");
            voir(1200 ms, '1', '1', '1', "1,2 s (verrouille sur B)");
            wait for 1500 ms - now;
            src_b <= 0; src_a <= 2;
            voir(1550 ms, '1', '0', '1', "1,55 s (perte de B)");
            voir(2400 ms, '1', '0', '1', "2,4 s (attente avant retour sur A)");
            voir(3000 ms, '1', '1', '0', "3 s (verrouille sur A, noir et blanc)");
            wait for 3200 ms - now;
            src_a <= 0;
            voir(3250 ms, '1', '0', '0', "3,25 s (coupure de A)");
            wait for 3500 ms - now;
            src_a <= 2;
            voir(3800 ms, '1', '1', '0', "3,8 s (A revenu, meme entree)");
            verdict("tvp", 3, "configuration conforme (49 ecritures), verrouillage sur B, perte, retour sur A en noir et blanc, coupure breve sans changement d'entree");
        elsif G_ABS = 1 then
            src_a <= 1;
            voir(2500 ms, '0', '0', '0', "2,5 s (decodeur absent)");
            if n_debut /= 6 then report integer'image(n_debut) & " debuts au lieu de 6 (3 essais de lecture)" severity warning; err := err + 1; end if;
            verdict("tvp_abs", 0, "decodeur absent, present et video_ok a 0, identifiant relu chaque seconde");
        else
            src_b <= 1;
            voir(1200 ms, '1', '1', '1', "1,2 s (verrouille sur B)");
            voir(1350 ms, '0', '0', '1', "1,35 s (transaction bloquee, decodeur repute absent)");
            voir(2600 ms, '1', '0', '0', "2,6 s (bus libere, decodeur reconfigure, acquisition sur A)");
            voir(3600 ms, '1', '1', '1', "3,6 s (verrouille sur B)");
            verdict("tvp_bloc", 4, "SCL bloque 20 ms : garde, liberation du bus (SDA tenu a 0), nouvelle configuration, verrouillage sur B");
        end if;
        finish;
    end process;
end architecture sim;
