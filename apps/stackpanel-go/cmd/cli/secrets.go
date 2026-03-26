// secrets.go implements `stackpanel secrets`, which provides CLI access to
// SOPS-encrypted secrets management. All operations delegate to the agent's
// REST API — the CLI itself never touches encryption keys or SOPS files
// directly, keeping the crypto logic centralized in one place.

package cmd

import (
	"encoding/json"
	"fmt"
	"net/http"
	"os"
	"strings"
	"text/tabwriter"

	"github.com/darkmatter/stackpanel/stackpanel-go/internal/tui"
	secretsview "github.com/darkmatter/stackpanel/stackpanel-go/internal/tui/views/secrets"
	"github.com/fatih/color"
	"github.com/spf13/cobra"
)

var secretsCmd = &cobra.Command{
	Use:     "secrets",
	Short:   "Manage secrets and encryption",
	Long:    "Interactive dashboard for managing SOPS-encrypted secrets, groups, recipients, and keys.",
	Aliases: []string{"sec"},
	RunE: func(cmd *cobra.Command, args []string) error {
		noTUI, _ := cmd.Root().PersistentFlags().GetBool("no-tui")
		if noTUI || !tui.IsInteractive() {
			return secretsStatusPlain()
		}
		return secretsview.RunSecretsDashboard()
	},
}

var secretsStatusCmd = &cobra.Command{
	Use:   "status",
	Short: "Show secrets configuration status",
	RunE: func(cmd *cobra.Command, args []string) error {
		return secretsStatusPlain()
	},
}

var secretsGroupsCmd = &cobra.Command{
	Use:     "groups",
	Short:   "List configured secret groups",
	Aliases: []string{"g"},
	RunE: func(cmd *cobra.Command, args []string) error {
		return secretsGroupsPlain()
	},
}

var secretsRecipientsCmd = &cobra.Command{
	Use:     "recipients",
	Short:   "List recipients (team members with access)",
	Aliases: []string{"r"},
	RunE: func(cmd *cobra.Command, args []string) error {
		return secretsRecipientsPlain()
	},
}

func init() {
	secretsCmd.AddCommand(secretsStatusCmd)
	secretsCmd.AddCommand(secretsGroupsCmd)
	secretsCmd.AddCommand(secretsRecipientsCmd)
}

// --- Plain CLI output (non-TUI fallback) ---

func secretsStatusPlain() error {
	bold := color.New(color.Bold)
	dim := color.New(color.FgHiBlack)
	green := color.New(color.FgGreen)
	yellow := color.New(color.FgYellow)
	red := color.New(color.FgRed)

	bold.Println("Secrets Status")
	fmt.Println()

	// Groups
	groups, err := fetchAgentJSON("/api/secrets/group/list")
	if err != nil {
		red.Printf("  Agent not reachable: %v\n", err)
		dim.Println("  Start the agent with: stackpanel agent")
		return nil
	}

	groupMap, _ := groups["groups"].(map[string]interface{})
	if len(groupMap) == 0 {
		yellow.Println("  No secrets groups found.")
		dim.Println("  Initialize a group: secrets:init-group dev")
	} else {
		bold.Println("Groups:")
		w := tabwriter.NewWriter(os.Stdout, 0, 0, 2, ' ', 0)
		for name, data := range groupMap {
			dataMap, _ := data.(map[string]interface{})
			keys, _ := dataMap["keys"].([]interface{})
			fmt.Fprintf(w, "  %s\t%d secrets\n", green.Sprint(name), len(keys))
		}
		w.Flush()
	}

	fmt.Println()

	// Recipients
	recipientsResp, err := fetchAgentJSON("/api/secrets/recipients")
	if err == nil {
		recipientList, _ := recipientsResp["recipients"].([]interface{})
		bold.Println("Recipients:")
		if len(recipientList) == 0 {
			dim.Println("  No recipients registered yet.")
		} else {
			for _, r := range recipientList {
				rMap, _ := r.(map[string]interface{})
				name, _ := rMap["name"].(string)
				pubKey, _ := rMap["publicKey"].(string)
				shortKey := pubKey
				if len(shortKey) > 20 {
					shortKey = shortKey[:12] + "..." + shortKey[len(shortKey)-6:]
				}
				fmt.Printf("  %s  %s\n", green.Sprint(name), dim.Sprint(shortKey))
			}
		}
	}

	fmt.Println()

	// Rekey workflow
	workflowResp, err := fetchAgentJSON("/api/secrets/rekey-workflow")
	if err == nil {
		exists, _ := workflowResp["exists"].(bool)
		bold.Println("Rekey Workflow:")
		if exists {
			green.Println("  GitHub Actions workflow exists")
		} else {
			yellow.Println("  Not configured")
			dim.Println("  Run: secrets:init-group <group> --force-gh")
		}
	}

	return nil
}

