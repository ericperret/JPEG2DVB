<!--
  Nom        : README.md
  Projet     : JPEG2DVB, portage FPGA (émetteur DVB-S 23 cm)
  Objet      : rôle de chaque fichier du dossier fpga_test/ (bancs de test du VHDL)
  Auteur     : Eric PERRET
  Date       : 2026-10-19
  Version    : 1.3
  Licence    : CC BY-NC 4.0
  Historique : 1.0  2026-10-19  création
               1.1  2026-10-19  banc rc ; état mis à jour (régulation TM5 vérifiée au bit près)
               1.2  2026-10-19  sdm.js et sd_iq.bin : référence de la sortie sigma-delta
               1.3  2026-10-19  sdm.js 2.0 : entrée par les symboles QPSK, SRRC à 640 MS/s par tables
-->

# fpga_test — références et outils des bancs de test VHDL

Le VHDL est dans `../vhdl/` : `jpeg2dvb_fpga.vhd` (modules) et `jpeg2dvb_fpga_tb.vhd` (bancs). Ce dossier contient ce que les bancs lisent, et les outils qui l'ont produit à partir des pages JPEG2DVB. Les tests se lancent d'ici : `./run_tests.sh` (tous les bancs) ou `./run_tests.sh nom` (un seul banc).

## Outils

| Fichier | Rôle |
|---|---|
| `run_tests.sh` | Analyse les deux fichiers VHDL, lance chaque banc GHDL (OK / ECHEC au bit près), puis vérifie la synthétisabilité des modules (`ghdl --synth`) |
| `refs.js` | Extrait les références de la chaîne arrière (étapes 08 à 14) d'un dossier de sorties JPEG2DVB ; réécrit le paquetage `srrc_coef_pkg` |
| `refs_video.js` | Extrait les références vidéo (étapes 01 à 08) d'un dossier de sorties JPEG2DVB : DCT entière, régulation TM5 |
| `gen_vlc.js` | Lit les tables VLC de `page05-rle-huffman.html` et réécrit le paquetage `vlc_tab_pkg` |
| `mire.js` | Dessine la mire 16 couleurs : `mire.png` (entrée de la page 01) et paquetage `mire_pkg` |
| `sdm.js` | Référence de la sortie sigma-delta (cahier des charges § 5.4) : symboles de `qpsk.bin` → SRRC à 640 MS/s par tables → sigma-delta 1 bit d'ordre 3 par voie à 640 Mbit/s ; vérifie que la formulation par anticipation du VHDL donne le même flux que la boucle pas à pas ; écrit `sd_iq.bin`, réécrit le paquetage `sdm_coef_pkg` et affiche le contrôle spectral. `node sdm.js` ou `node sdm.js ENTREE.bin N SORTIE.bin` |
| `fusion.js` | Module commun aux trois générateurs : met un paquetage généré au format du fichier fusionné et le remplace entre ses balises `-- >>>` / `-- <<<` |

Ces outils ne servent que si une page JPEG2DVB change : les références doivent alors suivre la page.

## Images sources

| Fichier | Rôle |
|---|---|
| `dur.png` | Image de test des références vidéo (3 images, carré mobile) |
| `mire.png` | Mire du FPGA, à charger en page 01 pour les références de bout en bout |

## Références — chaîne arrière (un extrait d'une seconde de flux, photo, FEC 1/2, α = 0,35)

| Fichier | Étape | Contenu | Banc |
|---|---|---|---|
| `ts.bin` | 08 | 64 paquets TS de 188 octets | `prbs`, `chaine` |
| `rand.bin` | 09 | après dispersion d'énergie | `prbs`, `rs` |
| `rs.bin` | 10 | paquets RS de 204 octets | `rs`, `inter` |
| `inter.bin` | 11 | après entrelacement | `inter`, `conv*` |
| `conv.bin` | 12 | bits codés, FEC 1/2 | `conv12`, `qpsk` |
| `conv23.bin` … `conv78.bin` | 12 | bits codés, FEC 2/3, 3/4, 5/6, 7/8 | `conv23` … `conv78` |
| `qpsk.bin` | 13 | symboles QPSK | `qpsk`, `srrc` |
| `iq.cs16` | 14 | 160 000 échantillons I/Q, entiers 16 bits | `srrc`, `chaine` |
| `sd_iq.bin` | 13 → sigma-delta | bits sigma-delta des 20 000 premiers symboles de `qpsk.bin` : un octet I puis un octet Q par cycle de 80 MHz, bit 7 émis en premier (1 280 000 bits par voie) | `sdm` |

## Références — vidéo (3 images de `dur.png`, DCT entière, régulation TM5)

| Fichier | Étape | Contenu | Banc |
|---|---|---|---|
| `mb0.bin` | 01 | macroblocs de l'image 0 (octets) | `dct` |
| `dct0.bin` | 02 | coefficients DCT de l'image 0 (int16) | `dct`, `quant*` |
| `q0.bin` | 03 | coefficients quantifiés, code de chaque rangée | `quant8`, `zigzag` |
| `q0_c1.bin`, `q0_c31.bin` | 03 | quantifiés aux codes 1 et 31 (bornes) | `quant1`, `quant31` |
| `qcode.bin` | 03 | quantiser_scale_code de chaque slice (54 octets) | `quant8`, `es`, `rc` |
| `zz0.bin` | 04 | vecteurs zigzag | `zigzag`, `vlc` |
| `vlc.bin`, `mbbits.bin` | 05 | bits VLC bout à bout, longueur de chaque macrobloc | `vlc`, `es`, `rc` (`mbbits.bin`) |
| `es.bin`, `es_au.bin` | 06 | flux élémentaire, début de chaque image | `es`, `ts` |
| `ts_v.bin` | 08 | Transport Stream de ces 3 images | `ts` |

## Références — de bout en bout (mire animée, 3 images)

| Fichier | Étape | Contenu | Banc |
|---|---|---|---|
| `mire_mb.bin` | 01 | macroblocs de 2 images de la mire | `mire` |
| `mire_ts.bin` | 08 | TS produit depuis la mire | `video` |
| `mire_iq.cs16` | 14 | 160 000 échantillons I/Q depuis la mire (les 12 premiers paquets TS) | `emetteur` |

## État au 2026-10-19

Toutes les références sont à jour : DCT entière et régulation TM5 de la page 03 (3.x). Les 23 bancs passent au bit près, dont `rc` (codes de `rate_ctrl` comparés à `qcode.bin`), et les 11 modules passent `ghdl --synth` sans verrou.

`mire_iq.cs16` ne couvre que les 12 premiers paquets TS, identiques avant et après la régulation : la régulation se vérifie par les bancs `quant8`, `es`, `rc` et `video`.
