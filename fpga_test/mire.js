/*
================================================================================
  Nom        : mire.js
  Projet     : JPEG2DVB, portage FPGA (émetteur DVB-S 23 cm)
  Objet      : dessine la mire 16 couleurs du FPGA (352 × 288, frontières de
               couleur sur coordonnées paires), l'écrit en PNG pour la page 01
               de JPEG2DVB, et génère le paquetage mire_pkg de
               vhdl/jpeg2dvb_fpga.vhd : géométrie de la mire (barres, gris,
               bandeau, lettres), fonction mire_idx qui donne la couleur d'un
               pixel sans mémoire d'image, et palette Y, Cb, Cr calculée avec
               les formules de la page 01 (BT.601, arrondi Math.round,
               chrominance en Float32) ; contrôle que mire_idx redonne l'image
  Auteur     : Eric PERRET
  Date       : 2026-11-11
  Version    : 1.2
  Plateforme : Node.js (zlib intégré, aucune dépendance)
  Licence    : CC BY-NC 4.0
  Usage      : node mire.js          → mire.png et paquetage mire_pkg de vhdl/jpeg2dvb_fpga.vhd
  Historique : 1.0  2026-10-19  création
               1.1  2026-10-19  dossier fpga_test/ ; paquetage écrit dans vhdl/jpeg2dvb_fpga.vhd
               1.2  2026-11-11  paquetage sans image (101 376 mots retirés) : la mire
                     est décrite par sa géométrie et la fonction mire_idx
================================================================================
*/
'use strict';
const fs = require('fs'), path = require('path'), zlib = require('zlib');
const W = 352, H = 288;
const { section } = require('./fusion');      // paquetage réécrit dans vhdl/jpeg2dvb_fpga.vhd


// palette : 8 barres, 6 gris intermédiaires, ambre AZS, ardoise
const PAL = [
    [255, 255, 255], [255, 255, 0], [0, 255, 255], [0, 255, 0], [255, 0, 255], [255, 0, 0], [0, 0, 255], [0, 0, 0],
    [36, 36, 36], [73, 73, 73], [109, 109, 109], [146, 146, 146], [182, 182, 182], [219, 219, 219],
    [240, 166, 58], [24, 34, 42]];
const BLANC = 0, NOIR = 7, AMBRE = 14, ARDOISE = 15;
const GRIS = [7, 8, 9, 10, 11, 12, 13, 0];

// géométrie (reprise dans mire_pkg)
const BARRE = 44, Y_GRIS = 168, Y_BANDEAU = 224, Y_CPT = 276, X_TXT = 120, Y_TXT = 236, PAVE = 4, PAS = 28, TEXTE = 'AZS';

const img = new Uint8Array(W * H);
function rect(x0, y0, w, h, c) { for (let y = y0; y < y0 + h; y++) { for (let x = x0; x < x0 + w; x++) { img[y * W + x] = c; } } }
for (let b = 0; b < 8; b++) { rect(b * BARRE, 0, BARRE, Y_GRIS, b); }                        // barres de couleur
for (let g = 0; g < 8; g++) { rect(g * BARRE, Y_GRIS, BARRE, Y_BANDEAU - Y_GRIS, GRIS[g]); }   // gamme de gris
rect(0, Y_BANDEAU, W, H - Y_BANDEAU, ARDOISE);                                               // bandeau
// « AZS » en pavés de 4 × 4 pixels (frontières paires)
const LETTRES = {
    A: ['01110', '10001', '10001', '11111', '10001', '10001', '10001'],
    Z: ['11111', '00001', '00010', '00100', '01000', '10000', '11111'],
    S: ['01111', '10000', '10000', '01110', '00001', '00001', '11110']
};
let xl = X_TXT;
for (const l of TEXTE) {
    LETTRES[l].forEach((ligne, j) => { for (let i = 0; i < 5; i++) { if (ligne[i] === '1') { rect(xl + PAVE * i, Y_TXT + PAVE * j, PAVE, PAVE, AMBRE); } } });
    xl += PAS;
}
rect(0, Y_CPT, W, H - Y_CPT, NOIR);                                          // fond du compteur d'images

/* mireIdx — E : x, y → T : mêmes règles que la fonction mire_idx du paquetage
   → S : indice de couleur du pixel */
