/*
================================================================================
  Nom        : sdm.js
  Projet     : JPEG2DVB, portage FPGA (émetteur DVB-S 23 cm)
  Objet      : référence au bit près de la sortie sigma-delta (cahier des charges
               § 5.4, point P3) : I/Q 16 bits à 80 MS/s (.cs16 de l'étape 14) →
               interpolation × 8 (CIC d'ordre 3) → modulateur sigma-delta 1 bit
               d'ordre 3 par voie à 640 Mbit/s ; écrit le flux de bits de
               référence et contrôle le spectre (rapport signal sur bruit en
               bande, bruit hors bande, marge de stabilité)
  Auteur     : Eric PERRET
  Date       : 2026-10-19
  Version    : 1.1
  Plateforme : Node.js, modules intégrés seulement
  Usage      : node sdm.js                  → iq.cs16 → sd_iq.bin
               node sdm.js ENTREE.cs16 SORTIE.bin
  Licence    : CC BY-NC 4.0
  Historique : 1.0  2026-10-19  création
               1.1  2026-10-19  bornage des états une fois par groupe de 8 bits (fin
                     de cycle à 80 MHz, comme le VHDL déroulé) ; flux inchangé

  Arithmétique (entière, identique au VHDL) :
    CIC × 8, ordre 3 : 3 peignes à 80 MS/s, insertion de 7 zéros, 3 intégrateurs
      à 640 MS/s ; gain 8² = 64 ; sortie sur 22 bits signés.
    Sigma-delta CIFB d'ordre 3, pleine échelle FS = 2²¹, sortie s = +1 si x3 ≥ 0 :
      x3 ← x3 + x2 − s·FS
      x2 ← x2 + x1 − s·3FS/8
      x1 ← x1 + (y >> 5) − s·FS/16     (y : sortie du CIC ; >> 5 = ÷ 2 puis ÷ 16)
      s se lit sur l'ancien x3 ; après chaque groupe de 8 bits (un échantillon
      d'entrée), chaque état est borné à ±(2²³ − 1) (24 bits signés).
    Bit émis : 1 pour s = +1, 0 pour s = −1.
  Format de SORTIE : pour chaque échantillon d'entrée, un octet I puis un octet
    Q ; le bit 7 est le premier bit émis (8 bits = 8 instants à 640 MHz).
================================================================================
*/
'use strict';
const fs = require('fs'), path = require('path');

const R = 8;                                   // facteur d'interpolation
const FS = 1 << 21;                            // pleine échelle du sigma-delta
const A1 = FS / 16, A2 = 3 * FS / 8, A3 = FS;  // coefficients CIFB × FS
const SH = 5;                                  // y >> 5 : ÷ 2 (marge de stabilité) et ÷ 16 (a1)
const XMAX = (1 << 23) - 1;                    // bornes des états (24 bits signés)
const FH = 80e6 * R;                           // débit binaire par voie
const BANDE = 6.75e6;                          // demi-bande occupée (10 MS/s, α = 0,35)

const entree = process.argv[2] || path.join(__dirname, 'iq.cs16');
const sortie = process.argv[3] || path.join(__dirname, 'sd_iq.bin');

/* lireCs16 — E : fichier .cs16 (I, Q entiers 16 bits petit-boutistes) → S : voies I et Q */
function lireCs16(f) {
    const b = fs.readFileSync(f), n = b.length >> 2, I = new Int32Array(n), Q = new Int32Array(n);
    for (let k = 0; k < n; k++) { I[k] = b.readInt16LE(4 * k); Q[k] = b.readInt16LE(4 * k + 2); }
    return { I: I, Q: Q };
}

/* cic — E : voie à 80 MS/s → T : 3 peignes, insertion de zéros, 3 intégrateurs
   → S : voie à 640 MS/s, gain 64 */
function cic(x) {
    const y = new Int32Array(x.length * R), p = [0, 0, 0];
    let g0 = 0, g1 = 0, g2 = 0;
    for (let n = 0; n < x.length; n++) {
        let v = x[n];
        for (let k = 0; k < 3; k++) { const t = v - p[k]; p[k] = v; v = t; }
        for (let r = 0; r < R; r++) {
            g0 += (r === 0 ? v : 0); g1 += g0; g2 += g1;
            y[n * R + r] = g2;
        }
    }
    return y;
}

