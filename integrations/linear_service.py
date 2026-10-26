import httpx

class LinearService:
    def __init__(self, api_key: str):
        self.api_key = api_key
        self.endpoint = "https://api.linear.app/graphql"
        self.headers = {
            "Authorization": self.api_key,
            "Content-Type": "application/json"
        }

    def _query(self, query: str, variables: dict = None):
        payload = {"query": query}
        if variables:
            payload["variables"] = variables
        
        with httpx.Client() as client:
            resp = client.post(self.endpoint, headers=self.headers, json=payload)
            resp.raise_for_status()
            data = resp.json()
            if data and "errors" in data:
                raise Exception(f"Linear API error: {data['errors']}")
            return data

    def list_documents(self, workspace_id: str = None, search_all: bool = False):
        if search_all or not workspace_id:
            query = """
            query {
              documents(first: 50) {
                nodes {
                  id
                  title
                  updatedAt
                }
              }
            }
            """
            data = self._query(query)
            return data.get("data", {}).get("documents", {}).get("nodes", [])
            
        if workspace_id.startswith("team:"):
            team_id = workspace_id.replace("team:", "")
            query = """
            query($id: String!) {
              team(id: $id) {
                documents(first: 50) {
                  nodes { id title updatedAt }
                }
              }
            }
            """
            data = self._query(query, {"id": team_id})
            return data.get("data", {}).get("team", {}).get("documents", {}).get("nodes", [])
            
        if workspace_id.startswith("project:"):
            project_id = workspace_id.replace("project:", "")
            query = """
            query($id: String!) {
              project(id: $id) {
                documents(first: 50) {
                  nodes { id title updatedAt }
                }
              }
            }
            """
            data = self._query(query, {"id": project_id})
            return data.get("data", {}).get("project", {}).get("documents", {}).get("nodes", [])
            
        return []

    def get_document(self, doc_id: str):
        query = """
        query($id: String!) {
          document(id: $id) {
            id
            title
            content
          }
        }
        """
        data = self._query(query, {"id": doc_id})
        return data.get("data", {}).get("document")

    def update_document(self, doc_id: str, content: str):
        query = """
        mutation UpdateDocument($id: String!, $content: String!) {
          documentUpdate(id: $id, input: { content: $content }) {
            success
            document {
              id
              title
            }
          }
        }
        """
        data = self._query(query, {"id": doc_id, "content": content})
        return data.get("data", {}).get("documentUpdate", {})

    def list_workspaces(self):
        query = """
        query {
          teams {
            nodes {
              id
              name
            }
          }
          projects {
            nodes {
              id
              name
            }
          }
        }
        """
        data = self._query(query)
        teams = data.get("data", {}).get("teams", {}).get("nodes", [])
        projects = data.get("data", {}).get("projects", {}).get("nodes", [])
        return {"teams": teams, "projects": projects}

    def get_default_team_id(self):
        query = """
        query {
          teams(first: 1) {
            nodes {
              id
            }
          }
        }
        """
        data = self._query(query)
        teams = data.get("data", {}).get("teams", {}).get("nodes", [])
        return teams[0]["id"] if teams else None

    def create_document(self, title: str, content: str, project_id: str = None, team_id: str = None):
        query = """
        mutation CreateDocument($title: String!, $content: String!, $projectId: String, $teamId: String) {
          documentCreate(input: { title: $title, content: $content, projectId: $projectId, teamId: $teamId }) {
            success
            document {
              id
              title
            }
          }
        }
        """
        variables = {"title": title, "content": content}
        if project_id:
            variables["projectId"] = project_id
        if team_id:
            variables["teamId"] = team_id
            
        if not project_id and not team_id:
            default_team = self.get_default_team_id()
            if default_team:
                variables["teamId"] = default_team
            
        data = self._query(query, variables)
        return data.get("data", {}).get("documentCreate", {})
