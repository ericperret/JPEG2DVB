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
| 02 | ▶️ [DCT](https://ericperret.github.io/JPEG2DVB/page02-dct.html) | DCT 2D 8×8 MPEG-2 intra (sans centrage, DC = 8 × moyenne), ordre naturel F[v][u] | macroblocs → coefficients | [voir](captures/page02-dct.png) |
| 03 | ▶️ [Quantification](https://ericperret.github.io/JPEG2DVB/page03-quantification.html) | Quantification MPEG-2 : DC / 8, AC = 16·F / (W·quantiser_scale) ; matrice et code d'échelle transmis à l'étape 06 | coefficients → entiers quantifiés | [voir](captures/page03-quantification.png) |
| 04 | ▶️ [Zigzag](https://ericperret.github.io/JPEG2DVB/page04-zigzag.html) | Parcours zigzag des 64 coefficients | blocs → vecteurs de 64 | [voir](captures/page04-zigzag.png) |
| 05 | ▶️ [RLE + Huffman](https://ericperret.github.io/JPEG2DVB/page05-rle-huffman.html) | Paires (run, level), tables MPEG-2 B.12 / B.13 (DC) et B.14 (AC), échappement, prédicteurs DC par composante | vecteurs → bitstreams | [voir](captures/page05-rle-huffman.png) |
| 06 | ▶️ [Elementary Stream](https://ericperret.github.io/JPEG2DVB/page06-elementary-stream.html) | Sequence, GOP, Picture headers, slices MPEG-2 ; matrice et code d'échelle de l'étape 03 ; décodable par ffmpeg / VLC | bitstreams → fichier .es | [voir](captures/page06-elementary-stream.png) |
| 07 | ▶️ [PES](https://ericperret.github.io/JPEG2DVB/page07-pes.html) | Paquets PES, PTS = PCR initial + 0,7 s (pas de DTS pour une image I), alignement des données | ES → PES | [voir](captures/page07-pes.png) |
| 08 | ▶️ [Transport Stream](https://ericperret.github.io/JPEG2DVB/page08-ts.html) | Paquets de 188 octets, tables PAT et PMT, PCR dans le premier paquet vidéo | PES → fichier .ts, lu par VLC et ffplay | [voir](captures/page08-ts.png) |
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

## Flux multi-images (2.0)

Pour éprouver l'algorithme avant le portage sur FPGA, toute la chaîne traite aussi une séquence d'images.

1. **Étape 01** : régler **Images** (1 à 1500) puis ⚙️ Convertir. L'image (ou la mire) est répétée avec un carré mobile (+8 pixels par image) et un compteur binaire de 12 bits. Au-delà d'une image, les sorties sont des conteneurs binaires `.j2d` (en-tête JSON + tableaux typés), chargés par les étapes suivantes comme les JSON.
2. **Étape 02** : option **virgule fixe**, DCT entière (coefficients sur 13 bits, deux passes, 32 bits suffisent), référence bit à bit du FPGA, à ±1 de la DCT flottante arrondie.
3. **Étape 03** : régulation de débit TM5 par slice (rangée de macroblocs). Le débit symbole, le FEC et la part vidéo du multiplex donnent la cible par image ; les bits sont comptés exactement (tables VLC, en-têtes, alignements) ; le quantiser_scale_code de chaque slice est écrit dans le flux.
4. **Étapes 06 à 08** : suite d'images I (GOP fermé de 12, Sequence Header répété), un PES par image, PTS = ((n+1)/25 + 0,1 s) × 90 000, multiplexage à débit constant au débit utile du canal (9,216 Mbit/s à 10 MS/s en FEC 1/2) : PAT et PMT toutes les 80 ms, PCR toutes les 30 ms, paquets nuls. Contrôles affichés : tampon du décodeur, arrivée de chaque image avant son PTS, intervalles PCR et PSI.
5. **Étapes 09 à 14** : flux entier traité par blocs. Étape 13 : symboles entiers ±1. Étape 14 : filtre SRRC (α = 0,35), coefficients en virgule fixe 16 bits en option, I/Q entiers 16 bits (format cs16) écrits au fil de l'eau sur le disque (Chrome, Edge) ou téléchargés à la fin.

**Validation** : ffmpeg et ffprobe sans avertissement ; débit mesuré sur les PCR constant (9,215686 Mbit/s, écart inférieur à une période de 27 MHz) ; compteurs de continuité sans erreur. La bande de base de l'étape 14, démodulée par un récepteur DVB-S indépendant (leandvb), restitue à l'identique tous les paquets TS reçus (6 351 sur 6 367 pour une seconde de flux, les autres sont perdus pendant l'accrochage du récepteur). Chaîne fichier par fichier et chaîne « suivante ▶ » identiques.

## Historique

| Version | Évolution |
|---|---|
| 2026-10-17 | Ancien filtre SRRC retiré (seule la v2 est conservée), pages renommées sans suffixe de copie, cartouches, page d'accueil corrigée, README / LISEZMOI réécrits, captures de chaque étape |
| 2026-10-18 | Charte graphique AZS sur les 15 étapes et la page d'accueil (palette ardoise / ambre / cyan, marque AZS avec lien vers www.azs.fr, polices système) ; sorties vérifiées identiques sur toute la chaîne ; captures refaites |
| 2026-10-18 | Pages 1.3 : passage automatique entre les étapes — suivante ▶ garde la sortie dans le navigateur (session en cours) et l'étape suivante la charge d'office ; traitement toujours au clic ; sorties identiques à la chaîne fichier par fichier |
| 2026-10-18 | Pages 03, 04, 06 (1.4) : encadrés sur les écarts avec MPEG-2 (quantification séparée du DC, formule AC et quantiser_scale, balayage alterné, matrices transmises en ordre zigzag dans le Sequence Header) |
| 2026-10-18 | Conformité MPEG-2 (pages 02, 03, 05, 06 → 1.5) : DCT sans centrage et en ordre naturel (les coefficients étaient transposés), quantification normative, tables VLC complètes B.12 / B.13 / B.14 avec prédicteurs DC par composante, matrice et code d'échelle écrits dans le flux. L'Elementary Stream et le Transport Stream se décodent désormais avec ffmpeg (PSNR 35,7 dB au facteur 50 ; 30,7 à 48,4 dB du facteur 10 à 100). Pages 07 à 12 (1.4) : export JSON des gros flux corrigé |
| 2026-10-18 | Pages 07 et 08 (1.5) : horodatage ISO 13818-1 — PCR dans l'adaptation field du premier paquet vidéo (PID annoncé par la PMT), PTS = PCR + 0,7 s, indicateurs data_alignment et random_access, PTS 33 bits sans débordement 32 bits |
| 2026-10-19 | Pages 2.0 : flux multi-images (conteneur .j2d, DCT en virgule fixe, régulation de débit TM5, multiplexage à débit constant, traitement par blocs, SRRC en virgule fixe et écriture au fil de l'eau). Conformité EN 300 421 corrigée sur trois étapes : générateur PRBS (initialisation et sortie), ordre des octets de parité Reed-Solomon, registre du codeur convolutif. Vérifié par démodulation avec un récepteur DVB-S indépendant |

## Licence

CC BY-NC 4.0

## Auteur

**Eric PERRET** — [GitHub](https://github.com/ericperret)
