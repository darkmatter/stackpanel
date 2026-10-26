# Copied from cachix/devenv src/modules/languages at a73c5b84c9527760f009232988466763068f9f61.
# `languages.` is rewritten to `stackpanel.languages.`. compat.nix forwards
# packages, env, and enterShell onto stackpanel.devshell.
# go and typescript are omitted; stackpanel maintains those.
{ ... }:
{
  imports = [
    ./compat.nix
    ./ansible.nix
    ./c.nix
    ./clojure.nix
    ./cplusplus.nix
    ./crystal.nix
    ./cue.nix
    ./dart.nix
    ./deno.nix
    ./dotnet.nix
    ./elixir.nix
    ./elm.nix
    ./erlang.nix
    ./fortran.nix
    ./gawk.nix
    ./gleam.nix
    ./hare.nix
    ./haskell.nix
    ./helm.nix
    ./idris.nix
    ./java.nix
    ./javascript.nix
    ./jsonnet.nix
    ./julia.nix
    ./kotlin.nix
    ./lean4.nix
    ./lobster.nix
    ./lua.nix
    ./nim.nix
    ./nix.nix
    ./ocaml.nix
    ./odin.nix
    ./opentofu.nix
    ./pascal.nix
    ./perl.nix
    ./php.nix
    ./pkl.nix
    ./purescript.nix
    ./python
    ./r.nix
    ./racket.nix
    ./raku.nix
    ./robotframework.nix
    ./ruby.nix
    ./rust.nix
    ./scala.nix
    ./shell.nix
    ./solidity.nix
    ./standardml.nix
    ./swift.nix
    ./terraform.nix
    ./texlive.nix
    ./typst.nix
    ./unison.nix
    ./v.nix
    ./vala.nix
    ./zig.nix
  ];
}
