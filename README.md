<!--
  Name     : README.md
  Purpose  : Overview of JPEG2DVB (step-by-step DVB-S transmission chain)
  Author   : Eric PERRET
  Date     : 2026-10-17
  License  : CC BY-NC 4.0
-->

# 📡 JPEG2DVB — from image to DVB-S modulation

🇫🇷 [Version française : LISEZMOI.md](LISEZMOI.md)

▶️ **[Home page of the 15 steps](https://ericperret.github.io/JPEG2DVB/index2.html)**

[![License: CC BY-NC 4.0](https://img.shields.io/badge/License-CC%20BY--NC%204.0-lightgrey.svg)](https://creativecommons.org/licenses/by-nc/4.0/)

![Page 02: 8×8 DCT](captures/page02-dct.png)

Interactive tutorial of the digital satellite TV chain: from capturing an image to shaping the QPSK signal, following MPEG-2 and DVB-S (EN 300 421). Each step is a standalone HTML page doing the real computations: it loads the file produced by the previous step (JSON or binary), processes it step by step with visualisation, and saves its result for the next step.

No library, no installation. User interfaces in French.

## The steps

| Step | Launch | Processing | Input → output | Screenshot |
|---|---|---|---|---|
| 00 | ▶️ [Camera](https://ericperret.github.io/JPEG2DVB/page00-camera.html) | Image capture from the webcam | webcam → image | [view](captures/page00-camera.png) |
| 01 | ▶️ [Macroblocks](https://ericperret.github.io/JPEG2DVB/page01-image-to-macroblocs.html) | RGB → YCbCr 4:2:0, 16×16 macroblocks (4 Y + 1 Cb + 1 Cr) | image → macroblock JSON | [view](captures/page01-image-to-macroblocs.png) |
| 02 | ▶️ [DCT](https://ericperret.github.io/JPEG2DVB/page02-dct.html) | Centring −128, 8×8 2D DCT | macroblocks → coefficients | [view](captures/page02-dct.png) |
| 03 | ▶️ [Quantisation](https://ericperret.github.io/JPEG2DVB/page03-quantification.html) | Division by the quantisation matrix (lossy) | coefficients → quantised integers | [view](captures/page03-quantification.png) |
| 04 | ▶️ [Zigzag](https://ericperret.github.io/JPEG2DVB/page04-zigzag.html) | Zigzag scan of the 64 coefficients | blocks → 64-value vectors | [view](captures/page04-zigzag.png) |
| 05 | ▶️ [RLE + Huffman](https://ericperret.github.io/JPEG2DVB/page05-rle-huffman.html) | (run, level) pairs, variable-length codes | vectors → bitstreams | [view](captures/page05-rle-huffman.png) |
| 06 | ▶️ [Elementary Stream](https://ericperret.github.io/JPEG2DVB/page06-elementary-stream.html) | MPEG-2 sequence, GOP, picture headers, slices | bitstreams → .es file | [view](captures/page06-elementary-stream.png) |
| 07 | ▶️ [PES](https://ericperret.github.io/JPEG2DVB/page07-pes.html) | PES packets, PTS timestamps | ES → PES | [view](captures/page07-pes.png) |
| 08 | ▶️ [Transport Stream](https://ericperret.github.io/JPEG2DVB/page08-ts.html) | 188-byte packets, PAT and PMT tables | PES → playable .ts file | [view](captures/page08-ts.png) |
| 09 | ▶️ [PRBS](https://ericperret.github.io/JPEG2DVB/page09-prbs.html) | Energy dispersal, polynomial 1 + X¹⁴ + X¹⁵, 8-packet super-frame | TS → randomised TS | [view](captures/page09-prbs.png) |
| 10 | ▶️ [Reed-Solomon](https://ericperret.github.io/JPEG2DVB/page10-reed-solomon.html) | RS(204,188) shortened from RS(255,239), GF(2⁸) 0x11D, 8 correctable bytes | 188 → 204 bytes | [view](captures/page10-reed-solomon.png) |
| 11 | ▶️ [Interleaving](https://ericperret.github.io/JPEG2DVB/page11-interleaving.html) | Forney convolutional interleaver, I = 12, M = 17 | RS blocks → interleaved stream | [view](captures/page11-interleaving.png) |
| 12 | ▶️ [Convolutional coder](https://ericperret.github.io/JPEG2DVB/page12-convolutional_1.html) | K = 7, rate 1/2, G1 = 171₈, G2 = 133₈, optional puncturing | stream → coded bits | [view](captures/page12-convolutional_1.png) |
| 13 | ▶️ [QPSK](https://ericperret.github.io/JPEG2DVB/page13-qpsk.html) | 2 bits → I/Q symbol, Gray coding | bits → I/Q symbols | [view](captures/page13-qpsk.png) |
| 14 | ▶️ [SRRC filter](https://ericperret.github.io/JPEG2DVB/page14-srrc-v2.html) | Square-root raised-cosine pulse shaping | symbols → shaped signal | [view](captures/page14-srrc-v2.png) |

## Usage

1. Open step 00 (webcam) or 01 (image file).
2. At each step: load the file from the previous step, run the processing (at once or step by step), save the output.
3. Move on to the next step with that file.

## History

| Version | Change |
|---|---|
| 2026-10-17 | Old SRRC filter removed (only v2 kept), pages renamed without copy suffix, header blocks, home page fixed, README / LISEZMOI rewritten, screenshot of every step |
| 2026-10-18 | AZS visual identity on the 15 steps and the home page (slate / amber / cyan palette, AZS mark linking back to www.azs.fr, system fonts); outputs checked identical along the whole chain; screenshots refreshed |

## License

CC BY-NC 4.0

## Author

**Eric PERRET** — [GitHub](https://github.com/ericperret)
