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
    -- répertoire des références (relatif au dossier de lancement)
    constant REF : string := "ref/";
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
