#include <Arduino.h>
#include "FS.h"
#include "SD_MMC.h"
#include <SPI.h>

#define CHUNK_SIZE 512 //can be tuned later

#define SPI_SCLK_PIN  1
#define SPI_MOSI_PIN  2
#define SPI_MISO_PIN  21
#define SPI_CS_PIN    47
#define BOOT_DONE_PIN 14

// Tentative SDRAM destinations -- revisit once real firmware size is
// known (Phase 5). 1MB of headroom for code vs. today's 288-byte
// bring-up binary.
#define FIRMWARE_DEST_ADDR 0x80000000UL
#define WAD_DEST_ADDR      0x80100000UL


void listDir(fs::FS &fs, const char *dirname)
{

    Serial.printf("Listing directory: %s\n", dirname);
    File root = fs.open(dirname);
    if (!root || !root.isDirectory()) {
        Serial.println("Failed to open directory");
        return;
    }
    File file = root.openNextFile();
    while (file) {
        Serial.printf("  %s  (%u bytes)\n", file.name(), (unsigned int)file.size());
        file = root.openNextFile();
    }
}

void readWadHeader(fs::FS &fs, const char *path)
{

    File f = fs.open(path, FILE_READ);
    if (!f) {
        Serial.printf("Failed to open %s\n", path);
        return;
    }

    char magic[5] = {0};
    f.read((uint8_t *)magic, 4);

    uint32_t numLumps, dirOffset;
    f.read((uint8_t *)&numLumps, 4);
    f.read((uint8_t *)&dirOffset, 4);

    Serial.printf("WAD magic: %s\n", magic);
    Serial.printf("Num lumps: %u\n", numLumps);
    Serial.printf("Directory offset: 0x%08X\n", dirOffset);

    f.close();
}

void readFileInChunks(fs::FS &fs, const char *path)
{

    File f = fs.open(path, FILE_READ);
    if(!f)
    {
        Serial.printf("Failed to open %s\n", path);
        return;
    }

    uint32_t totalSize = f.size();
    Serial.printf("Reading %s (%u bytes) in %d-byte chunks...\n", path, totalSize, CHUNK_SIZE);

    uint8_t buffer[CHUNK_SIZE];
    uint32_t bytesRead = 0;
    uint32_t chunksCount = 0;

    while (f.available())
    {
        size_t n = f.read(buffer, CHUNK_SIZE);
        if(n == 0) break;

        bytesRead += n;
        chunksCount++;

        // Placeholder: this is where each chunk gets handed off to the
        // FPGA receiver interface in Phase 3.2 (e.g. spi_write(buffer, n)).
        // For now we just track progress.
    }

    f.close();

    Serial.printf("Done: read %u bytes in %u chunks\n", bytesRead, chunksCount);
    if (bytesRead != totalSize)
    {
        Serial.println("WARNING: bytes read does not match file size!");
    }
}

// Sends the 8-byte address+length header boot_loader.vhd expects,
// little-endian, before a file's payload bytes.
void bootSendHeader(uint32_t addr, uint32_t len) {
    uint8_t hdr[8];
    hdr[0] = (addr >> 0)  & 0xFF;
    hdr[1] = (addr >> 8)  & 0xFF;
    hdr[2] = (addr >> 16) & 0xFF;
    hdr[3] = (addr >> 24) & 0xFF;
    hdr[4] = (len >> 0)  & 0xFF;
    hdr[5] = (len >> 8)  & 0xFF;
    hdr[6] = (len >> 16) & 0xFF;
    hdr[7] = (len >> 24) & 0xFF;
    SPI.transfer(hdr, 8);
}

// TEMPORARY DIAGNOSTIC (see setup() below): sends a small, known,
// in-RAM payload instead of a real SD card file -- same CS-low/header/
// payload framing as bootSendFile(), just sourced from `data` instead
// of a File. Lets a single real-hardware boot cycle be compared
// directly against sim/tb_boot_path.vhd, which drives this exact
// framing at the Wishbone/SDRAM level and confirmed the write+read
// round-trip is correct there. If this small transfer also comes back
// correct on hardware, the bug is specific to the real, multi-second,
// ~4.2MB transfer (refresh interaction, drift, ...); if even this
// comes back wrong, the bug is in the physical SPI link itself.
void bootSendTestPattern(uint32_t destAddr, const uint8_t *data, uint32_t len) {
    Serial.printf("boot: [TEST] sending %u known bytes -> 0x%08X\n", len, destAddr);

    digitalWrite(SPI_CS_PIN, LOW);
    bootSendHeader(destAddr, len);
    SPI.transfer((void *)data, len);
    digitalWrite(SPI_CS_PIN, HIGH);

    Serial.printf("boot: [TEST] done, %u bytes sent\n", len);
}

// Sends one file to the FPGA boot loader: header, then payload bytes
// in CHUNK_SIZE-sized SPI transfers, all under one CS-low session.
bool bootSendFile(fs::FS &fs, const char *path, uint32_t destAddr) {
    File f = fs.open(path, FILE_READ);
    if (!f) {
        Serial.printf("boot: failed to open %s\n", path);
        return false;
    }

    uint32_t size = f.size();
    Serial.printf("boot: sending %s (%u bytes) -> 0x%08X\n", path, size, destAddr);

    digitalWrite(SPI_CS_PIN, LOW);
    bootSendHeader(destAddr, size);

    uint8_t buf[CHUNK_SIZE];
    uint32_t sent = 0;
    while (sent < size) {
        size_t n = f.read(buf, sizeof(buf));
        if (n == 0) break;
        SPI.transfer(buf, n);
        sent += n;
    }
    digitalWrite(SPI_CS_PIN, HIGH);
    f.close();

    if (sent != size) {
        Serial.println("boot: WARNING short read, file transfer incomplete");
        return false;
    }
    Serial.printf("boot: done, %u bytes sent\n", sent);
    return true;
}

