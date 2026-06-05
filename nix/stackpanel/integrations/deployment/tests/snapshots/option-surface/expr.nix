{
  deploymentAlchemyOptionNames,
  deploymentOptionNames,
  topLevelOptionNames,
  ...
}:
{
  topLevelHasAlchemy = builtins.elem "alchemy" topLevelOptionNames;
  inherit deploymentOptionNames deploymentAlchemyOptionNames;
}
