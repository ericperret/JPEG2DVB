--==============================================================================
--  Nom        : rate_ctrl.vhd
--  Projet     : JPEG2DVB, portage FPGA (émetteur DVB-S 23 cm)
--  Objet      : régulation de débit TM5 en entiers, un quantiser_scale_code par
--               rangée de macroblocs (slice) ; référence bit à bit : JPEG2DVB
--               étape 03 (3.0)
--  Auteur     : Eric PERRET
--  Date       : 2026-10-19
--  Version    : 1.0
--  Plateforme : VHDL-2008, synthétisable (Libero SoC)
--  Licence    : CC BY-NC 4.0
--  Interface  : s_* / m_* : coefficients DCT, de la DCT vers la quantification ;
--               la vanne se ferme à la fin de chaque rangée et se rouvre quand
--               le code de la rangée suivante est prêt ;
--               v_* : mots VLC acceptés par l'assemblage (observés seulement) ;
--               code, code_ok : code de la rangée en cours, pour la
--               quantification et l'en-tête de slice
--  Paramètres : G_COLS × G_ROWS macroblocs (22 × 18, ou 45 × 36 en 720 × 576),
--               G_T budget en bits par image, G_GOP longueur du GOP
--  Principe   : avant la rangée s (j = s·G_COLS, N = G_COLS·G_ROWS) :
--                 d = d0 + B − ⌊T·j / N⌋, B bits des rangées déjà produites
--                 code = 1 si d ≤ 0, sinon ⌊(31·d + T) / 2T⌋ borné à 1..31
--               bits d'une slice : 38 + Σ (2 + bits VLC du macrobloc), arrondi
--               à l'octet ; fin d'image : B += 136 (+ 240 en tête de GOP),
--               d0 ← max(0, d0 + B − T) ; d0 initial = ⌊20·T / 31⌋.
--               ⌊T·j / N⌋ = ⌊T·s / G_ROWS⌋ tenu en cumul (quotient, reste) ;
--               division par 2T en 5 pas (quotient ≤ 31).
--  Historique : 1.0  2026-10-19  création
--==============================================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity rate_ctrl is
    generic (
        G_COLS : natural := 22;
        G_ROWS : natural := 18;
        G_T    : natural := 350196;
        G_GOP  : natural := 12
    );
    port (
        clk     : in  std_logic;
        rst     : in  std_logic;
        -- coefficients DCT → quantification
        s_valid : in  std_logic;
        s_ready : out std_logic;
        s_data  : in  signed(15 downto 0);
        m_valid : out std_logic;
        m_ready : in  std_logic;
        m_data  : out signed(15 downto 0);
        -- mots VLC acceptés par l'assemblage du flux élémentaire
        v_valid : in  std_logic;
        v_ready : in  std_logic;
        v_lg    : in  unsigned(5 downto 0);
        v_fin   : in  std_logic;
        -- code de la rangée
        code    : out unsigned(4 downto 0);
        code_ok : out std_logic
    );
end entity rate_ctrl;

architecture rtl of rate_ctrl is
    constant W      : natural := 40;                     -- largeur des cumuls (bits)
    constant COEFS  : natural := G_COLS * 384;           -- coefficients par rangée
    constant SB0    : natural := 38 + 2 * G_COLS;        -- en-tête de slice + adresses et types
    constant T_Q    : natural := G_T / G_ROWS;
    constant T_R    : natural := G_T mod G_ROWS;
    constant DEN    : signed(W - 1 downto 0) := to_signed(2 * G_T, W);
    constant D0_INI : natural := (20 * (G_T / 31)) + (20 * (G_T mod 31)) / 31;   -- ⌊20·T / 31⌋ sans débordement

    type etat_t is (CALCUL, DIVISION, PRET);
    signal etat    : etat_t := CALCUL;
    signal ouvert  : std_logic := '0';
    signal n_coef  : natural range 0 to COEFS - 1 := 0;

    -- côté VLC : position et bits
    signal col     : natural range 0 to G_COLS - 1 := 0;
    signal rang    : natural range 0 to G_ROWS - 1 := 0;
    signal sb      : unsigned(W - 1 downto 0) := to_unsigned(SB0, W);    -- bits de la slice en cours
    signal b_img   : signed(W - 1 downto 0) := (others => '0');          -- B
    signal d0      : signed(W - 1 downto 0) := to_signed(D0_INI, W);
    signal cib_q   : signed(W - 1 downto 0) := (others => '0');          -- ⌊T·s / G_ROWS⌋
    signal cib_r   : natural range 0 to G_ROWS - 1 := 0;
    signal n_gop   : natural range 0 to G_GOP - 1 := 0;

    -- division
    signal num     : signed(W - 1 downto 0) := (others => '0');
    signal k       : natural range 0 to 4 := 4;
    signal quot    : unsigned(4 downto 0) := (others => '0');
    signal code_r  : unsigned(4 downto 0) := to_unsigned(1, 5);