void setup()
{
    // Both FPGA-facing control pins are driven to their idle levels
    // before ANYTHING else -- ahead of Serial.begin() and the ~1 s of SD
    // card work below -- so neither is ever left floating while the FPGA
    // is already out of reset and watching them.
    //
    // BOOT_DONE idles LOW (not done). It previously stayed unconfigured
    // through SD_MMC.begin()/listDir()/readWadHeader()/readFileInChunks();
    // during that window the FPGA's boot_done input could pick up a
    // spurious high and its sticky latch would trip on that alone,
    // releasing the CPU before any real data had arrived. Confirmed on
    // hardware: the byte counter read far short of the full transfer
    // while the ESP32 was still visibly transmitting.
    //
    // CS idles HIGH (deasserted). Same class of problem, milder symptom:
    // left floating it produced one spurious falling edge per boot (the
    // FPGA counted 3 CS assertions for a 2-file transfer). spi_slave
    // resets its bit counter whenever CS is high, so an edge here costs
    // nothing while no data is in flight -- but a floating input next to
    // actively switching SPI lines is not something to leave in place
    // just because this particular instance was harmless.
    //
    // Note this does NOT fully close either window: the ESP32's own boot
    // takes a few hundred ms, and these pins are undriven until it gets
    // here. Holding them at their idle levels through power-up is a job
    // for termination resistors, not firmware -- see the WEAK_PULL_UP
    // note on spi_cs_n in CPU_FPGA.qsf.
    pinMode(BOOT_DONE_PIN, OUTPUT);
    digitalWrite(BOOT_DONE_PIN, LOW);
    pinMode(SPI_CS_PIN, OUTPUT);
    digitalWrite(SPI_CS_PIN, HIGH);

    Serial.begin(115200);
    delay(1000);

    SD_MMC.setPins(39,38,40);

    if(!SD_MMC.begin("/sdcard" , true))
    {
        Serial.println("SD_MMC Mount Failed");
        return;
    }

    uint8_t cardType = SD_MMC.cardType();
    if(cardType == CARD_NONE)
    {

        Serial.println("No SD card attached");
        return;
    }

    Serial.println("SD Card Type: ");
    if(cardType == CARD_MMC) Serial.println("MMC");
    else if (cardType == CARD_SD) Serial.println("SDSC");
    else if (cardType == CARD_SDHC) Serial.println("SDHC");
    else Serial.println("UNKNOWN");

    uint64_t cardSize = SD_MMC.cardSize() / (1024 * 1024);
    Serial.printf("SD Card Size: %lluMB\n", cardSize);

    listDir(SD_MMC, "/");
    readWadHeader(SD_MMC, "/DOOM1.WAD");
    readFileInChunks(SD_MMC, "/DOOM1.WAD");

    // Boot-load: stream the firmware binary and the WAD into the
    // FPGA's SDRAM over SPI, then release the FPGA CPU from reset.
    // (BOOT_DONE_PIN and SPI_CS_PIN are both already configured and
    // driven to their idle levels at the very top of setup() -- see the
    // comment there. SPI.begin()'s ss argument is left as the real pin:
    // begin() does not drive it, and CS is toggled manually per file in
    // bootSendFile(), so hardware CS is never engaged.)

    SPI.begin(SPI_SCLK_PIN, SPI_MISO_PIN, SPI_MOSI_PIN, SPI_CS_PIN);
    // Back to 1 MHz after a temporary drop to 100 kHz while chasing an
    // apparent byte-loss problem. That drop turned out not to be the
    // fix: the real causes were a spurious boot_done assertion (the
    // FPGA released the CPU mid-transfer, so the byte counter was being
    // read while the ESP32 was still sending -- fixed by the debounce
    // in rv32im_soc.vhd plus driving BOOT_DONE_PIN low at the top of
    // setup()) and an SDRAM column-address aliasing bug (see the
    // ADDRESS MAPPING note in rtl/memory/sdram_controller.vhd). With
    // those fixed, SPI_BYTE_COUNT/WRITE_COUNT come back exact and
    // FW[0]/WAD[0] read correctly, so the extra 10x of per-bit
    // synchronizer margin is not needed -- and 1 MHz keeps the boot
    // transfer at ~30 s instead of ~5 min.
    SPI.beginTransaction(SPISettings(1000000, MSBFIRST, SPI_MODE0));

    // Small-test-pattern diagnostic (bootSendTestPattern) confirmed the
    // short-transfer case round-trips onto the boot_loader/sdram_controller
    // Wishbone interface fine in sim, but that transfer is only ~12 bytes
    // -- under a millisecond at 1 MHz -- too fast to watch the new LED
    // boot-diagnostic in rv32im_soc.vhd actually progress. Back to the
    // real files: this transfer runs ~30+ real seconds, long enough to
    // see LED0/1/2/3 light up in sequence (or not) during an actual boot.
    bool ok = true;
    ok &= bootSendFile(SD_MMC, "/FIRMWARE.BIN", FIRMWARE_DEST_ADDR);
    ok &= bootSendFile(SD_MMC, "/DOOM1.WAD", WAD_DEST_ADDR);

    SPI.endTransaction();

    if (ok) {
        Serial.println("boot: all files sent, asserting BOOT_DONE");
        digitalWrite(BOOT_DONE_PIN, HIGH);
    } else {
        Serial.println("boot: file transfer failed, NOT asserting BOOT_DONE");
    }

}

void loop()
{


}
