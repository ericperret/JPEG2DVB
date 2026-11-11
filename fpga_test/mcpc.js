/*
================================================================================
  Nom        : mcpc.js
  Projet     : JPEG2DVB, portage FPGA (émetteur DVB-S 23 cm)
  Objet      : référence au bit près du multiplexeur TS à deux programmes
               (MCPC) du module ts_mux : programme 1 (PMT 0x0100, vidéo 0x0101,
               PCR), programme 2 (PMT 0x0200, vidéo 0x0201, même PCR) ; mêmes
               règles entières que la page 08 pour le programme 1 ; contrôle
               que le mode à un programme redonne ts_v.bin ; écrit le flux
               élémentaire du canal 2 du banc (es2.bin, tiré de mire_ts.bin) et
               la référence ts_mcpc.bin
  Auteur     : Eric PERRET
  Date       : 2026-11-11
  Version    : 1.0
  Plateforme : Node.js, modules intégrés seulement
  Usage      : node mcpc.js
  Licence    : CC BY-NC 4.0
  Historique : 1.0  2026-11-11  création

  Règles (identiques au VHDL) :
    Images : un flux élémentaire est découpé en images à chaque
      sequence_header (00 00 01 B3) et à chaque picture_start (00 00 01 00)
      hors en-tête de séquence ; sequence_end (00 00 01 B7) ferme la dernière.
    Créneau k (un paquet) : PAT si 51k ≥ 25 000·m, puis PMT 1, puis PMT 2 (MCPC)
      aux créneaux suivants ; sinon PCR dû si 51k ≥ 9 375·m ; canal 1 si son
      image n est complète et 51k ≥ 12 500·(n + 1) ; sinon, en MCPC, canal 2
      à la même condition, sauf au créneau d'un PCR dû (PCR seul sur 0x0101) ;
      sinon PCR seul ou paquet nul.
    PES : un par image, 00 00 01 E0, longueur, 84 80 05, PTS = 3 600·(n + 1) +
      9 000 ; random_access au début de chaque GOP de 12 images.
    PCR(k) = round((188k + 10)·5 508 / 235), dans le champ d'adaptation du
      canal 1 ; le programme 2 déclare le même PID de PCR.
================================================================================
*/
'use strict';
const fs = require('fs'), path = require('path');
const ici = f => path.join(__dirname, f);
const G_K = 51, G_PSI = 25000, G_PCR = 9375, G_IMG = 12500, G_GOP = 12;

/* crc32 — E : octets → S : CRC-32 MPEG-2 */
function crc32(d) {
    let c = 0xFFFFFFFF;
    for (const o of d) { for (let b = 7; b >= 0; b--) { const f = ((c >>> 31) ^ (o >> b)) & 1; c = (c << 1) >>> 0; if (f) { c = (c ^ 0x04C11DB7) >>> 0; } } }
    return c;
}

/* paquetPsi — E : en-tête TS avec pointer_field, section sans CRC → S : paquet de 188 octets */
function paquetPsi(entete, sect) {
    const p = Buffer.alloc(188, 0xFF), c = crc32(sect);
    Buffer.from(entete).copy(p, 0); Buffer.from(sect).copy(p, entete.length);
    p.writeUInt32BE(c, entete.length + sect.length);
    return p;
}
const PAT1 = paquetPsi([0x47, 0x40, 0x00, 0x10, 0x00], [0x00, 0xB0, 0x0D, 0x00, 0x01, 0xC1, 0x00, 0x00, 0x00, 0x01, 0xE1, 0x00]);
const PAT2 = paquetPsi([0x47, 0x40, 0x00, 0x10, 0x00], [0x00, 0xB0, 0x11, 0x00, 0x01, 0xC1, 0x00, 0x00, 0x00, 0x01, 0xE1, 0x00, 0x00, 0x02, 0xE2, 0x00]);
const PMT1 = paquetPsi([0x47, 0x41, 0x00, 0x10, 0x00], [0x02, 0xB0, 0x12, 0x00, 0x01, 0xC1, 0x00, 0x00, 0xE1, 0x01, 0xF0, 0x00, 0x02, 0xE1, 0x01, 0xF0, 0x00]);
const PMT2 = paquetPsi([0x47, 0x42, 0x00, 0x10, 0x00], [0x02, 0xB0, 0x12, 0x00, 0x02, 0xC1, 0x00, 0x00, 0xE1, 0x01, 0xF0, 0x00, 0x02, 0xE2, 0x01, 0xF0, 0x00]);

