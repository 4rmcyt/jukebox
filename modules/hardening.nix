# No preset applied: start from nix-mineral defaults and override per audited need.
{lib, ...}: {
  nix-mineral = {
    enable = true;

    # podman execs binaries from image layers under /var/lib/containers.
    filesystems.normal."/var/lib" = {
      enable = true;
      options."noexec" = false;
      options."exec" = true;
    };

    # podman bridge needs forwarding for the PO Token container to reach YouTube.
    settings.network.ip-forwarding = true;

    # DHCP reservation and FTD ACLs are keyed to the real NIC MAC.
    settings.network.random-mac = false;

    # Unattended box: a driver oops (i915/BT) shouldn't panic it into a hang.
    settings.kernel.oops-panic = false;

    # Default pulls Kicksecure's AutoEnable=false, leaving the speaker adapter off after boot.
    settings.etc.harden-bluetooth = false;

    # Disables X11/TCP/agent forwarding on sshd.
    extras.misc.ssh-hardening = true;

    # Closes su/console root password login that PermitRootLogin=no doesn't cover.
    extras.system.lock-root = true;

    # Re-audit against hosts/jukebox/facter.json once generated (thunderbolt varies by Tiny model).
    kernel-modules.disable = {
      bluetooth-related = false;
      # Unaudited — overlay (podman) and vfat (ESP) must stay loadable.
      unused-filesystems = false;
      # Unaudited — once broke nfs-server via sunrpc on homeserver.
      secureblue-additional = false;

      intelme-related = true;
      unused-network-protocols = true;
      firewire-related = true;
      thunderbolt-related = true;
      gnss-related = true;
      esp4-and-esp6 = true;
      xfrm-related = true;
      ipsec-related = true;
      l2tp-related = true;
      legacy-interfaces = true;
      kernel-debugging-related = true;
      cdrom-related = true;
      gpib-related = true;
      dvb-and-tv-receivers = true;
      automotive-related = true;
      rdma-related = true;
      legacy-digital-cameras = true;
      radio-tuners = true;
      remote-controls = true;
      joystick-drivers = true;
    };
  };

  # Max out mmap ASLR entropy (x86_64 ceiling is 32/16).
  boot.kernel.sysctl = {
    "vm.mmap_rnd_bits" = 32;
    "vm.mmap_rnd_compat_bits" = 16;
  };

  systemd.services = {
    # nscd still carries the full default capability set it never uses.
    nscd.serviceConfig = {
      CapabilityBoundingSet = lib.mkForce "";
      RestrictAddressFamilies = lib.mkDefault ["AF_INET" "AF_INET6" "AF_UNIX" "AF_NETLINK"];
      SystemCallFilter = lib.mkDefault ["@system-service"];
      SystemCallArchitectures = lib.mkDefault "native";
      ProtectClock = lib.mkDefault true;
      ProtectKernelLogs = lib.mkDefault true;
      ProtectKernelModules = lib.mkDefault true;
      ProtectKernelTunables = lib.mkDefault true;
      ProtectControlGroups = lib.mkDefault true;
      ProtectHostname = lib.mkDefault true;
      RestrictNamespaces = lib.mkDefault true;
      RestrictSUIDSGID = lib.mkDefault true;
      LockPersonality = lib.mkDefault true;
      RestrictRealtime = lib.mkDefault true;
      MemoryDenyWriteExecute = lib.mkDefault true;
      ProtectProc = lib.mkDefault "invisible";
      ProcSubset = lib.mkDefault "pid";
      UMask = lib.mkDefault "0077";
      RemoveIPC = lib.mkDefault true;
      PrivateUsers = lib.mkDefault true;
    };

    # Only directives SSH sessions can inherit safely: no ProtectSystem/ProtectKernelTunables/PrivateDevices (breaks remote activation).
    sshd.serviceConfig = {
      ProtectClock = lib.mkDefault true;
      ProtectKernelLogs = lib.mkDefault true;
      ProtectKernelModules = lib.mkDefault true;
      ProtectHostname = lib.mkDefault true;
      LockPersonality = lib.mkDefault true;
      RestrictRealtime = lib.mkDefault true;
      RemoveIPC = lib.mkDefault true;
      UMask = lib.mkDefault "0077";
    };

    # Upstream unit sets ProtectSystem/ProtectHome/MDWE/NNP; add the rest. AF_ALG: bluez crypto; no PrivateNetwork: BT sockets live in the init netns.
    bluetooth.serviceConfig = {
      RestrictAddressFamilies = ["AF_BLUETOOTH" "AF_UNIX" "AF_ALG" "AF_NETLINK"];
      ProtectKernelModules = true;
      ProtectKernelLogs = true;
      ProtectClock = true;
      ProtectHostname = true;
      ProtectProc = "invisible";
      LockPersonality = true;
      RestrictNamespaces = true;
      RestrictSUIDSGID = true;
      SystemCallArchitectures = "native";
      SystemCallFilter = "~@clock @cpu-emulation @debug @module @mount @obsolete @raw-io @reboot @swap";
      SystemCallErrorNumber = "EPERM";
      UMask = "0077";
    };
  };
}
