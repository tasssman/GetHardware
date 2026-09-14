[CmdletBinding()]
param(
    [ValidateRange(0, 255)]
    [int]$DiskNumber = 0
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

if (-not ('GetHardware.StorageTopology' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;

namespace GetHardware
{
    public sealed class DiskFormFactorResult
    {
        public int Code { get; set; }
        public string Name { get; set; }
        public string Source { get; set; }
        public string Detail { get; set; }
    }

    public static class StorageTopology
    {
        private const uint IOCTL_STORAGE_QUERY_PROPERTY = 0x002D1400;
        private const uint FILE_SHARE_READ = 0x00000001;
        private const uint FILE_SHARE_WRITE = 0x00000002;
        private const uint OPEN_EXISTING = 3;
        private static readonly IntPtr InvalidHandleValue = new IntPtr(-1);

        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        private static extern IntPtr CreateFile(
            string fileName,
            uint desiredAccess,
            uint shareMode,
            IntPtr securityAttributes,
            uint creationDisposition,
            uint flagsAndAttributes,
            IntPtr templateFile);

        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern bool DeviceIoControl(
            IntPtr device,
            uint controlCode,
            byte[] input,
            uint inputSize,
            byte[] output,
            uint outputSize,
            out uint bytesReturned,
            IntPtr overlapped);

        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern bool CloseHandle(IntPtr handle);

        public static DiskFormFactorResult Query(int diskNumber)
        {
            string path = @"\\.\PhysicalDrive" + diskNumber;
            IntPtr handle = CreateFile(
                path,
                0,
                FILE_SHARE_READ | FILE_SHARE_WRITE,
                IntPtr.Zero,
                OPEN_EXISTING,
                0,
                IntPtr.Zero);

            if (handle == InvalidHandleValue)
            {
                throw new Win32Exception(Marshal.GetLastWin32Error(), "Nie można otworzyć " + path);
            }

            try
            {
                // 54 = StorageDevicePhysicalTopologyProperty,
                // 53 = StorageAdapterPhysicalTopologyProperty (fallback).
                int[] propertyIds = new int[] { 54, 53 };
                string[] propertyNames = new string[] {
                    "StorageDevicePhysicalTopologyProperty",
                    "StorageAdapterPhysicalTopologyProperty"
                };
                int lastError = 0;

                for (int propertyIndex = 0; propertyIndex < propertyIds.Length; propertyIndex++)
                {
                    byte[] query = new byte[12];
                    Buffer.BlockCopy(BitConverter.GetBytes(propertyIds[propertyIndex]), 0, query, 0, 4);
                    byte[] output = new byte[65536];
                    uint bytesReturned;
                    bool success = DeviceIoControl(
                        handle,
                        IOCTL_STORAGE_QUERY_PROPERTY,
                        query,
                        (uint)query.Length,
                        output,
                        (uint)output.Length,
                        out bytesReturned,
                        IntPtr.Zero);

                    if (!success)
                    {
                        lastError = Marshal.GetLastWin32Error();
                        continue;
                    }
                    if (bytesReturned < 56)
                    {
                        continue;
                    }

                    uint nodeCount = BitConverter.ToUInt32(output, 8);
                    for (uint nodeIndex = 0; nodeIndex < nodeCount; nodeIndex++)
                    {
                        long nodeOffset64 = 16L + (nodeIndex * 40L);
                        if (nodeOffset64 + 28 > bytesReturned)
                        {
                            break;
                        }

                        int nodeOffset = (int)nodeOffset64;
                        uint deviceCount = BitConverter.ToUInt32(output, nodeOffset + 16);
                        uint deviceDataOffset = BitConverter.ToUInt32(output, nodeOffset + 24);
                        if (deviceCount == 0 || deviceDataOffset == 0 || deviceDataOffset + 24 > bytesReturned)
                        {
                            continue;
                        }

                        int formFactorCode = BitConverter.ToInt32(output, (int)deviceDataOffset + 20);
                        return new DiskFormFactorResult {
                            Code = formFactorCode,
                            Name = GetFormFactorName(formFactorCode),
                            Source = propertyNames[propertyIndex],
                            Detail = formFactorCode == 0 ? "Sterownik zwrócił nieznany format." : ""
                        };
                    }
                }

                return new DiskFormFactorResult {
                    Code = 0,
                    Name = "Unknown",
                    Source = "IOCTL_STORAGE_QUERY_PROPERTY",
                    Detail = lastError == 0
                        ? "Sterownik nie zwrócił danych o formacie."
                        : new Win32Exception(lastError).Message
                };
            }
            finally
            {
                CloseHandle(handle);
            }
        }

        private static string GetFormFactorName(int code)
        {
            switch (code)
            {
                case 1: return "3.5 inch";
                case 2: return "2.5 inch";
                case 3: return "1.8 inch";
                case 4: return "Less than 1.8 inch";
                case 5: return "Embedded";
                case 6: return "Memory Card";
                case 7: return "mSATA";
                case 8: return "M.2";
                case 9: return "PCIe Board";
                case 10: return "DIMM";
                default: return "Unknown";
            }
        }
    }
}
'@
}

Write-Host ''
Write-Host '=== Test formatu dysku ===' -ForegroundColor Cyan
Write-Host "Dysk: \\.\PhysicalDrive$DiskNumber"

try {
    $Result = [GetHardware.StorageTopology]::Query($DiskNumber)
    $Color = if ($Result.Name -eq 'Unknown') { 'Yellow' } else { 'Green' }
    Write-Host "Format: $($Result.Name)" -ForegroundColor $Color
    Write-Host "Kod:    $($Result.Code)"
    Write-Host "Źródło: $($Result.Source)"
    if (-not [string]::IsNullOrWhiteSpace($Result.Detail)) {
        Write-Warning $Result.Detail
    }
}
catch {
    Write-Error "Nie udało się odczytać formatu dysku: $($_.Exception.Message)"
}
