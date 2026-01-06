/*
Copyright © 2024-2026 Alessandro Meles (TheForge-2)
This file is part of the LARI OS project.
Use is restricted to personal, non-commercial, educational and experimental purposes only.
See 'LICENSE.txt' in the project root for full terms.

Based on the code shown in Nanobyte's tutorial "Building an OS", episode 3.
Expanded with comments and partially restructured.
*/



#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>



// Define a boolean structure
typedef uint8_t bool;
#define true 1
#define false 0



// Define the BPB and EBR sctructure
typedef struct {

	uint8_t BootJumpInstruction[3];
	uint8_t OemIdentifier[8];
	uint16_t BytesPerSector;
	uint8_t SectorsPerCluster;
	uint16_t ReservedSectors;
	uint8_t FatCount;
	uint16_t DirEntryCount;
	uint16_t TotalSectors;
	uint8_t MediaDescriptorType;
	uint16_t SectorsPerFat;
	uint16_t SectorsPerTrack;
	uint16_t Heads;
	uint32_t HiddenSectors;
	uint32_t LargeSectorCount;

	uint8_t DriveNumber;
	uint8_t _Reserved;
	uint8_t Signature;
	uint32_t VolumeId;
	uint8_t VolumeLabel[11];
	uint8_t SystemId[8];

} __attribute__((packed)) BootSector; // Don't allign

typedef struct {

	uint8_t Name[11];
	uint8_t Attributes;
	uint8_t _Reserved;
	uint8_t CreatedTimeTenths;
	uint16_t CreatedTime;
	uint16_t CreatedDate;
	uint16_t AccessedDate;
	uint16_t FirstClusterHigh;
	uint16_t ModifiedTime;
	uint16_t ModifiedDate;
	uint16_t FirstClusterLow;
	uint32_t Size;

} __attribute__((packed)) DirectoryEntry; // Don't allign



// Declare a global BootSector variable
BootSector g_BootSector;
// Initialise a global Fat pointer
uint8_t* g_Fat = NULL;
// Initialise a global RootDirectory pointer
DirectoryEntry* g_RootDirectory = NULL;
// Declare a global RootDirectoryEnd variable, for later use
uint32_t g_RootDirectoryEnd;



// Read the BPB and EBR from the disk
bool readBootSector (FILE* disk){

	return fread(&g_BootSector, sizeof(g_BootSector), 1, disk) > 0; // Read the data and assign it to the structure
}



// Read some sectors from the disk
bool readSectors (FILE *disk, uint32_t lba, uint32_t count, void* bufferOut){

	bool ok = true;
	ok = ok && (fseek(disk, lba * g_BootSector.BytesPerSector, SEEK_SET) == 0); // Point disk (FILE*) to the beginning of the sector
	ok = ok && (fread(bufferOut, g_BootSector.BytesPerSector, count, disk) == count); // Read the sector/s
	return ok;
}



// Read the FAT into memory
bool readFat (FILE* disk){

	g_Fat = (uint8_t*) malloc(g_BootSector.SectorsPerFat * g_BootSector.BytesPerSector); // g_Fat points to a memory region
	return readSectors(disk, g_BootSector.ReservedSectors, g_BootSector.SectorsPerFat, g_Fat);
}



// Read the root directory into memory
bool readRootDirectory (FILE* disk){

	uint32_t lba = g_BootSector.ReservedSectors + g_BootSector.SectorsPerFat * g_BootSector.FatCount; // Get the LBA of the begining
	uint32_t size = sizeof(DirectoryEntry) * g_BootSector.DirEntryCount; // Get the size
	uint32_t sectors = size / g_BootSector.BytesPerSector; // Get the sector count
	if (size % g_BootSector.BytesPerSector > 0) // Add a sector if it doesn't fit
		sectors++;
	g_RootDirectoryEnd = lba + sectors; // Save for later use
	g_RootDirectory = (DirectoryEntry*) malloc(sectors * g_BootSector.BytesPerSector); // g_RootDirectory points to a memory region
	return readSectors(disk, lba, sectors, g_RootDirectory);
}



// Find a file in the root directory
DirectoryEntry* findFile (const char* name){

	for (uint32_t i = 0; i < g_BootSector.DirEntryCount; i++){ // Keep comparing until the file name matches
		if (memcmp(name, g_RootDirectory[i].Name, 11) == 0) // Compare consecutive names
			return &g_RootDirectory[i];
	}
	return NULL; // No file was found
}



