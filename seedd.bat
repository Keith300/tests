#include "seed.h"
#include "utils.h"
#include "defines.h"
#include <intrin.h>

namespace SeedSystem {
    PERSISTENT_SEED g_PersistentSeed = { 0 };

    typedef struct _HIDDEN_SEED_STORAGE {
        ULONG MasterSeed;
        ULONG BootCount;
        ULONG Checksum;
    } HIDDEN_SEED_STORAGE, * PHIDDEN_SEED_STORAGE;

    PHIDDEN_SEED_STORAGE g_HiddenStorage = nullptr;
    const ULONG HIDDEN_POOL_TAG = 'DeeS';

    ULONG CryptographicHash(ULONG input) {
        input = (input ^ (input >> 16)) * 0x45D9F3B;
        input = (input ^ (input >> 16)) * 0x45D9F3B;
        input = input ^ (input >> 16);
        return input;
    }

    ULONG GenerateComponentSeed(ULONG baseSeed, ULONG componentId) {
        ULONG componentMagic = 0;

        switch (componentId) {
        case 1: componentMagic = 0x8F4A3C2B; break; // CPU
        case 2: componentMagic = 0x3B6A9C8D; break; // GPU
        case 3: componentMagic = 0x7D2E5A9B; break; // Motherboard
        case 4: componentMagic = 0x1A5E9C3D; break; // Memory
        case 5: componentMagic = 0x6C3A8F4D; break; // Disk
        case 6: componentMagic = 0x4B7D1E9A; break; // Monitor
        case 7: componentMagic = 0x2E5B8A1D; break; // Network
        default: componentMagic = 0xDEADBEEF;
        }
        return CryptographicHash(baseSeed ^ componentMagic ^ componentId);
    }

    ULONG GenerateHardwareBasedSeed() {
        ULONG seed = 0;

        int cpuInfo[4] = { 0 };
        __cpuid(cpuInfo, 0);
        seed ^= cpuInfo[0] ^ cpuInfo[1] ^ cpuInfo[2] ^ cpuInfo[3];

        __cpuid(cpuInfo, 1);
        seed ^= cpuInfo[0] ^ cpuInfo[1] ^ cpuInfo[2] ^ cpuInfo[3];

        seed ^= 0x12345678;

        for (int i = 0; i < 16; i++) {
            seed = CryptographicHash(seed ^ i);
        }
        return seed;
    }

    ULONG CalculateStorageChecksum(PHIDDEN_SEED_STORAGE storage) {
        if (!storage) return 0;
        return CryptographicHash(storage->MasterSeed ^ storage->BootCount ^ 0x12345678);
    }

    NTSTATUS InitializeMemoryPersistence() {
        if (g_HiddenStorage) {
            return STATUS_SUCCESS;
        }
        g_HiddenStorage = (PHIDDEN_SEED_STORAGE)ExAllocatePool2(
            POOL_FLAG_NON_PAGED,
            sizeof(HIDDEN_SEED_STORAGE),
            HIDDEN_POOL_TAG
        );

        if (!g_HiddenStorage) {
            return STATUS_INSUFFICIENT_RESOURCES;
        }

        RtlZeroMemory(g_HiddenStorage, sizeof(HIDDEN_SEED_STORAGE));
        return STATUS_SUCCESS;
    }

    VOID CleanupMemoryPersistence() {
        if (g_HiddenStorage) {
            RtlZeroMemory(g_HiddenStorage, sizeof(HIDDEN_SEED_STORAGE));
            ExFreePoolWithTag(g_HiddenStorage, HIDDEN_POOL_TAG);
            g_HiddenStorage = nullptr;
        }
    }

    NTSTATUS SaveSeedToMemory(ULONG masterSeed, ULONG bootCount) {
        NTSTATUS status = InitializeMemoryPersistence();
        if (!NT_SUCCESS(status)) {
            return status;
        }

        if (!g_HiddenStorage) {
            return STATUS_UNSUCCESSFUL;
        }

        g_HiddenStorage->MasterSeed = masterSeed;
        g_HiddenStorage->BootCount = bootCount;
        g_HiddenStorage->Checksum = CalculateStorageChecksum(g_HiddenStorage);

        return STATUS_SUCCESS;
    }

