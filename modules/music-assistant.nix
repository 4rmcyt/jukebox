_: {
  services.music-assistant = {
    enable = true;
    providers = [
      "ytmusic"
      "party"
      "music_quiz"
      "squeezelite"
      "lrclib"
      "milkdrop_visualizer"
    ];
  };

  # Web UI + Party guest view only; stream/slimproto ports stay closed, squeezelite connects over loopback.
  networking.firewall.allowedTCPPorts = [8095];

  # Upstream module already sets DynamicUser, empty capabilities, @system-service filter, Protect*.
  systemd.services.music-assistant = {
    wants = ["podman-bgutil-pot.service"];
    after = ["podman-bgutil-pot.service"];
    serviceConfig = {
      NoNewPrivileges = true;
      PrivateDevices = true;
      PrivateTmp = true;
      PrivateUsers = true;
      ProtectSystem = "strict";
      RemoveIPC = true;
      SystemCallErrorNumber = "EPERM";
      # MDWE stays off upstream (deno JIT); SocketBindAllow omitted: zeroconf/plugins bind undocumented ports.
    };
  };
}
