--==============================================================================
--  Nom        : dvbs_pkg.vhd
--  Projet     : JPEG2DVB, portage FPGA (émetteur DVB-S 23 cm)
--  Objet      : types et fonctions communs de la chaîne DVB-S (EN 300 421) :
--               dispersion d'énergie, corps de Galois GF(2⁸), Reed-Solomon,
--               codeur convolutif
--  Auteur     : Eric PERRET
--  Date       : 2026-10-19
--  Version    : 1.0
--  Plateforme : VHDL-2008, synthétisable (Libero SoC), bibliothèque ieee seule
--  Licence    : CC BY-NC 4.0
--  Historique : 1.0  2026-10-19  création
--==============================================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package dvbs_pkg is

    subtype octet_t is std_logic_vector(7 downto 0);
    type octet_tab_t is array (natural range <>) of octet_t;

    ----------------------------------------------------------------------------
    -- Dispersion d'énergie (§ 4.4.1) : générateur 1 + X¹⁴ + X¹⁵
    -- Registre : bit k-1 = étage k ; initialisation étages 1 à 15 = 100101010000000
    -- Sortie = étage 14 ⊕ étage 15, réinjectée dans l'étage 1
    ----------------------------------------------------------------------------
    subtype prbs_reg_t is std_logic_vector(14 downto 0);
    constant PRBS_INIT : prbs_reg_t := "000000010101001";      -- 0x00A9
    function prbs_pas(r : prbs_reg_t) return prbs_reg_t;        -- un pas
    function prbs_pas8(r : prbs_reg_t) return prbs_reg_t;       -- huit pas
    function prbs_octet(r : prbs_reg_t) return octet_t;         -- 8 bits de sortie, premier bit en poids fort

    ----------------------------------------------------------------------------
    -- GF(2⁸), polynôme primitif x⁸ + x⁴ + x³ + x² + 1 (0x11D)
    ----------------------------------------------------------------------------
    function gf_mul(a, b : octet_t) return octet_t;

    ----------------------------------------------------------------------------
    -- RS(204,188) : g(x) = (x + λ⁰)(x + λ¹)…(x + λ¹⁵), coefficients du plus haut
    -- degré au plus bas (RS_GEN(0) = 1)
    ----------------------------------------------------------------------------
    constant RS_GEN : octet_tab_t(0 to 16) := (
        x"01", x"3B", x"0D", x"68", x"BD", x"44", x"D1", x"1E", x"08",
        x"A3", x"41", x"29", x"E5", x"62", x"32", x"24", x"3B");

    ----------------------------------------------------------------------------
    -- Codeur convolutif K = 7 (§ 4.4.3) : masques sur (entrée & registre),
    -- registre de 6 bits, D0 (bit précédent) en poids fort
    ----------------------------------------------------------------------------
    constant CONV_G1 : std_logic_vector(6 downto 0) := "1111001";   -- 171 octal, sortie X
    constant CONV_G2 : std_logic_vector(6 downto 0) := "1011011";   -- 133 octal, sortie Y
    function parite(v : std_logic_vector) return std_logic;

end package dvbs_pkg;

package body dvbs_pkg is

    function prbs_pas(r : prbs_reg_t) return prbs_reg_t is
        variable f : std_logic;
    begin
        f := r(13) xor r(14);
        return r(13 downto 0) & f;
    end function;

    function prbs_pas8(r : prbs_reg_t) return prbs_reg_t is
        variable v : prbs_reg_t := r;
    begin
        for k in 0 to 7 loop
            v := prbs_pas(v);
        end loop;
        return v;
    end function;

    function prbs_octet(r : prbs_reg_t) return octet_t is
        variable v : prbs_reg_t := r;
        variable o : octet_t;
    begin
        for k in 7 downto 0 loop
            o(k) := v(13) xor v(14);
            v := prbs_pas(v);
        end loop;
        return o;
    end function;

    function gf_mul(a, b : octet_t) return octet_t is
        variable p  : octet_t := (others => '0');
        variable aa : octet_t := a;
    begin
        for k in 0 to 7 loop
            if b(k) = '1' then
                p := p xor aa;
            end if;
            if aa(7) = '1' then
                aa := (aa(6 downto 0) & '0') xor x"1D";
            else
                aa := aa(6 downto 0) & '0';
            end if;
        end loop;
        return p;
    end function;

    function parite(v : std_logic_vector) return std_logic is
        variable p : std_logic := '0';
    begin
        for k in v'range loop
            p := p xor v(k);
        end loop;
        return p;
    end function;

end package body dvbs_pkg;