    ULONG LoadSeedFromMemory(PULONG bootCount) {
        if (!g_HiddenStorage) {
            NTSTATUS status = InitializeMemoryPersistence();
            if (!NT_SUCCESS(status)) {
                if (bootCount) *bootCount = 0;
                return 0;
            }
        }

        if (!g_HiddenStorage || g_HiddenStorage->MasterSeed == 0) {
            if (bootCount) *bootCount = 0;
            return 0;
        }

        ULONG computedChecksum = CalculateStorageChecksum(g_HiddenStorage);
        if (computedChecksum != g_HiddenStorage->Checksum) {
            CleanupMemoryPersistence();
            if (bootCount) *bootCount = 0;
            return 0;
        }

        if (bootCount) {
            *bootCount = g_HiddenStorage->BootCount;
        }
        return g_HiddenStorage->MasterSeed;
    }

    NTSTATUS SetUserSeed(ULONG userSeed) {
        if (g_PersistentSeed.IsInitialized) {
            g_PersistentSeed.MasterSeed = userSeed;
            RegenerateSessionSeed();

            SaveSeedToMemory(g_PersistentSeed.MasterSeed, g_PersistentSeed.BootCount);
            return STATUS_SUCCESS;
        }

        g_PersistentSeed.MasterSeed = userSeed;
        g_PersistentSeed.HardwareSeed = GenerateHardwareBasedSeed();
        g_PersistentSeed.BootCount = 1;

        LARGE_INTEGER time;
        KeQuerySystemTime(&time);
        g_PersistentSeed.SessionSeed = CryptographicHash(
            g_PersistentSeed.MasterSeed ^
            time.LowPart
        );

        KeQuerySystemTime(&g_PersistentSeed.CreationTime);
        g_PersistentSeed.IsInitialized = TRUE;

        SaveSeedToMemory(g_PersistentSeed.MasterSeed, g_PersistentSeed.BootCount);

        return STATUS_SUCCESS;
    }

    NTSTATUS InitializeSeedSystem() {
        if (g_PersistentSeed.IsInitialized) {
            return STATUS_SUCCESS;
        }

        ULONG storedMasterSeed = 0;
        ULONG storedBootCount = 0;

        storedMasterSeed = LoadSeedFromMemory(&storedBootCount);
        BOOLEAN hasPersistentSeed = (storedMasterSeed != 0);

        if (hasPersistentSeed) {
            g_PersistentSeed.MasterSeed = storedMasterSeed;
            g_PersistentSeed.BootCount = storedBootCount + 1;
            g_PersistentSeed.HardwareSeed = GenerateHardwareBasedSeed();
        }
        else {
            g_PersistentSeed.MasterSeed = GenerateHardwareBasedSeed();
            g_PersistentSeed.BootCount = 1;
            g_PersistentSeed.HardwareSeed = GenerateHardwareBasedSeed();
        }

        LARGE_INTEGER time;
        KeQuerySystemTime(&time);

        g_PersistentSeed.SessionSeed = CryptographicHash(
            g_PersistentSeed.MasterSeed ^
            time.LowPart
        );

        for (int i = 0; i < 8; i++) {
            g_PersistentSeed.MasterSeed = CryptographicHash(g_PersistentSeed.MasterSeed ^ i);
            g_PersistentSeed.SessionSeed = CryptographicHash(g_PersistentSeed.SessionSeed ^ i);
        }

        KeQuerySystemTime(&g_PersistentSeed.CreationTime);
        g_PersistentSeed.IsInitialized = TRUE;

        if (!hasPersistentSeed) {
            SaveSeedToMemory(g_PersistentSeed.MasterSeed, g_PersistentSeed.BootCount);
        }

        return STATUS_SUCCESS;
    }

    ULONG GetCpuSeed() {
        return GenerateComponentSeed(GetMasterSeed(), 1);
    }

    ULONG GetGpuSeed() {
        return GenerateComponentSeed(GetMasterSeed(), 2);
    }

    ULONG GetMotherboardSeed() {
        return GenerateComponentSeed(GetMasterSeed(), 3);
    }

    ULONG GetMemorySeed() {
        return GenerateComponentSeed(GetMasterSeed(), 4);
    }

