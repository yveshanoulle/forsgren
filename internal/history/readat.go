package history

// LoadReadAt reads data/failures_read.csv at path: per repository, when its
// failure issues were last read (forsgren#67). Stub: returns nothing.
func LoadReadAt(_ string) (Reach, error) { return Reach{}, nil }

// SaveReadAt writes r to path whole, in the failures read format v1.
// Stub: writes nothing.
func SaveReadAt(_ string, _ Reach) error { return nil }
