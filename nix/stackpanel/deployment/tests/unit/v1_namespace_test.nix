{
  deploymentOptionNames,
  topLevelOptionNames,
  ...
}:
[
  {
    name = "deployment option namespace exposes alchemy";
    actual = builtins.elem "alchemy" deploymentOptionNames;
    expected = true;
  }
  {
    name = "top-level option namespace removes alchemy";
    actual = builtins.elem "alchemy" topLevelOptionNames;
    expected = false;
  }
]
