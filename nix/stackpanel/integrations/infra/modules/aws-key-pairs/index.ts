// ==============================================================================
// AWS Key Pairs Module
// ==============================================================================
import Infra from "@stackpanel/infra";
import { KeyPair } from "@stackpanel/infra/resources/key-pair";

interface KeyPairInput {
  publicKey: string;
  tags?: Record<string, string>;
  destroyOnDelete?: boolean;
}

interface AwsKeyPairsInputs {
  keys: Record<string, KeyPairInput>;
}

const infra = new Infra("aws-key-pairs");
const inputs = infra.inputs<AwsKeyPairsInputs>(
  process.env.STACKPANEL_INFRA_INPUTS_OVERRIDES,
);

const keyNames: string[] = [];
const keyPairIds: Record<string, string> = {};

for (const [keyName, key] of Object.entries(inputs.keys ?? {})) {
  const result = await KeyPair(infra.id(keyName), {
    keyName,
    publicKey: key.publicKey,
    tags: key.tags,
    destroyOnDelete: key.destroyOnDelete,
  });
  keyNames.push(result.keyName);
  if (result.keyPairId) {
    keyPairIds[result.keyName] = result.keyPairId;
  }
}

export default {
  keyNames: JSON.stringify(keyNames),
  keyPairIds: JSON.stringify(keyPairIds),
};
