#!/bin/bash

# Function to prompt for confirmation
confirm() {
    read -p "$1 (yes/no): " response
    case "$response" in
        [yY][eE][sS]|[yY])
            true
            ;;
        *)
            false
            ;;
    esac
}

# List available drives and prompt for the target disk
lsblk
read -p "Enter the disk to partition (e.g., /dev/nvme1n1, /dev/sda): " disk

# Confirm the selected disk
if ! confirm "You have selected $disk. Is this correct?"; then
    echo "Exiting..."
    exit 1
fi

# Start partitioning the disk
echo "Partitioning the disk..."
parted "$disk" --script mklabel gpt

# Create EFI partition
echo "Creating EFI partition..."
parted "$disk" --script mkpart primary fat32 1MiB 301MiB
parted "$disk" --script set 1 esp on

# Create root partition (adjust size as needed, here the rest of the disk)
echo "Creating root partition..."
parted "$disk" --script mkpart primary 301MiB 100%

# Optionally create a swap partition (Uncomment to use swap)
# parted "$disk" --script mkpart primary linux-swap 100MiB 3000MiB
# parted "$disk" --script mkpart primary ext4 3000MiB 100%

# Get the partition names based on selected disk
efi_partition="${disk}p1"
root_partition="${disk}p2"

# Confirm partitions before formatting
echo "EFI partition: $efi_partition"
echo "Root partition: $root_partition"
if ! confirm "Are these partitions correct?"; then
    echo "Exiting..."
    exit 1
fi

# Format the partitions
echo "Formatting EFI partition..."
mkfs.fat -F32 "$efi_partition"

echo "Formatting root partition..."
mkfs.btrfs "$root_partition"

# Your existing script continues from here...

# Mount the root partition and create Btrfs subvolumes
mount "$root_partition" /mnt

btrfs su cr /mnt/@
btrfs su cr /mnt/@home
btrfs su cr /mnt/@pkg
btrfs su cr /mnt/@log
btrfs su cr /mnt/@snapshots

# Unmount the root partition
umount /mnt

# Mount the root partition with subvolumes and options
mkdir /mnt/archinstall

mount -o noatime,space_cache=v2,compress=zstd:5,discard=async,subvol=@ "$root_partition" /mnt/archinstall
mkdir -p /mnt/archinstall/{boot,home,var/log,var/cache/pacman/pkg,.snapshots}
mount -o noatime,space_cache=v2,compress=zstd:5,discard=async,subvol=@home "$root_partition" /mnt/archinstall/home
mount -o noatime,space_cache=v2,compress=zstd:5,discard=async,subvol=@pkg "$root_partition" /mnt/archinstall/var/cache/pacman/pkg
mount -o noatime,space_cache=v2,compress=zstd:5,discard=async,subvol=@log "$root_partition" /mnt/archinstall/var/log
mount -o noatime,space_cache=v2,compress=zstd:5,discard=async,subvol=@snapshots "$root_partition" /mnt/archinstall/.snapshots

# Mount the EFI partition
mount "$efi_partition" /mnt/archinstall/boot

echo "Partitioning and formatting completed. System is ready for Arch Linux installation."
