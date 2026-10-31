package main

import (
	"encoding/json"
	"os"
	"path/filepath"
	"testing"

	"github.com/metacubex/bbolt"
	"github.com/metacubex/mihomo/component/profile/cachefile"
	"github.com/metacubex/mihomo/constant"
)

func TestHandleExportSmartData(t *testing.T) {
	dir := t.TempDir()
	constant.SetHomeDir(dir)

	cache := cachefile.Cache()
	if cache == nil || cache.DB == nil {
		t.Fatal("cache file not initialized")
	}
	err := cache.DB.Update(func(tx *bbolt.Tx) error {
		b, err := tx.CreateBucketIfNotExists([]byte("smart_stats"))
		if err != nil {
			return err
		}
		if err := b.Put(
			[]byte("smart/node/cfg1/SmartGroup/node-a"),
			[]byte(`{"success":10,"failure":1}`),
		); err != nil {
			return err
		}
		if err := b.Put(
			[]byte("smart/stats/cfg1/SmartGroup/example.com/node-a"),
			[]byte(`{"samples":42}`),
		); err != nil {
			return err
		}
		return b.Put(
			[]byte("smart/ranking/cfg1/SmartGroup"),
			[]byte(`["node-a","node-b"]`),
		)
	})
	if err != nil {
		t.Fatal(err)
	}

	var doc smartExportDocument
	if err := json.Unmarshal([]byte(handleExportSmartData()), &doc); err != nil {
		t.Fatalf("export is not valid JSON: %v", err)
	}
	if !doc.Available {
		t.Fatal("export reports available=false with a populated bucket")
	}
	if doc.TotalKeys != 3 {
		t.Fatalf("expected 3 keys, got %d", doc.TotalKeys)
	}
	if doc.Counts["node"] != 1 || doc.Counts["stats"] != 1 || doc.Counts["ranking"] != 1 {
		t.Fatalf("unexpected counts: %+v", doc.Counts)
	}

	var node *smartExportEntry
	for i := range doc.Entries {
		if doc.Entries[i].Type == "node" {
			node = &doc.Entries[i]
		}
	}
	if node == nil {
		t.Fatal("node entry missing")
	}
	if node.Config != "cfg1" || node.Group != "SmartGroup" || node.Node != "node-a" {
		t.Fatalf("node entry parsed wrong: %+v", node)
	}
	var value map[string]int
	if err := json.Unmarshal(node.Value, &value); err != nil || value["success"] != 10 {
		t.Fatalf("node value did not round-trip: %s", node.Value)
	}

	if _, err := os.Stat(filepath.Join(dir, "cache.db")); err != nil {
		t.Fatalf("cache.db not where expected: %v", err)
	}
}
