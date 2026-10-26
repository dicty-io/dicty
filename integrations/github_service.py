import os
import httpx

class GitHubService:
    def __init__(self, token: str = None, repo: str = None):
        self.token = token or os.getenv("GITHUB_TOKEN")
        self.repo = repo or os.getenv("GITHUB_REPO")  # Format: owner/repo
        if self.repo in ["owner/repo-name", "owner/repo", ""] or (self.repo and "your-" in self.repo):
            self.repo = None
        self.branch = None
        self.headers = {}
        if self.token and not self.token.startswith("your-"):
            clean = self.token.strip().strip('"').strip("'").strip()
            if clean.startswith("Bearer ") or clean.startswith("bearer "):
                clean = clean[7:].strip()
            elif clean.startswith("token ") or clean.startswith("Token "):
                clean = clean[6:].strip()
            if clean.startswith("github_pat_"):
                self.headers["Authorization"] = f"Bearer {clean}"
            else:
                self.headers["Authorization"] = f"token {clean}"
        self.headers["Accept"] = "application/vnd.github.v3+json"

    async def get_recent_commits(self, limit: int = 1) -> list[str]:
        if not self.repo:
            return []
        
        url = f"https://api.github.com/repos/{self.repo}/commits?per_page={limit}"
        async with httpx.AsyncClient() as client:
            try:
                response = await client.get(url, headers=self.headers)
                response.raise_for_status()
                data = response.json()
                return [c["sha"] for c in data]
            except Exception as e:
                print(f"[!] GitHub API Error fetching commits: {e}")
                return []

    async def get_commit_info(self, commit_hashes: list[str]) -> list[dict]:
        commits_data = []
        if not self.repo:
            return commits_data

        async with httpx.AsyncClient() as client:
            for ch in commit_hashes:
                url = f"https://api.github.com/repos/{self.repo}/commits/{ch}"
                try:
                    response = await client.get(url, headers=self.headers)
                    response.raise_for_status()
                    data = response.json()
                    
                    diffs = []
                    for f in data.get("files", []):
                        diffs.append({
                            "a_path": f.get("previous_filename", f.get("filename")),
                            "b_path": f.get("filename"),
                            "diff": f.get("patch", "")
                        })

                    commits_data.append({
                        "hexsha": data["sha"],
                        "message": data["commit"]["message"],
                        "author": data["commit"]["author"]["name"],
                        "date": data["commit"]["author"]["date"],
                        "diffs": diffs
                    })
                except Exception as e:
                    commits_data.append({
                        "hexsha": ch,
                        "error": f"Failed to retrieve commit from GitHub: {str(e)}"
                    })
        return commits_data

    async def get_pr_details(self, pr_number: int) -> dict:
        if not self.repo:
            return {"error": "Target GitHub repository is not configured."}
        
        url = f"https://api.github.com/repos/{self.repo}/pulls/{pr_number}"
        async with httpx.AsyncClient() as client:
            try:
                response = await client.get(url, headers=self.headers)
                response.raise_for_status()
                data = response.json()
                return {
                    "number": pr_number,
                    "title": data.get("title"),
                    "description": data.get("body"),
                    "state": data.get("state"),
                    "html_url": data.get("html_url")
                }
            except Exception as e:
                return {"number": pr_number, "error": f"Failed to fetch PR: {str(e)}"}

    async def get_issue_details(self, issue_number: int) -> dict:
        if not self.repo:
            return {"error": "Target GitHub repository is not configured."}
        
        url = f"https://api.github.com/repos/{self.repo}/issues/{issue_number}"
        async with httpx.AsyncClient() as client:
            try:
                response = await client.get(url, headers=self.headers)
                response.raise_for_status()
                data = response.json()
                return {
                    "number": issue_number,
                    "title": data.get("title"),
                    "body": data.get("body"),
                    "state": data.get("state"),
                    "labels": [l.get("name") for l in data.get("labels", [])],
                    "html_url": data.get("html_url")
                }
            except Exception as e:
                return {"number": issue_number, "error": f"Failed to fetch issue: {str(e)}"}

    async def get_repo_tree(self) -> str:
        url = f"https://api.github.com/repos/{self.repo}" if self.repo else None
        if url:
            async with httpx.AsyncClient() as client:
                try:
                    response = await client.get(url, headers=self.headers)
                    response.raise_for_status()
                    target_branch = self.branch or response.json().get("default_branch", "main")
                    
                    tree_url = f"https://api.github.com/repos/{self.repo}/git/trees/{target_branch}?recursive=1"
                    tree_resp = await client.get(tree_url, headers=self.headers)
                    tree_resp.raise_for_status()
                    
                    paths = [item["path"] for item in tree_resp.json().get("tree", []) if item["type"] == "blob"]
                    if paths:
                        return "\n".join(paths)
                except Exception as e:
                    print(f"[!] GitHub API tree failed ({e}), falling back to local files...")
                    
        # Fallback to local git repository files
        try:
            import subprocess
            res = subprocess.run(["git", "ls-files"], capture_output=True, text=True, timeout=3)
            if res.returncode == 0 and res.stdout.strip():
                return res.stdout.strip()
        except Exception:
            pass
            
        return "Error: Could not retrieve repository file tree."

    async def get_file_content(self, path: str) -> str:
        # 1. Try reading local file directly if available
        clean_path = path.lstrip("/")
        if os.path.exists(clean_path) and os.path.isfile(clean_path):
            try:
                with open(clean_path, "r", encoding="utf-8", errors="ignore") as f:
                    return f.read()
            except Exception:
                pass
                
        # 2. Try GitHub API
        if not self.repo:
            return f"Error: File '{path}' not found locally and no remote GitHub repo is configured."
            
        url = f"https://api.github.com/repos/{self.repo}/contents/{path}"
        if self.branch:
            url += f"?ref={self.branch}"
        async with httpx.AsyncClient() as client:
            try:
                response = await client.get(url, headers=self.headers)
                response.raise_for_status()
                data = response.json()
                if "content" in data:
                    import base64
                    return base64.b64decode(data["content"]).decode('utf-8')
                elif type(data) == list:
                    return f"Error: Path '{path}' is a directory, not a file."
                return "Error: Empty or unreadable file."
            except Exception as e:
                return f"Failed to fetch file content: {str(e)}"
