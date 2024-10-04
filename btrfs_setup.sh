#!/bin/bash

# Description of the script
echo "--------------------------------------------------------"
echo "     Arch Linux Disk Partitioning and Formatting Script   "
echo "--------------------------------------------------------"
echo "This script will guide you through partitioning a selected disk,"
echo "formatting it with Btrfs and creating subvolumes for Arch Linux installation."
echo "It will also create and format an EFI partition for UEFI booting."
echo "Ensure that you select the correct disk, as this operation is destructive!"
echo "--------------------------------------------------------"
echo

# Function to prompt for confirmation
confirm() {
    read -p "$1 (yes/no): " response
    case "$response" in
        [yY][eE][sS]|[yY]) true ;;
        *) false ;;
    esac
}

# Check if required commands are available
for cmd in parted mkfs.btrfs mkfs.fat btrfs; do
    if ! command -v "$cmd" &> /dev/null; then
        echo "Error: $cmd is not installed." >&2
        exit 1
    fi
done

# List available drives and prompt for the target disk
lsblk
read -p "Enter the disk to partition (e.g., /dev/nvme1n1, /dev/sda): " disk

# Check if the disk exists
if ! lsblk | grep -q "$disk"; then
    echo "Error: Disk $disk not found." >&2
    exit 1
fi

# Confirm the selected disk
if ! confirm "You have selected $disk. Is this correct?"; then
    echo "Exiting..."
    exit 1
fi

# Start partitioning the disk
echo "Partitioning the disk..."
if ! parted "$disk" --script mklabel gpt; then
    echo "Error: Failed to partition the disk." >&2
    exit 1
fi

# Create EFI partition
echo "Creating EFI partition..."
parted "$disk" --script mkpart primary fat32 1MiB 301MiB
parted "$disk" --script set 1 esp on

# Create root partition
echo "Creating root partition..."
parted "$disk" --script mkpart primary 301MiB 100%

# Determine partition names
efi_partition="${disk}p1"
root_partition="${disk}p2"
if [[ ! -e "$efi_partition" || ! -e "$root_partition" ]]; then
    echo "Error: Partition names not found." >&2
    exit 1
fi

# Confirm partitions before formatting
echo "EFI partition: $efi_partition"
echo "Root partition: $root_partition"
if ! confirm "Are these partitions correct?"; then
    echo "Exiting..."
    exit 1
fi

# Format the partitions
echo "Formatting EFI partition..."
if ! mkfs.fat -F32 "$efi_partition"; then
    echo "Error: Failed to format EFI partition." >&2
    exit 1
fi

echo "Formatting root partition..."
if ! mkfs.btrfs "$root_partition"; then
    echo "Error: Failed to format root partition." >&2
    exit 1
fi

# Mount the root partition and create Btrfs subvolumes
mount "$root_partition" /mnt

btrfs su cr /mnt/@
btrfs su cr /mnt/@home
btrfs su cr /mnt/@pkg
btrfs su cr /mnt/@log
btrfs su cr /mnt/@snapshots

# Unmount the root partition
umount /mnt

# Common mount options for Btrfs
btrfs_opts="noatime,space_cache=v2,compress=zstd:5,discard=async"

# Mount the root partition with subvolumes and options
mkdir /mnt/archinstall
mount -o $btrfs_opts,subvol=@ "$root_partition" /mnt/archinstall
mkdir -p /mnt/archinstall/{boot,home,var/log,var/cache/pacman/pkg,.snapshots}
mount -o $btrfs_opts,subvol=@home "$root_partition" /mnt/archinstall/home
mount -o $btrfs_opts,subvol=@pkg "$root_partition" /mnt/archinstall/var/cache/pacman/pkg
mount -o $btrfs_opts,subvol=@log "$root_partition" /mnt/archinstall/var/log
mount -o $btrfs_opts,subvol=@snapshots "$root_partition" /mnt/archinstall/.snapshots

# Mount the EFI partition
mount "$efi_partition" /mnt/archinstall/boot

echo "Partitioning and formatting completed. System is ready for Arch Linux installation."
