/*
================================================================================
  Nom        : dvbs2.js
  Projet     : JPEG2DVB, portage FPGA (émetteur DVB-S 23 cm)
  Objet      : référence au bit près de l'émetteur DVB-S2 (EN 302 307-1) du
               module dvbs2_tx : QPSK 1/4, trame normale, pilotes, CCM, du
               Transport Stream aux symboles ; port des blocs GNU Radio gr-dtv
               (dvb_bbheader_bb, dvb_bbscrambler_bb, dvb_bch_bb, dvb_ldpc_bb,
               dvbs2_physical_cc) ; le tableau LDPC (annexe B.1) et les
               polynômes BCH (tableau 6a) sont lus dans les sources gr-dtv
  Auteur     : Eric PERRET
  Date       : 2026-11-12
  Version    : 1.0
  Plateforme : Node.js, modules intégrés seulement
  Usage      : node dvbs2.js SOURCES_GRDTV ENTREE_TS.bin NB_TRAMES SORTIE.bin
                 SOURCES_GRDTV : dossier de dvb_ldpc_bb_impl.cc et
                 dvb_bch_bb_impl.cc ; ENTREE_TS.bin : paquets de 188 octets ;
                 SORTIE.bin : un octet par symbole, bit 1 = I négatif, bit 0 =
                 Q négatif ; trame de 33 282 symboles
  Licence    : CC BY-NC 4.0
  Historique : 1.0  2026-11-12  création
================================================================================
*/
'use strict';
const fs = require('fs'), path = require('path');

const KBCH = 16008, NBCH = 16200, NLDPC = 64800, NPAR = NLDPC - NBCH, Q = 135;
const UPL = 1504, DFL = KBCH - 80, SYNC = 0x47;
const NSLOT = 360, NSYM = 90 * NSLOT + 90 + Math.floor(NSLOT / 16) * 36;

/* tableau LDPC 1/4 et polynômes BCH : lus dans les sources gr-dtv */
function lireSources(dir) {
    const ldpc = fs.readFileSync(path.join(dir, 'dvb_ldpc_bb_impl.cc'), 'utf8');
    const a = ldpc.indexOf('ldpc_tab_1_4N[45][13] = {');
    const b = ldpc.indexOf('};', a);
    const nombres = ldpc.slice(a + 25, b).match(/\d+/g).map(Number);
    const table = [];
    let i = 0;
    while (i < nombres.length) { const n = nombres[i]; table.push(nombres.slice(i + 1, i + 1 + n)); i += 13; }
    const bch = fs.readFileSync(path.join(dir, 'dvb_bch_bb_impl.cc'), 'utf8');
    const poly = [];
    for (let k = 1; k <= 12; k++) {
        const m = bch.match(new RegExp('polyn' + String(k).padStart(2, '0') + '\\[\\] = \\{([^}]*)\\}'));
        poly.push(m[1].split(',').map(Number));
    }
    return { table, poly };
}

/* produit de polynômes sur GF(2), coefficients par puissance croissante */
function mult(a, b) {
    const r = new Array(a.length + b.length - 1).fill(0);
    for (let i = 0; i < a.length; i++) for (let j = 0; j < b.length; j++) r[i + j] ^= a[i] & b[j];
    return r;
}

/* CRC-8 de l'en-tête : polynôme réfléchi 0xAB, bits en ordre de transmission */
function crc8Bits(bits) {
    let crc = 0;
    for (const x of bits) {
        const b = x ^ (crc & 1);
        crc >>= 1;
        if (b) crc ^= 0xAB;
    }
    const o = [];
    for (let n = 0; n < 8; n++) o.push((crc >> n) & 1);
    return o;
}

/* CRC-8 des paquets : polynôme 0xD5, octet par octet, MSB en premier */
const crcTab = [];
for (let r = 0; r < 256; r++) {
    let crc = 0;
    for (let j = 7; j >= 0; j--) {
        crc = ((r >> j) & 1) ^ ((crc & 0x80) ? 1 : 0) ? ((crc << 1) ^ 0xD5) & 0xFF : (crc << 1) & 0xFF;
    }
    crcTab[r] = crc;
}

function bits(v, n) { const o = []; for (let i = n - 1; i >= 0; i--) o.push((v >> i) & 1); return o; }

