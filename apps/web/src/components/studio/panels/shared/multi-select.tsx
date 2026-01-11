"use client";

import { Checkbox } from "@/components/ui/checkbox";
import { Label } from "@/components/ui/label";

interface SelectableItem {
  id: string;
  name: string;
}

interface MultiSelectProps<T extends SelectableItem> {
  label: string;
  items: T[];
  selectedIds: string[];
  onSelectionChange: (ids: string[]) => void;
  renderItem: (item: T) => React.ReactNode;
}

export function MultiSelect<T extends SelectableItem>({
  label,
  items,
  selectedIds,
  onSelectionChange,
  renderItem,
}: MultiSelectProps<T>) {
  const toggleItem = (id: string) => {
    if (selectedIds.includes(id)) {
      onSelectionChange(selectedIds.filter((i) => i !== id));
    } else {
      onSelectionChange([...selectedIds, id]);
    }
  };

  return (
    <div className="space-y-2">
      <Label>{label}</Label>
      <div className="max-h-40 space-y-1 overflow-y-auto rounded-md border border-border bg-secondary/30 p-2">
        {items.length === 0 ? (
          <p className="py-2 text-center text-muted-foreground text-xs">
            No {label.toLowerCase()} available
          </p>
        ) : (
          items.map((item) => (
            <div
              key={item.id}
              className="flex items-center gap-2 rounded-md px-2 py-1.5 hover:bg-secondary/50"
            >
              <Checkbox
                id={`select-${item.id}`}
                checked={selectedIds.includes(item.id)}
                onCheckedChange={() => toggleItem(item.id)}
              />
              <label
                htmlFor={`select-${item.id}`}
                className="flex-1 cursor-pointer text-sm"
              >
                {renderItem(item)}
              </label>
            </div>
          ))
        )}
      </div>
      {selectedIds.length > 0 && (
        <p className="text-muted-foreground text-xs">
          {selectedIds.length} selected
        </p>
      )}
    </div>
  );
}
