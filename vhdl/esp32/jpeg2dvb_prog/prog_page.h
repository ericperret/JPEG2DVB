/*
 * ══════════════════════════════════════════════════════════════
 *  Nom      : prog_page.h
 *  Projet   : JPEG2DVB — chantier 2 : programmation du PIC et du FPGA depuis l'ESP32
 *  Objet    : page web embarquée (HTML/CSS/JavaScript, sans ressource externe)
 *  Auteur   : Eric PERRET
 *  Date     : 2026-11-21
 *  Version  : 1.0.0
 * ══════════════════════════════════════════════════════════════
 */
#pragma once

static const char PAGE_PROG[] PROGMEM = R"PAGEPROG(<!DOCTYPE html>
<!--
  Nom      : jpeg2dvb_prog (page servie par le CoreS3, prog_page.h)
  Projet   : JPEG2DVB — chantier 2 : programmation du PIC et du FPGA
  Objet    : état, réglage de la PLL (PIC16F18323), programmation du FPGA (JTAG-DirectC)
  Auteur   : Eric PERRET
  Date     : 2026-11-21
  Version  : 1.0.0
-->
<html lang="fr">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>JPEG2DVB — programmation</title>
<style>
  :root { --fond:#f4f5f7; --carte:#fff; --texte:#1d2330; --doux:#5f6878; --bord:#d9dde4;
          --accent:#1f5fbf; --ok:#1e8a3c; --alerte:#c77700; --erreur:#c62828; }
  * { box-sizing:border-box; }
  body { margin:0; font:15px/1.45 system-ui, -apple-system, "Segoe UI", Roboto, sans-serif;
         background:var(--fond); color:var(--texte); }
  header { background:#16233a; color:#fff; padding:12px 16px; }
  header h1 { margin:0; font-size:18px; font-weight:600; }
  header small { color:#aab6cc; }
  main { max-width:880px; margin:0 auto; padding:12px; display:grid; gap:12px; }
  section { background:var(--carte); border:1px solid var(--bord); border-radius:8px; padding:12px 14px; }
  h2 { margin:0 0 10px; font-size:16px; }
  table { border-collapse:collapse; width:100%; }
  td { padding:3px 6px; vertical-align:top; }
  td:first-child { color:var(--doux); width:40%; }
  .mono { font-family:ui-monospace, Consolas, "DejaVu Sans Mono", monospace; }
  .ok { color:var(--ok); font-weight:600; } .alerte { color:var(--alerte); font-weight:600; }
  .erreur { color:var(--erreur); font-weight:600; }
  .ligne { display:flex; flex-wrap:wrap; gap:8px; align-items:center; margin:8px 0; }
  input[type=text] { font-size:16px; padding:6px 8px; width:9em; border:1px solid var(--bord); border-radius:6px; }
  input.faux { border-color:var(--erreur); background:#fff3f3; }
  button { font-size:15px; padding:7px 14px; border-radius:6px; border:1px solid var(--accent);
           background:var(--accent); color:#fff; cursor:pointer; }
  button.second { background:#fff; color:var(--accent); }
  button.danger { background:var(--erreur); border-color:var(--erreur); }
  button:disabled { opacity:.45; cursor:not-allowed; }
  .barre { height:14px; background:#e6e9ee; border-radius:7px; overflow:hidden; flex:1; min-width:160px; }
  .barre > div { height:100%; width:0; background:var(--accent); transition:width .3s; }
  .regs td { font-family:ui-monospace, Consolas, monospace; }
  pre { margin:0; max-height:320px; overflow:auto; background:#0f1520; color:#d4dbe6;
        padding:8px; border-radius:6px; font-size:12.5px; white-space:pre-wrap; }
  .note { color:var(--doux); font-size:13px; }
</style>
</head>
<body>
<header>
  <h1>JPEG2DVB — programmation PIC et FPGA</h1>
  <small id="entete">connexion…</small>
</header>
<main>

<section>
  <h2>État</h2>
  <table>
    <tr><td>DEVID du PIC (dernière programmation)</td><td id="e_devid" class="mono">—</td></tr>
    <tr><td>PLL (LD)</td><td id="e_ld">—</td></tr>
    <tr><td>FPGA (dernière identification)</td><td id="e_fpga" class="mono">—</td></tr>
    <tr><td>Espace libre FFat</td><td id="e_ffat">—</td></tr>
    <tr><td>Dernière action</td><td id="e_action">—</td></tr>
    <tr><td>Résultat</td><td id="e_res">—</td></tr>
  </table>
  <div class="ligne"><div class="barre"><div id="barre"></div></div><span id="e_phase" class="note"></span></div>
</section>

<section>
  <h2>PLL (ADF4351 programmé par le PIC)</h2>
  <div class="ligne">
    <label for="freq">Fréquence (MHz)</label>
    <input type="text" id="freq" inputmode="decimal" autocomplete="off" placeholder="1250,0">
    <button id="b_pic">Écrire dans le PIC</button>
  </div>
  <div class="note">950,0 à 2150,0 MHz, par pas de 0,5 MHz. Référence 50 MHz, PFD 25 MHz, MOD 25.</div>
  <div id="pll_msg" class="note"></div>
  <table class="regs" id="pll_regs" style="margin-top:8px">
    <tr><td>Diviseur de sortie</td><td id="p_div">—</td></tr>
    <tr><td>VCO</td><td id="p_vco">—</td></tr>
    <tr><td>INT / FRAC / MOD</td><td id="p_nf">—</td></tr>
    <tr><td>R0</td><td id="p_r0">—</td></tr>
    <tr><td>R1</td><td id="p_r1">—</td></tr>
    <tr><td>R2</td><td id="p_r2">—</td></tr>
    <tr><td>R3</td><td id="p_r3">—</td></tr>
    <tr><td>R4</td><td id="p_r4">—</td></tr>
    <tr><td>R5</td><td id="p_r5">—</td></tr>
  </table>
</section>

<section>
  <h2>FPGA (PolarFire, JTAG-DirectC)</h2>
  <table>
    <tr><td>Fichier stocké (/fpga.dat)</td><td id="f_dat" class="mono">—</td></tr>
  </table>
  <div class="ligne">
    <input type="file" id="fichier" accept=".dat">
    <button id="b_envoi" class="second">Envoyer</button>
  </div>
  <div class="ligne"><div class="barre"><div id="barre_envoi"></div></div><span id="f_envoi" class="note"></span></div>
  <div class="ligne">
    <button id="b_id">Identifier</button>
    <button id="b_prog" class="danger">Programmer et vérifier</button>
  </div>
  <div class="note">Fichier DAT exporté par Libero (Export Bitstream, format DAT).
    La sortie HF est coupée pendant toute l'opération (PIC tenu en reset).</div>
</section>

<section>
  <h2>Journal</h2>
  <pre id="journal"></pre>
  <div class="ligne"><button id="b_vider" class="second">Effacer l'affichage</button></div>
</section>

</main>
<script>
"use strict";
const $ = (id) => document.getElementById(id);
let E = null;               // dernier état reçu
let jSuivant = 0;           // prochaine ligne du journal à demander
let envoiActif = false;
let tempo = null;

function octets(n) {
  if (n >= 1048576) return (n / 1048576).toFixed(2).replace('.', ',') + ' Mo';
  if (n >= 1024) return (n / 1024).toFixed(1).replace('.', ',') + ' ko';
  return n + ' o';
}

function freqValide(t) {
  const s = t.trim();
  if (!/^\d{1,4}([.,](0|5)0*)?$/.test(s)) return null;
  const v = parseFloat(s.replace(',', '.'));
  if (v < 950 || v > 2150) return null;
  return s;
}

async function requete(url, corps) {
  const opt = corps === undefined ? {} : {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams(corps || {}).toString()
  };
  const r = await fetch(url, opt);
  let j = null;
  try { j = await r.json(); } catch (e) { j = { ok: false, erreur: 'réponse illisible' }; }
  if (!r.ok && j.ok === undefined) j.ok = false;
  return j;
}

function afficherPll(j) {
  if (!j || j.ok === false) {
    ['p_div', 'p_vco', 'p_nf', 'p_r0', 'p_r1', 'p_r2', 'p_r3', 'p_r4', 'p_r5'].forEach(id => $(id).textContent = '—');
    return;
  }
  $('p_div').textContent = '÷' + j.diviseur;
  $('p_vco').textContent = j.vco + ' MHz';
  $('p_nf').textContent = j.int + ' / ' + j.frac + ' / ' + j.mod;
  for (let i = 0; i < 6; i++) $('p_r' + i).textContent = j.r[i];
}

async function calculer() {
  const s = freqValide($('freq').value);
  $('freq').classList.toggle('faux', s === null);
  if (s === null) {
    $('pll_msg').innerHTML = '<span class="erreur">Fréquence refusée : 950,0 à 2150,0 MHz, par pas de 0,5 MHz</span>';
    afficherPll(null);
    majBoutons();
    return;
  }
  const j = await requete('/pll', { frequence: s, ecrire: '0' });
  $('pll_msg').innerHTML = j.ok ? '' : '<span class="erreur">' + (j.erreur || 'erreur') + '</span>';
  afficherPll(j);
  majBoutons();
}

async function ecrirePic() {
  const s = freqValide($('freq').value);
  if (s === null) { calculer(); return; }
  const j = await requete('/pll', { frequence: s, ecrire: '1' });
  if (!j.ok) $('pll_msg').innerHTML = '<span class="erreur">' + (j.erreur || 'erreur') + '</span>';
  else { $('pll_msg').textContent = 'Programmation du PIC lancée à ' + j.frequence + ' MHz'; afficherPll(j); }
  etat();
}

function envoyer() {
  const f = $('fichier').files[0];
  if (!f) { $('f_envoi').innerHTML = '<span class="erreur">Choisir un fichier .dat</span>'; return; }
  if (!/\.dat$/i.test(f.name)) { $('f_envoi').innerHTML = '<span class="erreur">Le fichier doit être un .dat</span>'; return; }
  if (E && f.size > E.ffat_libre) {
    $('f_envoi').innerHTML = '<span class="erreur">Espace FFat insuffisant (' + octets(E.ffat_libre) + ' libres)</span>';
    return;
  }
  const fd = new FormData();
  fd.append('dat', f, f.name);
  const x = new XMLHttpRequest();
  envoiActif = true; majBoutons();
  x.upload.onprogress = (ev) => {
    if (ev.lengthComputable) {
      const p = Math.round(ev.loaded * 100 / ev.total);
      $('barre_envoi').style.width = p + '%';
      $('f_envoi').textContent = 'Envoi ' + p + ' % (' + octets(ev.loaded) + ' / ' + octets(ev.total) + ')';
    }
  };
  x.onload = () => {
    envoiActif = false;
    let j = {};
    try { j = JSON.parse(x.responseText); } catch (e) { j = { ok: false, erreur: 'réponse illisible' }; }
    $('f_envoi').innerHTML = j.ok ? '<span class="ok">Enregistré : ' + octets(j.taille) + ', CRC32 ' + j.crc + '</span>'
                                  : '<span class="erreur">Échec : ' + (j.erreur || x.status) + '</span>';
    if (j.ok) $('barre_envoi').style.width = '100%';
    etat();
  };
  x.onerror = () => {
    envoiActif = false;
    $('f_envoi').innerHTML = '<span class="erreur">Échec de la liaison pendant l\'envoi</span>';
    etat();
  };
  x.open('POST', '/fpga/envoi');
  x.send(fd);
}

async function fpga(action) {
  if (action === 'prog') {
    const t = E && E.dat_present ? octets(E.dat_taille) + ', CRC32 ' + E.dat_crc : '?';
    if (!confirm('Programmer le FPGA avec /fpga.dat (' + t + ') ?\n\n' +
                 'Le FPGA est EFFACÉ au départ, puis programmé et vérifié.\n' +
                 'La sortie HF est coupée pendant toute l\'opération.')) return;
  }
  const j = await requete('/fpga/' + action, {});
  if (!j.ok) $('e_res').innerHTML = '<span class="erreur">' + (j.erreur || 'erreur') + '</span>';
  etat();
}

function majBoutons() {
  const occ = envoiActif || !E || E.occupe;
  $('b_pic').disabled = occ || freqValide($('freq').value) === null;
  $('b_envoi').disabled = occ;
  $('b_id').disabled = occ || !E.dat_present;
  $('b_prog').disabled = occ || !E.dat_present;
}

async function etat() {
  let j;
  try { j = await requete('/etat'); } catch (e) { $('entete').textContent = 'liaison perdue'; return; }
  const premier = (E === null);
  E = j;
  $('entete').textContent = j.ssid + ' — ' + j.ip + ' — firmware ' + j.version;
  $('e_devid').innerHTML = j.pic_devid === null ? '—'
    : (j.pic_devid === j.pic_devid_attendu ? '<span class="ok">' : '<span class="erreur">') +
      j.pic_devid + 'h</span> (rév. ' + j.pic_revid + 'h, attendu ' + j.pic_devid_attendu + 'h)';
  $('e_ld').innerHTML = j.ld ? '<span class="ok">verrouillée</span>' : '<span class="erreur">non verrouillée</span>';
  $('e_fpga').textContent = j.fpga_idcode === null ? '—' : j.fpga_idcode + 'h — ' + j.fpga_nom;
  $('e_ffat').textContent = octets(j.ffat_libre) + ' sur ' + octets(j.ffat_total);
  $('e_action').textContent = j.action || '—';
  $('e_res').innerHTML = j.resultat ? '<span class="' + (j.qualite || '') + '">' + j.resultat.replace(/</g, '&lt;') + '</span>' : '—';
  $('barre').style.width = (j.occupe ? j.progression : 0) + '%';
  $('e_phase').textContent = j.occupe ? (j.phase + ' — ' + j.progression + ' %') : '';
  $('f_dat').textContent = j.dat_present ? octets(j.dat_taille) + ' (' + j.dat_taille + ' o), CRC32 ' + j.dat_crc : 'aucun';
  if (premier && j.freq) { $('freq').value = j.freq; calculer(); }
  majBoutons();
  if (j.journal !== jSuivant) journal();
}

async function journal() {
  for (let n = 0; n < 8; n++) {
    let j;
    try { j = await requete('/journal?depuis=' + jSuivant); } catch (e) { return; }
    const p = $('journal');
    if (j.debut !== jSuivant && jSuivant !== 0) p.textContent += '[… lignes perdues …]\n';
    if (j.lignes.length) {
      const bas = p.scrollTop + p.clientHeight >= p.scrollHeight - 4;
      p.textContent += j.lignes.join('\n') + '\n';
      const l = p.textContent.split('\n');
      if (l.length > 600) p.textContent = l.slice(l.length - 600).join('\n');
      if (bas) p.scrollTop = p.scrollHeight;
    }
    jSuivant = j.suivant;
    if (j.suivant >= j.total) return;
  }
}

$('freq').addEventListener('input', () => { clearTimeout(tempo); tempo = setTimeout(calculer, 350); });
$('freq').addEventListener('keydown', (e) => { if (e.key === 'Enter' && !$('b_pic').disabled) ecrirePic(); });
$('b_pic').addEventListener('click', ecrirePic);
$('b_envoi').addEventListener('click', envoyer);
$('b_id').addEventListener('click', () => fpga('id'));
$('b_prog').addEventListener('click', () => fpga('prog'));
$('b_vider').addEventListener('click', () => { $('journal').textContent = ''; });
etat();
setInterval(() => { if (!envoiActif) etat(); }, 1000);
</script>
</body>
</html>
)PAGEPROG";
