{ lib, pkgs }:
name: svc:
if !(svc.proxy.enable or false) || (svc.module or null) == null then
  svc.command
else
  let
    validComponent = s: builtins.match "[A-Za-z0-9._~-]+" s != null && s != "." && s != "..";
  in
  assert lib.assertMsg (
    validComponent svc.module && validComponent name
  ) "process-compose: proxied service and module IDs must be single URI-unreserved path components";
  "exec "
  + lib.escapeShellArgs [
    "${pkgs.python3}/bin/python3"
    "-I"
    "${./proxy-service.py}"
    svc.module
    name
    "${pkgs.bash}/bin/bash"
    "${pkgs.writeText "stackpanel-proxied-service.sh" svc.command}"
  ]
