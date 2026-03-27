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
  Wand2,
  X,
} from "lucide-react";
import { MultiValueCombobox } from "../multi-value-combobox";

export interface CreationRule {
  "path-regex"?: string;
  recipients?: string[];
  "recipient-groups"?: string[];
}

interface CreationRulesTableProps {
  creationRules: CreationRule[];
  recipientNames: string[];
  recipientGroupNames: string[];
  onAddRule: (rule: CreationRule) => Promise<void>;
  onRemoveRule: (index: number) => Promise<void>;
  onUpdateRule: (index: number, rule: CreationRule) => Promise<void>;
}

export function CreationRulesTable({
  creationRules,
  recipientNames,
  recipientGroupNames,
  onAddRule,
  onRemoveRule,
  onUpdateRule,
}: CreationRulesTableProps) {
  const [ruleRegex, setRuleRegex] = useState("");
  const [ruleRecipients, setRuleRecipients] = useState<string[]>([]);
  const [ruleGroups, setRuleGroups] = useState<string[]>([]);

  const [editingRuleIndex, setEditingRuleIndex] = useState<number | null>(null);
  const [editingRuleRegex, setEditingRuleRegex] = useState("");
  const [editingRuleRecipients, setEditingRuleRecipients] = useState<string[]>(
    [],
  );
  const [editingRuleGroups, setEditingRuleGroups] = useState<string[]>([]);

  const handleAdd = async () => {
    await onAddRule({
      "path-regex": ruleRegex,
      recipients: ruleRecipients,
      "recipient-groups": ruleGroups,
    });
    setRuleRegex("");
    setRuleRecipients([]);
    setRuleGroups([]);
  };

  const handleUpdate = async () => {
    if (editingRuleIndex !== null) {
      await onUpdateRule(editingRuleIndex, {
        "path-regex": editingRuleRegex,
        recipients: editingRuleRecipients,
        "recipient-groups": editingRuleGroups,
      });
      setEditingRuleIndex(null);
      setEditingRuleRegex("");
      setEditingRuleRecipients([]);
      setEditingRuleGroups([]);
    }
  };

  const beginEditRule = (rule: CreationRule, index: number) => {
    setEditingRuleIndex(index);
    setEditingRuleRegex(rule["path-regex"] ?? "");
    setEditingRuleRecipients(rule.recipients ?? []);
    setEditingRuleGroups(rule["recipient-groups"] ?? []);
  };

  const creationRuleCount = creationRules.length;

  return (
    <Card>
      <CardHeader>
        <CardTitle className="text-base flex items-center gap-2">
          <Wand2 className="h-4 w-4" />
          Creation Rules <Badge variant="secondary">{creationRuleCount}</Badge>
        </CardTitle>
        <CardDescription>
          Rules are rendered directly into SOPS `creation_rules`.
        </CardDescription>
      </CardHeader>
      <CardContent className="space-y-4">
        <div className="rounded-lg border bg-muted/20 p-4 space-y-3">
          <div className="space-y-1.5">
            <Label>Path regex</Label>
            <Input
              value={ruleRegex}
              onChange={(e) => setRuleRegex(e.target.value)}
              placeholder="e.g. ^dev/web\.sops\.yaml$"
            />
            <p className="text-xs text-muted-foreground">
              The first matching rule wins in SOPS. A Stackpanel fallback rule
              is appended automatically.
            </p>
          </div>
          <div className="grid gap-3 md:grid-cols-2">
            <div className="space-y-1.5">
              <Label>Direct recipients</Label>
              <MultiValueCombobox
                value={ruleRecipients}
                onChange={setRuleRecipients}
                options={recipientNames}
                placeholder="Select recipients..."
              />
            </div>
            <div className="space-y-1.5">
              <Label>Recipient groups</Label>
              <MultiValueCombobox
                value={ruleGroups}
                onChange={setRuleGroups}
                options={recipientGroupNames}
                placeholder="Select recipient groups..."
              />
            </div>
          </div>
          <Button size="sm" onClick={handleAdd}>
            <Plus className="mr-1 h-3.5 w-3.5" />
            Add creation rule
          </Button>
        </div>

        <div className="space-y-2">
          {creationRules.length === 0 ? (
            <div className="rounded-md border border-amber-500/30 bg-amber-500/5 p-3 text-sm text-muted-foreground flex items-start gap-2">
              <AlertTriangle className="h-4 w-4 text-amber-500 mt-0.5" />
              <div>
                No creation rules configured. Add at least one rule so
                Stackpanel can generate `.stack/secrets/.sops.yaml`.
              </div>
            </div>
          ) : (
            creationRules.map((rule, index) => (
              <div
                key={`${rule["path-regex"]}-${index}`}
                className="rounded-md border px-3 py-2 space-y-3"
              >
                <div className="min-w-0">
                  <div className="flex items-start justify-between gap-3">
                    <div className="text-sm font-medium font-mono break-all">
                      {rule["path-regex"]}
                    </div>
                    <div className="flex items-center gap-1 shrink-0">
                      <Button
                        variant="ghost"
                        size="icon"
                        className="h-7 w-7"
                        onClick={() => beginEditRule(rule, index)}
                      >
                        <Pencil className="h-3.5 w-3.5" />
                      </Button>
                      <Button
                        variant="ghost"
                        size="icon"
                        className="h-7 w-7 text-destructive"
                        onClick={() => onRemoveRule(index)}
                      >
                        <Trash2 className="h-3.5 w-3.5" />
                      </Button>
                    </div>
                  </div>
                  <div className="flex gap-1 flex-wrap mt-2">
                    {(rule.recipients ?? []).map((recipient) => (
                      <Badge key={`${index}-r-${recipient}`} variant="outline">
                        {recipient}
                      </Badge>
                    ))}
                    {(rule["recipient-groups"] ?? []).map((group) => (
                      <Badge key={`${index}-g-${group}`} variant="secondary">
                        @{group}
                      </Badge>
                    ))}
                  </div>
                </div>
                {editingRuleIndex === index ? (
                  <div className="rounded-lg border bg-muted/20 p-3 space-y-3">
                    <Input
                      value={editingRuleRegex}
                      onChange={(e) => setEditingRuleRegex(e.target.value)}
                      className="font-mono"
                    />
                    <div className="grid gap-3 md:grid-cols-2">
                      <MultiValueCombobox
                        value={editingRuleRecipients}
                        onChange={setEditingRuleRecipients}
                        options={recipientNames}
                        placeholder="Recipients..."
                      />
                      <MultiValueCombobox
                        value={editingRuleGroups}
                        onChange={setEditingRuleGroups}
                        options={recipientGroupNames}
                        placeholder="Recipient groups..."
                      />
                    </div>
                    <div className="flex items-center gap-2">
                      <Button size="sm" onClick={handleUpdate}>
                        <Save className="mr-1 h-3.5 w-3.5" />
                        Save
                      </Button>
                      <Button
                        variant="ghost"
                        size="sm"
                        onClick={() => setEditingRuleIndex(null)}
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