/* images — E : flux élémentaire → S : [début, fin[ de chaque image complète */
function images(es) {
    const l = [];
    let seq = false, deb = -1;
    for (let w = 3; w < es.length; w++) {
        if (es[w - 3] !== 0 || es[w - 2] !== 0 || es[w - 1] !== 1) { continue; }
        const o = es[w];
        if (o === 0xB3 || (o === 0x00 && !seq)) { if (deb >= 0) { l.push([deb, w - 3]); } deb = w - 3; seq = o === 0xB3; }
        else if (o === 0x00) { seq = false; }
        else if (o === 0xB7) { l.push([deb, w + 1]); deb = -1; }
    }
    return l;
}

/* multiplexe — E : flux élémentaires (1 ou 2 canaux), nombre de paquets → T :
   choix du paquet de chaque créneau, PES, PCR → S : Transport Stream */
function multiplexe(flux, N) {
    const mcpc = flux.length === 2, out = Buffer.alloc(188 * N);
    const can = flux.map(es => ({ es: es, img: images(es), n: 0, gop: 0, ptr: 0, lg: 0, cc: 0, d: -G_IMG, pts: 12600 }));
    let dPsi = 0, dPcr = 0, pmtDu = 0, base = 0, ext = 234, r = 415, ccPat = 0, ccPmt = [0, 0];
    const SAT = 2 ** 38;
    for (let k = 0; k < N; k++) {
        const p = out.subarray(188 * k, 188 * k + 188);
        const firePsi = dPsi >= 0, firePcr = dPcr >= 0, pret = can.map(c => c.n < c.img.length && c.d >= 0);
        dPsi += G_K; dPcr += G_K;
        for (const c of can) { if (c.d < SAT) { c.d += G_K; } }
        const pBase = base, pExt = ext;
        const pcr = q => { q[6] = Math.floor(pBase / 2 ** 25) & 255; q[7] = Math.floor(pBase / 2 ** 17) & 255; q[8] = Math.floor(pBase / 2 ** 9) & 255; q[9] = Math.floor(pBase / 2) & 255; q[10] = ((pBase & 1) << 7) | 0x7E | (pExt >> 8); q[11] = pExt & 255; };
        p.fill(0xFF);
        if (firePsi) {
            (mcpc ? PAT2 : PAT1).copy(p); p[3] = 0x10 | ccPat; ccPat = (ccPat + 1) & 15; pmtDu = mcpc ? 2 : 1; dPsi -= G_PSI;
        } else if (pmtDu > 0) {
            const i = mcpc ? 2 - pmtDu : 0;
            (i === 0 ? PMT1 : PMT2).copy(p); p[3] = 0x10 | ccPmt[i]; ccPmt[i] = (ccPmt[i] + 1) & 15; pmtDu--;
        } else {
            if (firePcr) { dPcr -= G_PCR; }
            const v = pret[0] ? 0 : (mcpc && pret[1] && !firePcr ? 1 : -1);
            if (v < 0) {
                if (firePcr) { p[0] = 0x47; p[1] = 0x01; p[2] = 0x01; p[3] = 0x20 | can[0].cc; p[4] = 183; p[5] = 0x10; pcr(p); }
                else { p[0] = 0x47; p[1] = 0x1F; p[2] = 0xFF; p[3] = 0x10; }
            } else {
                const c = can[v], im = c.img[c.n], debut = c.ptr === 0, rai = debut && c.gop === 0, avecPcr = v === 0 && firePcr;
                if (debut) { c.lg = im[1] - im[0] + 14; }
                const af = avecPcr ? 8 : (rai ? 2 : 0), cu = Math.min(c.lg - c.ptr, 184 - af), afl = 184 - cu;
                p[0] = 0x47; p[1] = (debut ? 0x40 : 0) | (v === 0 ? 0x01 : 0x02); p[2] = 0x01; p[3] = (afl > 0 ? 0x30 : 0x10) | c.cc;
                if (afl > 0) { p[4] = afl - 1; }
                if (afl > 1) { p[5] = (rai ? 0x40 : 0) | (avecPcr ? 0x10 : 0); }
                if (avecPcr) { pcr(p); }
                for (let pos = 4 + afl; pos < 188; pos++) {
                    const q = c.ptr, lgp = c.lg - 6;
                    let o;
                    switch (q) {
                        case 0: case 1: o = 0; break;
                        case 2: o = 1; break;
                        case 3: o = 0xE0; break;
                        case 4: o = lgp > 65535 ? 0 : lgp >> 8; break;
                        case 5: o = lgp > 65535 ? 0 : lgp & 255; break;
                        case 6: o = 0x84; break;
                        case 7: o = 0x80; break;
                        case 8: o = 0x05; break;
                        case 9: o = 0x21 | ((Math.floor(c.pts / 2 ** 30) & 7) << 1); break;
                        case 10: o = Math.floor(c.pts / 2 ** 22) & 255; break;
                        case 11: o = ((Math.floor(c.pts / 2 ** 15) & 127) << 1) | 1; break;
                        case 12: o = Math.floor(c.pts / 2 ** 7) & 255; break;
                        case 13: o = ((c.pts & 127) << 1) | 1; break;
                        default: o = c.es[im[0] + q - 14];
                    }
                    p[pos] = o;
                    if (c.ptr === c.lg - 1) { c.ptr = 0; c.n++; c.gop = (c.gop + 1) % G_GOP; c.d -= G_IMG; c.pts = (c.pts + 3600) % 2 ** 33; } else { c.ptr++; }
                }
                c.cc = (c.cc + 1) & 15;
            }
        }
        // PCR du créneau suivant
        let e2 = r + 188, carry = 0;
        if (e2 >= 470) { carry = 1; e2 -= 470; }
        r = e2;
        if (ext + 206 + carry >= 300) { ext = ext + 206 + carry - 300; base = (base + 15) % 2 ** 33; } else { ext = ext + 206 + carry; base = (base + 14) % 2 ** 33; }
    }
    return { ts: out, reste: can.map(c => c.img.length - c.n) };
}

