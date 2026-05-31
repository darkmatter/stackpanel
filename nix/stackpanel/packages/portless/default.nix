{
  lib,
  pkgs,
  ...
}:

pkgs.stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "portless";
  version = "0.13.0";

  src = pkgs.fetchurl {
    url = "https://registry.npmjs.org/portless/-/portless-${finalAttrs.version}.tgz";
    hash = "sha512-PxMZ5BHH+ZZi9rTq4T8m003aZxh56qI0aBdNsxLn7jrTtvNJYBWYD3lc5PuQrom/aVh6z8iLb+tKUI6b7QNYQw==";
  };

  nativeBuildInputs = [
    pkgs.makeWrapper
  ];

  installPhase = ''
    runHook preInstall

    mkdir -p "$out/lib/node_modules/portless" "$out/bin"
    cp -R . "$out/lib/node_modules/portless"

    makeWrapper ${pkgs.nodejs_22}/bin/node "$out/bin/portless" \
      --add-flags "$out/lib/node_modules/portless/dist/cli.js"

    runHook postInstall
  '';

  meta = {
    description = "Replace port numbers with stable, named localhost URLs";
    homepage = "https://portless.sh";
    license = lib.licenses.asl20;
    mainProgram = "portless";
    platforms = lib.platforms.darwin ++ lib.platforms.linux;
  };
})
