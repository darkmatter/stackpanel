import { Link } from "@tanstack/react-router";
import { Github, Twitter } from "lucide-react";

export function Footer() {
  const links = {
    product: [
      { label: "Features", href: "#features" },
      { label: "Infrastructure", href: "#infrastructure" },
      { label: "DevEx", href: "#devex" },
      { label: "Pricing", href: "#pricing" },
    ],
    resources: [
      { label: "Documentation", href: "#" },
      { label: "API Reference", href: "#" },
      { label: "Changelog", href: "#" },
      { label: "Status", href: "#" },
    ],
    company: [
      { label: "About", href: "#" },
      { label: "Blog", href: "#" },
      { label: "Careers", href: "#" },
      { label: "Contact", href: "#" },
    ],
    legal: [
      { label: "Privacy", href: "#" },
      { label: "Terms", href: "#" },
      { label: "Security", href: "#" },
    ],
  };

  return (
    <footer className="border-border border-t bg-secondary/20">
      <div className="mx-auto max-w-7xl px-4 py-12 sm:px-6 lg:px-8 lg:py-16">
        <div className="grid gap-8 sm:grid-cols-2 lg:grid-cols-5">
          <div className="lg:col-span-1">
            <Link className="flex items-center gap-2" to="/">
              <div className="flex h-8 w-8 items-center justify-center rounded-lg bg-accent">
                <span className="font-bold text-accent-foreground text-sm">SP</span>
              </div>
              <span className="font-semibold text-foreground text-lg">StackPanel</span>
            </Link>
            <p className="mt-4 text-muted-foreground text-sm">
              Your entire company, one panel.
            </p>
            <div className="mt-4 flex gap-4">
              <a
                className="text-muted-foreground transition-colors hover:text-foreground"
                href="https://github.com"
                rel="noopener noreferrer"
                target="_blank"
              >
                <Github className="h-5 w-5" />
                <span className="sr-only">GitHub</span>
              </a>
              <a
                className="text-muted-foreground transition-colors hover:text-foreground"
                href="https://twitter.com"
                rel="noopener noreferrer"
                target="_blank"
              >
                <Twitter className="h-5 w-5" />
                <span className="sr-only">Twitter</span>
              </a>
            </div>
          </div>

          {Object.entries(links).map(([category, items]) => (
            <div key={category}>
              <h3 className="font-semibold text-foreground text-sm capitalize">
                {category}
              </h3>
              <ul className="mt-4 space-y-3">
                {items.map((item) => (
                  <li key={item.label}>
                    <a
                      className="text-muted-foreground text-sm transition-colors hover:text-foreground"
                      href={item.href}
                    >
                      {item.label}
                    </a>
                  </li>
                ))}
              </ul>
            </div>
          ))}
        </div>

        <div className="mt-12 border-border border-t pt-8">
          <p className="text-center text-muted-foreground text-sm">
            © {new Date().getFullYear()} StackPanel. All rights reserved.
          </p>
        </div>
      </div>
    </footer>
  );
}