func secretsGroupsPlain() error {
	groups, err := fetchAgentJSON("/api/secrets/group/list")
	if err != nil {
		return fmt.Errorf("agent not reachable: %w", err)
	}

	groupMap, _ := groups["groups"].(map[string]interface{})
	if len(groupMap) == 0 {
		fmt.Println("No groups found. Run: secrets:init-group dev")
		return nil
	}

	bold := color.New(color.Bold)
	dim := color.New(color.FgHiBlack)

	for name, data := range groupMap {
		dataMap, _ := data.(map[string]interface{})
		keys, _ := dataMap["keys"].([]interface{})
		bold.Printf("%s ", name)
		dim.Printf("(%d secrets)\n", len(keys))
		for _, k := range keys {
			fmt.Printf("  %s\n", k)
		}
		if len(keys) == 0 {
			dim.Println("  (empty)")
		}
	}

	return nil
}

func secretsRecipientsPlain() error {
	resp, err := fetchAgentJSON("/api/secrets/recipients")
	if err != nil {
		return fmt.Errorf("agent not reachable: %w", err)
	}

	recipientList, _ := resp["recipients"].([]interface{})
	if len(recipientList) == 0 {
		fmt.Println("No recipients registered.")
		fmt.Println("Recipients are auto-registered when team members enter the devshell.")
		return nil
	}

	bold := color.New(color.Bold)
	dim := color.New(color.FgHiBlack)
	bold.Printf("Recipients (%d):\n", len(recipientList))
	for _, r := range recipientList {
		rMap, _ := r.(map[string]interface{})
		name, _ := rMap["name"].(string)
		pubKey, _ := rMap["publicKey"].(string)
		fmt.Printf("  %-20s %s\n", name, dim.Sprint(pubKey))
	}

	return nil
}

// fetchAgentJSON makes a GET request to the local agent API and returns parsed JSON.
// The agent must be running for any secrets command to work; if not, the error
// message guides the user to start it.
//
// Default agent URL is localhost:21234, overridable via STACKPANEL_AGENT_URL
// for remote-agent or non-standard port setups.
//
// The agent wraps responses in a { success, data } envelope — this function
// automatically unwraps it so callers get the inner payload directly.
func fetchAgentJSON(path string) (map[string]interface{}, error) {
	agentURL := os.Getenv("STACKPANEL_AGENT_URL")
	if agentURL == "" {
		agentURL = "http://localhost:21234"
	}
	agentToken := os.Getenv("STACKPANEL_AGENT_TOKEN")

	url := strings.TrimRight(agentURL, "/") + path
	req, err := http.NewRequest("GET", url, nil)
	if err != nil {
		return nil, err
	}
	if agentToken != "" {
		req.Header.Set("Authorization", "Bearer "+agentToken)
	}

	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	var result map[string]interface{}
	if err := json.NewDecoder(resp.Body).Decode(&result); err != nil {
		return nil, err
	}

	// Unwrap the { success, data } envelope
	if data, ok := result["data"].(map[string]interface{}); ok {
		return data, nil
	}
	return result, nil
}
