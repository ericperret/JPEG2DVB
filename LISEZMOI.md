<!--
  Nom      : LISEZMOI.md
  Objet    : Présentation de JPEG2DVB (chaîne de transmission DVB-S pas à pas)
  Auteur   : Eric PERRET
  Date     : 2026-10-17
  Licence  : CC BY-NC 4.0
-->

# 📡 JPEG2DVB — de l'image à la modulation DVB-S

🇬🇧 [English version: README.md](README.md)

▶️ **[Page d'accueil des 15 étapes](https://ericperret.github.io/JPEG2DVB/index2.html)**

[![Licence : CC BY-NC 4.0](https://img.shields.io/badge/Licence-CC%20BY--NC%204.0-lightgrey.svg)](https://creativecommons.org/licenses/by-nc/4.0/deed.fr)

![Page 02 : DCT 8×8](captures/page02-dct.png)

Tutoriel interactif de la chaîne de télévision numérique par satellite : de la capture d'une image à la mise en forme du signal QPSK, selon MPEG-2 et DVB-S (EN 300 421). Chaque étape est une page HTML autonome qui fait les vrais calculs : elle charge le fichier produit par l'étape précédente (JSON ou binaire), le traite pas à pas avec visualisation, et enregistre son résultat pour l'étape suivante.

Aucune librairie, aucune installation. Interfaces en français.

## Les étapes

| Étape | Lancer | Traitement | Entrée → sortie | Capture |
|---|---|---|---|---|
| 00 | ▶️ [Caméra](https://ericperret.github.io/JPEG2DVB/page00-camera.html) | Capture d'une image à la webcam | webcam → image | [voir](captures/page00-camera.png) |
| 01 | ▶️ [Macroblocs](https://ericperret.github.io/JPEG2DVB/page01-image-to-macroblocs.html) | RGB → YCbCr 4:2:0, macroblocs 16×16 (4 Y + 1 Cb + 1 Cr) | image → JSON macroblocs | [voir](captures/page01-image-to-macroblocs.png) |
| 02 | ▶️ [DCT](https://ericperret.github.io/JPEG2DVB/page02-dct.html) | Centrage −128, DCT 2D 8×8 | macroblocs → coefficients | [voir](captures/page02-dct.png) |
| 03 | ▶️ [Quantification](https://ericperret.github.io/JPEG2DVB/page03-quantification.html) | Division par la matrice de quantification (pertes) | coefficients → entiers quantifiés | [voir](captures/page03-quantification.png) |
| 04 | ▶️ [Zigzag](https://ericperret.github.io/JPEG2DVB/page04-zigzag.html) | Parcours zigzag des 64 coefficients | blocs → vecteurs de 64 | [voir](captures/page04-zigzag.png) |
| 05 | ▶️ [RLE + Huffman](https://ericperret.github.io/JPEG2DVB/page05-rle-huffman.html) | Paires (run, level), codes à longueur variable | vecteurs → bitstreams | [voir](captures/page05-rle-huffman.png) |
| 06 | ▶️ [Elementary Stream](https://ericperret.github.io/JPEG2DVB/page06-elementary-stream.html) | Sequence, GOP, Picture headers, slices MPEG-2 | bitstreams → fichier .es | [voir](captures/page06-elementary-stream.png) |
| 07 | ▶️ [PES](https://ericperret.github.io/JPEG2DVB/page07-pes.html) | Paquets PES, horodatage PTS | ES → PES | [voir](captures/page07-pes.png) |
| 08 | ▶️ [Transport Stream](https://ericperret.github.io/JPEG2DVB/page08-ts.html) | Paquets de 188 octets, tables PAT et PMT | PES → fichier .ts lisible | [voir](captures/page08-ts.png) |
| 09 | ▶️ [PRBS](https://ericperret.github.io/JPEG2DVB/page09-prbs.html) | Dispersion d'énergie, polynôme 1 + X¹⁴ + X¹⁵, super-trame de 8 paquets | TS → TS randomisé | [voir](captures/page09-prbs.png) |
| 10 | ▶️ [Reed-Solomon](https://ericperret.github.io/JPEG2DVB/page10-reed-solomon.html) | RS(204,188) raccourci de RS(255,239), GF(2⁸) 0x11D, 8 octets corrigibles | 188 → 204 octets | [voir](captures/page10-reed-solomon.png) |
| 11 | ▶️ [Entrelacement](https://ericperret.github.io/JPEG2DVB/page11-interleaving.html) | Entrelaceur convolutif de Forney, I = 12, M = 17 | blocs RS → flux entrelacé | [voir](captures/page11-interleaving.png) |
| 12 | ▶️ [Codeur convolutif](https://ericperret.github.io/JPEG2DVB/page12-convolutional_1.html) | K = 7, taux 1/2, G1 = 171₈, G2 = 133₈, poinçonnage optionnel | flux → bits codés | [voir](captures/page12-convolutional_1.png) |
| 13 | ▶️ [QPSK](https://ericperret.github.io/JPEG2DVB/page13-qpsk.html) | 2 bits → symbole I/Q, codage de Gray | bits → symboles I/Q | [voir](captures/page13-qpsk.png) |
| 14 | ▶️ [Filtre SRRC](https://ericperret.github.io/JPEG2DVB/page14-srrc-v2.html) | Mise en forme en racine de cosinus surélevé | symboles → signal mis en forme | [voir](captures/page14-srrc-v2.png) |

## Utilisation

1. Ouvrir l'étape 00 (webcam) ou 01 (fichier image).
2. À chaque étape, lancer le traitement (en une fois ou pas à pas), puis cliquer sur **suivante ▶** : la sortie est transmise à l'étape suivante, qui la charge d'office (bandeau en haut de page). Le traitement reste toujours au clic.
3. Les boutons **Exporter** / **Charger** restent disponibles pour garder chaque fichier intermédiaire ou reprendre depuis un fichier.

## Historique

| Version | Évolution |
|---|---|
| 2026-10-17 | Ancien filtre SRRC retiré (seule la v2 est conservée), pages renommées sans suffixe de copie, cartouches, page d'accueil corrigée, README / LISEZMOI réécrits, captures de chaque étape |
| 2026-10-18 | Charte graphique AZS sur les 15 étapes et la page d'accueil (palette ardoise / ambre / cyan, marque AZS avec lien vers www.azs.fr, polices système) ; sorties vérifiées identiques sur toute la chaîne ; captures refaites |
| 2026-10-18 | Pages 1.3 : passage automatique entre les étapes — suivante ▶ garde la sortie dans le navigateur (session en cours) et l'étape suivante la charge d'office ; traitement toujours au clic ; sorties identiques à la chaîne fichier par fichier |
| 2026-10-18 | Pages 03, 04, 06 (1.4) : encadrés sur les écarts avec MPEG-2 (quantification séparée du DC, formule AC et quantiser_scale, balayage alterné, matrices transmises en ordre zigzag dans le Sequence Header) |

## Licence

CC BY-NC 4.0

## Auteur

**Eric PERRET** — [GitHub](https://github.com/ericperret)
