--==============================================================================
--  Nom        : ts_mux.vhd
--  Projet     : JPEG2DVB, portage FPGA (émetteur DVB-S 23 cm)
--  Objet      : mise en paquets PES (un par image) et multiplexage Transport
--               Stream à débit constant ; référence bit à bit : JPEG2DVB
--               étapes 07 et 08 (version 2.4, instants en entiers exacts)
--  Auteur     : Eric PERRET
--  Date       : 2026-10-19
--  Version    : 1.0
--  Plateforme : VHDL-2008, synthétisable (Libero SoC)
--  Licence    : CC BY-NC 4.0
--  Interface  : entrée : octets du flux élémentaire (es_mux) ; sortie : paquets
--               TS de 188 octets (m_sop sur la synchro), un paquet par créneau
--  Principe   : le flux élémentaire est rangé dans une mémoire tournante de
--               128 Ko ; les débuts d'image (sequence_header, ou picture_start
--               hors en-tête de séquence) et la fin de séquence sont repérés
--               par leurs codes de début. Le paquet k (créneau de 1 504 bits au
--               débit TS) est choisi dans l'ordre : PAT puis PMT toutes les
--               80 ms ; PCR toutes les 30 ms ; vidéo si l'image n est
--               disponible (instant ≥ (n+1)/25) ; sinon PCR seul ou paquet nul.
--               Instants exacts pour 10 MS/s, FEC 1/2 (R_ts = 9 215 686,27 bit/s) :
--               t_k ≥ a/b ⇔ 51·k ≥ a·12 500·25/b, soit 51k ≥ 25 000·m (PSI),
--               51k ≥ 9 375·m (PCR), 51k ≥ 12 500·(n+1) (images).
--               PCR(k) = round((188k + 10)·5 508 / 235), tenu en cumul exact :
--               +4 406 par créneau, +1 tous les 470/188 créneaux.
--               PES : 00 00 01 E0, longueur, 84 80 05, PTS = 3 600·(n+1) + 9 000.
--  Historique : 1.0  2026-10-19  création
--==============================================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity ts_mux is
    generic (
        G_K     : natural := 51;            -- 51 k  ≥  …  (créneau k)
        G_PSI   : natural := 25000;         -- période PAT/PMT 80 ms
        G_PCR   : natural := 9375;          -- période PCR 30 ms
        G_IMG   : natural := 12500;         -- période image 40 ms
        G_GOP   : natural := 12
    );
    port (
        clk     : in  std_logic;
        rst     : in  std_logic;
        s_valid : in  std_logic;
        s_ready : out std_logic;
        s_data  : in  std_logic_vector(7 downto 0);
        m_valid : out std_logic;
        m_ready : in  std_logic;
        m_data  : out std_logic_vector(7 downto 0);
        m_sop   : out std_logic
    );
end entity ts_mux;