function mireIdx(x, y) {
    const b = Math.floor(x / BARRE);
    if (y < Y_GRIS) { return b; }
    if (y < Y_BANDEAU) { return GRIS[b]; }
    if (y >= Y_CPT) { return NOIR; }
    if (y >= Y_TXT && y < Y_TXT + 7 * PAVE && x >= X_TXT && x < X_TXT + TEXTE.length * PAS) {
        const l = Math.floor((x - X_TXT) / PAS), i = Math.floor((x - X_TXT - l * PAS) / PAVE), j = Math.floor((y - Y_TXT) / PAVE);
        if (i < 5 && LETTRES[TEXTE[l]][j][i] === '1') { return AMBRE; }
    }
    return ARDOISE;
}
// contrôle : les règles redonnent l'image dessinée
for (let y = 0; y < H; y++) { for (let x = 0; x < W; x++) { if (mireIdx(x, y) !== img[y * W + x]) { throw new Error('mire_idx différent de l\'image en ' + x + ',' + y); } } }

// contrôle : chaque bloc 2 × 2 est uniforme
for (let y = 0; y < H; y += 2) { for (let x = 0; x < W; x += 2) {
    const c = img[y * W + x];
    if (img[y * W + x + 1] !== c || img[(y + 1) * W + x] !== c || img[(y + 1) * W + x + 1] !== c) { throw new Error('bloc 2 × 2 non uniforme en ' + x + ',' + y); }
} }

// PNG RGB 8 bits
function crc32(b) { let c, t = []; for (let n = 0; n < 256; n++) { c = n; for (let k = 0; k < 8; k++) { c = c & 1 ? 0xEDB88320 ^ (c >>> 1) : c >>> 1; } t[n] = c >>> 0; }
    let r = 0xFFFFFFFF; for (const x of b) { r = t[(r ^ x) & 0xFF] ^ (r >>> 8); } return (r ^ 0xFFFFFFFF) >>> 0; }
function bloc(type, data) { const l = Buffer.alloc(4); l.writeUInt32BE(data.length); const td = Buffer.concat([Buffer.from(type), data]); const c = Buffer.alloc(4); c.writeUInt32BE(crc32(td)); return Buffer.concat([l, td, c]); }
const brut = Buffer.alloc(H * (1 + W * 3));
for (let y = 0; y < H; y++) { brut[y * (1 + W * 3)] = 0; for (let x = 0; x < W; x++) { const p = PAL[img[y * W + x]]; brut.set(p, y * (1 + W * 3) + 1 + x * 3); } }
const ihdr = Buffer.alloc(13); ihdr.writeUInt32BE(W, 0); ihdr.writeUInt32BE(H, 4); ihdr[8] = 8; ihdr[9] = 2;
const png = Buffer.concat([Buffer.from([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]), bloc('IHDR', ihdr), bloc('IDAT', zlib.deflateSync(brut)), bloc('IEND', Buffer.alloc(0))]);
fs.writeFileSync(path.join(__dirname, 'mire.png'), png);

