#pragma once
#include <ntifs.h>

namespace SeedSystem {
    typedef struct _PERSISTENT_SEED {
        ULONG MasterSeed;
        ULONG SessionSeed;
        ULONG HardwareSeed;
        LARGE_INTEGER CreationTime;
        ULONG BootCount;
        BOOLEAN IsInitialized;
    } PERSISTENT_SEED, * PPERSISTENT_SEED;

    extern PERSISTENT_SEED g_PersistentSeed;

    NTSTATUS InitializeSeedSystem();
    VOID CleanupSeedSystem();
    ULONG GetMasterSeed();
    ULONG GetSessionSeed();
    ULONG GetHardwareSeed();
    BOOLEAN IsSeedSystemInitialized();
    VOID RegenerateSessionSeed();

    NTSTATUS SetUserSeed(ULONG userSeed);

    ULONG GetCpuSeed();
    ULONG GetGpuSeed();
    ULONG GetMotherboardSeed();
    ULONG GetMemorySeed();
    ULONG GetDiskSeed();
    ULONG GetMonitorSeed();
    ULONG GetNetworkSeed();

    ULONG GenerateDeterministicValue(ULONG componentSeed, ULONG minVal, ULONG maxVal);
    VOID GenerateSerialString(ULONG seed, CHAR* output, SIZE_T size, const CHAR* charset);
    VOID GenerateMacAddress(ULONG seed, UCHAR mac[6]);
    VOID GenerateUuid(ULONG seed, GUID* uuid);
}