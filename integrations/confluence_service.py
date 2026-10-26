import httpx
import base64

class ConfluenceService:
    def __init__(self, url: str, space_key: str, username: str, api_token: str):
        self.url = url.rstrip("/")
        self.space_key = space_key
        self.username = username
        self.api_token = api_token

    def _get_auth_headers(self):
        if not self.username or not self.api_token:
            return {}
        credentials = f"{self.username}:{self.api_token}"
        encoded = base64.b64encode(credentials.encode()).decode()
        return {
            "Authorization": f"Basic {encoded}",
            "Accept": "application/json",
            "Content-Type": "application/json"
        }

    async def get_page_content_by_title(self, title: str):
        """Fetches the existing content of a Confluence page by title."""
        endpoint = f"{self.url}/wiki/rest/api/content"
        params = {
            "spaceKey": self.space_key,
            "title": title,
            "expand": "body.storage,version"
        }
        
        async with httpx.AsyncClient(timeout=30.0) as client:
            resp = await client.get(endpoint, headers=self._get_auth_headers(), params=params)
            resp.raise_for_status()
            data = resp.json()
            
            if data.get("results") and len(data["results"]) > 0:
                page = data["results"][0]
                return {
                    "id": page["id"],
                    "version": page["version"]["number"],
                    "content": page["body"]["storage"]["value"]
                }
            return None

    async def update_page(self, page_id: str, title: str, content: str, version: int):
        """Updates an existing Confluence page."""
        endpoint = f"{self.url}/wiki/rest/api/content/{page_id}"
        
        payload = {
            "id": page_id,
            "type": "page",
            "title": title,
            "space": {"key": self.space_key},
            "body": {
                "storage": {
                    "value": content,
                    "representation": "storage"
                }
            },
            "version": {
                "number": version + 1
            }
        }
        
        async with httpx.AsyncClient(timeout=30.0) as client:
            resp = await client.put(endpoint, headers=self._get_auth_headers(), json=payload)
            resp.raise_for_status()
            return resp.json()
            
    async def create_page(self, title: str, content: str):
        """Creates a new Confluence page if it doesn't exist."""
        endpoint = f"{self.url}/wiki/rest/api/content"
        
        payload = {
            "type": "page",
            "title": title,
            "space": {"key": self.space_key},
            "body": {
                "storage": {
                    "value": content,
                    "representation": "storage"
                }
            }
        }
        
        async with httpx.AsyncClient(timeout=30.0) as client:
            resp = await client.post(endpoint, headers=self._get_auth_headers(), json=payload)
            resp.raise_for_status()
            return resp.json()
