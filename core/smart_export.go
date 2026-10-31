package main

import (
	"encoding/json"
	"sort"
	"strings"
	"time"

	"github.com/metacubex/bbolt"
	"github.com/metacubex/mihomo/component/profile/cachefile"
)

// Bettbox-SmartCore: export of the Smart policy groups' learning data.
//
// The Smart implementation persists what it learns about proxies (node
// states, per-target statistics, rankings, host failures, prefetch
// results) in the "smart_stats" bucket of the kernel cache database
// (cache.db in the core home directory). That directory is private to
// the app sandbox, so users cannot inspect the data directly; this
// handler dumps the bucket as one JSON document for the UI to save.
//
// The dump is read-only and best-effort: it reflects the last flushed
// state. Operations still sitting in the store's in-memory batch queue
// are not included. On a core without the Smart patch (or before the
// first Smart group ran) the bucket simply does not exist and the
// document reports available=false.

type smartExportEntry struct {
	Key    string          `json:"key"`
	Type   string          `json:"type,omitempty"`
	Config string          `json:"config,omitempty"`
	Group  string          `json:"group,omitempty"`
	Target string          `json:"target,omitempty"`
	Node   string          `json:"node,omitempty"`
	Value  json.RawMessage `json:"value"`
}

type smartExportDocument struct {
	Kind       string             `json:"kind"`
	Version    int                `json:"version"`
	ExportedAt string             `json:"exportedAt"`
	Available  bool               `json:"available"`
	TotalKeys  int                `json:"totalKeys"`
	Counts     map[string]int     `json:"counts"`
	Entries    []smartExportEntry `json:"entries"`
}

var smartStatsBucket = []byte("smart_stats")

func handleExportSmartData() string {
	doc := smartExportDocument{
		Kind:       "bettbox-smart-learning-data",
		Version:    1,
		ExportedAt: time.Now().Format(time.RFC3339),
		Counts:     map[string]int{},
		Entries:    []smartExportEntry{},
	}

	cache := cachefile.Cache()
	if cache == nil || cache.DB == nil {
		return marshalSmartExport(doc)
	}

	_ = cache.DB.View(func(tx *bbolt.Tx) error {
		bucket := tx.Bucket(smartStatsBucket)
		if bucket == nil {
			return nil
		}
		doc.Available = true
		return bucket.ForEach(func(k, v []byte) error {
			entry := parseSmartExportEntry(string(k), v)
			doc.Entries = append(doc.Entries, entry)
			doc.Counts[entry.Type]++
			return nil
		})
	})
	doc.TotalKeys = len(doc.Entries)
	sort.Slice(doc.Entries, func(i, j int) bool {
		return doc.Entries[i].Key < doc.Entries[j].Key
	})
	return marshalSmartExport(doc)
}

func marshalSmartExport(doc smartExportDocument) string {
	data, err := json.Marshal(doc)
	if err != nil {
		return `{"kind":"bettbox-smart-learning-data","version":1,"available":false,"entries":[]}`
	}
	return string(data)
}

// parseSmartExportEntry splits a store key of the form
// "smart/<type>/<config>/<group>[/<target>[/<node>]]" into its fields.
// Names may themselves contain "/", so surplus segments are folded
// back into the last field; the verbatim key is always kept.
func parseSmartExportEntry(key string, value []byte) smartExportEntry {
	entry := smartExportEntry{Key: key}
	if json.Valid(value) {
		entry.Value = json.RawMessage(value)
	} else {
		quoted, _ := json.Marshal(string(value))
		entry.Value = quoted
	}

	parts := strings.Split(key, "/")
	if len(parts) < 2 || parts[0] != "smart" {
		return entry
	}
	entry.Type = parts[1]
	rest := parts[2:]
	if len(rest) > 0 {
		entry.Config = rest[0]
	}
	if len(rest) > 1 {
		entry.Group = rest[1]
	}
	tail := rest[2:]
	switch entry.Type {
	case "node": // smart/node/<config>/<group>/<node>
		entry.Node = strings.Join(tail, "/")
	case "stats": // smart/stats/<config>/<group>/<target>/<node>
		if len(tail) > 0 {
			entry.Target = tail[0]
		}
		if len(tail) > 1 {
			entry.Node = strings.Join(tail[1:], "/")
		}
	case "prefetch", "failures": // smart/<type>/<config>/<group>/<target>
		entry.Target = strings.Join(tail, "/")
	}
	return entry
}
