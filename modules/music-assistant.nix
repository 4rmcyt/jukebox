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
      # MCP on /mcp/v1 of the MA webserver; permissions and access in docs/security.md §8.6.
      "fastmcp_server"
    ];
  };

  # No firewall ports: clients reach MA only through Caddy (modules/caddy.nix); MA binds 127.0.0.1 (set in its UI).

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
