"use client";

import {
  Clock,
  Copy,
  Eye,
  EyeOff,
  KeyRound,
  Lock,
  MoreVertical,
  Plus,
  RefreshCw,
  Search,
  Shield,
  Users,
} from "lucide-react";
import { useState } from "react";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent } from "@/components/ui/card";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
  DialogTrigger,
} from "@/components/ui/dialog";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Tabs, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { Textarea } from "@/components/ui/textarea";

const secrets = [
  {
    key: "DATABASE_URL",
    environment: "production",
    lastRotated: "3 days ago",
    accessedBy: ["api-gateway", "auth-service", "worker-service"],
    type: "connection-string",
  },
  {
    key: "REDIS_URL",
    environment: "production",
    lastRotated: "1 week ago",
    accessedBy: ["api-gateway", "worker-service"],
    type: "connection-string",
  },
  {
    key: "JWT_SECRET",
    environment: "production",
    lastRotated: "30 days ago",
    accessedBy: ["auth-service"],
    type: "secret",
  },
  {
    key: "STRIPE_SECRET_KEY",
    environment: "production",
    lastRotated: "60 days ago",
    accessedBy: ["api-gateway"],
    type: "api-key",
  },
  {
    key: "OPENAI_API_KEY",
    environment: "production",
    lastRotated: "14 days ago",
    accessedBy: ["worker-service"],
    type: "api-key",
  },
  {
    key: "GITHUB_TOKEN",
    environment: "ci",
    lastRotated: "7 days ago",
    accessedBy: ["ci-pipeline"],
    type: "token",
  },
  {
    key: "SMTP_PASSWORD",
    environment: "production",
    lastRotated: "45 days ago",
    accessedBy: ["notification-service"],
    type: "password",
  },
];