architecture rtl of ts_mux is
    subtype octet_t is std_logic_vector(7 downto 0);
    type octets_t is array (natural range <>) of octet_t;

    -- CRC-32 MPEG-2 (polynôme 0x04C11DB7, registre initial 0xFFFFFFFF)
    function crc32(d : octets_t) return std_logic_vector is
        variable c : std_logic_vector(31 downto 0) := (others => '1');
        variable f : std_logic;
    begin
        for i in d'range loop
            for b in 7 downto 0 loop
                f := c(31) xor d(i)(b);
                c := c(30 downto 0) & '0';
                if f = '1' then c := c xor x"04C11DB7"; end if;
            end loop;
        end loop;
        return c;
    end function;
    function paquet_psi(entete : octets_t; section : octets_t) return octets_t is
        variable p : octets_t(0 to 187) := (others => x"FF");
        variable c : std_logic_vector(31 downto 0) := crc32(section);
        variable j : natural := 0;
    begin
        for i in entete'range loop p(j) := entete(i); j := j + 1; end loop;
        for i in section'range loop p(j) := section(i); j := j + 1; end loop;
        p(j) := c(31 downto 24); p(j + 1) := c(23 downto 16); p(j + 2) := c(15 downto 8); p(j + 3) := c(7 downto 0);
        return p;
    end function;
    -- PAT : programme 1 → PMT PID 0x0100 ; PMT : vidéo MPEG-2 PID 0x0101, PCR sur 0x0101
    constant PAT : octets_t(0 to 187) := paquet_psi((x"47", x"40", x"00", x"10", x"00"),
        (x"00", x"B0", x"0D", x"00", x"01", x"C1", x"00", x"00", x"00", x"01", x"E1", x"00"));
    constant PMT : octets_t(0 to 187) := paquet_psi((x"47", x"41", x"00", x"10", x"00"),
        (x"02", x"B0", x"12", x"00", x"01", x"C1", x"00", x"00", x"E1", x"01", x"F0", x"00", x"02", x"E1", x"01", x"F0", x"00"));

    -- mémoire du flux élémentaire
    constant AB : natural := 17;
    type ram_t is array (0 to 2 ** AB - 1) of octet_t;
    signal ram    : ram_t;
    signal ecr    : unsigned(AB - 1 downto 0) := (others => '0');
    signal der3   : std_logic_vector(23 downto 0) := (others => '1');   -- 3 derniers octets
    signal en_tete_seq : std_logic := '0';
    type adr_t is array (0 to 7) of unsigned(AB - 1 downto 0);
    signal au_deb, au_fin : adr_t := (others => (others => '0'));
    signal nb_deb, nb_cpl : unsigned(31 downto 0) := (others => '0');   -- images commencées, complètes

    -- ordonnancement
    type type_t is (T_PAT, T_PMT, T_PCR, T_NUL, T_VID);
    signal typ      : type_t := T_NUL;
    signal k        : unsigned(31 downto 0) := (others => '0');
    signal m_psi, m_pcr : unsigned(31 downto 0) := (others => '0');
    signal pmt_du   : std_logic := '0';
    signal pcr_base : unsigned(32 downto 0) := (others => '0');
    signal pcr_ext  : unsigned(8 downto 0) := to_unsigned(234, 9);
    signal pcr_r    : natural range 0 to 469 := 415;
    signal p_base   : unsigned(32 downto 0);
    signal p_ext    : unsigned(8 downto 0);
    signal cc_pat, cc_pmt, cc_vid : unsigned(3 downto 0) := (others => '0');
    signal n_vid    : unsigned(31 downto 0) := (others => '0');
    signal n_gop    : natural range 0 to 255 := 0;
    signal pes_ptr  : natural range 0 to 2 ** AB + 16 := 0;    -- octet suivant du PES en cours
    signal pes_lg   : natural range 0 to 2 ** AB + 16 := 0;
    signal debut, avec_pcr, rai : std_logic := '0';
    signal afl      : natural range 0 to 184 := 0;
    signal actif    : std_logic := '0';
    signal pos      : natural range 0 to 187 := 0;
    -- pipeline de sortie
    signal a_valid, a_ram, a_sop : std_logic := '0';
    signal a_oct, ram_q : octet_t := (others => '0');
    signal o_valid  : std_logic := '0';
    signal libre    : std_logic;
    signal place    : std_logic;