// palette Y, Cb, Cr : formules de la page 01 (plansDepuisRGBA)
const clamp = v => Math.max(0, Math.min(255, Math.round(v)));
const pal = PAL.map(([R, G, B]) => {
    const Y = clamp(0.299 * R + 0.587 * G + 0.114 * B);
    const cb = Math.fround(-0.168736 * R - 0.331264 * G + 0.5 * B + 128), cr = Math.fround(0.5 * R - 0.418688 * G - 0.081312 * B + 128);
    return [Y, clamp((cb + cb + cb + cb) / 4), clamp((cr + cr + cr + cr) / 4)];
});
const txt = [...TEXTE].map((l, k) => '        "' + LETTRES[l].join('') + '"' + (k < TEXTE.length - 1 ? ' &' : ';') + '    -- ' + l).join('\n');
const vhd = `--==============================================================================
--  Nom        : mire_pkg.vhd
--  Projet     : JPEG2DVB, portage FPGA (émetteur DVB-S 23 cm)
--  Objet      : mire 16 couleurs ${W} × ${H} décrite par sa géométrie (barres,
--               gamme de gris, bandeau, lettres, fond du compteur) : mire_idx
--               donne l'indice de couleur d'un pixel par comparaisons, sans
--               mémoire d'image ; palette Y, Cb, Cr ; frontières de couleur
--               sur coordonnées paires, la chrominance 4:2:0 d'un bloc 2 × 2
--               est donc celle de la palette
--               (fichier généré par fpga_test/mire.js ; même image : fpga_test/mire.png)
--  Auteur     : Eric PERRET
--  Date       : 2026-11-11
--  Version    : 1.2
--  Plateforme : VHDL-2008, synthétisable (Libero SoC)
--  Licence    : CC BY-NC 4.0
--  Historique : 1.0  2026-10-19  création
--==============================================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package mire_pkg is
    constant MIRE_L : natural := ${W};
    constant MIRE_H : natural := ${H};
    type ycc_t is array (0 to 2) of natural range 0 to 255;
    type palette_t is array (0 to 15) of ycc_t;
    constant PALETTE : palette_t := (
${pal.map((p, i) => '        ' + String(i).padStart(2) + ' => (' + p.join(', ') + ')').join(',\n')});
    constant IDX_BLANC   : natural := ${BLANC};
    constant IDX_NOIR    : natural := ${NOIR};
    constant IDX_AMBRE   : natural := ${AMBRE};
    constant IDX_ARDOISE : natural := ${ARDOISE};
    -- géométrie : 8 barres de couleur, 8 gris, bandeau, fond du compteur
    constant MIRE_BARRE     : natural := ${BARRE};      -- largeur d'une barre
    constant MIRE_Y_GRIS    : natural := ${Y_GRIS};     -- première ligne de la gamme de gris
    constant MIRE_Y_BANDEAU : natural := ${Y_BANDEAU};     -- première ligne du bandeau
    constant MIRE_Y_CPT     : natural := ${Y_CPT};     -- première ligne du fond du compteur
    type gris_t is array (0 to 7) of natural range 0 to 15;
    constant MIRE_GRIS : gris_t := (${GRIS.join(', ')});
    -- lettres « ${TEXTE} » : 7 lignes de 5 pavés par lettre, ligne du haut et pavé de
    --   gauche en premier ; pavé (lettre l, ligne j, colonne i) : bit 35·l + 5·j + i
    constant MIRE_X_TXT : natural := ${X_TXT};
    constant MIRE_Y_TXT : natural := ${Y_TXT};
    constant MIRE_PAVE  : natural := ${PAVE};            -- côté d'un pavé
    constant MIRE_PAS   : natural := ${PAS};           -- pas des lettres
    constant MIRE_NL    : natural := ${TEXTE.length};            -- nombre de lettres
    constant MIRE_TXT : std_logic_vector(0 to 35 * MIRE_NL - 1) :=
${txt}
    function mire_idx(x, y : natural) return natural;
end package mire_pkg;

package body mire_pkg is
    -- mire_idx : E : x (0 à MIRE_L − 1), y (0 à MIRE_H − 1) → T : barre x / 44
    --   par comparaisons ; zone selon y ; pavé de lettre dans le bandeau → S :
    --   indice de couleur du pixel
    function mire_idx(x, y : natural) return natural is
        variable b : natural range 0 to 7 := 0;
        variable l : natural range 0 to MIRE_NL - 1 := 0;
        variable i : natural range 0 to 7;
        variable j : natural range 0 to 6;
    begin
        for k in 1 to 7 loop
            if x >= MIRE_BARRE * k then b := k; end if;
        end loop;
        if y < MIRE_Y_GRIS then
            return b;
        elsif y < MIRE_Y_BANDEAU then
            return MIRE_GRIS(b);
        elsif y >= MIRE_Y_CPT then
            return IDX_NOIR;
        elsif y >= MIRE_Y_TXT and y < MIRE_Y_TXT + 7 * MIRE_PAVE and x >= MIRE_X_TXT and x < MIRE_X_TXT + MIRE_NL * MIRE_PAS then
            for k in 1 to MIRE_NL - 1 loop
                if x >= MIRE_X_TXT + MIRE_PAS * k then l := k; end if;
            end loop;
            i := (x - MIRE_X_TXT - MIRE_PAS * l) / MIRE_PAVE;
            j := (y - MIRE_Y_TXT) / MIRE_PAVE;
            if i < 5 and MIRE_TXT(35 * l + 5 * j + i) = '1' then
                return IDX_AMBRE;
            end if;
        end if;
        return IDX_ARDOISE;
    end function;
end package body mire_pkg;
`;
section('mire_pkg.vhd', vhd);
console.log('mire.png', png.length, 'octets ; palette', JSON.stringify(pal));
