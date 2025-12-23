"use client";

import {
  Clock,
  Copy,
  Database,
  ExternalLink,
  HardDrive,
  MoreVertical,
  Plus,
  Shield,
} from "lucide-react";
import { useState } from "react";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
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
import { Progress } from "@/components/ui/progress";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";

const databases = [
  {
    name: "main-postgres",
    type: "PostgreSQL",
    version: "15.2",
    status: "online",
    connections: "23/100",
    storage: { used: 12.4, total: 50 },
    host: "main-postgres.internal.acme.com",
    lastBackup: "2 hours ago",
    ssl: true,
  },
  {
    name: "auth-postgres",
    type: "PostgreSQL",
    version: "15.2",
    status: "online",
    connections: "8/50",
    storage: { used: 2.1, total: 20 },
    host: "auth-postgres.internal.acme.com",
    lastBackup: "1 hour ago",
    ssl: true,
  },
  {
    name: "cache-redis",
    type: "Redis",
    version: "7.0",
    status: "online",
    connections: "156/1000",
    storage: { used: 0.8, total: 4 },
    host: "cache-redis.internal.acme.com",
    lastBackup: "N/A",
    ssl: true,
  },
  {
    name: "analytics-clickhouse",
    type: "ClickHouse",
    version: "23.3",
    status: "online",
    connections: "12/50",
    storage: { used: 45.2, total: 200 },
    host: "analytics-clickhouse.internal.acme.com",
    lastBackup: "6 hours ago",
    ssl: true,
  },
];

export function DatabasesPanel() {
  const [dialogOpen, setDialogOpen] = useState(false);

  return (
    <div className="space-y-6">
      <div className="flex items-center justify-between">
        <div>
          <h2 className="font-semibold text-foreground text-xl">Databases</h2>
          <p className="text-muted-foreground text-sm">
            Manage your database instances and connections
          </p>
        </div>
        <Dialog onOpenChange={setDialogOpen} open={dialogOpen}>
          <DialogTrigger asChild>
            <Button className="gap-2 bg-accent text-accent-foreground hover:bg-accent/90">
              <Plus className="h-4 w-4" />
              Create Database
            </Button>
          </DialogTrigger>
          <DialogContent>
            <DialogHeader>
              <DialogTitle>Create New Database</DialogTitle>
              <DialogDescription>
                Provision a new database instance for your stack.
              </DialogDescription>
            </DialogHeader>
            <div className="grid gap-4 py-4">
              <div className="grid gap-2">
                <Label htmlFor="db-name">Database Name</Label>
                <Input id="db-name" placeholder="my-database" />
              </div>
              <div className="grid gap-2">
                <Label>Database Type</Label>
                <Select>
                  <SelectTrigger>
                    <SelectValue placeholder="Select type" />
                  </SelectTrigger>
                  <SelectContent>
                    <SelectItem value="postgres">PostgreSQL</SelectItem>
                    <SelectItem value="mysql">MySQL</SelectItem>
                    <SelectItem value="redis">Redis</SelectItem>
                    <SelectItem value="clickhouse">ClickHouse</SelectItem>
                    <SelectItem value="mongo">MongoDB</SelectItem>
                  </SelectContent>
                </Select>
              </div>
              <div className="grid gap-2">
                <Label>Storage Size</Label>
                <Select defaultValue="20">
                  <SelectTrigger>
                    <SelectValue />
                  </SelectTrigger>
                  <SelectContent>
                    <SelectItem value="10">10 GB</SelectItem>
                    <SelectItem value="20">20 GB</SelectItem>
                    <SelectItem value="50">50 GB</SelectItem>
                    <SelectItem value="100">100 GB</SelectItem>
                    <SelectItem value="200">200 GB</SelectItem>
                  </SelectContent>
                </Select>
              </div>
            </div>
            <DialogFooter>
              <Button onClick={() => setDialogOpen(false)} variant="outline">
                Cancel
              </Button>
              <Button className="bg-accent text-accent-foreground hover:bg-accent/90">
                Create
              </Button>
            </DialogFooter>
          </DialogContent>
        </Dialog>
      </div>

      <div className="grid gap-4 md:grid-cols-2">
        {databases.map((db) => (
          <Card key={db.name}>
            <CardHeader className="pb-3">
              <div className="flex items-start justify-between">
                <div className="flex items-center gap-3">
                  <div className="flex h-10 w-10 items-center justify-center rounded-lg bg-accent/10">
                    <Database className="h-5 w-5 text-accent" />
                  </div>
                  <div>
                    <CardTitle className="font-medium text-base">{db.name}</CardTitle>
                    <p className="text-muted-foreground text-sm">
                      {db.type} {db.version}
                    </p>
                  </div>
                </div>
                <div className="flex items-center gap-2">
                  <Badge
                    className={
                      db.status === "online" ? "border-accent text-accent" : ""
                    }
                    variant="outline"
                  >
                    {db.status}
                  </Badge>
                  <DropdownMenu>
                    <DropdownMenuTrigger asChild>
                      <Button className="h-8 w-8" size="icon" variant="ghost">
                        <MoreVertical className="h-4 w-4" />
                      </Button>
                    </DropdownMenuTrigger>
                    <DropdownMenuContent align="end">
                      <DropdownMenuItem>
                        <ExternalLink className="mr-2 h-4 w-4" />
                        Open Console
                      </DropdownMenuItem>
                      <DropdownMenuItem>View metrics</DropdownMenuItem>
                      <DropdownMenuItem>Backup now</DropdownMenuItem>
                      <DropdownMenuItem>Edit config</DropdownMenuItem>
                      <DropdownMenuItem className="text-destructive">
                        Delete
                      </DropdownMenuItem>
                    </DropdownMenuContent>
                  </DropdownMenu>
                </div>
              </div>
            </CardHeader>
            <CardContent className="space-y-4">
              <div className="rounded-lg border border-border bg-secondary/30 p-3">
                <div className="flex items-center justify-between">
                  <code className="flex-1 truncate text-muted-foreground text-xs">
                    {db.host}
                  </code>
                  <Button className="h-6 w-6 shrink-0" size="icon" variant="ghost">
                    <Copy className="h-3 w-3" />
                  </Button>
                </div>
              </div>

              <div className="space-y-2">
                <div className="flex items-center justify-between text-sm">
                  <span className="flex items-center gap-2 text-muted-foreground">
                    <HardDrive className="h-4 w-4" />
                    Storage
                  </span>
                  <span className="text-foreground">
                    {db.storage.used} GB / {db.storage.total} GB
                  </span>
                </div>
                <Progress
                  className="h-1.5"
                  value={(db.storage.used / db.storage.total) * 100}
                />
              </div>

              <div className="grid grid-cols-2 gap-4 text-sm">
                <div className="flex items-center gap-2 text-muted-foreground">
                  <Clock className="h-4 w-4" />
                  <span>Backup: {db.lastBackup}</span>
                </div>
                <div className="flex items-center gap-2 text-muted-foreground">
                  <Shield className="h-4 w-4" />
                  <span>Connections: {db.connections}</span>
                </div>
              </div>
            </CardContent>
          </Card>
        ))}
      </div>
    </div>
  );
}
