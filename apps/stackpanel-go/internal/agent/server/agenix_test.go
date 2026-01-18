package server

import "testing"

func TestIsAgeKeyContent(t *testing.T) {
	tests := []struct {
		name     string
		value    string
		expected bool
	}{
		{
			name:     "raw AGE secret key",
			value:    "AGE-SECRET-KEY-1QFPEJ2DGPKXZARQWNX6GS46VF526G0VJVNX4VMJZNGKJZDEHQZNSDPWXKY",
			expected: true,
		},
		{
			name:     "AGE identity file with comments",
			value:    "# created: 2023-01-01T00:00:00Z\n# public key: age1ql3z7hjy54pw3hyww5ayyfg7zqgvc7w3j2elw8zmrj2kg5sfn9aqmcac8p\nAGE-SECRET-KEY-1QFPEJ2DGPKXZARQWNX6GS46VF526G0VJVNX4VMJZNGKJZDEHQZNSDPWXKY",
			expected: true,
		},
		{
			name:     "AGE identity file with only public key comment",
			value:    "# public key: age1ql3z7hjy54pw3hyww5ayyfg7zqgvc7w3j2elw8zmrj2kg5sfn9aqmcac8p\nAGE-SECRET-KEY-1QFPEJ2DGPKXZARQWNX6GS46VF526G0VJVNX4VMJZNGKJZDEHQZNSDPWXKY",
			expected: true,
		},
		{
			name:     "SSH private key PEM format",
			value:    "-----BEGIN OPENSSH PRIVATE KEY-----\nb3BlbnNzaC1rZXktdjEAAAAABG5vbmUAAAAEbm9uZQAAAA==\n-----END OPENSSH PRIVATE KEY-----",
			expected: true,
		},
		{
			name:     "RSA private key PEM format",
			value:    "-----BEGIN RSA PRIVATE KEY-----\nMIIEowIBAAKCAQEA...\n-----END RSA PRIVATE KEY-----",
			expected: true,
		},
		{
			name:     "file path - home relative",
			value:    "~/.ssh/id_ed25519",
			expected: false,
		},
		{
			name:     "file path - absolute",
			value:    "/home/user/.config/age/key.txt",
			expected: false,
		},
		{
			name:     "file path - relative",
			value:    ".config/age/key.txt",
			expected: false,
		},
		{
			name:     "AGE public key (not identity)",
			value:    "age1ql3z7hjy54pw3hyww5ayyfg7zqgvc7w3j2elw8zmrj2kg5sfn9aqmcac8p",
			expected: false,
		},
		{
			name:     "empty string",
			value:    "",
			expected: false,
		},
		{
			name:     "comment without AGE key",
			value:    "# this is just a comment\n# another comment",
			expected: false,
		},
		{
			name:     "AGE secret key with leading whitespace",
			value:    "  AGE-SECRET-KEY-1QFPEJ2DGPKXZARQWNX6GS46VF526G0VJVNX4VMJZNGKJZDEHQZNSDPWXKY",
			expected: false, // trimming should happen before calling this function
		},
		{
			name:     "AGE identity with Windows line endings",
			value:    "# created: 2023-01-01T00:00:00Z\r\n# public key: age1ql3z7hjy54pw3hyww5ayyfg7zqgvc7w3j2elw8zmrj2kg5sfn9aqmcac8p\r\nAGE-SECRET-KEY-1QFPEJ2DGPKXZARQWNX6GS46VF526G0VJVNX4VMJZNGKJZDEHQZNSDPWXKY",
			expected: true,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result := isAgeKeyContent(tt.value)
			if result != tt.expected {
				t.Errorf("isAgeKeyContent(%q) = %v, want %v", tt.value, result, tt.expected)
			}
		})
	}
}
