/*
================================================================================
  Nom        : dvbt_ref.js
  Projet     : JPEG2DVB, mode DVB-T réduit (2K, 6 MHz, QPSK 1/2, garde 1/32)
  Objet      : référence au bit près de la chaîne DVB-T (EN 300 744) :
               mots (X, Y) du codeur convolutif → entrelaceur de bits →
               entrelaceur de symboles → cellules (données, pilotes, TPS) →
               FFT inverse 2048 points entière → intervalle de garde →
               filtre polyphasé 35/3 vers 80 MS/s → apports du sigma-delta
               (maintien ×8) ; contrôle de la FFT contre une FFT flottante
  Auteur     : Eric PERRET
  Date       : 2026-11-24
  Version    : 1.0
  Plateforme : Node.js, modules intégrés seulement
  Usage      : node dvbt_ref.js mots N SORTIE_DIR
               (mots : fichier d'octets, un octet par mot : bit 1 = X, bit 0 = Y ;
                N symboles OFDM à produire ; écrit des fichiers texte dans SORTIE_DIR)
               node dvbt_ref.js mesure      (contrôles de la FFT et du filtre)
  Licence    : CC BY-NC 4.0
  Historique : 1.0  2026-11-24  création
================================================================================
*/
'use strict';
const fs = require('fs'), path = require('path');

// ---- paramètres -------------------------------------------------------------
const NFFT = 2048, NACT = 1705, NPAY = 1512, NSYM_FR = 68;
const AMP = 200;                                   // demi-amplitude des données (I, Q = ±AMP)
const AMP_TPS = Math.round(AMP * Math.SQRT2);      // TPS : |c| = 1       → 283
const AMP_PIL = Math.round(AMP * Math.SQRT2 * 4 / 3); // pilotes : 4/3     → 377
const TW = 8191;                                   // twiddle : amplitude (14 bits signés)
const SCALE = [0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1];   // décalage de 1 bit après l'étage s (s = 1 à 11)
const WMAX = 8191;                                 // saturation 14 bits
const NPH = 35, NTAP = 16, HQ = 14;                // filtre polyphasé : phases, coefficients, échelle 2^14
const VMAX = 481;                                  // écrêtage : 56 · 481 ≤ 26 966

const CPIL = [0, 48, 54, 87, 141, 156, 192, 201, 255, 279, 282, 333, 432, 450, 483, 525, 531, 618, 636, 714, 759, 765, 780, 804, 873, 888, 918, 939, 942, 969, 984, 1050, 1101, 1107, 1110, 1137, 1140, 1146, 1206, 1269, 1323, 1377, 1491, 1683, 1704];
const TPSC = [34, 50, 209, 346, 413, 569, 595, 688, 790, 901, 1073, 1219, 1262, 1286, 1469, 1594, 1687];
const BITPERM = [4, 3, 9, 6, 2, 8, 1, 5, 7, 0];

// ---- PRBS wk : x^11 + x^2 + 1, tout à 1 au début de chaque symbole -------------
function prbs() {
    const w = new Uint8Array(NACT);
    let r = 0x7ff;
    for (let k = 0; k < NACT; k++) { w[k] = r & 1; const nb = ((r >> 2) ^ r) & 1; r = (r >> 1) | (nb << 10); }
    return w;
}
const WK = prbs();

// ---- TPS : 68 bits par trame, 4 trames par supertrame ---------------------------
function tpsTrame(f) {
    const d = new Uint8Array(NSYM_FR);
    const set = (a, b, v) => { for (let i = a; i >= b; i--) { d[i] = v & 1; v >>= 1; } };
    d[0] = WK[0];
    set(16, 1, (f % 2) ? 0xca11 : 0x35ee);
    set(22, 17, 0x17);
    set(24, 23, f);
    // constellation QPSK 00, hiérarchie 000, débits 000 000, garde 1/32 00, mode 2K 00, cellule 0
    let reg = 0;
    const din = new Uint8Array(113);
    for (let i = 0; i < 53; i++) { din[60 + i] = d[1 + i]; }
    for (let i = 0; i < 113; i++) {
        const fb = (din[i] ^ reg) & 1;
        reg >>= 1; reg |= fb << 13;
        reg ^= (fb << 12) ^ (fb << 11) ^ (fb << 9) ^ (fb << 8) ^ (fb << 7) ^ (fb << 5) ^ (fb << 4);
    }
    for (let i = 0; i < 14; i++) { d[54 + i] = (reg >> i) & 1; }
    return d;
}
const TPS = [0, 1, 2, 3].map(tpsTrame);

