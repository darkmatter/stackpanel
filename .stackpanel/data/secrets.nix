{
  backend = "chamber";
  codegen = {
    typescript = {
      directory = "packages/env/src/generated";
      language = "CODEGEN_LANGUAGE_TYPESCRIPT";
      name = "env";
    };
  };
  enable = true;
  environments = { };
  input-directory = ".stackpanel/secrets";
  secrets-dir = ".stackpanel/secrets/vars";
  system-keys = [ ];
}

