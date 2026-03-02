{
  config,
  org ? "acme",
  name ? "example-project",
}:
# syntax: json
''
  {
    "name": "${config.stackpanel.github}/${name}",
    "version": "0.1.0",
    "private": true,
    "type": "module",
    "workspaces": [
      "apps/*",
      "packages/*",
      "packages/gen/*"
    ],
    "scripts": {}
  }
''
