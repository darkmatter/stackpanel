{
  pkgs,
  lib ? pkgs.lib,
}:
let
  serviceCommand = import ./service-command.nix { inherit lib pkgs; };
  marker = ".stack/state/proxy/example/server.identity";
  verify = pkgs.writeText "verify-proxy-service.py" ''
    import fcntl, os, stat
    info = os.fstat(9)
    assert os.path.samestat(info, os.stat("${marker}"))
    assert stat.S_ISREG(info.st_mode) and stat.S_IMODE(info.st_mode) == 0o600
    assert info.st_uid == os.geteuid() and info.st_nlink == 1
    assert (fcntl.fcntl(9, fcntl.F_GETFL) & os.O_ACCMODE) == os.O_RDONLY
  '';
  service = {
    module = "example";
    proxy.enable = true;
    command = ''
      touch service-started
      exec ${pkgs.python3}/bin/python3 -I ${verify}
    '';
  };
  launch = serviceCommand "server" service;
in
assert serviceCommand "server" (service // { module = null; }) == service.command;
assert serviceCommand "server" (service // { proxy.enable = false; }) == service.command;
assert !(builtins.tryEval (serviceCommand "../escape" service)).success;
pkgs.runCommand "stackpanel-proxy-service-launch" { } ''
  mkdir project other
  cd project
  export STACKPANEL_ROOT="$PWD"
  ( ${launch} )
  ( ${launch} )  # restart: the same marker must remain usable

  reject() {
    rm -f service-started
    if ( ${launch} ); then echo 'unsafe launch succeeded' >&2; exit 1; fi
    test ! -e service-started
  }
  marker=${lib.escapeShellArg marker}
  chmod 644 "$marker"
  reject
  chmod 600 "$marker"
  ln "$marker" hardlink
  reject
  rm "$marker"
  ln -s "$PWD/hardlink" "$marker"
  reject
  rm "$marker"
  mkfifo "$marker"
  reject
  mv .stack stack-real
  ln -s stack-real .stack
  reject
  rm .stack
  STACKPANEL_ROOT="$PWD/../other" reject
  test ! -e ../other/.stack && test ! -e .stack
  touch "$out"
''
