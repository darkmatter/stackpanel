"use client";

import {
  BadgeCheck,
  Key,
  MoreVertical,
  Plus,
  Search,
  Shield,
} from "lucide-react";
import { useMemo, useState } from "react";
import { Avatar, AvatarFallback } from "@/components/ui/avatar";
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
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { useNixData } from "@/lib/use-nix-config";
import type { User } from "@/lib/types";

type GithubCollaborator = {
  login: string;
  role: string;
  isAdmin?: boolean;
  publicKeys?: string[];
};

type GithubCollaboratorsData = {
  _meta?: { source?: string; generatedAt?: string };
  collaborators?: Record<string, GithubCollaborator>;
};

type TeamMember = {
  id: string;
  name: string;
  handle: string | null;
  role: string;
  status: "active" | "pending";
  publicKeys: string[];
  secretsAccess: string[];
  source: "stackpanel" | "github";
};

export function TeamPanel() {
  const [searchQuery, setSearchQuery] = useState("");
  const [dialogOpen, setDialogOpen] = useState(false);
  const { data: usersData, isLoading: usersLoading } =
    useNixData<Record<string, User>>("users");
  const { data: githubData, isLoading: githubLoading } =
    useNixData<GithubCollaboratorsData>("external-github-collaborators");

  const members = useMemo(() => {
    const users = usersData ?? {};
    const collaborators = githubData?.collaborators ?? {};
    const entries: TeamMember[] = [];
    const githubHandles = new Set(
      Object.values(users)
        .map((user) => user.github?.toLowerCase())
        .filter((handle): handle is string => Boolean(handle)),
    );

    for (const [key, user] of Object.entries(users)) {
      const displayName = user.name || user.github || key;
      const handle = user.github ? `@${user.github}` : null;
      const publicKeys = user.public_keys ?? [];
      const secretsAccess = (user.secrets_allowed_environments ?? []).map(
        (env) => String(env).toLowerCase(),
      );

      entries.push({
        id: key,
        name: displayName,
        handle,
        role: "Member",
        status: publicKeys.length > 0 ? "active" : "pending",
        publicKeys,
        secretsAccess,
        source: "stackpanel",
      });
    }

    for (const [key, collaborator] of Object.entries(collaborators)) {
      if (githubHandles.has(collaborator.login.toLowerCase())) {
        continue;
      }
      const publicKeys = collaborator.publicKeys ?? [];
      const roleValue = collaborator.role ?? "member";
      const roleLabel = collaborator.isAdmin
        ? "Admin"
        : roleValue.charAt(0).toUpperCase() + roleValue.slice(1);

      entries.push({
        id: key,
        name: collaborator.login,
        handle: `@${collaborator.login}`,
        role: roleLabel,
        status: publicKeys.length > 0 ? "active" : "pending",
        publicKeys,
        secretsAccess: [],
        source: "github",
      });
    }

    return entries.sort((a, b) => a.name.localeCompare(b.name));
  }, [usersData, githubData]);

  const filteredMembers = useMemo(() => {
    const query = searchQuery.trim().toLowerCase();
    if (!query) return members;
    return members.filter(
      (member) =>
        member.name.toLowerCase().includes(query) ||
        member.handle?.toLowerCase().includes(query) ||
        member.role.toLowerCase().includes(query),
    );
  }, [members, searchQuery]);

  const totalMembers = members.length;
  const keysRegistered = members.filter(
    (member) => member.publicKeys.length > 0,
  ).length;
  const adminCount = members.filter((member) => member.role === "Admin").length;

  const getRoleColor = (role: string) => {
    switch (role) {
      case "Admin":
        return "bg-purple-500/10 text-purple-400 border-purple-500/20";
      case "Member":
        return "bg-accent/10 text-accent border-accent/20";
      case "Write":
        return "bg-blue-500/10 text-blue-400 border-blue-500/20";
      case "Read":
        return "bg-slate-500/10 text-slate-400 border-slate-500/20";
      case "Maintain":
        return "bg-green-500/10 text-green-400 border-green-500/20";
      case "Triage":
        return "bg-yellow-500/10 text-yellow-400 border-yellow-500/20";
      default:
        return "";
    }
  };

  return (
    <div className="space-y-6">
      <div className="flex items-center justify-between">
        <div>
          <h2 className="font-semibold text-foreground text-xl">Team</h2>
          <p className="text-muted-foreground text-sm">
            Manage team members, roles, and secrets access
          </p>
        </div>
        <Dialog onOpenChange={setDialogOpen} open={dialogOpen}>
          <DialogTrigger asChild>
            <Button className="gap-2 bg-accent text-accent-foreground hover:bg-accent/90">
              <Plus className="h-4 w-4" />
              Invite Member
            </Button>
          </DialogTrigger>
          <DialogContent>
            <DialogHeader>
              <DialogTitle>Invite Team Member</DialogTitle>
              <DialogDescription>
                Send an invitation to join your StackPanel organization via SSO.
              </DialogDescription>
            </DialogHeader>
            <div className="grid gap-4 py-4">
              <div className="grid gap-2">
                <Label htmlFor="email">Email Address</Label>
                <Input
                  id="email"
                  placeholder="colleague@acme.com"
                  type="email"
                />
              </div>
              <div className="grid gap-2">
                <Label>Role</Label>
                <Select defaultValue="developer">
                  <SelectTrigger>
                    <SelectValue />
                  </SelectTrigger>
                  <SelectContent>
                    <SelectItem value="admin">Admin</SelectItem>
                    <SelectItem value="developer">Developer</SelectItem>
                    <SelectItem value="viewer">Viewer</SelectItem>
                  </SelectContent>
                </Select>
              </div>
              <div className="rounded-lg border border-border bg-secondary/30 p-3">
                <p className="text-muted-foreground text-sm">
                  The invited member will receive an email with SSO login
                  instructions. Once they log in, they'll be prompted to add
                  their age public key for secrets access.
                </p>
              </div>
            </div>
            <DialogFooter>
              <Button onClick={() => setDialogOpen(false)} variant="outline">
                Cancel
              </Button>
              <Button className="bg-accent text-accent-foreground hover:bg-accent/90">
                Send Invitation
              </Button>
            </DialogFooter>
          </DialogContent>
        </Dialog>
      </div>

      <div className="grid gap-4 sm:grid-cols-3">
        <Card>
          <CardContent className="p-4">
            <div className="flex items-center gap-3">
              <div className="flex h-10 w-10 items-center justify-center rounded-lg bg-accent/10">
                <Shield className="h-5 w-5 text-accent" />
              </div>
              <div>
                <p className="font-bold text-2xl text-foreground">
                  {totalMembers}
                </p>
                <p className="text-muted-foreground text-sm">Total Members</p>
              </div>
            </div>
          </CardContent>
        </Card>
        <Card>
          <CardContent className="p-4">
            <div className="flex items-center gap-3">
              <div className="flex h-10 w-10 items-center justify-center rounded-lg bg-accent/10">
                <Key className="h-5 w-5 text-accent" />
              </div>
              <div>
                <p className="font-bold text-2xl text-foreground">
                  {keysRegistered}
                </p>
                <p className="text-muted-foreground text-sm">Keys Registered</p>
              </div>
            </div>
          </CardContent>
        </Card>
        <Card>
          <CardContent className="p-4">
            <div className="flex items-center gap-3">
              <div className="flex h-10 w-10 items-center justify-center rounded-lg bg-accent/10">
                <BadgeCheck className="h-5 w-5 text-accent" />
              </div>
              <div>
                <p className="font-bold text-2xl text-foreground">
                  {adminCount}
                </p>
                <p className="text-muted-foreground text-sm">Admins</p>
              </div>
            </div>
          </CardContent>
        </Card>
      </div>

      <div className="relative max-w-sm">
        <Search className="-translate-y-1/2 absolute top-1/2 left-3 h-4 w-4 text-muted-foreground" />
        <Input
          className="pl-9"
          onChange={(e) => setSearchQuery(e.target.value)}
          placeholder="Search members..."
          value={searchQuery}
        />
      </div>

      <div className="grid gap-3">
        {usersLoading || githubLoading ? (
          <Card>
            <CardContent className="p-4">
              <p className="text-muted-foreground text-sm">
                Loading team data from the agent...
              </p>
            </CardContent>
          </Card>
        ) : filteredMembers.length === 0 ? (
          <Card>
            <CardContent className="p-4">
              <p className="text-muted-foreground text-sm">
                No team members found yet.
              </p>
            </CardContent>
          </Card>
        ) : (
          filteredMembers.map((member) => (
            <Card key={member.id}>
              <CardContent className="p-4">
                <div className="flex items-center justify-between">
                  <div className="flex items-center gap-4">
                    <Avatar className="h-10 w-10">
                      <AvatarFallback className="bg-secondary text-foreground">
                        {member.name
                          .split(" ")
                          .map((n) => n[0])
                          .join("")}
                      </AvatarFallback>
                    </Avatar>
                    <div>
                      <div className="flex items-center gap-2">
                        <h3 className="font-medium text-foreground">
                          {member.name}
                        </h3>
                        <Badge
                          className={getRoleColor(member.role)}
                          variant="outline"
                        >
                          {member.role}
                        </Badge>
                        {member.status === "pending" && (
                          <Badge
                            className="border-yellow-500/20 bg-yellow-500/10 text-yellow-400"
                            variant="outline"
                          >
                            Pending
                          </Badge>
                        )}
                      </div>
                      <p className="text-muted-foreground text-sm">
                        {member.handle ?? "No handle"}
                      </p>
                    </div>
                  </div>

                  <div className="flex items-center gap-6">
                    <div className="hidden items-center gap-6 text-muted-foreground text-sm sm:flex">
                      <div className="flex items-center gap-2">
                        <Key className="h-4 w-4" />
                        <span>
                          {member.publicKeys.length > 0
                            ? `${member.publicKeys.length} key${
                                member.publicKeys.length === 1 ? "" : "s"
                              }`
                            : "No keys"}
                        </span>
                      </div>
                      <div className="flex items-center gap-2">
                        <Shield className="h-4 w-4" />
                        <span>
                          {member.secretsAccess.length > 0
                            ? `Secrets: ${member.secretsAccess.join(", ")}`
                            : `Source: ${
                                member.source === "github"
                                  ? "GitHub"
                                  : "Stackpanel"
                              }`}
                        </span>
                      </div>
                    </div>
                    <DropdownMenu>
                      <DropdownMenuTrigger asChild>
                        <Button className="h-8 w-8" size="icon" variant="ghost">
                          <MoreVertical className="h-4 w-4" />
                        </Button>
                      </DropdownMenuTrigger>
                      <DropdownMenuContent align="end">
                        <DropdownMenuItem>View profile</DropdownMenuItem>
                        <DropdownMenuItem>Change role</DropdownMenuItem>
                        <DropdownMenuItem>Regenerate invite</DropdownMenuItem>
                        <DropdownMenuItem className="text-destructive">
                          Remove
                        </DropdownMenuItem>
                      </DropdownMenuContent>
                    </DropdownMenu>
                  </div>
                </div>
              </CardContent>
            </Card>
          ))
        )}
      </div>
    </div>
  );
}
