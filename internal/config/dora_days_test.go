package config

import "testing"

// TestDoraDaysDefaultsTo30AndReadsEachAllowedValue (forsgren#178): the
// optional top-level dora_days key is 30, 90 or 180; 30 when the key is left
// out or written without a value.
func TestDoraDaysDefaultsTo30AndReadsEachAllowedValue(t *testing.T) {
	cases := []struct {
		name string
		yaml string
		want int
	}{
		{"absent", valid, DefaultDoraDays},
		{"no value", "dora_days:\n" + valid, DefaultDoraDays},
		{"thirty", "dora_days: 30\n" + valid, 30},
		{"ninety", "dora_days: 90\n" + valid, 90},
		{"one hundred eighty", "dora_days: 180\n" + valid, 180},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			got, err := parse([]byte(tc.yaml))
			if err != nil || got.DoraDays != tc.want {
				t.Errorf("want dora_days %d and no error, got %d, %v", tc.want, got.DoraDays, err)
			}
		})
	}
}

// TestDoraDaysRefusesAnythingElse (forsgren#178): any other value is refused
// with ErrDoraDays and the message names the key and the three values.
func TestDoraDaysRefusesAnythingElse(t *testing.T) {
	for name, value := range map[string]string{
		"sixty": "60", "zero": "0", "negative": "-30", "a year": "365", "fraction": "30.5",
		"float": "90.0", "quoted": `"90"`, "word": "ninety",
	} {
		t.Run(name, func(t *testing.T) {
			_, err := parse([]byte("dora_days: " + value + "\n" + valid))
			wantRefusal(t, err, ErrDoraDays, "invalid dora_days", "use 30, 90 or 180")
		})
	}
}
