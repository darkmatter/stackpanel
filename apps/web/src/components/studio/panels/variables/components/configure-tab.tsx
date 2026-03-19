"use client";

import { CheckCircle2 } from "lucide-react";
import { GroupsSection } from "../groups-section";
import { KMSSettings } from "../edit-secret-dialog";

interface ConfigureTabProps {
  isChamber: boolean;
  backendData?: {
    chamber?: {
      servicePrefix?: string;
    };
  } | null;
}

export function ConfigureTab({ isChamber, backendData }: ConfigureTabProps) {
  return (
    <div className="mt-6 space-y-6">
      {isChamber ? (
        <div className="space-y-4">
          <div>
            <h3 className="text-lg font-medium mb-1">Chamber Backend</h3>
            <p className="text-sm text-muted-foreground">
              Secrets are managed via AWS Systems Manager Parameter Store using
              Chamber.
            </p>
          </div>

          <div className="rounded-lg border border-border bg-card p-4 space-y-3">
            <div className="flex items-center gap-2">
              <CheckCircle2 className="h-4 w-4 text-green-500" />
              <span className="text-sm font-medium">Active Backend: Chamber</span>
            </div>
            {backendData?.chamber?.servicePrefix && (
              <div className="space-y-1">
                <p className="text-xs font-medium text-muted-foreground">
                  Service Prefix
                </p>
                <code className="text-sm font-mono">
                  {backendData.chamber.servicePrefix}
                </code>
              </div>
            )}
            <p className="text-sm text-muted-foreground">
              Secrets in{" "}
              <code className="bg-muted px-1 py-0.5 rounded text-xs">/dev/*</code>,{" "}
              <code className="bg-muted px-1 py-0.5 rounded text-xs">
                /staging/*
              </code>
              , and{" "}
              <code className="bg-muted px-1 py-0.5 rounded text-xs">
                /prod/*
              </code>{" "}
              keygroups are stored as encrypted SSM parameters. Encryption is
              handled transparently by AWS KMS.
            </p>
          </div>

          <div className="rounded-lg border border-blue-500/20 bg-blue-500/5 p-4">
            <h4 className="mb-2 text-sm font-medium text-blue-600 dark:text-blue-400">
              AWS Credentials Required
            </h4>
            <p className="text-sm text-muted-foreground">
              Reading and writing secrets requires valid AWS credentials with
              access to the SSM Parameter Store and KMS key.
            </p>
          </div>
        </div>
      ) : (
        <div className="space-y-4">
          <GroupsSection />

          <div>
            <h3 className="text-lg font-medium mb-1">Encryption Settings</h3>
            <p className="text-sm text-muted-foreground">
              Configure how secrets are encrypted and decrypted in this project.
            </p>
          </div>

          <div className="rounded-lg border border-blue-500/20 bg-blue-500/5 p-4">
            <h4 className="mb-2 text-sm font-medium text-blue-600 dark:text-blue-400">
              Auto-generated local keys
            </h4>
            <p className="text-sm text-muted-foreground">
              Your local AGE key is automatically generated when you enter the
              devshell and stored at{" "}
              <code className="bg-muted px-1.5 py-0.5 rounded text-xs">
                .stack/keys/local.txt
              </code>
              . A wrapped SOPS binary handles key resolution automatically &mdash;
              no manual identity configuration is needed.
            </p>
          </div>

          <div className="space-y-4">
            <KMSSettings />
          </div>
        </div>
      )}
    </div>
  );
}
