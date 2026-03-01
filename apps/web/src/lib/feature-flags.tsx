// Compatibility shim for local imports.
// Keeps existing call sites working while feature-flag logic lives in the
// generated package.

export {
  FEATURE_FLAG_KEYS,
  FeatureFlagProvider,
  featureFlagDefinitions,
  useFeatureFlags,
} from "@gen/featureflags";

export type {
  BooleanFeatureFlagDefinition,
  FeatureFlagDefinition,
  FeatureFlagValue,
  VariantFeatureFlagDefinition,
} from "@gen/featureflags";
