/*
================================================================================
  Nom        : gen_vlc.js
  Projet     : JPEG2DVB, portage FPGA (émetteur DVB-S 23 cm)
  Objet      : génère le paquetage vlc_tab_pkg de vhdl/jpeg2dvb_fpga.vhd (tables VLC MPEG-2 B.12, B.13, B.14)
               à partir de la page 05 de JPEG2DVB, pour que le VHDL et la
               référence partagent exactement les mêmes codes
  Auteur     : Eric PERRET
  Date       : 2026-10-19
  Version    : 1.1
  Plateforme : Node.js (aucune dépendance)
  Licence    : CC BY-NC 4.0
  Usage      : node gen_vlc.js [chemin de page05-rle-huffman.html]
  Historique : 1.0  2026-10-19  création
               1.1  2026-10-19  dossier fpga_test/ ; paquetage écrit dans vhdl/jpeg2dvb_fpga.vhd
================================================================================
*/
'use strict';
const fs = require('fs'), path = require('path');
const P05 = process.argv[2] || path.join(__dirname, '..', 'page05-rle-huffman.html');
function section(nom, texte) {                 // remplace un paquetage dans le fichier VHDL fusionné
    const f = path.join(__dirname, '..', 'vhdl', 'jpeg2dvb_fpga.vhd'), a = '-- >>> ' + nom + '\n', b = '-- <<< ' + nom;
    const s = fs.readFileSync(f, 'utf8'), i = s.indexOf(a), j = s.indexOf(b);
    if (i < 0 || j < i) { throw new Error('balises de ' + nom + ' absentes de ' + f); }
    fs.writeFileSync(f, s.slice(0, i + a.length) + texte.replace(/\s*$/, '\n') + s.slice(j));
}

const h = fs.readFileSync(P05, 'utf8');
function objet(nom) {
    const m = new RegExp('const ' + nom + ' = (\\{[\\s\\S]*?\\});').exec(h);
    if (!m) { throw new Error(nom + ' introuvable'); }
    return Function('return ' + m[1])();
}
const DCL = objet('DC_VLC_LUMA'), DCC = objet('DC_VLC_CHROMA'), AC = objet('AC_VLC');

// tables DC : code cadré à droite sur 10 bits + longueur
function dc(t) { return Object.keys(t).map(Number).sort((a, b) => a - b).map(s => '        ' + s + ' => ("' + t[s].padStart(10, '0') + '", ' + t[s].length + ')').join(',\n'); }
// table AC : un cas par paire (run, niveau)
const parRun = {};
for (const k of Object.keys(AC)) {
    if (k === 'EOB' || k === 'ESCAPE') { continue; }
    const [r, l] = k.split(',').map(Number);
    (parRun[r] = parRun[r] || []).push([l, AC[k]]);
}
let cas = '';
for (const r of Object.keys(parRun).map(Number).sort((a, b) => a - b)) {
    cas += '            when ' + r + ' =>\n                case niveau is\n';
    for (const [l, c] of parRun[r].sort((a, b) => a[0] - b[0])) {
        cas += '                    when ' + String(l).padStart(2) + ' => v := (true, "' + c.padStart(16, '0') + '", ' + c.length + ');\n';
    }
    cas += '                    when others => null;\n                end case;\n';
}
const n = Object.keys(AC).length - 2;
const pkg = `--==============================================================================
--  Nom        : vlc_tab_pkg.vhd
--  Projet     : JPEG2DVB, portage FPGA (émetteur DVB-S 23 cm)
--  Objet      : tables VLC MPEG-2 intra : B.12 (taille DC luminance), B.13
--               (taille DC chrominance), B.14 (coefficients AC, intra_vlc_format
--               = 0, ${n} paires run / niveau, sans le bit de signe)
--               (fichier généré par fpga_test/gen_vlc.js depuis la page 05)
--  Auteur     : Eric PERRET
--  Date       : 2026-10-19
--  Version    : 1.1
--  Plateforme : VHDL-2008, synthétisable (Libero SoC)
--  Licence    : CC BY-NC 4.0
--  Historique : 1.0  2026-10-19  création
               1.1  2026-10-19  dossier fpga_test/ ; paquetage écrit dans vhdl/jpeg2dvb_fpga.vhd
--==============================================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package vlc_tab_pkg is
    type dc_vlc_t is record
        code : std_logic_vector(9 downto 0);       -- cadré à droite
        lg   : natural range 0 to 10;
    end record;
    type dc_tab_t is array (0 to 11) of dc_vlc_t;
    constant DC_LUMA : dc_tab_t := (
${dc(DCL)});
    constant DC_CHROMA : dc_tab_t := (
${dc(DCC)});
    constant AC_EOB    : std_logic_vector(1 downto 0) := "${AC.EOB}";
    constant AC_ESCAPE : std_logic_vector(5 downto 0) := "${AC.ESCAPE}";

    type ac_vlc_t is record
        trouve : boolean;
        code   : std_logic_vector(15 downto 0);    -- cadré à droite, sans le signe
        lg     : natural range 0 to 16;
    end record;
    function ac_code(run : natural range 0 to 63; niveau : natural range 0 to 2047) return ac_vlc_t;
end package vlc_tab_pkg;

package body vlc_tab_pkg is
    function ac_code(run : natural range 0 to 63; niveau : natural range 0 to 2047) return ac_vlc_t is
        variable v : ac_vlc_t := (false, (others => '0'), 0);
    begin
        case run is
${cas}            when others => null;
        end case;
        return v;
    end function;
end package body vlc_tab_pkg;
`;
section('vlc_tab_pkg.vhd', pkg);
console.log('vlc_tab_pkg.vhd :', n, 'codes AC');
