/*
================================================================================
  Nom        : refs_video.js
  Projet     : JPEG2DVB, portage FPGA (émetteur DVB-S 23 cm)
  Objet      : extrait les références du côté vidéo (macroblocs, DCT entière,
               quantification, zigzag, VLC, flux élémentaire) à partir des
               conteneurs .j2d de JPEG2DVB 2.x, en fichiers binaires simples
  Auteur     : Eric PERRET
  Date       : 2026-10-19
  Version    : 1.0
  Plateforme : Node.js (aucune dépendance)
  Licence    : CC BY-NC 4.0
  Usage      : node refs_video.js DOSSIER
               DOSSIER : sorties des étapes 01 à 06 d'un même traitement, DCT en
               virgule fixe (étape 02) et régulation « fixe » (étape 03)
  Sorties    : ref/mb0.bin   macroblocs de l'image 0 (octets, 396 × 384)
               ref/dct0.bin  coefficients DCT de l'image 0 (int16 LE)
               ref/q0.bin    coefficients quantifiés, ordre naturel (int16 LE)
               ref/zz0.bin   vecteurs zigzag (int16 LE)
               ref/vlc.bin   bits VLC des macroblocs, toutes images, bout à bout
               ref/mbbits.bin longueur en bits de chaque macrobloc (uint16 LE)
               ref/qcode.bin quantiser_scale_code de chaque slice (octets)
               ref/es.bin    flux élémentaire MPEG-2 (toutes images)
               ref/es_au.bin début de chaque image dans es.bin (uint32 LE)
  Historique : 1.0  2026-10-19  création
================================================================================
*/
'use strict';
const fs = require('fs'), path = require('path');
const SRC = process.argv[2], REF = path.join(__dirname, '..', 'ref');
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
if (dct.meta.dct !== 'fixe') { throw new Error('étape 02 : la DCT doit être en virgule fixe'); }
const q = lireJ2D('coefficients_quantified.j2d');
if (q.meta.rate.mode !== 'fixe') { throw new Error('étape 03 : la régulation doit être « fixe »'); }
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
console.log('images :', mb.meta.frames, '— quantiser_scale_code :', q.meta.quantization.quantiser_scale_code, '— matrice :', q.meta.quantization.matrix);
