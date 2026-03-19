"use client";

import { useState } from "react";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import {
  AlertTriangle,
  Pencil,
  Plus,
  Save,
  Trash2,
  Users,
  X,
} from "lucide-react";
import { MultiValueCombobox } from "../multi-value-combobox";

interface RecipientGroupsTableProps {
  recipientGroups: Record<string, { recipients: string[] }>;
  recipientNames: string[];
  onAddGroup: (name: string, recipients: string[]) => Promise<void>;
  onRemoveGroup: (name: string) => Promise<void>;
  onUpdateGroup: (name: string, recipients: string[]) => Promise<void>;
}

export function RecipientGroupsTable({
  recipientGroups,
  recipientNames,
  onAddGroup,
  onRemoveGroup,
  onUpdateGroup,
}: RecipientGroupsTableProps) {
  const [groupName, setGroupName] = useState("");
  const [groupRecipients, setGroupRecipients] = useState<string[]>([]);
  const [editingGroupName, setEditingGroupName] = useState<string | null>(null);
  const [editingGroupRecipients, setEditingGroupRecipients] = useState<string[]>(
    [],
  );

  const sortedGroups = Object.entries(recipientGroups).sort(([a], [b]) =>
    a.localeCompare(b),
  );
  const recipientGroupCount = sortedGroups.length;

  const handleAdd = async () => {
    await onAddGroup(groupName, groupRecipients);
    setGroupName("");
    setGroupRecipients([]);
  };

  const handleUpdate = async () => {
    if (editingGroupName) {
      await onUpdateGroup(editingGroupName, editingGroupRecipients);
      setEditingGroupName(null);
      setEditingGroupRecipients([]);
    }
  };

  const beginEditGroup = (name: string) => {
    setEditingGroupName(name);
    setEditingGroupRecipients(recipientGroups[name]?.recipients ?? []);
  };

  return (
    <Card>
      <CardHeader>
        <CardTitle className="text-base flex items-center gap-2">
          <Users className="h-4 w-4" />
          Recipient Groups{" "}
          <Badge variant="secondary">{recipientGroupCount}</Badge>
        </CardTitle>
        <CardDescription>
          Reusable named sets of recipients for creation rules.
        </CardDescription>
      </CardHeader>
      <CardContent className="space-y-4">
        <div className="rounded-lg border bg-muted/20 p-4 space-y-3">
          <div className="grid gap-3 md:grid-cols-2">
            <div className="space-y-1.5">
              <Label>Group name</Label>
              <Input
                value={groupName}
                onChange={(e) => setGroupName(e.target.value)}
                placeholder="e.g. dev-team"
              />
            </div>
            <div className="space-y-1.5">
              <Label>Recipients</Label>
              <MultiValueCombobox
                value={groupRecipients}
                onChange={setGroupRecipients}
                options={recipientNames}
                placeholder="Select recipients..."
                leadingOption={
                  recipientNames.length > 0
                    ? {
                        label: "Add all recipients",
                        value: "__all__",
                        onSelect: () =>
                          setGroupRecipients(
                            Array.from(new Set(recipientNames)).sort((a, b) =>
                              a.localeCompare(b),
                            ),
                          ),
                      }
                    : undefined
                }
              />
            </div>
          </div>
          <Button size="sm" onClick={handleAdd}>
            <Plus className="mr-1 h-3.5 w-3.5" />
            Add recipient group
          </Button>
        </div>

        <div className="space-y-2">
          {sortedGroups.length === 0 ? (
            <div className="rounded-md border border-amber-500/30 bg-amber-500/5 p-3 text-sm text-muted-foreground flex items-start gap-2">
              <AlertTriangle className="h-4 w-4 text-amber-500 mt-0.5" />
              <div>
                No recipient groups configured. Rules can still reference
                recipients directly, but groups make anchors reusable.
              </div>
            </div>
          ) : (
            sortedGroups.map(([name, group]) => (
              <div key={name} className="rounded-md border px-3 py-2 space-y-3">
                <div>
                  <div className="flex items-center justify-between gap-3">
                    <div className="text-sm font-medium font-mono">{name}</div>
                    <div className="flex items-center gap-1">
                      <Button
                        variant="ghost"
                        size="icon"
                        className="h-7 w-7"
                        onClick={() => beginEditGroup(name)}
                      >
                        <Pencil className="h-3.5 w-3.5" />
                      </Button>
                      <Button
                        variant="ghost"
                        size="icon"
                        className="h-7 w-7 text-destructive"
                        onClick={() => onRemoveGroup(name)}
                      >
                        <Trash2 className="h-3.5 w-3.5" />
                      </Button>
                    </div>
                  </div>
                  <div className="flex gap-1 flex-wrap mt-1">
                    {(group.recipients ?? []).map((recipient) => (
                      <Badge key={`${name}-${recipient}`} variant="secondary">
                        {recipient}
                      </Badge>
                    ))}
                  </div>
                </div>
                {editingGroupName === name ? (
                  <div className="rounded-lg border bg-muted/20 p-3 space-y-3">
                    <MultiValueCombobox
                      value={editingGroupRecipients}
                      onChange={setEditingGroupRecipients}
                      options={recipientNames}
                      placeholder="Select recipients..."
                    />
                    <div className="flex items-center gap-2">
                      <Button size="sm" onClick={handleUpdate}>
                        <Save className="mr-1 h-3.5 w-3.5" />
                        Save
                      </Button>
                      <Button
                        variant="ghost"
                        size="sm"
                        onClick={() => setEditingGroupName(null)}
                      >
                        <X className="mr-1 h-3.5 w-3.5" />
                        Cancel
                      </Button>
                    </div>
                  </div>
                ) : null}
              </div>
            ))
          )}
        </div>
      </CardContent>
    </Card>
  );
}