begin
    libre   <= (not o_valid) or m_ready;
    m_valid <= o_valid;
    s_ready <= place and not rst;

    -- place libre : on ne recouvre pas l'image la plus ancienne non encore envoyée
    process (all)
        variable base : unsigned(AB - 1 downto 0);
    begin
        if n_vid < nb_deb then
            base := au_deb(to_integer(n_vid(2 downto 0)));
        else
            base := ecr;
        end if;
        if (ecr - base) < 2 ** AB - 16 and nb_deb - n_vid < 7 then place <= '1'; else place <= '0'; end if;
    end process;

    process (clk)
        variable w      : unsigned(AB - 1 downto 0);
        variable fire_psi, fire_pcr, pret : boolean;
        variable af, maxcu, cu, reste : natural range 0 to 2 ** AB + 16;
        variable oct    : octet_t;
        variable lit    : boolean;
        variable adr    : unsigned(AB - 1 downto 0);
        variable pts    : unsigned(32 downto 0);
        variable lp     : natural range 0 to 2 ** AB + 16;
        variable carry  : natural range 0 to 1;
        variable e2     : natural range 0 to 1023;
        variable ni     : natural range 0 to 7;
    begin
        if rising_edge(clk) then
            if rst = '1' then
                ecr <= (others => '0'); der3 <= (others => '1'); en_tete_seq <= '0';
                nb_deb <= (others => '0'); nb_cpl <= (others => '0');
                k <= (others => '0'); m_psi <= (others => '0'); m_pcr <= (others => '0'); pmt_du <= '0';
                pcr_base <= (others => '0'); pcr_ext <= to_unsigned(234, 9); pcr_r <= 415;
                cc_pat <= (others => '0'); cc_pmt <= (others => '0'); cc_vid <= (others => '0');
                n_vid <= (others => '0'); n_gop <= 0; pes_ptr <= 0; actif <= '0'; pos <= 0;
                a_valid <= '0'; o_valid <= '0';
            else
                ----------------------------------------------------------------
                -- écriture du flux élémentaire, repérage des images
                ----------------------------------------------------------------
                if s_valid = '1' and place = '1' then
                    w := ecr;
                    ram(to_integer(w)) <= s_data;
                    ecr  <= w + 1;
                    der3 <= der3(15 downto 0) & s_data;
                    if der3 = x"000001" then
                        if s_data = x"B3" or (s_data = x"00" and en_tete_seq = '0') then
                            -- début d'image à w − 3 ; l'image précédente est complète
                            if nb_deb > 0 then
                                au_fin(to_integer(nb_deb(2 downto 0) - 1)) <= w - 3;
                                nb_cpl <= nb_cpl + 1;
                            end if;
                            au_deb(to_integer(nb_deb(2 downto 0))) <= w - 3;
                            nb_deb <= nb_deb + 1;
                            en_tete_seq <= '1' when s_data = x"B3" else '0';
                        elsif s_data = x"00" then
                            en_tete_seq <= '0';
                        elsif s_data = x"B7" then
                            -- fin de séquence : la dernière image se termine après ce code
                            au_fin(to_integer(nb_deb(2 downto 0) - 1)) <= w + 1;
                            nb_cpl <= nb_cpl + 1;
                        end if;
                    end if;
                end if;

                ----------------------------------------------------------------
                -- sortie : étage B (octet final), étage A (choix et lecture)
                ----------------------------------------------------------------
                if libre = '1' then
                    o_valid <= a_valid;
                    m_sop   <= a_sop;
                    m_data  <= ram_q when a_ram = '1' else a_oct;

                    if actif = '0' then
                        -- choix du paquet du créneau k
                        a_valid  <= '0';
                        fire_psi := resize(k * G_K, 48) >= resize(m_psi * G_PSI, 48);
                        fire_pcr := resize(k * G_K, 48) >= resize(m_pcr * G_PCR, 48);
                        pret     := n_vid < nb_cpl and resize(k * G_K, 48) >= resize((n_vid + 1) * G_IMG, 48);
                        avec_pcr <= '0';
                        if fire_psi then
                            typ <= T_PAT; pmt_du <= '1'; m_psi <= m_psi + 1;
                        elsif pmt_du = '1' then
                            typ <= T_PMT; pmt_du <= '0';
                        else
                            if fire_pcr then m_pcr <= m_pcr + 1; avec_pcr <= '1'; end if;
                            if not pret then
                                typ <= T_PCR when fire_pcr else T_NUL;
                            else
                                typ <= T_VID;
                                ni := to_integer(n_vid(2 downto 0));
                                if pes_ptr = 0 then
                                    lp := to_integer(au_fin(ni) - au_deb(ni)) + 14;
                                    pes_lg <= lp;
                                else
                                    lp := pes_lg;
                                end if;
                                debut <= '1' when pes_ptr = 0 else '0';
                                rai   <= '1' when pes_ptr = 0 and n_gop = 0 else '0';
                                if fire_pcr then af := 8; elsif pes_ptr = 0 and n_gop = 0 then af := 2; else af := 0; end if;
                                maxcu := 184 - af;
                                reste := lp - pes_ptr;
                                if reste < maxcu then cu := reste; else cu := maxcu; end if;
                                afl <= af + maxcu - cu;
                            end if;
                        end if;
                        p_base <= pcr_base; p_ext <= pcr_ext;
                        -- PCR du créneau suivant
                        e2 := pcr_r + 188;
                        if e2 >= 470 then carry := 1; e2 := e2 - 470; else carry := 0; end if;
                        pcr_r <= e2;
                        if to_integer(pcr_ext) + 206 + carry >= 300 then
                            pcr_ext  <= to_unsigned(to_integer(pcr_ext) + 206 + carry - 300, 9);
                            pcr_base <= pcr_base + 15;
                        else
                            pcr_ext  <= to_unsigned(to_integer(pcr_ext) + 206 + carry, 9);
                            pcr_base <= pcr_base + 14;
                        end if;
                        k     <= k + 1;
                        actif <= '1';
                        pos   <= 0;
                    else
                        -- octet pos du paquet choisi
                        oct := x"FF"; lit := false; adr := (others => '0');
                        case typ is
                            when T_PAT =>
                                oct := PAT(pos);
                                if pos = 3 then oct := x"1" & std_logic_vector(cc_pat); end if;
                            when T_PMT =>
                                oct := PMT(pos);
                                if pos = 3 then oct := x"1" & std_logic_vector(cc_pmt); end if;
                            when T_NUL =>
                                case pos is
                                    when 0 => oct := x"47"; when 1 => oct := x"1F"; when 2 => oct := x"FF"; when 3 => oct := x"10";
                                    when others => null;
                                end case;
                            when T_PCR | T_VID =>
                                case pos is
                                    when 0 => oct := x"47";
                                    when 1 => oct := x"41" when typ = T_VID and debut = '1' else x"01";
                                    when 2 => oct := x"01";
                                    when 3 =>
                                        if typ = T_PCR then oct := x"2" & std_logic_vector(cc_vid);
                                        elsif afl > 0 then oct := x"3" & std_logic_vector(cc_vid);
                                        else oct := x"1" & std_logic_vector(cc_vid); end if;
                                    when others => null;
                                end case;
                                if typ = T_PCR then
                                    if pos = 4 then oct := std_logic_vector(to_unsigned(183, 8)); end if;
                                    if pos = 5 then oct := x"10"; end if;
                                end if;
                                if (typ = T_PCR or (typ = T_VID and avec_pcr = '1')) and pos >= 6 and pos <= 11 then
                                    case pos is
                                        when 6  => oct := std_logic_vector(p_base(32 downto 25));
                                        when 7  => oct := std_logic_vector(p_base(24 downto 17));
                                        when 8  => oct := std_logic_vector(p_base(16 downto 9));
                                        when 9  => oct := std_logic_vector(p_base(8 downto 1));
                                        when 10 => oct := p_base(0) & "111111" & p_ext(8);
                                        when others => oct := std_logic_vector(p_ext(7 downto 0));
                                    end case;
                                end if;
                                if typ = T_VID and pos >= 4 then
                                    if afl > 0 and pos = 4 then
                                        oct := std_logic_vector(to_unsigned(afl - 1, 8));
                                    elsif afl > 1 and pos = 5 then
                                        oct := '0' & rai & '0' & avec_pcr & "0000";      -- random_access, PCR_flag
                                    elsif pos >= 4 + afl then
                                        -- charge utile : en-tête PES puis flux élémentaire
                                        ni := to_integer(n_vid(2 downto 0));
                                        pts := to_unsigned(3600, 12) * resize(n_vid + 1, 21) + 9000;
                                        case pes_ptr is
                                            when 0 | 1 => oct := x"00";
                                            when 2  => oct := x"01";
                                            when 3  => oct := x"E0";
                                            when 4  => if pes_lg - 6 > 65535 then oct := x"00"; else oct := std_logic_vector(to_unsigned((pes_lg - 6) / 256, 8)); end if;
                                            when 5  => if pes_lg - 6 > 65535 then oct := x"00"; else oct := std_logic_vector(to_unsigned((pes_lg - 6) mod 256, 8)); end if;
                                            when 6  => oct := x"84";
                                            when 7  => oct := x"80";
                                            when 8  => oct := x"05";
                                            when 9  => oct := "0010" & std_logic_vector(pts(32 downto 30)) & '1';
                                            when 10 => oct := std_logic_vector(pts(29 downto 22));
                                            when 11 => oct := std_logic_vector(pts(21 downto 15)) & '1';
                                            when 12 => oct := std_logic_vector(pts(14 downto 7));
                                            when 13 => oct := std_logic_vector(pts(6 downto 0)) & '1';
                                            when others =>
                                                lit := true;
                                                adr := au_deb(ni) + to_unsigned(pes_ptr - 14, AB);
                                        end case;
                                        if pes_ptr = pes_lg - 1 then
                                            pes_ptr <= 0;
                                            n_vid   <= n_vid + 1;
                                            n_gop   <= 0 when n_gop = G_GOP - 1 else n_gop + 1;
                                        else
                                            pes_ptr <= pes_ptr + 1;
                                        end if;
                                    end if;
                                end if;
                        end case;
                        a_oct   <= oct;
                        a_ram   <= '1' when lit else '0';
                        a_sop   <= '1' when pos = 0 else '0';
                        a_valid <= '1';
                        ram_q   <= ram(to_integer(adr));
                        if pos = 187 then
                            actif <= '0';
                            case typ is
                                when T_PAT => cc_pat <= cc_pat + 1;
                                when T_PMT => cc_pmt <= cc_pmt + 1;
                                when T_VID => cc_vid <= cc_vid + 1;
                                when others => null;
                            end case;
                        else
                            pos <= pos + 1;
                        end if;
                    end if;
                end if;
            end if;
        end if;
    end process;
end architecture rtl;