// ---- entrelaceur de symboles : H(q), q = 0 à 1511 --------------------------------
function tableH() {
    const h = [];
    let reg = 0;
    for (let i = 0; i < NFFT; i++) {
        if (i === 0 || i === 1) { reg = 0; }
        else if (i === 2) { reg = 1; }
        else { const nb = (reg ^ (reg >> 3)) & 1; reg = ((reg >> 1) | (nb << 9)) & 0x7ff; }
        let nr = 0;
        for (let k = 0; k < 10; k++) { nr |= ((reg >> k) & 1) << BITPERM[k]; }
        const v = ((i % 2) << 10) + nr;
        if (v < NPAY) { h.push(v); }
    }
    return h;
}
const H = tableH();

// ---- entrelaceur de bits : blocs de 126 mots (X, Y) → (X[w], Y[(w + 63) mod 126]) ---
function entrelaceBits(mots) {
    const n = mots.length - mots.length % 126, out = new Uint8Array(n);
    for (let b = 0; b < n; b += 126) {
        for (let w = 0; w < 126; w++) {
            const x = (mots[b + w] >> 1) & 1, y = mots[b + (w + 63) % 126] & 1;
            out[b + w] = (x << 1) | y;
        }
    }
    return out;
}

// ---- cellules d'un symbole (l = 0 à 67, f = 0 à 3) : tableaux I, Q, longueur 1705 ------
function cellules(mots, l, f, etatTps) {
    // mots : 1512 mots (bit 1 → I, bit 0 → Q ; 0 → +) déjà entrelacés par symbole
    const I = new Int32Array(NACT), Q = new Int32Array(NACT);
    const cp = new Set(CPIL), tp = new Map(TPSC.map((k, i) => [k, i]));
    let dn = 0;
    if (l === 0) { for (let t = 0; t < 17; t++) { etatTps[t] = WK[TPSC[t]]; } }
    else { const b = TPS[f][l]; if (b) { for (let t = 0; t < 17; t++) { etatTps[t] ^= 1; } } }
    for (let k = 0; k < NACT; k++) {
        if (tp.has(k)) { I[k] = etatTps[tp.get(k)] ? -AMP_TPS : AMP_TPS; }
        else if (cp.has(k) || (k % 12) === 3 * (l % 4)) { I[k] = WK[k] ? -AMP_PIL : AMP_PIL; }
        else {
            const w = mots[dn++];
            I[k] = (w & 2) ? -AMP : AMP; Q[k] = (w & 1) ? -AMP : AMP;
        }
    }
    if (dn !== NPAY) { throw new Error('cellules de données : ' + dn); }
    return { I: I, Q: Q };
}

// entrelacement d'un symbole de 1512 mots : pair : sortie[H(q)] = entrée[q] ; impair : sortie[q] = entrée[H(q)]
function entrelaceSymbole(w, l) {
    const o = new Uint8Array(NPAY);
    for (let q = 0; q < NPAY; q++) { if (l % 2) { o[q] = w[H[q]]; } else { o[H[q]] = w[q]; } }
    return o;
}

