"use client";

import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Users } from "lucide-react";
import { RecipientsSection } from "../recipients-section";

export function RecipientsTab() {
  return (
    <div className="mt-6 space-y-6">
      <Card>
        <CardHeader>
          <CardTitle className="text-base flex items-center gap-2">
            <Users className="h-4 w-4" />
            Recipients Management
          </CardTitle>
          <CardDescription>
            Manage team members and their public keys for secret decryption.
          </CardDescription>
        </CardHeader>
        <CardContent>
          <RecipientsSection />
        </CardContent>
      </Card>
    </div>
  );
}
