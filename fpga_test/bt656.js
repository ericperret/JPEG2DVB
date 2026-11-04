/*
================================================================================
  Nom        : bt656.js
  Projet     : JPEG2DVB, portage FPGA (émetteur DVB-S 23 cm)
  Objet      : référence du récepteur bt656_rx : flux ITU-R BT.656 PAL
               (625 lignes, 1 728 octets par ligne, synchros intégrées) tel
               que le sort le décodeur TVP5150AM1, et couples de pixels
               attendus en sortie du récepteur ; image 720 × 576 : mire du
               FPGA (mire.png) doublée au centre, marquage de la ligne dans
               les 8 premiers pixels ; une image en couleur, une image en
               noir et blanc (Cb = Cr = 128)
  Auteur     : Eric PERRET
  Date       : 2026-11-04
  Version    : 1.0
  Plateforme : Node.js (zlib intégré, aucune dépendance)
  Licence    : CC BY-NC 4.0
  Usage      : node bt656.js         → bt656.bin (entrée) et bt656_ref.bin (sortie attendue)
  Flux       : fin de la trame 2 d'une image précédente, entrée au milieu
               d'une ligne (le récepteur doit attendre un début de trame),
               image 0 en couleur, image 1 en noir et blanc, lignes 1 et 2
               de l'image suivante
  Référence  : 4 trames de 288 lignes × 360 couples, octets Cb Y0 Cr Y1 dans
               l'ordre du flux
  Historique : 1.0  2026-11-04  création
================================================================================
*/
'use strict';
const fs = require('fs'), path = require('path'), zlib = require('zlib');

const L = 720, H = 576;                 // image PAL
const ML = 352, MH = 288;               // mire du FPGA
const OCT_LIGNE = 1728, OCT_ACTIF = 1440, OCT_SUPP = 280;

/* lirePNG — E : PNG RGB 8 bits, filtre 0 sur chaque ligne (écrit par mire.js)
   → T : blocs, décompression → S : {l, h, rgb} */
function lirePNG(f) {
    const b = fs.readFileSync(f);
    let p = 8, l = 0, h = 0;
    const idat = [];
    while (p < b.length) {
        const n = b.readUInt32BE(p), t = b.toString('latin1', p + 4, p + 8);
        if (t === 'IHDR') {
            l = b.readUInt32BE(p + 8); h = b.readUInt32BE(p + 12);
            if (b[p + 16] !== 8 || b[p + 17] !== 2) { throw new Error('PNG RGB 8 bits attendu'); }
        } else if (t === 'IDAT') { idat.push(b.subarray(p + 8, p + 8 + n)); }
        p += 12 + n;
    }
    const brut = zlib.inflateSync(Buffer.concat(idat));
    const rgb = Buffer.alloc(l * h * 3);
    for (let y = 0; y < h; y++) {
        if (brut[y * (1 + l * 3)] !== 0) { throw new Error('filtre PNG non nul ligne ' + y); }
        brut.copy(rgb, y * l * 3, y * (1 + l * 3) + 1, (y + 1) * (1 + l * 3));
    }
    return { l, h, rgb };
}

/* ycc — E : R, G, B → T : formules de la page 01 (BT.601, Math.round,
   chrominance en Float32), bornes 1…254 (0 et 255 réservés aux codes
   de synchronisation BT.656) → S : [Y, Cb, Cr] */
const borne = v => Math.max(1, Math.min(254, Math.round(v)));
function ycc(R, G, B) {
    const cb = Math.fround(-0.168736 * R - 0.331264 * G + 0.5 * B + 128);
    const cr = Math.fround(0.5 * R - 0.418688 * G - 0.081312 * B + 128);
    return [borne(0.299 * R + 0.587 * G + 0.114 * B), borne(cb), borne(cr)];
}

const mire = lirePNG(path.join(__dirname, 'mire.png'));
if (mire.l !== ML || mire.h !== MH) { throw new Error('mire.png : 352 × 288 attendu'); }

/* pixel — E : image k, rangée r (0 à 575), colonne x (0 à 719), couleur
   → T : marquage (x < 8), bordure droite (x ≥ 712), mire doublée sinon
   → S : [Y, Cb, Cr] ; la chrominance d'un couple (x pair, x + 1) est celle
   du pixel pair */