begin
    -- vanne : un coefficient passe tel quel quand le code de sa rangée est prêt
    m_valid <= s_valid and ouvert;
    s_ready <= m_ready and ouvert;
    m_data  <= s_data;
    code    <= code_r;
    code_ok <= '1' when etat = PRET else '0';

    process (clk)
        variable sa   : unsigned(W - 1 downto 0);
        variable b    : signed(W - 1 downto 0);
        variable dn   : signed(W - 1 downto 0);
        variable d    : signed(W - 1 downto 0);
        variable n31  : signed(W + 4 downto 0);
        variable essai : signed(W - 1 downto 0);
    begin
        if rising_edge(clk) then
            if rst = '1' then
                etat <= CALCUL; ouvert <= '0'; n_coef <= 0;
                col <= 0; rang <= 0; sb <= to_unsigned(SB0, W);
                b_img <= (others => '0'); d0 <= to_signed(D0_INI, W);
                cib_q <= (others => '0'); cib_r <= 0; n_gop <= 0;
                code_r <= to_unsigned(1, 5);
            else
                -- vanne : fermeture après le dernier coefficient de la rangée
                if s_valid = '1' and m_ready = '1' and ouvert = '1' then
                    if n_coef = COEFS - 1 then
                        n_coef <= 0;
                        ouvert <= '0';
                    else
                        n_coef <= n_coef + 1;
                    end if;
                end if;

                -- comptage des bits produits
                if v_valid = '1' and v_ready = '1' then
                    if v_fin = '1' and col = G_COLS - 1 then
                        -- fin de rangée : slice arrondie à l'octet, ajoutée à B
                        sa := sb + v_lg + 7;
                        sa(2 downto 0) := "000";
                        b  := b_img + signed(sa);
                        sb <= to_unsigned(SB0, W);
                        col <= 0;
                        if rang = G_ROWS - 1 then
                            -- fin d'image : en-têtes d'image (et de séquence, GOP)
                            b := b + 136;
                            if n_gop = 0 then b := b + 240; end if;
                            dn := d0 + b - G_T;
                            if dn < 0 then d0 <= (others => '0'); else d0 <= dn; end if;
                            b_img <= (others => '0');
                            rang  <= 0;
                            cib_q <= (others => '0'); cib_r <= 0;
                            n_gop <= 0 when n_gop = G_GOP - 1 else n_gop + 1;
                        else
                            b_img <= b;
                            rang  <= rang + 1;
                            if cib_r + T_R >= G_ROWS then
                                cib_r <= cib_r + T_R - G_ROWS;
                                cib_q <= cib_q + T_Q + 1;
                            else
                                cib_r <= cib_r + T_R;
                                cib_q <= cib_q + T_Q;
                            end if;
                        end if;
                        etat <= CALCUL;                 -- code de la rangée suivante
                    else
                        sb <= sb + v_lg;
                        if v_fin = '1' then col <= col + 1; end if;
                    end if;
                end if;

                case etat is
                    when CALCUL =>
                        -- d = d0 + B − ⌊T·s / G_ROWS⌋ (registres déjà à jour)
                        if not (v_valid = '1' and v_ready = '1' and v_fin = '1' and col = G_COLS - 1) then
                            d := d0 + b_img - cib_q;
                            if d <= 0 then
                                code_r <= to_unsigned(1, 5);
                                etat   <= PRET;
                                ouvert <= '1';
                            else
                                n31 := shift_left(resize(d, W + 5), 5) - resize(d, W + 5) + G_T;     -- 31·d + T
                                if n31 >= shift_left(resize(DEN, W + 5), 5) then                     -- quotient ≥ 32
                                    code_r <= to_unsigned(31, 5);
                                    etat   <= PRET;
                                    ouvert <= '1';
                                else
                                    num  <= resize(n31, W);
                                    k    <= 4;
                                    quot <= (others => '0');
                                    etat <= DIVISION;
                                end if;
                            end if;
                        end if;
                    when DIVISION =>
                        essai := num - shift_left(DEN, k);
                        if essai >= 0 then
                            num <= essai;
                            quot(k) <= '1';
                        end if;
                        if k = 0 then
                            if essai >= 0 then
                                code_r <= quot or "00001";
                            elsif quot = 0 then
                                code_r <= to_unsigned(1, 5);
                            else
                                code_r <= quot;
                            end if;
                            etat   <= PRET;
                            ouvert <= '1';
                        else
                            k <= k - 1;
                        end if;
                    when PRET =>
                        null;
                end case;
            end if;
        end if;
    end process;
end architecture rtl;
