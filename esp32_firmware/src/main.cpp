#include <Arduino.h>
#include "FS.h"
#include "SD_MMC.h"

#define CHUNK_SIZE 512 //can be tuned later


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

void setup()
{

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

}

void loop()
{


}