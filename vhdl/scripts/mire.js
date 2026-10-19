/*
================================================================================
  Nom        : mire.js
  Projet     : JPEG2DVB, portage FPGA (émetteur DVB-S 23 cm)
  Objet      : dessine la mire 16 couleurs du FPGA (352 × 288, frontières de
               couleur sur coordonnées paires), l'écrit en PNG pour la page 01
               de JPEG2DVB, et génère rtl/mire_pkg.vhd : image en indices
               4 bits et palette Y, Cb, Cr calculée avec les formules de la
               page 01 (BT.601, arrondi Math.round, chrominance en Float32)
  Auteur     : Eric PERRET
  Date       : 2026-10-19
  Version    : 1.0
  Plateforme : Node.js (zlib intégré, aucune dépendance)
  Licence    : CC BY-NC 4.0
  Usage      : node mire.js          → ref/mire.png et rtl/mire_pkg.vhd
  Historique : 1.0  2026-10-19  création
================================================================================
*/
'use strict';
const fs = require('fs'), path = require('path'), zlib = require('zlib');
const W = 352, H = 288;

// palette : 8 barres, 6 gris intermédiaires, ambre AZS, ardoise
const PAL = [
    [255, 255, 255], [255, 255, 0], [0, 255, 255], [0, 255, 0], [255, 0, 255], [255, 0, 0], [0, 0, 255], [0, 0, 0],
    [36, 36, 36], [73, 73, 73], [109, 109, 109], [146, 146, 146], [182, 182, 182], [219, 219, 219],
    [240, 166, 58], [24, 34, 42]];
const BLANC = 0, NOIR = 7, AMBRE = 14, ARDOISE = 15;
const GRIS = [7, 8, 9, 10, 11, 12, 13, 0];

const img = new Uint8Array(W * H);
function rect(x0, y0, w, h, c) { for (let y = y0; y < y0 + h; y++) { for (let x = x0; x < x0 + w; x++) { img[y * W + x] = c; } } }
for (let b = 0; b < 8; b++) { rect(b * 44, 0, 44, 168, b); }                 // barres de couleur
for (let g = 0; g < 8; g++) { rect(g * 44, 168, 44, 56, GRIS[g]); }          // gamme de gris
rect(0, 224, W, 64, ARDOISE);                                                // bandeau
// « AZS » en pavés de 4 × 4 pixels (frontières paires)
const LETTRES = {
    A: ['01110', '10001', '10001', '11111', '10001', '10001', '10001'],
    Z: ['11111', '00001', '00010', '00100', '01000', '10000', '11111'],
    S: ['01111', '10000', '10000', '01110', '00001', '00001', '11110']
};
let xl = 120;
for (const l of 'AZS') {
    LETTRES[l].forEach((ligne, j) => { for (let i = 0; i < 5; i++) { if (ligne[i] === '1') { rect(xl + 4 * i, 236 + 4 * j, 4, 4, AMBRE); } } });
    xl += 28;
}
rect(0, 276, W, 12, NOIR);                                                   // fond du compteur d'images

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
fs.writeFileSync(path.join(__dirname, '..', 'ref', 'mire.png'), png);

// palette Y, Cb, Cr : formules de la page 01 (plansDepuisRGBA)
const clamp = v => Math.max(0, Math.min(255, Math.round(v)));
const pal = PAL.map(([R, G, B]) => {
    const Y = clamp(0.299 * R + 0.587 * G + 0.114 * B);
    const cb = Math.fround(-0.168736 * R - 0.331264 * G + 0.5 * B + 128), cr = Math.fround(0.5 * R - 0.418688 * G - 0.081312 * B + 128);
    return [Y, clamp((cb + cb + cb + cb) / 4), clamp((cr + cr + cr + cr) / 4)];
});
const lignes = [];
for (let y = 0; y < H; y++) { let s = ''; for (let x = 0; x < W; x++) { s += img[y * W + x].toString(16).toUpperCase(); } lignes.push('        "' + s + '"'); }
const vhd = `--==============================================================================
--  Nom        : mire_pkg.vhd
--  Projet     : JPEG2DVB, portage FPGA (émetteur DVB-S 23 cm)
--  Objet      : mire 16 couleurs 352 × 288 (indices 4 bits, un caractère
--               hexadécimal par pixel) et palette Y, Cb, Cr ; frontières de
--               couleur sur coordonnées paires, la chrominance 4:2:0 d'un bloc
--               2 × 2 est donc celle de la palette
--               (fichier généré par scripts/mire.js ; même image : ref/mire.png)
--  Auteur     : Eric PERRET
--  Date       : 2026-10-19
--  Version    : 1.0
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
    constant IDX_BLANC : natural := ${BLANC};
    constant IDX_NOIR  : natural := ${NOIR};
    type mire_t is array (0 to MIRE_H - 1) of string(1 to MIRE_L);
    constant MIRE : mire_t := (
${lignes.join(',\n')});
    -- même image en mémoire morte de 101 376 mots de 4 bits (adresse = 352·y + x)
    type rom_t is array (0 to MIRE_L * MIRE_H - 1) of unsigned(3 downto 0);
    function vers_rom return rom_t;
    constant MIRE_ROM : rom_t;
end package mire_pkg;

package body mire_pkg is
    function vers_rom return rom_t is
        variable r : rom_t;
        variable c : character;
        variable v : natural;
    begin
        for y in 0 to MIRE_H - 1 loop
            for x in 0 to MIRE_L - 1 loop
                c := MIRE(y)(x + 1);
                if c >= 'A' then v := character'pos(c) - character'pos('A') + 10; else v := character'pos(c) - character'pos('0'); end if;
                r(y * MIRE_L + x) := to_unsigned(v, 4);
            end loop;
        end loop;
        return r;
    end function;
    constant MIRE_ROM : rom_t := vers_rom;
end package body mire_pkg;
`;
fs.writeFileSync(path.join(__dirname, '..', 'rtl', 'mire_pkg.vhd'), vhd);
console.log('mire.png', png.length, 'octets ; palette', JSON.stringify(pal));
