"use client";

import { Input } from "@ui/input";
import { ToggleGroup, ToggleGroupItem } from "@ui/toggle-group";
import { Search } from "lucide-react";
import { VARIABLE_TYPES } from "../constants";
import { useVariablesUIStore } from "../store/variables-ui-store";

interface VariablesFilterProps {
  filteredCount: number;
}

export function VariablesFilter({ filteredCount }: VariablesFilterProps) {
  const searchQuery = useVariablesUIStore((state: any) => state.searchQuery);
  const setSearchQuery = useVariablesUIStore(
    (state: any) => state.setSearchQuery,
  );
  const selectedType = useVariablesUIStore((state: any) => state.selectedType);
  const setSelectedType = useVariablesUIStore(
    (state: any) => state.setSelectedType,
  );
  return (
    <div className="flex flex-col gap-4">
      <div className="flex flex-wrap items-center gap-3">
        <div className="relative flex-1 min-w-60">
          <Search className="absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-muted-foreground" />
          <Input
            placeholder="Search variables..."
            value={searchQuery}
            onChange={(e) => setSearchQuery(e.target.value)}
            className="pl-9"
          />
        </div>
        <ToggleGroup
          type="single"
          variant="outline"
          value={selectedType}
          onValueChange={(value) => {
            setSelectedType((value || "all") as any);
          }}
          className="flex-wrap"
        >
          <ToggleGroupItem value="all" size="sm" className="text-[11px] px-2">
            All
          </ToggleGroupItem>
          {VARIABLE_TYPES.map((type) => {
            const TypeIcon = type.icon;
            return (
              <ToggleGroupItem
                key={type.value}
                value={type.value}
                size="sm"
                className="text-[11px] px-6"
              >
                <TypeIcon className="size-4 opacity-80 shrink-0" />
                {type.label}
              </ToggleGroupItem>
            );
          })}
        </ToggleGroup>
        <div className="text-xs text-muted-foreground">
          {filteredCount} result{filteredCount === 1 ? "" : "s"}
        </div>
      </div>
    </div>
  );
}
