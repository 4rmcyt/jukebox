_: {
  sops = {
    defaultSopsFile = ../secrets/jukebox.yaml;
    # Host age identity derived from the SSH host key; pre-generated at install, see README.
    age.sshKeyPaths = ["/etc/ssh/ssh_host_ed25519_key"];
    # yescrypt hash for the admin account (sudo password).
    secrets.admin-password.neededForUsers = true;
  };
}