/* sdm — E : voie à 640 MS/s → T : boucle CIFB d'ordre 3, états bornés en fin
   de groupe de 8 → S : bits
   (+1 / −1), maxima des états, nombre de bornages */
function sdm(y) {
    const v = new Int8Array(y.length), m = [0, 0, 0];
    let x1 = 0, x2 = 0, x3 = 0, bornes = 0;
    const borne = z => { if (z > XMAX) { bornes++; return XMAX; } if (z < -XMAX) { bornes++; return -XMAX; } return z; };
    for (let n = 0; n < y.length; n++) {
        const s = x3 >= 0 ? 1 : -1;
        v[n] = s;
        const n3 = x3 + x2 - s * A3, n2 = x2 + x1 - s * A2, n1 = x1 + (y[n] >> SH) - s * A1;
        x3 = n3; x2 = n2; x1 = n1;
        if (n % R === R - 1) { x3 = borne(x3); x2 = borne(x2); x1 = borne(x1); }
        m[0] = Math.max(m[0], Math.abs(x1)); m[1] = Math.max(m[1], Math.abs(x2)); m[2] = Math.max(m[2], Math.abs(x3));
    }
    return { v: v, m: m, bornes: bornes };
}

/* ecrire — E : bits I et Q → T : 8 bits par octet, premier bit en poids fort,
   I puis Q → S : fichier de référence */
function ecrire(f, vi, vq) {
    const n = vi.length / R, b = Buffer.alloc(2 * n);
    for (let k = 0; k < n; k++) {
        let oi = 0, oq = 0;
        for (let r = 0; r < R; r++) { oi = (oi << 1) | (vi[k * R + r] > 0 ? 1 : 0); oq = (oq << 1) | (vq[k * R + r] > 0 ? 1 : 0); }
        b[2 * k] = oi; b[2 * k + 1] = oq;
    }
    fs.writeFileSync(f, b);
}

/* fft — E : parties réelle et imaginaire (longueur 2^k) → S : transformée sur place */
function fft(re, im) {
    const n = re.length;
    for (let i = 1, j = 0; i < n; i++) {
        let b = n >> 1;
        for (; j & b; b >>= 1) { j ^= b; }
        j ^= b;
        if (i < j) { let t = re[i]; re[i] = re[j]; re[j] = t; t = im[i]; im[i] = im[j]; im[j] = t; }
    }
    for (let len = 2; len <= n; len <<= 1) {
        const a = -2 * Math.PI / len, wr = Math.cos(a), wi = Math.sin(a);
        for (let i = 0; i < n; i += len) {
            let cr = 1, ci = 0;
            for (let j = 0; j < len / 2; j++) {
                const p = i + j, q = p + len / 2;
                const tr = re[q] * cr - im[q] * ci, ti = re[q] * ci + im[q] * cr;
                re[q] = re[p] - tr; im[q] = im[p] - ti; re[p] += tr; im[p] += ti;
                const t = cr * wr - ci * wi; ci = cr * wi + ci * wr; cr = t;
            }
        }
    }
}

/* spectre — E : bits I/Q, entrée I/Q interpolée → T : FFT de 2²⁰ points du
   signal complexe I + jQ ; gain complexe et retard ajustés dans la bande ±6,75 MHz
   → S : rapport signal sur bruit en bande, densité hors bande relative */
function spectre(vi, vq, yi, yq) {
    const L = 1 << 20, kb = Math.floor(BANDE / FH * L);
    const ar = new Float64Array(L), ai = new Float64Array(L), br = new Float64Array(L), bi = new Float64Array(L);
    for (let n = 0; n < L; n++) { ar[n] = vi[n]; ai[n] = vq[n]; br[n] = yi[n]; bi[n] = yq[n]; }
    fft(ar, ai); fft(br, bi);
    let snr = -Infinity, retard = 0;
    for (let d = 0; d < 8; d++) {
        let xr = 0, xi = 0, yy = 0, xx = 0;
        for (let k = -kb; k <= kb; k++) {
            const kk = (k + L) % L, w = -2 * Math.PI * k * d / L, c = Math.cos(w), s = Math.sin(w);
            const ur = br[kk] * c - bi[kk] * s, ui = br[kk] * s + bi[kk] * c;
            xr += ar[kk] * ur + ai[kk] * ui; xi += ai[kk] * ur - ar[kk] * ui;
            yy += ur * ur + ui * ui; xx += ar[kk] * ar[kk] + ai[kk] * ai[kk];
        }
        const g2 = (xr * xr + xi * xi) / yy, r = 10 * Math.log10(g2 / (xx - g2));
        if (r > snr) { snr = r; retard = d; }
    }
    const dens = f => {
        const k0 = Math.round(f / FH * L);
        let s = 0;
        for (let k = k0 - 64; k <= k0 + 64; k++) { const kk = (k + L) % L; s += ar[kk] * ar[kk] + ai[kk] * ai[kk]; }
        return s / 129;
    };
    const d0 = dens(0);
    return { snr: snr, retard: retard, hb: [20e6, 50e6, 100e6, 200e6, 300e6].map(f => [f, 10 * Math.log10(dens(f) / d0)]) };
}

