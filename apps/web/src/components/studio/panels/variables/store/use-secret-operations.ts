import { create } from "zustand";
import { devtools } from "zustand/middleware";
import { immer } from "zustand/middleware/immer";

/**
 * Secret operation state (async operations)
 */
interface SecretOperationsState {
  // Reveal secret operation state
  revealingSecretId: string | null;
  revealError: string | null;

  // Delete secret operation state
  deletingSecretId: string | null;
  deleteError: string | null;

  // Actions
  setRevealingSecretId: (id: string | null) => void;
  setRevealError: (error: string | null) => void;
  clearRevealState: () => void;

  setDeletingSecretId: (id: string | null) => void;
  setDeleteError: (error: string | null) => void;
  clearDeleteState: () => void;

  reset: () => void;
}

const initialState = {
  revealingSecretId: null,
  revealError: null,
  deletingSecretId: null,
  deleteError: null,
};

export const useSecretOperationsStore = create<SecretOperationsState>()(
  devtools(
    immer((set: any) => ({
      ...initialState,

      setRevealingSecretId: (id: string | null) => {
        set(
          (state: any) => {
            state.revealingSecretId = id;
          },
          false,
          "setRevealingSecretId",
        );
      },

      setRevealError: (error: string | null) => {
        set(
          (state: any) => {
            state.revealError = error;
          },
          false,
          "setRevealError",
        );
      },

      clearRevealState: () => {
        set(
          (state: any) => {
            state.revealingSecretId = null;
            state.revealError = null;
          },
          false,
          "clearRevealState",
        );
      },

      setDeletingSecretId: (id: string | null) => {
        set(
          (state: any) => {
            state.deletingSecretId = id;
          },
          false,
          "setDeletingSecretId",
        );
      },

      setDeleteError: (error: string | null) => {
        set(
          (state: any) => {
            state.deleteError = error;
          },
          false,
          "setDeleteError",
        );
      },

      clearDeleteState: () => {
        set(
          (state: any) => {
            state.deletingSecretId = null;
            state.deleteError = null;
          },
          false,
          "clearDeleteState",
        );
      },

      reset: () => {
        set((): any => initialState, false, "reset");
      },
    })),
    {
      name: "SecretOperationsStore",
      trace: true,
    },
  ),
);
