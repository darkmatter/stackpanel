import { Code2, GitBranch, Package, Sparkles } from "lucide-react";

export function DevExperienceSection() {
  const features = [
    {
      icon: Code2,
      title: "Nix Flakes & Devenv",
      description:
        "A managed nix flake based on devenv. Enable toolchains, git hooks, and dev environments through the UI.",
    },
    {
      icon: Package,
      title: "create-app Command",
      description:
        "Pre-configured to use your stack's tools. Creates a GitHub repo with turborepo template, CI/CD, and all the scaffolding.",
    },
    {
      icon: GitBranch,
      title: "x install Integration",
      description:
        "Run x install neon to add Neon to your stack with full scaffolding. Works for dozens of services.",
    },
    {
      icon: Sparkles,
      title: "Zero Install Tools",
      description:
        "Scripts and tools available in your PATH automatically. No manual installation required for your team.",
    },
  ];

  return (
    <section className="border-border border-b" id="devex">
      <div className="mx-auto max-w-7xl px-4 py-24 sm:px-6 lg:px-8">
        <div className="text-center">
          <p className="font-medium text-accent text-sm">Developer Experience</p>
          <h2 className="mt-4 text-balance font-bold text-3xl text-foreground sm:text-4xl">
            Local development, supercharged
          </h2>
          <p className="mx-auto mt-4 max-w-2xl text-pretty text-muted-foreground">
            The StackPanel isn&apos;t just for infrastructure. It&apos;s your
            team&apos;s local development hub with managed dev shells, toolchains, and
            scripts.
          </p>
        </div>

        <div className="mt-16 grid gap-px overflow-hidden rounded-xl border border-border bg-border sm:grid-cols-2">
          {features.map((feature, index) => (
            <div
              className={`bg-card p-8 ${index === 0 ? "sm:rounded-tl-xl" : ""} ${index === 1 ? "sm:rounded-tr-xl" : ""} ${index === 2 ? "sm:rounded-bl-xl" : ""} ${index === 3 ? "sm:rounded-br-xl" : ""}`}
              key={feature.title}
            >
              <div className="flex h-10 w-10 items-center justify-center rounded-lg bg-accent/10">
                <feature.icon className="h-5 w-5 text-accent" />
              </div>
              <h3 className="mt-4 font-semibold text-foreground text-lg">
                {feature.title}
              </h3>
              <p className="mt-2 text-muted-foreground text-sm leading-relaxed">
                {feature.description}
              </p>
            </div>
          ))}
        </div>
      </div>
    </section>
  );
}
