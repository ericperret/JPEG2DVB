/*
================================================================================
  Nom        : gen_pkgg.js
  Projet     : JPEG2DVB, mode GMSK
  Objet      : génère le paquetage VHDL gmsk_pkg (table q de l'impulsion de fréquence
               gaussienne) depuis gmsk_ref.js ; écrit dvbg_pkg.txt
  Auteur     : Eric PERRET
  Date       : 2026-11-24
  Version    : 1.0
  Plateforme : Node.js, modules intégrés seulement
  Usage      : node gen_pkgg.js
  Licence    : CC BY-NC 4.0
  Historique : 1.0  2026-11-24  création
================================================================================
*/
'use strict';
const fs = require('fs');
const G = require('./gmsk_ref.js');
let o = 'package gmsk_pkg is\n';
o += '    constant MULT : natural := ' + G.MULT + ';     -- ⌊phase de symbole · 149 / 1 024⌋ ≈ 64 · phase / 440\n';
o += '    type t_q_t is array (0 to ' + (G.NJ * G.NP - 1) + ') of natural range 0 to ' + G.QMAX + ';\n';
o += '    -- T_Q(j · 64 + i) = 512 · Q(j + (i + 1/2) / 64), Q : intégrale de l\'impulsion de fréquence (BT 0,5, 4 symboles)\n';
o += '    constant T_Q : t_q_t := (\n';
for (let r = 0; r < G.NJ * G.NP; r += 16) {
    const l = []; for (let i = r; i < r + 16; i++) { l.push(G.TQ.t[i]); }
    o += '        ' + l.join(', ') + (r + 16 < G.NJ * G.NP ? ',' : '') + '\n';
}
o += '    );\nend package gmsk_pkg;\n';
fs.writeFileSync(__dirname + '/dvbg_pkg.txt', o);
console.log('dvbg_pkg.txt écrit');
