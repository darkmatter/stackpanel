import type { BaseLayoutProps } from "fumadocs-ui/layouts/shared";

export function baseOptions(): BaseLayoutProps {
  return {
    nav: {
      title: (
        <div className="flex items-center justify-center w-full flex-row flex-auto m-auto">
          <Image
            src="/light.png"
            alt="StackPanel"
            width={120}
            height={40}
            className="max-w-28 opacity-90 m-0 me-0 ml-2"
          />
        </div>
      ),
    },
  };
}

import { DocsLayout } from "fumadocs-ui/layouts/docs";
import { source } from "@/lib/source";
import type { ReactNode } from "react";
import Image from "next/image";
export default function Layout({ children }: { children: ReactNode }) {
  return (
    <DocsLayout
      {...baseOptions()}
      tree={source.pageTree}
      sidebar={{
        enabled: true,
      }}
      nav={{
        enabled: true,
        title: "StackPanel Docs",
        url: "/docs",
        transparentMode: "top",
      }}
    >
      {children}
    </DocsLayout>
  );
}
