{
  docs = {
    description = "Documentation site";
    domain = "docs";
    environments = {
      dev = {
        name = "dev";
        variables = {
          HELLO = {
            key = "HELLO";
            type = 1;
            value = "world";
            variable-id = "";
          };
          POSTGRES-URL = {
            key = "POSTGRES_URL";
            type = 1;
            variable-id = "";
          };
        };
      };
      prod = {
        name = "prod";
        variables = {
          HELLO = {
            key = "HELLO";
            type = 1;
            value = "world";
            variable-id = "";
          };
          POSTGRES-URL = {
            key = "POSTGRES_URL";
            type = 1;
            variable-id = "";
          };
        };
      };
      staging = {
        name = "staging";
        variables = {
          HELLO = {
            key = "HELLO";
            type = 1;
            value = "world";
            variable-id = "";
          };
          POSTGRES-URL = {
            key = "POSTGRES_URL";
            type = 1;
            variable-id = "";
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
    variables = {
      APP-URL = {
        environments = [ "dev" ];
        variable-id = "APP_URL";
      };
      POSTGRES-URL = {
        environments = {
          "0" = {
            name = "0";
            variables = { };
          };
          dev = {
            name = "dev";
            variables = { };
          };
          prod = {
            name = "prod";
            variables = { };
          };
          staging = {
            name = "staging";
            variables = { };
          };
        };
        key = "POSTGRES_URL";
        type = 0;
        variable-id = null;
      };
    };
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
    variables = {
      AUTH-SECRET = {
        environments = [ "dev" ];
        variable-id = "AUTH_SECRET";
      };
      DATABASE-URL = {
        environments = [ "dev" ];
        variable-id = "DATABASE_URL";
      };
      REDIS-URL = {
        environments = [ "dev" ];
        variable-id = "REDIS_URL";
      };
      STRIPE-SECRET-KEY = {
        environments = [ "dev" ];
        variable-id = "STRIPE_SECRET_KEY";
      };
    };
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
    variables = {
      API-URL = {
        environments = [ "dev" ];
        variable-id = "API_URL";
      };
      APP-URL = {
        environments = [ "dev" ];
        variable-id = "APP_URL";
      };
      AUTH-SECRET = {
        environments = [ "dev" ];
        variable-id = "AUTH_SECRET";
      };
      DATABASE-URL = {
        environments = [ "dev" ];
        variable-id = "DATABASE_URL";
      };
    };
  };
}
