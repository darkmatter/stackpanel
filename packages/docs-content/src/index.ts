import variablesGuide from "../content/guides/variables.mdx?raw";

export type GuideEntry = {
  slug: string;
  title: string;
  description?: string;
  content: string;
};

export const guides = {
  variables: {
    slug: "guides/variables",
    title: "Variables",
    description: "Variables in StackPanel",
    content: variablesGuide,
  },
} satisfies Record<string, GuideEntry>;