// ---- FFT inverse entière, DIT sur place, entrée en ordre bit-inversé ------------------
const rev11 = i => { let r = 0; for (let b = 0; b < 11; b++) { r |= ((i >> b) & 1) << (10 - b); } return r; };
// table en quart d'onde T[r] = round(8191·cos(2π r / 2048)), r = 0 à 512 ; cos et sin des indices 0 à 1023 s'en déduisent
const TQ = new Int32Array(513);
for (let r = 0; r <= 512; r++) { TQ[r] = Math.round(TW * Math.cos(2 * Math.PI * r / NFFT)); }
const TWC = new Int32Array(NFFT / 2), TWS = new Int32Array(NFFT / 2);
for (let m = 0; m < NFFT / 2; m++) {
    if (m < 512) { TWC[m] = TQ[m]; TWS[m] = TQ[512 - m]; } else { const r = m - 512; TWC[m] = -TQ[512 - r]; TWS[m] = TQ[r]; }
}
const sat = v => v > WMAX ? WMAX : v < -WMAX - 1 ? -WMAX - 1 : v;
function ifft(cI, cQ, bilan) {
    // cI, cQ : cellules par bin de fréquence 0 à 2047 ; retourne le signal temporel
    const xr = new Int32Array(NFFT), xi = new Int32Array(NFFT);
    for (let k = 0; k < NFFT; k++) { xr[rev11(k)] = cI[k]; xi[rev11(k)] = cQ[k]; }
    for (let s = 1; s <= 11; s++) {
        const d = 1 << (s - 1);
        for (let a = 0; a < NFFT; a++) {
            if (a & d) { continue; }
            const b = a + d, j = a & (d - 1), m = j * (NFFT / 2 / d);
            const c = TWC[m], sn = TWS[m];
            const tr = (xr[b] * c - xi[b] * sn + 4096) >> 13, ti = (xr[b] * sn + xi[b] * c + 4096) >> 13;
            let yr = xr[a] + tr, yi = xi[a] + ti, zr = xr[a] - tr, zi = xi[a] - ti;
            if (SCALE[s - 1]) { yr = (yr + 1) >> 1; yi = (yi + 1) >> 1; zr = (zr + 1) >> 1; zi = (zi + 1) >> 1; }
            if (bilan) { bilan.max = Math.max(bilan.max, Math.abs(yr), Math.abs(yi), Math.abs(zr), Math.abs(zi)); if (Math.abs(yr) > WMAX || Math.abs(yi) > WMAX || Math.abs(zr) > WMAX || Math.abs(zi) > WMAX) { bilan.sat++; } }
            xr[a] = sat(yr); xi[a] = sat(yi); xr[b] = sat(zr); xi[b] = sat(zi);
        }
    }
    return { re: xr, im: xi };
}
// carrière k (0 à 1704) → bin : K' = k − 852, bin = K' mod 2048
const binDe = k => (k - 852 + NFFT) % NFFT;

// ---- filtre polyphasé 35/3 : coefficients entiers [phase][i], i = 0 à 15 -----------------
function bessel0(x) { let s = 1, t = 1; const q = (x / 2) * (x / 2); for (let k = 1; k < 60; k++) { t *= q / (k * k); s += t; } return s; }
function coefFiltre() {
    // prototype passe-bas à 80 MS/s, longueur 16 × 35/3 échantillons d'entrée, fc = 3,43 MHz (fs_in / 2)
    const L = NTAP, BETA = 5.5;
    const H = [];
    for (let p = 0; p < NPH; p++) {
        const f = p / NPH, r = [];
        let s = 0;
        for (let i = 0; i < L; i++) {
            const u = f + i - (L - 1) / 2;                  // distance au centre, en échantillons d'entrée
            const x = u / (L / 2);
            const w = Math.abs(x) <= 1 ? bessel0(BETA * Math.sqrt(1 - x * x)) / bessel0(BETA) : 0;
            const sinc = Math.abs(u) < 1e-12 ? 1 : Math.sin(Math.PI * u * 0.98) / (Math.PI * u * 0.98);   // coupure 0,49 fs_in
            r.push(sinc * w); s += sinc * w;
        }
        H.push(r.map(v => v / s));
    }
    return H;
}
const HF = coefFiltre();
const HI = HF.map(r => r.map(v => Math.round(v * (1 << HQ))));

