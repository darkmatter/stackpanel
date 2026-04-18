let
  config = {
    stackpanel = {
      apps = {
        web = {
          name = "web";
          description = "Main web application";
          path = "apps/web";
        };
      };
    };
  };
  codegen = import ./config-package.nix { inherit config; };
in
{
  testCodegen = {
    expr = codegen.generatedFiles."packages/gen/env/package.json".content;
    expected = {
      name = "web";
      description = "Main web application";
      path = "apps/web";
    };
  };
}
