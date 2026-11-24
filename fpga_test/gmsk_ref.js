/*
================================================================================
  Nom        : gmsk_ref.js
  Projet     : JPEG2DVB, mode GMSK
  Objet      : référence du modulateur GMSK (BT 0,5, h 0,5) à 80 MS/s, arithmétique
               entière identique au VHDL gmsk_mod : phase = somme de quatre termes
               q(j, phase de symbole) + cumul modulo 4 des bits plus anciens, puis
               cos/sin par le quart d'onde T_COS (2 048 points par tour), amplitude R
  Auteur     : Eric PERRET
  Date       : 2026-11-24
  Version    : 1.0
  Plateforme : Node.js, modules intégrés seulement
  Licence    : CC BY-NC 4.0
  Principe   : débit symbole Rs = 80 MHz · 27 / 440 = 54/11 MBd (une phase de symbole
               avance de 27 par cycle, modulo 440) ; impulsion de fréquence gaussienne
               BT 0,5 tronquée à 4 symboles ; phase en tours = (A + Σ b(k−j)·Q(j+u)) / 4,
               A = cumul modulo 4 des bits plus anciens (chaque bit = un quart de tour) ;
               u = phase du symbole, quantifiée sur 64 pas (centre de l'intervalle)
  Historique : 1.0  2026-11-24  création
================================================================================
*/
'use strict';
const BT = 0.5, NP = 64, NJ = 4, QMAX = 512, TOUR = 2048, R = 480;
const PAS = 27, PER = 440, MULT = 149;            // idx = (phase · 149) >> 10 (≈ 64 · phase / 440)
const AMP = 8191;

// quart d'onde du cosinus (identique à dvbt_pkg.T_COS)
const T_COS = new Int32Array(513);
for (let n = 0; n <= 512; n++) { T_COS[n] = Math.round(AMP * Math.cos(2 * Math.PI * n / TOUR)); }

// impulsion de fréquence : rectangle de largeur T convolué avec la gaussienne de BT ; Q tronquée à 4T
function tableQ() {
    const sg = Math.sqrt(Math.log(2)) / (2 * Math.PI * BT);              // en unités de T
    const M = 4096, dt = 1 / M, T0 = -2;                                    // grille fine, t de −2T à +2T
    const n = 4 * M;
    const g = new Float64Array(n);
    for (let i = 0; i < n; i++) {
        const t = T0 + (i + 0.5) * dt;
        // g(t) = ∫ de t−1/2 à t+1/2 de la gaussienne ; intégration numérique
        let s = 0; const K = 64;
        for (let k = 0; k < K; k++) { const x = t - 0.5 + (k + 0.5) / K; s += Math.exp(-x * x / (2 * sg * sg)) / (sg * Math.sqrt(2 * Math.PI)); }
        g[i] = s / K;
    }
    const c = new Float64Array(n + 1);
    for (let i = 0; i < n; i++) { c[i + 1] = c[i] + g[i] * dt; }
    const tot = c[n];
    const Q = tau => {                                                      // tau en symboles, 0 à 4
        const x = Math.min(Math.max(tau, 0), 4) * M;
        const i = Math.floor(x), f = x - i;
        const a = c[Math.min(i, n)], b = c[Math.min(i + 1, n)];
        return (a + (b - a) * f) / tot;
    };
    const t = new Int32Array(NJ * NP);
    for (let j = 0; j < NJ; j++) { for (let i = 0; i < NP; i++) { t[j * NP + i] = Math.round(QMAX * Q(j + (i + 0.5) / NP)); } }
    return { t: t, Q: Q };
}
const TQ = tableQ();

function cosq(n) {                                                          // cos(2π n / 2048), n entier
    n = ((n % TOUR) + TOUR) % TOUR;
    const q = n >> 9, r = n & 511;
    if (q === 0) { return T_COS[r]; }
    if (q === 1) { return -T_COS[512 - r]; }
    if (q === 2) { return -T_COS[r]; }
    return T_COS[512 - r];
}
// scale : E : cos ou sin (±8191) → S : valeur ×R / 8192 arrondie (R = 512 − 32 : décalages)
function scale(v) { return (v * 480 + 4096) >> 13; }

