"use client";

import { useState } from "react";
import { Plus, Loader2, Key } from "lucide-react";
import { Card, CardContent } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { MultiValueCombobox } from "../multi-value-combobox";

interface AddRecipientFormProps {
  onAdd: (recipient: {
    name: string;
    publicKey: string;
    keyType: "age" | "ssh";
    tags: string[];
  }) => Promise<void>;
  isPending: boolean;
  knownTags: string[];
  onCancel: () => void;
}

export function AddRecipientForm({
  onAdd,
  isPending,
  knownTags,
  onCancel,
}: AddRecipientFormProps) {
  const [name, setName] = useState("");
  const [publicKey, setPublicKey] = useState("");
  const [tags, setTags] = useState<string[]>([]);
  const [keyType, setKeyType] = useState<"age" | "ssh">("age");

  const handleSubmit = async () => {
    await onAdd({ name, publicKey, keyType, tags });
    // Reset form is usually handled by the parent on success,
    // but we can also do it here if needed.
  };

  return (
    <Card className="border-dashed">
      <CardContent className="space-y-3 pt-4">
        <div className="grid grid-cols-2 gap-3">
          <div className="space-y-1.5">
            <Label htmlFor="recipient-name">Name</Label>
            <Input
              id="recipient-name"
              placeholder="e.g. alice"
              value={name}
              onChange={(e) => setName(e.target.value)}
            />
          </div>
          <div className="space-y-1.5">
            <Label>Key type</Label>
            <Select
              value={keyType}
              onValueChange={(v) => setKeyType(v as "age" | "ssh")}
            >
              <SelectTrigger>
                <SelectValue />
              </SelectTrigger>
              <SelectContent>
                <SelectItem value="age">AGE public key</SelectItem>
                <SelectItem value="ssh">SSH public key</SelectItem>
              </SelectContent>
            </Select>
          </div>
        </div>
        <div className="space-y-1.5">
          <Label htmlFor="recipient-key">Public key</Label>
          <Input
            id="recipient-key"
            placeholder={
              keyType === "age"
                ? "age1..."
                : "ssh-ed25519 AAAA... or ssh-rsa AAAA..."
            }
            value={publicKey}
            onChange={(e) => setPublicKey(e.target.value)}
            className="font-mono text-xs"
          />
        </div>
        <div className="space-y-1.5">
          <Label htmlFor="recipient-tags">Tags</Label>
          <MultiValueCombobox
            value={tags}
            onChange={setTags}
            options={knownTags}
            placeholder="Select or type tags..."
            allowCreate
          />
          <p className="text-xs text-muted-foreground">
            Tags decide which groups this recipient can decrypt.
          </p>
        </div>
        <div className="flex justify-end gap-2">
          <Button
            variant="ghost"
            size="sm"
            onClick={onCancel}
          >
            Cancel
          </Button>
          <Button
            size="sm"
            onClick={handleSubmit}
            disabled={isPending}
          >
            {isPending ? (
              <Loader2 className="mr-1 h-3.5 w-3.5 animate-spin" />
            ) : (
              <Key className="mr-1 h-3.5 w-3.5" />
            )}
            Add recipient
          </Button>
        </div>
      </CardContent>
    </Card>
  );
}
