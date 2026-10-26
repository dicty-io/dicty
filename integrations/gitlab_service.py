import os
import httpx
import urllib.parse

class GitLabService:
    def __init__(self, host: str = None, token: str = None, repo: str = None):
        self.host = host or os.getenv("GITLAB_HOST", "https://gitlab.com")
        self.token = token or os.getenv("GITLAB_TOKEN")
        self.repo = repo or os.getenv("GITLAB_REPO")
        
        # Ensure host doesn't end with a slash
        if self.host.endswith('/'):
            self.host = self.host[:-1]
            
        if self.repo in ["owner/repo-name", "owner/repo", ""] or (self.repo and "your-" in self.repo):
            self.repo = None
            
        # GitLab API uses URL-encoded path or project ID
        self.encoded_repo = urllib.parse.quote(self.repo, safe='') if self.repo else None
        self.branch = None
        self.headers = {}
        if self.token and not self.token.startswith("your-"):
            self.headers["PRIVATE-TOKEN"] = self.token
            
    async def get_recent_commits(self, limit: int = 1) -> list[str]:
        if not self.encoded_repo:
            return []
            
        url = f"{self.host}/api/v4/projects/{self.encoded_repo}/repository/commits?per_page={limit}"
        async with httpx.AsyncClient() as client:
            try:
                response = await client.get(url, headers=self.headers)
                response.raise_for_status()
                data = response.json()
                return [c["id"] for c in data]
            except Exception as e:
                print(f"[!] GitLab API Error fetching commits: {e}")
                return []

    async def get_commit_info(self, commit_hashes: list[str]) -> list[dict]:
        commits_data = []
        if not self.encoded_repo:
            return commits_data

        async with httpx.AsyncClient() as client:
            for ch in commit_hashes:
                url = f"{self.host}/api/v4/projects/{self.encoded_repo}/repository/commits/{ch}"
                diff_url = f"{self.host}/api/v4/projects/{self.encoded_repo}/repository/commits/{ch}/diff"
                try:
                    # Fetch commit metadata
                    response = await client.get(url, headers=self.headers)
                    response.raise_for_status()
                    data = response.json()
                    
                    # Fetch diffs
                    diff_response = await client.get(diff_url, headers=self.headers)
                    diff_response.raise_for_status()
                    diff_data = diff_response.json()
                    
                    diffs = []
                    for f in diff_data:
                        diffs.append({
                            "a_path": f.get("old_path", f.get("new_path")),
                            "b_path": f.get("new_path"),
                            "diff": f.get("diff", "")
                        })

                    commits_data.append({
                        "hexsha": data["id"],
                        "message": data["message"],
                        "author": data["author_name"],
                        "date": data["created_at"],
                        "diffs": diffs
                    })
                except Exception as e:
                    commits_data.append({
                        "hexsha": ch,
                        "error": f"Failed to retrieve commit from GitLab: {str(e)}"
                    })
        return commits_data

    async def get_pr_details(self, mr_number: int) -> dict:
        if not self.encoded_repo:
            return {"error": "Target GitLab repository is not configured."}
            
        url = f"{self.host}/api/v4/projects/{self.encoded_repo}/merge_requests/{mr_number}"
        async with httpx.AsyncClient() as client:
            try:
                response = await client.get(url, headers=self.headers)
                response.raise_for_status()
                data = response.json()
                return {
                    "number": mr_number,
                    "title": data.get("title"),
                    "description": data.get("description"),
                    "state": data.get("state"),
                    "html_url": data.get("web_url")
                }
            except Exception as e:
                return {"number": mr_number, "error": f"Failed to fetch MR: {str(e)}"}

    async def get_issue_details(self, issue_number: int) -> dict:
        if not self.encoded_repo:
            return {"error": "Target GitLab repository is not configured."}
            
        url = f"{self.host}/api/v4/projects/{self.encoded_repo}/issues/{issue_number}"
        async with httpx.AsyncClient() as client:
            try:
                response = await client.get(url, headers=self.headers)
                response.raise_for_status()
                data = response.json()
                return {
                    "number": issue_number,
                    "title": data.get("title"),
                    "body": data.get("description"),
                    "state": data.get("state"),
                    "labels": data.get("labels", []),
                    "html_url": data.get("web_url")
                }
            except Exception as e:
                return {"number": issue_number, "error": f"Failed to fetch issue: {str(e)}"}

    async def get_repo_tree(self) -> str:
        if not self.encoded_repo:
            return "Error: Target GitLab repository is not configured."
            
        url = f"{self.host}/api/v4/projects/{self.encoded_repo}"
        async with httpx.AsyncClient() as client:
            try:
                response = await client.get(url, headers=self.headers)
                response.raise_for_status()
                if self.branch:
                    target_branch = self.branch
                else:
                    target_branch = response.json().get("default_branch", "main")
                
                # Use recursive=true in GitLab API
                tree_url = f"{self.host}/api/v4/projects/{self.encoded_repo}/repository/tree?ref={target_branch}&recursive=true"
                tree_resp = await client.get(tree_url, headers=self.headers)
                tree_resp.raise_for_status()
                
                paths = []
                for item in tree_resp.json():
                    if item["type"] == "blob":
                        paths.append(item["path"])
                        
                return "\n".join(paths)
            except Exception as e:
                return f"Failed to fetch repo tree: {str(e)}"

    async def get_file_content(self, path: str) -> str:
        if not self.encoded_repo:
            return "Error: Target GitLab repository is not configured."
            
        encoded_path = urllib.parse.quote(path, safe='')
        url = f"{self.host}/api/v4/projects/{self.encoded_repo}/repository/files/{encoded_path}?ref={self.branch or 'HEAD'}"
        async with httpx.AsyncClient() as client:
            try:
                response = await client.get(url, headers=self.headers)
                response.raise_for_status()
                data = response.json()
                if "content" in data:
                    import base64
                    return base64.b64decode(data["content"]).decode('utf-8')
                return "Error: Empty or unreadable file."
            except Exception as e:
                return f"Failed to fetch file content: {str(e)}"
