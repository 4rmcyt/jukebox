# Schema reference for inputs.private.lib.office — NOT imported anywhere; real values and secrets/jukebox.yaml live in the private repo.
{
  timeZone = "Etc/UTC";
  adminKeys = ["ssh-ed25519 AAAA... admin@workstation"];
  speakerMac = "AA:BB:CC:DD:EE:FF";
  workDays = ["Mon" "Tue" "Wed" "Thu" "Fri"];
  fqdn = "jukebox.example.com";
  acmeEmail = "it@example.com";
  adminNets = ["192.0.2.0/28"];

  bridge = {
    enable = true;
    tenantId = "00000000-0000-0000-0000-000000000000";
    clientId = "00000000-0000-0000-0000-000000000000";
    teamId = "00000000-0000-0000-0000-000000000000";
    channelId = "19:00000000000000000000000000000000@thread.tacv2";
    adminIds = ["00000000-0000-0000-0000-000000000000"];
    # Optional, default 90: days the per-person request/play log is kept.
    retentionDays = 90;
  };
}
