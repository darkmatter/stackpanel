{...}: {
  mkgoApp = { pname, version, src, vendorSrc ? null, ... }:
    let
      goBuildFlags = [
        "-ldflags"
        ''
          -X "github.com/darkmatter/stackpanel-go/common.Version=${version}"
        ''
      ];
    in
    import ../lib/apps/go-app.nix {
      inherit pname version src vendorSrc;
      inherit goBuildFlags;
    };
}