    ULONG GetDiskSeed() {
        return GenerateComponentSeed(GetMasterSeed(), 5);
    }

    ULONG GetMonitorSeed() {
        return GenerateComponentSeed(GetMasterSeed(), 6);
    }

    ULONG GetNetworkSeed() {
        return GenerateComponentSeed(GetMasterSeed(), 7);
    }

    ULONG GenerateDeterministicValue(ULONG componentSeed, ULONG minVal, ULONG maxVal) {
        if (minVal > maxVal) {
            return minVal;
        }

        ULONG localSeed = CryptographicHash(componentSeed ^ minVal ^ maxVal);
        ULONG range = maxVal - minVal + 1;

        if (range == 0) {
            return minVal;
        }

        return minVal + (localSeed % range);
    }

    VOID GenerateSerialString(ULONG seed, CHAR* output, SIZE_T size, const CHAR* charset) {
        if (!output || size == 0) return;

        RtlZeroMemory(output, size);

        ULONG localSeed = seed;
        SIZE_T charsetLen = 0;

        if (charset) {
            const CHAR* ptr = charset;
            while (*ptr != '\0') {
                charsetLen++;
                ptr++;
            }
        }

        if (charsetLen == 0) {
            output[0] = '\0';
            return;
        }

        for (SIZE_T i = 0; i < size - 1; i++) {
            localSeed = CryptographicHash(localSeed ^ i);
            output[i] = charset[localSeed % charsetLen];
        }

        output[size - 1] = '\0';
    }

    VOID GenerateMacAddress(ULONG seed, UCHAR mac[6]) {
        if (!mac) return;

        ULONG localSeed = seed;

        mac[0] = 0x02;

        for (int i = 1; i < 6; i++) {
            localSeed = CryptographicHash(localSeed ^ i);
            mac[i] = (UCHAR)(localSeed & 0xFF);
        }
    }

    VOID GenerateUuid(ULONG seed, GUID* uuid) {
        if (!uuid) return;

        RtlZeroMemory(uuid, sizeof(GUID));

        ULONG localSeed = seed;
        uuid->Data1 = CryptographicHash(localSeed);
        localSeed = CryptographicHash(localSeed ^ 1);
        uuid->Data2 = (USHORT)(localSeed & 0xFFFF);
        localSeed = CryptographicHash(localSeed ^ 2);
        uuid->Data3 = (USHORT)(localSeed & 0xFFFF);

        for (int i = 0; i < 8; i++) {
            localSeed = CryptographicHash(localSeed ^ (3 + i));
            uuid->Data4[i] = (UCHAR)(localSeed & 0xFF);
        }
        uuid->Data3 = (uuid->Data3 & 0x0FFF) | 0x4000;
        uuid->Data4[0] = (uuid->Data4[0] & 0x3F) | 0x80;
    }

    ULONG GetMasterSeed() {
        if (!g_PersistentSeed.IsInitialized) {
            InitializeSeedSystem();
        }
        return g_PersistentSeed.MasterSeed;
    }

    ULONG GetSessionSeed() {
        if (!g_PersistentSeed.IsInitialized) {
            InitializeSeedSystem();
        }
        return g_PersistentSeed.SessionSeed;
    }

    ULONG GetHardwareSeed() {
        if (!g_PersistentSeed.IsInitialized) {
            InitializeSeedSystem();
        }
        return g_PersistentSeed.HardwareSeed;
    }

    VOID RegenerateSessionSeed() {
        if (!g_PersistentSeed.IsInitialized) return;

        LARGE_INTEGER time;
        KeQuerySystemTime(&time);

        g_PersistentSeed.SessionSeed = CryptographicHash(
            g_PersistentSeed.MasterSeed ^
            time.LowPart
        );
        SaveSeedToMemory(g_PersistentSeed.MasterSeed, g_PersistentSeed.BootCount);
    }

    VOID CleanupSeedSystem() {
        CleanupMemoryPersistence();
        RtlZeroMemory(&g_PersistentSeed, sizeof(g_PersistentSeed));
    }

    BOOLEAN IsSeedSystemInitialized() {
        return g_PersistentSeed.IsInitialized;
    }
}