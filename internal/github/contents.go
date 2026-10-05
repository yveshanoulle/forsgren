package github

import (
	"context"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"net/url"
	"strings"
)

// FileRef names a file of a repository at a commit or branch.
type FileRef struct {
	Ref  string
	Path string
}

// FileAt is the content of the file at.Path of repo as it is at at.Ref, a
// commit or a branch: GET /repos/{owner}/{repo}/contents/{path}?ref={ref},
// its base64 content decoded. A 404 is a file that is not there, found false,
// not an error; any other error answer is one.
func (c *Client) FileAt(ctx context.Context, repo string, at FileRef) (string, bool, error) {
	segments := append([]string{"contents"}, strings.Split(at.Path, "/")...)
	t, err := c.endpoint(repo, nil, segments...)
	if err != nil {
		return "", false, err
	}
	t.url.RawQuery = url.Values{"ref": {at.Ref}}.Encode()
	body, _, err := c.get(ctx, t, jsonMedia)
	if isNotFound(err) {
		return "", false, nil
	}
	if err != nil {
		return "", false, err
	}
	content, err := decodeContent(body)
	if err != nil {
		return "", false, fmt.Errorf("%s: %w for %s: %w", repo, ErrAnswer, t.path(), err)
	}
	return content, true, nil
}

// decodeContent is the content of a contents answer, whose base64 comes in
// lines.
func decodeContent(answer []byte) (string, error) {
	var file struct {
		Content string `json:"content"`
	}
	if err := json.Unmarshal(answer, &file); err != nil {
		return "", err
	}
	raw, err := base64.StdEncoding.DecodeString(strings.ReplaceAll(file.Content, "\n", ""))
	return string(raw), err
}