function pixel(k, r, x, couleur) {
    if (x < 8) { return [1 + ((k * H + r) * 8 + x) % 254, 128, 128]; }
    if (x >= 712) { return [16, 128, 128]; }
    const mx = (x - 8) >> 1, my = r >> 1, o = (my * ML + mx) * 3;
    const c = ycc(mire.rgb[o], mire.rgb[o + 1], mire.rgb[o + 2]);
    return couleur ? c : [c[0], 128, 128];
}

/* xy — E : F, V, H → T : bits de protection P3 = V⊕H, P2 = F⊕H, P1 = F⊕V,
   P0 = F⊕V⊕H → S : 4e octet du code de synchronisation */
function xy(f, v, h) {
    return 0x80 | f << 6 | v << 5 | h << 4 | (v ^ h) << 3 | (f ^ h) << 2 | (f ^ v) << 1 | (f ^ v ^ h);
}

/* ligne — E : image k, numéro de ligne n (1 à 625), couleur, tampon de
   référence → T : F, V (ITU-R BT.656, 625 lignes), EAV, suppression, SAV,
   1 440 octets actifs ou de suppression → S : 1 728 octets ; les octets
   actifs sont aussi ajoutés à la référence si ref est donné */
function ligne(k, n, couleur, ref) {
    const f = n >= 313 ? 1 : 0;
    const v = (n <= 22 || (n >= 311 && n <= 335) || n >= 624) ? 1 : 0;
    const b = Buffer.alloc(OCT_LIGNE);
    let p = 0;
    b[p++] = 0xFF; b[p++] = 0x00; b[p++] = 0x00; b[p++] = xy(f, v, 1);
    for (let i = 0; i < OCT_SUPP; i++) { b[p++] = i & 1 ? 0x10 : 0x80; }
    b[p++] = 0xFF; b[p++] = 0x00; b[p++] = 0x00; b[p++] = xy(f, v, 0);
    if (v) {
        for (let i = 0; i < OCT_ACTIF; i++) { b[p++] = i & 1 ? 0x10 : 0x80; }
    } else {
        const r = f ? 2 * (n - 336) + 1 : 2 * (n - 23);
        for (let x = 0; x < L; x += 2) {
            const a = pixel(k, r, x, couleur), c = pixel(k, r, x + 1, couleur);
            b[p++] = a[1]; b[p++] = a[0]; b[p++] = a[2]; b[p++] = c[0];
        }
        if (ref) { ref.push(b.subarray(OCT_LIGNE - OCT_ACTIF)); }
    }
    return b;
}

const flux = [], ref = [];
// fin d'une image précédente (image 2, trame 2), entrée au milieu de la ligne 600
flux.push(ligne(2, 600, true, null).subarray(700));
for (let n = 601; n <= 625; n++) { flux.push(ligne(2, n, true, null)); }
// image 0 en couleur, image 1 en noir et blanc : trames ordonnées par numéro de ligne
for (let n = 1; n <= 625; n++) { flux.push(ligne(0, n, true, ref)); }
for (let n = 1; n <= 625; n++) { flux.push(ligne(1, n, false, ref)); }
// lignes 1 et 2 de l'image suivante (fin de la dernière trame)
for (let n = 1; n <= 2; n++) { flux.push(ligne(3, n, true, null)); }

// les références sont rangées par trame : trame 1 (lignes 23 à 310) puis trame 2 (336 à 623)
const fluxB = Buffer.concat(flux), refB = Buffer.concat(ref);
if (refB.length !== 4 * 288 * OCT_ACTIF) { throw new Error('référence : ' + refB.length + ' octets'); }
for (let i = 0; i < refB.length; i++) { if (refB[i] === 0 || refB[i] === 255) { throw new Error('octet réservé dans la zone active'); } }
fs.writeFileSync(path.join(__dirname, 'bt656.bin'), fluxB);
fs.writeFileSync(path.join(__dirname, 'bt656_ref.bin'), refB);
console.log('bt656.bin', fluxB.length, 'octets ; bt656_ref.bin', refB.length, 'octets (', refB.length / 4, 'couples )');
