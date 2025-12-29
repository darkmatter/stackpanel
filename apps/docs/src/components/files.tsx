"use client";

import { cva } from "class-variance-authority";
import { File as FileIcon, Folder as FolderIcon, FolderOpen } from "lucide-react";
import { type HTMLAttributes, type ReactNode, useState } from "react";
import { cn } from "../lib/cn";
import { Collapsible, CollapsibleContent, CollapsibleTrigger } from "./ui/collapsible";

const itemVariants = cva(
  "flex flex-row items-center gap-2 rounded-md px-2 py-1.5 text-sm hover:bg-fd-accent hover:text-fd-accent-foreground [&_svg]:size-4",
  {
    variants: {
      highlighted: {
        true: "bg-fd-primary/5 text-fd-primary border-l-2 border-fd-warning -ml-0.5 pl-2.5",
      },
    },
  },
);

export function Files({ className, ...props }: HTMLAttributes<HTMLDivElement>): React.ReactElement {
  return (
    <div
      className={cn(
        "not-prose rounded-md border bg-fd-card p-2 max-h-96 overflow-y-auto",
        className,
      )}
      {...props}
    >
      {props.children}
    </div>
  );
}

export interface FileProps extends HTMLAttributes<HTMLDivElement> {
  name: string;
  icon?: ReactNode;
  /**
   * Highlight this file
   */
  highlighted?: boolean;
}

export interface FolderProps extends HTMLAttributes<HTMLDivElement> {
  name: string;

  disabled?: boolean;

  /**
   * Highlight this folder
   */
  highlighted?: boolean;

  /**
   * Open folder by default
   *
   * @defaultValue false
   */
  defaultOpen?: boolean;
}

export function File({
  name,
  icon = <FileIcon />,
  className,
  highlighted,
  ...rest
}: FileProps): React.ReactElement {
  return (
    <div className={cn(itemVariants({ highlighted, className }))} {...rest}>
      {icon}
      {name}
    </div>
  );
}

export function Folder({
  name,
  defaultOpen = false,
  highlighted,
  ...props
}: FolderProps): React.ReactElement {
  const [open, setOpen] = useState(defaultOpen);

  return (
    <Collapsible open={open} onOpenChange={setOpen} {...props}>
      <CollapsibleTrigger className={cn(itemVariants({ highlighted, className: "w-full" }))}>
        {open ? <FolderOpen /> : <FolderIcon />}
        {name}
      </CollapsibleTrigger>
      <CollapsibleContent>
        <div className="ms-2 flex flex-col border-l ps-2">{props.children}</div>
      </CollapsibleContent>
    </Collapsible>
  );
}
