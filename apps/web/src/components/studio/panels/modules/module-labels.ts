export function getCategoryLabel(category?: string) {
  if (!category || category === "unspecified") return "Uncategorized";
  if (category === "ci-cd") return "CI/CD";
  return category.charAt(0).toUpperCase() + category.slice(1);
}

export function getSourceLabel(type?: string) {
  switch (type) {
    case "builtin":
      return "Built-in";
    case "flake-input":
      return "Flake Input";
    case "local":
      return "Local";
    case "registry":
      return "Registry";
    default:
      return type || "Unspecified";
  }
}