/* cicReponse — E : fréquence → S : gain du CIC relatif au continu (dB) */
function cicReponse(f) {
    const x = Math.PI * f / FH;
    return 20 * 3 * Math.log10(Math.abs(Math.sin(R * x) / (R * Math.sin(x))));
}

/* stabilite — E : coefficients → T : sinus de 1 MHz d'amplitude croissante sur
   l'entrée du sigma-delta → S : amplitude maximale stable (fraction de FS) */
function stabilite() {
    let ok = 0;
    for (let a = 0.05; a <= 1.0001; a += 0.05) {
        let x1 = 0, x2 = 0, x3 = 0, m = 0;
        for (let n = 0; n < 400000; n++) {
            const s = x3 >= 0 ? 1 : -1, u = Math.round(a * FS * Math.sin(2 * Math.PI * n * 1e6 / FH)) * 2;
            const n3 = x3 + x2 - s * A3, n2 = x2 + x1 - s * A2, n1 = x1 + (u >> SH) - s * A1;
            x3 = n3; x2 = n2; x1 = n1; m = Math.max(m, Math.abs(x3));
        }
        if (m < 4 * FS) { ok = a; } else { break; }
    }
    return ok;
}

// ---------------------------------------------------------------------------
const e = lireCs16(entree);
const yi = cic(e.I), yq = cic(e.Q);
let pe = 0, py = 0;
for (let n = 0; n < e.I.length; n++) { pe = Math.max(pe, Math.abs(e.I[n]), Math.abs(e.Q[n])); }
for (let n = 0; n < yi.length; n++) { py = Math.max(py, Math.abs(yi[n]), Math.abs(yq[n])); }
const si = sdm(yi), sq = sdm(yq);
ecrire(sortie, si.v, sq.v);
const sp = spectre(si.v, sq.v, yi, yq);
const fr = (v, d) => v.toFixed(d).replace('.', ',');

console.log('entrée   : ' + path.basename(entree) + ', ' + e.I.length + ' échantillons I/Q à 80 MS/s, crête ' + pe);
console.log('CIC × 8  : crête ' + py + ' (' + fr(Math.log2(py + 1) + 1, 1) + ' bits signés), atténuation à 5 MHz ' + fr(cicReponse(5e6), 2) +
    ' dB, à 6,75 MHz ' + fr(cicReponse(BANDE), 2) + ' dB ; image à 80 − 6,75 MHz ' + fr(cicReponse(80e6 - BANDE), 1) + ' dB');
console.log('entrée du sigma-delta : crête ' + fr((py >> 1) / FS, 3) + ' FS ; stable jusqu\'à ' + fr(stabilite(), 2) + ' FS (sinus 1 MHz)');
console.log('états    : |x1| ≤ ' + fr(Math.max(si.m[0], sq.m[0]) / FS, 2) + ' FS, |x2| ≤ ' + fr(Math.max(si.m[1], sq.m[1]) / FS, 2) +
    ' FS, |x3| ≤ ' + fr(Math.max(si.m[2], sq.m[2]) / FS, 2) + ' FS ; bornages : ' + (si.bornes + sq.bornes));
console.log('spectre  : rapport signal sur bruit dans ±6,75 MHz ' + fr(sp.snr, 1) + ' dB (retard ' + sp.retard + ' bits)');
console.log('hors bande (densité relative au centre) : ' + sp.hb.map(h => fr(h[0] / 1e6, 0) + ' MHz ' + fr(h[1], 1) + ' dB').join(', '));
console.log('sortie   : ' + path.basename(sortie) + ', ' + fs.statSync(sortie).size + ' octets (I, Q : 8 bits par échantillon, ' + FH / 1e6 + ' Mbit/s par voie)');
