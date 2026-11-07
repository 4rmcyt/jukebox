_: {
  disko.devices.disk.main = {
    type = "disk";
    device = "/dev/nvme0n1";
    content = {
      type = "gpt";
      partitions = {
        ESP = {
          size = "1G";
          type = "EF00";
          content = {
            type = "filesystem";
            format = "vfat";
            mountpoint = "/boot";
            mountOptions = ["umask=0077"];
          };
        };
        luks = {
          size = "100%";
          content = {
            type = "luks";
            name = "cryptroot";
            # disko prompts for the recovery passphrase at install; the TPM2 slot is enrolled after first boot.
            settings = {
              allowDiscards = true;
              crypttabExtraOpts = ["tpm2-device=auto"];
            };
            content = {
              type = "filesystem";
              format = "ext4";
              mountpoint = "/";
              mountOptions = ["noatime"];
            };
          };
        };
      };
    };
  };
}
