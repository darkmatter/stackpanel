import { createElement, type ComponentType } from "react";
import { DynamicIcon, iconNames, type IconName } from "lucide-react/dynamic.mjs";
import { Boxes, type LucideProps } from "lucide-react";

// Lucide publishes canonical names and aliases in kebab-case. Comparing
// without separators also handles PascalCase acronyms and numeric segments.
const normalize = (name: string) => name.replaceAll("-", "").toLowerCase();
const names = new Map(iconNames.map((name) => [normalize(name), name] as const));
const components = new Map<IconName, ComponentType<LucideProps>>();

/** Resolve an icon by its lucide icon name string (from panel metadata) */
export function getModuleIconByName(iconName?: string | null): ComponentType<LucideProps> {
  const name = typeof iconName === "string" && names.get(normalize(iconName.trim()));
  if (!name) return Boxes;
  const cached = components.get(name);
  if (cached) return cached;
  const ModuleIcon = (props: LucideProps) =>
    createElement(DynamicIcon, { ...props, name, fallback: () => createElement(Boxes, props) });
  components.set(name, ModuleIcon);
  return ModuleIcon;
}