/*
File Allocation Table:
FF0 FFF 003 004 005 006 007 ...

The first two clusters (0 and 1) are reserved and don't appear on the disk. The are just FAT entries.

Then each entry has the value of the next one in the chain for a file.
If that is the last cluster, a value greater than or equal to FF8 is used.
If the cluster contains a bad sector, it is marked with FF7.
Anything else is a valid reference.

The FAT is stored on the disk "packed", as 12 bits don't make an integer number of bytes:
F0 FF FF 03 40 00 05 60 00 07 80 00 ...

So every even entry is:
l4bB(n+1), h4bB(n), l4bB(n)
And every odd entry is:
h4bB(n+1), l4bB(n+1), h4bB(n)

In memory it is stored like it is on the disk: the beginning at a lower address then the end.
When 2 bytes are accesed, they are read in little-endian, so the on with the higher address is read first.

The sequence 03 40 (even entry) becomes 40 03 and a bitwise AND is applied with 0x0FFF.
This makes the hh4b 0000 and the rest are kept: the reference is decoded in 0x0003

The sequence 40 00 (odd entry) becomes 00 40 and a 4 bit right shift is applied.
This gives 0x0004, the decoded reference.
*/



// Read a file from the data region via the FAT
bool readFile (DirectoryEntry* fileEntry, FILE* disk, uint8_t* outputBuffer){

	bool ok = true;
	uint16_t currentCluster = fileEntry->FirstClusterLow; // Initialise currentCluster as the first cluster of the file

	do {
		uint32_t lba = g_RootDirectoryEnd + (currentCluster - 2) * g_BootSector.SectorsPerCluster; // Get the LBA of the cluster
		ok = ok && readSectors(disk, lba, g_BootSector.SectorsPerCluster, outputBuffer); // Read the cluster
		outputBuffer += g_BootSector.SectorsPerCluster * g_BootSector.BytesPerSector; // Advance in memory

		uint32_t fatIndex = currentCluster * 3 / 2; // Go the the lowest byte needed for reading the FAT entry of the current cluster
		// "Decode" the next reference (explained above)
		if (currentCluster % 2 == 0)
			currentCluster = (*(uint16_t*)(g_Fat + fatIndex)) & 0x0FFF;
		else
			currentCluster = (*(uint16_t*)(g_Fat + fatIndex)) >> 4;
	} while (ok && currentCluster < 0x0FF7); // Break if currentCluster is 0x0FF7 (bad sector) or greater or equal than 0x0FF8 (OEF, end of file)

	return (ok && currentCluster != 0x0FF7); // Failed if a bad sector prevented reading
}



// Main function
int main (int argc, char** argv){

	// Minimum arguments check
	if (argc < 3){
		printf("Usage: %s <disk image> <file name>\n", argv[0]);
		return -1;
	}

	// Open the disk image
	FILE* disk = fopen(argv[1], "rb");
	if (!disk){
		fprintf(stderr, "Could not open disk image \"%s\"!\n", argv[1]);
		return -2;
	}

	// Read the BootSector
	if (!readBootSector(disk)){
		fprintf(stderr, "Could not read boot sector!\n");
		return -3;
	}

	// Read the FAT
	if (!readFat(disk)){
		fprintf(stderr, "Could not read FAT!\n");
		free(g_Fat);
		return -4;
	}

	// Read the root directory
	if (!readRootDirectory(disk)){
		fprintf(stderr, "Could not read root directory!\n");
		free(g_Fat);
		free(g_RootDirectory);
		return -5;
	}

	// Find the file
	DirectoryEntry* fileEntry = findFile(argv[2]); // Initialise fileEntry as a pointer to a DirectoryEntry structure
	if (!fileEntry){
		fprintf(stderr, "Could not find file \"%s\"!\n", argv[2]);
		free(g_Fat);
		free(g_RootDirectory);
		return -6;
	}

	// Read the file
	uint8_t* buffer = (uint8_t*) malloc(fileEntry->Size + g_BootSector.BytesPerSector); // Allocate sufficient memory for the file
	if (!readFile(fileEntry, disk, buffer)){
		fprintf(stderr, "Could not read file \"%s\"!\n", argv[2]);
		free(g_Fat);
		free(g_RootDirectory);
		free(buffer);
		return -7;
	}

	// Print out the contents of the file
	for (size_t i = 0; i < fileEntry->Size; i++){ // Print each byte at a time
		if (isprint(buffer[i])) // Check the printability of each byte
			fputc(buffer[i], stdout); // Print the character
		else if (buffer[i] == 0x0A) // Check for 0x0A (new line), because it is rejected by isprint
			printf("\n");
		else
			printf("<%02x>", buffer[i]); // Print the byte's hex value
	}

	printf("\n");

	// Free the used memory
	free(buffer);
	free(g_Fat);
	free(g_RootDirectory);
	return 0;
}
