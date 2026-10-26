import os
import httpx
import urllib.parse

class BitbucketService:
    def __init__(self, token: str = None, repo: str = None):
        """
        Bitbucket Cloud API 2.0 Client.
        token: Access Token (Repository, Workspace, or User token) or App Password
        repo: Repository identifier in 'workspace/repo-slug' format (e.g. 'vkazmin/test-repo-1')
        """
        self.token = token or os.getenv("BITBUCKET_TOKEN")
        self.repo = repo or os.getenv("BITBUCKET_REPO")
        self.base_url = "https://api.bitbucket.org/2.0"
        
        if self.repo in ["owner/repo-name", "owner/repo", ""] or (self.repo and "your-" in self.repo):
            self.repo = None
            
        self.branch = None
        self.headers = {
            "Accept": "application/json"
        }
        if self.token and not self.token.startswith("your-"):
            # Bitbucket Access Tokens use Bearer auth
            if ":" in self.token:
                # In case user provided username:app_password
                import base64
                encoded = base64.b64encode(self.token.encode()).decode()
                self.headers["Authorization"] = f"Basic {encoded}"
            else:
                self.headers["Authorization"] = f"Bearer {self.token}"

    async def get_recent_commits(self, limit: int = 1) -> list[str]:
        if not self.repo:
            return []
            
        url = f"{self.base_url}/repositories/{self.repo}/commits?pagelen={limit}"
        if self.branch:
            url += f"&include={self.branch}"
            
        async with httpx.AsyncClient() as client:
            try:
                response = await client.get(url, headers=self.headers)
                response.raise_for_status()
                data = response.json()
                values = data.get("values", [])
                return [c["hash"] for c in values]
            except Exception as e:
                print(f"[!] Bitbucket API Error fetching commits: {e}")
                return []

    async def get_commit_info(self, commit_hashes: list[str]) -> list[dict]:
        commits_data = []
        if not self.repo:
            return commits_data

        async with httpx.AsyncClient() as client:
            for ch in commit_hashes:
                url = f"{self.base_url}/repositories/{self.repo}/commit/{ch}"
                diff_url = f"{self.base_url}/repositories/{self.repo}/diff/{ch}"
                try:
                    response = await client.get(url, headers=self.headers)
                    response.raise_for_status()
                    data = response.json()
                    
                    diff_response = await client.get(diff_url, headers=self.headers)
                    diff_text = diff_response.text if diff_response.status_code == 200 else ""
                    
                    author = data.get("author", {})
                    author_name = author.get("raw", "") if isinstance(author, dict) else str(author)
                    
                    diffs = []
                    if diff_text:
                        diffs.append({
                            "a_path": "commit_diff",
                            "b_path": "commit_diff",
                            "diff": diff_text
                        })

                    commits_data.append({
                        "hexsha": data.get("hash", ch),
                        "message": data.get("message", ""),
                        "author": author_name,
                        "date": data.get("date", ""),
                        "diffs": diffs
                    })
                except Exception as e:
                    commits_data.append({
                        "hexsha": ch,
                        "error": f"Failed to retrieve commit from Bitbucket: {str(e)}"
                    })
        return commits_data

    async def get_pr_details(self, pr_number: int) -> dict:
        if not self.repo:
            return {"error": "Target Bitbucket repository is not configured."}
            
        url = f"{self.base_url}/repositories/{self.repo}/pullrequests/{pr_number}"
        async with httpx.AsyncClient() as client:
            try:
                response = await client.get(url, headers=self.headers)
                response.raise_for_status()
                data = response.json()
                return {
                    "number": pr_number,
                    "title": data.get("title"),
                    "description": data.get("description") or (data.get("summary", {}).get("raw", "") if isinstance(data.get("summary"), dict) else ""),
                    "state": data.get("state"),
                    "html_url": data.get("links", {}).get("html", {}).get("href", "")
                }
            except Exception as e:
                return {"number": pr_number, "error": f"Failed to fetch PR: {str(e)}"}

    async def get_repo_tree(self) -> str:
        """
        Recursively fetches the repository file paths.
        """
        if not self.repo:
            return "Error: Target Bitbucket repository is not configured."
            
        target_ref = self.branch or "main"
        
        paths = []
        async with httpx.AsyncClient(timeout=30.0) as client:
            try:
                # Helper to traverse directory nodes
                async def fetch_dir(dir_path: str = ""):
                    url = f"{self.base_url}/repositories/{self.repo}/src/{target_ref}/{dir_path}?pagelen=100"
                    resp = await client.get(url, headers=self.headers)
                    if resp.status_code == 404 and target_ref == "main":
                        # Try 'master' if 'main' returns 404
                        fallback_url = f"{self.base_url}/repositories/{self.repo}/src/master/{dir_path}?pagelen=100"
                        resp = await client.get(fallback_url, headers=self.headers)
                    resp.raise_for_status()
                    data = resp.json()
                    
                    subdirs = []
                    for item in data.get("values", []):
                        item_type = item.get("type")
                        item_path = item.get("path")
                        if item_type == "commit_file":
                            paths.append(item_path)
                        elif item_type == "commit_directory":
                            subdirs.append(item_path)
                            
                    for sd in subdirs[:15]: # Limit recursion depth to avoid rate limits
                        await fetch_dir(sd)

                await fetch_dir("")
                if not paths:
                    return "README.md"
                return "\n".join(paths)
            except Exception as e:
                return f"Failed to fetch repo tree: {str(e)}"

    async def get_file_content(self, path: str) -> str:
        if not self.repo:
            return "Error: Target Bitbucket repository is not configured."
            
        target_ref = self.branch or "main"
        encoded_path = urllib.parse.quote(path)
        url = f"{self.base_url}/repositories/{self.repo}/src/{target_ref}/{encoded_path}"
        async with httpx.AsyncClient(timeout=20.0) as client:
            try:
                response = await client.get(url, headers=self.headers)
                if response.status_code == 404 and target_ref == "main":
                    fallback_url = f"{self.base_url}/repositories/{self.repo}/src/master/{encoded_path}"
                    response = await client.get(fallback_url, headers=self.headers)
                response.raise_for_status()
                return response.text
            except Exception as e:
                return f"Failed to fetch file content: {str(e)}"