function main() {
    const [dir, entree, nbTrames, sortie] = process.argv.slice(2);
    if (!sortie) { console.error('usage : node dvbs2.js SOURCES_GRDTV ENTREE_TS.bin NB_TRAMES SORTIE.bin'); process.exit(1); }
    const { table, poly } = lireSources(dir);
    const ts = fs.readFileSync(entree);
    const nTr = Number(nbTrames);
    if (table.length !== 45 || poly.length !== 12) throw new Error('lecture des tables');

    /* g(x) BCH t = 12, 192 bits de parité */
    let g = poly[0];
    for (let k = 1; k < 12; k++) g = mult(g, poly[k]);
    if (g.length !== 193) throw new Error('degré BCH ' + (g.length - 1));

    /* table LDPC : pour chaque bit de parité, les bits d'information (ldpc_bf) */
    const lut = Array.from({ length: NPAR }, () => []);
    for (let row = 0; row < table.length; row++) {
        for (let n = 0; n < 360; n++) {
            for (const c of table[row]) lut[(c + n * Q) % NPAR].push(row * 360 + n);
        }
    }

    /* brouilleur des trames BB : sr = 0x4A80 */
    const rnd = [];
    let sr = 0x4A80;
    for (let i = 0; i < KBCH; i++) {
        const b = (sr ^ (sr >> 1)) & 1;
        rnd.push(b);
        sr >>= 1;
        if (b) sr |= 0x4000;
    }

    /* brouilleur physique (suite de Gold, n = 0) */
    const par = (a, m) => { let c = 0; a &= m; for (let i = 0; i < 18; i++) if (a & (1 << i)) c++; return c & 1; };
    const cscram = [];
    {
        let x = 1, y = 0x3FFFF;
        for (let i = 0; i < NLDPC; i++) {
            const xa = par(x, 0x8050), xb = par(x, 0x0081), xc = x & 1;
            x >>= 1; if (xb) x |= 0x20000;
            const ya = par(y, 0x04A1), yb = par(y, 0xFF60), yc = y & 1;
            y >>= 1; if (ya) y |= 0x20000;
            cscram.push(((xa ^ yb) << 1) + (xc ^ yc));
        }
    }

    /* en-tête PL : SOF + PLS (MODCOD 1, pilotes : code 5), π/2-BPSK */
    const sof = [0,1,1,0,0,0,1,1,0,1,0,0,1,0,1,1,1,0,1,0,0,0,0,0,1,0];
    const gRM = [0x90AC2DDD, 0x55555555, 0x33333333, 0x0F0F0F0F, 0x00FF00FF, 0x0000FFFF, 0xFFFFFFFF];
    const scr = [0,1,1,1,0,0,0,1,1,0,0,1,1,1,0,1,1,0,0,0,0,0,1,1,1,1,0,0,1,0,0,1,0,1,0,1,0,0,1,1,0,1,0,0,0,0,1,0,0,0,1,0,1,1,0,1,1,1,1,1,1,0,1,0];
    const code = (1 << 2) | 1;
    let t = 0;
    for (let k = 0; k < 7; k++) if (code & (0x80 >> k)) t = (t ^ gRM[k]) >>> 0;
    const pls = [];
    for (let m = 0; m < 32; m++) {
        const b = (t >>> (31 - m)) & 1;
        pls.push(b, b ^ (code & 1));
    }
    const hb = sof.concat(pls.map((x, m) => x ^ scr[m]));
    const entete = hb.map((b, i) => (i & 1) ? (b ? [0, 1] : [1, 0]) : (b ? [1, 1] : [0, 0]));   /* [I négatif, Q négatif] */

    const sortieOct = [];
    let pos = 0, count = 0, crc = 0;
    for (let f = 0; f < nTr; f++) {
        /* en-tête BB */
        const h = [1, 1, 1, 1, 0, 0, 0, 0].concat(bits(0, 8), bits(UPL, 16), bits(DFL, 16), bits(SYNC, 8),
                                                   bits(count === 0 ? 0 : (188 - count) * 8, 16));
        const trame = h.concat(crc8Bits(h));
        for (let j = 0; j < (KBCH - 80) / 8; j++) {
            let b;
            if (count === 0) {
                if (ts[pos] !== 0x47) throw new Error('synchro TS');
                pos++; b = crc; crc = 0;
            } else {
                b = ts[pos++]; crc = crcTab[b ^ crc];
            }
            count = (count + 1) % 188;
            for (let n = 7; n >= 0; n--) trame.push((b >> n) & 1);
        }
        /* brouillage, BCH */
        const d = trame.map((x, i) => x ^ rnd[i]);
        const reste = new Array(192).fill(0);                   /* reste, index = puissance */
        for (let i = 0; i < KBCH; i++) {
            const fb = d[i] ^ reste[191];
            for (let k = 191; k > 0; k--) reste[k] = reste[k - 1] ^ (fb & g[k]);
            reste[0] = fb & g[0];
        }
        const mot = d.slice();
        for (let k = 191; k >= 0; k--) mot.push(reste[k]);
        if (mot.length !== NBCH) throw new Error('longueur BCH');
        /* LDPC */
        const p = new Array(NPAR);
        for (let i = 0; i < NPAR; i++) { let v = 0; for (const x of lut[i]) v ^= mot[x]; p[i] = v; }
        for (let j = 1; j < NPAR; j++) p[j] ^= p[j - 1];
        const cw = mot.concat(p);
        /* QPSK, trame PL */
        const sym = [];
        for (let i = 0; i < NLDPC; i += 2) sym.push([cw[i], cw[i + 1]]);
        for (const s of entete) sortieOct.push((s[0] << 1) | s[1]);
        let n = 0;
        for (let j = 0; j < NSLOT; j++) {
            for (let k = 0; k < 90; k++) sortieOct.push(brouille(sym[j * 90 + k], cscram[n++]));
            if ((j + 1) % 16 === 0 && j < NSLOT - 1) {
                for (let k = 0; k < 36; k++) sortieOct.push(brouille([0, 0], cscram[n++]));
            }
        }
    }
    function brouille(s, r) {
        let i = s[0], q = s[1];
        if (r === 1) { const ni = q ^ 1, nq = i; i = ni; q = nq; }
        else if (r === 2) { i ^= 1; q ^= 1; }
        else if (r === 3) { const ni = q, nq = i ^ 1; i = ni; q = nq; }
        return (i << 1) | q;
    }
    if (sortieOct.length !== nTr * NSYM) throw new Error('longueur de trame ' + sortieOct.length);
    fs.writeFileSync(sortie, Buffer.from(sortieOct));
    console.log(nTr + ' trames, ' + sortieOct.length + ' symboles, ' + pos + ' octets TS consommés → ' + sortie);
}
main();
