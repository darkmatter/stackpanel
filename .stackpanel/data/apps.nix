{
  docs = {
    description = "Documentation site";
    domain = "docs";
    environments = {
      dev = {
        name = "dev";
        variables = {
          PORT = {
            key = "PORT";
            type = 2;
            variable-id = "/apps/docs/port";
          };
        };
      };
      prod = {
        name = "prod";
        variables = {
          PORT = {
            key = "PORT";
            type = 2;
            variable-id = "/apps/docs/port";
          };
        };
      };
      staging = {
        name = "staging";
        variables = {
          PORT = {
            key = "PORT";
            type = 2;
            variable-id = "/apps/docs/port";
          };
        };
      };
    };
    name = "docs";
    path = "apps/docs";
    port = 3002;
    tasks = {
      build = {
        command = "bun run build";
        description = "Build documentation site";
        env = { };
        key = "build";
      };
      dev = {
        command = "bun run dev";
        description = "Start documentation dev server";
        env = { };
        key = "dev";
      };
    };
    type = "bun";
    variables = { };
  };
  server = {
    description = "Backend API server";
    name = "server";
    path = "apps/server";
    port = 3001;
    tasks = {
      build = {
        command = "bun run build";
        description = "Build API server";
        env = { };
        key = "build";
      };
      dev = {
        command = "bun run dev";
        description = "Start API server in development mode";
        env = { };
        key = "dev";
      };
      test = {
        command = "bun run test";
        description = "Run API tests";
        env = { };
        key = "test";
      };
    };
    type = "bun";
    variables = { };
  };
  stackpanel-go = {
    description = "Stackpanel CLI and agent (Go)";
    name = "stackpanel";
    path = "apps/stackpanel-go";
    tasks = {
      build = {
        command = "go build -o stackpanel ./cmd/stackpanel";
        description = "Build Go binary";
        env = { };
        key = "build";
      };
      test = {
        command = "go test ./...";
        description = "Run Go tests";
        env = { };
        key = "test";
      };
    };
    type = "go";
    variables = { };
  };
  web = {
    description = "Main web application (Next.js)";
    domain = "stackpanel";
    environments = {
      dev = {
        name = "dev";
        variables = {
          DOCS-PORT = {
            key = "DOCS_PORT";
            type = 2;
            variable-id = "/apps/docs/port";
          };
          OPENAI-API-KEY = {
            key = "OPENAI_API_KEY";
            type = 2;
            variable-id = "openai-api-key";
          };
          PORT = {
            key = "PORT";
            type = 2;
            variable-id = "/apps/web/port";
          };
        };
      };
    };
    name = "web";
    path = "apps/web";
    port = 3000;
    tasks = {
      build = {
        command = "bun run build";
        description = "Build for production";
        env = { };
        key = "build";
      };
      dev = {
        command = "bun run dev";
        description = "Start development server with hot reload";
        env = { };
        key = "dev";
      };
      test = {
        command = "bun run test";
        description = "Run test suite";
        env = { };
        key = "test";
      };
    };
    type = "bun";
    variables = { };
  };
}