// ---- filtre : flux de symboles temporels (avec garde) → v à 80 MS/s, un par cycle ---------
//  Position de sortie n (0 à 24639 par symbole) : phase p = 3n mod 35, nouvel échantillon d'entrée
//  quand 3n mod 35 < 3 (le premier cycle de chaque période) — voir dvbt_ref.js §modèle
function filtre(xr, xi) {
    // xr, xi : flux continu d'échantillons à 6,857 MS/s ; sortie : 80 MS/s, retard fixe
    const n = Math.floor(xr.length * NPH / 3);
    const vr = new Int32Array(n), vi = new Int32Array(n);
    let m = -1, ph = 0;
    for (let o = 0; o < n; o++) {
        // avance de 3/35 d'échantillon d'entrée : un nouvel échantillon entre quand le cumul dépasse
        if (ph < 3) { m++; }                        // ph = (3·o) mod 35 : < 3 → un nouvel échantillon est arrivé
        const p = ph;
        let sr = 0, si = 0;
        for (let i = 0; i < NTAP; i++) {
            const k = m - i;
            if (k >= 0 && k < xr.length) { sr += xr[k] * HI[p][i]; si += xi[k] * HI[p][i]; }
        }
        const rr = Math.max(-VMAX, Math.min(VMAX, (sr + (1 << (HQ - 1))) >> HQ));
        const rq = Math.max(-VMAX, Math.min(VMAX, (si + (1 << (HQ - 1))) >> HQ));
        vr[o] = rr; vi[o] = rq;
        ph = (ph + 3) % NPH;
    }
    return { vr: vr, vi: vi };
}

// ---- construction complète ---------------------------------------------------------------
function chaine(mots, nsym) {
    const be = entrelaceBits(mots);
    const etat = new Int32Array(17);
    const sym = [], cells = [];
    let flux = { re: [], im: [] };
    const bilan = { max: 0, sat: 0 };
    for (let s = 0; s < nsym; s++) {
        const l = s % NSYM_FR, f = Math.floor(s / NSYM_FR) % 4;
        const w = entrelaceSymbole(be.subarray(s * NPAY, (s + 1) * NPAY), l);
        const c = cellules(w, l, f, etat);
        const cI = new Int32Array(NFFT), cQ = new Int32Array(NFFT);
        for (let k = 0; k < NACT; k++) { cI[binDe(k)] = c.I[k]; cQ[binDe(k)] = c.Q[k]; }
        const t = ifft(cI, cQ, bilan);
        cells.push({ I: c.I, Q: c.Q, bins: [cI, cQ] });
        sym.push(t);
        for (let n = 0; n < 64; n++) { flux.re.push(t.re[NFFT - 64 + n]); flux.im.push(t.im[NFFT - 64 + n]); }
        for (let n = 0; n < NFFT; n++) { flux.re.push(t.re[n]); flux.im.push(t.im[n]); }
    }
    return { be: be, cells: cells, sym: sym, flux: flux, bilan: bilan };
}

module.exports = { TQ, BITPERM, NFFT, NACT, NPAY, H, TPS, WK, CPIL, TPSC, HI, HF, entrelaceBits, entrelaceSymbole, cellules, ifft, binDe, rev11, filtre, chaine, AMP, AMP_PIL, AMP_TPS, VMAX, TWC, TWS };

