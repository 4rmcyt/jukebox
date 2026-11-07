_: {
  virtualisation.podman.enable = true;
  virtualisation.oci-containers.backend = "podman";
  # Integrity comes from the digest pin below.
  virtualisation.containers.policy.default = [{type = "insecureAcceptAnything";}];

  # Rootful --userns=auto carves per-container ranges out of the "containers" subuid/subgid entry (podman-run(1)).
  users.users.containers = {
    isSystemUser = true;
    group = "containers";
    subUidRanges = [
      {
        startUid = 2147483647;
        count = 2147483648;
      }
    ];
    subGidRanges = [
      {
        startGid = 2147483647;
        count = 2147483648;
      }
    ];
  };
  users.groups.containers = {};

  virtualisation.oci-containers.containers.bgutil-pot = {
    # brainicism/bgutil-ytdlp-pot-provider:1.2.1, the version Music Assistant requires.
    image = "docker.io/brainicism/bgutil-ytdlp-pot-provider@sha256:7064546d70a58680aec236b50859c4fca065092d7ed462c85ea5d897b003095e";
    # Unauthenticated server: loopback only (published ports bypass the NixOS firewall).
    ports = ["127.0.0.1:4416:4416"];
    extraOptions = [
      "--init"
      "--userns=auto"
      "--read-only"
      "--tmpfs=/tmp"
      "--cap-drop=all"
      "--security-opt=no-new-privileges"
    ];
  };
}
