/*
================================================================================
  Nom        : refs_video.js
  Projet     : JPEG2DVB, portage FPGA (émetteur DVB-S 23 cm)
  Objet      : extrait les références du côté vidéo (macroblocs, DCT entière,
               quantification, zigzag, VLC, flux élémentaire) à partir des
               conteneurs .j2d de JPEG2DVB 2.x, en fichiers binaires simples
  Auteur     : Eric PERRET
  Date       : 2026-10-19
  Version    : 1.2
  Plateforme : Node.js (aucune dépendance)
  Licence    : CC BY-NC 4.0
  Usage      : node refs_video.js DOSSIER
               DOSSIER : sorties des étapes 01 à 08 d'un même traitement (étape 02
               en DCT entière, étape 03 en régulation TM5, versions 3.0)
  Sorties    : mb0.bin   macroblocs de l'image 0 (octets, 396 × 384)
               dct0.bin  coefficients DCT de l'image 0 (int16 LE)
               q0.bin    coefficients quantifiés, ordre naturel (int16 LE)
               zz0.bin   vecteurs zigzag (int16 LE)
               vlc.bin   bits VLC des macroblocs, toutes images, bout à bout
               mbbits.bin longueur en bits de chaque macrobloc (uint16 LE)
               qcode.bin quantiser_scale_code de chaque slice (octets)
               es.bin    flux élémentaire MPEG-2 (toutes images)
               es_au.bin début de chaque image dans es.bin (uint32 LE)
               ts_v.bin  Transport Stream de l'étape 08 (2.4) pour ces images
  Historique : 1.0  2026-10-19  création
               1.1  2026-10-19  étapes 02 et 03 en 3.0 : DCT entière, régulation TM5
                                (q0.bin quantifié avec le code de chaque rangée)
               1.2  2026-10-19  dossier fpga_test/
================================================================================
*/
'use strict';
const fs = require('fs'), path = require('path');
const SRC = process.argv[2], REF = __dirname;
if (!SRC) { console.error('usage : node refs_video.js DOSSIER'); process.exit(1); }

const TYPES = { u8: Uint8Array, i8: Int8Array, u16: Uint16Array, i16: Int16Array, u32: Uint32Array, i32: Int32Array, f32: Float32Array, f64: Float64Array };
function lireJ2D(nom) {
    const b = fs.readFileSync(path.join(SRC, nom)), buf = b.buffer.slice(b.byteOffset, b.byteOffset + b.length);
    const dv = new DataView(buf);
    if (dv.getUint32(0, false) !== 0x4A324431) { throw new Error(nom + ' : pas un .j2d'); }
    const L = dv.getUint32(4, true), meta = JSON.parse(Buffer.from(buf, 8, L).toString());
    let off = Math.ceil((8 + L) / 8) * 8; const t = {};
    for (const d of meta.tampons) { const T = TYPES[d.type]; t[d.nom] = new T(buf, off, d.n); off += Math.ceil(d.n * T.BYTES_PER_ELEMENT / 8) * 8; }
    return { meta, t };
}
function ecrire(nom, typed) { const b = Buffer.from(typed.buffer, typed.byteOffset, typed.byteLength); fs.writeFileSync(path.join(REF, nom), b); console.log(nom.padEnd(12), b.length, 'octets'); }
const PAR = 396 * 384;

const mb = lireJ2D('macroblocs_ycbcr_420.j2d');
const dct = lireJ2D('coefficients_dct.j2d');
if (dct.meta.dct !== 'entiere') { throw new Error('étape 02 : DCT entière attendue (page 02 en 3.0)'); }
const q = lireJ2D('coefficients_quantified.j2d');
if (q.meta.rate.mode !== 'TM5') { throw new Error('étape 03 : régulation TM5 attendue (page 03 en 3.0)'); }
const zz = lireJ2D('vectors_zigzag.j2d');
const vlc = lireJ2D('bitstreams_vlc.j2d');
const es = lireJ2D('elementary_stream.j2d');

ecrire('mb0.bin', mb.t.mb.slice(0, PAR));
ecrire('dct0.bin', Int16Array.from(dct.t.coef.subarray(0, PAR)));
ecrire('q0.bin', q.t.q.slice(0, PAR));
ecrire('zz0.bin', zz.t.zz.slice(0, PAR));
ecrire('vlc.bin', vlc.t.bits.slice());
ecrire('mbbits.bin', Uint16Array.from(vlc.t.mbBits));
ecrire('qcode.bin', vlc.t.qcode.slice());
ecrire('es.bin', es.t.es.slice());
ecrire('es_au.bin', es.t.au.slice());
fs.copyFileSync(path.join(SRC, 'video.ts'), path.join(REF, 'ts_v.bin')); console.log('ts_v.bin    ', fs.statSync(path.join(REF, 'ts_v.bin')).size, 'octets');
console.log('images :', mb.meta.frames, '— budget T :', q.meta.rate.T, '— codes :', Array.from(vlc.t.qcode).join(' '));
for (let i = 0; i < vlc.t.qcode.length; i++) { if (vlc.t.qcode[i] !== q.t.qcode[i]) { throw new Error('codes des étapes 03 et 05 différents'); } }
