{python3Packages}:
python3Packages.buildPythonApplication {
  pname = "jukebox-bridge";
  version = "0.1.0";
  pyproject = true;
  src = ./.;

  build-system = [python3Packages.setuptools];
  dependencies = with python3Packages; [
    aiohttp
    msal
    music-assistant-client
  ];

  meta.mainProgram = "jukebox-bridge";
}
