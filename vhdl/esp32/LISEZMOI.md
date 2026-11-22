<!--
  Nom      : LISEZMOI.md
  Projet   : JPEG2DVB — chantier 2 : programmation du PIC et du FPGA depuis l'ESP32 (M5Stack CoreS3)
  Objet    : câblage, compilation, utilisation et premier essai du firmware jpeg2dvb_prog
  Auteur   : Eric PERRET
  Date     : 2026-11-21
  Version  : 1.0.0
-->

# jpeg2dvb_prog — firmware du M5Stack CoreS3

Programme le PIC16F18323 (U6, ICSP basse tension) et le FPGA PolarFire (IC1, JTAG-DirectC) par une page web en Wi-Fi.
L'émetteur fonctionne sans le CoreS3.

## Câblage J7 ↔ CoreS3

| J7 | Signal | Côté carte | GPIO CoreS3 | Broche M5-Bus | Sens ESP |
|---|---|---|---|---|---|
| 1 | +5V | +5V carte | 5V | 28 | alimentation |
| 2 | GND | GND | GND | 1 | masse |
| 3 | MCLR | U6.4, R47 10 kΩ vers +3V3 | G5 | 8 | sortie (haute impédance au repos) |
| 4 | ICSPCLK | U6.12 (RA1) | G6 | 21 | sortie (haute impédance au repos) |
| 5 | ICSPDAT | U6.13 (RA0) | G7 | 22 | bidirectionnel (haute impédance au repos) |
| 6 | LD | U3.25 (LD de l'ADF4351), U6.11 (RA2) | G10 | 2 | entrée |
| 7 | JTAG_TCK | IC1.H10, J4.1, R19 10 kΩ vers GND | G8 | 4 | sortie (haute impédance au repos) |
| 8 | JTAG_TMS | IC1.F6, J4.5, R14 10 kΩ vers +3V3 | G9 | 10 | sortie (haute impédance au repos) |
| 9 | JTAG_TDI | IC1.G7, J4.9, R15 10 kΩ vers +3V3 | G17 | 16 | sortie (haute impédance au repos) |
| 10 | JTAG_TDO | IC1.F7, J4.3 | G18 | 15 | entrée |
| 11 | JTAG_TRSTB | IC1.H7, J4.8, R20 1 kΩ vers GND | G1 | 20 | sortie (haute impédance au repos) |

Logique 3,3 V en direct. Hors programmation, toutes les liaisons sont en haute impédance (J4 FlashPro reste utilisable),
sauf MCLR tenu à 0 pendant la programmation du FPGA (HF coupée).

## Compilation et flashage

Environnement de DroneRX : `arduino-cli` dans `~/bin`, cœur esp32 3.3.12, M5Unified 0.2.25, `git`, `gcc`, `node`.

```
cd esp32
./build.sh compile      # récupère JTAG-DirectC (1re fois), compile
./build.sh flash        # compile + téléverse (CoreS3 en USB, /dev/ttyACM*)
./build.sh mon          # moniteur série 115200
./build.sh all          # compile + téléverse + moniteur
./build.sh controle     # contrôles sur PC : calcul ADF4351 (gcc), PIC assemblé et simulé (node)
```

- JTAG-DirectC v2021.2 (commit `2de7cdc` de MicrochipTech/adg_fpga_reconfiguration) est récupéré par `build.sh`
  dans `jpeg2dvb_prog/src/directc/` (licence Microchip : jamais versionné, voir `.gitignore`),
  puis complété par les fichiers de `jpeg2dvb_prog/portage/`.
- `pic_fw.h` est livré assemblé. Après modification de `pic/pll_boot.asm` :
  `node outils/pic14.js asm jpeg2dvb_prog/pic/pll_boot.asm jpeg2dvb_prog/pic_fw.h`

## Utilisation

1. Se connecter au Wi-Fi `jpeg2dvb.local`, mot de passe `jpeg2dvb.local`. Le portail captif ouvre la page
   (sinon `http://192.168.4.1/` ou `http://jpeg2dvb.local/`).
2. **PLL** : saisir la fréquence (950,0 à 2150,0 MHz, pas de 0,5 MHz) ; diviseur, INT, FRAC et R0 à R5 s'affichent.
   « Écrire dans le PIC » efface, programme et vérifie le PIC (programme + configuration + EEPROM),
   puis attend LD au plus 1 s. La dernière fréquence écrite est gardée et réaffichée.
3. **FPGA** : choisir le `.dat` exporté par Libero (Export Bitstream, format DAT), « Envoyer » (stocké en `/fpga.dat`,
   taille et CRC32 affichés). « Identifier » lit l'IDCODE et les informations du composant.
   « Programmer et vérifier » efface puis programme et vérifie le FPGA (confirmation demandée).
4. Le bloc « État » et le journal se mettent à jour chaque seconde. L'écran du CoreS3 montre SSID, IP, LD
   et la dernière action avec son résultat.

## Premier essai sur carte

1. **CoreS3 seul** (hors carte, alimenté en USB) : `./build.sh all`, vérifier l'écran (SSID, IP), se connecter au Wi-Fi,
   ouvrir la page, saisir 1250,0 : registres affichés (R0 `00320000`, R4 `009C843C`).
2. **PIC à 1250,0 MHz** (CoreS3 sur J7, carte alimentée) : « Écrire dans le PIC ». Attendu : DEVID `3067h`,
   « PIC programmé et vérifié … PLL verrouillée », LD verrouillée sur l'écran et la page, HF présente sur RFOUTA.
   Couper puis remettre l'alimentation : la PLL doit se reverrouiller seule.
3. **Identifier le FPGA** : envoyer le `.dat`, « Identifier ». Attendu : IDCODE `?F8111CFh` (MPF100T)
   ou `?F8101CFh` (MPF050T), « ? » étant la révision du composant, code DirectC 0. La HF revient à la fin (le PIC redémarre).
4. **Programmer et vérifier le FPGA** : « Programmer et vérifier », confirmer. Attendu : code DirectC 0 pour la
   programmation puis pour la vérification. En cas d'échec, J4 (FlashPro) reste le secours.
