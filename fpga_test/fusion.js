/*
================================================================================
  Nom        : fusion.js
  Projet     : JPEG2DVB, portage FPGA (émetteur DVB-S 23 cm)
  Objet      : mise en forme commune des unités VHDL rangées dans
               vhdl/jpeg2dvb_fpga.vhd : cartouche d'unité réduit à un bloc de
               description, clauses ieee remplacées par le context commun ;
               réécriture d'un paquetage généré entre ses balises
  Auteur     : Eric PERRET
  Date       : 2026-10-19
  Version    : 1.0
  Plateforme : Node.js (aucune dépendance)
  Licence    : CC BY-NC 4.0
  Usage      : module, utilisé par refs.js, gen_vlc.js et mire.js
  Historique : 1.0  2026-10-19  création
================================================================================
*/
'use strict';
const fs = require('fs'), path = require('path');

const CARTOUCHE = /^--={10,}\n([\s\S]*?)\n--={10,}\n/;
const EXCLUS = ['Nom', 'Projet', 'Auteur', 'Date', 'Version', 'Plateforme', 'Licence', 'Historique', 'Contenu'];
const IEEE = /library ieee;\n(use ieee\.[a-z_0-9]+\.all;\n)+/;

/* lireCartouche — E : texte d'une unité → T : découpe les champs « --  Clé : valeur »
   et leurs lignes de suite → S : { champs : [[clé, [lignes]]], reste } ou null */
function lireCartouche(t) {
    const m = CARTOUCHE.exec(t);
    if (!m) { return null; }
    const champs = [];
    for (const l of m[1].split('\n')) {
        const c = /^--  ([^ :][^:]*?)\s*: ?(.*)$/.exec(l);
        if (c && !/^ /.test(c[1])) { champs.push([c[1], [c[2]]]); }
        else if (champs.length) { champs[champs.length - 1][1].push(l.replace(/^--\s{0,15}/, '')); }
    }
    return { champs, reste: t.slice(m[0].length) };
}

/* normaliser — E : texte complet d'une unité (cartouche, clauses, code) →
   T : bloc de description (objet, interface, principe, paramètres), context
   commun → S : { texte, nom, objet, historique } */
function normaliser(t) {
    const c = lireCartouche(t);
    if (!c) { return { texte: t.replace(IEEE, 'context work.jpeg2dvb_ctx;\n'), nom: '', objet: '', historique: [] }; }
    const champ = k => (c.champs.find(x => x[0] === k) || [k, ['']])[1];
    const nom = champ('Nom')[0].replace('.vhd', '').trim();
    const L = '-'.repeat(80);
    let b = L + '\n-- ' + nom + ' : ' + champ('Objet').join('\n--   ') + '\n';
    for (const [k, v] of c.champs) {
        if (k === 'Objet' || EXCLUS.includes(k)) { continue; }
        b += '--   ' + k + ' : ' + v.join('\n--   ' + ' '.repeat(k.length + 3)) + '\n';
    }
    b += L + '\n';
    const historique = champ('Historique').map(l => l.trim()).filter(l => l);
    return { texte: b + c.reste.replace(IEEE, 'context work.jpeg2dvb_ctx;\n'), nom, objet: champ('Objet').join(' ').replace(/\s+/g, ' '), historique };
}

/* section — E : nom du fichier d'origine (ex. mire_pkg.vhd), texte généré →
   T : normalise et remplace le contenu entre « -- >>> nom » et « -- <<< nom »
   → S : vhdl/jpeg2dvb_fpga.vhd réécrit */
function section(nom, texte) {
    const f = path.join(__dirname, '..', 'vhdl', 'jpeg2dvb_fpga.vhd'), a = '-- >>> ' + nom + '\n', b = '-- <<< ' + nom;
    const s = fs.readFileSync(f, 'utf8'), i = s.indexOf(a), j = s.indexOf(b);
    if (i < 0 || j < i) { throw new Error('balises de ' + nom + ' absentes de ' + f); }
    fs.writeFileSync(f, s.slice(0, i + a.length) + normaliser(texte).texte.replace(/\s*$/, '\n') + s.slice(j));
}

module.exports = { lireCartouche, normaliser, section };