// ---- exécution ------------------------------------------------------------------------------
if (require.main === module) {
    const arg = process.argv[2];
    if (arg === 'vect') {
        // vect N DIR : mots aléatoires (déterministes), sortie du filtre v à 80 MS/s (un couple par ligne)
        const nsym = +process.argv[3], dir = process.argv[4];
        let seed = 777;
        const rnd = () => { seed = (seed * 1103515245 + 12345) & 0x7fffffff; return seed >> 16; };
        const mots = new Uint8Array(nsym * NPAY);
        for (let i = 0; i < mots.length; i++) { mots[i] = rnd() & 3; }
        const r = chaine(mots, nsym);
        const fl = filtre(Int32Array.from(r.flux.re), Int32Array.from(r.flux.im));
        fs.mkdirSync(dir, { recursive: true });
        fs.writeFileSync(path.join(dir, 'mots.txt'), Array.from(mots).join('\n') + '\n');
        const o = [];
        for (let i = 0; i < fl.vr.length; i++) { o.push(fl.vr[i] + ' ' + fl.vi[i]); }
        fs.writeFileSync(path.join(dir, 'ref_v.txt'), o.join('\n') + '\n');
        // symboles temporels (sortie de la FFT) : 2048 couples par symbole
        const t = [];
        for (const sy of r.sym) { for (let n = 0; n < NFFT; n++) { t.push(sy.re[n] + ' ' + sy.im[n]); } }
        fs.writeFileSync(path.join(dir, 'ref_fft.txt'), t.join('\n') + '\n');
        console.log('écrit : ' + mots.length + ' mots, ' + fl.vr.length + ' groupes, ' + r.sym.length + ' symboles FFT ; crête ' + Math.max(...Array.from(fl.vr).map(Math.abs)));
    }
    if (arg === 'mesure') {
        // mots aléatoires déterministes
        let seed = 12345;
        const rnd = () => { seed = (seed * 1103515245 + 12345) & 0x7fffffff; return seed >> 16; };
        const nsym = 6, mots = new Uint8Array(nsym * NPAY);
        for (let i = 0; i < mots.length; i++) { mots[i] = rnd() & 3; }
        const r = chaine(mots, nsym);
        // FFT flottante de référence
        let emax = 0, p = 0, e = 0;
        for (let s = 0; s < nsym; s++) {
            const c = r.cells[s], t = r.sym[s];
            // x[n] = Σ X[k] e^{+j 2π k n / N} / 2^6  (échelle = 2^-6 des 6 étages à décalage)
            for (const n of [0, 1, 7, 100, 513, 1024, 2047]) {
                let ar = 0, ai = 0;
                for (let k = 0; k < NFFT; k++) {
                    const a = 2 * Math.PI * k * n / NFFT, cs = Math.cos(a), sn = Math.sin(a);
                    ar += c.bins[0][k] * cs - c.bins[1][k] * sn; ai += c.bins[0][k] * sn + c.bins[1][k] * cs;
                }
                ar /= 64; ai /= 64;
                e += (t.re[n] - ar) ** 2 + (t.im[n] - ai) ** 2; p += ar * ar + ai * ai;
                emax = Math.max(emax, Math.abs(t.re[n] - ar), Math.abs(t.im[n] - ai));
            }
        }
        let sg = 0, cnt = 0;
        for (const t of r.sym) { for (let n = 0; n < NFFT; n++) { sg += t.re[n] ** 2 + t.im[n] ** 2; cnt++; } }
        console.log('H : ' + H.length + ' valeurs, H[0..7] = ' + H.slice(0, 8).join(' ') + ', max ' + Math.max(...H));
        console.log('TPS trame 0 : ' + Array.from(TPS[0]).join(''));
        console.log('TPS trame 1 : ' + Array.from(TPS[1]).join(''));
        console.log('FFT : écart max ' + emax.toFixed(2) + ', rapport signal sur erreur ' + (10 * Math.log10(p / e)).toFixed(1) + ' dB');
        console.log('FFT : sigma par composante ' + Math.sqrt(sg / cnt / 2).toFixed(1) + ', max interne ' + r.bilan.max + ', saturations ' + r.bilan.sat);
        const fl = filtre(Int32Array.from(r.flux.re), Int32Array.from(r.flux.im));
        let mv = 0, sv = 0;
        for (let i = 0; i < fl.vr.length; i++) { mv = Math.max(mv, Math.abs(fl.vr[i])); sv += fl.vr[i] ** 2; }
        console.log('filtre : ' + fl.vr.length + ' échantillons à 80 MS/s, sigma I ' + Math.sqrt(sv / fl.vr.length).toFixed(1) + ', crête ' + mv);
        // somme de chaque phase
        console.log('coefficients : somme par phase ' + HI.slice(0, 4).map(r => r.reduce((a, b) => a + b, 0)).join(' ') + ', crête ' + Math.max(...HI.flat()));
    }
}