/* canal2 — E : mire_ts.bin → T : charges du PID 0x0101 sans les en-têtes PES →
   S : flux élémentaire de la mire */
function canal2() {
    const ts = fs.readFileSync(ici('mire_ts.bin')), l = [];
    for (let k = 0; k < ts.length / 188; k++) {
        const p = ts.subarray(188 * k, 188 * k + 188);
        if ((((p[1] & 0x1F) << 8) | p[2]) !== 0x0101 || !(p[3] & 0x10)) { continue; }
        let h = (p[3] & 0x20) ? 5 + p[4] : 4;
        if (p[1] & 0x40) { h += 14; }
        l.push(p.subarray(h));
    }
    return Buffer.concat(l);
}

// ---------------------------------------------------------------------------
const es1 = fs.readFileSync(ici('es.bin')), ref = fs.readFileSync(ici('ts_v.bin'));
const un = multiplexe([es1], ref.length / 188);
let ecarts = 0;
for (let i = 0; i < ref.length; i++) { if (un.ts[i] !== ref[i]) { ecarts++; } }
console.log('un programme : ' + (ecarts ? ecarts + ' octets DIFFÉRENTS de ts_v.bin' : 'identique à ts_v.bin (' + ref.length / 188 + ' paquets)'));
if (ecarts) { process.exit(1); }
const es2 = canal2();
fs.writeFileSync(ici('es2.bin'), es2);
const N = 1900, deux = multiplexe([es1, es2], N);
fs.writeFileSync(ici('ts_mcpc.bin'), deux.ts);
const compte = {};
for (let k = 0; k < N; k++) { const pid = ((deux.ts[188 * k + 1] & 0x1F) << 8) | deux.ts[188 * k + 2]; compte[pid] = (compte[pid] || 0) + 1; }
console.log('canal 2      : es2.bin, ' + es2.length + ' octets, ' + images(es2).length + ' images (canal 1 : ' + es1.length + ' octets, ' + images(es1).length + ' images)');
console.log('deux programmes : ts_mcpc.bin, ' + N + ' paquets ; par PID : ' + Object.keys(compte).map(k => '0x' + (+k).toString(16).toUpperCase().padStart(4, '0') + ' ' + compte[k]).join(', ') + ' ; images non envoyées : ' + deux.reste.join(', '));
