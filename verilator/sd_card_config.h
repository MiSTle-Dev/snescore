#ifndef SD_CARD_CONFIG_H
#define SD_CARD_CONFIG_H

#define TICKLEN   (0.5/21505400)

#define TB_NAME   Vsnestang_top

#include "Vsnestang_top.h"

#ifdef SD_CARD_CPP
const char *file_image[8] = {
  "../../src/roms/hello.sfc",  // with 512 byte header
  // "../../src/roms/hello_no_hdr.sfc",  // w/o  -"-
  // "../../src/roms/superbomberman.sfc",  // w/o  -"-
  NULL, NULL, NULL, NULL, NULL, NULL, NULL            // unused
};
#endif

#define MAX_DRIVES   6   // DF0-3/DH0-1

// enable to test direct mapping bypassing the companion if possible
#define ENABLE_DIRECT_MAP

// enable writing of modified data back into image ... potentially corrupting it
// #define WRITE_BACK

// enable this to simulate a FPGA Companion constantly writing and reading data,
// potentially colliding with the Core's own accesses
// #define FC_RW_STORM

// interface to sd card simulation
void sd_init(void);
void sd_handle(void);
void sd_get_sector(int drive, int lba, uint8_t *data);

void hexdump(void *data, int size);
void hexdiff(void *data1, void *data2, int size);

// clocks the SD card claims to be busy before read data is returned
#define READ_BUSY_COUNT 100

#endif