export function SecretsPanel() {
  const [searchQuery, setSearchQuery] = useState("");
  const [dialogOpen, setDialogOpen] = useState(false);
  const [showSecret, setShowSecret] = useState<string | null>(null);

  const filteredSecrets = secrets.filter((secret) =>
    secret.key.toLowerCase().includes(searchQuery.toLowerCase())
  );

  const getTypeColor = (type: string) => {
    switch (type) {
      case "connection-string":
        return "bg-blue-500/10 text-blue-400";
      case "api-key":
        return "bg-purple-500/10 text-purple-400";
      case "secret":
        return "bg-accent/10 text-accent";
      case "token":
        return "bg-orange-500/10 text-orange-400";
      default:
        return "bg-muted text-muted-foreground";
    }
  };

  return (
    <div className="space-y-6">
      <div className="flex items-center justify-between">
        <div>
          <h2 className="font-semibold text-foreground text-xl">Secrets</h2>
          <p className="text-muted-foreground text-sm">
            Manage encrypted secrets using age encryption with team public keys
          </p>
        </div>
        <Dialog onOpenChange={setDialogOpen} open={dialogOpen}>
          <DialogTrigger asChild>
            <Button className="gap-2 bg-accent text-accent-foreground hover:bg-accent/90">
              <Plus className="h-4 w-4" />
              Add Secret
            </Button>
          </DialogTrigger>
          <DialogContent>
            <DialogHeader>
              <DialogTitle>Add New Secret</DialogTitle>
              <DialogDescription>
                Secrets are encrypted with your team members' public keys using age.
              </DialogDescription>
            </DialogHeader>
            <div className="grid gap-4 py-4">
              <div className="grid gap-2">
                <Label htmlFor="secret-key">Key</Label>
                <Input
                  className="font-mono"
                  id="secret-key"
                  placeholder="MY_SECRET_KEY"
                />
              </div>
              <div className="grid gap-2">
                <Label htmlFor="secret-value">Value</Label>
                <Textarea
                  className="font-mono"
                  id="secret-value"
                  placeholder="Enter secret value..."
                />
              </div>
              <div className="grid gap-2">
                <Label>Environment</Label>
                <Tabs defaultValue="production">
                  <TabsList className="grid w-full grid-cols-3">
                    <TabsTrigger value="production">Production</TabsTrigger>
                    <TabsTrigger value="staging">Staging</TabsTrigger>
                    <TabsTrigger value="development">Development</TabsTrigger>
                  </TabsList>
                </Tabs>
              </div>
            </div>
            <DialogFooter>
              <Button onClick={() => setDialogOpen(false)} variant="outline">
                Cancel
              </Button>
              <Button className="bg-accent text-accent-foreground hover:bg-accent/90">
                Encrypt & Save
              </Button>
            </DialogFooter>
          </DialogContent>
        </Dialog>
      </div>

      <Card className="border-accent/20 bg-accent/5">
        <CardContent className="flex items-center gap-4 p-4">
          <div className="flex h-10 w-10 items-center justify-center rounded-lg bg-accent/20">
            <Shield className="h-5 w-5 text-accent" />
          </div>
          <div className="flex-1">
            <p className="font-medium text-foreground text-sm">
              Age Encryption Enabled
            </p>
            <p className="text-muted-foreground text-xs">
              All secrets are encrypted using your team's public keys. Only authorized
              members can decrypt.
            </p>
          </div>
          <Button size="sm" variant="outline">
            Manage Keys
          </Button>
        </CardContent>
      </Card>

      <div className="relative max-w-sm">
        <Search className="-translate-y-1/2 absolute top-1/2 left-3 h-4 w-4 text-muted-foreground" />
        <Input
          className="pl-9"
          onChange={(e) => setSearchQuery(e.target.value)}
          placeholder="Search secrets..."
          value={searchQuery}
        />
      </div>

      <div className="grid gap-3">
        {filteredSecrets.map((secret) => (
          <Card key={secret.key}>
            <CardContent className="p-4">
              <div className="flex items-center justify-between">
                <div className="flex items-center gap-4">
                  <div className="flex h-10 w-10 items-center justify-center rounded-lg bg-secondary">
                    <KeyRound className="h-5 w-5 text-muted-foreground" />
                  </div>
                  <div>
                    <div className="flex items-center gap-2">
                      <h3 className="font-medium font-mono text-foreground text-sm">
                        {secret.key}
                      </h3>
                      <Badge className={getTypeColor(secret.type)} variant="outline">
                        {secret.type}
                      </Badge>
                    </div>
                    <div className="mt-1 flex items-center gap-4 text-muted-foreground text-xs">
                      <span className="flex items-center gap-1">
                        <Clock className="h-3 w-3" />
                        Rotated {secret.lastRotated}
                      </span>
                      <span className="flex items-center gap-1">
                        <Users className="h-3 w-3" />
                        {secret.accessedBy.length} services
                      </span>
                    </div>
                  </div>
                </div>

                <div className="flex items-center gap-2">
                  <Button
                    className="h-8 w-8"
                    onClick={() =>
                      setShowSecret(showSecret === secret.key ? null : secret.key)
                    }
                    size="icon"
                    variant="ghost"
                  >
                    {showSecret === secret.key ? (
                      <EyeOff className="h-4 w-4" />
                    ) : (
                      <Eye className="h-4 w-4" />
                    )}
                  </Button>
                  <Button className="h-8 w-8" size="icon" variant="ghost">
                    <Copy className="h-4 w-4" />
                  </Button>
                  <DropdownMenu>
                    <DropdownMenuTrigger asChild>
                      <Button className="h-8 w-8" size="icon" variant="ghost">
                        <MoreVertical className="h-4 w-4" />
                      </Button>
                    </DropdownMenuTrigger>
                    <DropdownMenuContent align="end">
                      <DropdownMenuItem>
                        <RefreshCw className="mr-2 h-4 w-4" />
                        Rotate
                      </DropdownMenuItem>
                      <DropdownMenuItem>Edit</DropdownMenuItem>
                      <DropdownMenuItem>View history</DropdownMenuItem>
                      <DropdownMenuItem className="text-destructive">
                        Delete
                      </DropdownMenuItem>
                    </DropdownMenuContent>
                  </DropdownMenu>
                </div>
              </div>

              {showSecret === secret.key && (
                <div className="mt-3 rounded-lg bg-secondary/50 p-3 font-mono text-muted-foreground text-xs">
                  <div className="flex items-center gap-2">
                    <Lock className="h-3 w-3" />
                    ••••••••••••••••••••••••••••••••
                  </div>
                </div>
              )}
            </CardContent>
          </Card>
        ))}
      </div>
    </div>
  );
}
