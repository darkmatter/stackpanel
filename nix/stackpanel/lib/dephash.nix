# primitive functions for hashing files for change detection
_: {
  hash = path: builtins.hashFile "sha256" path;

  changed = path: old: builtins.hashFile "sha256" path != old;
}
