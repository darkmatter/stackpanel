"use client";

import { useMemo, useState } from "react";
import {
  Combobox,
  ComboboxChip,
  ComboboxChips,
  ComboboxChipsInput,
  ComboboxContent,
  ComboboxEmpty,
  ComboboxItem,
  ComboboxList,
  ComboboxValue,
  useComboboxAnchor,
} from "@/components/ui/combobox";

interface MultiValueComboboxProps {
  value: string[];
  onChange: (value: string[]) => void;
  options: string[];
  placeholder?: string;
  allowCreate?: boolean;
  leadingOption?: {
    label: string;
    value: string;
    onSelect: () => void;
  };
}

export function MultiValueCombobox({
  value,
  onChange,
  options,
  placeholder,
  allowCreate = false,
  leadingOption,
}: MultiValueComboboxProps) {
  const anchor = useComboboxAnchor();
  const [query, setQuery] = useState("");

  const items = useMemo(() => {
    const normalizedQuery = query.trim();
    const base = Array.from(new Set(options))
      .filter((item) => !value.includes(item))
      .sort((a, b) => a.localeCompare(b));
    const withLeading = leadingOption ? [leadingOption.value, ...base] : base;
    if (!allowCreate || !normalizedQuery) return withLeading;
    if (
      value.some((item) => item.toLowerCase() === normalizedQuery.toLowerCase()) ||
      base.some((item) => item.toLowerCase() === normalizedQuery.toLowerCase())
    ) {
      return withLeading;
    }
    return leadingOption
      ? [leadingOption.value, normalizedQuery, ...base]
      : [normalizedQuery, ...base];
  }, [allowCreate, leadingOption, options, query, value]);

  return (
    <Combobox
      multiple
      autoHighlight
      items={items}
      value={value}
      itemToStringLabel={(item) => item === leadingOption?.value ? leadingOption.label : item}
      filter={(item, nextQuery) => {
        if (item === leadingOption?.value) return true;
        return item.toLowerCase().includes(nextQuery.toLowerCase());
      }}
      onValueChange={(next) => {
        const nextValues = Array.isArray(next) ? next : [];
        if (leadingOption && nextValues.includes(leadingOption.value)) {
          leadingOption.onSelect();
          return;
        }
        onChange(nextValues);
      }}
    >
      <ComboboxChips ref={anchor} className="w-full">
        <ComboboxValue>
          {(values) => (
            <>
              {values.map((item: string) => (
                <ComboboxChip key={item}>{item}</ComboboxChip>
              ))}
              <ComboboxChipsInput placeholder={placeholder} onChange={(e) => setQuery(e.target.value)} />
            </>
          )}
        </ComboboxValue>
      </ComboboxChips>
      <ComboboxContent anchor={anchor}>
        <ComboboxEmpty>No matches found.</ComboboxEmpty>
        <ComboboxList>
          {(item: string) => (
            <ComboboxItem key={item} value={item}>
              {item === leadingOption?.value ? leadingOption.label : item}
            </ComboboxItem>
          )}
        </ComboboxList>
      </ComboboxContent>
    </Combobox>
  );
}
