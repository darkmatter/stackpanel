{ lib, ... }:
{
  disko.devices = {
    disk.main = {
      type = "disk";
      device = lib.mkDefault "/dev/vda";
      content = {
        type = "gpt";
        partitions = {
          # Tiny BIOS boot partition so GRUB can install on GPT systems.
          bios = {
            size = "1M";
            type = "EF02";
          };

          root = {
            size = "100%";
            content = {
              type = "filesystem";
              format = "ext4";
              mountpoint = "/";
            };
          };
        };
      };
    };
  };
}
