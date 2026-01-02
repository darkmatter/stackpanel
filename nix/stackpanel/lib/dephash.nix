# primitive functions for hashing files for change detection
{ lib }:
{
  hash = path: builtins.hashFile "sha256" path;

  changed = path: old: builtins.hashFile "sha256" path != old;
}
