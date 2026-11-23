<!--
  Nom      : README.md
  Projet   : JPEG2DVB — Chantier 2 : Programmation du PIC et du FPGA depuis l'ESP32 (M5Stack CoreS3)
  Auteur   : Eric PERRET
  Date     : 2026-11-23
  Version  : 1.1.0
-->

# `jpeg2dvb_prog` — Firmware M5Stack CoreS3

![Target](https://img.shields.io/badge/cible-M5Stack%20CoreS3-orange.svg)
![Version](https://img.shields.io/badge/version-1.1.0-blue.svg)
![Protocol](https://img.shields.io/badge/interfaces-ICSP%20%7C%20JTAG--DirectC-brightgreen.svg)

Firmware d'interface web pour le **M5Stack CoreS3** permettant la programmation in-situ du microcontrôleur **PIC** de U6 (ICSP basse tension ; PIC16(L)F18323, 18324, 18325, 18326 reconnus par leur DEVID) et du FPGA **Microchip PolarFire** (JTAG-DirectC) via un réseau Wi-Fi local.

> ℹ️ **Remarque :** L'émetteur est autonome et fonctionne normalement sans la présence du module CoreS3 une fois la programmation effectuée.

---

## 📌 Sommaire

- [Aperçu du système](#-aperçu-du-système)
- [Câblage J7 ↔ CoreS3](#-câblage-j7--cores3)
- [Environnement & Compilation](#-environnement--compilation)
- [Utilisation de l'Interface Web](#-utilisation-de-linterface-web)
- [Procédure de Premier Essai](#-procédure-de-premier-essai)

---

## 🔍 Aperçu du système

- **Microcontrôleur cible (PIC)** : U6, PIC16(L)F18323, 18324, 18325 ou 18326 — Contrôle du synthétiseur de fréquence ADF4351.
- **FPGA cible** : Microchip PolarFire IC1 (MPF100T / MPF050T).
- **Interface de contrôle** : Serveur Web embarqué sur ESP32 avec portail captif.
- **Affichage local** : Écran du CoreS3 indiquant le SSID, l'adresse IP, le statut du signal LD (*Lock Detect*) et les comptes rendus d'exécution.

---

## 🔌 Câblage J7 ↔ CoreS3

Toutes les liaisons fonctionnent directement en **logique 3,3 V**. 

En dehors des phases de programmation, l'ensemble des broches est maintenu en **haute impédance (Hi-Z)**, permettant de laisser le programmateur externe (FlashPro sur J4) utilisable.  
*Exception :* Le signal `MCLR` est forcé à `0` pendant la programmation du FPGA afin de couper la sortie Haute Fréquence (HF) par sécurité.

| Broche J7 | Signal | Connexion Côté Carte | GPIO CoreS3 | Broche M5-Bus | Sens (ESP32) |
| :---: | :--- | :--- | :---: | :---: | :--- |
| **1** | `+5V` | +5V carte | 5V | 28 | Alimentation |
| **2** | `GND` | GND carte | GND | 1 | Masse |
| **3** | `MCLR` | U6.4, R47 (10 kΩ vers +3V3) | G5 | 8 | Sortie *(Hi-Z au repos)* |
| **4** | `ICSPCLK` | U6.12 (RA1) | G6 | 21 | Sortie *(Hi-Z au repos)* |
| **5** | `ICSPDAT` | U6.13 (RA0) | G7 | 22 | Bidirectionnel *(Hi-Z au repos)* |
| **6** | `LD` | U3.25 (LD ADF4351), U6.11 (RA2) | G10 | 2 | Entrée |
| **7** | `JTAG_TCK` | IC1.H10, J4.1, R19 (10 kΩ vers GND) | G8 | 4 | Sortie *(Hi-Z au repos)* |
| **8** | `JTAG_TMS` | IC1.F6, J4.5, R14 (10 kΩ vers +3V3) | G9 | 10 | Sortie *(Hi-Z au repos)* |
| **9** | `JTAG_TDI` | IC1.G7, J4.9, R15 (10 kΩ vers +3V3) | G17 | 16 | Sortie *(Hi-Z au repos)* |
| **10** | `JTAG_TDO` | IC1.F7, J4.3 | G18 | 15 | Entrée |
| **11** | `JTAG_TRSTB` | IC1.H7, J4.8, R20 (1 kΩ vers GND) | G1 | 20 | Sortie *(Hi-Z au repos)* |

---

## 🛠️ Environnement & Compilation

### Prérequis
Le projet s'appuie sur la chaîne d'outils **DroneRX** :
- `arduino-cli` (placé dans `~/bin`)
- **Cœur ESP32** : `v3.3.12`
- **Bibliothèque M5Stack** : `M5Unified v0.2.25`
- **Dépendances système** : `unzip`, `gcc`, `node`

### Dépendances et Fichiers Sources
Tous les fichiers sont à plat dans `esp32/`, sans sous-dossier ; `build.sh` est autonome (aucun téléchargement)
et ne crée rien dans ce dossier : il compile dans une copie, `~/.cache/jpeg2dvb_esp32`.

| Fichier | Rôle |
|---|---|
| `jpeg2dvb_prog.ino`, `prog_page.h`, `pic_fw.h` | firmware (copiés dans `~/.cache` pour la compilation) |
| `pll_boot.asm` | source du programme du PIC (`pic_fw.h` en est produit par `pic14.js`) |
| `pic14.js`, `test_adf4351.c` | contrôles sur PC (`./build.sh controle`) |
| `directc.zip` | JTAG-DirectC v2021.2 de Microchip prêt à compiler + adaptation ESP32 ; **sur le PC seulement, jamais sur GitHub** (licence Microchip) |

`directc.zip` contient les sources Microchip (dépôt public MicrochipTech/adg_fpga_reconfiguration, commit `2de7cdc`)
et les fichiers d'adaptation : `dpuser.c`, `gpio_hw_interface.c`, `jpeg2dvb_port.h`, `reglages.sh`
(G5 PolarFire activé, RTG4 désactivé, lecture paginée du `.dat`).

- **Firmware PIC** : `pic_fw.h` est livré pré-assemblé. En cas de modification de `pll_boot.asm` :
  ```bash
  node pic14.js asm pll_boot.asm pic_fw.h
  ```

### Commandes de Build

Placez-vous dans le dossier `esp32` puis utilisez le script `./build.sh` :

```bash
cd esp32

# Compile le projet (directc.zip doit être à côté de build.sh)
./build.sh compile

# Téléverse le firmware (CoreS3 connecté en USB sur /dev/ttyACM*)
./build.sh flash

# Ouvre le moniteur série à 115200 bauds
./build.sh mon

# Enchaîne : compilation + téléversement + moniteur série
./build.sh all

# Exécute les contrôles hors-ligne sur PC (calculs ADF4351 via GCC & simulation PIC via Node.js)
./build.sh controle
```

---

## 🌐 Utilisation de l'Interface Web

1. **Connexion au point d'accès Wi-Fi** :
   - **SSID** : `jpeg2dvb.local`
   - **Mot de passe** : `jpeg2dvb.local`
   - Le portail captif redirige automatiquement vers l'interface. En cas d'échec, ouvrez votre navigateur sur `http://192.168.4.1/` ou `http://jpeg2dvb.local/`.

2. **Section PIC (U6)** :
   - **« Lire le PIC »** : modèle (F ou LF) reconnu par le DEVID, mémoire programme, contenu (vierge, programme JPEG2DVB et sa version, autre programme), fréquence en EEPROM.
   - **« Programmer le PIC »** (première programmation ou PIC remplacé) : effacement, programme, repère User ID, configuration, EEPROM à la fréquence du bloc PLL, vérification.

3. **Section PLL** :
   - Indiquez la fréquence désirée (**950,0 MHz** à **2150,0 MHz**, pas de 0,5 MHz).
   - Les valeurs des registres (`INT`, `FRAC`, `R0` à `R5`) et des diviseurs sont recalculées automatiquement.
   - Cliquez sur **« Écrire la fréquence »** : seule l'EEPROM du PIC est réécrite (le programme JPEG2DVB doit être en place), puis attente du verrouillage `LD` (1 s max). La dernière fréquence configurée est conservée en mémoire.

4. **Section FPGA (PolarFire)** :
   - Sélectionnez le fichier bitstream `.dat` généré depuis **Libero** (*Export Bitstream*, format DAT).
   - Cliquez sur **« Envoyer »** (le fichier est stocké sous `/fpga.dat` ; la taille et le CRC32 sont contrôlés).
   - **« Identifier »** : Lit et affiche l'IDCODE ainsi que les détails du FPGA.
   - **« Programmer et vérifier »** : Déclenche l'effacement, la programmation puis la vérification complète de la puce (confirmation demandée).

5. **Monitoring & Journaux** :
   - Le bloc d'état et le journal d'activité s'actualisent toutes les secondes.

---

## 🧪 Procédure de Premier Essai

Suivez ces étapes dans l'ordre pour valider le bon fonctionnement du sous-ensemble :

1. **Vérification du CoreS3 seul** *(hors carte, alimenté en USB)* :
   - Lancer `./build.sh all`.
   - Contrôler les informations d'affichage sur l'écran (SSID et IP).
   - Se connecter au Wi-Fi, ouvrir la page web et saisir `1250.0` MHz.
   - Vérifier la valeur des registres générés : R0 doit afficher `00320000` et R4 `009C843C`.

2. **Programmation du PIC à 1250,0 MHz** *(CoreS3 branché sur J7, carte sous tension)* :
   - Cliquer sur **« Lire le PIC »** (modèle reconnu), saisir 1250,0 puis cliquer sur **« Programmer le PIC »**.
   - **Attendu :** message *« PIC16F18323 programmé et vérifié à 1250,0 MHz — PLL verrouillée »*, signal `LD` confirmé sur l'écran et sur la page web. Signal HF mesurable sur `RFOUTA`.
   - **« Écrire la fréquence »** à 1300,0 puis à 1250,0 : seule l'EEPROM change, `LD` se reverrouille.
   - Couper puis remettre l'alimentation de la carte : la PLL doit se reverrouiller seule au démarrage.

3. **Identification du FPGA** :
   - Envoyer le fichier `.dat` sur le CoreS3 via l'interface web, puis cliquer sur **« Identifier »**.
   - **Attendu :** Lecture de l'IDCODE `?F8111CFh` (MPF100T) ou `?F8101CFh` (MPF050T), avec un code de retour DirectC égal à `0`. Le signal HF réapparaît à la fin du processus après le redémarrage du PIC.

4. **Programmation et vérification du FPGA** :
   - Cliquer sur **« Programmer et vérifier »** et confirmer.
   - **Attendu :** Code de retour DirectC `0` pour l'étape de programmation, puis `0` pour l'étape de vérification.
   - *Note :* En cas de problème ou d'échec de flashage, le connecteur J4 (sonde FlashPro) reste opérationnel comme solution de secours.