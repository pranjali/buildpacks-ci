package main

import (
	"fmt"
	"sort"
	"strings"
)

func GenerateCommitMessage(oldDeps, newDeps []Dependency, depID, depVersion string, storyID int) string {
	added := false
	rebuilt := false
	stacks := map[string]bool{}
	removedDeps := map[string]bool{}

	for _, dep := range newDeps {
		if dep.ID != depID || dep.Version != depVersion {
			continue
		}

		oldDep, exists := findDependency(oldDeps, dep)
		if exists {
			if oldDep.Sha256 != dep.Sha256 || oldDep.URI != dep.URI {
				rebuilt = true
				stacks[dep.Stacks[0]] = true
			}
		} else {
			added = true
			stacks[dep.Stacks[0]] = true
		}
	}

	for _, dep := range oldDeps {
		if dep.ID != depID {
			continue
		}

		if !containsDependency(newDeps, dep) {
			removedDeps[depID+" "+dep.Version] = true
			stacks[dep.Stacks[0]] = true
		}
	}

	if !added && !rebuilt && len(removedDeps) == 0 {
		return ""
	}

	var commitMessage string
	if added {
		commitMessage = fmt.Sprintf("Add %s %s", depID, depVersion)
	} else {
		commitMessage = fmt.Sprintf("Rebuild %s %s", depID, depVersion)
	}

	if len(removedDeps) > 0 {
		commitMessage += fmt.Sprintf(", remove %s", joinMap(removedDeps))
	}

	commitMessage += fmt.Sprintf("\n\nfor stack(s) %s [#%d]", joinMap(stacks), storyID)

	return commitMessage
}

func containsDependency(deps []Dependency, dep Dependency) bool {
	_, exists := findDependency(deps, dep)
	return exists
}

func findDependency(deps []Dependency, dep Dependency) (Dependency, bool) {
	for _, d := range deps {
		if d.ID == dep.ID && d.Version == dep.Version && d.Stacks[0] == dep.Stacks[0] {
			return d, true
		}
	}
	return Dependency{}, false
}

func joinMap(m map[string]bool) string {
	var a []string
	for s := range m {
		a = append(a, s)
	}
	sort.Strings(a)
	return strings.Join(a, ", ")
}