// modulation : bits[k] = ±1 (+1 : fréquence positive) → échantillons v_i, v_q à 80 MS/s ;
//   inv : voie Q inversée. Historique initial : bits = +1, A = 0.
function modulate(bits, ncycles, inv, opt) {
    opt = opt || {};
    const vi = new Int16Array(ncycles), vq = new Int16Array(ncycles), ph = new Int16Array(ncycles);
    let acc = 0, k = 0;
    let hb = [1, 1, 1, 1];                                                  // hb[j] = bit k−j
    let A = 0;
    // le premier bit entre au premier cycle (état de départ : phase de symbole 0 après l'arrivée de b0)
    hb = [bits[0], 1, 1, 1];
    for (let n = 0; n < ncycles; n++) {
        const idx = (acc * MULT) >> 10;
        let s = 512 * A;
        for (let j = 0; j < NJ; j++) { s += hb[j] * TQ.t[j * NP + idx]; }
        const p = ((s % TOUR) + TOUR) % TOUR;
        ph[n] = p;
        const cr = cosq(p), sr = cosq(p + TOUR - 512);
        vi[n] = scale(cr); vq[n] = scale(inv ? -sr : sr);     // inversion avant l'amplitude : ⌊·⌋ n'est pas symétrique
        acc += PAS;
        if (acc >= PER) {
            acc -= PER;
            A = (((A + hb[3]) % 4) + 4) % 4;
            k++;
            hb = [k < bits.length ? bits[k] : 1, hb[0], hb[1], hb[2]];
        }
    }
    return { vi: vi, vq: vq, ph: ph };
}

// forme d'onde idéale (flottante) à 80 MS/s, sans quantification : même modèle, phases exactes
function ideal(bits, ncycles) {
    const vi = new Float64Array(ncycles), vq = new Float64Array(ncycles);
    let acc = 0, k = 0, hb = [bits[0], 1, 1, 1], A = 0;
    for (let n = 0; n < ncycles; n++) {
        const u = acc / PER;
        let s = A;
        for (let j = 0; j < NJ; j++) { s += hb[j] * TQ.Q(j + u); }
        const th = 2 * Math.PI * s / 4;
        vi[n] = R * Math.cos(th); vq[n] = R * Math.sin(th);
        acc += PAS;
        if (acc >= PER) { acc -= PER; A = (((A + hb[3]) % 4) + 4) % 4; k++; hb = [k < bits.length ? bits[k] : 1, hb[0], hb[1], hb[2]]; }
    }
    return { vi: vi, vq: vq };
}

module.exports = { BT, NP, NJ, QMAX, TOUR, R, PAS, PER, MULT, T_COS, TQ, cosq, scale, modulate, ideal };

// ---- ligne de commande : node gmsk_ref.js vect NSAMPLES REP INV  →  REP/in.txt (mots X,Y) et REP/exp.txt (v_i v_q)
if (require.main === module) {
    const fs = require('fs');
    if (process.argv[2] === 'vect') {
        const N = +process.argv[3], dir = process.argv[4], inv = +(process.argv[5] || 0);
        let seed = 99; const rnd = () => { seed = (seed * 1103515245 + 12345) & 0x7fffffff; return seed >> 16; };
        const nw = Math.ceil(N * PAS / PER / 2) + 8;
        const words = Array.from({ length: nw }, () => rnd() & 3);
        const bits = []; for (const w of words) { bits.push((w >> 1) ? 1 : -1, (w & 1) ? 1 : -1); }
        const m = modulate(bits, N, inv === 1);
        fs.mkdirSync(dir, { recursive: true });
        fs.writeFileSync(dir + '/in.txt', words.join('\n') + '\n');
        let o = ''; for (let n = 0; n < N; n++) { o += m.vi[n] + ' ' + m.vq[n] + '\n'; }
        fs.writeFileSync(dir + '/exp.txt', o);
        console.log('vecteurs : ' + nw + ' mots, ' + N + ' échantillons');
    }
}
