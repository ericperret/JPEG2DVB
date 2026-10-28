/*
================================================================================
  Nom        : refs.js
  Projet     : JPEG2DVB, portage FPGA (émetteur DVB-S 23 cm)
  Objet      : extrait les fichiers de référence des bancs de test VHDL à partir
               des sorties de JPEG2DVB 2.x, et génère le paquetage des
               coefficients SRRC
  Auteur     : Eric PERRET
  Date       : 2026-10-19
  Version    : 1.1
  Plateforme : Node.js (aucune dépendance)
  Licence    : CC BY-NC 4.0
  Usage      : node refs.js DOSSIER_JPEG2DVB
               DOSSIER_JPEG2DVB contient, pour un même traitement (FEC 1/2,
               α = 0,35, 8 échantillons par symbole, coefficients 16 bits) :
               video.ts (étape 08), randomized.ts (09), encoded.rs (10),
               interleaved.bin (11), convolutional.bin (12), qpsk_iq_s8.bin (13),
               dvbs_iq_s16_*.cs16 et dvbs_iq_s16_*.json (14)
  Historique : 1.0  2026-10-19  création
               1.1  2026-10-19  dossier fpga_test/ ; paquetage écrit dans vhdl/jpeg2dvb_fpga.vhd
================================================================================
*/
'use strict';
const fs = require('fs'), path = require('path');
const SRC = process.argv[2];
if (!SRC) { console.error('usage : node refs.js DOSSIER_JPEG2DVB'); process.exit(1); }
const ICI = __dirname, REF = ICI;
const { section } = require('./fusion');      // paquetage réécrit dans vhdl/jpeg2dvb_fpga.vhd


// Toutes les fonctions de la chaîne arrière sont causales : un préfixe de
// l'entrée donne un préfixe de la sortie (à la marge du filtre SRRC près).
const NP = 64;                        // paquets TS de référence
const NS_SRRC = 20000;                // symboles comparés en sortie du SRRC (8 échantillons chacun)

function lire(nom) { return fs.readFileSync(path.join(SRC, nom)); }
function ecrire(nom, buf) { fs.writeFileSync(path.join(REF, nom), buf); console.log(nom.padEnd(12), buf.length, 'octets'); }
function trouver(re) { const f = fs.readdirSync(SRC).find(n => re.test(n)); if (!f) { throw new Error('fichier absent : ' + re); } return f; }

fs.mkdirSync(REF, { recursive: true });
ecrire('ts.bin', lire('video.ts').subarray(0, NP * 188));
ecrire('rand.bin', lire('randomized.ts').subarray(0, NP * 188));
ecrire('rs.bin', lire('encoded.rs').subarray(0, NP * 204));
ecrire('inter.bin', lire('interleaved.bin').subarray(0, NP * 204));
ecrire('conv.bin', lire('convolutional.bin').subarray(0, NP * 204 * 2));          // taux 1/2 : 16 bits par octet
ecrire('qpsk.bin', lire('qpsk_iq_s8.bin').subarray(0, NP * 204 * 8 * 2));         // un symbole par bit d'entrée, I et Q signés 8 bits
const cs16 = trouver(/^dvbs_iq_s16_.*\.cs16$/);
ecrire('iq.cs16', lire(cs16).subarray(0, NS_SRRC * 8 * 4));

// Paquetage des coefficients polyphase (8 phases × 13 coefficients entiers)
const desc = JSON.parse(lire(trouver(/^dvbs_iq_s16_.*\.json$/)).toString());
const P = desc.srrc.polyphase;
if (P.length !== 8 || P[0].length !== 13) { throw new Error('polyphase attendue : 8 × 13'); }
const lignes = P.map((v, r) => '        ' + r + ' => (' + v.map(c => String(c).padStart(6)).join(', ') + ')').join(',\n');
const pkg = `--==============================================================================
--  Nom        : srrc_coef_pkg.vhd
--  Projet     : JPEG2DVB, portage FPGA (émetteur DVB-S 23 cm)
--  Objet      : coefficients du filtre SRRC en forme polyphase, entiers 16 bits
--               (fichier généré par fpga_test/refs.js depuis l'étape 14 de JPEG2DVB)
--  Auteur     : Eric PERRET
--  Date       : 2026-10-19
--  Version    : 1.1
--  Paramètres : α = ${desc.srrc.rolloff}, ${desc.srrc.span} symboles, ${desc.srrc.samplesPerSymbol} échantillons par symbole,
--               fenêtre ${desc.srrc.window}, ${desc.srrc.taps} coefficients, échelle E = ${desc.srrc.echelle.toFixed(4)}
--  Principe   : échantillon n·8 + r = somme sur d de C(r)(d) · s(n − 6 + d),
--               symboles s = ±1 ; la somme des |C(r)(d)| ne dépasse pas 0,95 × 32 767
--  Licence    : CC BY-NC 4.0
--  Historique : 1.0  2026-10-19  création
               1.1  2026-10-19  dossier fpga_test/ ; paquetage écrit dans vhdl/jpeg2dvb_fpga.vhd
--==============================================================================
library ieee;
use ieee.std_logic_1164.all;

package srrc_coef_pkg is
    constant SRRC_SPS  : natural := 8;
    constant SRRC_TAPS : natural := 13;
    type srrc_phase_t is array (0 to SRRC_TAPS - 1) of integer range -32768 to 32767;
    type srrc_coef_t  is array (0 to SRRC_SPS - 1) of srrc_phase_t;
    constant SRRC_C : srrc_coef_t := (
${lignes}
    );
end package srrc_coef_pkg;
`;
section('srrc_coef_pkg.vhd', pkg);
console.log('srrc_coef_pkg.vhd généré');
